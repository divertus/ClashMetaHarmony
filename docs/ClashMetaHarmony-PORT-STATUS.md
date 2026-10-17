# ClashMeta → HarmonyOS 移植状态

日期：2026-10-17
工具链：HomeTrans v0.1.20（SMAT/HomeTrans）+ DevEco CLI 1.3.5 + DevEco Studio（API 26 / HarmonyOS 26.0.0 Beta1）
源工程：<https://github.com/MetaCubeX/ClashMetaForAndroid> v2.11.35（GPL-3.0，★47,768）
目标工程：`outputs/ClashMetaHarmony`

---

## 一句话结论

**主界面、代理页和 VPN/TUN 数据面都已移植完成，并且已经装到真机上跑起来了
（HUAWEI Pocket 2 / HarmonyOS 7.0.0 / API 26，序列号 XMH0224429007248）。**

范围要说清楚：Android 的 mihomo core（Go）已经交叉编译成 OHOS arm64 的
`libclash.so`，通过 `libclashcore.so` 的 NAPI 桥接进 `VpnExtensionAbility` 进程；
UI 仍然通过本机 `127.0.0.1:9090` 的 external controller 访问它，主界面大卡片
可以直接启动/停止 VPN 并加载当前 active profile。§21 记录过
「HarmonyOS 没有公开 VpnService 等价物」的早期错误结论；§23 记录 core 移植、
真实订阅、TUN 路由和真机浏览验证。§25–§27 补齐了剩余功能：三条静态快捷方式、
网络设置 7 行接 `VpnConfig`、profile 二维码分享/扫码、age key 生成/校验，以及
快速重启时的 `protectProcessNet` 稳定性修复。
20 个 Activity 里已移植 17 个页面（主界面、代理、Providers、设置、App 设置、
网络设置、覆写设置、Meta 特性设置、访问控制、配置列表、新建配置、配置编辑、
配置文件浏览、帮助、日志、ApkBroken、AppCrashed + Logcat 本地文件模式），
其余三项是 §19.2 的 Logcat 流式（结论：不移植）、§19.1 的 ExternalControl
（无界面入口，已做）和 §19.3 的 MainActivity 后端收尾。

---

## 1. 已完成（均已实测验证）

| 项 | 结果 | 证据 |
|---|---|---|
| HomeTrans 装入 Codex | 8 skills + 7 agents → `~/.codex/skills`、`~/.codex/agents` | `ht init -a` 输出 |
| 鸿蒙工程脚手架 | API 26，bundle `com.example.clashmeta` | `devecocli create` |
| **基线编译** | **BUILD SUCCESSFUL** | hvigor |
| 资源转换 | **2241 条 values 条目 + 52 个 XML drawable → SVG，0 失败** | `a2h_resource_convert.ts` |
| 图标分级 | 主界面 10 个图标全部 **L1**（`res/drawable/` 有 `<vector>`），逐个开文件核对：单路径纯 fill、无 stroke-only、无空文件 | 见 `entry/src/main/resources/base/media/` |
| 主界面 ArkTS 移植 | V2 范式（`@ComponentV2`/`@Local`/`@Param`/`@Event`/`@ObservedV2`/`@Trace`/`@Computed`）+ MVVM 分层，645 行 / 8 个 .ets | `entry/src/main/ets/` |
| **主界面编译** | **BUILD SUCCESSFUL**，产出 314 KB HAP | hvigor |
| **ArkTS 语义检查** | **errorCount 0 / warnCount 0**（8 个文件，用 SDK 自带 ets-loader，非文本扫描） | `hmos-precheck` arkts 后端 |

### 主界面移植的映射依据

`design_main.xml` + `MainActivity.kt` → `entry/src/main/ets/pages/Index.ets`：

- `CoordinatorLayout` → `Column`；`ScrollView` → `Scroll`；`LinearLayout` → `Column`/`Row`；`FrameLayout` → `Stack`
- `MaterialCardView` → `Row` + `borderRadius(8vp)` + `shadow`（按映射表：CardView 映射为容器样式，不做成拉伸 SVG）
- `View.GONE` → 用 `if` 从构建树中移除（等价 GONE，非 `Visibility.Hidden`）
- `dp → vp`、`sp → fp`，尺寸全部取自转换后的 `float.json`
- `trafficTotal()` 的 64 位打包解析（高 32 位上传 / 低 32 位下载，各含 2 位单位类型 + 30 位数据）与 `trafficString` 的整数除法后除 100 行为 **1:1 复刻**

---

## 2. 装机情况（已完成）

### 2.1 签名（已解决）

在 DevEco Studio 里用华为开发者账号完成自动签名，生成：

- `~/.ohos/config/default_ClashMetaHarmony_*.p12` / `.cer` / `.p7b`
- `build-profile.json5` 的 `signingConfigs` 已写入

Profile 校验通过：`type=debug`、`bundle-name=com.example.clashmeta`（与工程一致）、`device-ids` 含当前设备 UDID `CFC378630BC95C80FE1C18492EE90710370A7902EB4F8B3CB8FB1930D6679875`。

### 2.2 真机安装与运行（已完成）

设备：**HUAWEI Pocket 2 (LEM-AL00)**，HarmonyOS **7.0.0.109**，API **26**（与工程 targetSdkVersion 26 一致）。

```
hdc install -r entry-default-signed.hap   →  install bundle successfully
hdc shell aa start -a EntryAbility -b com.example.clashmeta  →  start ability successfully
```

验证结果：

| 检查项 | 结果 |
|---|---|
| 已安装包 | `com.example.clashmeta`，codePath `/data/app/el1/bundle/public/com.example.clashmeta` |
| 进程 | 存活（PID 20598） |
| 渲染 | 持续 `RSSurfaceRenderNodeDrawable::OnDraw name:clashmeta0` |
| 崩溃日志 | faultlog 中无 clashmeta 记录 |
| 截图 | 主界面正常渲染：图标 + 应用名 + 灰色状态卡（"Stopped"，色值 `#ff808080` 与 Android 源码 `color_light_clash_stopped` 一致）+ Profile 卡 + Providers/Logs/Settings/Help/About 各行 |

产物：`entry/build/default/outputs/default/entry-default-signed.hap`（349,971 字节）

### 2.3 数据源是空的（能力层面，这是真正的硬伤——仍未解决）

Android 版的所有状态都来自**原生 mihomo 内核**（Go，gomobile 编译的 `.so`，通过 JNI 调用），流量接管靠 **Android `VpnService`**。这两样在鸿蒙上都不存在：

- `VpnService` 在 HarmonyOS NEXT 没有公开等价 API —— Clash 式的 TUN 流量接管无法照搬；
- mihomo 内核需要为鸿蒙交叉编译并用 NAPI 桥接，这是独立于本次 UI 移植的另一个项目。

所以代码里 `ClashBackend` 被显式声明为接口，默认实现 `NullClashBackend` 一律返回「已停止、无配置」。**UI 是真实的，数据是空的。** 这一点写在 `entry/src/main/ets/viewmodel/MainViewModel.ets` 的文件头注释里，没有假装完成。

### 2.4 其余 19 个页面没动

CMFA 共 20 个 Activity、43 个布局文件。本次只做了主界面。Proxy / Profiles / Settings / Logs / Providers / Files / AccessControl / OverrideSettings / MetaFeatureSettings / NetworkSettings / NewProfile / Properties / Help / About / Logcat / ExternalControl / ApkBroken / AppCrashed 都还是原样。

---

## 3. 务实的产品定位

**能移植的**：UI 外壳、配置/订阅管理、规则编辑、日志查看、外部控制器对接。
**移植不了的**：mihomo 引擎本身、TUN 流量接管。

所以自洽的形态是：**做成鸿蒙上的 Clash 配置管理器/控制器**，通过 external controller API 连接跑在别处（路由器 / PC / NAS）的 mihomo 实例。这不是妥协，CMFA 自己就有 `ExternalControlActivity` 和 external controller 相关代码，这条路有上游依据。

---

## 4. 在 HomeTrans 上实测到的 4 个真实缺陷

这些是本次实际踩到的，都会影响他人上手：

| # | 缺陷 | 证据 | 影响 |
|---|---|---|---|
| 1 | `devecocli` 在 npm 上不存在 | `npm view devecocli` → 404（npmjs 与 npmmirror 均无） | skills 里大量 `npx --yes devecocli ...` 会直接失败。真实包名是 **`@deveco/deveco-cli`**，bin 名才是 `devecocli` |
| 2 | `jsonc-parser` 未声明为依赖 | `agents/scripts/hmos-precheck/core/sdk_context.mjs` 导入它，但 `@buaa_smat/hometrans` 的 `dependencies` 里没有 | **hmos-precheck 全新安装后完全跑不起来**（`ERR_MODULE_NOT_FOUND`）。手动 `npm i jsonc-parser` 后才恢复 |
| 3 | `ht init` 不装脚本依赖 | 复制到 `~/.codex/agents/scripts/` 后同样缺 `jsonc-parser` | 即使用包内 node_modules 修好，Codex/编辑器侧的副本仍是坏的 |
| 4 | `codelinter` 后端找不到工具 | DevEco 只提供 IDE 插件 `Contents/plugins/codelinter/lib/instrumented-codelinter-26.0.0.461.jar`，`Contents/tools/` 下无 CLI | precheck 永远报 `codelinter-missing`（blocking），全量检查永远 `ok:false` |

另外两个非缺陷但需要注意的点：

- `a2h_resource_convert.ts` 的文件头注释写「XML drawable → SVG 尚未覆盖」，但实际已实现（本次转了 52 个）。**注释与实现不一致**。
- 转换后的 locale 字符串（如 `values-zh/strings.xml`）没有 base 版本，编译时产生 15 条 `does not have a base resource` 警告。

---

## 5. 要继续做的话，优先级

1. **配置签名 + 连真机**（需要你的华为开发者账号）—— 做完这一步就能把当前这个「空壳主界面」装到手机上跑起来看效果。
2. **实现 `ClashBackend` 的 external controller 客户端** —— 让它连上路由器/PC 上的 mihomo，主界面就会真的活起来。这是投入产出比最高的一步。
3. **继续搬其余页面** —— 按 `hmos-batch-ui-align` 的流程逐页做，每页都要走「资源转换 → 图标分级 → ArkTS → 编译 → precheck」。

---

## 6. 代理页（ProxyPage）已移植并实测验证

主界面之后做的第二个页面，数据源同样走 external controller。

### 6.1 移植内容

`design_proxy.xml` + `ProxyActivity.kt` + `ProxyView.kt` / `ProxyViewState.kt` →
`pages/ProxyPage.ets` + `viewmodel/ProxyViewModel.ets` + `model/ProxyModels.ets`；
`ExternalControllerBackend` 增加 `listProxyGroups()` / `selectProxy()` / `patchMode()`。

- `ViewPager2 + TabLayout` → `Tabs + TabContent`；`RecyclerView` → `List + ForEach`
- 一个组一个 tab；`GET /proxies` 里带 `all` 的条目是组，其余是叶子节点
- 点成员 → `PUT /proxies/{group}` `{"name":"<member>"}`

### 6.2 实测（真机 + mock controller）

用 `work/mock-mihomo-controller.py` 当 peer，`hdc rport tcp:9090 tcp:9090` 把设备
`127.0.0.1:9090` 反代到宿主机，再用 DevEco CLI 1.3.5 的 `devecocli ui`
（`ui layout` / `ui screenshot` / `ui click`）驱动：

| 检查项 | 结果 |
|---|---|
| 组 → tab | GLOBAL / Proxy / Auto 三个 tab 全部渲染 |
| 成员列表 | 名称 + 类型 + 延迟；延迟取自该成员的 `history[-1].delay` |
| 组套组 | 成员本身是组时副标题为 `type(now)`，如 `Selector(node-2)` |
| 选中态 | `now` 成员用 `colorPrimary` 卡片底，其余用 `colorSurface` |
| 选择 | 点 Selector 组内成员 → mock 收到 `PUT /proxies/Proxy`，高亮随之移动 |
| 非可选组 | URLTest 组点成员不发 PUT；`now` 成员仍按 Android 语义高亮 |
| 返回 | 标题栏返回箭头回到主界面 |

截图存于 `work/shots/proxy-verify/`。

### 6.3 本轮修掉的 4 处保真偏差

对着 `ProxyViewState.kt` / `ProxyViewConfig.kt` 核对后发现并修正：

1. **选中态**：原画的是勾选圆圈图标；Android 是给整行铺 `colorPrimary` 底
   （`selectedBackground = colorPrimary`），已改为铺底。
2. **高亮判定**：原写成 `group.selectable && node.name === group.now`，导致
   URLTest 组完全没有高亮；Android 只看 `proxy.name == parent.now`
   （`selectable` 仅决定能否点击），已改。
3. **延迟文案**：原渲染成 `118 ms` 并按数值分绿/黄/红；Android 是裸数字
   `118`、颜色与整行一致（`delayText = proxy.delay.toString()`），已改。
4. **组套组副标题**：补上 `type(now)`（`ProxyViewState.update()` 的
   `"%s(%s)".format(type, link.now)`）。

### 6.4 仍未对齐（已知偏差）

- ~~**布局**：单列列表、字号沿用 16/12fp~~ —— 已在 **§12** 改成 Android 的
  1/2/3 列网格（`uiStore.proxyLine`），padding、圆角、字号都按
  `ProxyViewConfig` 走。
- ~~**未搬的交互**：延迟测试按钮与溢出菜单~~ —— 延迟测试与模式切换在 **§11**
  补齐（`GET /group/{name}/delay`、`PATCH /configs`），过滤 / 布局 / 排序三组
  在 **§12** 补齐。
- **precheck**：`arkts` 后端单独跑 **errorCount 0 / warnCount 6**（6 条均为
  INTERNET 权限提示与 `pushUrl`/`back` 弃用警告）；整体仍 `ok:false`，原因是
  §4 缺陷 #4 的 codelinter/typescript 缺失使 project-integrity 后端 unavailable，
  与本次改动无关。

---

## 7. Providers 页（ProvidersPage）已移植并实测验证

主界面、代理页之后的第三个页面，数据源同样走 external controller。

### 7.1 移植内容

`design_providers.xml` + `ProvidersActivity.kt` + `adapter/ProviderAdapter.kt` +
`adapter_provider.xml` → `pages/ProvidersPage.ets` +
`viewmodel/ProvidersViewModel.ets` + `model/ProviderModels.ets`；
`ExternalControllerBackend` 增加 `listProviders()` / `updateProvider()`；
`Index.ets` 的 `MainRequest.OpenProviders` 分支从死路改为
`router.pushUrl('pages/ProvidersPage')`（此前 Providers 行点击无反应）；
`main_pages.json` 注册新页面。

- `RecyclerView` → `List + ForEach`；`View.GONE` → `if` 从构建树移除
- `ProgressBar` → `LoadingProgress`；行内竖线 → `Divider().vertical(true)`
- `GET /providers/proxies` + `GET /providers/rules` 合并成一个列表；
  行尾同步图标 / 标题栏同步图标 → `PUT /providers/{type}/{name}`

### 7.2 实测（真机 + mock controller）

`work/mock-mihomo-controller.py` 扩展出 `/providers/proxies`、
`/providers/rules`、`PUT /providers/...` 三个端点后，按代理页同样的方式
（`hdc rport` + `devecocli ui layout/screenshot/click`）驱动：

| 检查项 | 结果 |
|---|---|
| 排序 | 代理类在前、规则类在后，同类按名称排序（`Provider.compareTo`） |
| 过滤 | `vehicleType == Compatible` 的条目被过滤掉（`tunnel.QueryProviders()`） |
| 类型文案 | `代理(HTTP)` / `代理(内联)` / `规则(文件)`，经资源管理器取词 |
| 相对时间 | `3 小时前` / `近期`（`elapsedIntervalString`） |
| Inline 行 | 隐藏 elapsed、分隔线与行尾按钮（`ProviderAdapter.onBindViewHolder`） |
| 单行更新 | 点行尾同步图标 → mock 收到 `PUT /providers/proxies/...` |
| 全部更新 | 点标题栏同步图标 → 逐个 PUT |
| 失败提示 | mock 对 `BrokenProvider` 返回 503 → toast `更新 BrokenProvider: fetch failed` |
| 返回 | 标题栏返回箭头回到主界面 |

### 7.3 本轮修掉的 1 个隐蔽 bug

`updateProvider()` 最初给 `http.HttpRequestOptions` 传了 `extraData: ''`。
**ArkTS 在请求发出前就会拒绝空 `extraData`**，于是 GET 正常、PUT 静默不发。
改为完全不传 `extraData` 后 PUT 正常触发；同时把 catch 从固定字符串改为
透出 `error.message`，让内核返回的错误信息能到达 toast。

### 7.4 需要注意的资源改写（易被回退）

ArkUI 的 `$r` 格式化只文档化 `%d`/`%s`/`%f`，而资源转换器会产出 Android 的
索引占位符 `%1$s`。本次把 6 个字符串名、跨 8 个 locale 目录（共 39 处）
从 `%1$s` 改写为 `%s`。**重跑 `a2h_resource_convert.ts` 会把改写冲掉**，
重跑后需重新修正，否则 `format_provider_type` 等会渲染异常。

另：`Divider.strokeWidth` 接受 `Length` 而非 `Resource`，
`$r('app.float.divider_size')` 无法编译，已在行内写成 `1`。

---

## 8. Settings 页 + Help 页已移植并实测验证

按路线图推荐顺序（tier 1 第 1、2 项）做的两个页面，同时补上它们共用的
三个 preference 组件。

### 8.1 新增文件

| 文件 | 对应 Android |
|---|---|
| `pages/SettingsPage.ets` | `design_settings.xml` + `SettingsActivity.kt` + `SettingsDesign.kt` |
| `pages/HelpPage.ets` | `design_settings_common.xml` + `HelpActivity.kt` + `HelpDesign.kt` |
| `model/SettingsModels.ets` | `SettingsDesign.Request` 枚举 |
| `util/Platform.ets` | `Intent.ACTION_VIEW` 与 `showToast` 的鸿蒙等价物 |
| `view/ActionLabel.ets` | `component_action_label.xml` |
| `view/PreferenceCategory.ets` | `preference_category.xml` |
| `view/PreferenceTips.ets` | `preference_tips.xml` + `Tips.kt` 的 `getHtml()` |

### 8.2 主界面导航被改成 Android 的形状

原来主界面的「设置」行是就地展开控制器地址面板（移植时的临时做法）。
现在恢复成 Android 的结构——主界面只导航，设置页负责配置：

| 主界面行 | 之前 | 现在 |
|---|---|---|
| 设置 | 就地展开控制器面板 | `pushUrl('pages/SettingsPage')` |
| 帮助 | 无反应 | `pushUrl('pages/HelpPage')` |
| 配置 / 日志 / 关于 | 无反应 | toast「Not ported yet」 |

控制器地址面板搬进设置页，作为 Android 没有的**External Controller** 条目
（端口自己的补充：没有进程内内核时，控制器地址就是这个 App 的主要设置）。
`Index.ets` 增加 `onPageShow()` 重新读取 `ControllerStore` 并 `refresh()`，
否则从设置页返回后主界面还在探测旧地址。

### 8.3 实测（真机 + mock controller）

| 检查项 | 结果 |
|---|---|
| 主界面 → 设置 | 标题栏「设置」+ External Controller（副标题 `http://127.0.0.1:9090`）+ 应用/网络/覆写/Meta 特性 |
| External Controller 行 | 点击就地展开：地址输入框（预填当前值）、密钥输入框、Cancel/Save |
| Save | 面板收起，副标题保持，返回主界面后主界面按新地址刷新 |
| 未移植行 | 点「应用」→ toast `Not ported yet`（`Toast [370,2240,765,2353]`） |
| 主界面 → 帮助 | tips + 文档（Clash Wiki / Clash Meta Wiki）+ 源代码（Clash Meta 核心 / Clash Meta for Android），副标题为 URL |
| 帮助链接 | 点 Clash Wiki → 系统浏览器打开 `github.com`（`ohos.want.action.viewData`） |
| 返回 | 两个页面的返回箭头都回到主界面 |
| 回归 | 主界面仍能连 mock controller：运行中 / `15.27 MiB 已转发` / 代理·规则模式 / 外部资源行出现 |
| 崩溃 | 无 faultlog 记录，进程存活 |

截图：`work/shots/settings-verify/`（`settings-page.png`、`help-page.png`、`toast2.png`）。

### 8.4 两处需要说明的实现细节

1. **`ActionLabel` 的 `showIcon`**：Android 的 `ClickablePreference.icon` setter
   只在 icon 非 null 时才把 `iconView` 设为 `GONE`；`HelpDesign` / `ApkBrokenDesign`
   都不传 icon，所以那个 30dp 的 `View` **留在布局里**，文字仍缩进 65dp。
   `showIcon: false` 因此只去掉图片、保留占位，跟 Android 一致。
2. **tips 里的 HTML**：`tips_help` 是带 `<strong>` 的富文本（中文值也一样，
   如 `是一个<strong>免费软件</strong>`），Android 走 `Html.fromHtml`。
   ArkUI 的 `Text` 不解析标记，`PreferenceTips` 用一个 `<strong>` 切分器把
   字符串拆成若干 `Span` 并按段加粗，渲染结果与 Android 相同。

### 8.5 仍未对齐（已知偏差）

- **设置页 4 行的目标页**（`AppSettingsActivity` / `NetworkSettingsActivity` /
  `OverrideSettingsActivity` / `MetaFeatureSettingsActivity`）都在路线图 tier 2 / 4，
  分别卡在 `PackageManager`、`VpnService` 和原生 override API 上，现在只出 toast。
- **新加字符串只进 base**：`not_ported` 只写在 `base/element/string.json`，
  其它 locale 回落到英文。这与端口既有的 `controller_cancel` / `controller_save` /
  `external_controller` 一致——上游 Android 自己的 `values-zh/strings.xml` 也没有
  `external_controller`，所以回落行为与 Android 相同。
- **构建警告**：新增代码带入 `getContext` 弃用、`router.back` 弃用、
  `getStringSync` 可能抛异常三类警告（不阻断编译）。
- **precheck**：24 个文件，`arkts` 后端 errorCount 0 / warnCount 26；
  整体 `ok:false` 仍只因 §4 缺陷 #4 的 codelinter/permission-catalog 缺失。

---

## 9. Logs / Application Broken / Application Crashed 三页已移植并实测验证

路线图 tier 1 的第 3、4、5 项。三页共用 §8 的 `ActionLabel` /
`PreferenceCategory` / `PreferenceTips`，新增代码很少。

### 9.1 新增文件

| 文件 | 对应 Android |
|---|---|
| `pages/LogsPage.ets` | `design_logs.xml` + `LogsActivity.kt` + `LogsDesign.kt` + `adapter/LogFileAdapter.kt` |
| `viewmodel/LogsViewModel.ets` | `LogsActivity.loadFiles()` / `deleteAllLogs()` |
| `model/LogFileModels.ets` | `design/model/LogFile.kt` + `Date.format(context)` |
| `pages/ApkBrokenPage.ets` | `design_settings_common.xml` + `ApkBrokenDesign.kt` |
| `pages/AppCrashedPage.ets` | `design_app_crashed.xml` + `AppCrashedDesign.kt` |

`Index.ets` 的 `MainRequest.OpenLogs` 从 toast 改成
`router.pushUrl('pages/LogsPage')`（Android 在此处按 logcat 服务是否运行二选一，
本端口没有该服务，所以恒走文件列表）。

### 9.2 实测（真机）

| 检查项 | 结果 |
|---|---|
| 日志页布局 | 标题栏（返回 + 日志 + 清空图标）、`Clash 日志捕捉工具`/点此启动、分隔线、`历史` |
| 清空日志 | 点标题栏清空图标 → `AlertDialog`：标题 `删除所有日志`、正文 `所有历史日志将丢失`、取消/确认 |
| 确认删除 | 点确认 → `deleteAll()` 无异常，列表保持为空（目录本就不存在） |
| 应用损坏页 | 标题 `应用损坏` + tips + `重新安装` 分类 + `Github Releases`（副标题为仓库 URL） |
| 应用损坏页链接 | 点 `Github Releases` → 系统浏览器打开 GitHub |
| 应用崩溃页 | 标题 `应用崩溃` + 崩溃文本，可选中（`copyOption`） |
| 返回 | 三页返回箭头都回到主界面 |
| 崩溃 | 无 faultlog 记录 |

### 9.3 验证方式上的一个说明（临时改动已回退）

`ApkBrokenActivity` 与 `AppCrashedActivity` 在 Android 上由「原生库加载失败」
和「进程崩溃」触发，**没有 UI 入口**，所以本端口里它们也没有入口。为了按
「每页都要真机验证」的标准验证这两页，本轮临时把主界面的 `配置` / `关于`
两行分别指到这两个页面（`关于` 还带了 `params.logs` 样本），验证完立刻回退，
回退后重新构建装机并复查：`配置` 重新回到 toast，`日志` 仍进日志页。
`Index.ets` 中已无 `TEMP-VERIFY` 标记。

### 9.4 仍未对齐（已知偏差）

- **日志页永远是空的**：Android 的 `LogcatService`（前台服务 + `Clash.subscribeLogcat`）
  没有移植，所以 `cacheDir/logs` 没有任何写入方。本页的目录读取、`clash-<millis>.log`
  解析、日期格式化、删除逻辑都是真的，只是没有生产者。`Clash Logcat` 行与
  单个文件行都出 toast。
- **`rmdirSync` 不递归**：Android 是 `logsDir.deleteRecursively()`；鸿蒙的
  `fs.rmdirSync` 对非空目录会抛 `13900032`，所以 `deleteAll()` 先逐个
  `unlinkSync` 再 `rmdirSync`。
- **崩溃文本来源**：Android 由 `SystemLogcat.dumpCrash()`（`logcat` 命令）填充；
  鸿蒙没有等价命令，本端口改为路由参数传入，无参数时渲染空文本（与 Android
  空 dump 的表现一致）。
- **precheck**：29 个文件，`arkts` 后端 errorCount 0 / warnCount 39；整体
  `ok:false` 仍只因 §4 缺陷 #4。

---

## 10. Logcat 页（本地文件模式）已移植并实测验证

路线图 tier 1 第 6 项。`LogcatActivity` 有两条分支：`fileName != null` 时读本地
日志文件，否则启动 `LogcatService` 做流式抓取。本次做的是**本地文件分支**，
流式分支没有移植（见 §10.4）。

### 10.1 新增文件

| 文件 | 对应 Android |
|---|---|
| `pages/LogcatPage.ets` | `design_logcat.xml` + `LogcatActivity.mainLocalFile` + `LogcatDesign.kt` + `adapter/LogMessageAdapter.kt` + `adapter_log_message.xml` |
| `viewmodel/LogcatViewModel.ets` | `LogcatReader` 调用、`Request.Delete`、`Request.Export` |
| `model/LogMessageModels.ets` | `core/model/LogMessage.kt` + `log/LogcatReader.kt` + `log/LogcatFilter.kt` |

`LogsPage` 的文件行从 toast 改为
`router.pushUrl('pages/LogcatPage', { fileName })`，并在 `onPageShow()` 重新
扫描目录（对应 Android 的 `Event.ActivityStart`，因为日志页可能刚被删掉）。

### 10.2 实测（真机）

因为 `hdc` 无法写入应用沙箱（`mkdir` 直接 `Permission denied`），验证用的日志
文件由应用自己临时写入（见 §10.3），验证后已回退。

| 检查项 | 结果 |
|---|---|
| 文件列表 | `clash-1760616000000.log` + `2025-10-16 20:00:00.000`（`SimpleDateFormat` 同款格式） |
| 打开文件 | 标题栏 `Logcat` + 删除/导出两个图标；6 条消息逐条渲染 |
| 行布局 | 级别名（Caption，左）+ `HH:mm:ss.SSS`（Caption，右）在 accent 色，正文 Body2 在下 |
| 消息含冒号 | `Error` / `connect failed: timeout` —— `split(":", limit=3)` 保住了正文里的冒号 |
| 长按复制 | 长按行 → toast `已复制`（`pasteboard` 写入） |
| 导出 | 点导出图标 → 系统文档选择器弹出（预填文件名）→ 保存后 hilog 显示 `getDocumentPickerSaveResult errorcode = 0`，`file_monitor_service` 记录该文件被创建，toast `File Exported` |
| 删除 | 点删除图标 → 文件被删除、返回日志页、历史列表为空 |
| 崩溃 | 无 faultlog 记录 |

### 10.3 验证方式上的说明（临时改动已回退）

`hdc` 对应用沙箱只读不可写，无法从外部放一个日志文件进去，所以本轮临时在
`LogsPage.aboutToAppear()` 里写了一个样本文件、并把 toast 时长临时调成 10s
（长按手势约 1s 后才触发，2s 的 toast 在 `ui layout` 取快照前就消失了，这是
工具时序问题而不是功能问题）。两项临时改动都已删除，`entry/src/main/ets/`
下已无 `TEMP-VERIFY` 标记，回退后重新构建装机并复查通过。

### 10.4 仍未对齐（已知偏差）

- **流式模式未移植**：Android 的 `mainStreaming()` 会 `startForegroundService`
  拉起 `LogcatService`，绑定后每 500ms 拉一次快照，列表 `reverseLayout`，标题栏
  的「停止」按钮对应 `Request.Close`。前台服务 + 内核日志订阅在鸿蒙上没有等价
  物，所以本页只有本地文件分支，标题栏没有停止按钮。
- **日志没有生产者**：`cacheDir/logs` 目前没有任何写入方（Android 由
  `LogcatWriter` 写 `"%d:%s:%s"`，即 `<epochMillis>:<Level>:<message>`），
  所以日志页正常情况下是空的。读取、解析、导出、删除都是真的。
- **导出格式与写入格式不同**（上游行为，非本次引入）：`LogcatFilter` 导出的是
  `# Capture on <date>` 头 + `%12s %7s: %s`（时间是 `HH:mm:ss.SSS`），而
  `LogcatReader` 只认 `<epochMillis>:<Level>:<message>`。所以**导出的文件再读
  回来会全部变成 Warning**。端口按上游原样复刻，没有"修正"它。
- **precheck**：32 个文件，`arkts` 后端 errorCount 0 / warnCount 47；整体
  `ok:false` 仍只因 §4 缺陷 #4。

## 11. 代理页补齐：延迟测试 + 模式切换菜单（已实测验证）

§6 收尾时留下两个缺口：标题栏的「测延迟」图标和溢出菜单的「模式切换」。
本轮把这两项做完并实测通过。

### 11.1 改动

| 文件 | 改动 |
|---|---|
| `backend/ExternalControllerBackend.ets` | 新增 `queryMode()`、`urlTestGroup()`；新增常量 `DELAY_TEST_URL`（`https://www.gstatic.com/generate_204`，与 mihomo `constant.DefaultTestURL` 一致）、`DELAY_TEST_TIMEOUT_MS=5000`、`DELAY_TEST_READ_TIMEOUT_MS=9000`；`getJson()` 增加可选 `readTimeoutMs`（测延迟比普通查询慢，读超时要放宽） |
| `viewmodel/ProxyViewModel.ets` | 新增 `@Trace urlTesting`、`@Trace mode`、`loadMode()`、`urlTest(groupIndex)`、`switchMode(mode)`、`refreshGroup()`，以及 `applyGroups()` / `mergeGroup()` |
| `pages/ProxyPage.ets` | 标题栏 flash 图标（测试中换成 spinner）、溢出菜单 `bindMenu(this.modeMenuItems())`、右下角浮动按钮（与标题栏图标同一个 `Request.UrlTest`） |
| `work/mock-mihomo-controller.py` | 新增 `do_PATCH`（`/configs` → 204，改 `MODE`）、`GET /group/{name}/delay`（每轮换一组数值，并写回成员的 `history`） |

延迟测试对应 `GET /group/{name}/delay?url=…&timeout=5000`，模式切换对应
`PATCH /configs {"mode": …}`，两者都在
`outputs/mihomo-external-controller-api-verified.md` 里。

### 11.2 实测（真机，mock controller）

| 检查项 | 结果 |
|---|---|
| 测延迟 | mock 记录 `GET /group/GLOBAL/delay` → `{'Proxy': 116, 'DIRECT': 193}`，界面同步刷新成 116/193；再测一次变 126/203，说明是真的重新取值而不是渲染缓存 |
| 浮动按钮 | 与标题栏图标走同一条 `urlTest`，点浮动按钮同样刷新延迟 |
| 模式菜单 | 点溢出图标 → 弹出 `直连模式` / `全局模式 ✓` / `规则模式`，当前模式带勾 |
| 模式切换 | 点 `全局模式` → mock 记录 `PATCH /configs -> mode=global`；返回主界面，代理卡副标题同步变成「全局模式」 |
| 提示 toast | 切换时弹出 `mode_switch_tips`（`Valid only for current session`） |
| 崩溃 | 无 faultlog 记录 |

### 11.3 踩到的两个 ArkUI 坑（已在代码里注释，勿回退）

1. **`ForEach` 的 key 就是子节点身份**。测延迟后如果整批换掉 `ProxyGroup`
   对象（名字没变），`ForEach` 认为子节点没变，行不会重绘，延迟数字就停在旧值。
   修法：`applyGroups()` 按名字把新值**合并进已有对象**（`mergeGroup()`），靠
   `@Trace` 推动刷新；只有分组结构本身变了才整体替换数组。
2. **`bindMenu` 传 `@Builder` 在本组件里弹不出来**，必须传 `MenuElement[]`。
   Android 的 `PopupMenu` 会在当前项上画对勾图标，这里的等价做法是在标签后面
   追加 `✓`。

另外记录一条**工具侧**的坑：`devecocli ui layout --mode simplified` 会过滤掉
Toast 节点，看起来像"toast 没弹"。判断 toast 是否真的出现要用
`--mode full`（完整树里是 `Toast [321,2241,815,2354]`）。这一条和功能无关，
但下次验证别再被它误导。

### 11.4 仍未对齐（已知偏差）

- ~~**溢出菜单只做了模式组**~~ —— `proxyExcludeNotSelectable` / `proxyLine` /
  `proxySort` 三组已在 **§12** 补齐。
- **「不修改」模式项没有控制器对应物**。Android 的第四个菜单项会清掉会话级
  override，controller API 没有 override 这一层，所以只提供三个具体模式。
- ~~**行布局仍是单列列表**~~ —— 已在 **§12** 换成 1/2/3 列网格。
- **precheck**：32 个文件，`arkts` 后端 errorCount 0；整体 `ok:false` 仍只因
  §4 缺陷 #4。

## 12. 代理页溢出菜单：过滤 / 布局 / 排序（已实测验证）

§11 只做了 `menu_proxy.xml` 的模式组，另外三组（Filter / Layout / Sort）本轮
补齐，同时把 §6.3 记的「单列列表 + 16/12fp 字号」偏差一并修掉。另外把
`QueryProxyGroupNames` 里剩下的两条模式规则（Direct 不返回任何组、只有 Global
模式才把 `GLOBAL` 列进去）也补上了 —— 见 §12.1。

### 12.1 语义是照着 Go bridge 抄的，不是猜的

这三项在 Android 上不产生网络请求，而是**改变 native core 的查询条件**，所以
光看 `ProxyMenu.kt` 只能知道「点了哪个菜单项」，不知道它到底做了什么。真正的
语义在 JNI 背后那层 Go 代码里：

| Android | 端口对应 |
|---|---|
| `queryProxyGroupNames(uiStore.proxyExcludeNotSelectable)` | `ProxyViewModel.shape()` 的分组过滤 |
| `queryProxyGroupNames` 里的模式分支 | `shape()` 的 Direct / Global 处理 |
| `queryProxyGroup(names[i], uiStore.proxySort)` | `ProxyViewModel.sortNodes()` |
| `ProxyViewConfig(context, uiStore.proxyLine)` + `ProxyPageFactory` | `ProxyPage` 的 `Grid` 列数与行度量 |

`queryProxyGroupNames` / `queryProxyGroup` 的实现在
`work/clashmeta/core/src/main/golang/native/tunnel/proxies.go`（CFA 自己往
mihomo 里加的那层，不是 mihomo 上游）。摘两条关键行为：

```go
// QueryProxyGroupNames
if mode == tunnel.Direct { return []string{} }               // Direct 模式没有组
if mode == tunnel.Global { result = append(result, "GLOBAL") }  // 只有 Global 才列 GLOBAL
if !excludeNotSelectable || p.Type() == C.Selector { ... }   // 过滤只留 Selector

// QueryProxyGroup
case Title: strings.Compare(a.Title, b.Title) < 0            // 按标题字节序
case Delay: a.Delay < b.Delay                                // 按延迟升序
```

`Delay` 用的是 `LastDelayForTestUrl(testURL)`，没测过时返回 0，所以**未测速的
节点排最前**；端口里未测速是 `-1`，升序排也在最前，两者一致。

模式那两条不是可有可无的洁癖：`GLOBAL` 这个选择器**只在 Global 模式下参与
路由**，rule 模式下从它里面选节点没有任何效果，摆在 tab 栏里是个误导性的
无效控件；Direct 模式下所有流量都直连，代理组整体没有意义。所以
`shape()` 也按模式决定列表：Direct → 空列表，Global → `GLOBAL` 排在最前，
其余模式 → 只列配置里的组。列表空了以后页面自然落到 Android 的
`empty_view` 分支（`ProxyDesign.init` 里 `groupNames.isEmpty()` 那一段：
隐藏 tab / pages / 测速按钮，只留空态文案）。

### 12.2 改动

| 文件 | 改动 |
|---|---|
| `backend/ProxyUiStore.ets`（新增） | 对应 `UiStore.kt` 里那三个 `proxy_*` 键，用 PersistenceV2 持久化；默认值照抄 Android：`excludeNotSelectable=false`、`line=2`、`sort=Default` |
| `model/ProxyModels.ets` | 新增 `ProxySort` 枚举（`Default` / `Title` / `Delay`，取值与 `ProxySort.kt` 一致） |
| `viewmodel/ProxyViewModel.ets` | 新增 `shape()`（过滤 + 排序）、`sortNodes()`、`reshape()`、`rawGroup()`；缓存最近一次未过滤的 `GET /proxies` 结果，改过滤/排序时**只在本地重新整形，不发请求** |
| `pages/ProxyPage.ets` | 溢出菜单从 3 项扩到 11 项（四组）；`List` 换成 `Grid`，列数 1/2/3 可选 |
| `work/mock-mihomo-controller.py` | `Proxy` 组加了一个 `aardvark` 节点 |

加 `aardvark` 是因为原来的 `node-1/2/3` 恰好「按名字」和「按默认顺序」是同一个
排列，没法区分 `Title` 和 `Default` 两种排序。现在三种排序结果各不相同：

| 排序 | 顺序 |
|---|---|
| 默认 | node-1, node-2, node-3, aardvark |
| 名称 | aardvark, node-1, node-2, node-3 |
| 延迟 | node-3(0), node-1(118), node-2(342), aardvark(500) |

### 12.3 行布局按 `ProxyViewConfig` 复刻

`proxyLine` 的三档在 Android 上不只是列数，还带三套度量：

| | 单列(1) | 双列(2) | 多列(3) |
|---|---|---|---|
| contentPadding | 12 | 15 | 12 |
| textMargin | 5 | 10 | 5 |
| textSize | 11 | 12 | 11 |
| 背景 | 通栏、无圆角 | 卡片（内缩 3dp、圆角 5dp） | 卡片 |

`ProxyViewConfig` 里 `proxyLine==2` 是唯一走 `proxy_content_padding` /
`proxy_text_size` 的分支，1 和 3 共用 `_grid3` 那套值。另外
`unselectedBackground` 在 `proxyLine==1` 时是 `TRANSPARENT`，`ProxyView.draw`
也在该分支跳过圆角矩形 —— 所以单列是通栏行，多列才是卡片。行高按
`ProxyView.onMeasure` 的
`layoutPadding*2 + contentPadding*2 + textHeight*2 + textMargin` 算。

顺带修掉 §6.3 记的字号偏差：Android 的标题、副标题、延迟**共用同一个
`textSize`**（`ProxyView.onDraw` 只设一次 `paint.textSize`），不是端口原来的
16/12fp 两级。

### 12.4 实测（真机 + mock controller）

| 检查项 | 结果 |
|---|---|
| 菜单项 | 11 项全部渲染，四组前缀（过滤/模式/布局/排序）；当前项带勾 |
| 默认布局 | 双列：`Grid [0,456,1136,2603]`，两个 cell 各 550px |
| 单列 | 行 `[0,456,1136,616]` 通栏，文字起点 46px ≈ 15vp（= 3 + 12），行间无间隙 |
| 多列 | 行宽 361px，卡片内缩 9px = 3vp，文字距卡片边 37px ≈ 12vp |
| 排序：名称 | aardvark 提到最前 |
| 排序：延迟 | node-3(0) → node-1(118) → node-2(342) → aardvark(500) |
| 过滤：不可选择 | URLTest 组 `Auto` 从 tab 栏消失，只剩 GLOBAL / Proxy |
| 模式：规则 | tab 栏为 `[Proxy, Auto]`，**没有 GLOBAL** |
| 模式：全局 | tab 栏为 `[GLOBAL, Proxy, Auto]`，GLOBAL 排第一，网格首格是 GLOBAL 的第一个成员 |
| 模式：直连 | 列表为空：无 tab、无网格、无测速按钮，只剩「没有可以显示的组」空态；切回规则后 tab 栏恢复 |
| 选择成员 | 点 node-1 → mock 收到 `PUT /proxies/Proxy`，`now` 变为 node-1 |
| 测延迟 | 延迟刷新成 144/176/177/178，且**延迟排序跟着新值重排**（说明刷新后会重新整形） |
| 持久化 | 强杀重启后，过滤 / 三列 / 延迟排序三项都还在 |
| 崩溃 | 无 faultlog 记录 |

验证后已把三项设置复位回默认（过滤关、双列、默认排序），模式回到 `rule`。

### 12.5 仍未对齐（已知偏差）

- **菜单是平铺的，不是 Android 的四级子菜单**。Android 用
  `menu_proxy.xml` 的嵌套 `<menu>` 做 Filter / Mode / Layout / Sort 四个子菜单；
  ArkUI 的 `MenuElement[]` 没有嵌套形式，而 `bindMenu` 传 `@Builder` 在本组件
  里弹不出来（§11.3 记过）。折中办法是把组名当标签前缀，例如
  `布局: 双列 ✓`。
- **模式变化时 tab 栏会增减**：这是 §12.1 那两条模式规则带来的直接结果 ——
  切到 Direct 后 tab 栏消失、切到 Global 后多出 GLOBAL。Android 的做法是
  「模式变了就重启 Activity」，端口是在改模式和进入页面时重新整形，效果一样
  但不会闪一次白屏。代价是：如果**外部**（比如路由器上）改了模式，端口的
  tab 栏不会自己变，要等下一次进入页面或切模式。这一条是有意的取舍。
- **文字颜色**：Android 选中行用 `colorOnPrimary`、未选中用 `colorOnSurface`；
  端口沿用主题默认文字色。深色主题下默认色本身就接近 onSurface，视觉差异很小。
- **precheck**：33 个文件，`arkts` 后端 errorCount 0；整体 `ok:false` 仍只因
  §4 缺陷 #4。

---

## 13. 主题语义色层 + 暗黑模式 + App 设置页（已实测验证）

这一节修掉一个**一直存在但没被发现的可见缺陷**，并在此之上补齐
`AppSettingsActivity`。

### 13.1 先修缺陷：端口一直硬编码深色

Android 的每个 Activity 都走 `BaseActivity.queryDayNight()`，按
`UiStore.darkMode` 选 `AppThemeLight` / `AppThemeDark`，**默认 `Auto` = 跟随系统**。
端口之前把 `color_dark_background`(#121212) / `color_dark_surface`(#202020) 直接
写死在 12 个文件里，等于永远深色。测试机当时是浅色系统，于是出现
「白色状态栏 + 深色内容」以及图标几乎看不见（见下一条）。

### 13.2 图标 tint 也错了

Android 每个 vector 都带 `android:tint="?attr/colorControlNormal"`（浅色=黑、
深色=白）。转换出的 SVG 里 fill 被写成 `#ffffff`，端口之前又统一
`fillColor(color_light_control_disabled)`(#d3d3d3)，在浅色底上基本不可见。
正确映射是 `color_control_normal`。

### 13.3 新增语义色层（`base/` + `dark/` 双份）

`entry/src/main/resources/base/element/color.json`（浅色）+
`entry/src/main/resources/dark/element/color.json`（深色）。命名对齐 Android 的
theme attribute，值直接取自 `design/src/main/res/values/themes.xml`：

| 语义名 | 浅色（base） | 深色（dark） | Android 来源 |
|---|---|---|---|
| `color_background` | `#fffafafa` | `#ff121212` | `android:windowBackground` |
| `color_surface` | `#ffffffff` | `#ff202020` | `colorSurface` |
| `color_control_normal` | `#ff000000` | `#ffffffff` | `colorControlNormal` |
| `color_control_disabled` | `#ffd3d3d3` | `#ff808080` | `colorControlDisabled` |
| `color_control_highlight` | `#1f000000` | `#33ffffff` | `colorControlHighlight` |
| `color_primary` | `#ff1e4376` | `#ff1976d2` | `colorPrimary` |
| `color_on_primary` | `#ffffffff` | `#ffffffff` | `colorOnPrimary` |
| `color_clash_started` | `#ff1e4376` | `#ff1976d2` | `?attr/colorPrimary`（`MainDesign.kt:84`） |
| `color_clash_stopped` | `#ff808080` | `#ff202020` | `colorClashStopped` |

替换范围：12 个文件 36 处硬编码引用，外加 3 处字面量
（ProvidersPage 分隔线 `#33FFFFFF`、LogsPage 对话框按钮、Index 缺页背景）。

`LargeActionCard` 增加 `contentColor` 参数：`design_main.xml` 给状态卡钉了
`android:theme="@style/AppThemeDark"`，所以状态卡在两种主题下都是白字，而
代理/配置卡跟随主题（`color_control_normal`）。

### 13.4 暗黑模式落地

- `model/AppSettingsModels.ets`：`DarkMode`（`Auto` / `ForceLight` / `ForceDark`）
  + `AppSettingsRequest`，对应 `DarkMode.kt` 与 `AppSettingsDesign.Request`。
- `backend/UiStore.ets`：`PersistenceV2` 存 `darkMode`；`applyDarkMode()` 调
  `ApplicationContext.setColorMode()`，`Auto` → `COLOR_MODE_NOT_SET`（跟随系统）。
- **踩到的坑**：一开始在 `EntryAbility.onCreate` 里 `PersistenceV2.connect()`，
  值**写不进磁盘**（重启后回到 `Auto`）。改成从 UI 侧（`Index.aboutToAppear`）
  连接后就正常了 —— PersistenceV2 必须在 UI 侧连接。这条已写进代码注释。
- 切换模式时**不需要重建页面**：`setColorMode` 会让 ArkUI 重新解析
  `base/` / `dark/` 限定词，整条页面栈即时换色（Android 那边靠
  `ApplicationObserver.createdActivities.forEach { it.recreate() }`）。

### 13.5 App 设置页

`pages/AppSettingsPage.ets` + `view/PreferenceSwitch.ets`，走
`design_settings_common.xml` 同一套外壳（和 Help / ApkBroken 一致）。

Android 的四组偏好里**只有暗黑模式可移植**，其余三项在 HarmonyOS 上没有对应
API，页面按 Android 的排版画出来，点下去报 `not_ported`：

| 行 | Android 实现 | 端口 |
|---|---|---|
| 暗黑模式 | `selectableList uiStore::darkMode` | **真做**：`bindMenu` 三选一，写 store + `setColorMode` |
| 自动重启 | `PackageManager.setComponentEnabledSetting(RestartReceiver)` | stub |
| 隐藏应用图标 | 同一个 API 打在 `MainActivityAlias`（launcher activity-alias） | stub |
| 从最近任务隐藏 | `ActivityManager` 的 recents 排除标志 | stub |
| 显示流量 | `ServiceStore.dynamicNotification`（前台服务通知） | stub（没有常驻服务可通知） |

两个实现细节：`preference_switch.xml` 的开关本身 `clickable=false`，整行才是
热区，所以 ArkUI 侧用 `hitTestBehavior(HitTestMode.None)` 让 `Toggle` 不吞点击；
`bindMenu` 挂在带 `onClick` 的自定义组件上弹不出来（§11.3 记过），所以暗黑模式
那一行在页面内联构建、不带 `onClick`。

### 13.6 实测（真机 + mock controller）

| 检查项 | 结果 |
|---|---|
| 浅色主界面 | 背景 `(250,250,250)`=#FAFAFA；状态卡（停止）`(128,128,128)`=#808080；代理/配置卡 `#FFFFFF`；卡片文字状态卡白、代理/配置卡黑 |
| 浅色图标 | 导航图标最深像素 `(0,0,0)`（= `color_control_normal`） |
| 深色主界面 | 背景 `(18,18,18)`=#121212；运行中状态卡 `(24,118,210)`=#1976D2；代理/配置卡 `(32,32,32)`=#202020；状态栏黑 |
| 深色代理页 | 选中行 `#1976D2`、未选中行 `#202020`、背景 `#121212` |
| 深色 Providers 分隔线 | 列 x931-933 = `(65,65,65)` = #33FFFFFF over #121212 |
| 深色日志页分隔线 | y515-517 = `(65,65,65)`，同上 |
| 浅色日志页分隔线 | y515-517 = `(220,220,220)` = #1F000000 over #FAFAFA |
| 分类标题色 | 浅色 `(30,67,118)`=#1E4376；深色 `(25,118,210)`=#1976D2 |
| 设置页三选一 | 菜单三项（跟随系统 / 总是明亮 / 总是暗黑）逐项点选，摘要文字跟着变 |
| 持久化 | 选「总是暗黑」→ 强杀 → 重启，冷启动直接是深色（背景 `#121212`、状态栏黑） |
| stub 行 | 点「自动重启」弹出 toast（full 模式抓到 `[425..713, 2279..2322]` 的深色 toast） |
| 崩溃 | 无 faultlog 记录 |

验证后已把模式复位回 `Auto`（跟随系统），当前系统是浅色。

### 13.7 仍未对齐（已知偏差）

- **状态栏颜色**：Android 浅色主题把状态栏涂成 `color_system_ui_overlay`
  (#50000000)，深色主题透明；端口没碰系统栏，交给 HarmonyOS 自己按应用颜色
  模式处理（实测浅色白底、深色黑底，可读性没问题）。
- **`hideAppIcon` 等三项不落盘**：`UiStore` 里只保留 `darkMode`，另外三个开关
  永远是关的状态，点了只报 `not_ported`。Android 那边这三项是有状态的。
- **precheck**：37 个文件，`arkts` 后端 errorCount 0；整体 `ok:false` 仍只因
  §4 缺陷 #4。

---

## 14. 网络设置页（NetworkSettingsPage）已移植，VPN 控件禁用（已实测验证）

### 14.1 为什么整页都是「不可用」

`NetworkSettingsDesign` 里除最后一行外**全部**是在配置 Android 的
`VpnService`：`uiStore::enableVpn`、`bypass_private_network`、`dns_hijacking`、
`allow_bypass`、`allow_ipv6`、`system_proxy`、`tun_stack_mode`、
`access_control_mode`。HarmonyOS 没有公开的 `VpnService` 等价物，这个端口也没有
进程内 core，所以这些开关没有可配置的对象。

处理方式：**保留 Android 的版面和顺序，把 VPN 相关行画成 Android 自己的禁用
态**（`Preference.enabled = false` → 整行 alpha 0.33），点下去报 `not_ported`。

### 14.2 两处刻意的例外

- `access_control_packages` 这一行在 Android 里**没有**被放进 `vpnDependencies`
  （见 `NetworkSettingsDesign.kt` 末尾），所以隧道运行时它依然是启用的 —— 它是
  导航行不是 VPN 选项。端口照此保留启用态，点击报缺 `AccessControlActivity`。
- Android 在隧道运行时会把整组禁用并弹一个 indefinite 的 `options_unavailable`
  toast。这个闸门在端口里没有意义（控件本来就是禁用的），所以没有复刻。

### 14.3 顺带抽出的共用组件

`view/PreferenceList.ets`：`preference_clickable.xml` + `bindMenu`。§13 里
AppSettingsPage 内联写的那段暗黑模式行被替换成它，`PreferenceSwitch` 也补上了
`showIcon`（Android 的 `switch()` 不传 icon 时仍保留 30dp 图标位）。

为什么 `PreferenceList` 是 `ActionLabel` 的**副本**而不是包装：`ActionLabel` 注册了
`onClick`，而带 `onClick` 的行会吞掉 `bindMenu` 的手势，菜单弹不出来（§11.3、§13.5
都踩过）。行内容不带手势是菜单能打开的前提。

### 14.4 实测（真机 + mock controller）

| 检查项 | 结果 |
|---|---|
| 版面对齐 | 10 行全部渲染，顺序与 `NetworkSettingsDesign` 一致（主开关 → `VpnService 选项` → 5 个开关 → Stack Mode → 访问控制模式 → 应用包列表） |
| 禁用态 | 主开关图标 `(168,168,168)` = 0.33 × 黑 over #FAFAFA；标题最深 `(184,184,184)` |
| 启用态 | `访问控制应用包列表` 标题 `(48,48,48)`，与禁用行形成对比 |
| 深色 | 背景 `#121212`；禁用图标 `(96,96,96)` = 0.33 × 白 over #121212；启用标题 `(193,193,193)` |
| 点击禁用行 | 弹出 toast（对比截图 diff 落在 y 2200-2399） |
| 回归 | AppSettingsPage 的暗黑模式菜单换成 `PreferenceList` 后仍能弹出，弹层矩形与改造前逐像素一致（x16-760 / y1052-1593） |
| 崩溃 | 无 faultlog 记录 |

验证后模式已复位回 `Auto`。

### 14.5 已知偏差

- **整页不可用**：这是产品定位决定的，不是没做完。真正要让它活起来需要一条
  TUN/`VpnService` 替代方案（见 §3、§5）。
- **两个下拉的当前值**：端口显示 `ServiceStore` 的默认值（`tun_stack_mode` =
  "mips"、`access_control_mode` = `AcceptAll`），因为没有 service store 可读。
  Android 自己也是先画默认值、再异步取真实值。
- **`system_proxy` 行**：Android 只在 `SDK_INT >= 29` 时添加；端口恒定显示（该行
  本来就是禁用态）。
- **`Stack Mode` 在中文下是英文**：上游 `values-zh-rCN` 就没有 `tun_stack_*`，
  Android 同样回落到英文，不是转换漏项。
- **precheck**：40 个文件，`arkts` 后端 errorCount 0；整体 `ok:false` 仍只因
  §4 缺陷 #4。

---

## 15. 本地 profile store + 配置/新建/编辑三页（已实测验证）

这一节打通了主界面「配置」卡片。Android 的 profile 由 tunnel service 的 SQLite
持有，通过 `withProfile { ... }` 访问；端口没有 service，改成本地 store。

### 15.1 ProfileStore 的形状（踩了两个坑才定下来）

最终形状刻意和 `UiStore` 一模一样：**类里只有一个 `@Trace` 字符串**，所有 CRUD
都是自由函数（`profileAll` / `profileCreate` / `profilePatch` / `profileCommit` /
`profileSetActive` / `profileRemove` / `profileClone`），每次「解码 → 改 → 编码」
写回 `encoded`。

两条走不通、但看起来很合理的路，都记在文件注释里了：

1. 把 `Profile[]` 直接放进 `@Trace` 字段 —— **永远不落盘**。PersistenceV2 不能
   往返 `@ObservedV2` 实例数组，而且数组在场时**整个保存都会被丢掉**，连旁边那个
   纯字符串字段一起丢。
2. 把数组改成普通字段、CRUD 保留成类的方法 —— **仍然不落盘**。类里只要多出状态
   或方法就不行。

对照实验：同一台机器上 `UiStore`（单 `@Trace` 字段、无方法）的暗黑模式在强杀重启
后依然保留，所以不是环境问题。

代价：`profileAll()` 每次调用都新建 `Profile` 对象，所以列表行必须**按内容**做
`ForEach` key（`ProfilesPage.rowKey` 用
`uuid|name|type|active|pending|updatedAt`），否则 ArkUI 会复用一个内容已经变了的行。

### 15.2 三个页面

| 页面 | 对应 Android | 说明 |
|---|---|---|
| `ProfilesPage` | `design_profiles.xml` + `adapter_profile.xml` + `ProfilesActivity/Design` | 卡片列表（RadioButton + 名称 + 类型 + elapsed + 2dp 分隔线 + 溢出菜单）、更新全部、新建入口 |
| `NewProfilePage` | `design_new_profile.xml` + `adapter_profile_provider.xml` | 文件 / URL / QR 三个来源 |
| `PropertiesPage` | `design_properties.xml` + `component_action_text_field.xml` | tips + 名称 / URL / Age 私钥 / 自动更新 + 浏览文件 + 保存，含未保存退出确认 |

`ActionTextField` 抽成了 `view/ActionTextField.ets`（Android 那边本来就是一个自定义
View），`PreferenceSwitch`/`PreferenceList` 之外又多了个可复用件。

### 15.3 三个 ArkUI 坑（都写进代码注释了）

1. **`@Builder` 按值传参不会刷新**。`@Builder textField(field, value, ...)` 在父组件
   状态变化时**不会重新执行**，行里永远显示第一次构建时的值。同样的原因，挂在
   `@Builder` 体内的 `.onClick` 也不触发。结论：需要随状态变化的行必须写成
   `@ComponentV2` 组件（`@Param` 是响应式的），或者用无参 `@Builder`。
2. **`Stack` / `.overlay()` 会吞掉 `Scroll` 里的手势**。把整页包在
   `Stack { Column { Scroll } ; if(...) {...} }` 里时，工具栏按钮正常、列表里的行
   全部点不动；换成 `.overlay(...)` 一样。最后用 `bindContentCover` 承载两个对话框
   —— 它是真正盖在页面之上的模态层，不参与页面树的命中测试。
3. **`height('100%')` 的子元素会把卡片撑满整个 List**。`adapter_profile.xml` 里那条
   2dp 分隔线是 `layout_height="match_parent"`，端口照抄成 `.height('100%')` 后，
   卡片高度解析成了 List 的高度（实测 2292px，正常应为 234px）。改成
   `item_min_height` 后正常。

### 15.4 实测（真机 + mock controller）

| 检查项 | 结果 |
|---|---|
| 列表空态 | 只有返回 + 新建两个图标，更新全部隐藏（没有 `imported && type != File` 的配置） |
| 新建流程 | 配置 → `+` → URL → 直接进编辑器，名称预填「新配置」，URL 行显示占位符「仅接受 http(s) 和 content 类型」 |
| 编辑对话框 | 名称行 → 弹层（scrim 实测 `(125,125,125)` = 50% 黑 over #FAFAFA）→ 改完点 OK → 行文字跟着变 |
| 保存 | 写入 store 并回上一页；列表出现卡片，名称/类型/elapsed（「近期」）正确 |
| 卡片尺寸 | `Row [54,296,1082,530]` = 234px（修复前 2292px） |
| 持久化 | 建好配置 → 强杀 → 冷启动，配置仍在（`encoded` 长度 218、1 条记录） |
| 激活 | 点卡片 → 单选圆点变蓝（radio 区蓝色像素 756）→ 主界面配置卡副标题变成「新配置P1 已激活」 |
| 菜单 | 溢出菜单弹出（已导入的 Url 配置 5 项：更新/编辑/复制/分享二维码/删除）；未保存的 File 配置只剩编辑/删除 2 项 |
| 复制 | 复制后新记录类型被强制成 `File`、状态为未保存，列表显示「文件 (未保存)」，且重启后仍在 |
| 禁用行 | File 类型的编辑器里 URL 行显示「不可用」，整行 alpha 0.33（文字最亮 76 vs 正常 193） |
| 删除 | 菜单删除后列表立即少一条，重启后不复活 |
| 崩溃 | 无 faultlog 记录 |

验证后已把主题复位回 `Auto`；设备上保留 1 条已激活的示例配置（`新配置P1`）。

### 15.5 已知偏差

- **没有配置文件本体**。Android 每个 profile 有一个 `files/profiles/<uuid>/` 目录，
  里面是 `config.yaml` 和 `providers/`。端口只存记录，因为没有任何东西消费配置
  内容 —— `FilesActivity` 也因此没做，「浏览文件」行报 `not_ported`。
- **更新 / 更新全部 / 分享二维码**：分别需要 HTTP 拉取 + 交给 core、以及 ZXing 生成
  二维码，都报 `not_ported`。
- **QR 导入**：需要相机扫码 Activity 契约，报 `not_ported`。
- **订阅用量**（`upload`/`download`/`total`/`expire` 和那根进度条）来自订阅响应的
  HTTP 头，只有 `ProfileProcessor` 会产出。端口不建模这些字段，那几行视图保持
  隐藏 —— 这也正是 Android 对「从未拉取过的配置」渲染的样子。
- **未保存配置激活提示**：Android 的 toast 带一个 Edit 按钮，`promptAction` 的 toast
  没有 action 槽位，端口只显示同样的文案。
- **编辑器返回路径**：Android 从 `PropertiesActivity` 保存后会 finish 回配置列表，
  端口是 push 上去的，保存后回到「新建配置」页，需要再返回一次。
- **Age 私钥校验**：`ValidatorAgeSecretKey` 是 JNI 调用，端口不做校验，任何值都收。
- **precheck**：46 个文件，`arkts` 后端 errorCount 0；整体 `ok:false` 仍只因
  §4 缺陷 #4。

---

## 16. 配置文件浏览器（FilesPage）已移植（已实测验证）

### 16.1 文件树

Android 每个 profile 在 `files/profiles/<uuid>/` 下有 `config.yaml` + `providers/`，
通过 `DocumentsProvider` + `FilesClient` 访问。端口把同一棵树放在应用沙箱
`<filesDir>/profiles/<uuid>/`，用 `@kit.CoreFileKit` 的 `fileIo` 直接读写
（`backend/ProfileFiles.ets`）。目录结构保持一致，因为 `FilesActivity` 有一条规则
依赖它：**根目录下 `config.yaml` 大小为 0 时，列表只显示它自己**，`providers/`
要等配置有内容才出现。

### 16.2 页面

`pages/FilesPage.ets`：列表（文件夹/文件图标 + 名称 + 大小 + elapsed + 分隔线 +
溢出菜单）、新建入口（仅非根目录）、导入/导出/重命名/删除、目录栈与返回。
重命名/新建的输入框复用了抽出来的 `view/TextInputDialog.ets`（PropertiesPage 也
换成了它）。

### 16.3 这一轮踩到的三个新坑

1. **`fs.mkdirSync(path, true)` 在目录已存在时仍然抛 `File exists`**。Android 的
   `mkdirs()` 返回 false 就算了，这里抛出的异常在 `aboutToAppear` 里没人接，
   **整个应用直接挂掉**（现象：点「浏览文件」后回到桌面，没有 faultlog，只在
   hilog 里看到 `AppKit: Error message:File exists` + `HandleAppDied`）。
   修法：先 `accessSync` 再 `mkdirSync`，并且页面里也加了 try/catch。
2. **`router.back()` 不走 `onBackPress`**。工具栏返回箭头直接调 `router.back()`，
   于是目录栈没弹、整页退出；`onBackPress` 只在系统返回手势时触发。两处
   （FilesPage 的目录栈、PropertiesPage 的未保存确认）都改成箭头调用同一个
   `requestBack()`。
3. **`bindMenu` 传空 `MenuElement[]` 不是「没有菜单」，而是盖住整页的一块白板**。
   Url 类型 profile 根目录下的 `config.yaml` 四个菜单项全部不满足显示条件，
   点开就是全屏白色。改成菜单为空时不挂 `bindMenu`（图标保留，和 Android 一样）。

另外顺带修掉 §15 的一处：`ActionTextField` 禁用时应当**无条件**显示「不可用」，
而不是「有值就显示值」。

### 16.4 实测（真机 + mock controller）

| 检查项 | 结果 |
|---|---|
| 入口 | 配置编辑器 → 浏览文件 → `文件` 页，标题、返回、新建按钮位置与 Android 一致 |
| 根目录规则 | 空 `config.yaml` 时只显示它自己（`providers/` 被隐藏），与 `FilesActivity.fetch` 一致 |
| 非空根目录 | 写入内容后显示 `providers`（目录，无大小/时间）在前、`config.yaml`（28 Bytes）在后 —— 目录优先 + 名称排序 |
| 菜单可见性 | File 类型 profile 根目录下 `config.yaml` 只有「导入」；Url 类型下四个条件全不满足 → 不挂菜单 |
| 非根目录菜单 | `providers/` 里的文件显示导入/导出/重命名/删除四项 |
| 新建按钮 | 仅在非根目录出现 |
| 重命名 | 改名为 `provider1.yamlX`，大小 12 Bytes 保持不变 |
| 删除 | 删除后目录立即为空，重启不复活 |
| 返回 | 在 `providers/` 内点返回箭头 → 回到根目录（修复前会直接退出页面） |
| 导入 | 点「导入」→ 系统文件选择器正常弹出（见 16.5） |
| 崩溃 | 修复 `mkdirSync` 后无 faultlog |

### 16.5 未能验证的部分

- **导入/导出的实际拷贝**没有跑通端到端：系统文件选择器（`DocumentViewPicker`）
  能正常打开并列出文件，但自动化点击条目后它始终没有回传 URI（无论点条目、
  点勾选框还是点标题栏按钮都只关闭选择器）。这是自动化驱动系统 UI 的限制，
  不是页面逻辑的问题。代码里 `copyFromUri` / `copyToUri` 已简化为
  `fs.copyFileSync(src, dst)` —— 手写 `openSync` + `statSync(fd)` + `readSync`
  那条路在 picker URI 上会失败，`copyFileSync` 接受路径/fd/URI 三者的任意组合。
  **这一条需要在真机上手动点一次确认。**
- **打开文件**：Android 用 `Intent.ACTION_VIEW` 交给别的应用渲染，端口用
  `file://` URI + `viewData` Want 做同样的交接；实测会被系统「文件预览」接走并
  显示「预览失败」（沙箱文件 URI 没有授权给别的应用），随后回落到 `not_ported`
  toast。这一条是平台限制，Android 的 chooser 在 HarmonyOS 上没有等价物。

### 16.6 已知偏差

- **列表排序**：Android 按 `DocumentsProvider` 返回的顺序（文件系统顺序）渲染，
  端口改成「目录优先 + 名称排序」。
- **菜单**：Android 是 `AppBottomSheetDialog`，端口用 `bindMenu`（同其它页面，
  删除项因此没有 error 配色）。
- **文件本体**：这个端口里没有任何东西消费配置内容，`config.yaml` 只是一份文本；
  Android 那边它会被 `ProfileProcessor` 拉取并交给 core。
- **precheck**：50 个文件，`arkts` 后端 errorCount 0；整体 `ok:false` 仍只因
  §4 缺陷 #4。

---

## 17. 覆写设置页（OverrideSettingsPage）已移植（已实测验证）

### 17.1 整页是一张表，不是 34 段标记

`OverrideSettingsDesign` 用 `preference/` 里的四个 builder 搭出一棵偏好树：
`editableText`（14 行）、`editableTextList`（8 行）、`editableTextMap`（2 行）、
`selectableList`（10 行），分在 `general`（17 行）和 `dns`（17 行）两个
`category` 下。端口把这张表原样搬进 `model/OverrideModels.ets`：
`overrideGeneralRows()` / `overrideDnsRows()` 返回 `OverrideRow[]`，页面用
`ForEach` 渲染，行种类由 `OverrideKind` 决定。顺序、标题、placeholder、empty、
选项与 `valuesText` 全部按 Kotlin 逐条对照。

四个 builder 渲染的其实是**同一张行布局**（`preference_clickable.xml`：
30dp 图标槽 + Body1 标题 + Body2 摘要），所以这一页用的是 `ActionLabel`
（可点击行）和 `PreferenceList`（点击弹菜单的行），**不是** `PropertiesPage`
那种 `component_action_text_field.xml` 形状。`ActionLabel` 为此补了
`rowEnabled` / `onDisabledTap`，和 `PreferenceSwitch`、`PreferenceList` 对齐。

### 17.2 值的三态

Android 的 `ConfigurationOverride` 每个字段可空，`null` 表示「不修改」，
`""` 表示「已设置但为空」（`Disabled` / `Default`），其余是值本身。
端口把这三态压进一个 `Record<string, string>`：**键不存在 = 不修改**，
键存在（哪怕是空串）= 已设置。list/map 存它们的 JSON 文本，因此一种记录类型
覆盖全部四种行，整个覆写也能作为**一个字符串**过 `PersistenceV2`
（`backend/OverrideStore.ets`，形状与 `UiStore` / `ProfileStore` 相同）。

端口行走 `NullableTextAdapter.Port` 的往返：`abc` 和空串都落到 `0`，摘要显示
`Disabled`——和 Android 一样会归一化，所以库里不会留下 `abc`。

### 17.3 值最终去了哪里

Android 把整个 `ConfigurationOverride` 交给 native 侧的 persist slot，由 core
在启动时套用。端口没有进程内 core，于是把 **`PATCH /configs` 能吃下的子集**
在退出时发给正在运行的 core（只在本次进入真的改过东西时发）：

```
port, socks-port, redir-port, tproxy-port, mixed-port, authentication,
allow-lan, bind-address, mode, log-level, ipv6
```

这 11 行就是 mihomo `config.General` 的字段。其余 23 行（controller 自己的
地址与 secret、`hosts`、整个 DNS 子树）在 `RawConfig` 里，`PATCH /configs`
不带它们——这些行照样存、照样显示，但到不了任何地方，页面注释和本文都写明了。
后端加了 `ExternalControllerBackend.patchConfigs(body)`，`patchMode()` 改成
调它。

### 17.4 三个新的 ArkUI 坑

1. **`ForEach` 只对 key 变了的条目重跑 itemGenerator。** 覆写行的显示内容就是
   摘要，所以行 key 必须带上渲染后的摘要（`OverrideSettingsPage.rowKey`），
   否则改完值摘要不刷新。同理，摘要必须是**字符串**：`$r('app.string.
   format_elements', n)` 的 `Resource.id` 在 n 变化时不变，拿 id 做 key 会漏刷新，
   所以 `overrideSummaryText()` 收 `resourceManager` 直接返回字符串。
2. **行内容不能放在带值参的 `@Builder` 里**（老坑，见 §15.3），这次同样把行标记
   内联在 `ForEach` 里。列表/映射编辑器里那几行也一样。
3. **`TextInputDialog` 需要中性按钮。** `requestModelTextInput(reset = ...)`
   有「重置」这个 neutral 按钮，用来把值放回 `null`；组件补了 `showReset` +
   `onReset`，按钮顺序按 Material（neutral / negative / positive）。

另外，列表/映射编辑器的「新增元素」是**同一个 content cover 的下一步**，不是
叠在 overlay 上的第二个 dialog：两层 cover 不可靠，而 overlay 的 `List` 上面
压一个 `Stack` 会让列表手势失效。

### 17.5 实测（真机 + mock controller）

| 检查项 | 结果 |
|---|---|
| 入口 | 设置 → 覆写 → 标题「覆写」+ 右上角 replay 图标，位置与 Android 一致 |
| 两个分组 | 常规 17 行 + DNS 17 行，顺序、标题、摘要初始值（全部「不修改」）与 Android 一致 |
| selectableList | 允许局域网 / IPv6 / 模式 / 日志级别 / DNS 策略 等点击弹出菜单，选项文案与 `valuesText` 一致（不修改 / 已启用 / 已禁用；直连模式 / 全局模式 / 规则模式…） |
| editableText | HTTP 端口 → 对话框（标题 = 行标题，带「重置 / 取消 / 确认」）→ 输入 `7890` → 摘要变 `7890`；再打开按「重置」→ 回到「不修改」 |
| editableTextList | 认证 → 全屏 overlay（标题 + 右上角 add + 底部重置/取消/确认）→ 加 `user:pass`、`admin:pw` → 确认 → 摘要「2 个条目」 |
| 列表删除 | 删除第一项 → 列表只剩 `bbb` → 确认 → 摘要「1 个条目」 |
| editableTextMap | Hosts → 成对输入（key / value 两个输入框，key 为空时「确认」不可点）→ `example.com` / `1.2.3.4` → 摘要「1 个条目」 |
| DNS 依赖 | DNS 策略选「使用内置」→ 下面 16 行整体变淡（33%）；点击变淡行不再弹菜单 |
| 重置按钮 | 右上角 replay → 确认框（重置覆写设置 / 所有的覆写设置将会被擦除）→ 确认 → 清空并退出；再进页面全部「不修改」 |
| 持久化 | 强杀 + 重启 App 后重进，`7890` / 「2 个条目」/「已启用」都还在 |
| 下发到 core | 把「模式」设为「全局模式」后退出 → `GET /configs` 返回 `"mode": "global"`（`PATCH /configs` 真的打到了 mock） |
| precheck | 55 个文件，`arkts` 后端 errorCount 0；整体 `ok:false` 仍只因 §4 缺陷 #4 |

### 17.6 已知偏差

- **下发时机**：Android 的 persist override 在 core 启动时套用；端口改成「本次
  进入有改动时，退出那一刻 PATCH 给正在跑的 core」。没有改动就不发，
  因为这是对远端 core 的实时改写，不是写本地 slot。
- **重置不回收**：Android 的 `clearOverride` 之后 `defer` 还会把内存里的
  configuration 写回 persist slot（顺序取决于 `defer` 栈）；端口按语义直白地
  清空，不再把旧值写回去。已经 PATCH 出去的值无法撤回。
- **菜单没有选中标记**：Android 的 `PopupListAdapter` 会在当前项上画对勾，
  `bindMenu` 的 `MenuElement` 没有 checked 状态，选中项只在行摘要里体现
  （Android 的摘要也一样）。
- **新增元素是分步的**：Android 是 overlay 上再叠一个 `AlertDialog`，端口把
  cover 的内容换成输入框再换回来，功能等价但看不到底下的列表。
- **禁用行会报 toast**：Android 禁用行点了没反应；端口沿用
  `NetworkSettingsPage` 的做法，点了给一句 `options_unavailable`。

---

## 18. Meta 特性设置页（MetaFeatureSettingsPage）已移植（已实测验证）

### 18.1 两个页面共用一套外壳

`OverrideSettingsDesign` 和 `MetaFeatureSettingsDesign` 是**同一份 persist
override** 上的两棵偏好树，外壳和编辑器完全一样（工具栏 + replay、`category` +
四种行、`requestModelTextInput` / `requestEditableListOverlay` /
`popupSelectMenu` / `requestResetConfirm`）。所以这一轮把外壳抽成了
`view/PreferenceScreen.ets`：

- `@Param pageTitle` / `sections` / `data`
- `@Event onDataChange`（每次编辑回传新记录）/ `onRowAction`（`clickable` 行）/
  `onClear`（重置确认后）/ `onBack`

它不碰 store 也不碰 controller，两个页面只剩「自己那张表 + 自己那几个
`clickable` 行做什么」。

`OverrideRow` 因此多了两样东西：`OverrideKind.Action`（`clickable(title,
summary)`，没有值），以及把原来的 `dnsDependent: boolean` 换成
`dependsOn: string` —— `dnsDependencies` 和 `snifferDependencies` 都是
「owner 为 `false` 时禁用」，一个字段覆盖两处。

### 18.2 这一页的行

`OverrideModels.overrideMetaSections()`：四个 category、25 行，顺序与 Kotlin
一致。

```
age_key_category : age_key_type_x25519 / age_key_type_hybrid      (Action)
settings         : unified_delay / geodata_mode / tcp_concurrent /
                   find_process_mode                              (Select)
sniffer_setting  : strategy + 14 行（3 组协议 ports/override-destination、
                   force-dns-mapping、parse-pure-ip、override-destination、
                   force/skip-domain、skip-src/dst-address）        (Select/List)
geox_files       : import_geoip/geosite/country/ASN               (Action)
```

Android 里 `geox_url_setting` 整段是注释掉的，端口也没有对应的行。

### 18.3 两个 `clickable` 行各自的下场

- **age key（两行）**：`requestAgeKeyHelper` 整个建立在 JNI 上
  （`Clash.genX25519KeyPair` / `genHybridKeyPair` / `veritySecretKeys` /
  `verityPublicKeys` / `toPublicKeys`）。端口没有 age 实现，两行都报
  `not_ported`。这在本端口里也是诚实的：那把密钥的消费者是
  `ProfileProcessor` 拉取 age 加密订阅的时候，而本端口根本不拉取配置。
- **geofile（四行）**：`Request.Import*` 用 `DocumentViewPicker` 取代 SAF 的
  `GetContent`，检查扩展名（`.metadb` / `.db` / `.dat` / `.mmdb`，不合法就弹
  Android 那句 `geofile_unknown_db_format`），然后拷进 `filesDir/clash/`
  （`backend/GeoFiles.ets`，文件名按 Android 的 `geoip<ext>` /
  `geosite<ext>` / `country<ext>` / `ASN<ext>`）。显示名取 URI 最后一段，因为
  HarmonyOS 没有 `OpenableColumns`。

### 18.4 下发到 core 的部分

两个页面共用一条 `overridePatchBody`，因为它们是同一条记录。Meta 这边多出来的
字段里，`unified-delay`、`geodata-mode`、`tcp-concurrent`、
`find-process-mode`、`sniffing` 都在 `config.General` 里（`GET /configs` 会
返回它们），所以 `PATCH /configs` 能吃下；`sniffing` 是嵌套对象，协议键按
mihomo 的要求大写（`HTTP` / `TLS` / `QUIC`）。

### 18.5 实测（真机 + mock controller）

| 检查项 | 结果 |
|---|---|
| 入口 | 设置 → Meta 特性 → 标题「Meta 特性」+ 右上角 replay |
| 四个分组 | Age 密钥 2 行 / 设置 4 行 / 嗅探设置 15 行 / Geo 文件 4 行，标题与摘要初始值（「不修改」「点击生成」「点击导入...」）与 Android 一致 |
| age key 行 | 点击不弹任何对话框（走 `not_ported`），不会因为缺 JNI 而崩 |
| selectableList | 统一延迟 / Geodata 模式 / TCP 并发 / 查找进程模式 / 嗅探策略 都能弹出菜单，选项文案与 `valuesText` 一致（含 `off/strict/always`） |
| editableTextList | Sniff HTTP Ports → overlay 加 `80` → 摘要「1 个条目」 |
| sniffer 依赖 | 嗅探策略选「已禁用」→ 下面 14 行整体变淡，点击不再弹菜单 |
| geofile 行 | 点击「导入 GeoIP 数据库」→ 系统文档选择器真的打开（「全选 / 已选 0/1 / 完成 / 仅可访问所选文件」），与 FilesPage 的导入是同一个 picker |
| 重置按钮 | replay → 确认框 → 确认 → 清空并退出；再进页面全部「不修改」 |
| 下发到 core | 设「统一延迟 = 已启用」+「嗅探策略 = 已启用」+ HTTP ports = `["80"]`，退出后 mock 收到的 body 正好是 `{"unified-delay":true,"sniffing":{"enable":true,"sniff":{"HTTP":{"ports":["80"]}}}}` |
| precheck | 57 个文件，`arkts` 后端 errorCount 0；整体 `ok:false` 仍只因 §4 缺陷 #4 |

### 18.6 这一轮踩到的两个新坑

1. **`@Entry` 页面的 `build()` 根节点必须是容器组件**，自定义组件不算。
   `build() { PreferenceScreen({...}) }` 直接编译失败
   （`10905210 … only one root node, which must be a container component`），
   外面套一层 `Column` 才行。
2. **precheck 的 `regular-property-init` 是逐行扫描、不管嵌套的**：
   `PreferenceScreen.ets` 里那些 `title:` / `onAction:`（来自它内部调用
   `TextInputDialog` / `ActionLabel` 的实参）会被当成 `PreferenceScreen`
   自己的**未装饰成员**，于是每个传 `title` / `onAction` 的调用点都被报
   「Property 'x' cannot be initialized」。把两个参数改名成 `pageTitle` /
   `onRowAction` 之后 errorCount 回到 0（代码注释里写了原因，别改回去）。

### 18.7 已知偏差

- **age key 两行是死的**：Android 弹的是「密钥 / 公钥 + Generate / From Secret /
  Copy」的对话框，端口直接报 `not_ported`，没有画那个对话框（画出来也没有一个
  按钮能工作）。
- **geofile 导入没有端到端验证**：picker 能打开、能列出文件，但自动化拿不到回传
  的 URI（和 §16.5 同一条限制），所以「拷贝到 `filesDir/clash/`」这一步只能在
  真机上手动点一次确认。
- **重置按钮两个页面共用**：`clearOverride(Persist)` 清的是同一条记录，所以在
  Meta 页面按重置也会把覆写页设的端口/DNS 一起清掉 —— 和 Android 一样。

---

## 19. 并行收尾：ExternalControl、Logcat 流式结论、MainActivity 审计

§18 之后剩下的四项（路线图 15 / 18 / 19 / 20）互相不共享写集，于是拆给四个
子 agent 并行做，主线只保留「设备验证 + 共享接线 + 文档 + 合并」这几件互斥的活。

### 19.1 ExternalControlActivity（路线图 19）已移植，已实测

Android 那个 108 行的无界面 Activity 在 HarmonyOS 上的对应物是
`EntryAbility.onCreate` / `onNewWant` 收到的 `Want`。
`backend/ExternalControl.ets` 复刻了它的四个请求，`EntryAbility` 只多出
「构造 + 冷启动入队 + `loadContent` 成功后 `setReady()` 派发」三处，全部包在
try/catch 里，普通启动路径一行没动。

映射（Android action 名原样保留，另接受 `ohos.want.action.viewData` 作为别名）：

```
android.intent.action.VIEW + clash://install-config?url=&name=&type=&update-interval=
    -> 建本地 profile（type/name/interval 按 Android 的 toLongOrNull/coerceAtLeast(15) 规则）
    -> 尽力建好 profiles/<uuid>/ 目录 -> 打开 PropertiesPage{uuid}
android.intent.action.VIEW + clash://profiles
    -> ProfilesPage
TOGGLE_CLASH / START_CLASH / STOP_CLASH
    -> not_ported（控制器 API 没有 /start /stop，只有 POST /restart）
无 action / 未知 action
    -> 忽略，Index 照常加载
```

实测（`hdc shell aa start -a EntryAbility -b com.example.clashmeta -A … -U …`）：

| 检查项 | 结果 |
|---|---|
| 只给 `-U clash://profiles`（没有 action） | 停在 Index —— 和 Android 的 intent filter 一致：没有 action 就不是这个入口 |
| `-A ohos.want.action.viewData -U clash://profiles` | 打开配置页（截图/布局确认） |
| `-A ohos.want.action.viewData -U 'clash://install-config?url=…&name=WantTest'` | 新建出名为 `WantTest`、URL 为 `https://example.com/sub.yaml` 的记录并直接进编辑器 |
| `onNewWant`（App 已在前台时再发一次 Want） | 正常派发，不重启 Ability |

### 19.2 LogcatActivity 流式模式（路线图 18）：结论是保持 `not_ported`

单独写了 `outputs/logcat-streaming-harmonyos-feasibility.md`（358 行，带
`文件:行号` 证据）。结论：

> Android 的流式模式**不是** `logcat`，而是前台服务 `LogcatService` 订阅**进程内**
> mihomo core 的日志流（`Clash.subscribeLogcat` → `Bridge.nativeSubscribeLogcat`）。
> HarmonyOS 没有给三方应用读取别的进程 HiLog 流的公开 API，SDK 里跟读日志有关的
> 权限都是 system / system-core / 企业 MDM 级。

所以这一项**不移植**，保持 `not_ported`；本端口的 Logcat 页继续只做本地文件模式。
如果以后真要看实时日志，可行的是另起一个「控制器 `GET /logs` WebSocket」的页面，
那是新功能，不是 `LogcatService` 的移植，文档里也写明了不要混为一谈。

### 19.3 MainActivity 后端与接线（路线图 20）：审计完成，补了两处

审计结论（逐条对照 `MainActivity.kt` / `MainDesign.kt`）：

| 项 | 结论 |
|---|---|
| `hasProviders` | **已补**：Android 的 `Clash.queryProviders()` 是「规则 providers + 代理 providers，再丢掉 `Compatible`」，端口原来只查 `/providers/proxies`，现在改走 Providers 页那条合并路径 |
| About 里的应用版本 | **已补**：`Bridge.nativeCoreVersion()` 没有对应物，改用 `bundleManager` 读安装包 `versionName`，弹出一个 About 对话框 |
| VPN 启停 | **已由 §21 + §23 完成**：HarmonyOS 有公开的三方 VPN API（`VpnExtensionAbility` + `@ohos.net.vpnExtension`），本轮已经把 mihomo core 编进 OHOS arm64、建出 TUN、接上真实订阅并验证浏览器访问 |
| 「未选择配置」前置条件与 toast 动作按钮 | 阻塞：那条前置条件是因为 Android 用本地 core 载入配置；本端口是控制器监控，加上去只会改变已验证的行为。`promptAction` 的 toast 也没有动作按钮 |
| `withClash` / `withProfile` / `StatusClient` 广播（`ServiceRecreated` 等） | 阻塞：没有服务可绑；现在用 `onPageShow` 近似刷新 |
| 通知权限、`ShortcutManagerCompat` 快捷键 | 阻塞：本端口没有前台服务/通知消费者，快捷键依赖的 headless 动作本身也还是 `not_ported` |

`Index.ets` 的导航顺序、`running` 语义（「本应用在监控」，不是「控制器可达」）和
`trafficString(bytes * 100)` 都原样保留，没有回退。

### 19.4 本轮 precheck

57 → 61 个文件（新增 `ExternalControl.ets`、`AccessControlPage` 等），`arkts`
后端 errorCount 0；整体 `ok:false` 仍只因 §4 缺陷 #4。

---

## 20. 访问控制页（AccessControlPage）已移植（已实测验证）

### 20.1 版面

Android `design_access_control.xml` 是「列表 + ActivityBarLayout（返回 + 标题 +
搜索 + 溢出菜单）」，行是 `adapter_app.xml`（应用图标 + 名称 + 包名 + 勾选框）。
端口 1:1 照搬，三处映射：

| Android | 端口 |
|---|---|
| `PackageManager.getInstalledPackages` + `QUERY_ALL_PACKAGES` | `bundleManager.getInstalledBundleList`（API 26 的名字，`getAllBundleInfo` 已不暴露），顺带请求 `GET_BUNDLE_INFO_WITH_REQUESTED_PERMISSION` 复刻 Android 的 INTERNET 过滤 |
| `ServiceStore.accessControlPackages`（`Set<String>`） | `AccessControlStore.encoded`（单 `@Trace` 字符串的 PersistenceV2 存储，形状同 `ProfileStore`） |
| 搜索图标打开整屏 `dialog_search` | 工具栏内联 `Search`，过滤规则一样（label / packageName 包含关键字） |

溢出菜单按本轮任务范围只保留 `System Apps`（Android v2.11.35 还有全选/全不选/
反选、排序、剪贴板导入导出，端口没有做）。空列表显示 `empty` 资源，这样
「权限被拒 → 列表为空」在界面上是可见的，而不是一片空白。

### 20.2 拿不到应用列表是常态，不是 bug

`bundleManager.getInstalledBundleList` 需要企业级权限
（`ENTERPRISE_GET_INSTALLED_BUNDLE_LIST`），普通三方应用拿不到。端口的做法是
**整段 try/catch**：权限拒绝、抛异常、返回空都在同一处兜住，页面照常渲染空态，
绝不把异常抛出 `aboutToAppear`（那会直接杀掉整个应用，见 §16.3）。

### 20.3 实测（真机）

| 检查项 | 结果 |
|---|---|
| 入口 | 设置 → 网络 → 「访问控制应用包列表」→ 打开页面（Android 的入口也是网络设置里这一行） |
| 标题 / 返回 | 「访问控制应用包列表」+ 返回箭头，与 Android 一致 |
| 搜索框 | 工具栏内联搜索框，占位符 `keyword` |
| 溢出菜单 | 只有一项「系统应用」（`system_apps`），点击切换 `showSystem` |
| 空态 | 列表为空时显示 `empty` 文案（本机确实拿不到别的 bundle，符合预期） |
| 返回 | 返回箭头回到网络设置页 |
| 崩溃 | 无 faultlog；枚举被拒没有影响其它页面 |

### 20.4 已知偏差

- **只有 System Apps 一项菜单**：全选/反选、排序、剪贴板导入导出没做（超出本轮
  任务范围，`AccessControlPage` 头部注释里写明了）。
- **勾选框用 `ToggleType.Switch`**：Android 是 `MaterialCheckBox`；这一轮按任务
  约定用了开关。
- **选择即存**：Android 在 Activity 关闭的 `defer` 里写回，端口每次切换就落盘，
  所以页面被强杀也不会丢。
- **改完选择后的服务重启**报 `not_ported`：没有 VpnService 可重启。
- **应用图标**取 `ApplicationInfo.iconResource`，跨 bundle 取图标可能被权限拦，
  取不到时回落 `ic_baseline_apps`。

### 20.5 路线图收尾

到这一轮为止，路线图 0–20 项全部有了结果：17 项已移植并验证，1 项（Logcat 流式）
有书面结论判定不移植，2 项（ExternalControl、MainActivity 后端）按其平台边界做完
并逐条记录了阻塞原因。并行轮次的调度记录在 `outputs/agent-dispatch-log.md`，
进度可视化在 `outputs/agent-progress.html`（自包含，直接打开即可）。

---

## 21. 更正：HarmonyOS **有**三方 VPN/TUN 能力，且已在本机建出 TUN

### 21.1 之前那条结论是错的

§1、§13–§20 里多处写着「HarmonyOS 没有公开的 `VpnService` 等价物」。这条结论
**不成立**，是本轮查 SDK 时发现的。证据（都在本机 SDK 与官方文档里）：

```
$SDK/ets/api/@ohos.app.ability.VpnExtensionAbility.d.ts   # @since 11，@kit NetworkKit
$SDK/ets/api/@ohos.net.vpnExtension.d.ts                   # @since 11
```

- 两个文件里 **`@systemapi` 出现 0 次、`@permission` 出现 0 次** —— 是公开三方 API；
- `vpnExtension.createVpnConnection(context).create(config)` **返回 TUN 的文件描述符**；
- `VpnConfig` 有 `addresses` / `routes` / `dnsAddresses` / `searchDomains` / `mtu` /
  `isBlocking` / `trustedApplications` / `blockedApplications` —— 对应 Android 的
  `Builder.addAddress/addRoute/addDnsServer/setMtu/addAllowedApplication/...`；
- `VpnConnection.protect(socketFd)` 对应 `VpnService.protect()`；
- 官方文档标题就是「@ohos.app.ability.VpnExtensionAbility（**三方VPN能力**）」，
  开发指南明确写：「当前提供三方VPN能力主要用于**创建虚拟网卡及配置VPN路由信息**，
  连接隧道过程及内部连接的协议需要应用内部自行实现」—— 和 Android 的 VpnService
  是同一个模型（平台给网卡，数据面自己做）；
- 只需要 `ohos.permission.INTERNET`；`ohos.permission.MANAGE_VPN` 是
  `system_basic`，那是给系统 VPN 管理界面用的，**三方 VPN 不需要它**；
- 首次连接时系统会弹信任对话框，之后状态栏显示钥匙图标；同一时刻只允许一个 VPN。

### 21.2 真机实验（已跑通）

新增 `entry/src/main/ets/vpnextension/ClashVpnExtension.ets`（`type: "vpn"` 的
extensionAbility）+ `EntryAbility` 里一个 `--ps vpnDebug 1` 触发的调试钩子。
配置是**故意做成惰性的**：只给 `172.19.0.1/24` 一个地址，**不给路由、不给 DNS**，
因为一条默认路由配上没人读的 TUN 会让手机整个断网。

```
$ hdc shell aa start -a EntryAbility -b com.example.clashmeta --ps vpnDebug 1
  → 系统弹出「是否允许使用 VPN？」信任对话框（com.huawei.hmos.vpndialog 冷启动）
  → 点「允许」后：
     C01340/com.example.clashmeta:vpn/Ext: ClashVpnExtension;0;1;0
     A00000/com.example.clashmeta:vpn/ClashVpnExt: onCreate
     A00000/com.example.clashmeta:vpn/ClashVpnExt: tun fd = 32
$ hdc shell ifconfig -a
  vpn-tun   Link encap:UNSPEC
            inet addr:172.19.0.1  P-t-P:[NOT SET]  Mask:255.255.255.0
$ hdc shell aa force-stop com.example.clashmeta
  → vpn-tun 消失（系统回收）
```

也就是说：**「能不能开 VPN」这一层已经验证通过**，拿到的是真正的 TUN fd，
和 Android 那边 `VpnService.Builder.establish()` 的返回值是同一种东西。

### 21.2.1 TUN fd 交给 native 已实测（2026-10-17）

为了确认 fd 能跨 ArkTS → C++ 边界交给真正的数据面，本轮增加了最小的 NAPI
探针 `libclashcore.so`：`tunAttach(fd)` 用 `fcntl` 检查描述符、尝试
`TUNGETIFF`、设置非阻塞并做一次 `read`。重新安装并复跑同一调试入口后：

```
$ hdc shell aa force-stop com.example.clashmeta
$ hdc shell aa start -a EntryAbility -b com.example.clashmeta --ps vpnDebug 1
  A00000/com.example.clashmeta:vpn/ClashVpnExt: tun fd = 32
  A00000/com.example.clashmeta:vpn/ClashVpnExt: native probe:
    fd=32 | open, flags=0x133122 |
    TUNGETIFF failed: Permission denied (errno 13) |
    read 76 bytes
```

- `fcntl(F_GETFL)` 成功，说明 fd 在 native 进程里有效且可访问；
- `TUNGETIFF` 被沙箱拒绝（`EPERM`），但这不是数据面必需的 ioctl；
- 非阻塞 `read` 实际读到 76 字节，说明平台创建的 TUN 已经有包进入，
  native 侧可以直接按字节流读取；
- 设备清理：`aa force-stop com.example.clashmeta` 后 `vpn-tun` 和
  `com.example.clashmeta:vpn` 进程都消失，没有残留。

因此从 `VpnExtensionAbility` 到 native core 的关键交接路径已经验证：
**ArkTS 调 `create()` 拿 fd，native 用同一个 fd 读写 TUN**。剩下的是把
mihomo 编成 OHOS arm64 的 native 库，并让它接管这个 fd。

### 21.3 当时为什么还不能用它上 github（已由 §23 解决）

因为 TUN 里现在没人读写。Android 的 ClashMetaForAndroid 把 mihomo（Go）通过
gomobile 编成 `.so` 塞进 APK，用 JNI 调用，由 core 去读写 TUN、跑规则、连节点。
这个端口没有 core，只有控制器客户端，所以：

- 已经有的：界面、控制器 API 客户端、VPN 网卡通道；
- 还没有的：**mihomo 的 HarmonyOS 原生移植**（交叉编译到 OHOS arm64 + NAPI 桥
  + 把 tun fd 交给 core 的 `tun` inbound）。

这一步是 native 工程，不是 ArkTS 能补的：需要 Go/OHOS 工具链、`libclash.so`
级别的产物、以及把 fd 传进 core 的 TUN 实现（mihomo 支持从外部 fd 接管 TUN，
对应 Android 的 `TunInterface`）。§23 已把这条路径做完并在真机上验证。

当时的临时方案（路由器/电脑跑 mihomo）现在不再是唯一路径，见 §23。

### 21.4 本轮改动

| 文件 | 内容 |
|---|---|
| `entry/src/main/ets/vpnextension/ClashVpnExtension.ets` | 新增。`VpnExtensionAbility`：onCreate 建 TUN、onDestroy 销毁；配置惰性，注释写清数据面缺什么 |
| `entry/src/main/module.json5` | `extensionAbilities` 增加 `{"name":"ClashVpnExtension","type":"vpn"}` |
| `entry/src/main/ets/entryability/EntryAbility.ets` | 新增 `--ps vpnDebug 1` 调试钩子（调 `startVpnExtensionAbility`），普通启动路径不变 |
| `entry/src/main/cpp/CMakeLists.txt` | 新增。OHOS arm64 NAPI 动态库构建入口 |
| `entry/src/main/cpp/napi_init.cpp` | 新增。`tunAttach(fd)` 最小探针：fcntl / TUNGETIFF / 非阻塞 read |
| `entry/src/main/cpp/types/libclashcore/` | 新增。NAPI 类型声明与本地 oh-package |
| `entry/build-profile.json5` / `entry/oh-package.json5` | 接入 `libclashcore.so` 原生构建产物 |
| 本文 §1 / §19.3 | 更正「没有 VpnService 等价物」的错误结论 |

---

## 22. 访问控制应用包列表：从"空列表"改成真能用（静态检查通过，真机未验证）

§20 记的现状是"枚举被拒 → 空态"，界面上等于没实现。本轮把它做成两条都能真正用的
路径，并把平台限制写进代码与文档，详见
`outputs/access-control-applist-harmonyos.md`（含 API 26 d.ts 与
`PermissionDefinitions.json` 的逐条证据）。

### 22.1 关键事实

| API | 权限 | 本机权限等级 |
|---|---|---|
| `bundleManager.getInstalledBundleList` | `ENTERPRISE_GET_INSTALLED_BUNDLE_LIST` | `system_basic` → 普通应用拿不到 |
| `bundleManager.getBundleInfo(name, flags)` | `GET_BUNDLE_INFO_PRIVILEGED` 或 `GET_BUNDLE_INFO` | 前者 `system_basic`，后者 **`normal`** |
| `pasteboard.getDataSync()` | `READ_PASTEBOARD` | `system_basic` + `user_grant` |
| `pasteboard.setDataSync()` | 无 | — |

d.ts 里没有 `getAllBundleInfo`/`getBundleInfos`，所以"换个旧 API 枚举"不存在。

### 22.2 做法

- `queryInstalledApps()` 照旧调 `getInstalledBundleList`，但把结果报成
  `InstalledAppQuery{apps, enumerated, errorCode, permissionDenied}`；旧名字
  `loadInstalledApps()` 保留为薄封装。
- 列表 = 平台返回的行 **+** 已选包名中平台解析不出的行；后者渲染成暗色单行包名，
  不编造 label/图标。
- 工具栏 `+` 手输包名；菜单 `Import from Clipboard` 先试读剪贴板，被拒就弹输入框让
  用户自己粘贴（用户发起的粘贴不需要权限）；`Export to Clipboard` 与 Android 等价。
- 菜单补齐 Select All/None/Invert、System Apps、Sort×4 + Reverse，状态存
  `AccessControlUiStore`。
- `NetworkSettingsPage` 的 `access_control_mode` 从禁用占位改成可用的持久化
  `selectableList`（`AccessControlModeStore`）；`tun_stack_mode` 仍禁用（它描述内核
  怎么建 TUN）。

### 22.3 本轮改动

| 文件 | 内容 |
|---|---|
| `entry/src/main/ets/backend/InstalledApps.ets` | 重写：查询结果对象化、`resolvePackage(s)`、`parsePackageList`、`accessControlReplaceAll`、保留 `loadInstalledApps` |
| `entry/src/main/ets/backend/AccessControlPrefs.ets` | 新增：`AccessControlModeStore`、`AccessControlUiStore`、剪贴板读写 |
| `entry/src/main/ets/model/AccessControlModels.ets` | `AccessControlApp.resolved`、`AccessControlUi` |
| `entry/src/main/ets/model/NetworkSettingsModels.ets` | `ACCESS_CONTROL_MODES`、`accessControlModeText()` |
| `entry/src/main/ets/pages/AccessControlPage.ets` | 重写：平台行 + 选中行、`+` 输入、导入/导出、完整溢出菜单、提示条 |
| `entry/src/main/ets/pages/NetworkSettingsPage.ets` | `access_control_mode` 行改为可用持久化选择器 |
| `entry/src/main/resources/base/element/string.json` | 新增 5 条 `access_control_*` 文案（仅 base，其它语言回落） |

### 22.4 未完成

1. `module.json5` 已由主 agent 加上 `{"name": "ohos.permission.GET_BUNDLE_INFO"}`
   （`normal` / `system_grant`，安装即授予）。手输/导入的包名现在可以解析出
   label/图标/系统标记。
2. 真机未跑：本轮只做了 `arkts-diff` 静态检查（64 文件，`errors: 0`；`ok:false` 是
   已知环境缺陷 #4）。最终统一构建已通过，访问控制页面的真机交互仍需后续按需验证。

---

## 23. mihomo core 移植到 OHOS arm64，VPN/TUN 已真机跑通

### 23.1 结论

Android 的 mihomo core 已经成功交叉编译为 HarmonyOS 可加载的
`libclash.so`，通过 `libclashcore.so` 的 NAPI 桥接进
`VpnExtensionAbility` 进程。真机上完成：

- 从真实订阅 URL 下载 `config.yaml`（381,443 字节）；
- 在挂 TUN 之前先加载 core、下载 GeoIP/规则/provider，避免默认路由把
  自己的 DNS 黑洞掉；
- 创建 `172.19.0.1/30`、MTU 9000、默认路由、DNS `172.19.0.2` 的 VPN；
- 用 `protectProcessNet()` 保护 core 的出站 socket；
- 把 TUN fd 交给 core 的 `system` stack；
- external controller 在 `127.0.0.1:9090` 正常提供真实节点列表；
- 代理页显示订阅里的真实节点（`node-1` Shadowsocks、`node-2` Vmess、
  `node-3` Trojan、`aardvark` Shadowsocks）；
- `ping github.com` 返回 `20.205.243.166`，延迟约 235-300ms；
  `ping baidu.com` 约 69-75ms，符合规则分流；
- 手机浏览器打开 `https://github.com`，错误页消失，页面进入
  `rootWebArea`；刷新按钮和地址栏状态正常。

### 23.2 构建链

Go 官方没有 `GOOS=ohos`，但 Android 目标的 Go 运行时可以在 OHOS 的
musl/OHOS clang 上加载。实际使用的是：

```bash
GOOS=android GOARCH=arm64 CGO_ENABLED=1 \
CC=$OHOS_NDK/llvm/bin/aarch64-unknown-linux-ohos-clang \
CGO_CFLAGS="-I$WORK/ohos-clash-build/include" \
CGO_LDFLAGS="-L$WORK/ohos-clash-build/lib" \
go build -tags 'foss with_gvisor cmfa' \
  -buildmode=c-shared -trimpath \
  -ldflags '-s -w -extldflags "-Wl,-soname,libclash.so"' \
  -o libclash.so ./ohos
```

为了让 Android 目标的 Go 运行时在 OHOS 上落地，本地工具链做了三处
最小修补（都在 `work/`，不进入 HAP 源码）：

1. `net/cgo_resold.go`：OHOS 的 `getnameinfo` hostlen 是 `socklen_t`，
   不是 Android Bionic 的 `size_t`；
2. `runtime/write_err_android.go`：不尝试打开 Android 的
   `/dev/socket/logdw` / `/dev/log/main`，直接走 stderr，避免 core
   第一条日志就 `exit(2)`；
3. `work/ohos-clash-build/lib/liblog.so`：一个 `liblog.so` 兼容 shim，
   提供 `__android_log_*` 符号，满足 Android 目标运行时和 `bridge.c`
   的链接需求。

产物 `libclash.so` 的 SONAME 是 `libclash.so`，只依赖 `liblog.so` 和
`libc.so`。

### 23.3 NAPI 边界

`entry/src/main/cpp/napi_init.cpp` 现在暴露：

| 函数 | 作用 |
|---|---|
| `tunAttach(fd)` | 诊断：`fcntl` / `TUNGETIFF` / 非阻塞 `read`，确认 fd 可交给 native |
| `corePrepare(home, profileDir, version)` | 加载 `config.yaml`、启动代理/DNS/规则/external controller，但不挂 TUN |
| `coreAttach(fd)` | 在 VPN 路由安装后，把 TUN fd 交给 core 的 `system` stack |
| `coreStop()` | 关闭 TUN data plane |

Go 侧对应 `work/clashmeta/core/src/main/golang/ohos/main.go` 的
`ohos_core_prepare` / `ohos_core_attach` / `ohos_core_stop`。

### 23.4 启动顺序（关键）

`ClashVpnExtension.ets` 的最终顺序是：

1. 下载/复用真实 `config.yaml`；
2. `corePrepare(...)`：此时还没有 VPN 路由，core 可以用正常网络下载
   GeoIP/MMDB、provider 并启动 external controller；
3. `vpnExtension.create(config)`：安装地址、默认路由和 DNS；
4. `protectProcessNet()`：保护 core 后续创建的 socket，避免回环进 TUN；
5. `coreAttach(tunFd)`：core 开始读写 TUN；
6. 失败则 `connection.destroy()`，避免没有数据面时把手机黑洞。

早期“先建 TUN 再加载配置”的顺序会让 GeoIP 下载在 DNS 被 TUN 接管后失败，
`rules[7541] ... can't download MMDB ... dns resolve failed` 就是那次实测
留下的错误，已由拆分 `corePrepare` / `coreAttach` 修复。

### 23.5 为什么用 `system` stack

`gvisor` stack 的 fdbased endpoint 会对 TUN fd 调 `unix.Fstat`。OHOS 的
VPN fd 在这个沙箱里允许 `fcntl` / `read`，但 `Fstat` 返回 `EPERM`，
表现为：

```text
mihomo core failed: unix.Fstat(35,...) failed: permission denied
```

切换到 `system` stack 后，core 只通过 `read` / `write` 读写 fd，不再
`Fstat`，真机验证通过。`system` stack 同样使用 sing-tun 的 TUN 抽象，
规则、DNS、节点选择都正常。

### 23.6 本轮新增/修改

| 文件 | 内容 |
|---|---|
| `work/clashmeta/core/src/main/golang/ohos/main.go` | 新增 OHOS core 包装：`corePrepare` / `coreAttach` / `coreStop` |
| `work/ohos-clash-build/include/android/log.h` | Android 头文件 shim |
| `work/ohos-clash-build/lib/liblog.so` | Android 日志符号 shim |
| `entry/src/main/cpp/napi_init.cpp` | 新增 `corePrepare` / `coreAttach` / `coreStop` |
| `entry/src/main/cpp/CMakeLists.txt` | 链接 `libclash.so` + `liblog.so` |
| `entry/src/main/cpp/prebuilt/arm64-v8a/libclash.so` | OHOS arm64 mihomo core（约 60 MB） |
| `entry/src/main/ets/vpnextension/ClashVpnExtension.ets` | 真实订阅 fetch、默认路由/DNS、`protectProcessNet`、core 生命周期 |
| `entry/src/main/ets/entryability/EntryAbility.ets` | `vpnDebug` 调试钩子携带 `vpnRoutes=1` |
| `entry/src/main/module.json5` | 增加 `ohos.permission.GET_BUNDLE_INFO` |

### 23.7 仍待收尾

1. 主界面已经通过 Want 参数把 active profile 的 `uuid` / `source` 传给
   `ClashVpnExtension`；扩展优先加载该 profile 的 `<uuid>/config.yaml`，
   只有没有参数时才回退到硬编码调试订阅。
2. UI 的启动/停止已经接到 `startVpnExtensionAbility` /
   `stopVpnExtensionAbility`，并真机验证「启动 → 运行中/转发 → 停止 →
   `vpn-tun` 消失 → 再启动」。
3. `NetworkSettingsPage` 的 VPN 行（TUN stack / DNS 劫持 / 绕过私有网络 /
   应用白名单）还没有映射到 `VpnConfig`；本轮只固定了默认路由和 DNS。
4. external controller 只绑定 `127.0.0.1:9090`；这是本机 UI 的预期，
   不应暴露到局域网。
5. `libclash.so` 约 60 MB，后续可按 ABI/功能裁剪，或把 core 拆成按需
   下载的资源。
6. `system` stack 已经可用；`gvisor` 需要等 OHOS 放开 fd 的 `Fstat`
   或做一次针对性的 fdbased 适配。

---

## 24. 并行收尾轮（访问控制、点击审计、profile fetch、日志空态）

本轮同时开了 5 个子 agent，按互不重叠的写入范围并行处理：

| 子 agent | 交付 | 产物 |
|---|---|---|
| Linnaeus | 访问控制页从「枚举被拒 → 空列表」改成「平台返回 + 手输/导入包名」，补齐 Android 溢出菜单 | `outputs/access-control-applist-harmonyos.md` |
| Franklin | 设置/网络/代理/配置页的点击无响应审计 | `outputs/click-audit.md` |
| Avicenna | URL/External profile 真实下载并写 `config.yaml`，保存/更新按钮接入 fetch | `outputs/profile-fetch-harmonyos.md` |
| Meitner | `PreferenceSwitch` 禁用态、Proxy 非 Selector 行反馈、Settings 返回草稿等修复 | `outputs/click-audit-fixes.md` |
| Darwin | Logs 空态、FilesPage 灰菜单、MetaFeature age key 文案收尾 | `outputs/click-audit-fixes.md`（追加节） |

合并后统一构建 `BUILD SUCCESSFUL`，`hmos-precheck` 的 ArkTS 后端
`errorCount: 0`（`ok:false` 仍是已知环境缺陷 #4）。访问控制页的真机交互
（枚举被拒提示、手输/导入、菜单勾选）仍需后续按需验证；其余页面已随主链路
一起构建并通过启动/停止验证。

---

## 25. ExternalControl 快捷方式 + 启停动作（已真机验证）

§19.1 留下的尾巴补齐了：`ExternalControl` 的 TOGGLE / START / STOP 三个动作从
`not_ported` 换成真实启停（`@ohos.net.vpnExtension`，与主界面状态卡同一条路），
并新增三条**静态快捷方式**（`resources/base/profile/shortcuts_config.json` +
`module.json5` 的 `ohos.ability.shortcuts` metadata）。

真机验证：

- 桌面长按 `com.example.clashmeta` 图标出现「切换 Clash / 启动 Clash / 停止 Clash」；
- 点「启动 Clash」后 `vpn-tun` 起来（`172.19.0.1/30`，MTU 9000）；
- `--ps clashAction stop` 停掉，`vpn-tun` 与标记文件都消失；
- `clashAction toggle` 冷启动可用，再 toggle 一次按标记判定为「在跑」并停止；
- `-A ...action.TOGGLE_CLASH` 与 `-A ohos.want.action.viewData -U clash://toggle`
  两条既有形态行为一致。

新增 `backend/VpnRuntime.ets`：VPN 扩展跑在独立进程，而 `PersistenceV2` 是按进程
缓存的，所以「隧道在不在跑」用 `<filesDir>/vpn.running` 标记文件跨进程传递。
平台没有 `isRunning()` 之类的公开查询接口，`VpnObserver` 只报告授权弹窗的答复。

`TileService`（快捷设置磁贴）与 `DialerReceiver`（拨号盘密令）**不移植**：前者
HarmonyOS 不向三方应用开放，等价形态是服务卡片；后者没有公开的密令通道。
详见 `outputs/external-control-shortcuts-harmonyos.md`。

## 26. 设置 → 网络：7 个 VPN 行接成真实配置（已真机验证）

`NetworkSettingsPage` 上原本「33% 变淡 + 点了弹 `not_ported`」的 7 行现在是真控件：
`enableVpn` / `bypassPrivateNetwork` / `dnsHijacking` / `allowBypass` / `allowIpv6` /
`systemProxy` / `tunStackMode`。完整说明见 `outputs/vpn-settings-harmonyos.md`。

数据流：`VpnSettingsStore`（PersistenceV2，单 `@Trace` JSON，默认值逐字段对齐
`ServiceStore` / `UiStore`）→ `Index.ets` 启动扩展时经 `vpnTunnelParameters()` 塞进
Want（`vpnSettings` / `accessControlMode` / `accessControlPackages`）→
`ClashVpnExtension` 解码后构造 `VpnConfig` 并调用
`coreAttach(fd, stack, gateway, portal, dns)`。

真机覆盖了两个路由分支与两个 stack：

| 配置 | `VpnConfig` 日志 | 结果 |
|---|---|---|
| `bypassPrivate=true` + `stack=system` | `addresses=1 routes=75 dns=1 ipv6=false` | github 走代理 390 ms、baidu 直连 80 ms、同网段 192.168.239.74 直连 44 ms |
| `bypassPrivate=false` + `stack=mips` | `addresses=1 routes=1 dns=1 ipv6=false` | github 通、`vpn-tun 172.19.0.1/30 MTU 9000` |

75 = Android `bypass_private_route` 的 74 条 CIDR + 虚拟 DNS `172.19.0.2/32`；
1 = `0.0.0.0/0`。`mips` 是 `sing-tun` 的合法别名
（`case "", "mips": return NewMipstack(options)`），所以 Android 的默认值在 OHOS
上不会落到 `unknown stack`。

两处诚实降级：`systemProxy`（`VpnConfig` 无 proxy 字段，
`connection.setAppHttpProxy()` 是应用级不是系统级）与 `allowBypass`
（`trustedApplications` / `blockedApplications` 表达「谁在隧道里」而不是「谁能绕过」）。
两者照常存储与显示，summary 追加 `vpn_option_no_effect` 说明不生效。Android 在隧道
运行时禁用整组的 `running` 门控没有复刻，因为这里没有可读的运行状态。

顺带修好的一处 ABI 断裂：`cpp/napi_init.cpp` 与 Go 侧 `ohos_core_attach` 上一轮已经
改成 5 参数，但 `entry/src/main/cpp/prebuilt/arm64-v8a/libclash.so` 还是 1 参数旧产物
（旧 .so 会静默忽略后 4 个参数，stack/dns/gateway/portal 全部无效）。本次用
`work/toolchain/go1.27.2` 重编并替换，旧产物备份在
`work/ohos-clash-build/libclash.so.bak-1arg`。

未上机：`allowIpv6 = true` 分支、非空 `trustedApplications` / `blockedApplications`
的映射（设备上跑的是默认 `AcceptAll`，两个列表为空）。静态检查 `errorCount 0`，
`u build` → `BUILD SUCCESSFUL`。

---

## 27. 剩余功能并行收尾：QR、age key、快捷方式、网络设置接线

### 27.1 并行结果

本轮同时开了 5 个子 agent，覆盖剩余功能：

| 子 agent | 交付 | 状态 |
|---|---|---|
| Mencius | `VpnSettingsStore` + `NetworkSettingsPage` 7 行接线 + `ClashVpnExtension` `VpnConfig` 构造 | 已合并，真机验证 |
| Erdos | ProfilesPage 二维码分享（ArkUI `QRCode`）+ NewProfilePage `@kit.ScanKit` 扫码 | 已合并，分享弹层真机验证 |
| Boole | age key 生成/校验接 core + MetaFeature 对话框 | 已合并，真机验证 X25519 生成 |
| Locke | ExternalControl 快捷方式 + 启停动作 + `VpnRuntime` 标记文件 | 已合并，真机验证快捷方式 |
| 主 agent | 统一构建、ABI 校验、重启稳定性修复、最终设备状态 | 完成 |

### 27.2 VPN 设置接线（已真机验证）

`NetworkSettingsPage` 的 7 行现在全部可交互并持久化：

`enableVpn` / `bypassPrivateNetwork` / `dnsHijacking` / `allowBypass` /
`allowIpv6` / `systemProxy` / `tunStackMode`。

真机验证：

- 把 `dnsHijacking` 从 true 切到 false、把 `tunStackMode` 从 `mips` 切到
  `system`，停止再启动后扩展日志为：
  `settings: bypassPrivate=true dnsHijack=false ... stack=system`，
  `coreAttach(... dns=172.19.0.2)`，core 正常接管。
- `VpnConfig` 路由集：`bypassPrivate=true` 时 75 条（74 条私网 CIDR +
  虚拟 DNS `/32`），`bypassPrivate=false` 时 1 条默认路由。
- `allowBypass` 与 `systemProxy` 是诚实降级：值会存、会显示、会传给扩展，
  但 HarmonyOS `VpnConfig` 没有等价字段，summary 明确写“不生效”。

### 27.3 二维码分享/扫码

- `ProfilesPage` 的“二维码分享”用 ArkUI 原生 `QRCode` 组件渲染，不再
  `not_ported`；真机打开 WantVPN 菜单 → 二维码分享，标题、profile 名和
  二维码弹层正常。
- `NewProfilePage` 的 QR 入口改为 `@kit.ScanKit` 的
  `scanBarcode.startScanForResult`，取消错误码静默处理。
- 未实现系统分享面板；Android 的 `showProfileQrCode` 本身也只是展示二维码。

### 27.4 age key（已真机验证）

`work/clashmeta/core/src/main/golang/ohos/main.go` 新增 5 个 age 导出，
`libclashcore.so` 新增 `ageGenX25519` / `ageGenHybrid` /
`ageToPublicKeys` / `ageVerifySecretKeys` / `ageVerifyPublicKeys`。

真机在 Meta 特性页点 X25519 → 生成，得到：

```text
AGE-SECRET-KEY-136WPWPNE9J4K6WK20R3YNGZ259MYGENJQCNGLNHXRXCULQUA4QSSNHACFN
age148gt5l5xfclfzy3r707yush6hy53u5x8634ed94hwtv42ez8gg3qlagpl0
```

主 UI 进程加载 60 MB `libclash.so` 没有崩溃，说明 NAPI→Go runtime 在普通
ArkTS 进程也能初始化。当前 age key 只做到“生成/校验/复制”，还没有接到
profile 解密消费者上。

### 27.5 快捷方式与启停

`shortcuts_config.json` 提供三条静态快捷方式：切换 / 启动 / 停止。
`ExternalControl` 的 TOGGLE / START / STOP 改为真实
`startVpnExtensionAbility` / `stopVpnExtensionAbility`。

真机验证：

- 桌面长按图标出现「切换 Clash / 启动 Clash / 停止 Clash」；
- 点「启动 Clash」后 `vpn-tun 172.19.0.1/30 MTU 9000` 起来；
- stop 后 `vpn-tun` 与 `<filesDir>/vpn.running` 标记都消失；
- `clash://toggle|start|stop` 与 `clashAction` 两种入口行为一致。

平台限制：`TileService`（快捷设置磁贴）和 `DialerReceiver`（拨号密令）
没有公开等价物，不移植；详见
`outputs/external-control-shortcuts-harmonyos.md`。

### 27.6 重启稳定性修复

真机重启时曾复现一次 `ClashVpnExtension load timeout`，原因是
`protectProcessNet()` 在 VPN 刚销毁后调用会长时间挂起。修复：

- `ClashVpnExtension` 把 `protectProcessNet()` 移到 `connection.create()`
  **之前**；API 只保护“调用之后创建的 socket”，顺序正确且避免二次挂起；
- `Index.stopVpn()` 在 `stopVpnExtensionAbility` 后等待 1.5s，让平台完成
  上一次 `VpnConnection` 的拆除；
- `Index.onPageShow()` 用 `VpnRuntime.isVpnRunning()` 检查标记文件，避免
  extension 崩溃后 UI 还显示“运行中”。

修复后真机连续执行“启动 → 停止 → 再启动”，两次都正常，第二次日志为
`stack=system`、`dns=172.19.0.2`、`mihomo core attached`。

### 27.7 最终验证

- `u build clean` + `u build`：`BUILD SUCCESSFUL`。
- `hmos-precheck --profile arkts-diff`：`errorCount: 0`；`ok:false` 仍只是
  已知环境缺陷 #4（permission catalog `backend-unavailable`）。
- 设备最终状态：`WantVPN` 激活，VPN 运行中，`vpn-tun` 为
  `172.19.0.1/30`、MTU 9000；主界面显示运行中与累计转发。

---

## 28. WantVPN 真实可用性收口与剩余缺口

这一轮先解决“能不能真的上网”，再补剩余缺口。最终真机链路不再是 mock：

- 真订阅下载成功，`WantVPN` 为活动 profile；
- `vpn-tun` 为 `172.19.0.1/30`、MTU 9000；
- external controller 在 `127.0.0.1:9090`；
- 真节点 `CN丨香港03` 对 `https://github.com` 的 delay 为 130-219ms；
- 手机浏览器实际加载出 GitHub `rootWebArea`；
- 连续观察 2 分钟，VPN 进程、主进程、`vpn-tun` 和 controller 都保持；
- 停止 VPN 后 `vpn-tun` 消失、controller 停止监听，直连网络恢复；
- 再启动后 controller、`vpn-tun` 和 GitHub delay 再次正常。

### 28.1 关键根因：OHOS FdLeakDetector 杀 VPN 进程

设备日志里 VPN 进程会在约 90 秒后被系统杀死：

```text
FdLeakInfo: process: com.example.clashmeta:vpn fd handler leaked, fdcnt:24626
Kill Reason: ResourceLeak:Fd Leak
```

根因不是代理节点本身。Android 的 `TunModule` 把 `VpnService.protect` 作为
`markSocket` 回调传给 Go core，core 每创建一个出站 socket 就先调用它。OHOS
最初只调用了进程级 `protectProcessNet()`，而部分 Go raw socket 没有被覆盖，
代理连接回环进 TUN，连接风暴把 fd 撑到 24626。

修复分两层：

1. `protectProcessNet()` 提前到 `corePrepare()` 之前，覆盖 core 启动阶段创建的
   socket；
2. 补上 Android 同款 per-socket 链路：
   - Go `dialer.DefaultSocketHook` 回调 `ohos_core_set_mark_socket` 注册的 C 函数；
   - C 函数通过 NAPI threadsafe function 把 fd 送到 ArkTS 线程；
   - ArkTS 调用 `VpnConnection.protect(fd)`，完成后调用
     `coreMarkSocketDone(fd)` 释放 Go dialer 等待；
   - Go 侧对每次回调做 2 秒上限等待，protect 完成后才继续 connect。

### 28.2 路由侧兜底

`ClashVpnExtension` 还会从 `config.yaml` 解析 proxy `server:` 和 DNS
`nameserver:`，先通过 core 自己的 `/dns/query` 拿到它实际会使用的 A 记录，
再从 VPN route 集合里减去这些 `/32`。因此即使进程级保护在某个 OHOS 版本上
不完整，core 拨号到 proxy/DNS 的流量也不会回环进 TUN。

### 28.3 本轮补齐的缺口

- **age 解密已接通**：active profile 的 `ageSecretKey` 经 `Want` 传到扩展，
  在 `corePrepare()` 前调用 `coreSetAgeSecretKey()`；加密订阅由 core 的
  `UnmarshalAndPatch` 解密。
- **服务卡片**：新增 2x4 `ClashCard.ets` + `EntryFormAbility.ets`，卡片提供
  启动/切换/停止按钮，`module.json5` 注册 form extension。平台没有 Android
  TileService/拨号密令的公开等价物，卡片是可用替代形态。
- **IPv6 真机验证**：`allowIpv6=true` 时 `addresses=2`、`routes=84`、
  `dns=2`，`coreAttach` 带 `fdfe:dcba:9876::1/126` 和
  `fdfe:dcba:9876::2`；IPv4 连接仍正常。
- **访问控制真机验证**：
  - `AcceptSelected` + `com.huawei.hmos.browser`：
    `trusted=2`（浏览器 + 自身），`blocked=0`；
  - `DenySelected` + 同一包：`trusted=0`，`blocked=1`；
  - 验证后恢复 `AcceptAll`、清空包列表。
- **gvisor**：失败点已定位到上游
  `fdbased.New -> IsSocketFD -> unix.Fstat -> EPERM`，fail-closed 补丁在
  `outputs/gvisor-ohos-fstat-fallback.patch`。当前可用默认仍是 `system`；
  未把未上机验证的 gvisor 补丁塞进最终 HAP。

### 28.4 剩余平台限制

- `systemProxy` / `allowBypass`：OHOS `VpnConfig` 没有等价字段，继续诚实降级。
- `TileService` / 拨号密令：没有公开等价物，服务卡片和静态快捷方式替代。
- `mixed`：ping 可通，但完整浏览器回归未通过；最终使用 `system`。
- HAP 仍约 63MB，后续可做 core 裁剪或按需加载。

---

## 29. 平台限制续攻（本轮，逐条给结论）

§28.4 那四条里，本轮把每条都真的去撞了一遍，结论分三类：**已达成并上机验证**、
**已达成但只在特权签名下生效**、**明确证明不可达**。以下每条都带可复现的证据。

### 29.1 `tun_stack_mode` 选择器：已达成，真机验证（新）

§14 记的「整页禁用」里 `Stack Mode` 当时是禁用占位；代码里 `tunStackMenu()`
其实已经接好（`PreferenceList` + `settings.tunStackMode` + `update()`），本轮
在真机上把它走完了：

| 步骤 | 结果 |
|---|---|
| 设置 → 网络 → Stack Mode | 菜单展开 `System Stack` / `Gvisor Stack ✓` / `Mixed Stack` / `Mips Stack`，当前项带勾 |
| 选 `System Stack` | 行摘要变成 `System Stack`；重启隧道后 `coreAttach(fd=51, stack=system, ...)` → `mihomo core attached` |
| 选回 `Gvisor Stack` | `coreAttach(fd=52, stack=gvisor, ...)` → `mihomo core attached` |
| 停止 → 直连 → 再启动 | `vpn-tun` 消失、controller 停止监听；再启动后两者恢复 |
| 150 秒稳定性 | `vpn-tun` 与 `:vpn` 进程全程存在，`FdLeakInfo` 计数 0 |

也就是说 §28.4 里「最终使用 system」已经不成立：`system` 与 `gvisor` 两条栈都
真机跑通，选择器可在运行时切换。

### 29.2 访问控制应用包列表：不可达，已证明（有实测报错）

本轮把「换个 API 枚举」这条路彻底走死，并留下了精确证据。前提是
`ohos.permission.GET_BUNDLE_INFO` **已经声明且已授予**（真机 `bm dump`：
`reqPermissionStates: [0, 0, 0]`），但：

```text
getBundleNameByUidSync(uid)
  -> 201 "An attempt was made to GetBundleNameByUidSync forbidden by permission:
     ohos.permission.GET_BUNDLE_INFO or ohos.permission.GET_BUNDLE_INFO_PRIVILEGED."

getBundleInfo(other, GET_BUNDLE_INFO_WITH_APPLICATION|WITH_REQUESTED_PERMISSION)  // flags=17
  -> 201 "... GetBundleInfo forbidden by permission: ohos.permission.GET_BUNDLE_INFO_PRIVILEGED."

getBundleInfo(other, GET_BUNDLE_INFO_DEFAULT)
  -> 201 同上
```

结论：**目标不是自己时，这些接口一律要求 `GET_BUNDLE_INFO_PRIVILEGED`
（`availableLevel: system_basic`）**；`GET_BUNDLE_INFO`（normal）单独持有买不到
任何东西。SDK 注释里那句「The application requires to be a system application
when requesting the permission of ohos.permission.GET_BUNDLE_INFO」是真话。

本轮据此做了两件事，都不假装成功：

- `InstalledApps.ets` 新增 `scanInstalledApps()`：按
  `base = uid - (uid % 1000)` 推基址（真机 `base=20020000`），扫 2048 个 uid，
  分批 `setTimeout` 让出主线程并回报进度；在特权签名下这条路径即可用。
- 页面把它放成溢出菜单的 **Scan installed apps**，触发后若 0 行则弹
  `access_control_scan_denied`；页面顶部提示改成实测口径：
  「the list, the by-uid lookup and the per-package lookup all require a
  system_basic permission」。

因此这一条仍是**普通签名下不可达**，但不再是「没试过」——它是本轮唯一一条
撞到硬墙且能给出报错原文的。

### 29.3 实时日志（Logcat 流式）：试过、能连、**回退了**

`outputs/logcat-streaming-harmonyos-feasibility.md` 的结论是「读别的进程 HiLog
无公开 API」。本轮换了生产者：core 自己跑在 VPN 扩展进程里，它把日志挂在
external controller 的 `GET /logs`（WebSocket 逐帧
`{"type":"info","payload":"..."}`）。实现后真机表现：

- 页面能打开，级别菜单（debug/info/warning/error）可用；
- 连接成功：状态行 `info - connected`，切到 debug 后 `debug - connected`；
- **但**保持这条 socket 打开时，应用进程（连带隧道）在约 60 秒内结束：

```text
run A  log page open, level switched   -> 16:58:18 attach, 17:00:26 onDestroy
run B  log page open, no level switch  -> 17:02:37 attach, ~17:03:40 died
run C  main page, no log page          -> 150s alive, FdLeak 0
run D  main page + 8x ui layout dumps  -> 150s alive
run E  log page open, no dumps         -> tun=0 between t=40 and t=60
```

日志里是 `onTerminateScene ... terminateReason: 2` 后
`com.example.clashmeta ... exit with code:0`，没有 JS 异常、没有 `FdLeakInfo`。
也就是说这条 socket 会让 UI 进程被正常终止，而 UI 进程一死，平台就把 VPN
扩展一起收掉（`VpnKeepAlive` 的连续任务救不了它）。

**决定：回退。** 删掉 `ControllerLogStream.ets` 与 `StreamingLogViewModel.ets`，
`LogsPage` 的 Clash Logcat 行恢复成禁用态 + `not_ported`。理由很直接：
一个实时日志页不值得拿 VPN 可用性去换。复现步骤与五次对照都在本节，
谁要重开这条线先看这里。

### 29.4 文件打开（Android `ACTION_VIEW`）：代码已改，未上机验证

§16.5 记的是「沙箱 URI 没授权给目标应用，预览失败 → not_ported」。本轮改成
Android 同款做法：

- `Want.flags = wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION`
  （`@ohos.app.ability.wantConstant.d.ts`，`0x00000001`）；
- 去掉 `entity.system.browsable`（那是给 URL 用的，文本文件不该要求浏览器）；
- 失败时 toast 打真实 `error.message`，不再一律 `not_ported`。

显式 `uriPermissionManager.grantUriPermission` 没用：它要
`ohos.permission.PROVISIONING_GRANT_PERMISSION`（`system_basic`）。
这条**未做真机验证**（入口在「配置 → 某个 profile → 属性 → 文件」四层深处），
状态按「代码完成、未验证」记。

### 29.5 其余三条：确认没有公开 API

| 项 | 本轮动作 | 结论 |
|---|---|---|
| `systemProxy` | 全 SDK 搜 proxy：只有 `setAppHttpProxy`（仅本应用）、`getDefaultHttpProxy`、`findProxyForUrl`；`setPacUrl`/`setPacFileUrl` 要 `SET_PAC_URL`（`system_basic`） | 无系统级入口。TUN 已接管全部应用流量，行文案保持现状 |
| `allowBypass` | OHOS 无「应用自行 opt-out」API | 继续用「DenySelected 列表 + allowBypass 总开关」等价实现 |
| `TileService` / 拨号密令 | OpenHarmony `ets/api` 与 HMS `hms/ets/api` 全量搜 tile/quickSwitch/controlCenter/secretCode：只有 `@hms.pcService.quickBarManager`（PC 专用） | 手机侧无公开等价物；服务卡片 + 静态快捷方式仍是替代 |

### 29.6 HAP 体积

66,099,298 字节，其中 `libs/arm64-v8a/libclash.so` 62,603,344（94.7%）。
`libgoprobe.so` 不在包里（`unzip -l` 确认），没有可捡的边角；要显著变小只能裁
core（例如按栈拆 `with_gvisor`），代价是产物翻倍，本轮不做。

### 29.7 本轮回归

- `u build clean` + `u build`：`BUILD SUCCESSFUL`；
- `u check arkts`（`InstalledApps.ets` / `AccessControlPage.ets` / `LogcatPage.ets`
  / `LogsPage.ets` / `FilesPage.ets`）：`No errors found`；
- 真机：`WantVPN` 激活，`stack=gvisor`，`vpn-tun` 在线，150 秒无 `FdLeakInfo`；
- 访问控制页：提示条为实测文案，`Scan installed apps` 可跑并落 201 日志，
  手输包名仍可加入并持久化。
