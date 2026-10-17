# Age 密钥生成/校验接到 OHOS mihomo core

日期：2026-10-17
范围：Meta 特性设置页（`MetaFeatureSettingsPage`）里那两行 "Age Key"
相关文件：`work/clashmeta/core/src/main/golang/ohos/main.go`、
`entry/src/main/cpp/napi_init.cpp`、
`entry/src/main/cpp/types/libclashcore/index.d.ts`、
`entry/src/main/ets/backend/AgeKeyHelper.ets`、
`entry/src/main/ets/pages/MetaFeatureSettingsPage.ets`

---

## 1. 这一轮之前的状态

两行是"点击弹 `age_key_not_supported` toast"，理由是"端口没有 age 实现，
而且 hybrid 的 MLKEM768-X25519 是内核侧原语"。

前一半理由（没有 age 实现）现在不成立了：`libclash.so` 已经是 OHOS arm64 的
mihomo，`component/age` 就在里面。所以这两行不再是"等一个 UI 移植"，而是
"把已有的内核函数接出来"。

## 2. Android 侧到底调了什么

`MetaFeatureSettingsDesign.requestAgeKeyHelper(hybrid)` 是一个
`MaterialAlertDialogBuilder` + `dialog_age_key_helper.xml` 的对话框，
里面 5 个动作全部走 JNI：

| Android 调用 | 对话框里的位置 |
|---|---|
| `Clash.genX25519KeyPair()` | X25519 行的 "Generate" |
| `Clash.genHybridKeyPair()` | MLKEM768-X25519 行的 "Generate" |
| `Clash.toPublicKeys(secret)` | "From Secret" |
| `Clash.veritySecretKeys(secret)` | 私钥输入框的即时校验（每次输入） |
| `Clash.verityPublicKeys(public)` | 公钥输入框的即时校验（每次输入） |

这 5 个 JNI 函数在 `core/src/main/golang/native/config.go` 里分别转发到
`cfa/native/config` 的 `GenX25519KeyPair` / `GenHybridKeyPair` /
`ToPublicKeys` / `VeritySecretKeys` / `VerityPublicKeys`，后者再转发到
`mihomo/component/age`。所以端口要接的是**同一条链的下半段**，
不是重写密码学。

## 3. 这一轮做了什么

### 3.1 Go 侧：`cfa/ohos` 新增 5 个导出

文件：`work/clashmeta/core/src/main/golang/ohos/main.go`

```go
//export ohos_age_gen_x25519
//export ohos_age_gen_hybrid
//export ohos_age_verify_secret_keys
//export ohos_age_to_public_keys
//export ohos_age_verify_public_keys
```

内部就是 `cfa/native/config` 的那 5 个函数，没有额外逻辑。

**返回契约**：返回数据的三个（`gen_x25519` / `gen_hybrid` /
`to_public_keys`）返回一个 JSON 信封，而不是"空字符串表示失败"：

```json
{"ok":true,"secretKey":"AGE-SECRET-KEY-1...","publicKey":"age1..."}
{"ok":true,"publicKeys":["age1..."]}
{"ok":false,"error":"..."}
```

理由是 key pair 是**数据**不是成功标志，失败时应该带上原因，
否则 UI 只能把"失败"和"空结果"混成同一件事（访问控制页上一轮刚踩过这个坑）。
两个校验函数返回普通 `C int`（1 = 合法，0 = 不合法），布尔值不需要信封。

字符串一律 `C.CString`（即 `malloc`），调用方负责 `free` —— 和这个文件里
原有的 `ohos_core_prepare` / `ohos_core_stop` 同一套所有权规则。

### 3.2 同一文件：`ohos_core_attach` 扩展成 5 参数

顺带做的一项同文件契约变更（为网络设置页把 TUN stack / DNS hijack 接进 core）：

```go
// 旧
func ohos_core_attach(fd C.int) *C.char
// 新
func ohos_core_attach(fd C.int, stack, gateway, portal, dns *C.char) *C.char
```

原来 4 个值是在 Go 里写死的（`"system"` / `"172.19.0.1/30"` /
`"172.19.0.2"` / `"0.0.0.0"`），所以 `NetworkSettingsPage` 的
TUN stack / DNS 劫持行没有地方可落。现在这 4 个值从调用方传进来，
和 Android 的 `TunService` 从 `NetworkSettingsStore` 读出来再调
`startTun(fd, stack, gateway, portal, dns)` 是同一条路径。

`cfa/native/tun.Start(fd, stack, gateway, portal, dns)` 的签名本来就是这样，
所以 Go 侧只是把写死的常量换成参数，语义没有变化。

默认值（调用方应当传的）仍然是：

| 参数 | 默认值 | 含义 |
|---|---|---|
| `stack` | `system` | sing-tun stack：`system` / `gvisor` / `mixed` |
| `gateway` | `172.19.0.1/30` | 逗号分隔的接口前缀 |
| `portal` | `172.19.0.2` | sing-tun 重写成的 inet4 源地址 |
| `dns` | `0.0.0.0` | 逗号分隔的 DNS 劫持地址；`0.0.0.0` = 全部 |

**注意**：这一步只改了 Go + NAPI + `.d.ts`，**没有改 ArkTS 调用方**
（`ClashVpnExtension.ets:206` 现在还是 `coreAttach(tunFd)`）。见 §5 阻塞项。

### 3.3 NAPI 层

文件：`entry/src/main/cpp/napi_init.cpp`

新增 5 个函数 + 改 `coreAttach`，全部是"转调 Go 导出 + 管内存"：

| NAPI | 签名 | 返回 |
|---|---|---|
| `ageGenX25519` | `() => string` | `ageKeyPairResult` 信封 |
| `ageGenHybrid` | `() => string` | 同上 |
| `ageToPublicKeys` | `(keys: string) => string` | `agePublicKeysResult` 信封 |
| `ageVerifySecretKeys` | `(keys: string) => boolean` | `napi_get_boolean` |
| `ageVerifyPublicKeys` | `(keys: string) => boolean` | `napi_get_boolean` |
| `coreAttach` | `(fd, stack, gateway, portal, dns) => string` | `''` = 成功，否则错误串 |

新加了一个 `TakeCString(env, char*)`：把 Go 返回的 `char*` 拷成 JS 字符串后
`free`，`nullptr` 映射成空串（而不是 `undefined`），让 ArkTS 侧只有一种类型。

`.d.ts` 同步更新，并写清楚了 `coreAttach` 那 4 个字符串参数各自的含义和默认值。

### 3.4 ArkTS 侧

**新增** `entry/src/main/ets/backend/AgeKeyHelper.ets`：

- `AgeKeyKind`（`X25519` / `Hybrid`）、`AgeKeyPair`（`ok` / `secretKey` /
  `publicKey` / `error`）；
- `generateKeyPair(kind)`、`deriveFirstPublicKey(secretKey)`、
  `verifySecretKey`、`verifyPublicKey`；
- `copyToClipboard(text)`（对话框两个 "Copy" 按钮用）。

信封在这里拆掉，页面拿到的是 `AgeKeyPair` 对象，不是裸字符串。
NAPI 抛异常（比如参数个数不对）也会被 `try/catch` 变成 `ok:false` + 原因，
而不是把异常抛进 UI。

**改** `entry/src/main/ets/pages/MetaFeatureSettingsPage.ets`：

- 两行的 `action()` 从 `showToast(age_key_not_supported)` 改成
  `openAgeKeyHelper(kind)`；
- 新增 `@Builder ageKeyDialog()`，按 `dialog_age_key_helper.xml` 复刻：
  私钥输入框 → [Generate][Copy] → 公钥输入框 → [From Secret][Copy]；
- 校验规则逐字对齐 Android：`secretKey.isBlank() || veritySecretKeys(...)`，
  即**空字段不算错误**（这条留在页面里，不进 helper，因为它绑着要显示的文案）；
- `onBackPress` 在对话框打开时关闭对话框并 `return true`，对应 Android 的
  `AlertDialog` 被返回键 dismiss；
- `bindContentCover` 承载对话框（和 `view/TextInputDialog.ets` 同一套写法）。

## 4. 有意偏离 Android 的地方

| 项 | Android | 这个端口 | 原因 |
|---|---|---|---|
| 对话框关闭方式 | 无按钮，点外部/返回键 dismiss | 额外加一个 `Cancel` 按钮 | `bindContentCover` 的 cover 不响应外部点击；端口里其它对话框都有 Cancel，一个没有可见出口的模态更糟 |
| Generate 失败 | `keyPair` 为 null → NPE 崩溃 | toast 出内核给的原因，并保留已输入内容 | 顺手修掉的 Android 缺陷 |
| Copy 失败 | 无论如何都 toast "Copied" | 写入被拒时 toast `not_ported`，成功才 toast `copied` | 不谎报成功；和 `AccessControlPage.requestExport` 一致 |
| 公钥/私钥字段 | `TextInputLayout` + `error` 文案 | `TextInput` + 红字 `Text` | ArkUI 没有 `TextInputLayout` |

**没有简化掉的**：5 个操作全部走真内核；hybrid 也是真的 MLKEM768-X25519
（不是降级成 X25519）。

## 5. 契约衔接状态

两处跨文件的衔接都不在本轮的写入范围里，写在这里是为了可追溯。

1. **`entry/src/main/cpp/prebuilt/arm64-v8a/libclash.so` 已重建**（03:42，
   62,598,512 字节）。本轮改 Go 之前它是旧的，NAPI 层会链接不到
   `ohos_age_*`；现在 `llvm-nm -D --defined-only` 能列出全部 8 个
   `ohos_*` 符号，`ohos_core_attach` 也已经是 5 参数版本。

   重建命令（`$W` = `work`，`$SDK` = DevEco 的 `openharmony/native`）：

   ```bash
   cd $W/clashmeta/core/src/main/golang
   GOOS=android GOARCH=arm64 CGO_ENABLED=1 \
   CC=$SDK/llvm/bin/aarch64-unknown-linux-ohos-clang \
   CGO_CFLAGS="-I$W/ohos-clash-build/include" \
   CGO_LDFLAGS="-L$W/ohos-clash-build/lib" \
   $W/toolchain/go1.27.2/bin/go build -tags 'foss with_gvisor cmfa' \
     -buildmode=c-shared -trimpath \
     -ldflags '-s -w -extldflags "-Wl,-soname,libclash.so"' \
     -o <prebuilt>/libclash.so ./ohos
   ```

   本轮按这条命令跑过一次做验证，产物留在
   `work/ohos-clash-build/verify-c/libclash.so`（SONAME `libclash.so`，
   `NEEDED` 只有 `liblog.so` / `libc.so`）。

2. **`ClashVpnExtension.ets` 已经改成 5 参数**（03:45，由网络设置那一路的
   agent 完成）：

   ```ts
   const error: string = coreAttach(tunFd, stack, gateway, portal, dns);
   ```

   `stack` / `gateway` / `portal` / `dns` 来自新的
   `backend/VpnSettingsStore.ets`，即网络设置页的 TUN stack / DNS 劫持行。
   本轮**没有动**这个文件，只提供 `.d.ts` 契约。

## 6. 验证状态

| 项 | 结果 | 证据 |
|---|---|---|
| Go 编译 | **通过** | `go build -buildmode=c-shared` 成功，产出 62.6 MB `libclash.so` |
| cgo 导出签名 | **通过** | 生成的 `libclash.h` 里 `ohos_core_attach(int, char*, char*, char*, char*)` + 5 个 `ohos_age_*` |
| 动态符号 | **通过** | `llvm-nm -D --defined-only` 列出 8 个 `ohos_*` 符号 |
| C++ 语法 | **通过** | `aarch64-unknown-linux-ohos-clang++ -fsyntax-only -Wall -Wextra`，0 诊断 |
| NAPI ↔ Go 链接 | **通过** | 用 `-Wl,--no-undefined` 把 `napi_init.cpp` 链到新 `libclash.so`，成功产出 `libclashcore.so` |
| ArkTS 静态检查 | **通过（本文件）** | `hmos-precheck` arkts standalone，65 文件；`AgeKeyHelper.ets` 只有 `createPlainTextData` deprecated 一条 warning，`MetaFeatureSettingsPage.ets` 只有仓库通病 warning |
| ArkTS 全项目 | **通过** | 65 文件，`errorCount: 0` / `warnCount: 213`（§5.2 的调用方接上之后） |
| 真机 | **未验证** | 按分工没跑 hdc / 没装机 |

顶层 `ok:false` 仍然是已知缺陷 #4（`backend-unavailable`：permission catalog
不可用），与本次改动无关。

### 上机时要确认的

1. 打开 Meta 特性设置页不崩 —— 这一页现在会 `dlopen` `libclashcore.so`
   （进而加载 60 MB 的 `libclash.so` 和 Go runtime）到**主 UI 进程**。
   之前只有 `VpnExtensionAbility` 进程加载过它。Go runtime 在普通 ArkTS
   进程里初始化没有已知障碍，但这是本轮唯一没法静态证明的假设。
2. X25519 行点 "Generate" → 两个字段被填上 `AGE-SECRET-KEY-1...` / `age1...`。
3. Hybrid 行点 "Generate" → 同样是 `AGE-SECRET-KEY-1...` / `age1...`，
   但公钥长度明显更长（MLKEM768-X25519）。
4. 在私钥框里乱打几个字 → 下面出现 `age_secret_key_error` 红字；
   清空 → 红字消失。
5. "From Secret" 在私钥合法时把公钥框填对；私钥非法时把公钥框清空。
6. 两个 "Copy" 都能复制，且 toast 是 `copied`。

## 7. 还没做的（诚实清单）

1. **生成的密钥没有消费者。** Android 把私钥交给 `ProfileProcessor` 去解密
   age 加密的订阅；这个端口 `backend/ProfileFetch.ets` 只下载，没有 age
   解密步骤，所以密钥目前只是"能生成、能校验、能复制"。
   `age.SetGlobalSecretKeys` 也还没有接到 `ohos_core_prepare` 上。
2. **没有把密钥写进 override 记录。** Android 的对话框也不写 —— 它只是
   把值给用户复制走，所以这一点是一致的，不是缺口。
3. `age_key_not_supported` 这条字符串现在没有引用了（它由上一轮的
   点击审计 agent 加进 `base/element/string.json`）。留着无害，
   要清理的话是一处删除。

## 8. 后续收口：age key 已接到 profile 解密

2026-10-17 的主线收口已经补上第 7 节第 1 条：

- `Index.ets` / `ExternalControl.ets` / `EntryFormAbility.ets` 启动 VPN 时把
  active profile 的 `ageSecretKey` 放进 `Want`；
- `ClashVpnExtension` 在 `corePrepare()` 之前调用 `coreSetAgeSecretKey()`；
- Go 侧通过 `config.SetGlobalSecretKeys()` 把 key 装进 core，随后
  `config.UnmarshalAndPatch()` 会按 Android 的同一路径解密 age armor；
- 空 key 会清空全局身份列表，未加密订阅保持原行为。

所以现在的 age 链路是完整的：生成 / 校验 / 复制 / 保存到 profile /
传给 core / 解密订阅。`backend/ProfileFetch.ets` 仍然只负责下载原始字节，
解密发生在 core 加载 `config.yaml` 时，这与 Android 的实现顺序一致。
