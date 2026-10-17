/*
 * Proxy group / node models.
 *
 * Ported from ClashMetaForAndroid:
 *   core/src/main/java/com/github/kr328/clash/core/model/Proxy.kt
 *   design/src/main/java/com/github/kr328/clash/design/model/ProxyState.kt
 *
 * Source shape (from mihomo `GET /proxies`):
 *   { "proxies": {
 *       "GLOBAL":  { "type": "Selector", "now": "Proxy", "all": ["Proxy"], ... },
 *       "Proxy":   { "type": "Selector", "now": "node-1", "all": ["node-1","node-2"] },
 *       "node-1":  { "type": "Shadowsocks", "history": [...] }
 *   } }
 *
 * Only entries carrying an `all` array are groups; the rest are leaf nodes,
 * which is how the group list is derived here. On Android the same split comes
 * from `queryProxyGroupNames()`.
 */

/** One selectable member of a group, as shown in the list. */
@ObservedV2
export class ProxyNode {
  @Trace name: string = '';
  @Trace type: string = '';

  /** Latest delay in ms, or -1 when the core has no measurement yet. */
  @Trace delay: number = -1;
}

/**
 * Mirrors `core/model/ProxySort.kt`, which the native bridge turns into the
 * `Title` / `Delay` / default branches of `QueryProxyGroup` in
 * `core/src/main/golang/native/tunnel/proxies.go`.
 */
export enum ProxySort {
  Default = 'Default',
  Title = 'Title',
  Delay = 'Delay'
}

/** A proxy group: a tab in the UI, and one page of nodes. */
@ObservedV2
export class ProxyGroup {
  @Trace name: string = '';
  @Trace type: string = '';

  /** Currently selected member (`now`). */
  @Trace now: string = '';

  @Trace nodes: ProxyNode[] = [];

  /** True when the group can be switched, i.e. it is a Selector. */
  @Trace selectable: boolean = false;
}
