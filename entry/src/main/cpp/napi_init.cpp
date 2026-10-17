/*
 * The native side of the VPN port.
 *
 * WHY THIS EXISTS
 * ---------------
 * `VpnExtensionAbility` gives the app a TUN file descriptor, but a Clash core
 * is native code: on Android, mihomo is built with gomobile and reads that
 * descriptor from C/Go through JNI. The equivalent boundary here is
 * ArkTS -> NAPI -> native. If native code can take the descriptor and talk to
 * the interface, then a mihomo build (or any TUN pump) can be dropped behind
 * the same call and nothing else in the app has to change.
 *
 * That mihomo build now exists (`libclash.so`, see `CMakeLists.txt`), so this
 * module is the whole native surface the app uses:
 *
 *   tunAttach(fd)                          diagnostic only, `DescribeTunFd`
 *   corePrepare(home, profileDir, version) start the core without a TUN
 *   coreSetAgeSecretKey(ageSecretKey)      set the age identity before prepare
 *   coreAttach(fd, stack, gateway, ...)    hand the TUN to the core
 *   coreStop()                             tear the data plane down
 *   ageGenX25519() / ageGenHybrid()        age identity generation
 *   ageToPublicKeys(keys)                  derive public keys
 *   ageVerifySecretKeys / PublicKeys       validate what the user typed
 *
 * The `age*` group exists for the Meta-feature settings screen. Android reads
 * those five operations straight out of the core (`Clash.genX25519KeyPair` and
 * friends); the hybrid MLKEM768-X25519 pair is a core-only primitive, so they
 * are forwarded to the same Go functions rather than reimplemented here.
 *
 * The `age*` entry points are pure crypto and carry no core state, so the UI
 * process may call them without the VPN running. `core*` is the opposite: it
 * is single-shot, `corePrepare` -> `coreAttach` -> `coreStop`.
 *
 * WHAT IT CHECKS
 * --------------
 *   1. `fcntl(fd, F_GETFL)`      -- is the descriptor real and open?
 *   2. `ioctl(fd, TUNGETIFF)`    -- is it actually a TUN device, and what is
 *                                   its name? This is the Linux ioctl a TUN
 *                                   pump uses; if it succeeds the descriptor
 *                                   is a TUN, not some other fd.
 *   3. `read(fd, ...)`           -- can we read packets from it? With no route
 *                                   pointing at the interface there is nothing
 *                                   queued, so `EAGAIN` on a non-blocking read
 *                                   is the expected, healthy answer.
 *
 * It does not touch routes or DNS, and it restores the original descriptor
 * flags before returning.
 */

#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <condition_variable>
#include <mutex>
#include <set>
#include <string>

#include <fcntl.h>
#include <linux/if.h>
#include <linux/if_tun.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include "napi/native_api.h"

extern "C" char* ohos_core_prepare(char* home, char* profileDir, char* version);
extern "C" void ohos_core_set_age_secret_key(char* secretKey);
extern "C" char* ohos_core_attach(int fd, char* stack, char* gateway, char* portal, char* dns);
extern "C" void ohos_core_stop(void);
extern "C" char* ohos_age_gen_x25519(void);
extern "C" char* ohos_age_gen_hybrid(void);
extern "C" int ohos_age_verify_secret_keys(char* secretKeys);
extern "C" char* ohos_age_to_public_keys(char* secretKeys);
extern "C" int ohos_age_verify_public_keys(char* publicKeys);
extern "C" void ohos_core_set_mark_socket(void* callback);

static napi_threadsafe_function g_mark_socket_tsfn = nullptr;
static std::mutex g_mark_socket_mutex;
static std::condition_variable g_mark_socket_cv;
static std::set<int> g_mark_socket_pending;

/**
 * Called on the ArkTS thread by the NAPI threadsafe function. The Go dialer
 * hook is synchronous, so the actual `protect()` call is fire-and-forget; the
 * process-wide `protectProcessNet()` remains the primary protection and this
 * covers sockets that were created before it or by raw Go syscalls.
 */
static void MarkSocketCallJs(napi_env env, napi_value js_callback, void* context, void* data) {
    (void)context;
    if (env == nullptr || js_callback == nullptr) {
        return;
    }
    const int fd = static_cast<int>(reinterpret_cast<intptr_t>(data));
    napi_value argument = nullptr;
    napi_create_int32(env, fd, &argument);
    napi_value result = nullptr;
    napi_call_function(env, nullptr, js_callback, 1, &argument, &result);
}

/** Called from Go on a Go runtime thread; marshal the fd to the ArkTS thread. */
extern "C" void MarkSocketFromGo(int fd) {
    if (g_mark_socket_tsfn == nullptr) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(g_mark_socket_mutex);
        g_mark_socket_pending.insert(fd);
    }
    napi_call_threadsafe_function(
        g_mark_socket_tsfn,
        reinterpret_cast<void*>(static_cast<intptr_t>(fd)),
        napi_tsfn_nonblocking);
    std::unique_lock<std::mutex> lock(g_mark_socket_mutex);
    g_mark_socket_cv.wait_for(lock, std::chrono::milliseconds(2000), [fd] {
        return g_mark_socket_pending.find(fd) == g_mark_socket_pending.end();
    });
    g_mark_socket_pending.erase(fd);
}

namespace {

/** Human-readable errno, so the log line says `EAGAIN` instead of `11`. */
std::string ErrnoText(int value) {
    return std::string(std::strerror(value)) + " (errno " + std::to_string(value) + ")";
}

/**
 * Probe `fd` and describe what it is. The returned string is what ends up in
 * hilog, so it is written to be read by a human.
 */
std::string DescribeTunFd(int fd) {
    std::string report = "fd=" + std::to_string(fd);

    // 1. Is the descriptor open at all?
    const int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) {
        report += " | fcntl(F_GETFL) failed: " + ErrnoText(errno);
        return report;
    }
    report += " | open, flags=0x" + std::to_string(flags);

    // 2. Is it a TUN? TUNGETIFF is the ioctl that answers this.
    struct ifreq request;
    std::memset(&request, 0, sizeof(request));
    if (ioctl(fd, TUNGETIFF, &request) == 0) {
        report += " | TUNGETIFF ok: name=" + std::string(request.ifr_name);
        report += ", ifr_flags=0x" + std::to_string(request.ifr_flags);
    } else {
        report += " | TUNGETIFF failed: " + ErrnoText(errno);
    }

    // 3. Can we read from it? Nothing is routed here, so EAGAIN is expected.
    if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0) {
        unsigned char buffer[2048];
        const ssize_t read = ::read(fd, buffer, sizeof(buffer));
        if (read > 0) {
            report += " | read " + std::to_string(read) + " bytes";
        } else if (read == 0) {
            report += " | read returned EOF";
        } else {
            report += " | read: " + ErrnoText(errno);
        }
        fcntl(fd, F_SETFL, flags);
    } else {
        report += " | fcntl(F_SETFL, O_NONBLOCK) failed: " + ErrnoText(errno);
    }

    return report;
}

std::string GetString(napi_env env, napi_value value) {
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return {};
    }
    std::string result(length + 1, '\0');
    size_t written = 0;
    napi_get_value_string_utf8(env, value, result.data(), length + 1, &written);
    result.resize(written);
    return result;
}

/**
 * Copy a `char*` that came back from Go into a JS string and release it.
 *
 * Every `char*` export on the Go side is allocated with `C.CString`, i.e.
 * `malloc`, so the C side owns the free. A `nullptr` (the Go side had nothing
 * to say) becomes an empty string rather than `undefined`, so the ArkTS side
 * has one type to deal with.
 */
napi_value TakeCString(napi_env env, char* value) {
    std::string text = value == nullptr ? std::string() : std::string(value);
    if (value != nullptr) {
        std::free(value);
    }

    napi_value result = nullptr;
    napi_create_string_utf8(env, text.c_str(), text.size(), &result);
    return result;
}

/** Read `argv[0]` as a string; the caller has already checked the arity. */
char* ArgAsCString(napi_env env, napi_value value, std::string& storage) {
    storage = GetString(env, value);
    return const_cast<char*>(storage.c_str());
}

/** `corePrepare(home, profileDir, version): string` */
napi_value CorePrepare(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value argv[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 3) {
        napi_throw_type_error(env, nullptr, "corePrepare expects (home, profileDir, version)");
        return nullptr;
    }

    std::string home = GetString(env, argv[0]);
    std::string profileDir = GetString(env, argv[1]);
    std::string version = GetString(env, argv[2]);

    char* error = ohos_core_prepare(
        const_cast<char*>(home.c_str()),
        const_cast<char*>(profileDir.c_str()),
        const_cast<char*>(version.c_str()));
    std::string message = error == nullptr ? "native core returned no result" : error;
    if (error != nullptr) {
        std::free(error);
    }

    napi_value result = nullptr;
    napi_create_string_utf8(env, message.c_str(), message.size(), &result);
    return result;
}

/**
 * `coreSetAgeSecretKey(secretKey): void`
 *
 * Install the active profile's age identity before `corePrepare` reads
 * `config.yaml`. A blank key clears the core's global identity list, which
 * keeps an unencrypted profile from inheriting the previous profile's key.
 */
napi_value CoreSetAgeSecretKey(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 1) {
        napi_throw_type_error(env, nullptr, "coreSetAgeSecretKey expects (ageSecretKey)");
        return nullptr;
    }

    std::string secretKey;
    ohos_core_set_age_secret_key(ArgAsCString(env, argv[0], secretKey));

    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

/**
 * `coreAttach(fd, stack, gateway, portal, dns): string`
 *
 * `stack` / `gateway` / `portal` / `dns` are the four knobs Android's
 * `TunService` reads out of `NetworkSettingsStore`. The network-settings rows
 * that own them used to have nowhere to land because the Go side hard-coded
 * the values; passing them through is what makes those rows real.
 */
napi_value CoreAttach(napi_env env, napi_callback_info info) {
    size_t argc = 5;
    napi_value argv[5] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 5) {
        napi_throw_type_error(env, nullptr,
            "coreAttach expects (fd, stack, gateway, portal, dns)");
        return nullptr;
    }

    int32_t fd = -1;
    if (napi_get_value_int32(env, argv[0], &fd) != napi_ok) {
        napi_throw_type_error(env, nullptr, "coreAttach fd must be a number");
        return nullptr;
    }

    std::string stack = GetString(env, argv[1]);
    std::string gateway = GetString(env, argv[2]);
    std::string portal = GetString(env, argv[3]);
    std::string dns = GetString(env, argv[4]);

    char* error = ohos_core_attach(
        static_cast<int>(fd),
        const_cast<char*>(stack.c_str()),
        const_cast<char*>(gateway.c_str()),
        const_cast<char*>(portal.c_str()),
        const_cast<char*>(dns.c_str()));
    std::string message = error == nullptr ? "native core returned no result" : error;
    if (error != nullptr) {
        std::free(error);
    }

    napi_value result = nullptr;
    napi_create_string_utf8(env, message.c_str(), message.size(), &result);
    return result;
}

/** `coreStop(): void` */
napi_value CoreStop(napi_env env, napi_callback_info info) {
    (void)env;
    (void)info;
    if (g_mark_socket_tsfn != nullptr) {
        napi_release_threadsafe_function(g_mark_socket_tsfn, napi_tsfn_release);
        g_mark_socket_tsfn = nullptr;
    }
    ohos_core_stop();
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

/**
 * `coreSetMarkSocket(callback): void`
 *
 * Register the ArkTS per-socket protector. Go calls back through
 * `MarkSocketFromGo` for every socket created by the core dialer.
 */
napi_value CoreSetMarkSocket(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 1) {
        napi_throw_type_error(env, nullptr, "coreSetMarkSocket expects (callback)");
        return nullptr;
    }

    if (g_mark_socket_tsfn != nullptr) {
        napi_release_threadsafe_function(g_mark_socket_tsfn, napi_tsfn_release);
        g_mark_socket_tsfn = nullptr;
    }

    napi_value resource_name = nullptr;
    napi_create_string_utf8(env, "clashMarkSocket", NAPI_AUTO_LENGTH, &resource_name);
    napi_status status = napi_create_threadsafe_function(
        env,
        argv[0],
        nullptr,
        resource_name,
        0,
        1,
        nullptr,
        nullptr,
        nullptr,
        MarkSocketCallJs,
        &g_mark_socket_tsfn);
    if (status != napi_ok) {
        napi_throw_error(env, nullptr, "failed to create mark-socket callback");
        return nullptr;
    }

    ohos_core_set_mark_socket(reinterpret_cast<void*>(&MarkSocketFromGo));

    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

/**
 * `coreMarkSocketDone(fd): void`
 *
 * ArkTS calls this once `VpnConnection.protect(fd)` settles. It releases the
 * Go dialer hook that is waiting in `MarkSocketFromGo`.
 */
napi_value CoreMarkSocketDone(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t fd = -1;
    if (argc < 1 || napi_get_value_int32(env, argv[0], &fd) != napi_ok) {
        napi_throw_type_error(env, nullptr, "coreMarkSocketDone expects (fd)");
        return nullptr;
    }
    {
        std::lock_guard<std::mutex> lock(g_mark_socket_mutex);
        g_mark_socket_pending.erase(static_cast<int>(fd));
    }
    g_mark_socket_cv.notify_all();
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

/**
 * `ageGenX25519(): string` and `ageGenHybrid(): string` -- the two key types
 * the Age-key dialog offers. Both return the same JSON envelope:
 *
 *   {"ok":true,"secretKey":"AGE-SECRET-KEY-1...","publicKey":"age1..."}
 *   {"ok":false,"error":"..."}
 */
napi_value AgeGenX25519(napi_env env, napi_callback_info info) {
    (void)info;
    return TakeCString(env, ohos_age_gen_x25519());
}

napi_value AgeGenHybrid(napi_env env, napi_callback_info info) {
    (void)info;
    return TakeCString(env, ohos_age_gen_hybrid());
}

/**
 * `ageToPublicKeys(keys): string` -- derive the public key of each identity in
 * a newline-separated list. Envelope, with the public keys in input order:
 *
 *   {"ok":true,"publicKeys":["age1..."]}
 *   {"ok":false,"error":"..."}
 */
napi_value AgeToPublicKeys(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 1) {
        napi_throw_type_error(env, nullptr, "ageToPublicKeys expects (keys)");
        return nullptr;
    }

    std::string keys;
    return TakeCString(env, ohos_age_to_public_keys(ArgAsCString(env, argv[0], keys)));
}

/**
 * `ageVerifySecretKeys(keys): boolean` / `ageVerifyPublicKeys(keys): boolean`
 * -- the two inline validators the dialog runs on every keystroke, so a bad
 * key is marked before the user leaves the field.
 */
napi_value AgeVerifySecretKeys(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 1) {
        napi_throw_type_error(env, nullptr, "ageVerifySecretKeys expects (keys)");
        return nullptr;
    }

    std::string keys;
    const bool valid = ohos_age_verify_secret_keys(ArgAsCString(env, argv[0], keys)) != 0;

    napi_value result = nullptr;
    napi_get_boolean(env, valid, &result);
    return result;
}

napi_value AgeVerifyPublicKeys(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 1) {
        napi_throw_type_error(env, nullptr, "ageVerifyPublicKeys expects (keys)");
        return nullptr;
    }

    std::string keys;
    const bool valid = ohos_age_verify_public_keys(ArgAsCString(env, argv[0], keys)) != 0;

    napi_value result = nullptr;
    napi_get_boolean(env, valid, &result);
    return result;
}

/** `tunAttach(fd: number): string` */
napi_value TunAttach(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    int32_t fd = -1;
    if (argc < 1 || napi_get_value_int32(env, argv[0], &fd) != napi_ok) {
        napi_throw_type_error(env, nullptr, "tunAttach expects a numeric file descriptor");
        return nullptr;
    }

    const std::string report = DescribeTunFd(static_cast<int>(fd));
    napi_value result = nullptr;
    napi_create_string_utf8(env, report.c_str(), report.size(), &result);
    return result;
}

napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor properties[] = {
        {"tunAttach", nullptr, TunAttach, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"corePrepare", nullptr, CorePrepare, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"coreSetAgeSecretKey", nullptr, CoreSetAgeSecretKey, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"coreSetMarkSocket", nullptr, CoreSetMarkSocket, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"coreMarkSocketDone", nullptr, CoreMarkSocketDone, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"coreAttach", nullptr, CoreAttach, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"coreStop", nullptr, CoreStop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"ageGenX25519", nullptr, AgeGenX25519, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"ageGenHybrid", nullptr, AgeGenHybrid, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"ageToPublicKeys", nullptr, AgeToPublicKeys, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"ageVerifySecretKeys", nullptr, AgeVerifySecretKeys, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"ageVerifyPublicKeys", nullptr, AgeVerifyPublicKeys, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    return exports;
}

}  // namespace

static napi_module clashCoreModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "clashcore",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterClashCoreModule(void) {
    napi_module_register(&clashCoreModule);
}
