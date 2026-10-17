# ExternalControl 快捷入口 / 快捷方式（HarmonyOS 端口）

范围：把 ClashMetaForAndroid 的**无界面启停入口**补到 HarmonyOS 端。对应 Android
`ExternalControlActivity`（路线图第 19 项）、`MainActivity.setupShortcuts()`
（`ShortcutManagerCompat` 动态快捷方式）、`TileService`（快捷设置磁贴）和
`DialerReceiver`（拨号盘密令）。

本轮之前的状态：`ExternalControlActivity` 的四个动作里，`ACTION_VIEW` 的两个路由
（`clash://install-config`、`clash://profiles`）已经实测可用，但
TOGGLE / START / STOP 三个动作报 `not_ported`，也没有任何快捷方式声明。

---

## 1. 平台结论（先给结论，再给证据）

| Android 侧入口 | HarmonyOS 有没有公开等价物 | 本端口的处理 |
|---|---|---|
| `ShortcutManagerCompat.setDynamicShortcuts()` 三个快捷方式 | **部分有**。静态快捷方式由 `module.json5` 的 ability `metadata` + `$profile:shortcuts_config` 声明；`@ohos.bundle.shortcutManager`（API 20+）只能查询/显隐已有条目，不能动态创建 | **已实现静态快捷方式**，长按图标实测出现「切换 Clash / 启动 Clash / 停止 Clash」；动态创建不移植 |
| `Intents.ACTION_TOGGLE_CLASH` / `START_CLASH` / `STOP_CLASH` | **有**。HarmonyOS 的对应物是 `@ohos.net.vpnExtension` 的 `startVpnExtensionAbility()` / `stopVpnExtensionAbility()`，和主界面状态卡走同一条路 | **已实现**，三个动作全部真跑（不再是 `not_ported`） |
| `TileService`（快捷设置磁贴） | **没有磁贴 API**。HarmonyOS 不向三方应用开放快捷设置磁贴；平台提供的公开替代形态是**服务卡片**（FormExtensionAbility + 卡片 UI） | **已实现服务卡片**，卡片提供启动/停止/切换三个动作；磁贴本身不移植 |
| `DialerReceiver`（`*#*#252746382#*#*` 密令） | **没有**。HarmonyOS 没有 `android.provider.Telephony.SECRET_CODE` 这类公开密令通道 | **不移植**，改用静态快捷方式作为「不经主界面直达启停」的入口 |

### 证据（全部来自本地 SDK / 本地文档）

- 静态快捷方式的配置方法：本地文档
  `开发指南/开发基础知识/典型场景的开发指导/创建应用静态快捷方式/typical-scenario-configuration`
  ——「在应用的 module.json5 文件中配置 metadata，`name` 固定为
  `ohos.ability.shortcuts`，`resource` 指向 `$profile:<配置文件>`」，且
  「桌面展示快捷方式的数量有上限要求，最多展示 4 个」。
- 配置文件的 schema：
  `/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/modulecheck/shortcuts.json`
  —— `shortcutId`（必填）/ `label` / `icon` / `visible` /
  `wants[{bundleName, moduleName, abilityName, parameters}]`。
  **`wants` 里没有 `action`、也没有 `uri`，只能带 `parameters`** —— 这一条决定了下面
  §2 的 `clashAction` 约定。
- 动态快捷方式：`@ohos.bundle.shortcutManager`（API 20+）与 `ShortcutInfo`
  （「应用 module.json5 配置文件中定义的快捷方式信息，可以通过
  `getAllShortcutInfoForSelf` 接口获取」）。公开接口只有查询和
  `setShortcutVisibleForSelf()` 显隐，**没有动态创建/更新快捷方式的接口**；
  HMS 的 `productViewManager.checkPinShortcutPermitted()` /
  `requestNewPinShortcut()` 只能请求用户把静态快捷方式钉到桌面。
- 启停：`/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/api/@ohos.net.vpnExtension.d.ts`
  —— `startVpnExtensionAbility(want)` / `stopVpnExtensionAbility(want)`；
  另有 `createVpnObserver()`，但它的 `VpnObserver` **只报告用户对授权弹窗的答复**，
  没有任何「当前是否在运行」的查询接口（见 §3）。

---

## 2. 改了什么

| 文件 | 内容 |
|---|---|
| `entry/src/main/resources/base/profile/shortcuts_config.json` | **新增**。三条静态快捷方式 `clash_toggle` / `clash_start` / `clash_stop`，label 复用 Android 的 `shortcut_*_short`，图标复用转换过来的 `ic_baseline_swap_vert` / `ic_baseline_flash_on` / `ic_baseline_stop`；每条 `wants` 指向 `EntryAbility` 并带 `parameters.clashAction = "toggle" \| "start" \| "stop"` |
| `entry/src/main/module.json5` | `EntryAbility` 增加 `metadata: [{ "name": "ohos.ability.shortcuts", "resource": "$profile:shortcuts_config" }]`。`requestPermissions` 未动（仍然是 `INTERNET` + `GET_BUNDLE_INFO`） |
| `entry/src/main/ets/backend/ExternalControl.ets` | ① `parse()` 先看 `clashAction` 参数，再看 `action`；② 新增 `clash://toggle` / `clash://start` / `clash://stop` 三个 URI host；③ 三个动作从 `notPorted()` 换成真实的 `startVpnExtensionAbility` / `stopVpnExtensionAbility`，并给出 `external_control_started` / `external_control_stopped` toast（沿用 Android 的字符串）；④ 文件头那段「无法表示启停」的注释已改写 |
| `entry/src/main/ets/backend/VpnRuntime.ets` | **新增**。`markVpnRunning()` / `isVpnRunning()`，用 `<filesDir>/vpn.running` 这个标记文件回答「隧道在不在跑」 |
| `entry/src/main/ets/vpnextension/ClashVpnExtension.ets` | core 接管 TUN fd 成功后写标记；attach 失败与 `onDestroy` 清标记 |

### 四种入口形态

Android 的动作名原样保留，另外补两条 HarmonyOS 才需要的形态：

```
action = com.github.metacubex.clash.meta.action.TOGGLE_CLASH / START_CLASH / STOP_CLASH
         -> 真实启停（保留，用于命令行与第三方调用方）
uri    = clash://toggle | clash://start | clash://stop
         -> 同上（-A ohos.want.action.viewData -U clash://toggle 可用）
want.parameters['clashAction'] = "toggle" | "start" | "stop"
         -> 静态快捷方式走这条；必须先于 action 判断，因为快捷方式的 want
            本身不带 action（部分桌面还会补 ohos.want.action.home）

service card message = "clash:toggle" | "clash:start" | "clash:stop"
         -> 服务卡片走这条；由 EntryFormAbility.onFormEvent() 直接调用
            vpnExtension，不经过 EntryAbility
```

`clashAction` 的值只接受这三个小写词，其余值返回 `null`，也就是退回普通启动
Index 的路径 —— 与「没有 action 就不是这个入口」的既有约定一致。

---

## 3. 「在不在跑」这个问题

Android 用 `StatusClient(this).currentProfile()`。HarmonyOS 没有对应接口，所以
`ClashVpnExtension` 自己发布状态：core 成功接管 TUN fd 后创建
`<filesDir>/vpn.running`，`onDestroy` 删除它；`ExternalControl` 的 toggle 分支读它
决定这次是 start 还是 stop。

为什么用文件而不是 `PersistenceV2`：VPN 扩展跑在独立进程
（hilog 里是 `com.example.clashmeta:vpn`），而 `PersistenceV2` 是**按进程缓存**的，
UI 进程会一直读到自己那份过期副本。文件在同一个应用沙箱里，跨进程可见 ——
实测 UI 进程确实读到了扩展写下的标记。

已知边界（写在源码注释里，不藏）：`aa force-stop` 会杀掉扩展进程而不触发
`onDestroy`，标记可能残留。所以 toggle 把「标记存在」当作提示而不是真理，start
路径本身也是幂等的（对已在运行的扩展再调 `startVpnExtensionAbility` 会失败，调用方
容忍这种失败）。

---

## 4. 缺口处理

### 4.1 快捷设置磁贴（`TileService`）—— 用服务卡片替代

Android 的 `TileService` 是一个 `BIND_QUICK_SETTINGS_TILE` 服务，`onClick()` 里
按 `qsTile.state` 调 `startClashService()` / `stopClashService()`，并监听四个广播
刷新磁贴图标。HarmonyOS 的下拉控制中心不向三方应用开放磁贴注册；公开的等价能力是
**服务卡片**（`FormExtensionAbility` + 卡片 UI）。本端口现在实现了一个 2x4
卡片：`entry/src/main/ets/widget/pages/ClashCard.ets` +
`entry/src/main/ets/entryformability/EntryFormAbility.ets` +
`entry/src/main/resources/base/profile/form_config.json`。

卡片按钮通过 `postCardAction(..., { action: 'message' })` 进入
`onFormEvent()`，由卡片提供方直接调用 `@ohos.net.vpnExtension` 控制
`ClashVpnExtension`，并复用主界面的 `vpnTunnelParameters()` / 活动 profile。
这条路径与磁贴的 `onClick()` 启停语义最接近；详见
`outputs/service-card-harmonyos.md`。

平台风险：表单扩展进程直接启动 VPN 扩展、以及在该进程读取
`PersistenceV2` 中的 profile/网络设置，都需要真机确认；如果失败，备选方案是卡片
改为 `router` 事件拉起 `EntryAbility`，走已验证的 `ExternalControl`。

### 4.2 拨号盘密令（`DialerReceiver`）—— 不移植

`android_secret_code://252746382` 是 Android 专有的 `SECRET_CODE` 广播约定，
HarmonyOS 没有对应的公开通道。App 设置页里那行「隐藏应用图标」的副标题仍写着
`*#*#252746382#*#*`（它是 Android 字符串的直接翻译），这一行本身也还是
`not_ported`（见 PORT-STATUS §13）。

### 4.3 「隐藏图标时跳过快捷方式」没复现

Android 的 `setupShortcuts()` 开头是 `if (uiStore.hideAppIcon) return` —— 图标被隐藏
时干脆不注册快捷方式。本端口是**静态**声明，安装即存在，没有复现这条开关。
HarmonyOS 有对应的隐藏接口（`@ohos.bundle.shortcutManager` 的
`setShortcutVisibleForSelf`），但 App 设置页的「隐藏应用图标」本身还没有实现，
现在接上去只会给一个不工作的开关再加一个不工作的副作用。留待那条设置被移植时一起做。

---

## 5. 真机验证（已做）

设备：HUAWEI Pocket 2，API 26；HAP 已重新构建（`BUILD SUCCESSFUL`）并安装。

| 检查项 | 命令 / 操作 | 结果 |
|---|---|---|
| 快捷方式注册进包 | `bm dump -n com.example.clashmeta` | 出现 `"name": "ohos.ability.shortcuts"` / `"resource": "$profile:shortcuts_config"` |
| 配置进了 HAP | 解包 `entry-default-signed.hap` | 含 `resources/base/profile/shortcuts_config.json`，`module.json` 的 ability `metadata` 正确 |
| 桌面长按图标 | 桌面长按 `com.example.clashmeta` 图标 | 弹出 **「切换 Clash」「启动 Clash」「停止 Clash」** 三项（中文，说明 zh 资源里本来就有 Android 的 `shortcut_*_short`），图标正常渲染 |
| 点「启动 Clash」 | 点快捷方式 | 隧道真的起来：`ifconfig` 出现 `vpn-tun inet addr:172.19.0.1 Mask:255.255.255.252 MTU:9000`，且 `<filesDir>/vpn.running` 被创建 |
| `clashAction stop` | `aa start … --ps clashAction stop` | `vpn-tun` 消失、标记文件被删除 |
| `clashAction toggle`（冷启动） | `aa force-stop` 后 `aa start … --ps clashAction toggle` | 第一次点击就起来（走的是 onCreate → 排队 → `setReady()` 派发这条冷启动路径） |
| 再 toggle 一次 | 同上再发一次 | 按标记判定为「在跑」，执行停止：`vpn-tun` 消失、标记删除 |
| `ACTION_TOGGLE_CLASH` | `aa start … -A com.github.metacubex.clash.meta.action.TOGGLE_CLASH` | 起 → 再发一次 → 停，与 URI 形态行为一致 |
| `clash://toggle` | `aa start … -A ohos.want.action.viewData -U clash://toggle` | 冷启动可用，隧道起来 |

每次测试结束后都用 `clashAction stop` + `aa force-stop` 收尾，设备上没有留下
`vpn-tun`，也没有留下标记文件。

### 一个实测踩到的坑（记录以免后来者重踩）

重新安装 HAP 之后的**第一次** `startVpnExtensionAbility` 可能因为授权弹窗而静默不
生效：同一条命令当时没有任何反应，隔一次再发就正常了。判断「快捷方式坏了」之前先
确认 VPN 授权还在，并注意系统弹窗需要人工点「允许」。

---

## 6. 未验证 / 待办

1. **动态快捷方式没有公开创建 API**。现在三条是静态声明，安装即出现；
   `@ohos.bundle.shortcutManager`（API 20+）只能查询/显隐已有条目，
   HMS `productViewManager` 只能请求用户钉住静态条目。Android 那种
   `setDynamicShortcuts()` 任意创建/更新不移植；见 §4.3。
2. **桌面上的第 4 个位置**。平台上限是 4 条，本端口只声明 3 条；Android 的
   `setRank(0/1/2)` 顺序在 HarmonyOS 里由数组顺序体现，实测顺序与声明一致。
3. **`onNewWant` 的 URI 形态在热启动下**没有单独复测（冷启动已验；`ACTION_*` 热启动
   已验）。既有 §19.1 的 `onNewWant` 结论仍然成立。
4. **服务卡片**（磁贴的等价物）已实现，静态验证通过；真机上的
   `FormExtensionAbility -> startVpnExtensionAbility` 链路仍需主线验证。
5. 快捷方式点击后**没有拉起任何界面**（与 Android 的
   `FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS` / 无界面 Activity 语义一致）：点击
   「启动 Clash」会启动 `EntryAbility`（因为快捷方式的 want 指向它），主界面会被带到
   前台。Android 那边是走一个 translucent Activity，视觉上几乎无感。如果希望完全不
   打扰当前前台应用，需要把快捷方式指向一个独立的无界面 Ability —— 那是一个新的
   ability 声明，本轮没做。
