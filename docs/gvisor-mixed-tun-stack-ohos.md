# OHOS VPN fd：gVisor / mixed TUN stack 可行性分析

日期：2026-10-17
范围：只做静态分析和本地最小实验；没有执行 `hdc`、没有安装 HAP、没有改设备。
生产代码未改；age 和服务卡片相关文件未碰。

## 结论

1. 当前 `gvisor` 失败点已经精确定位，不是路由、权限申请或 `VpnConfig` 参数问题，
   而是 gVisor 的 fdbased endpoint 在创建 dispatcher 前无条件调用
   `unix.Fstat`：

   ```text
   fdbased.New
     -> IsSocketFD
       -> unix.Fstat
         -> EPERM
   ```

2. 这不是必须先等 OHOS 放开的硬限制。可以用一个很小的 fail-closed 补丁修复：
   只在 `Fstat` 返回 `EPERM` 时回退到 `getsockname`：

   - `getsockname` 成功：确定是 socket；
   - `getsockname` 返回 `ENOTSOCK`：确定不是 socket；
   - 其他错误：仍然报错，不猜测。

   这个补丁不提升权限、不绕过沙箱，也不把未知 fd 当成 TUN；它只替代
   “fd 是不是 socket” 这一个分类判断。补丁已放在：

   `outputs/gvisor-ohos-fstat-fallback.patch`

3. 补丁已在本地 gVisor 源码副本上实际应用，并通过：

   - `GOOS=android GOARCH=arm64` 的 `fdbased` 编译检查；
   - `GOOS=android GOARCH=arm64 -tags with_gvisor` 的 `sing-tun` 编译检查。

   但 **没有做 OHOS 真机运行验证**，所以不能把 `gvisor` 标成已可用。

4. 目前最稳妥的替代顺序：

   - `system` / `mips`：已经真机验证，保持默认；
   - `mixed`：代码路径不经过 fdbased / `Fstat`，理论上不受此失败影响，
     但当前仍是“未上机验证”；
   - `gvisor`：应用补丁后重建 `libclash.so`，再单独做真机 A/B 验证。

## 精确失败链

### 1. ArkTS 把 stack 名字原样传给 core

`entry/src/main/ets/vpnextension/ClashVpnExtension.ets`：

```text
createTunnel()
  -> coreAttach(tunFd, stack, gateway, portal, dns)
```

相关行：

- `createTunnel`：`ClashVpnExtension.ets:433`
- `coreAttach(...)`：`ClashVpnExtension.ets:488-497`
- 合法 stack 列表：`model/NetworkSettingsModels.ets:55`
  （`system` / `gvisor` / `mixed` / `mips`）

本地 OHOS SDK 的 `VpnConfig` 没有 stack 字段。它只定义
`addresses` / `routes` / `dnsAddresses` / `mtu` / `isIPv4Accepted` /
`isIPv6Accepted` / `isInternal` / `isBlocking` /
`trustedApplications` / `blockedApplications`，见：

`/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/api/@ohos.net.vpnExtension.d.ts:223-310`

所以 stack 选择完全在 mihomo / sing-tun 内部，平台 API 不会替应用选
“内核 TUN 模式”。

### 2. NAPI 到 Go 的 attach

`entry/src/main/cpp/napi_init.cpp` 的 `coreAttach` 把 fd 和四个字符串传给
Go 导出函数 `ohos_core_attach`。

Go 侧：

- `work/clashmeta/core/src/main/golang/ohos/main.go:128`
- `ohos_core_attach` 调用 `tun.Start(fd, stack, gateway, portal, dns)`

### 3. Go 侧 stack 映射

`work/clashmeta/core/src/main/golang/native/tun/tun.go:17-70`：

```go
tunStack, ok := C.StackTypeMapping[strings.ToLower(stack)]
if !ok {
    tunStack = C.TunSystem
}
...
listener, err := sing_tun.New(options, tunnel.Tunnel)
```

`gvisor` 会被映射到 sing-tun 的 `gvisor` stack。

### 4. sing-tun 选择 gVisor

`github.com/metacubex/sing-tun@v0.4.27/stack.go:41-59`：

```go
case "gvisor":
    return NewGVisor(options)
```

`stack_gvisor.go:85-88`：

```go
func (t *GVisor) Start() error {
    linkEndpoint, nicOptions, err := t.tun.NewEndpoint()
    ...
}
```

### 5. gVisor 创建 fdbased endpoint

`tun_linux_gvisor.go:88-114`：

```go
func (t *NativeTun) NewEndpoint() (stack.LinkEndpoint, stack.NICOptions, error) {
    ...
    ep, err := fdbased.New(&fdbased.Options{
        FDs: []int{t.tunFd},
        MTU: t.options.MTU,
        ...
    })
}
```

### 6. fdbased 在真正挂 NIC 之前做 Fstat

`github.com/metacubex/gvisor@v0.0.0-20260922041103-e2cbcd6e7400/pkg/tcpip/link/fdbased/endpoint.go:308-344`：

```go
for i, fd := range opts.FDs {
    if err := unix.SetNonblock(fd, true); err != nil { ... }

    isSocket, err := IsSocketFD(fd)
    if err != nil {
        return nil, err
    }
    ...
}
```

`endpoint.go:473-480`：

```go
func IsSocketFD(fd int) (bool, error) {
    var stat unix.Stat_t
    if err := unix.Fstat(fd, &stat); err != nil {
        return false, fmt.Errorf("unix.Fstat(%v,...) failed: %v", fd, err)
    }
    return (stat.Mode & unix.S_IFSOCK) == unix.S_IFSOCK, nil
}
```

OHOS 上实际表现：

```text
mihomo core failed: unix.Fstat(35,...) failed: permission denied
```

来源：`outputs/ClashMetaHarmony-PORT-STATUS.md:1551-1557`。

### 7. `PreConfigured` 不能绕过

gVisor 的 `Options` 有 `PreConfigured` 和 `IsPacketSocket`，但
`IsSocketFD` 在检查 `PreConfigured` 之前就执行了：

```go
isSocket, err := IsSocketFD(fd)   // 无条件
...
if opts.PreConfigured { ... }     // 之后才检查
```

所以只设置 `PreConfigured: true` 不能避免 `Fstat`。

## 为什么 system / mips / mixed 不受影响

### system

`stack_system.go:112-119` 的 `Start()` 只启动 `tunLoop()`；
`tunLoop` 走 `Tun.Read` / `Tun.Write`，不创建 fdbased endpoint。

### mips

`stack_mipstack.go:36-70` 构造 `Mipstack`，同样直接使用
`Tun` 的 `Read` / `Write`，没有 `Fstat`。

### mixed

`stack_mixed.go:23-51`：

```go
func NewMixed(options StackOptions) (Stack, error) {
    system, err := NewSystem(options)
    ...
}

func (m *Mixed) Start() error {
    err := m.System.start()
    ...
    endpoint := channel.New(1024, uint32(m.mtu), "")
    ipStack, err := NewGVisorStack(endpoint)
    ...
}
```

`mixed` 只把 UDP 注入 gVisor 的 `channel.Endpoint`，TCP / ICMP 走
system 路径；它不经过 `fdbased.New`，因此不会碰到这个 `Fstat`。

## 可行补丁

补丁文件：

`outputs/gvisor-ohos-fstat-fallback.patch`

核心改动：

```go
func IsSocketFD(fd int) (bool, error) {
    var stat unix.Stat_t
    if err := unix.Fstat(fd, &stat); err == nil {
        return (stat.Mode & unix.S_IFSOCK) == unix.S_IFSOCK, nil
    } else if !errors.Is(err, unix.EPERM) {
        return false, fmt.Errorf("unix.Fstat(%v,...) failed: %v", fd, err)
    }

    _, err := unix.Getsockname(fd)
    switch {
    case err == nil:
        return true, nil
    case errors.Is(err, unix.ENOTSOCK):
        return false, nil
    default:
        return false, fmt.Errorf(
            "unix.Fstat(%v,...) failed: EPERM; unix.Getsockname fallback failed: %v",
            fd, err,
        )
    }
}
```

安全性说明：

- 只在 `Fstat` 明确返回 `EPERM` 时进入 fallback；
- `getsockname` 成功只可能说明它是 socket；
- `getsockname` 返回 `ENOTSOCK` 只说明它不是 socket；
- 任何其他错误继续失败，不把未知 fd 当成 TUN；
- 不调用任何提权 API，不改变 VPN 路由或应用白名单。

对 gVisor 路径的后续影响：

- `isSocket=false` 后，fdbased 使用 `readv` dispatcher；
- 不会走 `recvmmsg` / packet mmap，只影响性能优化，不影响正确性；
- 写路径仍走 `writev`。

## 本地实验与编译验证

### 1. fallback 分类逻辑

实验代码：

`outputs/ClashMetaHarmony/work/gvisor-fstat-fallback/main.go`

运行命令：

```bash
cd outputs/ClashMetaHarmony/work/gvisor-fstat-fallback
GOSUMDB=off GOPROXY=off \
  /Users/hikaritus/Documents/Codex/2026-10-16/github-ios-android-android-ios-android-6/work/toolchain/go1.27.2/bin/go run .
```

结果：

```text
pipe: isSocket=false err=<nil>
pipe: fallback isSocket=false err=<nil>
chardev: isSocket=false err=<nil>
chardev: fallback isSocket=false err=<nil>
socketpair: isSocket=true err=<nil>
socketpair: fallback isSocket=true err=<nil>
```

这说明在本地 Linux/macOS 语义下，`Fstat` 路径与
`getsockname` fallback 的分类一致：非 socket 仍为 false，socket 仍为 true。

### 2. 补丁 dry-run

```bash
patch -p1 --dry-run -d outputs/ClashMetaHarmony/work/gvisor-fstat-patchcheck2 \
  < outputs/gvisor-ohos-fstat-fallback.patch
```

结果：

```text
patching file 'pkg/tcpip/link/fdbased/endpoint.go'
```

### 3. 补丁后的 gVisor 编译

本地副本：

`outputs/ClashMetaHarmony/work/gvisor-patched`

命令：

```bash
cd outputs/ClashMetaHarmony/work/gvisor-patched
GOSUMDB=off GOPROXY=off GOOS=android GOARCH=arm64 CGO_ENABLED=0 \
  /Users/hikaritus/Documents/Codex/2026-10-16/github-ios-android-android-ios-android-6/work/toolchain/go1.27.2/bin/go test -c \
  -o fdbased-android.test ./pkg/tcpip/link/fdbased
```

结果：

```text
?   github.com/metacubex/gvisor/pkg/tcpip/link/fdbased [no test files]
```

退出码为 0。

### 4. sing-tun 的 gVisor 路径编译

命令：

```bash
cd work/clashmeta/core/src/main/golang
GOSUMDB=off GOPROXY=off GOOS=android GOARCH=arm64 CGO_ENABLED=0 \
  /Users/hikaritus/Documents/Codex/2026-10-16/github-ios-android-android-ios-android-6/work/toolchain/go1.27.2/bin/go build \
  -tags with_gvisor github.com/metacubex/sing-tun
```

结果：退出码 0。

## 集成方式

生产构建当前直接使用 Go module cache 里的 gVisor。module cache 不是源码仓库，
不能把补丁写在那里当交付物。可行集成方式有三种：

1. **本地 fork + `replace`（推荐）**

   把补丁应用到项目维护的 gVisor fork，然后在
   `work/clashmeta/core/src/main/golang/go.mod` 增加：

   ```text
   replace github.com/metacubex/gvisor => ./third_party/gvisor
   ```

   这样 `go build` 会稳定使用补丁后的版本。

2. **构建时 `-overlay`**

   用 Go 的 `-overlay` 把 module cache 中的
   `pkg/tcpip/link/fdbased/endpoint.go` 替换为补丁后的副本。
   适合验证，不适合长期维护，因为 overlay JSON 里的绝对路径依赖构建机。

3. **上游补丁**

   把 `IsSocketFD` 的 `EPERM` fallback 提交给 `metacubex/gvisor`。
   这是最干净的长期方案，但需要等上游发版，不能作为本轮设备验证的前置条件。

## 真机验证矩阵（交给主线执行）

不要在没有设备验证的情况下把 `gvisor` 标成可用。建议按下面顺序：

| 步骤 | 配置 | 预期 |
|---|---|---|
| A | `stack=system` | 已验证基线 |
| B | `stack=mips` | 已验证基线 |
| C | `stack=mixed` | 不触发 `Fstat`；验证 TCP/UDP/DNS/节点列表 |
| D | 应用补丁后 `stack=gvisor` | 验证 `fdbased` / readv / writev / eventfd / poll 是否全通 |

建议日志过滤：

```bash
hdc shell "hilog -x -T ClashVpnExt"
hdc shell "hilog -z 5000" | grep -iE "ClashVpnExt|mihomo core|vpn-tun|Fstat|EPERM|eventfd|poll"
```

`gvisor` 应用补丁后如果仍然失败，优先看新的 errno：

- `eventfd`：`stopfd.New()` 失败；
- `poll` / `readv`：dispatcher 启动或读包失败；
- `writev`：core 回写 TUN 失败；
- `getsockname`：OHOS 对 VPN fd 的 `getsockname` 返回了非 `ENOTSOCK`
  的错误，此时补丁会 fail-closed，不会误判。

## 改动文件

本轮只新增分析/实验文件，没有改生产源码：

- `outputs/gvisor-mixed-tun-stack-ohos.md`（本文件）
- `outputs/gvisor-ohos-fstat-fallback.patch`
- `outputs/ClashMetaHarmony/work/gvisor-fstat-fallback/main.go`
- `outputs/ClashMetaHarmony/work/gvisor-fstat-fallback/go.mod`
- `outputs/ClashMetaHarmony/work/gvisor-fstat-fallback/go.sum`
- `outputs/ClashMetaHarmony/work/gvisor-fstat-patchcheck/...`
- `outputs/ClashMetaHarmony/work/gvisor-fstat-patchcheck2/...`
- `outputs/ClashMetaHarmony/work/gvisor-patched/...`

未修改：

- `work/clashmeta/core/src/main/golang/ohos/main.go`
- `work/clashmeta/core/src/main/golang/native/tun/tun.go`
- `entry/src/main/ets/vpnextension/ClashVpnExtension.ets`
- age 相关文件
- 服务卡片相关文件

## 剩余风险

1. **补丁没有 OHOS 真机运行证据**。它只证明了本地分类语义和
   Android/arm64 编译通过。
2. **`Fstat` 不是唯一可能的 OHOS syscall 限制**。gVisor 还需要
   `SetNonblock`、`eventfd`、`poll`、`readv`、`writev`。
   现有探针只证明 `fcntl` / `read` 可用。
3. **`mixed` 是当前最值得先试的替代路径**，因为它完全绕开
   fdbased，而且 system 已经验证可用；但 mixed 的 TCP/UDP 分流行为
   仍需真机确认。
4. **性能差异**：fallback 后 gVisor 走 readv，不走 recvmmsg / packet mmap；
   对本项目的数据面正确性无影响，但高吞吐场景需要重新压测。
5. **上游漂移**：补丁基于当前
   `github.com/metacubex/gvisor v0.0.0-20260922041103-e2cbcd6e7400`；
   升级 gVisor 后需要重新 rebase。
