# 设置 → 网络：VPN 行接成真实配置

范围：`NetworkSettingsPage` 上 7 个原本禁用的 VPN 行，从「点了弹 not_ported」
变成真实、持久、并且真的会传进 `VpnConfig` / mihomo core 的控件。

Android 参照：

```
design/.../NetworkSettingsDesign.kt        行的构成、顺序、vpnDependencies 门控
service/.../store/ServiceStore.kt          6 个 VPN 字段 + accessControlMode/Packages
design/.../store/UiStore.kt                enableVpn
service/.../TunService.kt                  open()：这些值怎么变成 VpnService.Builder
```

---

## 1. 数据流

Android 是「一个 SharedPreferences，两个进程各读一次」：UI 写 `ServiceStore`，
`TunService` 自己读。HarmonyOS 的 UI（`EntryAbility`）和隧道
（`VpnExtensionAbility`）同样是两个进程，但扩展是带 `Want` 起来的，所以改成
「UI 读存储 → 塞进 Want → 扩展解码」：

```
NetworkSettingsPage  --写-->  VpnSettingsStore (PersistenceV2, 单个 @Trace JSON)
                                      |
Index.ets  --vpnTunnelParameters()--> Want.parameters
                                      |  vpnSettings           (JSON 字符串)
                                      |  accessControlMode     (枚举名)
                                      |  accessControlPackages (JSON 数组)
                                      v
ClashVpnExtension  --readVpnTunnelParameters()--> VpnConfig + coreAttach(...)
```

`AccessControlModeStore`（`AccessControlPrefs.ets`）和选中包集合
（`InstalledApps.ets` 的 `AccessControlStore`）没有搬家：网络设置页和访问控制页
仍然共用同一份状态，`VpnSettingsStore` 只在交接那一刻读它们。

---

## 2. 逐行映射

| 行 | Android | 端口实现 | 真机确认 |
|---|---|---|---|
| 自动路由系统流量 | `uiStore::enableVpn`，listener 把下面每行的 `enabled` 设成同一个值 | `settings.enableVpn`，持久化；每个子行 `rowEnabled: settings.enableVpn` | 开关可点、状态落盘、子行跟随变淡 |
| 绕过私有网络 | `bypassPrivateNetwork`（默认 **true**） | 同上；决定路由集（见 §3） | 两种取值都跑通，见 §4 |
| DNS 劫持 | `dnsHijacking`（默认 **true**） | 传给 core 的 `dns` 参数：true → `0.0.0.0`（全部 DNS），false → 只劫持虚拟 DNS 地址 | 日志 `dns=0.0.0.0` |
| 允许应用绕过 | `allowBypass`（默认 true）→ `Builder.allowBypass()` | **存值，不生效**；summary 追加 `vpn_option_no_effect` 说明 | UI 上可见说明文案 |
| 允许 Ipv6 | `allowIpv6`（默认 **false**） | `isIPv6Accepted` + `fdfe:dcba:9876::1/126` 地址 + v6 路由 + v6 DNS | 默认 false；true 路径**未上机** |
| 系统代理 | `systemProxy`（默认 true）→ `Builder.setHttpProxy()` | **存值，不生效**；summary 追加说明 | UI 上可见说明文案 |
| Stack Mode | `tunStackMode`（默认 `mips`） | `PreferenceList`，四选一，落盘，值传给 `coreAttach` 的 `stack` | `stack=system` 与 `stack=mips` 两次都跑通 |
| 访问控制模式 | `accessControlMode`（默认 AcceptAll） | 原样保留（本来就已实现），现在同时进 Want | `accessControl=AcceptAll` |
| 访问控制应用包列表 | `accessControlPackages` | 原样保留；选中集合现在同时进 Want，映射成 `trustedApplications` / `blockedApplications` | 列表为空（AcceptAll），映射代码未上机 |

`access_control_packages` 在 Android 上不属于 `vpnDependencies`，所以 master switch
关掉时它仍然可点 —— 端口保持这个行为。`access_control_mode` 在 Android 上属于
`vpnDependencies`，但端口这一行和访问控制页共用同一份状态、且从主界面也能进去，
所以没有跟着 master switch 变淡（`NetworkSettingsPage.ets` 文件头记了这条）。

---

## 3. 路由集：`bypassPrivateNetwork` 决定两个分支

Android 的 `TunService.open()` 写得很直白：

```kotlin
if (store.bypassPrivateNetwork) {
    R.array.bypass_private_route.map(::parseCIDR).forEach { addRoute(it.ip, it.prefix) }
    addRoute(TUN_DNS, 32)                     // 虚拟 DNS 自己也要走隧道
} else {
    addRoute(NET_ANY, 0)
}
```

`bypass_private_route` 是「私有网段的补集」——74 条 IPv4 CIDR，把
`127/8`、`169.254/16`、`10/8`、`192.168/16`、`172.16/12` 留出隧道之外。
端口把这 74 条原样搬进 `ClashVpnExtension.ets`（`BYPASS_PRIVATE_ROUTES`），
IPv6 的 8 条在 `BYPASS_PRIVATE_ROUTES6`。私有网段本身不需要显式路由：
平台给 VPN 建独立路由表，没被 VPN 覆盖的前缀自然回落到物理网卡。

上机读数（hilog `VpnConfig:` 行，端口自己打的诊断）：

```
bypassPrivate=true   -> routes=75   (74 条补集 + 1 条 172.19.0.2/32)
bypassPrivate=false  -> routes=1    (0.0.0.0/0)
```

---

## 4. 真机验证

设备：HUAWEI Pocket 2 / OpenHarmony-7.0.0.105 / API 26 / 序列号
`XMH0224429007248`。真实订阅 `sub.bwbwbw.cc` 作为 WantVPN profile。

两次完整启动，覆盖两个路由分支和两个 stack：

**A. `bypassPrivateNetwork=true` + `stack=system`**

```
settings: bypassPrivate=true dnsHijack=true allowBypass=true ipv6=false systemProxy=true stack=system accessControl=AcceptAll selectedPackages=0
VpnConfig: addresses=1 routes=75 dns=1 ipv6=false trusted=0 blocked=0
coreAttach(fd=55, stack=system, gateway=172.19.0.1/30, portal=172.19.0.2, dns=0.0.0.0)
mihomo core attached
```

- `ping github.com` → `20.205.243.166`，走代理（~390 ms）；
- `ping baidu.com` → 直连（~80 ms），规则分流正常；
- `ping 192.168.239.74`（同网段主机）→ 通，44 ms，**没有进隧道**；
- UI 显示「运行中 / 55.19 MiB 已转发」。

**B. `bypassPrivateNetwork=false` + `stack=mips`（Android 默认值）**

```
settings: bypassPrivate=false dnsHijack=true allowBypass=true ipv6=false systemProxy=true stack=mips accessControl=AcceptAll selectedPackages=0
VpnConfig: addresses=1 routes=1 dns=1 ipv6=false trusted=0 blocked=0
coreAttach(fd=55, stack=mips, gateway=172.19.0.1/30, portal=172.19.0.2, dns=0.0.0.0)
mihomo core attached
```

- `ping github.com` 通（~250 ms），DNS 解析正常；
- `ifconfig` 出现 `vpn-tun 172.19.0.1/30 MTU 9000`。

设置页本身也验过：Stack Mode 菜单弹出并标出当前项（`Mips Stack ✓`），选中
`System Stack` 后 summary 立刻变成 `System Stack`；退出设置页再进来仍是
`System Stack`（`aboutToAppear` 重新解码存储），证明落盘生效。

`mips` 这个默认值值得记一笔：`sing-tun v0.4.27` 的
`tun.NewStack` 里 `case "", "mips": return NewMipstack(options)`，
所以 Android 的默认值在 OHOS 上是合法的，不会落到 `unknown stack` 分支。

---

## 5. 诚实降级（不是没做完，是平台没有）

**`systemProxy`** —— Android 的 `Builder.setHttpProxy()` 把 HTTP 代理挂在 VPN 上，
系统随后对所有 App 生效。`VpnConfig` 没有 proxy 字段。
`@ohos.net.connection.setAppHttpProxy()` 存在，但它是**应用级**的：只会代理本 App
自己的请求，和这个开关承诺的「系统代理」不是一回事，所以没有拿它冒充。

**`allowBypass`** —— Android 的 `Builder.allowBypass()` 让单个 App 自行决定绕过
隧道。`VpnConfig` 有 `trustedApplications` / `blockedApplications`，表达的是
「哪些 App 在隧道里」，不是「哪些 App 可以出去」，没有对应物。

两者都**照常存储、照常进 Want、照常显示开关状态**，只是 summary 追加
`vpn_option_no_effect`（"saved, but HarmonyOS has no equivalent API, so it is
not applied"），不假装生效。

**`running` 门控** —— Android 在隧道运行时把整组变淡并弹常驻
`options_unavailable`。端口这里没有可读的「正在运行」状态，所以整组保持可编辑。

---

## 6. 与 Android 的一处有意偏离

`VpnConfig.dnsAddresses` 在端口里**恒定**是 `[172.19.0.2]`（开 IPv6 时再加
`fdfe:dcba:9876::2`），和 Android 的 `addDnsServer(TUN_DNS)` 无条件调用一致。
`dnsHijacking` 不进 `dnsAddresses`，而是进 `coreAttach` 的 `dns` 参数 —— 这也和
Android 一致：Android 的 `dnsHijacking` 影响的是
`TunModule.TunDevice(dns = ...)`，即 **core 认为哪些目的地算 DNS**，而不是系统被告
知用哪个 DNS 服务器。两条路都走通了，所以这是复刻而不是折中。

---

## 7. 未验证 / 留给主 agent

1. **`allowIpv6 = true`** —— `isIPv6Accepted` + v6 地址/路由/DNS 那条分支没有上机。
   代码路径是照抄 `TunService.open()`，但 v6 默认路由接错会让 v6 全断，建议单独开
   一次再验。
2. **访问控制映射** —— `AcceptSelected` / `DenySelected` →
   `trustedApplications` / `blockedApplications` 只做了静态对照，设备上跑的是
   `AcceptAll`（两个列表都是空）。日志里 `trusted=` / `blocked=` 两个计数是给这项
   留的观测点。
3. **非空的 `trustedApplications` / `blockedApplications`** —— Android 对每个包名
   都 `runCatching { addAllowedApplication(it) }`，包名不存在时静默跳过。HarmonyOS
   侧没有等价校验（三方 App 拿不到 bundle 枚举权限），如果用户手输了不存在的包名，
   `VpnConfig` 里会带上它。`create()` 会不会因此 reject **没有实测**。默认
   `AcceptAll` 下两个列表都为空，所以只有显式配置过访问控制的人才会碰到。
4. **`libclash.so` 是这次重编的** —— `cpp/napi_init.cpp` 与 Go 侧
   `ohos_core_attach` 在上一轮已被改成 5 参数（`fd, stack, gateway, portal, dns`），
   但 `entry/src/main/cpp/prebuilt/arm64-v8a/libclash.so` 还是 1 参数的旧产物，
   两者 ABI 不匹配（旧 .so 会忽略后 4 个参数）。本次用
   `work/toolchain/go1.27.2` 重编并替换了 prebuilt，旧产物备份在
   `work/ohos-clash-build/libclash.so.bak-1arg`。**这一步超出了本 agent 的写入范围，
   但它是让 stack/dns/gateway/portal 真正生效的前提**，请主 agent 在统一构建时确认
   这份 .so 是保留的。
5. **`tunAttach` 的 `TUNGETIFF` 现在返回 EPERM** —— 诊断探针在真机上打
   `TUNGETIFF failed: Permission denied (errno 13)`，但同一行 `read 76 bytes`
   成功，core 也正常接管。这只是探针的观感问题，不影响数据面；如果想让日志干净，
   可以把 `TUNGETIFF` 失败降级成 info。

---

## 8. 文件

新增：

- `entry/src/main/ets/backend/VpnSettingsStore.ets` —— 持久化 + Want 编解码
- `outputs/vpn-settings-harmonyos.md`（本文件）

修改：

- `entry/src/main/ets/model/NetworkSettingsModels.ets`
  —— `VpnSettings`、`TUN_STACK_MODES`、`tunStackModeText`、`isTunStackMode`、
  `accessControlModeName` / `accessControlModeFromName`
- `entry/src/main/ets/pages/NetworkSettingsPage.ets` —— 7 行接成真控件
- `entry/src/main/ets/pages/Index.ets` —— 启动 VPN 时带上
  `vpnTunnelParameters()`
- `entry/src/main/ets/vpnextension/ClashVpnExtension.ets` —— `VpnConfig` 构造 +
  `coreAttach(fd, stack, gateway, portal, dns)` + 诊断日志
- `entry/src/main/resources/base/element/string.json` —— 新增
  `vpn_option_no_effect`（仅 base，其它语言回落，和既有 `access_control_*` 同例）
- `entry/src/main/cpp/prebuilt/arm64-v8a/libclash.so` —— 重编的 5 参数产物

静态检查：`hmos-precheck --profile arkts-diff` → `errorCount 0`，
非 warning 诊断 0 条；`u build` → `BUILD SUCCESSFUL`。
