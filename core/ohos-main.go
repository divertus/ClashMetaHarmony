package main

/*
#include <stdlib.h>

typedef void (*ohos_mark_socket_fn)(int);
static ohos_mark_socket_fn ohos_mark_socket_callback = NULL;

static void ohos_set_mark_socket_callback(void* callback) {
    ohos_mark_socket_callback = (ohos_mark_socket_fn)callback;
}

static void ohos_call_mark_socket_callback(int fd) {
    if (ohos_mark_socket_callback != NULL) {
        ohos_mark_socket_callback(fd);
    }
}
*/
import "C"

import (
	"encoding/json"
	"io"
	"strings"
	"sync"
	"syscall"
	"unsafe"

	"cfa/native/app"
	"cfa/native/config"
	"cfa/native/tun"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
)

var (
	coreMu       sync.Mutex
	coreCloser   io.Closer
	corePrepared bool
	coreAttached bool
)

func errorString(err error) *C.char {
	if err == nil {
		return C.CString("")
	}
	return C.CString(err.Error())
}

// marshalJSON renders a result envelope as a C string. `C.CString` allocates
// with malloc, which is the ownership rule every `char*` export in this file
// follows: the caller frees.
func marshalJSON(value any) *C.char {
	data, err := json.Marshal(value)
	if err != nil {
		return C.CString(`{"ok":false,"error":"failed to marshal result"}`)
	}
	return C.CString(string(data))
}

// ohos_core_prepare loads a Clash profile and starts the userspace parts of
// mihomo (proxies, DNS, rules, external controller) while the process still has
// ordinary network access. The TUN is deliberately not attached yet.
//
// The caller owns the returned C string and must release it with free(3).
// An empty string means success; otherwise the string is the error.
//
//export ohos_core_set_mark_socket
func ohos_core_set_mark_socket(callback unsafe.Pointer) {
	C.ohos_set_mark_socket_callback(callback)
}

//export ohos_core_prepare
func ohos_core_prepare(home, profileDir, version *C.char) *C.char {
	coreMu.Lock()
	defer coreMu.Unlock()

	if corePrepared {
		return C.CString("core is already prepared")
	}

	homeDir := C.GoString(home)
	profile := C.GoString(profileDir)
	versionName := C.GoString(version)

	constant.SetHomeDir(homeDir)
	app.ApplyVersionName(versionName)
	app.ApplyPlatformVersion(34)

	// Android's TunModule passes VpnService.protect as the per-socket marker.
	// OHOS uses the same shape: `coreSetMarkSocket` installs an ArkTS callback
	// that calls VpnConnection.protect(fd) for every socket the core dials.
	dialer.DefaultSocketHook = func(network, address string, conn syscall.RawConn) error {
		return conn.Control(func(fd uintptr) {
			C.ohos_call_mark_socket_callback(C.int(fd))
		})
	}

	rawCfg, err := config.UnmarshalAndPatch(profile)
	if err != nil {
		return errorString(err)
	}

	// The port's UI talks to the core over the external-controller REST API.
	// cfa's patch intentionally clears the profile value; put the local
	// endpoint back before the controller starts.
	rawCfg.ExternalController = "127.0.0.1:9090"
	rawCfg.ExternalControllerTLS = ""

	cfg, err := config.Parse(rawCfg)
	if err != nil {
		return errorString(err)
	}

	hub.ApplyConfig(cfg)

	corePrepared = true
	return C.CString("")
}

// ohos_core_set_age_secret_key installs the age identities used by
// config.UnmarshalRawConfig's age decryption. A blank key clears the global
// identity list, matching Android's `Clash.setAgeSecretKey(null)`.
//
//export ohos_core_set_age_secret_key
func ohos_core_set_age_secret_key(secretKey *C.char) {
	if secretKey == nil {
		config.SetGlobalSecretKeys()
		return
	}

	key := C.GoString(secretKey)
	if strings.TrimSpace(key) == "" {
		config.SetGlobalSecretKeys()
		return
	}

	config.SetGlobalSecretKeys(key)
}

// ohos_core_attach attaches the TUN descriptor after the VPN routes are
// installed. At this point the core is already listening and the route change
// cannot black-hole its own DNS/provider downloads.
//
// `stack`, `gateway`, `portal` and `dns` are the same four knobs Android's
// `TunService` reads from `NetworkSettingsStore` before calling
// `startTun(fd, stack, gateway, portal, dns)`; the port used to hard-code
// them here, which left the network-settings rows with nowhere to land.
//
//	stack    sing-tun stack name: "system" / "gvisor" / "mixed"
//	gateway  comma-separated interface prefixes, e.g. "172.19.0.1/30"
//	portal   the inet4 source address sing-tun rewrites to, e.g. "172.19.0.2"
//	dns      comma-separated DNS hijack addresses; "0.0.0.0" means "all"
//
//export ohos_core_attach
func ohos_core_attach(fd C.int, stack, gateway, portal, dns *C.char) *C.char {
	coreMu.Lock()
	defer coreMu.Unlock()

	if !corePrepared {
		return C.CString("core is not prepared")
	}
	if coreAttached {
		return C.CString("core is already attached")
	}

	closer, err := tun.Start(
		int(fd),
		C.GoString(stack),
		C.GoString(gateway),
		C.GoString(portal),
		C.GoString(dns),
	)
	if err != nil {
		return errorString(err)
	}

	coreCloser = closer
	coreAttached = true
	return C.CString("")
}

//export ohos_core_stop
func ohos_core_stop() {
	coreMu.Lock()
	defer coreMu.Unlock()

	if coreCloser != nil {
		_ = coreCloser.Close()
		coreCloser = nil
	}
	coreAttached = false
	corePrepared = false
	dialer.DefaultSocketHook = nil
}

// ---------------------------------------------------------------------------
// Age key helpers
// ---------------------------------------------------------------------------
//
// The Meta-feature settings screen's two "Age Key" rows open a helper dialog
// that generates an age identity, derives its public key and validates what
// the user typed. Android gets all five operations from `Clash`, i.e. from the
// core: `genX25519KeyPair`, `genHybridKeyPair`, `veritySecretKeys`,
// `toPublicKeys`, `verityPublicKeys`. The hybrid MLKEM768-X25519 pair in
// particular exists only in mihomo's `component/age`, so there is nothing to
// reimplement on the ArkTS side -- these are the same five calls.
//
// Result shape: every export that returns data returns a JSON object with an
// explicit `ok` flag, so a failure carries a reason instead of collapsing into
// an empty string:
//
//   {"ok":true,"secretKey":"AGE-SECRET-KEY-1...","publicKey":"age1..."}
//   {"ok":false,"error":"..."}
//
// The two validators return a plain C int (1 = valid, 0 = not) because a
// boolean needs no envelope.

// ageKeyPairResult is the JSON envelope `ohos_age_gen_*` returns.
type ageKeyPairResult struct {
	Ok        bool   `json:"ok"`
	SecretKey string `json:"secretKey,omitempty"`
	PublicKey string `json:"publicKey,omitempty"`
	Error     string `json:"error,omitempty"`
}

// agePublicKeysResult is the JSON envelope `ohos_age_to_public_keys` returns.
type agePublicKeysResult struct {
	Ok         bool     `json:"ok"`
	PublicKeys []string `json:"publicKeys,omitempty"`
	Error      string   `json:"error,omitempty"`
}

//export ohos_age_gen_x25519
func ohos_age_gen_x25519() *C.char {
	secretKey, publicKey, err := config.GenX25519KeyPair()
	if err != nil {
		return marshalJSON(ageKeyPairResult{Ok: false, Error: err.Error()})
	}

	return marshalJSON(ageKeyPairResult{Ok: true, SecretKey: secretKey, PublicKey: publicKey})
}

//export ohos_age_gen_hybrid
func ohos_age_gen_hybrid() *C.char {
	secretKey, publicKey, err := config.GenHybridKeyPair()
	if err != nil {
		return marshalJSON(ageKeyPairResult{Ok: false, Error: err.Error()})
	}

	return marshalJSON(ageKeyPairResult{Ok: true, SecretKey: secretKey, PublicKey: publicKey})
}

// ohos_age_verify_secret_keys accepts a newline-separated list of age
// identities and returns 1 when every line parses.
//
//export ohos_age_verify_secret_keys
func ohos_age_verify_secret_keys(secretKeys *C.char) C.int {
	if config.VeritySecretKeys(C.GoString(secretKeys)) != nil {
		return 0
	}

	return 1
}

// ohos_age_to_public_keys maps a newline-separated list of age identities to
// the matching public keys, in the same order.
//
//export ohos_age_to_public_keys
func ohos_age_to_public_keys(secretKeys *C.char) *C.char {
	publicKeys, err := config.ToPublicKeys(C.GoString(secretKeys))
	if err != nil {
		return marshalJSON(agePublicKeysResult{Ok: false, Error: err.Error()})
	}

	return marshalJSON(agePublicKeysResult{Ok: true, PublicKeys: publicKeys})
}

//export ohos_age_verify_public_keys
func ohos_age_verify_public_keys(publicKeys *C.char) C.int {
	if config.VerityPublicKeys(C.GoString(publicKeys)) != nil {
		return 0
	}

	return 1
}

func main() {}
