# 服务卡片 / 动态快捷方式（HarmonyOS 端口）

范围：ClashMetaForAndroid 的 `TileService`、动态快捷方式、拨号密令，以及
HarmonyOS 上对应的服务卡片入口。

结论先行：

- **服务卡片可以替代 `TileService` 的“快速启停”用途。** 已实现一个
  `FormExtensionAbility` 卡片，卡片上的启动/停止/切换按钮通过
  `postCardAction(..., { action: 'message' })` 进入 `onFormEvent()`，由卡片提供方
  直接调用 `@ohos.net.vpnExtension` 控制 `ClashVpnExtension`。
- **动态快捷方式没有 Android 那种“任意创建/更新”公开 API。** 现有三条
  静态快捷方式保留；`@ohos.bundle.shortcutManager` 只能查询和显隐已有快捷方式，
  HMS 的 `productViewManager` 只能请求用户把静态快捷方式钉到桌面。
- **`TileService` 和拨号密令没有公开等价物。** 服务卡片是平台提供的替代入口，
  拨号密令不做移植。

## 1. 平台能力与本地证据

### 1.1 服务卡片

本地 SDK / DevEco 模板确认了以下结构：

- `entry/src/main/module.json5` 中声明
  `extensionAbilities` 条目：`type = "form"`，`metadata.name =
  "ohos.extension.form"`，`resource = "$profile:form_config"`。
  DevEco 自带模板：
  `/Applications/DevEco-Studio.app/Contents/plugins/codegenie-plugin/previewProject/entry/src/main/module.json5`。
- `form_config.json` 的 `forms[]` 至少需要 `name`、`description`、`src`、
  `uiSyntax`、`window`、`isDynamic`、`defaultDimension`、`supportDimensions`。
  模板：
  `/Applications/DevEco-Studio.app/Contents/plugins/openharmony/lib/templates/widget/common/stageMode/ets/form_config.json.ftl`。
- 卡片内部交互使用 `postCardAction(component, action)`，`action` 支持
  `router`、`message`、`call`。`message` 会调用提供方
  `FormExtensionAbility.onFormEvent(formId, message)`。本地 API 文档：
  `.../JsEtsAPIReference/zh-cn_topic_0000002579060318.html`（`postCardAction`）
  和 `zh-cn_topic_0000002579220798.html`（`FormExtensionAbility.onFormEvent`）。
- 卡片状态刷新使用 `formBindingData.createFormBindingData()` +
  `formProvider.updateForm(formId, data)`。卡片 UI 用
  `@LocalStorageProp('key')` 接收数据。

### 1.2 动态快捷方式

本地 SDK 里的公开 API：

- `@ohos.bundle.shortcutManager`（API 20+）：
  `setShortcutVisibleForSelf(id, visible)`、`getAllShortcutInfoForSelf()`、
  `isShortcutSupported()`（API 26）。
- `@hms.core.appgalleryservice.productViewManager`（HMS，API 14+）：
  `checkPinShortcutPermitted()`、`requestNewPinShortcut()`、
  `getPinShortcutInfos()`、`removePinShortcut()`。

这两个接口都不提供“在应用启动时动态创建一批新快捷方式”的能力。它们能做的是
显隐 `module.json5` 里已经声明的快捷方式，或者在用户确认后把静态快捷方式钉到桌面。

所以本端口保持诚实降级：

- `resources/base/profile/shortcuts_config.json` 的三条静态快捷方式继续保留；
- 不伪造 Android `ShortcutManagerCompat.setDynamicShortcuts()` 的行为；
- “隐藏应用图标时跳过快捷方式”仍留待“隐藏应用图标”设置本身移植后一起做。

### 1.3 TileService / 拨号密令

- 快捷设置磁贴：HarmonyOS 不向普通三方应用开放控制中心磁贴注册。服务卡片是
  平台提供的公开替代形态，但不是 `TileService` 的 API 等价物。
- 拨号密令：HarmonyOS 没有 `android.provider.Telephony.SECRET_CODE` 这类公开
  通道，`*#*#252746382#*#*` 不做移植。

## 2. 本端口的实现

### 2.1 卡片 UI

文件：`entry/src/main/ets/widget/pages/ClashCard.ets`

- 2x4 动态 ArkTS 卡片；
- 顶部显示 `ClashMeta`、运行状态和当前 profile；
- 顶部区域点击后通过 `router` 事件打开主界面，作为手动操作和排障入口；
- 三个操作按钮：启动、切换、停止；
- 每个按钮调用：

  ```ts
  postCardAction(this, {
    action: 'message',
    params: { message: 'clash:start' | 'clash:toggle' | 'clash:stop' }
  });
  ```

### 2.2 卡片提供方

文件：`entry/src/main/ets/entryformability/EntryFormAbility.ets`

- `onAddForm()` 返回初始状态；
- `onUpdateForm()` 刷新状态；
- `onFormEvent()` 解析 `clash:start` / `clash:toggle` / `clash:stop`；
- 启动时读取活动 profile 和 `vpnTunnelParameters()`，构造和主界面相同的
  `Want`，调用 `vpnExtension.startVpnExtensionAbility()`；
- 停止时调用 `vpnExtension.stopVpnExtensionAbility()`；
- 切换时读取 `VpnRuntime.isVpnRunning()` 决定启动还是停止；
- 操作后调用 `formProvider.updateForm()` 刷新卡片状态。

### 2.3 与 VpnExtension 的通信

卡片提供方不经过 `EntryAbility` 的 UI 路由，直接控制
`ClashVpnExtension`：

```
ClashCard.ets
  --postCardAction(message)-->
EntryFormAbility.onFormEvent()
  --vpnExtension.startVpnExtensionAbility / stopVpnExtensionAbility-->
ClashVpnExtension
```

这条路径复用了主界面相同的 `Want` 参数：`vpnSettings`、访问控制模式/包列表、
`profileUuid`、`profileSource`、`ageSecretKey`。

**未上机验证的平台风险**：`FormExtensionAbility` 进程直接调用
`startVpnExtensionAbility()` 是否被系统允许，以及该进程读取
`PersistenceV2` 中的 profile/网络设置是否正常，必须在真机上确认。如果系统限制
表单扩展进程启动 VPN 扩展，备选路径是让卡片按钮改为 `router` 事件拉起
`EntryAbility`，由已经验证过的 `ExternalControl` 执行动作；代价是主界面会被带到
前台。

## 3. 改动文件

| 文件 | 内容 |
|---|---|
| `entry/src/main/module.json5` | 新增 `EntryFormAbility`（`type: "form"`），指向 `$profile:form_config` |
| `entry/src/main/resources/base/profile/form_config.json` | 新增 2x4 动态卡片声明 |
| `entry/src/main/ets/widget/pages/ClashCard.ets` | 新增卡片 UI 与三个 `message` 动作 |
| `entry/src/main/ets/entryformability/EntryFormAbility.ets` | 新增卡片生命周期、启停/切换、状态刷新 |
| `entry/src/main/resources/base/element/string.json` | 新增卡片展示名/描述 |
| `entry/src/main/resources/zh/element/string.json` | 新增中文卡片展示名/描述 |
| `outputs/external-control-shortcuts-harmonyos.md` | 更新“服务卡片未实现”的旧结论 |

## 4. 静态验证

以下命令在项目根目录执行：

```bash
jq empty \
  entry/src/main/resources/base/profile/form_config.json \
  entry/src/main/resources/base/element/string.json \
  entry/src/main/resources/zh/element/string.json

u() { node /Users/hikaritus/Documents/Codex/2026-10-16/github-ios-android-android-ios-android-6/work/hometrans-cli/node_modules/@deveco/deveco-cli/cli.js "$@"; }

u check arkts \
  entry/src/main/ets/entryformability/EntryFormAbility.ets \
  entry/src/main/ets/widget/pages/ClashCard.ets

u check lint entry/src/main/ets/entryformability/EntryFormAbility.ets
u check lint entry/src/main/ets/widget/pages/ClashCard.ets
```

结果：

- `jq empty`：通过；
- `u check arkts`：`No errors found in 2 file(s)`；
- `u check lint`：两个文件均 `No defects found`；
- 单独执行 ArkTS 编译任务：

  ```bash
  /Applications/DevEco-Studio.app/Contents/tools/node/bin/node \
    /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js \
    --mode module -p module=entry@default -p product=default -p buildMode=debug \
    default@CompileArkTS --analyze=normal --parallel --incremental
  ```

  结果：`BUILD SUCCESSFUL`。输出中有一条卡片 `@Entry` 的 ArkTS warning，和
  DevEco 自带卡片模板的写法一致，不影响编译。

  构建中间产物确认卡片走了独立的 widget 编译路径：
  `entry/build/default/cache/default/default@CompileArkTS/esmodule/debug_widget/entry/src/main/ets/widget/pages/ClashCard.ts`。
  `entry/build/default/intermediates/res/default/resources/base/profile/form_config.json`
  也已包含 `clash_control_card`。

完整 `u build` 当前被另一条并行工作挡住：native 链接缺
`ohos_core_set_age_secret_key`，来自 age 相关 native 代码，不是卡片改动。
等 age 侧合并后需要再跑一次完整构建。

## 5. 真机验证清单（交给主线）

1. 安装 HAP，长按桌面空白处或进入“服务卡片”列表，确认出现
   “Clash 控制 / Clash control”。
2. 添加 2x4 卡片，确认卡片显示当前 profile 和运行状态。
3. 点“启动”，确认 VPN 信任弹窗、`vpn-tun`、`127.0.0.1:9090` 出现。
4. 点“停止”，确认 `vpn-tun` 消失、状态刷新为停止。
5. 点“切换”，确认启动/停止交替生效。
6. 若第 3 步无效，检查 hilog 是否有
   `form startVpnExtensionAbility failed`，并切到 `router` 备选路径。

## 6. 剩余平台限制

- 卡片状态在创建、系统更新、用户操作和 `updateDuration` 周期刷新；不是秒级实时，
  精确刷新时机由系统调度。
- `FormExtensionAbility` 是短生命周期组件，创建后 10 秒内无操作会被系统清理。
  卡片只负责发出 VPN 启停请求和刷新一次状态，不承担长期监控；首次授权弹窗期间
  可能收不到最终结果，最终状态由下一次刷新补齐。
- 动态快捷方式只能显隐/钉住静态条目，不能动态创建新条目。
- `TileService` 的四个广播刷新语义没有等价物。
- 拨号密令不移植。
- 首次 VPN 授权弹窗仍需用户确认。
