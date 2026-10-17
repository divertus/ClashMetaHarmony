# mihomo external-controller API verification

Verified 2026-10-16 against `wiki.metacubex.one` and MetaCubeX/mihomo tag
`v1.19.32` (commit `88dcbf7f1614a67c3b36b848ee3592dfa92ada36`, latest stable
release at the time of review). I also checked the `Alpha` branch commit
`94b13aed49b8dc41973e4bb3f721c5fa2c5c5c1f`; the handlers and shapes below match.

## Endpoint matrix

| Method | Path | Response / request shape | Primary-source citation | Verdict |
|---|---|---|---|---|
| `GET` | `/configs` | Top-level JSON object. `mode` is a string with values `"rule"`, `"global"`, or `"direct"`. Other top-level fields include `port`, `socks-port`, `redir-port`, `tproxy-port`, `mixed-port`, `tun`, `tuic-server`, `ss-config`, `vmess-config`, `authentication`, `skip-auth-prefixes`, `lan-allowed-ips`, `lan-disallowed-ips`, `allow-lan`, `bind-address`, `inbound-tfo`, `inbound-mptcp`, `unified-delay`, `log-level`, `ipv6`, `interface-name`, `routing-mark`, `geox-url`, `geo-auto-update`, `geo-update-interval`, `geodata-mode`, `geodata-loader`, `geosite-matcher`, `tcp-concurrent`, `find-process-mode`, `sniffing`, `global-ua`, `etag-support`, `keep-alive-idle`, `keep-alive-interval`, and `disable-keep-alive`. | Wiki: “including `port`, `socks-port`, `mixed-port`, `mode`, `log-level`, `allow-lan`, `ipv6`, `tun`, and other fields” ([API /configs](https://wiki.metacubex.one/en/api/#configs)). Source: `getConfigs` returns `executor.GetGeneral()` ([configs.go L133-L136](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/hub/route/configs.go#L133-L136)); `Mode` is tagged `json:"mode"` ([config.go L47-L91](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/config/config.go#L47-L91)); `MarshalText` delegates to `String()`, which returns `"global"`, `"rule"`, `"direct"` ([mode.go L33-L48](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/tunnel/mode.go#L33-L48)). | Correct. |
| `PATCH` | `/configs` | Request body is a partial config object, e.g. `{"mode":"global"}`. Success is HTTP `204` with no body. Mode is handled by `tunnel.SetMode`. | Wiki: “Update basic configuration”, request method `PATCH`, data `'{"mixed-port": 7890}'`, response “none (HTTP 204)” ([API /configs](https://wiki.metacubex.one/en/api/#configs)). Source: `r.Patch("/", patchConfigs)` ([configs.go L25-L33](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/hub/route/configs.go#L25-L33)); `if general.Mode != nil { tunnel.SetMode(*general.Mode) }`, then `render.NoContent` ([configs.go L382-L398](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/hub/route/configs.go#L382-L398)). | Correct way to change mode. |
| `GET` | `/providers/proxies` | Exact top-level shape is `{"providers": { "<provider-name>": { ... } }}`. Each provider value contains metadata and its `proxies` array. | Wiki: “`providers`: object keyed by provider name, each containing provider metadata and its proxy list” ([API /providers/proxies](https://wiki.metacubex.one/en/api/#providersproxies)). Source: `render.JSON(w, r, render.M{"providers": providers})` ([provider.go L40-L45](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/hub/route/provider.go#L40-L45)). | Correct. |
| `GET` | `/traffic` | Streaming response; one newline-terminated JSON object per second. Each object is `{"up":<bytes/sec>,"down":<bytes/sec>,"upTotal":<bytes>,"downTotal":<bytes>}`. `up`/`down` are per-second deltas; `upTotal`/`downTotal` are cumulative byte counters (initialized to zero at process start). It also supports WebSocket (`GET` with `Upgrade: websocket`). | Wiki: “`up`/`down` are in bytes/s, `upTotal`/`downTotal` are in bytes”; fields “`upTotal`: cumulative uploaded bytes”, “`downTotal`: cumulative downloaded bytes” ([API /traffic](https://wiki.metacubex.one/en/api/#traffic)). Source: `json.NewEncoder(buf).Encode(Traffic{Up, Down, UpTotal, DownTotal})`, followed by `w.Write(...)` and `w.(http.Flusher).Flush()`; `Traffic` has `json:"up"`, `json:"down"`, `json:"upTotal"`, `json:"downTotal"` ([server.go L48-L53, L371-L415](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/hub/route/server.go#L48-L53)). | Partly wrong: the client omits the two cumulative fields. |
| `GET` | `/version` | `{"meta": <bool>, "version": <string>}`. | Wiki: “`meta`: whether this is a Meta build (`true` / `false`)”; “`version`: version string” ([API /version](https://wiki.metacubex.one/en/api/#version)). Source: `render.JSON(w, r, render.M{"meta": C.Meta, "version": C.Version})` ([server.go L572-L574](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/hub/route/server.go#L572-L574)). | Correct. |
| `GET` | `/connections` | One-shot JSON snapshot when not a WebSocket: `{"downloadTotal":<bytes>,"uploadTotal":<bytes>,"memory":<bytes>,"connections":[...]}`. This is a direct source of cumulative totals. | Wiki: “`downloadTotal`: cumulative downloaded bytes”, “`uploadTotal`: cumulative uploaded bytes” ([API /connections](https://wiki.metacubex.one/en/api/#connections_1)). Source: non-WebSocket path returns `statistic.DefaultManager.Snapshot()` ([connections.go L24-L28](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/hub/route/connections.go#L24-L28)); snapshot fields are `downloadTotal`, `uploadTotal`, `connections`, `memory` ([manager.go L84-L95, L124-L129](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/tunnel/statistic/manager.go#L84-L95)). | Correction: cumulative totals are exposed. |
| `POST` | `/restart` | Restarts the already-running core. Source returns `{"status":"ok"}` before shutdown/re-exec. The wiki currently says HTTP `204`/no body, which disagrees with the source. Disabled in embed mode. | Wiki: “Restart the kernel”, request method `POST` ([API /restart](https://wiki.metacubex.one/en/api/#restart)). Source: `r.Post("/", restart)`, `render.JSON(... {"status":"ok"})`, then `executor.Shutdown()` and re-exec ([restart.go L18-L43, L45-L66](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/hub/route/restart.go#L18-L43)). | Correction: there is no dedicated start/stop, but there is a restart route. |

## Authentication

For normal HTTP requests, including the plain HTTP `/traffic` stream, the only
accepted form is:

```http
Authorization: Bearer <secret>
```

The wiki’s request example confirms `Authorization: Bearer ${secret}`
([API request example](https://wiki.metacubex.one/en/api/)). The source requires
`Bearer <token>` for ordinary requests; `?token=<secret>` is accepted only when
the request has `Upgrade: websocket` and a non-empty `token` query parameter
([server.go L336-L364](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/hub/route/server.go#L336-L364)).
If `secret` is empty, the authentication middleware is not installed
([server.go L119-L122](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/hub/route/server.go#L119-L122)).

## Corrections to the client’s assumptions

1. **`/traffic` is not just `up`/`down`.** The current stable and Alpha source
   both include `upTotal` and `downTotal`. The client’s comment that traffic is
   “derived, not a core total” and its “no cumulative total” assumption are
   wrong for current mihomo.
2. **There is a one-shot cumulative-total endpoint:** `GET /connections`
   returns `uploadTotal` and `downloadTotal` alongside active connections.
3. **`?token=` is not a general alternative to the Bearer header.** It is only
   honored for WebSocket upgrades. The client’s Bearer header is correct for
   its HTTP streaming `/traffic` request.
4. **The client’s newline parser is unsafe.** `dataReceive` chunks are arbitrary
   byte chunks and do not necessarily end on JSON line boundaries. The current
   code discards a partial line on `JSON.parse` failure instead of buffering it,
   so it can undercount traffic ([ExternalControllerBackend.ets L129-L144](/Users/hikaritus/Documents/Codex/2026-10-16/github-ios-android-android-ios-android-6/outputs/ClashMetaHarmony/entry/src/main/ets/backend/ExternalControllerBackend.ets:129)).
5. **No profile/config-name endpoint exists.** The registered route set has no
   profile route ([server.go L123-L142](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/hub/route/server.go#L123-L142)),
   and `GET /configs` returns the `config.General` runtime settings, which have
   no profile-name or config-path field ([config.go L47-L91](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/config/config.go#L47-L91)).
   The `PUT /configs` request accepts a `path`, but there is no corresponding
   `GET` that reports the loaded path/name ([configs.go L401-L449](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/hub/route/configs.go#L401-L449)).
6. **Start/stop versus restart.** There is no `/start` or `/stop` endpoint. A
   stopped core cannot answer the controller API, so `start()` cannot start a
   remote core. `POST /restart` can restart an already-running core, subject to
   embed-mode restrictions.
7. **`PATCH /configs` for mode is correct.** Send
   `{"mode":"rule"}`, `{"mode":"global"}`, or `{"mode":"direct"}` and expect
   `204`. If the ArkTS client adds mode switching, do not reuse a helper that
   treats anything other than HTTP `200` as failure.

## Bottom line

The client is correct about `GET /configs`, `GET /providers/proxies`,
`GET /version`, Bearer authentication for ordinary HTTP, the absence of a
profile-name endpoint, and the use of `PATCH /configs` for mode changes. The
material API-contract misses are the `/traffic` cumulative fields and the
existence of `GET /connections` for one-shot totals; the lifecycle wording also
needs the `POST /restart` caveat.
