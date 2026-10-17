# ClashMetaHarmony 点击行为修复（子 agent D）

输入：`outputs/click-audit.md`（子 agent B 的审计）。
项目：`outputs/ClashMetaHarmony`。

范围：只修「点击无响应 / 点击反馈错误」里可独立处理的部分，即审计里的
**B1 / B2 / B8**。不碰 `AccessControlPage`、`InstalledApps`、`ProfileFiles`、
`ProfilesPage`、`PropertiesPage`、`ClashVpnExtension`、`EntryAbility`、`cpp/`、
CMake、`module.json5`。

**未做**：没有跑 hdc / 设备命令，没有跑完整构建。验证只到静态层（见文末）。

---

## 1. 改动文件与行为变化

### 1.1 `entry/src/main/ets/view/PreferenceSwitch.ets`（B1 组件侧）

**行为变化**

- 新增 `@Event onDisabledTap`。`onClick` 现在按 `rowEnabled` 分流：
  启用 → `onAction()`；禁用 → `onDisabledTap()`。
  与 `ActionLabel`（`view/ActionLabel.ets`）和 `PreferenceList`
  （`view/PreferenceList.ets`）的写法对齐。
- 修掉审计里的「定时炸弹」：以前 `rowEnabled: false` 的行照样会调 `onAction`，
  将来谁写「禁用行 + 真行为」就会被点活；现在禁用行永远走不到 `onAction`。
- 头部注释补了一段说明禁用态语义。

**注意（迁移影响）**：这是一次 API 语义收紧，所有 `rowEnabled: false` 的调用点
必须改用 `onDisabledTap`，否则那一行会从「弹 toast」变成「真的没反应」。
仓库里 10 个调用点已全部改完（见 1.2 / 1.3），`rg -n "rowEnabled: false"` 的
每一处现在都紧跟 `onDisabledTap`。

### 1.2 `entry/src/main/ets/pages/NetworkSettingsPage.ets`（B1 调用点，**必要连带改动**）

**行为变化**：6 个 VPN 开关（`route_system_traffic` / `bypass_private_network` /
`dns_hijacking` / `allow_bypass` / `allow_ipv6` / `system_proxy`）的
`onAction: () => this.unavailable()` 改成 `onDisabledTap: () => this.unavailable()`。
**用户可见行为不变**（点了还是弹 `not_ported`），只是接上了新的禁用态通道。

> 该文件不在任务给的 4 文件白名单里，但不改它就是纯回归（禁用行会变哑巴），
> 所以属于「必要连带改动」。改动只落在 6 个开关的 `onAction:` → `onDisabledTap:`，
> 与其它 agent 正在改的 `access_control_mode` 区域不重叠。

### 1.3 `entry/src/main/ets/pages/AppSettingsPage.ets`（B1 调用点，**必要连带改动**）

**行为变化**：4 个无法移植的开关（`auto_restart` / `hide_app_icon_title` /
`hide_from_recents_title` / `show_traffic`）加 `rowEnabled: false`，回调改成
`onDisabledTap`。

- 之前：画成一个可用的开关，永远是「关」，点了只弹 toast → 用户读到的信息是
  「这个开关坏了」。
- 现在：整行 33% 变淡（`Preference.enabled = false`，与 Android 的禁用行一致），
  点击仍然解释原因。**「不可用」在点之前就能看见。**
- 文件头注释同步更新。

> 同样不在 4 文件白名单里；理由同上。`dark_mode` 那一行是能真正工作的
> `PreferenceList`，没动。

**关于「checked 状态传递」**：审计里那 9～10 个开关在端口里没有任何可读的真值——
它们对应的 Android 能力（`PackageManager.setComponentEnabledSetting`、recents flag、
前台服务通知）在 HarmonyOS 上没有对应 API，`UiStore`（`backend/UiStore.ets`）也只持久化
`darkMode`。所以这一批只能「如实显示为不可用」，不能显示真实开关态。
`PreferenceSwitch` 的 `@Param checked` 本身渲染正常，等将来有了本地内核 / 服务，
把它接到 store 即可，组件侧不用再改。

### 1.4 `entry/src/main/ets/pages/ProxyPage.ets` + `entry/src/main/ets/viewmodel/ProxyViewModel.ets`（B2）

**行为变化**

- `ProxyViewModel` 新增 `canSelect(groupIndex: number): boolean`——判断该组是不是
  `Selector`。原 `select()` 里的 `!group.selectable` 早退**保留**（防御性，程序化调用
  仍然安全）。
- `ProxyPage` 的成员行 `onClick` 改成：
  `canSelect(index)` → `select(index, node.name)`；否则
  `showToast($r('app.string.not_selectable'))`。
- 之前：点 URLTest / Fallback 组的成员**完全没反应**（有手势，但处理器静默 `return`）。
- 现在：明确提示「不可选择」（`not_selectable`，7 个语言包都有译文）。
- 页面头注释补了这条规则。

**与 Android 的偏差**：Android `ProxyView` 对非 Selector 组**根本不挂监听**，
点了就是没反应；端口按用户要求改成「给一句反馈」。属于有意偏差，已在注释里写明。

### 1.5 `entry/src/main/ets/pages/SettingsPage.ets`（B8）

**行为变化**

- 新增 `private requestBack()` 与 `onBackPress()`。
- 外部控制器编辑面板打开时（`editing === true`）：
  - 工具栏返回箭头 → 取消编辑（丢掉草稿）并**留在本页**，与面板自带的 Cancel 一致；
  - 系统返回手势 → 同上，返回 `true` 消费掉这次返回。
- 之前：箭头直接 `router.back()`，且本页没有 `onBackPress`——输入到一半返回 =
  静默丢草稿并离开页面。
- 编辑面板没打开时行为完全不变（`router.back()`）。

**为什么是「取消」而不是「确认弹窗」**：审计给的两个选项里，取消 + 留在本页改动最小、
不会引入新对话框状态；`PropertiesPage` 那套「脏检查 + 确认框」是因为它整页都是表单，
这里只有一个两字段的小面板。若要改成「返回即保存」也可以，但那是产品决定，没有默认做。

---

## 2. 静态验证

工具：`hmos-precheck`（`--profile arkts-diff`，arkts standalone，mode=full）。

```
success: true, tool_status: ok
checked_files: 64
summary: { "errorCount": 0, "warnCount": 206 }
```

- **0 error**，覆盖全部 64 个 `.ets`（含本次改动的 6 个文件，以及其它 agent 新增的
  `backend/AccessControlPrefs.ets`）。
- 本次改动的文件只剩既有的良性 warning：`SettingsPage.ets:107` / `ProxyPage.ets:292`
  的 `'back' has been deprecated`（`router.back()`，全仓库通病），
  `ProxyViewModel.ets` 与 `PreferenceSwitch.ets` 零 warning。
- precheck 顶层 `ok:false` 是环境问题，**与本改动无关**：
  `kind: backend-unavailable`（"permission catalog unavailable; permission rules not
  checked"），即已知缺陷 #4；arkts 子检查本身跑通且 success。

**未验证（需要主 agent 统一构建 + 真机）**：

- 没有跑 `u build`（按分工留给主 agent）。
- 没上设备。以下都只有静态依据：
  - 开关行的 33% 变淡 + toast（`AppSettingsPage` / `NetworkSettingsPage`）；
  - 非 Selector 组点成员弹 `not_selectable`；
  - `SettingsPage` 编辑态按返回只收起面板、不离开页面，且草稿确实被丢弃；
  - 系统返回手势是否真被 `onBackPress` 拦到（ArkUI V2 上 `@Entry` 的
    `onBackPress` 已在 `PropertiesPage` / `OverrideSettingsPage` / `AccessControlPage`
    上验证过可用，本页是同一写法）。
- 需要真机确认的一个细节：`Toggle` 在 33% 透明度的行里视觉上是否仍像「可点」——
  如果不像，可以考虑给 `PreferenceSwitch` 的 Toggle 加 `.enabled(this.rowEnabled)`
  （本次没加，避免和 `hitTestBehavior(HitTestMode.None)` 的既有行为打架）。

---

## 3. 本次**没有**处理的审计项（留给后续 agent）

| 审计项 | 位置 | 为什么没做 |
|---|---|---|
| A1 应用包列表恒为空 | `AccessControlPage.ets` / `InstalledApps.ets` | 明确不在本 agent 写入范围；且需要「区分被拒 vs 真的空」的返回值改造 |
| A2 溢出菜单只做 1/11 | `AccessControlPage.ets` | 同上（另一个 agent 已在动该文件，见 §4） |
| A3 勾选结果无消费者 | `AccessControlPage.ets` / `NetworkSettingsPage.ets` | 同上；但 `NetworkSettingsPage` 的 `access_control_mode` 已被另一个 agent 改成真·持久化列表 |
| B3 日志历史永远为空 | `LogsPage.ets` / `LogsViewModel.ets` | 不在写入范围；建议按审计：要么页面加一行「当前没有日志写入者」，要么接 `GET /logs`（mihomo SSE） |
| B4 空菜单的 more-vert 死按钮 | `FilesPage.ets:477-497` | 不在写入范围；一行改动（`.opacity(0.33)` 或干脆不画），低风险，可派给任何 agent |
| B5 MetaFeature 两个 age key 行 | `MetaFeatureSettingsPage.ets:84-90` | 不在写入范围；可选把 `rowEnabled` 设 false 统一观感 |
| B6 ProfilesPage Update/UpdateAll/ShareQrCode | `ProfilesPage.ets` | 明确排除 |
| B7 AppSettingsPage 三开关「只报 not_ported」 | `AppSettingsPage.ets` | **本次已顺带解决**：它们现在画成禁用态（见 1.3） |

## 4. 并发写入提示

改到一半时发现 `NetworkSettingsPage.ets` 被**另一个 agent 同时修改**：
`access_control_mode` 行从「禁用 + 写死 AcceptAll」改成了真·持久化的
`PreferenceList`（新增 `backend/AccessControlPrefs.ets`、`AccessControlModeStore`、
`accessControlModeMenu()`）。两边改动区域不重叠，合并后文件是完整的
（6 个开关的 `onDisabledTap` + 新的 `access_control_mode` 菜单都在）。
主 agent 合并 / 构建时留意这一处即可。

---

# ClashMetaHarmony 点击行为修复（子 agent E）

输入：`outputs/click-audit.md`（子 agent B 的审计）+ 上面子 agent D 的修复记录。
项目：`outputs/ClashMetaHarmony`。

范围：审计里**剩下且不与已完成工作冲突**的三项 —— **B3**（`LogsPage` 历史列表永远为空）、
**B4**（`FilesPage` 空菜单的 more-vert 死按钮）、**B5**（`MetaFeatureSettingsPage`
两个 age key 行）。A1/A2/A3 已由访问控制那个 agent 处理，B1/B2/B7/B8 已由子 agent D 处理，
B6（`ProfilesPage`）已被 profile-fetch agent 接上真实拉取，均未重复触碰。

**未做**：没有跑 hdc / 设备命令，没有跑完整构建。验证只到静态层（见文末）。

## 1. B3 `LogsPage` / `LogsViewModel`：选「诚实降级」，不造假写入者

审计给了二选一：补一个最小可用的本地日志落盘路径，或者把页面降级成「当前没有本地日志」
并移除假入口。**选后者**，理由写在代码注释里也写在这里：

Android 的 `cacheDir/logs` 由 `LogcatService` 写，而 `LogcatService` 是「前台服务 +
订阅进程内 mihomo 内核日志流」这一对东西（`LogcatService.kt:86-126`）。HarmonyOS 没有
三方应用可用的 HiLog 读取 API，也没有对应的内核订阅，
`outputs/logcat-streaming-harmonyos-feasibility.md` 的结论是「不要加假 streaming、
不要轮询空目录冒充实时输出」。所以：

- **不写**任何 stub writer。往 `cacheDir/logs` 里写本 App 自己的 HTTP 请求流水，再让它
  出现在名为 `clash-<ts>.log` 的历史里，只会把「这页是假的」往后挪一层 —— 那不是我
  该做的「最小可用」，是伪装。
- 页面改为**如实说明**：空历史时画一条空态，而不是 `design_logs.xml` 那种留白列表。

**行为变化**

| 位置 | 之前 | 现在 |
|---|---|---|
| `Clash Logcat` 行 | 副标题 `tap_to_start`（承诺一个起不来的会话），满不透明，点了弹 `not_ported` | 副标题 `unavailable`，整行 33% 变淡（`Preference.enabled = false`），点击走 `onDisabledTap` 弹 `not_ported` |
| History 列表 | 目录空时是一片白，和「页面坏了」不可区分 | `files.length === 0` 时显示空态：`empty` + 新增的 `logs_empty_tip`（说明没有写入者、实时流未移植） |
| 有文件时 | 列表 + 点行进 `LogcatPage` | **完全不变**（读取/删除/导出都是真的） |

`Clash Logcat` 行选择**保留但置灰**，而不是删掉：删掉会让「为什么没有日志」这个信息
一起消失，而灰行点击仍然给出解释；副标题不再是 `tap_to_start`，就不再是「假入口」了。
如果主 agent 更想直接删这一行，改动只有一处 `if`，见文件内注释。

**改动文件**

- `entry/src/main/ets/pages/LogsPage.ets`（头部注释 + Clash Logcat 行 + 空态分支）
- `entry/src/main/ets/viewmodel/LogsViewModel.ets`（头部注释；`reload` / `deleteAll`
  逻辑一行未动 —— 它们本来就是对的）
- `entry/src/main/resources/base/element/string.json`（新增 1 条 `logs_empty_tip`，
  **base only**，其它语言回落；与访问控制那次 `access_control_*` 同一做法）

## 2. B4 `FilesPage`：空菜单的 more-vert 图标画成禁用态

`itemMenu(entry).length === 0` 时（root 的 `config.yaml` + Url profile 没有任何可用项）
图标原本满不透明、且不挂 `bindMenu`（`bindMenu([])` 会盖白屏，这个坑不能踩）。

**改动**：该分支加 `.opacity(0.33)`，其余不动。Android 的布局是「槽位永远在」，
所以不删图标；但满不透明时它读起来像个菜单按钮，点下去却只是把事件透给整行去打开文件。
33% 是 Android `Preference.enabled = false` 的同一个视觉语言，能在点之前说明「这里没有菜单」。

**改动文件**：`entry/src/main/ets/pages/FilesPage.ets`（1 行 + 注释）。

## 3. B5 `MetaFeatureSettingsPage`：两个 age key 行的点击反馈说清原因

两行是 `OverrideKind.Action`，点击落到页面 `action()`，之前统一弹 `not_ported`。

**改动**：弹新字符串 `age_key_not_supported`
（"Age key generation needs the Clash core, which this port does not have"）。
`not_ported` 的问题不是不诚实，是太笼统：这行等的不是「以后再补个界面」，而是
`Clash.genX25519KeyPair` / `genHybridKeyPair` 这些原生 age helper（hybrid 的
MLKEM768-X25519 更是内核侧原语）。另外顺手改掉了文件头一段已经过期的注释 —— 它写着
「这个端口根本不 fetch profile」，而 `backend/ProfileFetch.ets` 已经能下载订阅了；
现在的说法是「能下载，但没有 age 解密步骤，所以生成了密钥也无处可用」。

**为什么没有把这两行直接置灰**：置灰由 `view/PreferenceScreen.ets` 通过
`overrideRowEnabled(data, row)` 决定，行表在 `model/OverrideModels.ets`；两者都不在本次
写入范围。`dependsOn` 也走不通 —— 它读的是「值为 `'false'`」，给 age 行造一个合成键会
把假键写进持久化 override 记录并让页面一打开就是 dirty。留给主 agent 决定是否要
把 `age_key.*` 的 enabled 语义做进 `OverrideModels`。

**改动文件**：`entry/src/main/ets/pages/MetaFeatureSettingsPage.ets`（1 处 toast + 注释）、
`entry/src/main/resources/base/element/string.json`（新增 1 条 `age_key_not_supported`，
**base only**）。

## 4. 写入范围说明（必要偏离）

任务给的白名单是 5 个 `.ets` + 必要的 backend + 本文档。实际多改了
`entry/src/main/resources/base/element/string.json`，加 **2 条 base-only 字符串**：

- `logs_empty_tip`、`age_key_not_supported`

理由：B3 的空态和 B5 的说明都需要一句新文案；仓库既有做法就是「base 加键、其它语言回落」
（访问控制那批 `access_control_*` 就是这么加的，base 8 条 / 其它语言 3 条）。
只改 base，未碰任何 `zh*` / `ja_JP` / `ko_KR` / `ru` / `vi`，也没有动
`module.json5`、`AccessControlPage` / `InstalledApps`、`NetworkSettingsPage`、
`ProxyPage` / `ProxyViewModel`、`ClashVpnExtension`、`EntryAbility`、`cpp/`、CMake。

## 5. 静态验证

工具：`hmos-precheck`（`--profile arkts-diff`，arkts standalone，mode=full）。

```
summary: { "errorCount": 0, "warnCount": 206 }
checked_files: 64
```

- **0 error**。本次改动的 4 个 `.ets` 只剩仓库通病 warning
  （`'back' / 'getContext' / 'pushUrl' / 'showDialog' has been deprecated`、
  `Function may throw exceptions`），`LogsViewModel.ets` 零 warning。
- 顶层 `ok:false` / `tool_status: unavailable` 是已知环境缺陷 #4
  （`permission catalog unavailable; permission rules not checked`），与本次改动无关。
- 顺带复核（避免后续 agent 重复排查）：全项目已无空 `onClick` 体；
  `bindMenu` 的 6 个挂点里，`PreferenceList` 用 `rowEnabled` 内部守卫、`FilesPage` 用
  `if (length > 0)` 守卫，`ProxyPage` / `AccessControlPage` / `ProfilesPage` /
  `AppSettingsPage` 的菜单数组都是固定非空构造。空 `MenuElement[]` 盖白屏这个坑没有新增暴露面。

## 6. 未验证（需要主 agent 统一构建 + 真机）

没有跑 `u build`，没上设备。以下都只有静态依据：

- `LogsPage` 空态是否按预期显示（`files.length === 0` 分支、居中与留白）；
- `Clash Logcat` 行 33% 变淡 + 点击弹 `not_ported`；
- `FilesPage` 空菜单图标 33% 变淡，且点它仍然透给整行打开文件（Android 同行为）；
- `MetaFeatureSettingsPage` 两个 age 行弹新文案；
- 新增两条 base 字符串在真机上被 `$r('app.string.…')` 解析（`string.json` 已用
  `json.load` 校验，327 条 = 原 325 + 2，格式合法）。

**仍然没有日志写入者**：这是本次的有意结论，不是待办。真机打开 Logs 页应当看到
空态文案 + 灰掉的 `Clash Logcat` 行，而不是空列表。
