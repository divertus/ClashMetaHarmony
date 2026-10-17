# Logcat streaming on HarmonyOS: feasibility and recommendation

Date: 2026-10-17

Target: `outputs/ClashMetaHarmony`, ArkTS/ArkUI V2, API 26

## Decision

`LogcatActivity` streaming mode cannot be ported to HarmonyOS as it exists on
Android. Android's streaming mode is not Android `logcat`; it is a foreground
service subscribed to the in-process mihomo core's own log stream. HarmonyOS
does not expose a public third-party API for reading another process's HiLog
stream, and the SDK's log-related read permissions are system, system-core, or
enterprise/MDM grants.

The port should therefore keep the streaming entry point honest as
`not_ported`. If live logs are wanted later, the only useful path for this
port's current architecture is a separate mihomo external-controller
`GET /logs` WebSocket while the page is open. That is not the same feature as
Android's `LogcatService`, and it should not be described as a port of it.

## 1. What Android streaming mode is built on

The Android flow is:

1. `LogcatActivity.mainStreaming()` creates `LogcatDesign(this, true)`.
   `LogcatActivity.kt:94-130`.
2. It calls `startForegroundServiceCompat(LogcatService::class.intent)`.
   `LogcatActivity.kt:99`.
3. It binds to `LogcatService` and, while the activity is started, polls
   `snapshot(initial)` every 500 ms. `LogcatActivity.kt:101-126`.
4. `LogcatService` is a foreground Android service with a notification channel
   and an ongoing notification. The notification uses channel
   `clash_logcat_channel` and notification id `nf_logcat_status`.
   `LogcatService.kt:33-152`; `AndroidManifest.xml` declares the service with
   `android:foregroundServiceType="specialUse"`.
5. `LogcatService` binds `RemoteService`, obtains its `IClashManager`, and calls
   `setLogObserver(observer)`. `LogcatService.kt:85-125`.
6. `ClashManager.setLogObserver()` calls `Clash.subscribeLogcat()` and forwards
   each `LogMessage` to the observer. `ClashManager.kt:84-110`.
7. `Clash.subscribeLogcat()` calls `Bridge.nativeSubscribeLogcat()`, the JNI
   entry into the in-process mihomo core. `Clash.kt:221-231`;
   `LogcatInterface.kt:1-9`.
8. `LogcatService` also writes the same messages to
   `cacheDir/logs/clash-<epoch>.log` through `LogcatWriter`, using
   `"%d:%s:%s"` (`<epochMillis>:<Level>:<message>`).
   `LogcatWriter.kt:10-28`.
9. The UI's cache is a 128-entry `LogcatCache`; the activity polls snapshots
   and the streaming design uses a reversed list. `LogcatCache.kt:8-55`;
   `LogcatDesign.kt:18-69`.

The important consequence is that this feature is a subscription to the
embedded mihomo core's logs plus a foreground-service lifetime mechanism. It is
not a request to read the whole system log.

## 2. HarmonyOS APIs checked

The SDK used for this check is the installed DevEco Studio SDK:

`/Applications/DevEco-Studio.app/Contents/sdk/default`

Its ETS package reports API version `26` / platform version `26.0.0`
(`openharmony/ets/oh-uni-package.json`), matching the port's
`build-profile.json5`.

### 2.1 `@kit.PerformanceAnalysisKit` and `hilog`

The kit re-exports `hilog` from `@ohos.hilog.d.ts`.

The complete public `hilog` function set in that declaration is:

- `debug(domain, tag, format, ...args)`
- `info(domain, tag, format, ...args)`
- `warn(domain, tag, format, ...args)`
- `error(domain, tag, format, ...args)`
- `fatal(domain, tag, format, ...args)`
- `isLoggable(domain, tag, level)`
- `setMinLogLevel(level)`
- `setLogLevel(level, prefer)`

These are output and level-control APIs. There is no `read`, `query`,
`subscribe`, `open`, or equivalent function in the module. The system
capability is `SystemCapability.HiviewDFX.HiLog`.

This means `hilog` can make the port write its own logs, but it cannot give the
port a stream of HiLog entries from the system or from another process.

### 2.2 `FaultLogger` / `faultlogger`

The SDK ships `@ohos.faultLogger.d.ts`; `@kit.PerformanceAnalysisKit` exports
it as `FaultLogger`.

The public functions are:

- `FaultLogger.querySelfFaultLog(faultType, callback)`
- `FaultLogger.querySelfFaultLog(faultType)` (Promise form)
- `FaultLogger.query(faultType, callback)`
- `FaultLogger.query(faultType)` (Promise form)

The fault types are `NO_SPECIFIC`, `CPP_CRASH`, `JS_CRASH`, and `APP_FREEZE`.
The API queries fault logs belonging to the current application; it is not a
general HiLog reader.

The declaration marks the module deprecated since API 18 and says to use
`hiAppEvent` for `APP_CRASH` and `APP_FREEZE`. This is relevant because the port
targets API 26.

The related `FaultLogExtensionAbility` and `FaultLogExtensionContext` are API
21 fault-reporting extension surfaces. Their callbacks are
`onFaultReportReady()`, `onConnect()`, and `onDisconnect()`. They are not a
streaming log reader either.

### 2.3 `hiAppEvent`

`@kit.PerformanceAnalysisKit` also exports `hiAppEvent` from
`@ohos.hiviewdfx.hiAppEvent.d.ts`.

The relevant APIs are:

- `hiAppEvent.write(info)` for application event writing
- `hiAppEvent.addWatcher(watcher)` and `hiAppEvent.removeWatcher(watcher)`
- `Watcher.onTrigger` and `Watcher.onReceive`
- `hiAppEvent.clearData()`

The system event constants include `APP_CRASH` and `APP_FREEZE`. The watcher
can filter and receive application events, and can subscribe to those system
events for the application. It does not expose HiLog lines and it does not
subscribe to the mihomo core's log stream.

This is useful for crash/freeze reporting, but not for reproducing
`Clash.subscribeLogcat()`.

### 2.4 `hidebug`

`@kit.PerformanceAnalysisKit` exports `hidebug` from `@ohos.hidebug.d.ts`.

One API looks superficially relevant: `hidebug.getServiceDump(serviceid, fd,
args)`. Its declaration says it requires `ohos.permission.DUMP` and can be
called only by a system application.

The SDK permission definition for `ohos.permission.DUMP` is:

- grant mode: `system_grant`
- available level: `system_core`
- available type: `SYSTEM`

That is not available to this normal-privilege third-party app, and no
documented public service id is supplied for "dump the hilog service".

### 2.5 `hiRetrieval`

The API 26 SDK also contains `@ohos.hiviewdfx.hiRetrieval.d.ts`, exported by
`@kit.PerformanceAnalysisKit`.

Its functions are `init`, `participate`, `quit`, `isParticipant`,
`getLastParticipationTimestamp`, `run`, and `getCurrentConfig`. It is a
participant/config surface, not a log-reading API.

### 2.6 `hdc hilog`

`hdc` is the host-side device connector shipped in the SDK toolchains. The
`hdc help` output lists `hilog` under its debug commands:

`hilog [-h] - Show device log, -h for detail`

On a connected device, both of these work from the host:

- `hdc hilog -h`
- `hdc shell hilog -h`

The `hilog` CLI supports blocking reads, `-x` non-blocking reads, filters for
level/domain/tag/PID, buffer clearing, buffer sizing, and persistent capture to
`/data/log/hilog/`.

This is developer and device tooling. It is not an ArkTS API, and the
application cannot invoke `hdc` itself.

### 2.7 Shell execution and child processes

I checked the public process APIs as a possible route around the absence of a
HiLog reader:

- `@ohos.app.ability.childProcessManager` can start an application's own ArkTS
  or native child-process entry (`startChildProcess`,
  `startArkChildProcess`, `startNativeChildProcess`). It does not provide an
  arbitrary shell-command launcher.
- `AbilityDelegator.executeShellCommand()` and `ShellCmdResult` exist, but the
  SDK declaration says those APIs can be used only in JsUnit tests.
- `@ohos.process` exposes process identity and resource information, not shell
  execution.

So there is no supported production ArkTS path that lets the app run
`hilog -x`, `hdc hilog`, or another shell command.

## 3. Device-level checks

The device connected during this review was `XMH0224429007248`.

Verified with `hdc`:

- `hdc shell id` reports `uid=2000(shell)` with group `1007(log)`.
- `/data/log/hilog` is owned by `logd:log`; the shell account can access it.
- The installed port has bundle `com.example.clashmeta`, application privilege
  level `normal`, requested permissions `["ohos.permission.INTERNET"]`, and
  gids `[20020425]` in `bm dump -n com.example.clashmeta`.
- `ls /data/log` is denied even to the shell account, while `/data/log/hilog`
  is visible through the shell's log access.

I did not run the app as its own UID: this device does not provide `run-as`.
The conclusion that the app cannot read `/data/log/hilog` is therefore an
inference from the public API surface, the absence of any granted log-read
permission, and the app's normal privilege level. It is not a successful
app-UID read test.

## 4. Permission gates checked

The SDK permission definitions contain no normal third-party
`ohos.permission.READ_LOGS` equivalent. The log-related read grants that do
exist are gated:

| Permission | Grant mode | Available level | Available type |
|---|---|---|---|
| `ohos.permission.DUMP` | `system_grant` | `system_core` | `SYSTEM` |
| `ohos.permission.ACCESS_DFX_LOG_DIR` | `system_grant` | `system_basic` | `SYSTEM` |
| `ohos.permission.ENTERPRISE_READ_LOG` | `system_grant` | `system_basic` | `MDM` |
| `ohos.permission.READ_DIAGNOSTIC_LOGS` | `system_grant` | `system_basic` | `SYSTEM` |

`ENTERPRISE_READ_LOG` is used by enterprise system-manager APIs and requires
the caller to be an administrator application with the corresponding
permission. None of these is a normal app grant.

## 5. What the port can honestly do

The port can:

- read and export log files that it wrote itself under its own `cacheDir/logs`;
- write its own diagnostic logs with `hilog`;
- receive its own crash/freeze events with `hiAppEvent`;
- use the already-requested `ohos.permission.INTERNET` for a remote mihomo
  external-controller connection.

The port cannot:

- subscribe to system HiLog from another process;
- read arbitrary device logs through a public third-party API;
- invoke `hdc`, `hilog`, or a device shell from production app code;
- recreate Android's foreground-service/core-subscription pair with the same
  semantics.

## 6. Recommendation

Keep `LogcatActivity` streaming marked as `not_ported`.

Do not add a fake streaming mode, a fake foreground service, or a UI that
polls an empty `cacheDir/logs` and presents it as live output. The existing
local-file mode is honest and independently useful.

If live mihomo logs are wanted in this port, implement them as a separate
external-controller feature:

1. Connect to the configured controller with
   `@kit.NetworkKit`'s `webSocket.createWebSocket()`.
2. Open `GET /logs` as a WebSocket, optionally with
   `?level=...&format=structured`, and add `?token=<secret>` when the
   controller has a secret. The mihomo wiki documents `GET` / `WS` for
   `/logs`; the v1.19.32 source registers `r.Get("/logs", getLogs)` and
   upgrades the request when `Upgrade: websocket` is present.
3. Parse the standard-mode JSON objects (`{type, payload}`) or the structured
   mode objects (`{time, level, message, fields}`) into the existing
   `LogMessage` model.
4. Keep the connection page-scoped, close it when the page disappears, and do
   not write it into `cacheDir/logs` unless a separate retention design is
   approved.

This external-controller route is not the Android `LogcatService` port. It
does not need the Android foreground notification, and it does not claim that
HarmonyOS allows general system-log capture.

If background capture is ever required, that is a separate product and
platform decision. The SDK's continuous-task APIs require
`ohos.permission.KEEP_BACKGROUND_RUNNING` and a valid background mode; a log
viewer should not be made into a background task merely to imitate Android's
service. That question is out of scope for the honest streaming decision here.

## 7. Current port state and code-change decision

No code change is needed in `LogcatPage.ets` or `LogcatViewModel.ets`.

- `LogcatPage.ets` is explicitly the local-file branch, has no streaming
  branch, and has no stop action.
- `LogcatViewModel.ets` explicitly documents that the streaming half is not
  ported.
- The actual streaming entry point, the `Clash Logcat` row in `LogsPage.ets`,
  already shows `$r('app.string.not_ported')`.

There is therefore nothing in those two files that pretends streaming works.
If a future caller adds a new no-`fileName` streaming route, it should show
`not_ported` at that entry point before routing to `LogcatPage`.

## 8. Verification boundary

Verified:

- Android source behavior and the JNI/core subscription path.
- The current ArkTS page/view-model state.
- The API names and declarations in the installed API 26 SDK.
- `hdc` help and device-side `hilog` availability.
- The installed app's permission list and privilege level.
- The mihomo v1.19.32 `/logs` route and the mihomo wiki's `GET` / `WS`
  contract.

Inferred, not tested by running the app under its own UID:

- A normal-privilege HarmonyOS app cannot read `/data/log/hilog`.
- The absence of a public read API and the absence of a normal log-read
  permission are sufficient to rule out a supported implementation.

Not implemented or device-tested here:

- The external-controller `/logs` WebSocket client.
- Any background/continuous-task design for log retention.

## 9. Source index

Android:

- `work/clashmeta/app/src/main/java/com/github/kr328/clash/LogcatActivity.kt`
- `work/clashmeta/app/src/main/java/com/github/kr328/clash/LogcatService.kt`
- `work/clashmeta/app/src/main/java/com/github/kr328/clash/log/LogcatCache.kt`
- `work/clashmeta/app/src/main/java/com/github/kr328/clash/log/LogcatWriter.kt`
- `work/clashmeta/core/src/main/java/com/github/kr328/clash/core/Clash.kt`
- `work/clashmeta/service/src/main/java/com/github/kr328/clash/service/ClashManager.kt`
- `work/clashmeta/app/src/main/AndroidManifest.xml`

HarmonyOS SDK:

- `.../sdk/default/openharmony/ets/kits/@kit.PerformanceAnalysisKit.d.ts`
- `.../sdk/default/openharmony/ets/api/@ohos.hilog.d.ts`
- `.../sdk/default/openharmony/ets/api/@ohos.faultLogger.d.ts`
- `.../sdk/default/openharmony/ets/api/@ohos.hiviewdfx.hiAppEvent.d.ts`
- `.../sdk/default/openharmony/ets/api/@ohos.hiviewdfx.FaultLogExtensionAbility.d.ts`
- `.../sdk/default/openharmony/ets/api/@ohos.hidebug.d.ts`
- `.../sdk/default/openharmony/ets/api/@ohos.hiviewdfx.hiRetrieval.d.ts`
- `.../sdk/default/openharmony/ets/api/@ohos.app.ability.childProcessManager.d.ts`
- `.../sdk/default/openharmony/ets/api/@ohos.net.webSocket.d.ts`
- `.../sdk/default/openharmony/toolchains/lib/PermissionDefinitions.json`

Port:

- `outputs/ClashMetaHarmony/entry/src/main/ets/pages/LogcatPage.ets`
- `outputs/ClashMetaHarmony/entry/src/main/ets/viewmodel/LogcatViewModel.ets`
- `outputs/ClashMetaHarmony/entry/src/main/ets/pages/LogsPage.ets`
- `outputs/ClashMetaHarmony/entry/src/main/ets/backend/ExternalControllerBackend.ets`

Mihomo external controller:

- Wiki: `https://wiki.metacubex.one/en/api/#logs`
- Source: `https://github.com/MetaCubeX/mihomo/blob/v1.19.32/hub/route/server.go`
