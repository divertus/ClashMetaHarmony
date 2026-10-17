/*
 * mihomo external-controller client.
 *
 * Implements ClashBackend against the REST API that mihomo (Clash.Meta) exposes
 * on its `external-controller` address. Endpoints used, verified against
 * wiki.metacubex.one and the mihomo v1.19.32 source:
 *
 *   GET /configs            -> { mode: "rule" | "global" | "direct", ... }
 *   PATCH /configs          -> partial config, 204; mirrors patchOverride()
 *   GET /proxies            -> { proxies: { ... } }   (groups carry `all`)
 *   PUT /proxies/{name}     -> {"name": "..."}, 204; select a group member
 *   GET /group/{name}/delay -> { "<member>": <ms>, ... }; delay test
 *   GET /providers/proxies  -> { providers: { ... } }
 *   GET /connections        -> { uploadTotal, downloadTotal, connections }
 *   GET /traffic            -> chunked stream, newline-delimited JSON:
 *                              { up, down, upTotal, downTotal } per second
 *
 * Auth: `?token=` is WebSocket-only on this API; ordinary HTTP requests must
 * carry `Authorization: Bearer <secret>`. That is what this client sends.
 *
 * MAPPING HONESTY -- what the controller API can and cannot answer
 * ---------------------------------------------------------------
 * The Android app reads five values straight out of the in-process core. Three
 * have a faithful external-controller equivalent and two do not:
 *
 *   mode          -> GET /configs.mode                   exact
 *   hasProviders  -> GET /providers/proxies + /providers/rules non-empty
 *                                                        exact
 *   traffic       -> GET /connections totals              authoritative
 *                    (the /traffic stream also carries running totals, used
 *                     to keep the figure live between snapshot polls)
 *   profileName   -> NOT EXPOSED by the controller API    -> left unset
 *   start / stop  -> only POST /restart exists; there is no /start or /stop.
 *                    A remote core is started and stopped on the host running
 *                    it, not over this API. start() therefore only probes.
 *
 * "connected" therefore means "the controller answered", which is a weaker
 * claim than Android's tunnel-state query.
 */

import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BackendSnapshot, ClashBackend } from './BackendTypes';
import { TunnelMode } from '../model/MainModels';
import { ProxyGroup, ProxyNode } from '../model/ProxyModels';
import { ProviderItem, sortProviders } from '../model/ProviderModels';
import { ControllerStore } from './ControllerStore';

interface ConfigsResponse {
  mode?: string;
  port?: number;
}

interface ConnectionsResponse {
  uploadTotal?: number;
  downloadTotal?: number;
}

interface TrafficLine {
  up?: number;
  down?: number;
  upTotal?: number;
  downTotal?: number;
}

/** One entry of `GET /proxies`. Groups carry `all`; leaf nodes do not. */
interface ProxyEntry {
  type?: string;
  now?: string;
  all?: string[];
  history?: ProxyHistoryEntry[];
}

interface ProxyHistoryEntry {
  time?: string;
  delay?: number;
}

interface ProxiesResponse {
  proxies?: Record<string, ProxyEntry>;
}

/**
 * One entry of `GET /providers/proxies` or `GET /providers/rules`.
 *
 * Proxy providers carry `{name, type:"Proxy", vehicleType, proxies, testUrl,
 * expectedStatus, updatedAt, subscriptionInfo?}`; rule providers carry
 * `{behavior, format, name, ruleCount, type:"Rule", vehicleType, updatedAt}`.
 * Only the four fields the UI needs are declared here. `updatedAt` is a Go
 * `time.Time`, so it arrives as an RFC3339 string (and is present even when
 * zero, because `omitempty` does not apply to structs).
 */
interface ProviderEntry {
  name?: string;
  type?: string;
  vehicleType?: string;
  updatedAt?: string;
}

interface ProviderListResponse {
  providers?: Record<string, ProviderEntry>;
}

/** mihomo answers a rejected request with `{"message":"..."}`. */
interface ErrorResponse {
  message?: string;
}

/** Request body for `PUT /proxies/{group}`. */
interface SelectProxyRequest {
  name: string;
}

/** Request body for `PATCH /configs` when switching mode. */
interface PatchModeRequest {
  mode: string;
}

const CONNECT_TIMEOUT_MS: number = 4000;
const READ_TIMEOUT_MS: number = 6000;

/**
 * Delay-test parameters.
 *
 * `constant.DefaultTestURL` from mihomo is the target the core itself falls
 * back to. Android's `healthCheck(group)` re-tests through each of the group's
 * providers, which uses that provider's own configured `testUrl`; the
 * controller API has no per-provider "health check this group" call, so the
 * group endpoint is driven with mihomo's defaults instead.
 *
 * The test timeout is also the server-side budget, so the HTTP read timeout
 * for that one request has to be larger than it.
 */
const DELAY_TEST_URL: string = 'https://www.gstatic.com/generate_204';
const DELAY_TEST_TIMEOUT_MS: number = 5000;
const DELAY_TEST_READ_TIMEOUT_MS: number = DELAY_TEST_TIMEOUT_MS + 4000;

function normalizeBaseUrl(raw: string): string {
  let url: string = raw.trim();
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

function modeFromString(raw: string | undefined): TunnelMode {
  if (raw === 'direct') {
    return TunnelMode.Direct;
  }
  if (raw === 'global') {
    return TunnelMode.Global;
  }
  return TunnelMode.Rule;
}

/**
 * The controller reports `updatedAt` as an RFC3339 string (Go `time.Time`)
 * where the Android core reports epoch milliseconds. Go's zero time
 * ("0001-01-01T00:00:00Z") means "never updated" and maps to 0.
 */
function epochMillisFromRfc3339(raw: string | undefined): number {
  if (raw === undefined || raw.length === 0) {
    return 0;
  }
  const parsed: number = Date.parse(raw);
  if (Number.isNaN(parsed) || parsed < 0) {
    return 0;
  }
  return parsed;
}

export class ExternalControllerBackend implements ClashBackend {
  private store: ControllerStore;

  /**
   * Running totals. These come from the core (via /connections or the totals
   * embedded in /traffic), never from summing our own deltas -- partial reads
   * and reconnects would make an accumulated figure drift.
   */
  private totalUp: number = 0;
  private totalDown: number = 0;

  private streaming: boolean = false;
  private streamRequest: http.HttpRequest | null = null;

  /**
   * Carry-over for a JSON object split across two chunks. The stream emits one
   * object per second and chunk boundaries do not respect line boundaries, so
   * a fragment must be kept and prepended to the next chunk rather than
   * discarded.
   */
  private pendingLine: string = '';

  constructor(store: ControllerStore) {
    this.store = store;
  }

  private authHeader(): Record<string, string> {
    const header: Record<string, string> = {};
    const secret: string = this.store.secret.trim();
    if (secret.length > 0) {
      header['Authorization'] = `Bearer ${secret}`;
    }
    return header;
  }

  /** One-shot GET returning the response body, or null when unreachable. */
  private async getJson(path: string, readTimeoutMs: number = READ_TIMEOUT_MS): Promise<string | null> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: this.authHeader(),
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: readTimeoutMs,
        expectDataType: http.HttpDataType.STRING
      };
      const response: http.HttpResponse =
        await request.request(normalizeBaseUrl(this.store.baseUrl) + path, options);
      if (response.responseCode !== 200) {
        return null;
      }
      return response.result as string;
    } catch (error) {
      return null;
    } finally {
      request.destroy();
    }
  }

  /**
   * Consume GET /traffic. Each chunk carries zero or more complete JSON objects
   * plus possibly a trailing fragment, which is buffered until the next chunk.
   */
  startTrafficStream(): void {
    if (this.streaming) {
      return;
    }
    const request: http.HttpRequest = http.createHttp();
    this.streamRequest = request;
    this.streaming = true;
    this.pendingLine = '';

    request.on('dataReceive', (chunk: ArrayBuffer) => {
      const text: string =
        this.pendingLine + util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(chunk));
      const lines: string[] = text.split('\n');

      // The last element is either empty (chunk ended on a newline) or a
      // fragment; either way it belongs to the next chunk.
      this.pendingLine = lines.pop() ?? '';

      for (const line of lines) {
        const trimmed: string = line.trim();
        if (trimmed.length === 0) {
          continue;
        }
        try {
          const parsed: TrafficLine = JSON.parse(trimmed) as TrafficLine;
          // Prefer the core's running totals; older builds only send deltas.
          if (parsed.upTotal !== undefined) {
            this.totalUp = parsed.upTotal;
          }
          if (parsed.downTotal !== undefined) {
            this.totalDown = parsed.downTotal;
          }
        } catch (error) {
          // Malformed line: skip it rather than corrupt the totals.
        }
      }
    });

    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: this.authHeader(),
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: 0
    };

    request.requestInStream(
      normalizeBaseUrl(this.store.baseUrl) + '/traffic',
      options,
      (error: Error, code: number) => {
        this.streaming = false;
        request.destroy();
        this.streamRequest = null;
      }
    );
  }

  stopTrafficStream(): void {
    const request: http.HttpRequest | null = this.streamRequest;
    this.streaming = false;
    this.streamRequest = null;
    this.pendingLine = '';
    if (request !== null) {
      request.destroy();
    }
  }

  /** Ask the core for authoritative running totals. */
  private async refreshTotals(): Promise<void> {
    const body: string | null = await this.getJson('/connections');
    if (body === null) {
      return;
    }
    try {
      const connections: ConnectionsResponse = JSON.parse(body) as ConnectionsResponse;
      if (connections.uploadTotal !== undefined) {
        this.totalUp = connections.uploadTotal;
      }
      if (connections.downloadTotal !== undefined) {
        this.totalDown = connections.downloadTotal;
      }
    } catch (error) {
      // Leave the previous totals in place.
    }
  }

  resetTraffic(): void {
    this.totalUp = 0;
    this.totalDown = 0;
  }

  async snapshot(): Promise<BackendSnapshot> {
    const configsBody: string | null = await this.getJson('/configs');
    const reachable: boolean = configsBody !== null;

    let mode: TunnelMode = TunnelMode.Rule;
    if (configsBody !== null) {
      try {
        const configs: ConfigsResponse = JSON.parse(configsBody) as ConfigsResponse;
        mode = modeFromString(configs.mode);
      } catch (error) {
        mode = TunnelMode.Rule;
      }
    }

    let hasProviders: boolean = false;
    if (reachable) {
      // `Clash.queryProviders()` merges `tunnel.RuleProviders()` and
      // `tunnel.Providers()`, then drops `Compatible` vehicle types. The
      // controller API exposes those as two documents, so use the same merge
      // path the Providers screen already uses.
      const providers: ProviderItem[] = await this.listProviders();
      hasProviders = providers.length > 0;
      await this.refreshTotals();
    }

    const snapshot: BackendSnapshot = {
      connected: reachable,
      uploadBytes: this.totalUp,
      downloadBytes: this.totalDown,
      mode: mode,
      // The controller API does not expose the loaded profile's name.
      profileName: '',
      hasProfile: false,
      hasProviders: hasProviders
    };
    return snapshot;
  }

  /**
   * The controller API cannot start a remote core (only POST /restart exists).
   * This probes reachability so the caller can report "connected".
   */
  async start(): Promise<boolean> {
    const body: string | null = await this.getJson('/configs');
    const connected: boolean = body !== null;
    if (connected) {
      this.resetTraffic();
      this.startTrafficStream();
    }
    return connected;
  }

  /** Not representable over the controller API; documented no-op. */
  async stop(): Promise<void> {
    this.stopTrafficStream();
  }

  /** Current running totals, as reported by the core. */
  getTrafficTotals(): [number, number] {
    return [this.totalUp, this.totalDown];
  }

  /** One-shot request with a JSON body; returns true on a 2xx response. */
  private async sendJson(method: http.RequestMethod, path: string, body: string): Promise<boolean> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const header: Record<string, string> = this.authHeader();
      header['Content-Type'] = 'application/json';
      const options: http.HttpRequestOptions = {
        method: method,
        header: header,
        extraData: body,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING
      };
      const response: http.HttpResponse =
        await request.request(normalizeBaseUrl(this.store.baseUrl) + path, options);
      return response.responseCode >= 200 && response.responseCode < 300;
    } catch (error) {
      return false;
    } finally {
      request.destroy();
    }
  }

  /**
   * Read every proxy group. Mirrors `queryProxyGroupNames()` +
   * `queryProxyGroup(name)` from ProxyActivity, which the Android app obtains
   * from the native core.
   *
   * Groups are the entries that carry an `all` array. Each member's latest
   * delay comes from that member's own `history` array when present.
   */
  async listProxyGroups(): Promise<ProxyGroup[]> {
    const body: string | null = await this.getJson('/proxies');
    const groups: ProxyGroup[] = [];
    if (body === null) {
      return groups;
    }

    let map: Record<string, ProxyEntry> | undefined = undefined;
    try {
      const parsed: ProxiesResponse = JSON.parse(body) as ProxiesResponse;
      map = parsed.proxies;
    } catch (error) {
      return groups;
    }
    if (map === undefined) {
      return groups;
    }

    const names: string[] = Object.keys(map);
    for (const name of names) {
      const entry: ProxyEntry = map[name];
      const all: string[] | undefined = entry.all;
      if (all === undefined || all.length === 0) {
        continue;
      }

      const group: ProxyGroup = new ProxyGroup();
      group.name = name;
      group.type = entry.type ?? '';
      group.now = entry.now ?? '';
      // Only a Selector can be switched; URLTest/Fallback pick automatically.
      group.selectable = group.type === 'Selector';

      const nodes: ProxyNode[] = [];
      for (const member of all) {
        const node: ProxyNode = new ProxyNode();
        node.name = member;
        const memberEntry: ProxyEntry | undefined = map[member];
        if (memberEntry !== undefined) {
          node.type = memberEntry.type ?? '';
          // A member that is itself a group is rendered as "type(now)".
          // Mirrors ProxyViewState.update(): subtitle = "%s(%s)".format(type,
          // link.now.ifEmpty { "*" }). Leaf nodes keep their plain type.
          const memberAll: string[] | undefined = memberEntry.all;
          if (memberAll !== undefined && memberAll.length > 0) {
            const memberNow: string = memberEntry.now ?? '';
            node.type = `${node.type}(${memberNow.length > 0 ? memberNow : '*'})`;
          }
          const history: ProxyHistoryEntry[] | undefined = memberEntry.history;
          if (history !== undefined && history.length > 0) {
            const latest: ProxyHistoryEntry = history[history.length - 1];
            node.delay = latest.delay ?? -1;
          }
        }
        nodes.push(node);
      }
      group.nodes = nodes;
      groups.push(group);
    }
    return groups;
  }

  /**
   * Read one provider collection and append the entries the Android core keeps.
   *
   * `tunnel.QueryProviders()` skips every provider whose `vehicleType` is
   * `Compatible`; those are dropped here too so the list matches Android.
   */
  private async collectProviders(path: string, into: ProviderItem[]): Promise<void> {
    const body: string | null = await this.getJson(path);
    if (body === null) {
      return;
    }

    let map: Record<string, ProviderEntry> | undefined = undefined;
    try {
      const parsed: ProviderListResponse = JSON.parse(body) as ProviderListResponse;
      map = parsed.providers;
    } catch (error) {
      return;
    }
    if (map === undefined) {
      return;
    }

    for (const key of Object.keys(map)) {
      const entry: ProviderEntry = map[key];
      const vehicleType: string = entry.vehicleType ?? '';
      if (vehicleType === 'Compatible') {
        continue;
      }

      const item: ProviderItem = new ProviderItem();
      item.name = entry.name ?? key;
      item.type = entry.type ?? '';
      item.vehicleType = vehicleType;
      item.updatedAt = epochMillisFromRfc3339(entry.updatedAt);
      into.push(item);
    }
  }

  /**
   * Read every provider. Mirrors `Clash.queryProviders()` followed by
   * `ProvidersActivity`'s `.sorted()`: rule and proxy providers merged,
   * `Compatible` dropped, then ordered Proxy-before-Rule by name.
   *
   * The Android core merges both collections in one call; the controller API
   * exposes them as two documents, so this issues two GETs.
   */
  async listProviders(): Promise<ProviderItem[]> {
    const items: ProviderItem[] = [];
    await this.collectProviders('/providers/proxies', items);
    await this.collectProviders('/providers/rules', items);
    sortProviders(items);
    return items;
  }

  /**
   * Refresh one provider. Mirrors `updateProvider(type, name)` in
   * core/src/main/golang/native/tunnel/providers.go: "Rule" resolves against
   * `tunnel.RuleProviders()`, "Proxy" against `tunnel.Providers()`. Over the
   * controller API that is a `PUT` on the matching collection, answered with
   * HTTP 204 (503 when the fetch fails).
   *
   * Returns '' on success, otherwise the core's message (Android surfaces the
   * thrown exception's message in the same place) or the status code.
   */
  async updateProvider(type: string, name: string): Promise<string> {
    const collection: string = type === 'Rule' ? '/providers/rules/' : '/providers/proxies/';
    const request: http.HttpRequest = http.createHttp();
    try {
      // No request body: mihomo's updateProvider handler ignores one, and
      // ArkTS rejects an empty `extraData` before the request leaves the app.
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.PUT,
        header: this.authHeader(),
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING
      };
      const response: http.HttpResponse = await request.request(
        normalizeBaseUrl(this.store.baseUrl) + collection + encodeURIComponent(name),
        options
      );
      if (response.responseCode >= 200 && response.responseCode < 300) {
        return '';
      }
      return this.errorMessage(response.result as string, response.responseCode);
    } catch (error) {
      // Android surfaces the thrown exception's message in the same toast.
      const message: string = error instanceof Error ? error.message : '';
      return message.length > 0 ? message : 'controller unreachable';
    } finally {
      request.destroy();
    }
  }

  /** Prefer the core's own message; fall back to the raw status code. */
  private errorMessage(body: string, statusCode: number): string {
    try {
      const parsed: ErrorResponse = JSON.parse(body) as ErrorResponse;
      const message: string | undefined = parsed.message;
      if (message !== undefined && message.length > 0) {
        return message;
      }
    } catch (error) {
      // Body was not JSON; fall through to the status code.
    }
    return `HTTP ${statusCode}`;
  }

  /**
   * Switch the selected member of a group. Mirrors `patchSelector(index, name)`
   * from ProxyActivity: `PUT /proxies/{group}` with `{"name": "<member>"}`.
   */
  async selectProxy(group: string, name: string): Promise<boolean> {
    const payload: SelectProxyRequest = { name: name };
    const body: string = JSON.stringify(payload);
    return await this.sendJson(
      http.RequestMethod.PUT,
      `/proxies/${encodeURIComponent(group)}`,
      body
    );
  }

  /**
   * Switch the tunnel mode. Mirrors `patchOverride(Session, o)` with `o.mode`:
   * `PATCH /configs` with `{"mode": "<rule|global|direct>"}`.
   */
  async patchMode(mode: string): Promise<boolean> {
    const payload: PatchModeRequest = { mode: mode };
    return await this.patchConfigs(JSON.stringify(payload));
  }

  /**
   * `PATCH /configs` with a partial config object. Mirrors
   * `patchOverride(Clash.OverrideSlot.Persist, configuration)`: the request body
   * is a `config.General`, so only the fields that struct carries survive --
   * ports, `authentication`, `allow-lan`, `bind-address`, `mode`, `log-level`
   * and `ipv6`. `hosts`, the whole `dns` block, `external-controller` and
   * `secret` live in `RawConfig` and are dropped by this endpoint.
   *
   * `OverrideSettingsPage` builds the body; it is passed through as text so the
   * caller decides which rows to include.
   */
  async patchConfigs(body: string): Promise<boolean> {
    return await this.sendJson(http.RequestMethod.PATCH, '/configs', body);
  }

  /**
   * Read just the tunnel mode. `ProxyActivity` reads it once at start
   * (`queryOverride(Session).mode`) to tick the right entry in the overflow
   * menu; `snapshot()` would also pull providers and traffic.
   */
  async queryMode(): Promise<TunnelMode | null> {
    const body: string | null = await this.getJson('/configs');
    if (body === null) {
      return null;
    }
    try {
      const configs: ConfigsResponse = JSON.parse(body) as ConfigsResponse;
      return modeFromString(configs.mode);
    } catch (error) {
      return null;
    }
  }

  /**
   * Run a delay test across every member of a group.
   *
   * `GET /group/{name}/delay?url=&timeout=` answers with a
   * `{"<member>": <milliseconds>}` map (mihomo `hub/route/groups.go`,
   * `getGroupDelay`); `0` in that map means the member failed. A group that is
   * not a proxy group answers 404, and exceeding the server-side timeout
   * answers 504.
   *
   * This stands in for `healthCheck(name)` followed by `Reload(index)` from
   * ProxyActivity: the test refreshes each member's delay history, and the
   * caller re-reads the group afterwards.
   */
  async urlTestGroup(group: string): Promise<boolean> {
    const path: string =
      `/group/${encodeURIComponent(group)}/delay` +
        `?url=${encodeURIComponent(DELAY_TEST_URL)}&timeout=${DELAY_TEST_TIMEOUT_MS}`;
    const body: string | null = await this.getJson(path, DELAY_TEST_READ_TIMEOUT_MS);
    return body !== null;
  }
}
