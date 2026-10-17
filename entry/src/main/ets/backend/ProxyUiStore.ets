/*
 * The three proxy-screen preferences carried by CMFA's `UiStore`.
 *
 * Ported from ClashMetaForAndroid:
 *   design/src/main/java/com/github/kr328/clash/design/store/UiStore.kt
 *
 * Android persists these in SharedPreferences and feeds them into the native
 * queries (`queryProxyGroupNames(proxyExcludeNotSelectable)` and
 * `queryProxyGroup(name, proxySort)`) plus the row layout
 * (`ProxyViewConfig(context, proxyLine)`). The port owns its own list shaping,
 * so the same three values drive the filter, the sort and the grid instead.
 *
 * Key names follow UiStore: proxy_exclude_not_selectable / proxy_line /
 * proxy_sort.
 */

import { PersistenceV2 } from '@kit.ArkUI';
import { ProxySort } from '../model/ProxyModels';

@ObservedV2
export class ProxyUiStore {
  static readonly KEY: string = 'ClashProxyUiStore';

  /** `UiStore.proxyExcludeNotSelectable`, default false. */
  @Trace excludeNotSelectable: boolean = false;

  /** `UiStore.proxyLine`, default 2; only 1, 2 and 3 are offered. */
  @Trace line: number = 2;

  /** `UiStore.proxySort`, default `ProxySort.Default`. */
  @Trace sort: ProxySort = ProxySort.Default;
}

/** Load the persisted store, or create the default one on first run. */
export function loadProxyUiStore(): ProxyUiStore {
  const store: ProxyUiStore | undefined =
    PersistenceV2.connect(ProxyUiStore, ProxyUiStore.KEY, () => new ProxyUiStore());
  return store ?? new ProxyUiStore();
}
