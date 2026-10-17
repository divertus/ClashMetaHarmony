# CMFA Remaining Screens Port Plan

Date: 2026-10-16  
Source: `work/clashmeta` at `3cc102aab3f251ef460a3b6e2835b6c1eb581e73`  
Target: ArkTS + ArkUI V2 (`@ComponentV2` / `@ObservedV2` / MVVM)

Scope paths:

- Activities: `app/src/main/java/com/github/kr328/clash/*Activity.kt`
- Designs: `design/src/main/java/com/github/kr328/clash/design/*Design.kt`
- Layouts: `design/src/main/res/layout/*.xml`
- Current target: `outputs/ClashMetaHarmony/entry/src/main/ets/`

Count note: there are 20 top-level `*Activity.kt` files. Of these, 18 render a screen, `ExternalControlActivity` is a headless entry point, and `BaseActivity` is the shared shell. `MainActivity` is already ported; this plan covers the remaining 17 screen Activities plus the shared shell and headless route.

## 1. Activity Enumeration

`LOC` is physical lines from `wc -l`, shown as `Activity / Design`. Layout variables are the XML `<variable>` names and types. The activity path is `app/src/main/java/com/github/kr328/clash/<Name>.kt`; the design path is `design/src/main/java/com/github/kr328/clash/design/<Name>Design.kt`.

| Activity | Layout and data-binding variables | LOC | Main dependencies |
|---|---|---:|---|
| `AccessControlActivity` | `design_access_control.xml`: `self:AccessControlDesign` | 155 / 133 | `ServiceStore.accessControlPackages`; `PackageManager.getInstalledPackages`; `ClipboardManager`; restart via `startClashService` / `stopClashService`; app list/search menu |
| `ApkBrokenActivity` | `design_settings_common.xml`: `surface:Surface` | 19 / 47 | Static tips; opens GitHub releases with `Intent.ACTION_VIEW` |
| `AppCrashedActivity` | `design_app_crashed.xml`: `self:AppCrashedDesign` | 32 / 28 | `PackageManager.getPackageInfo`; `SystemLogcat.dumpCrash`; renders crash text |
| `AppSettingsActivity` | `design_settings_common.xml`: `surface:Surface` | 78 / 104 | `PackageManager` component enable/disable; `ServiceStore.dynamicNotification`; `UiStore` dark mode and hide-from-recents; activity recreation. **已移植**：暗黑模式可用，其余三行 stub（见 status §13） |
| `BaseActivity` | None | 234 / - | Shared shell: `UiStore`, `Remote.broadcasts`, activity-result lifecycle, theme/insets, `clashRunning`, common event channel |
| `ExternalControlActivity` | None | 108 / - | Headless intents: view-profile, toggle/start/stop; `StatusClient`; `withProfile`; `startClashService` / `stopClashService`; opens `PropertiesActivity` |
| `FilesActivity` | `design_files.xml`: `self:FilesDesign`, `currentInBaseDir:boolean`, `configurationEditable:boolean` | 141 / 123 | `withProfile`; `FilesClient` over DocumentsProvider/ContentResolver; SAF GetContent/CreateDocument; `ACTION_VIEW`; directory stack. **已移植**：沙箱文件树 + `DocumentViewPicker`（status §16） |
| `HelpActivity` | `design_settings_common.xml`: `surface:Surface` | 18 / 78 | Static documentation list; opens links with `Intent.ACTION_VIEW` |
| `LogcatActivity` | `design_logcat.xml`: `self:LogcatDesign`, `streaming:boolean` | 187 / 69 | Local file read/export; streaming via `LogcatService` + `RemoteService` + `Clash.subscribeLogcat`; clipboard copy; notification foreground service |
| `LogsActivity` | `design_logs.xml`: `self:LogsDesign` | 66 / 56 | Lists/deletes files under `cacheDir/logs`; opens `LogcatActivity` |
| `MainActivity` | `design_main.xml`: `self:MainDesign`, `clashRunning:boolean`, `forwarded:String`, `mode:String`, `profileName:String`, `colorClashStarted:int`, `colorClashStopped:int`, `hasProviders:boolean` | 214 / 90 | `withClash` tunnel/providers/traffic; `withProfile` active profile; `startClashService` / `stopClashService`; `Bridge.nativeCoreVersion`; `ShortcutManagerCompat`; notification permission; navigation to 7 screens. UI already ported |
| `MetaFeatureSettingsActivity` | `design_settings_meta_feature.xml`: `self:MetaFeatureSettingsDesign` | 136 / 421 | `withClash` persist override read/write/clear; JNI age-key helpers in design; file import via `OpenableColumns`; writes `clashDir`. **已移植**：四个 category 25 行照搬（`clickable` 行做成 `OverrideKind.Action`），外壳与覆写页共用 `view/PreferenceScreen.ets`，geofile 走 `DocumentViewPicker` + `filesDir/clash/`，age key 两行报 `not_ported`（status §18） |
| `NetworkSettingsActivity` | `design_settings_common.xml`: `surface:Surface` | 39 / 153 | `UiStore.enableVpn`; `ServiceStore` TUN/DNS/access-control options; running state; opens `AccessControlActivity`; effect depends on `VpnService`. **已移植**：版面与顺序 1:1；访问控制已可用；VPN 行仍待接 `VpnConfig`（core/TUN 已在 status §23 跑通） |
| `NewProfileActivity` | `design_new_profile.xml`: `self:NewProfileDesign` | 200 / 56 | `withProfile.create`; `PackageManager.queryIntentActivities` for `ACTION_PROVIDE_URL`; app-details intent; QR scanner result; opens `PropertiesActivity`. **已移植**：文件/URL 可建，QR 与外部 provider 报 `not_ported`（status §15） |
| `OverrideSettingsActivity` | `design_settings_overide.xml`: `self:OverrideSettingsDesign` | 57 / 419 | `withClash` persist override read/write/clear; very large preference tree. **已移植**：34 行全部照搬，值存本地 `OverrideStore`，退出时把 `PATCH /configs` 能吃下的 11 个字段下发给正在运行的 core（status §17） |
| `ProfilesActivity` | `design_profiles.xml`: `self:ProfilesDesign` | 129 / 200 | `withProfile` query/update/delete/clone/set-active; ZXing QR generation; bottom-sheet menu; opens `NewProfileActivity` / `PropertiesActivity`. **已移植**：本地 store + 卡片列表 + 溢出菜单（status §15） |
| `PropertiesActivity` | `design_properties.xml`: `self:PropertiesDesign`, `profile:Profile`, `processing:boolean` | 115 / 190 | `withProfile` query/patch/commit/release; `FetchStatus` progress; profile model; opens `FilesActivity`. **已移植**：名称/URL/Age 私钥/自动更新/保存 + 未保存退出确认；浏览文件报 `not_ported`（status §15） |
| `ProvidersActivity` | `design_providers.xml`: `self:ProvidersDesign` | 71 / 62 | `withClash.queryProviders` / `updateProvider`; `Provider` model; elapsed-time refresh |
| `ProxyActivity` | `design_proxy.xml`: `self:ProxyDesign` | 117 / 176 | `withClash` group names/group/select/health/override session; `ViewPager2` + `TabLayout`; proxy models; URL-test state |
| `SettingsActivity` | `design_settings.xml`: `self:SettingsDesign` | 33 / 32 | Navigation only: App, Network, Override, Meta Feature |

Relevant source anchors:

- `core/src/main/java/com/github/kr328/clash/core/Clash.kt`
- `core/src/main/java/com/github/kr328/clash/core/bridge/Bridge.kt`
- `service/src/main/java/com/github/kr328/clash/service/TunService.kt`
- `service/src/main/java/com/github/kr328/clash/service/ProfileProcessor.kt`
- `app/src/main/java/com/github/kr328/clash/remote/FilesClient.kt`
- `app/src/main/java/com/github/kr328/clash/log/SystemLogcat.kt`

## 2. Porting Tiers

| Tier | Activities | Why this tier / hard parts |
|---|---|---|
| 1. Cheap pure UI | `SettingsActivity`, `HelpActivity`, `ApkBrokenActivity`, `LogsActivity`, `AppCrashedActivity` UI shell | Plain lists, static preferences, local file listing, and text rendering. Only browser launch and cache-directory storage are platform work. For `AppCrashedActivity`, inject the crash text; the real Android logcat dump is not portable as-is. |
| 2. Platform adapters | `FilesActivity`, `NewProfileActivity`, `AppSettingsActivity`, `NetworkSettingsActivity`, `AccessControlActivity` | No direct mihomo JNI in the screen code, but Android contracts must be replaced: SAF/DocumentsProvider/ContentResolver, `PackageManager` / `QUERY_ALL_PACKAGES`, component alias enable/disable, notifications, intents, and `VpnService` semantics. On HarmonyOS these need BundleManager, FilePicker, Preferences, Want/Ability, and — **更正**：VPN/TUN 不需要「重新设计」，平台有公开的三方 VPN API（`VpnExtensionAbility` + `@ohos.net.vpnExtension`，见 status §21/§23），mihomo core + TUN 已真机跑通。 |
| 3. Core/service-backed data | `ProfilesActivity`, `PropertiesActivity`, `ProxyActivity`, `ProvidersActivity` | These carry the app's real data. Profile CRUD and commit are service-backed and partly core-backed; proxy/provider screens map only partially to the mihomo external-controller API. UI work is also substantial: ViewPager2/TabLayout replacement, bottom sheets, QR rendering, progress dialogs, and nested proxy state. |
| 4. Hard-blocked | `MainActivity` backend, `ExternalControlActivity`, `OverrideSettingsActivity`, `MetaFeatureSettingsActivity`, `LogcatActivity` streaming | Direct blockers are `Bridge.native*` / `Clash` JNI, foreground/bound services, Android notifications, `ShortcutManager`, `PackageManager`, and Android `logcat`. **`VpnService` 已不在这个列表里**：HarmonyOS 有公开等价物，mihomo core 也已编成 OHOS arm64 并接上 TUN（status §21/§23）。`MainActivity` UI 与后端收尾都做完了；`LogcatActivity` local-file mode 已移植，只有 streaming mode 判定不移植。 |

### Pure UI wins with no app backend dependency

- `SettingsActivity`
- `HelpActivity`
- `ApkBrokenActivity`
- `LogsActivity`
- `AppCrashedActivity` UI shell, if the log text is supplied by the caller
- `LogcatActivity` local-file mode, if streaming mode is deferred

### Blocked on the native core or an Android-only primitive

- Direct mihomo JNI: `MainActivity` backend, `ProxyActivity`, `ProvidersActivity`, `OverrideSettingsActivity`, `MetaFeatureSettingsActivity`, `PropertiesActivity` commit, `ProfilesActivity` active/update, and `LogcatActivity` streaming.
- **（已更正）** Android `VpnService` **有**公开的 HarmonyOS 等价物：`VpnExtensionAbility` + `@ohos.net.vpnExtension`（API 11+，只需 `ohos.permission.INTERNET`），本端口已实测建出 `vpn-tun`、拿到 tun fd，并把 mihomo core 编成 OHOS arm64 接上真实订阅（status §21/§23）。当前剩下的工作是 UI 启停和 active profile 接线，不是平台/核心阻塞。
- Android platform APIs: `ShortcutManager` and notifications in `MainActivity`; `PackageManager` in `AppSettingsActivity`, `AccessControlActivity`, and `NewProfileActivity`; DocumentsProvider/SAF in `FilesActivity`; foreground/bound services in `LogcatService`; system logcat in `AppCrashedActivity`.

The external-controller route can unblock `ProxyActivity` and `ProvidersActivity` for a remote mihomo instance. It cannot provide profile CRUD, local access control, TUN startup, or the full override API.

## 3. Recommended Port Order

| Order | Activity or work item | Rationale |
|---:|---|---|
| 0 | `BaseActivity`-equivalent shell | **已完成**（status §2–§4）。V2 页面外壳、导航、主题/insets、生命周期与后端契约都定下来了。 |
| 1 | `SettingsActivity` | **已完成**（status §5）。四个设置分支的导航枢纽。 |
| 2 | `HelpActivity` | **已完成**（status §6）。静态列表 + 外链。 |
| 3 | `ApkBrokenActivity` | **已完成**（status §6）。静态恢复页。 |
| 4 | `AppCrashedActivity` | **已完成**（status §6）。崩溃文本由调用方注入，Android 的 logcat 抓取不移植。 |
| 5 | `LogsActivity` | **已完成**（status §6）。本地日志文件列表/删除，验证了 cache 目录存储。 |
| 6 | `LogcatActivity` local-file mode | **已完成**（status §6）。复用日志列表与文件查看；流式模式见第 18 项。 |
| 7 | `FilesActivity` | **已完成**（status §16）。沙箱 `profiles/<uuid>/` 文件树 + 列表/新建/重命名/删除 + `DocumentViewPicker` 导入导出；「打开文件」按 Android 的方式交接给外部应用，实测被系统预览接走并失败（平台限制）。 |
| 8 | `NewProfileActivity` | **已完成**（status §15）。文件/URL 建出 pending 记录后进编辑器；QR 与 `ACTION_PROVIDE_URL` 外部 provider 报 `not_ported`。 |
| 9 | `ProfilesActivity` | **已完成**（status §15）。本地 `ProfileStore` + 卡片列表 + 溢出菜单 + 激活/复制/删除，强杀重启后仍在。 |
| 10 | `PropertiesActivity` | **已完成**（status §15/§27）。名称/URL/Age 私钥/自动更新可编辑并提交；URL fetch、二维码分享/扫码已接；core reload 仍由下次启动生效。 |
| 11 | `ProvidersActivity` | **已完成**（status §8）。external-controller `/providers/proxies` + `/providers/rules` 是最直接的 core 映射。 |
| 12 | `ProxyActivity` | **已完成**（status §7）。标签页、选择、延迟测试、模式切换、过滤/列数/排序都已在真机验证。 |
| 13 | `AppSettingsActivity` | **已完成**（status §13）。暗黑模式接 `ApplicationContext.setColorMode` + `base/`/`dark/` 语义色；hide-icon / restart / recents / notification 四行 stub 报 `not_ported`。 |
| 14 | `NetworkSettingsActivity` | **已完成**（status §14/§22/§26）。7 个 VPN 行已接 `VpnSettingsStore` → Want → `VpnConfig`；访问控制模式和应用包列表可用；`systemProxy`/`allowBypass` 为平台无等价能力的诚实降级。 |
| 15 | `AccessControlActivity` | **已完成**（status §20/§22）。平台枚举受 `system_basic` 限制，已做手输/导入包名 + 已选包名渲染 + 完整溢出菜单；改选后的服务重启由下一次 VPN 启动生效。 |
| 16 | `OverrideSettingsActivity` | **已完成**（status §17）。四个 builder 的 34 行做成 `OverrideRow[]` 表，四种行共用 `preference_clickable.xml` 形状，所以复用 `ActionLabel` / `PreferenceList`；值过 `PersistenceV2`，退出时把 `config.General` 子集 `PATCH /configs`；`hosts` 与整个 DNS 子树 `PATCH` 不带，只存不发。 |
| 17 | `MetaFeatureSettingsActivity` | **已完成**（status §18/§27）。与覆写页共用外壳（`PreferenceScreen`）和同一条 persist 记录；`sniffing` + 四个 `General` 开关随 `PATCH /configs` 下发；age X25519 / MLKEM768-X25519 生成、校验、复制已接 core。 |
| 18 | `LogcatActivity` streaming mode | **结论：不移植**（status §19.2）。Android 的流式模式是前台服务订阅进程内 core 的日志，HarmonyOS 没有给三方应用读别的进程 HiLog 的公开 API，相关权限都是 system/企业级。证据与替代方案见 `outputs/logcat-streaming-harmonyos-feasibility.md`；页面保持 `not_ported`。 |
| 19 | `ExternalControlActivity` | **已完成**（status §19.1/§25）。`Want` 路由放在 `EntryAbility.onCreate`/`onNewWant` + `backend/ExternalControl.ets`；`clash://profiles`、`clash://install-config?url=…`、`clash://toggle|start|stop` 和三条静态快捷方式均已实测；磁贴/拨号密令无公开等价物。 |
| 20 | `MainActivity` backend and route wiring | **已完成**（status §19.3/§23）。审计逐条对照后补了两处（`hasProviders` 走规则+代理 providers 合并、About 用 `bundleManager` 的 versionName）；VPN core/TUN 已真机跑通，主界面启停和 active profile 接线也已验证。 |
