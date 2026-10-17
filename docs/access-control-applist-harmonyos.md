# 访问控制应用包列表：HarmonyOS 侧实现与 SDK 限制

范围：`设置 → 网络 → 访问控制应用包列表`（Android `AccessControlActivity` /
`AccessControlDesign` / `AccessControlMenu` / `NetworkSettingsDesign` 的
`accessControlMode` + `accessControlPackages` 两行）。

结论先说：**HarmonyOS 没有给普通三方应用"枚举已安装应用"的公开 API**。所以这里
不是"没实现"，而是按平台能力重做成两条都能真正用的路径：平台返回什么就列什么 +
用户手动/剪贴板录入。所有降级点都在下面的表里，没有伪造系统能力。

---

## 1. SDK 证据（本机 API 26 d.ts + 权限表）

`/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony`：

| API | 文件 / 行 | 要求的权限 | 本机权限表里的等级 |
|---|---|---|---|
| `bundleManager.getInstalledBundleList(flags)` | `ets/api/@ohos.bundle.bundleManager.d.ts:2076` | `ohos.permission.ENTERPRISE_GET_INSTALLED_BUNDLE_LIST` | `availableLevel: system_basic` |
| `bundleManager.getBundleInfo(name, flags)` | 同上 `:1686` | `GET_BUNDLE_INFO_PRIVILEGED` **或** `GET_BUNDLE_INFO` | 前者 `system_basic`，后者 **`normal`** |
| `bundleManager.getBundleInfoForSelf(flags)` | 同上 `:1572` | 无 | — |
| `launcherBundleManager.getLauncherAbilityInfoSync(name, userId)` | `ets/api/@ohos.bundle.launcherBundleManager.d.ts` | `GET_BUNDLE_INFO_PRIVILEGED` | `system_basic` |
| `bundleManager.getApplicationLabel(name, appIndex)` | 同上 `:2091` | `GET_BUNDLE_INFO_PRIVILEGED` | `system_basic` |
| `pasteboard.SystemPasteboard.getDataSync()` | `ets/api/@ohos.pasteboard.d.ts:1308` | `ohos.permission.READ_PASTEBOARD`（since 12） | `system_basic` + `user_grant` |
| `pasteboard.SystemPasteboard.setDataSync(data)` | 同上 `:1435` | 无 | — |

等级来自 `toolchains/lib/PermissionDefinitions.json`（`definePermissions`），例如：

```
ohos.permission.ENTERPRISE_GET_INSTALLED_BUNDLE_LIST  availableLevel=system_basic  grantMode=system_grant
ohos.permission.GET_BUNDLE_INFO                       availableLevel=normal       grantMode=system_grant
ohos.permission.GET_INSTALLED_BUNDLE_LIST             availableLevel=system_basic  grantMode=user_grant
ohos.permission.READ_PASTEBOARD                       availableLevel=system_basic  grantMode=user_grant
```

normal APL 的应用拿不到 `system_basic` 权限，`user_grant` 也不行（申请会被拒）。
另外 `@ohos.bundle.bundleManager.d.ts` 里**根本没有** `getAllBundleInfo` /
`getBundleInfos`（`grep '^\s*function '` 的完整导出列表里只有上面那几个
`getBundleInfo*`），所以"换个旧 API 枚举"这条路不存在。

## 2. 端口怎么做的

### 2.1 枚举：照旧试，但把失败如实上报

`backend/InstalledApps.ets`

- `queryInstalledApps(selfBundleName)` 仍然调用 `getInstalledBundleList`，返回
  `InstalledAppQuery { apps, enumerated, errorCode, permissionDenied }`。
  `enumerated === false` 表示"平台没给列表"，`permissionDenied` 表示是 201 权限拒绝。
  旧接口名 `loadInstalledApps()` 保留为"只要数组"的薄封装，避免调用方被接口变化打断。
- 过滤规则与 Android `loadApps` 一致：跳过自身 bundle、非系统应用必须申请
  `ohos.permission.INTERNET`；`showSystem` 是显示层过滤，不在这里做。
- 权限一旦拿到（例如换成有特权的签名证书），这个函数不用改就会开始返回真列表。

### 2.2 列表：平台行 + 选中行，二者合并

`pages/AccessControlPage.ets` 的 `rows()` 把两半合起来：

1. `apps` —— 平台真返回的行（今天通常为空）；
2. `selected` —— 已选包名里**不在** `apps` 中的那些，作为行渲染。

所以即使枚举被拒，页面也不是空列表：用户选过的包一定看得见、点得掉。

第 2 类行是 `resolved === false`，渲染成**单行暗色包名**（不编造 label）；
第 1 类行沿用 Android `adapter_app.xml` 的图标 + 名称 + 包名 + 开关。

### 2.3 录入：工具栏 "+" 与剪贴板

| Android | 端口 |
|---|---|
| `PackageManager` 直接给出全部应用 | 工具栏 `+`：手输一个或多个包名（`TextArea`，每行一个 / 逗号分隔） |
| `Request.Import`：读剪贴板，与已安装应用取交集 | 先试 `getDataSync()`；被拒（201）则弹出同一个输入框，让用户**自己粘贴**——往 `TextArea` 里粘贴是用户发起的读剪贴板，不需要权限 |
| `Request.Export`：`selected.joinToString("\n")` 写剪贴板 | 完全等价，`setDataSync` 不需要权限；成功 toast `copied` |
| 菜单：Select All / None / Invert | 已实现，作用对象是"当前列表显示的行"（Android 作用在整表，因为它的搜索是独立弹窗；端口把搜索放进工具栏，所以"全选"= 全选可见行） |
| 菜单：Filter > System Apps | 已实现（`AccessControlUiStore.showSystem`） |
| 菜单：Sort > Name / Package Name / Install Time / Update Time + Reverse | 已实现，比较器复刻 `compareByDescending { it.packageName in selected }` 再按 key 排；`reverse` 只翻转 key 部分 |

`AccessControlUiStore`（`backend/AccessControlPrefs.ets`）用**一个 `@Trace` 字符串**
存 `{showSystem, sort, reverse}`，形状同 `ProfileStore`（PersistenceV2 不接受更富的
对象）。模式值 `accessControlMode` 单独一个 store 类，`@Trace` 直接是枚举，同
`UiStore.darkMode`。

### 2.4 网络设置页：`access_control_mode` 变成真控件

Android 把这一行放进 `vpnDependencies`（`enableVpn` 关着就禁用）。端口里主开关
`route_system_traffic` 自己都还没法用，照抄这个门会得到一行永远禁用的占位符，所以
改成可用的、持久化的 `selectableList`：三项 + 勾选当前值，写进
`AccessControlModeStore`。`tun_stack_mode` 保持禁用——它描述的是**内核**怎么建 TUN，
而端口还没有内核。

`access_control_packages` 行本来就不在 `vpnDependencies` 里，保持可点、跳转不变。

## 3. 偏差清单（相对 Android）

| # | 偏差 | 原因 |
|---|---|---|
| 1 | 应用列表默认要靠手输/导入，而不是自动枚举 | `ENTERPRISE_GET_INSTALLED_BUNDLE_LIST` 是 `system_basic` |
| 2 | 手输的包名若本机解析不出来，显示为暗色单行包名（无图标/无 label） | 诚实表达"只知道这个名字" |
| 3 | 导入不再与已安装应用取交集 | 无法枚举，交集会把所有条目过滤掉 |
| 4 | 导入默认走"用户自己粘贴"对话框 | `READ_PASTEBOARD` 是 `system_basic` + `user_grant` |
| 5 | 全选/反选作用于可见行 | 搜索框内联在工具栏，没有独立搜索弹窗 |
| 6 | 溢出菜单是一层平铺 11 项（勾选表示状态），不是 Android 的三层子菜单 | `bindMenu` 的 `MenuElement[]` 不支持嵌套 |
| 7 | `access_control_mode` 不再随主开关禁用 | 主开关本身不可用，照抄会得到永久禁用行 |
| 8 | 改完选择后的服务重启仍然报 `not_ported` | 没有 VpnService/内核可重启 |

## 4. 待办 / 未验证

1. **`entry/src/main/module.json5` 需要加一条权限**（在本次改动的写入范围之外，
   需要主 agent 决定）：

   ```json5
   { "name": "ohos.permission.GET_BUNDLE_INFO" }
   ```

   这是 `normal` / `system_grant`，安装即授予、无弹窗。加上之后，手输/导入的包名会
   通过 `getBundleInfo` 解析出真实 label / 图标 / 系统应用标记；不加也能用，只是全部
   显示为暗色包名行。

2. **真机未验证**：本次只做了静态检查（`arkts-diff` precheck：64 文件，`errors: 0`；
   `ok:false` 是已知的环境缺陷 #4）。需要在设备上确认的：`getInstalledBundleList`
   实际返回 201（提示条出现）、`+` 输入框落盘、导入对话框、导出 toast、菜单勾选。

3. **没做的 Android 菜单项**：`access_control_sort` / `access_control_reverse` 已做，
   但 Android 的"整表排序（含未显示的行）"语义与端口一致；`access_control_reverse`
   对未解析行（`installTime = 0`）没有可观察差别。
