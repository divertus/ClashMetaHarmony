# Platform limits measured on HarmonyOS NEXT / API 26

Each row was checked on a real device (HUAWEI Pocket 2, HarmonyOS 7.0.0.109,
API 26) with a normally signed app. "Closed" means the API exists but a normal
signature cannot hold the permission it needs.

| Capability | Verdict | Evidence |
|---|---|---|
| Third-party VPN / TUN | available | `@ohos.net.vpnExtension` `VpnExtensionAbility`, `createVpnConnection()`; no privileged permission. A TUN came up at `172.19.0.1/30`. |
| IPv6 through the tunnel | available | `VpnConfig.isIPv6Accepted` plus IPv6 addresses/routes/DNS; device reported `addresses=2 routes=84 dns=2`. |
| Per-app routing (allow list / block list) | available | `VpnConfig.trustedApplications` / `blockedApplications`; device reported `trusted=2` and `blocked=1`. |
| Reading another process's HiLog | closed | No public API; the log-reading permissions are system / system-core / enterprise MDM level. |
| Enumerating installed apps | closed | `bundleManager.getInstalledBundleList` needs `ohos.permission.ENTERPRISE_GET_INSTALLED_BUNDLE_LIST`, `availableLevel: system_basic`. |
| Resolving another app's bundle info by name | closed | `getBundleInfo(name, flags)` returns `BusinessError 201` demanding `GET_BUNDLE_INFO_PRIVILEGED`, even with `GET_BUNDLE_INFO` granted. |
| Resolving a bundle name from a uid | closed | `getBundleNameByUidSync(uid)` returns `BusinessError 201`; the granted `GET_BUNDLE_INFO` is not sufficient when the target is not the caller. |
| System-wide HTTP/PAC proxy | closed | `connection.setPacUrl()` / `setPacFileUrl()` need `ohos.permission.SET_PAC_URL`, `availableLevel: system_basic`. `setAppHttpProxy()` only affects the calling app. |
| Quick-settings tile | absent | No tile or control-centre API in the OpenHarmony or HMS `.d.ts` trees. The only near hit, `@hms.pcService.quickBarManager`, is PC-only. |
| Dialer secret code | absent | No MMI / secret-code API. Use a URI scheme plus launcher shortcuts instead. |
| Reading `/proc/<other pid>/fd` | closed | `ls /proc/<pid>/fd` from the device shell returns nothing for another app's process. |

## Two traps in this table

**"The permission level is `normal`" does not mean the API works.** `GET_BUNDLE_INFO`
is `availableLevel: normal` and the app held it
(`reqPermissionStates: [0, 0, 0]`), yet every bundle lookup for a target other
than the caller still answered 201. The permission list is necessary evidence,
not sufficient evidence. Call the API.

**"No API" and "closed API" have different consequences.** The first means
redesign; the second means ship the degraded path and say so. The bundle case is
the second: the manual/imported list still works, and an enumeration scan starts
working the day the app is signed with a privileged profile, so it is worth
keeping behind a menu entry rather than deleting.

## A workflow consequence

A VPN client's per-app routing list needs a UI, and the platform will not give
you the app list. Plan for manual package entry plus clipboard import from the
start; do not leave it as "TODO: enumerate apps", because it will not resolve.
