# ClashMetaHarmony 点击行为审计（子 agent B）

范围：`outputs/ClashMetaHarmony` 里设置 / 网络 / 代理 / 配置文件等页面的「点击无响应」
或「点了没效果」。方法：静态审计每个可点击行 / 按钮的 `onClick`（含 `bindMenu`、
`@Event` 转发、`@Builder`、`ForEach` key、`disabled` 分支），对照 `work/clashmeta`
（CMFA v2.11.35）的 Design / Activity / layout，必要时查本地 HarmonyOS SDK。

**未做**：没有跑 hdc / 设备命令，没有跑构建。所有「设备上的实际表现」结论都引用
`ClashMetaHarmony-PORT-STATUS.md` 里已有的真机记录，其余标为「待真机确认」。

分类记号（每个 finding 都会标）：

- **A 无处理器**：行/按钮画出来了，但没有任何手势或 `bindMenu`。
- **B 静默 no-op**：有 `onClick`，但处理器提前 `return`，界面上没有任何反馈。
- **C 只报 `not_ported`**：有反馈（toast），但 Android 那边是真行为。
- **D 无视觉变化**：处理器真的改了状态，但画面不会变，看起来像没响应。

---

## 摘要

| # | 位置 | 症状 | 分类 | 严重度 |
|---|---|---|---|---|
| A1 | `AccessControlPage` 应用包列表 | 列表恒为空；用户点进去只看到 `empty` 文案，没有任何解释 | A/C | **高** |
| A2 | `AccessControlPage` 溢出菜单 | 只有「系统应用」一项；Android 的全选/全不选/反选、排序、反序、剪贴板导入导出全缺 | A | **高** |
| A3 | `AccessControlPage` 勾选后的效果 | 选择能落盘，但没有任何消费者；退出时只弹 `not_ported` | C | 中 |
| B1 | `PreferenceSwitch`（App 设置 / 网络设置 共 9 行） | 开关永远画成「关」，点了也不动；`rowEnabled=false` 时仍会走 `onAction` | D | 中 |
| B2 | `ProxyPage` 非 Selector 分组的成员行 | 有 `onClick` 但 `select()` 直接 `return`，无任何反馈 | B | 中 |
| B3 | `LogsPage` 日志历史 | 没有任何写入者，页面永远空；「Clash Logcat」行只报 `not_ported` | C/A | 中 |
| B4 | `FilesPage` 空菜单的 more-vert 图标 | 图标画出来了但完全不参与命中测试 | A | 低 |
| B5 | `MetaFeatureSettingsPage` 两行 age key | 只报 `not_ported`（JNI 缺） | C | 低（已记录） |
| B6 | `ProfilesPage` Update / UpdateAll / ShareQrCode | 只报 `not_ported` | C | 低（已记录） |
| B7 | `AppSettingsPage` 3 个开关 | 只报 `not_ported`（平台无对应 API） | C | 低（已记录） |
| B8 | `SettingsPage` 编辑态直接返回 | 工具栏返回箭头不走 `onBackPress`，草稿静默丢弃 | D | 低 |

审计后判定**正常**的点击（避免误报，见文末附录）：主界面 8 个入口、代理页 tab/节点/
溢出菜单/测速、配置文件页卡片与菜单、Providers 刷新、Properties 四个输入行、
Help / ApkBroken 外链、覆盖设置页（Override / MetaFeature）的全部行与对话框、
FilesPage 的行与菜单。

---

## A1. `AccessControlPage` 应用包列表恒为空（高）

用户的原话就是这一条：「设置网络里的访问控制应用包列表就没有实现」。

**预期**（Android）：`AccessControlActivity.loadApps()` 用
`PackageManager.getInstalledPackages(GET_PERMISSIONS)` 枚举已安装应用，过滤掉自己、
过滤掉不申请 `INTERNET` 且非系统的包，按「已选优先 + 排序键」列出
（`work/clashmeta/app/src/main/java/com/github/kr328/clash/AccessControlActivity.kt:120-150`）。

**现状**：端口用 `bundleManager.getInstalledBundleList()` 枚举，而该 API 需要
`ohos.permission.ENTERPRISE_GET_INSTALLED_BUNDLE_LIST`，其 `availableLevel` 是
`system_basic`——普通三方应用拿不到。查询抛 201，被 catch 成空数组，页面渲染
`$r('app.string.empty')`。真机记录也确认列表为空
（`ClashMetaHarmony-PORT-STATUS.md` §20.3「本机确实拿不到别的 bundle」）。

**证据**

- 端口：`outputs/ClashMetaHarmony/entry/src/main/ets/backend/InstalledApps.ets:114-165`
  （`:119` 是 `getInstalledBundleList` 调用，`:161-164` 把任何异常吞成 `[]`）。
- 端口：`entry/src/main/ets/pages/AccessControlPage.ets:100-116`（`loadApps`）、
  `:272-292`（`loading` / 空态分支，空态用的是通用 `empty`）。
- SDK：`/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/api/@ohos.bundle.bundleManager.d.ts:2064-2076`
  —— `@permission ohos.permission.ENTERPRISE_GET_INSTALLED_BUNDLE_LIST`。
- SDK 权限级别：`/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/PermissionDefinitions.json`
  —— `ohos.permission.ENTERPRISE_GET_INSTALLED_BUNDLE_LIST → availableLevel: system_basic`。
- 同级备选也都不行：`GET_BUNDLE_INFO` / `GET_BUNDLE_INFO_PRIVILEGED` /
  `GET_ABILITY_INFO` / `GET_INSTALLED_BUNDLE_LIST` 全是 `system_basic`，且
  `getBundleInfo` 的注释明说「The application requires to be a system application」。
  本 SDK 里也**没有** `getAllBundleInfo`。即：**平台没有给三方应用枚举其它包的公开 API**。
- 端口 `entry/src/main/module.json5:13-20` 只申请了 `ohos.permission.INTERNET`。

**为什么这算「没实现」而不是「权限被拒」**：枚举失败和「这台机器真的没装应用」被折叠成
同一个空数组，页面只画一个 `empty`。用户看不到任何原因，也做不了任何事——这是关键
问题，权限本身反而没法绕过。

**建议修法**（按性价比排序，前两条建议同批做）

1. **让空态说实话**。给 `loadInstalledApps` 一个能区分「被拒」和「真的空」的返回值，
   例如

   ```ts
   export interface InstalledAppsResult {
     apps: AccessControlApp[];
     /** true 表示 bundle 查询被拒 / 抛异常，list 为空不代表没有应用 */
     unavailable: boolean;
   }
   export async function loadInstalledApps(selfBundleName: string): Promise<InstalledAppsResult>
   ```

   页面在 `unavailable` 时显示一条专门的文案（可以先用现成的
   `app.string.options_unavailable`，或者新增一条 base-only 字符串），而不是
   `app.string.empty`。顺手在 catch 里加一行 `hilog`，真机上就能直接看到错误码 201。

2. **补上剪贴板导入 / 导出**（Android 本来就有，见 A2）。这条是让功能**真的能用**的
   关键：选择集合（`AccessControlStore.encoded`）和列表是解耦的，手工粘贴一串包名就能
   把访问控制配好，完全不需要枚举权限。所需字符串
   `import_from_clipboard` / `export_to_clipboard` 已在
   `entry/src/main/resources/base/element/string.json` 里存在。
   Android 的 Import 会与已装应用求交集（`AccessControlActivity.kt:89-102`）；枚举不可用
   时端口应当**跳过求交集**，原样接受（并在注释里写明这是偏差）。

3. 可选的第三条：溢出菜单加「手动添加包名」，弹一个 `TextInputDialog`。工作量比前两条
   大，可以缓。

4. 只做 UI 侧的收尾：既然枚举拿不到，就应该把「已选但不在列表里」的包名单独列出来
   （或者至少显示已选数量），否则第 2 条导入进去的选择在界面上仍然不可见。

---

## A2. `AccessControlPage` 溢出菜单只实现了 1/11 项（高）

**预期**（Android）：`menu_access_control.xml` 有 11 个条目——
全选 / 全不选 / 反选；筛选（系统应用，checkable）；排序（名称 / 包名 / 安装时间 /
更新时间，单选）＋反序（checkable）；外部（从剪贴板导入 / 导出到剪贴板）。
见 `work/clashmeta/design/src/main/res/menu/menu_access_control.xml:3-55`，
行为在 `design/src/main/java/com/github/kr328/clash/design/component/AccessControlMenu.kt:29-71`，
执行在 `app/src/main/java/com/github/kr328/clash/AccessControlActivity.kt:61-114`。

**现状**：只有「系统应用」一项，且没有勾选态（Android 的 `system_apps` 是 checkable，
`AccessControlMenu.kt:92` 初始化 `isChecked = !accessControlSystemApp`）。

**证据**

- 端口：`entry/src/main/ets/pages/AccessControlPage.ets:214-225`（`systemMenuItems()` 只返回
  一个元素）、`:259-265`（`bindMenu`）。
- 端口：`entry/src/main/ets/model/AccessControlModels.ets:47-53` 声明了
  `AccessControlSort` 枚举但全项目无人使用（排序在页面里被硬编码，见
  `AccessControlPage.ets:185-201`）。
- 文档已承认：`ClashMetaHarmony-PORT-STATUS.md` §20.1 / §20.4「只有 System Apps 一项菜单」。

**为什么值得现在补**：全选 / 全不选 / 反选、排序、反序、导入 / 导出**都不需要枚举权限**
（它们只作用在 `this.apps` / `selectedPackages` 上），所以即使 A1 的权限问题无解，
这几项也能落地；而导入 / 导出正是 A1 的补救手段。

**建议修法**：把 `systemMenuItems()` 扩成完整菜单（`MenuElement[]` 不支持嵌套和勾选态，
沿用本仓库既有做法：用 `markActive()` 前缀 `✓`，参考
`pages/AppSettingsPage.ets:58-89` 的暗黑模式菜单）。

- SelectAll：`selectedPackages = visibleApps().map(packageName)`；SelectNone：清空；
  SelectInvert：`visibleApps() - selected`。三者都调
  `accessControlSetEnabled` 逐个落盘 + `updateChanged()`。
- 排序 / 反序：把 `AccessControlPage.visibleApps()` 的硬编码比较器换成读
  `AccessControlSort` + `reverse` 两个 `@Local`（Android 存在 `UiStore` 里，端口可以只放
  页面状态，或者照 `ProxyUiStore` 加一个 store）。
- Import：`pasteboard.getSystemPasteboard().getDataSync()` 取文本，按 `\n` 切分、trim、
  去空；枚举可用时求交集，不可用时原样接受。
- Export：`pasteboard.createData(MIMETYPE_TEXT_PLAIN, selectedPackages.join('\n'))`
  + `setDataSync`，然后 toast。`pages/LogcatPage.ets:69-74` 已有可抄的写法。

---

## A3. 勾选结果没有任何消费者（中）

**预期**（Android）：退出页面时若选择集合变了且隧道在跑，会
`stopClashService()` → `startClashService()` 让内核重新读白名单
（`AccessControlActivity.kt:30-42`）。

**现状**：`reportRestartIfNeeded()` 只弹 `not_ported`（因为端口没有本地内核）；
`NetworkSettingsPage` 的 `access_control_mode` 行也是禁用态、写死的默认值
（`AcceptAll`），所以「允许/拒绝所选应用」这个语义在端口里根本不存在。选择落盘了，
但没人读。

**证据**：`entry/src/main/ets/pages/AccessControlPage.ets:147-153`、
`entry/src/main/ets/pages/NetworkSettingsPage.ets:56-82`（写死的 `AcceptAll`）、
`:191-200`（禁用的 `access_control_mode` 行）。

**建议**：这是 A1 之外的第二层「没实现」。短期把行为说清楚即可（toast 文案别只写
`not_ported`，写「选择已保存，但没有本地内核可用」）。中期如果要接外部控制器，
`PATCH /configs` 里并没有访问控制字段（见 `ExternalControllerBackend.ets:613-626` 的
说明），所以这一层只能等本地内核。

---

## B1. `PreferenceSwitch`：开关不动 + 禁用态仍触发 `onAction`（中）

**预期**（Android `preference_switch.xml` + `Switch.kt`）：行点击翻转开关，开关显示
持久化的真实值；`enabled=false` 时整行变淡且**不响应**。

**现状**：两个偏差。

1. 所有调用点都没有传 `checked`，默认 `false`，所以 9 个开关（App 设置 4 个 +
   网络设置 5 个）永远画成「关」；点击只弹 toast，开关不动 → 用户看到的是「点了没效果」。
2. `view/PreferenceSwitch.ets:88-90` 的 `.onClick` 里**没有** `rowEnabled` 判断，
   和 `ActionLabel`（`view/ActionLabel.ets:84-90`）、`PreferenceList`
   （`view/PreferenceList.ets:82-102`）的写法不一致；后者都分了
   `onAction` / `onDisabledTap` 两条路。目前每个 `rowEnabled:false` 的调用点都恰好把
   `onAction` 设成了 `unavailable()`，所以还能弹 toast，但这是个定时炸弹：将来谁写
   `rowEnabled:false` + 真行为，禁用行就会被点活。

**证据**：`entry/src/main/ets/view/PreferenceSwitch.ets:29-40`（无 `onDisabledTap` 参数）、
`:84-91`；调用点 `pages/AppSettingsPage.ets:126-174`、
`pages/NetworkSettingsPage.ets:117-178`。

**建议**

- 给 `PreferenceSwitch` 加 `@Event onDisabledTap`，`onClick` 按 `rowEnabled` 分流，
  与另外两个行组件对齐（低风险、纯局部改动）。
- 开关的 `checked` 值：能真读到的（`AppSettingsPage` 的暗黑模式不是开关，跳过）先接上
  store；读不到的保持「关 + toast」，但**至少要能看出来它不生效**——可以考虑把
  `rowEnabled` 设成 `false` 走 33% 变淡，而不是画成可用的开关。这条建议与
  `NetworkSettingsPage` 现有做法一致（那里就是这么处理的）。

---

## B2. `ProxyPage` 非 Selector 分组的成员行是静默 no-op（中）

**预期**（Android）：`ProxyView` 只给可切换的组挂点击（`ProxyViewModel.select` 的
注释里也这么写：「`selectable` 仅决定能否点击」）。

**现状**：端口给**每一行**都挂了 `onClick`，但 `select()` 在 `!group.selectable` 时
直接 `return`，不弹 toast、不改高亮 → 点 URLTest / Fallback 组的成员毫无反应。

**证据**：`entry/src/main/ets/pages/ProxyPage.ets:384-386`（无条件挂 `onClick`）、
`entry/src/main/ets/viewmodel/ProxyViewModel.ets:146-154`（`!group.selectable` 早退）。

**建议**：二选一——(a) 只有 `group.selectable` 时才挂 `onClick`（与 Android 一致，
推荐）；(b) 保留手势但加一句 toast 说明该组由内核自动选择。别保持现状。

---

## B3. `LogsPage` 的历史列表永远为空（中）

**预期**（Android）：`LogcatService` 往 `cacheDir/logs` 写文件，`LogsActivity` 列出来，
点一行进 Logcat 详情。

**现状**：端口读的是同一个目录（`LogsViewModel.reload()`），但**没有任何代码往里写**，
所以「历史」分组永远是空的；「Clash Logcat」行只弹 `not_ported`。

**证据**：`entry/src/main/ets/pages/LogsPage.ets:112-120`、
`entry/src/main/ets/viewmodel/LogsViewModel.ets:36-60`；
书面结论见 `outputs/logcat-streaming-harmonyos-feasibility.md`。

**建议**：这页已经判定为「流式不移植」，但**本地文件模式是能用的**（LogcatPage 的
读取/删除/导出都实现了）。所以要么在页面顶部加一行说明「当前没有日志写入者」，要么
让内核/控制器日志落到该目录（`GET /logs` 是 mihomo 控制器的一个 SSE 接口，值得评估
——它能把这条链路接通，而且不需要本地内核）。

---

## B4. `FilesPage` 空菜单的 more-vert 图标不可点（低）

**现状**：`itemMenu(entry).length === 0` 时仍画一个 more-vert 图标，但不挂
`bindMenu`（这是刻意的——`bindMenu([])` 会盖出一张白屏，见同文件注释）。结果是图标
在视觉上像按钮，点它毫无反应。

**证据**：`entry/src/main/ets/pages/FilesPage.ets:477-497`。

**建议**：Android 侧同样是保留图标、弹一个空 sheet，所以行为上「对齐」，但用户视角是
死按钮。建议改成不画（或用 `.opacity(0.33)` 画成禁用态）——这是纯 UI 偏好，交给实现者
决定，记录在此以免被当成 bug 反复排查。

---

## B5–B7. 只报 `not_ported` 的点击（低，均已在文档里声明）

| 位置 | 行 | Android 行为 | 端口 | 证据 |
|---|---|---|---|---|
| MetaFeature 设置 | 2 个 age key 行 | `Clash.genX25519KeyPair` 等 JNI | toast | `pages/MetaFeatureSettingsPage.ets:84-90` |
| 配置文件 | Update / UpdateAll / ShareQrCode | 拉订阅 + 内核重载 / ZXing 出二维码 | toast | `pages/ProfilesPage.ets:168-191` |
| App 设置 | autoRestart / hideAppIcon / hideFromRecents / dynamicNotification | `setComponentEnabledSetting` / recents flag / 前台通知 | toast | `pages/AppSettingsPage.ets:126-174` |

这四条不是「无响应」——都有 toast。列出来是因为它们和 A3 一样属于「点了但没效果」，
排查时容易被重复怀疑。若要提升观感，可以把这些行的 `rowEnabled` 设成 `false`
（画成 33% 禁用态），让「不可用」在点击前就可见，而不是靠点击后的 toast 解释。

---

## B8. `SettingsPage` 编辑态下返回会静默丢草稿（低）

**现状**：`beginEdit()` 展开外部控制器编辑面板后，工具栏返回箭头直接
`router.back()`，不检查 `this.editing`。`SettingsPage` 没有 `onBackPress`，所以
系统返回手势也不会拦。输入到一半返回 = 静默丢弃。

**证据**：`entry/src/main/ets/pages/SettingsPage.ets:100-102`（返回箭头）、
`:79-89`（`beginEdit` / `save`）。对比 `PropertiesPage.requestBack()`
（`pages/PropertiesPage.ets:157-167`）和 `OverrideSettingsPage.requestBack()`
（`pages/OverrideSettingsPage.ets:93-99`），两处都做了脏检查。

**建议**：`editing` 时返回先 `this.editing = false`（等于取消），或者加确认对话框。
一行改动即可，风险极低。

---

## 共享组件复核（这些坑都已避开，勿回退）

| 已知坑 | 复核结果 |
|---|---|
| `@Builder` 按值传参不刷新 / 其体内手势不触发 | 全部避开：会随状态变化的行都是 `@ComponentV2` 组件（`ActionLabel` / `PreferenceList` / `PreferenceSwitch` / `ActionTextField`）或**无参** `@Builder`（`dialogContent()` / `resetDialog()` / `nameDialog()` / `textInputDialog()` / `overlayContent()`）。`radioButton(active)` 与 `providerRow(...)` 带参，但两者体内都没有手势（点击挂在包一层的容器上）。 |
| `ForEach` key 不带渲染内容 | 全部带：`PreferenceScreen.rowKey`、`AccessControlPage.rowKey`、`ProfilesPage.rowKey`、`FilesPage`（`id\|size\|lastModified`）、`ElementListDialog.rowKey`、`LogcatPage`（`index:time:message`）。 |
| `bindMenu([])` 盖白屏 | `PreferenceList` 的禁用分支不挂 `bindMenu`；`NetworkSettingsPage` 两个 `PreferenceList` 都是 `rowEnabled:false`；`FilesPage` 用 `if (length > 0)` 判断。 |
| 行内容上的 `onClick` 吞掉 `bindMenu` | 所有 `bindMenu` 都挂在最内层的命中组件上（`PreferenceList` 的 `rowContent()` 不带手势；`ProfilesPage` / `FilesPage` 的菜单挂在 `Image` 上，父 `Row` 的 `onClick` 不会抢）。 |
| `router.back()` 不走 `onBackPress` | 有栈状态 / 脏状态的页面都改走 `requestBack()`：`AccessControlPage`、`FilesPage`、`PropertiesPage`、`OverrideSettingsPage`、`MetaFeatureSettingsPage`。**例外见 B8**（`SettingsPage`）。 |
| `Toggle` 吞点击 | `PreferenceSwitch.ets:81` 与 `AccessControlPage.ets:332` 都设了 `hitTestBehavior(HitTestMode.None)`。 |
| `Stack` / `.overlay()` 盖在 `Scroll` 上导致手势全失效 | 全部改用 `bindContentCover`。 |

---

## 附录：审计后判定正常的点击

主界面（`pages/Index.ets`）：共 8 个可点入口 —— 状态卡（连接/断开）、代理卡（仅运行中
显示）、配置文件卡、Providers 标签（`running && hasProviders`）、Logs / Settings /
Help / About 四个标签，另加 About 对话框 —— 全部有真实处理器，跳转目标都存在。

代理页（`pages/ProxyPage.ets`）：返回、Tabs 切换（`onChange` 写 `selectedIndex`）、
Selector 成员选择（`PUT /proxies/{group}`）、测速按钮（工具栏 + 悬浮球，含
`urlTesting` 期间的 spinner 替换）、溢出菜单 10 项（筛选/模式/布局/排序，全部落到
`ProxyViewModel` 的 setter 并 reshape）。**只有 B2 那一处是死点击。**

配置文件页（`pages/ProfilesPage.ets`）：返回、UpdateAll 图标（`canUpdateAll()` 才显示）、
添加、卡片点击（激活 / 未保存提示）、每张卡的溢出菜单（Update/Edit/Duplicate/
ShareQrCode/Delete，条件与 Android 一致）。

Providers（`pages/ProvidersPage.ets`）：返回、`updateAll` 图标、每行的 swap-vert
（`item.updating` 时忽略重复点击，与 Android 一致）。整行不可点是**对齐** Android 的
（`design/.../adapter/ProviderAdapter.kt:58-69` 只给 `endView` 挂监听）。

Properties（`pages/PropertiesPage.ets`）：返回（带脏检查 + 退出确认）、保存、
name / url / age key / interval 四个 `ActionTextField`（`Type.File` 时 url 与 interval
禁用且无反馈 —— 与 Android 的 `app:enabled` 一致）、browse files 跳 FilesPage。

覆盖设置 / MetaFeature 设置（`view/PreferenceScreen.ets`）：工具栏返回与重置、
`Select` 行的 `bindMenu`、`Text` / `List` / `Map` 行的三个对话框（含 Reset / Cancel / OK /
新增元素 / 删除元素）、禁用行的 `options_unavailable` toast —— 全部有处理器。

Files（`pages/FilesPage.ets`）：返回（带目录栈）、新增、行点击（进目录 / 外部打开）、
非空菜单（Import/Export/Rename/Delete）。Help / ApkBroken 的外链行走
`openInBrowser()`，失败会 toast 出错误消息。

Logs / Logcat：返回、删除全部（带确认对话框）、文件行、Logcat 的删除 / 导出、
长按复制（`LongPressGesture` 挂在行内容上）。
