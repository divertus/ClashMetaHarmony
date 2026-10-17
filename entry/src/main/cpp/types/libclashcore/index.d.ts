/*
 * Typings for `libclashcore.so` -- see `cpp/napi_init.cpp` for what each call
 * actually does. `libclashcore.so` is a thin NAPI shim over `libclash.so`, the
 * OHOS arm64 build of mihomo; every function here is a direct forward to a Go
 * export in `cfa/ohos` (`work/clashmeta/core/src/main/golang/ohos/main.go`).
 *
 * Two groups:
 *
 *   core*   the VPN data plane. Single-shot: `corePrepare` -> `coreAttach` ->
 *           `coreStop`; `coreSetAgeSecretKey` installs the active profile's age
 *           identity before `corePrepare`. Only the `VpnExtensionAbility`
 *           process drives these.
 *   age*    pure crypto, no core state. The Meta-feature settings screen calls
 *           them from the ordinary UI process, exactly like Android calls
 *           `Clash.genX25519KeyPair` from `MetaFeatureSettingsDesign`.
 */

/**
 * Take the file descriptor that `vpnExtension.createVpnConnection().create()`
 * returns and report what native code can see of it: whether it is open,
 * whether `TUNGETIFF` says it is a TUN (and its name), and whether a
 * non-blocking read works.
 *
 * Diagnostic only -- it does not hand the descriptor to anything.
 *
 * @param fd TUN file descriptor from `VpnConnection.create()`.
 * @returns A one-line human-readable report, meant for hilog.
 */
export const tunAttach: (fd: number) => string;

/**
 * Load `profileDir/config.yaml` into the embedded mihomo core while the process
 * still has ordinary network access. This starts proxies, DNS, rules and the
 * external controller, but does not attach the TUN.
 *
 * @param home Writable app home directory for mihomo state.
 * @param profileDir Directory containing `config.yaml`.
 * @param version App version string reported by the core.
 * @returns Empty string on success, otherwise an error message.
 */
export const corePrepare: (home: string, profileDir: string, version: string) => string;

/**
 * Install the active profile's age secret key in the core before
 * `corePrepare` reads `profileDir/config.yaml`. The core uses the key only when
 * the config starts with an age armor header; an unencrypted config is left
 * unchanged. An empty key clears the previous identity.
 *
 * @param ageSecretKey Newline-separated age identities, or `''` when unset.
 */
export const coreSetAgeSecretKey: (ageSecretKey: string) => void;

/**
 * Install the per-socket protector used by the core dialer. Go calls the
 * callback for every outbound socket; the ArkTS side forwards the fd to
 * `VpnConnection.protect(fd)`.
 *
 * @param callback Receives the raw socket file descriptor.
 */
export const coreSetMarkSocket: (callback: (fd: number) => void) => void;

/**
 * Release the Go dialer hook waiting on the socket marker callback. The ArkTS
 * callback must call this after `VpnConnection.protect(fd)` settles.
 *
 * @param fd The socket file descriptor passed to the marker callback.
 */
export const coreMarkSocketDone: (fd: number) => void;

/**
 * Attach the TUN descriptor created by `VpnExtensionAbility`. Call this only
 * after `corePrepare` succeeded and the VPN routes are installed.
 *
 * The four string arguments are the same knobs Android's `TunService` reads
 * from `NetworkSettingsStore`, in the same order:
 *
 *   stack    sing-tun stack: `system` / `gvisor` / `mixed`
 *   gateway  comma-separated interface prefixes, e.g. `172.19.0.1/30`
 *   portal   inet4 source address sing-tun rewrites to, e.g. `172.19.0.2`
 *   dns      comma-separated DNS hijack addresses; `0.0.0.0` means "all"
 *
 * @param fd TUN descriptor from `VpnConnection.create()`.
 * @returns Empty string on success, otherwise an error message.
 */
export const coreAttach:
  (fd: number, stack: string, gateway: string, portal: string, dns: string) => string;

/** Stop the embedded core and detach the TUN descriptor. */
export const coreStop: () => void;

/**
 * Generate an X25519 age identity.
 *
 * @returns JSON: `{"ok":true,"secretKey":"AGE-SECRET-KEY-1...","publicKey":"age1..."}`
 *          or `{"ok":false,"error":"..."}`.
 */
export const ageGenX25519: () => string;

/**
 * Generate a post-quantum hybrid (MLKEM768-X25519) age identity. The pair is a
 * core-only primitive; there is no ArkTS-side equivalent.
 *
 * @returns The same JSON envelope as `ageGenX25519`.
 */
export const ageGenHybrid: () => string;

/**
 * Derive the public key of every identity in a newline-separated list.
 *
 * @param keys Newline-separated age secret keys.
 * @returns JSON: `{"ok":true,"publicKeys":["age1..."]}` or
 *          `{"ok":false,"error":"..."}`. The output order matches the input.
 */
export const ageToPublicKeys: (keys: string) => string;

/**
 * Validate a newline-separated list of age identities.
 *
 * @param keys Newline-separated age secret keys.
 * @returns `true` when every line parses as an age identity.
 */
export const ageVerifySecretKeys: (keys: string) => boolean;

/**
 * Validate a newline-separated list of age public keys (recipients).
 *
 * @param keys Newline-separated age public keys.
 * @returns `true` when every line parses as an age recipient.
 */
export const ageVerifyPublicKeys: (keys: string) => boolean;
