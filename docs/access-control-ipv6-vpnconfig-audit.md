# 独立审计：访问控制与 IPv6 的 VpnConfig 语义

范围：`accessControlMode` / `accessControlPackages` / `allowIpv6` 是否真正映射到
OHOS `@ohos.net.vpnExtension` 的 `VpnConfig`，以及真机上安全验证的方法。
只做代码 / 文档 / 平台源码的静态核对，未碰设备。

---

## 0. 结论

**映射是忠实的，没有发现明确 bug，因此没有改代码。**

- `allowIpv6` 的四个落点（`isIPv6Accepted`、v6 接口地址、v6 路由、v6 DNS）逐条
  对齐 Android `TunService.open()`，两个路由数组与 `arrays.xml` 逐项相同。
- `AcceptAll / AcceptSelected / DenySelected` 三个分支与 Android 的
  `addAllowedApplication` / `addDisallowedApplication` 语义一致，且满足平台
  "两个列表不能同时配置" 的约束。
- 之前担心的一条风险（用户手输不存在的包名会让 `create()` reject）**经平台源码
  证伪**：平台会跳过解析失败的包名，等价于 Android 的 `runCatching`。

剩余的都是"文档范围 / 上限"级别的风险，见 §4。

---

## 1. 每个字段的映射证据

### 1.1 `allowIpv6`

| 落点 | 端口代码 | Android `TunService.open()` | 结论 |
|---|---|---|---|
| `isIPv6Accepted` | `ClashVpnExtension.ets:449` `isIPv6Accepted: settings.allowIpv6` | Android 无同名字段（靠"加不加 v6 地址/路由"表达） | 语义等价：false = 不收 v6，v6 走底层网络 |
| 接口地址 | `:318 buildAddresses()` 加 `fdfe:dcba:9876::1/126`（family 2） | `addAddress(TUN_GATEWAY6, TUN_SUBNET_PREFIX6)` | 相同 |
| 路由 | `:341 buildRoutes()` 加 `BYPASS_PRIVATE_ROUTES6` + `fdfe:dcba:9876::2/128`，或 `::/0` 默认路由 | `addRoute(bypass_private_route6...)` + `addRoute(TUN_DNS6, 128)` / `addRoute(NET_ANY6, 0)` | 相同 |
| DNS | `:440` `dnsAddresses: [TUN_PORTAL, TUN_PORTAL6]` | `addDnsServer(TUN_DNS)` + `addDnsServer(TUN_DNS6)` | 相同 |
| core 参数 | `:401/:410/:422` `coreGateway/corePortal/coreDns` 追加 v6 | `TunDevice(gateway=..., portal=..., dns=...)` | 相同 |
| 默认值 | `NetworkSettingsModels.ets` `allowIpv6 = false` | `ServiceStore.allowIpv6` 默认 `false` | 相同 |

平台侧依据：

- SDK `ets/api/@ohos.net.vpnExtension.d.ts:286` —— `isIPv6Accepted?: boolean`，
  "The default value is false"。
- OpenHarmony 文档 `zh-cn/application-dev/reference/apis-network-kit/js-apis-net-vpnExtension.md:770`
  —— "若支持 IPv6 功能，需要在 addresses 中配置 IPv6 类型的 IP 地址"。端口在
  `allowIpv6` 为真时确实把 v6 LinkAddress 加进了 `addresses`，满足该前置条件。

### 1.2 `accessControlMode` + `accessControlPackages`

端口把设置读进 `VpnTunnelParameters`（`VpnSettingsStore.ets:131-132`），
`vpnTunnelParameters()` 打包成 Want 参数（`:146-149`），扩展侧
`readVpnTunnelParameters()` 解出（`:174-181`），再在 `create()` 里落成
`trustedApplications` / `blockedApplications`（`ClashVpnExtension.ets:371-397, 451-452`）。

| 模式 | 端口产出 | Android | 平台语义（文档） |
|---|---|---|---|
| `AcceptAll` | 两个列表都空 | `AccessControlMode.AcceptAll -> Unit` | 两个都空 → 全应用 uid 段（全网代理） |
| `AcceptSelected` | `trustedApplications = 选中 ∪ {自己}` | `(packages + packageName).forEach { addAllowedApplication }` | "仅该列表中的应用数据才能根据 routes 被 VPN 代理" |
| `DenySelected` | `blockedApplications = 选中 \ {自己}` | `(packages - packageName).forEach { addDisallowedApplication }` | "该列表中的应用数据不会被 VPN 代理，其他应用可以被代理" |

"自己" = `:250 bundleName()` 取 `context.applicationInfo.name`。SDK
`bundleManager/ApplicationInfo.d.ts:29` 明确注释 "Indicates the application name,
which is the same as `bundleName`"，所以这条"VPN 应用不进自己的隧道"规则表达正确。

平台侧依据（`communication_netmanager_ext`，master）：

- 解析：`frameworks/js/napi/vpnext/src/vpn_config_utils_ext.cpp:128-129`
  —— `trustedApplications -> acceptedApplications_`，`blockedApplications -> refusedApplications_`。
- 落地：`services/vpnmanager/src/net_vpn_impl.cpp:465-495 GenerateUidRanges()`：
  - `acceptedApplications_` 非空 → `GenerateUidRangesByAcceptedApps`（只覆盖这些 uid）；
  - 否则 `refusedApplications_` 非空 → `GenerateUidRangesByRefusedApps`（取补集）；
  - 都为空 → 整个应用 uid 段（= AcceptAll）。

  `if / else if` 的结构说明：**两个列表即使同时非空，trusted 优先**；端口本来就
  只填一个，天然满足。
- 未知包名：`net_vpn_impl.cpp:430-462 GetAppsUids()` 对解析失败的包名只
  `NETMGR_EXT_LOG_E("app: ... error")` 后跳过，不抛错、不影响 `create()`。
  这正是 Android `runCatching { addAllowedApplication(it) }` 的等价物。

---

## 2. 静态验证（可复现）

1. **路由数组逐项相同**（脚本比对，非肉眼）：

   ```
   v4 count 74   xml v4 74   match: True
   v6 count  8   xml v6  8   match: True
   ```

   对照 `work/clashmeta/service/src/main/res/values/arrays.xml`。
2. **路由条数**：`bypassPrivateNetwork=true` → 74 + 1（虚拟 DNS `/32`）= **75**，
   与主线记录的 `VpnConfig 75 条路由` 吻合；开 IPv6 → 74 + 8 + 2 = **84**。
3. **补集语义**：对 74 条 v4 做 collapse，结果 = `0.0.0.0/0` 去掉
   `10/8`、`127/8`、`169.254/16`、`172.16/12`、`192.168/16`（以及 Android 同样
   有意排除的 `0.0.0.0/8`、`224.0.0.0/4`）。与 `arrays.xml` 顶部注释一致。
4. **v6 补集**：collapse 结果恰为 `::/1, 8000::/2, c000::/3, e000::/4,
   f000::/5, f800::/6, fe00::/9, fec0::/10`，即 `::/0` 去掉
   `fc00::/7`、`fe80::/10`、`ff00::/8`。
5. **NAPI ABI**：`cpp/napi_init.cpp:65` 与 Go `work/clashmeta/core/src/main/golang/ohos/main.go:128`
   都是 5 参数 `(fd, stack, gateway, portal, dns)`；`cpp/types/libclashcore/index.d.ts`
   签名一致；`prebuilt/arm64-v8a/libclash.so` 时间戳 03:42（晚于 5 参数改动）。
   即 IPv6 的 gateway/portal/dns 确实能到 core。
6. **启动路径完整**：三条真实启动路径都带 `vpnTunnelParameters()`
   —— `pages/Index.ets:189`、`backend/ExternalControl.ets:446`、
   `entryformability/EntryFormAbility.ets:120`。唯一不带的是
   `EntryAbility.maybeStartVpnDebug()` 的 `vpnDebug 1` 调试钩子（只发
   `vpnRoutes: '1'`），属于设计内。

---

## 3. 可能 bug

没有发现需要改代码的明确 bug。逐条排除了下面这些怀疑点：

| 怀疑点 | 结论 |
|---|---|
| 手输不存在的包名让 `create()` reject | 否。平台 `GetAppsUids` 跳过并记日志 |
| `trustedApplications` + `blockedApplications` 同时出现会被拒 | 否。官方示例就同时传两个 key；平台 `if/else if` 只取一个 |
| 空数组被当成"已配置" | 否。AcceptAll 上机跑通（两个都空，日志 `trusted=0 blocked=0`） |
| `applicationInfo.name` 不是 bundleName | 否。SDK 注释明确二者相同 |
| 路由数组手抄出错 | 否。与 `arrays.xml` 逐项相同 |
| `acceptSelected` 未选任何应用 | 与 Android 一致：`{自己}` → 因 socket 已 protect，实际不代理任何应用（与 Android 同样"等于关闭"） |

---

## 4. 风险（不阻塞，但值得知道）

1. **MTU = 9000 超出文档范围**。文档写 `mtu` 取值 `[576, 1500]`，端口沿用
   Android 的 `TUN_MTU = 9000`。本机真机已把 9000 应用到 `vpn-tun` 并跑通，说明
   这个版本不校验；但换设备 / 换版本若校验，`create()` 会以 `2200001` 失败
   （整个 VPN 起不来，不只是 v6）。属于"文档范围之外但实测可用"，不是 bug。
2. **应用列表上限**。文档写 API 23 前最多 64、23 起 256 个包名。端口没有截断，
   平台 napi 层（`ParseOptionArrayString`）也没有长度校验，所以超限行为未知。
   只对"选了非常多个应用"的人有影响。
3. **`isIPv6Accepted=true` 的风险面比 v4 大**。v6 一旦路由接错就是 v6 全断
   （v4 仍通），且 v6 默认路由只有一条，容易整段黑洞。测试时务必按 §5 的
   "先看日志、再打流量、失败立刻切回"顺序。
4. **`gvisor` stack 不可用**（已知：OHOS VPN fd 的 `Fstat` 返回 EPERM）。与本次
   IPv6 / 访问控制无关，但 `tunStackMode` 仍暴露该选项，选它会失败。

---

## 5. 真机测试矩阵

前置：VPN 已能正常启停；`hdc shell ifconfig vpn-tun` 可见 v4 地址；
`hilog -x -T ClashVpnExt` 能出 `VpnConfig:` 与 `coreAttach(...)` 两行。

### 5.1 IPv6 开 / 关

| # | `allowIpv6` | 期望日志 | 期望 `ifconfig vpn-tun` | 流量验证 |
|---|---|---|---|---|
| A1 | false（默认） | `addresses=1 routes=75 dns=1 ipv6=false`；`coreAttach(... gateway=172.19.0.1/30, portal=172.19.0.2, dns=172.19.0.2)` | 只有 `172.19.0.1/30` | v4 站（github）走代理；v6 站直连（不经隧道） |
| A2 | true | `addresses=2 routes=84 dns=2 ipv6=true`；`gateway=172.19.0.1/30,fdfe:dcba:9876::1/126`、`portal=172.19.0.2,fdfe:dcba:9876::2`、`dns=` 视 `dnsHijacking` | 多出 `fdfe:dcba:9876::1/126` | `hdc shell ping6 -c3 2400:3200::1`（Ali v6 DNS）能通；浏览器访问 IPv6 站点成功 |

安全做法：A2 前先记下 A1 的 `ifconfig`；A2 失败（ping6 不通 / 浏览器白屏）时
**立刻**在设置页关回 `allowIpv6` 再重启 VPN，避免停在 v6 黑洞状态。
另外 A2 建议同时把 `bypassPrivateNetwork` 两种取值各跑一次
（`true`=84 条路由；`false`=2 条默认路由），因为这是 v6 最容易接错的一处。

### 5.2 访问控制（用浏览器包名）

先拿到浏览器 bundle name：在 `设置 → 网络 → 访问控制应用包列表` 用工具栏 `+`
输入候选名（华为浏览器 `com.huawei.hmos.browser`；OpenHarmony 设备可能是
`com.ohos.browser`）。**能解析出真实图标/名称的那个就是对的**（走
`GET_BUNDLE_INFO`）；解析不出来会渲染成暗色包名行，说明名字不对。

| # | 模式 | 选中集合 | 浏览器期望 | 其他应用期望 | 观察点 |
|---|---|---|---|---|---|
| B0 | AcceptAll | 任意 | 走隧道 | 走隧道 | 基线；日志 `trusted=0 blocked=0` |
| B1 | AcceptSelected | 仅浏览器 | **走隧道** | 直连 | 日志 `trusted=2`（浏览器 + 自己）`blocked=0`；浏览时控制器 `/connections` 出现该连接 |
| B2 | DenySelected | 仅浏览器 | **直连** | 走隧道 | 日志 `trusted=0 blocked=1`；浏览时 `/connections` **不**出现该连接 |
| B3 | AcceptSelected | 浏览器 + 一个不存在的包名 | 走隧道 | 直连 | 日志 `trusted=3`；`create()` 仍成功（验证平台跳过未知包名） |
| B4 | DenySelected | 只有自己（`com.example.clashmeta`） | 走隧道 | 走隧道 | 日志 `blocked=0` → 退化成 AcceptAll（验证"不能把自己放进黑名单"） |

判读方法（任选，从强到弱）：

1. 端口后端 / 外部控制器的 `GET /connections`：B1 能看到浏览器请求，B2 看不到。
2. 主界面实时流量 / 节点计数：B1 浏览时增长，B2 不增长。
3. 同一目标站在 B1 与 B2 下分别用浏览器打开，对比是否真的走了代理
   （例如用只对代理 IP 返回结果的探测页）。

B4 之后记得把选中集合清空再切回 AcceptAll，避免留下"退化成 AcceptAll 但模式显示
DenySelected"的困惑状态。

---

## 6. 建议的最小补丁（可选，未改动）

没有必须打的补丁。若真机上真出现"两个 app 列表同时出现导致 `create()` 失败"，
最小、最保守的改法是：**只在列表非空时才写这个字段**，即
`ClashVpnExtension.ets:451-452` 改成

```ts
const trusted: string[] = this.buildTrustedApplications();
const blocked: string[] = this.buildBlockedApplications();
// ...
trustedApplications: trusted.length > 0 ? trusted : undefined,
blockedApplications: blocked.length > 0 ? blocked : undefined
```

这样 AcceptAll / 未选任何应用时两个 key 都不出现，把"不能同时配置"的歧义彻底消掉。
但官方示例与真机 AcceptAll 都证明两个空数组是可接受的，所以这属于锦上添花，
不建议在没有实测失败的情况下先改。

---

## 7. 本次改动文件

无（只读审计）。本文件为新增文档：

- `outputs/access-control-ipv6-vpnconfig-audit.md`
