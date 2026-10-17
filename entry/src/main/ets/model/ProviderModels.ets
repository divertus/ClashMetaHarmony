/*
 * Provider models -- port of ClashMetaForAndroid:
 *   core/src/main/java/com/github/kr328/clash/core/model/Provider.kt
 *   design/src/main/java/com/github/kr328/clash/design/model/ProviderState.kt
 *
 * Where the Android list comes from
 * --------------------------------
 * `Clash.queryProviders()` -> `Bridge.nativeQueryProviders()` ->
 * `tunnel.QueryProviders()` (core/src/main/golang/native/tunnel/providers.go).
 * That function concatenates **rule providers first, then proxy providers**,
 * skipping every provider whose `vehicleType` is `Compatible`, and reports
 * `updatedAt` as epoch **milliseconds** (`updatedAt.UnixNano() / 1000 / 1000`).
 *
 * Over the mihomo external-controller API the same set is split across two
 * documents -- `GET /providers/proxies` and `GET /providers/rules` -- and both
 * shapes carry `name` / `type` / `vehicleType` / `updatedAt`, except that
 * `updatedAt` is an RFC3339 string (`time.Time`) instead of epoch millis. The
 * `Compatible` filter and the ordering are applied in the backend.
 *
 * The ProxyViewConfig-style per-row UI state (`updating`) lives on the item so
 * a single `@ObservedV2` object drives the row.
 */

/** One row of the provider list. */
@ObservedV2
export class ProviderItem {
  @Trace name: string = '';

  /** `Proxy` | `Rule` -- `Provider.Type`. */
  @Trace type: string = '';

  /** `HTTP` | `File` | `Inline` | `Compatible` -- `Provider.VehicleType`. */
  @Trace vehicleType: string = '';

  /** Epoch milliseconds; 0 when the core has no timestamp for this provider. */
  @Trace updatedAt: number = 0;

  /** Mirrors `ProviderState.updating`: a refresh request is in flight. */
  @Trace updating: boolean = false;
}

/**
 * Mirrors `Provider.compareTo` / `compareValuesBy(type, name)`.
 *
 * `Provider.Type` is declared `Proxy, Rule`, so the enum ordinal puts Proxy
 * first; `ProvidersActivity` then does `.sorted()`, i.e. Proxy providers (by
 * name) followed by Rule providers (by name).
 */
function providerTypeRank(type: string): number {
  return type === 'Rule' ? 1 : 0;
}

export function sortProviders(items: ProviderItem[]): void {
  items.sort((left: ProviderItem, right: ProviderItem): number => {
    const rankDelta: number = providerTypeRank(left.type) - providerTypeRank(right.type);
    if (rankDelta !== 0) {
      return rankDelta;
    }
    if (left.name < right.name) {
      return -1;
    }
    if (left.name > right.name) {
      return 1;
    }
    return 0;
  });
}

const MS_PER_DAY: number = 24 * 60 * 60 * 1000;
const MS_PER_HOUR: number = 60 * 60 * 1000;
const MS_PER_MINUTE: number = 60 * 1000;

/**
 * Mirrors `Long.elapsedIntervalString` (design/util/Interval.kt): whole days,
 * else whole hours, else whole minutes, else "Recently".
 */
export function elapsedIntervalString(elapsedMs: number): ResourceStr {
  const day: number = Math.floor(elapsedMs / MS_PER_DAY);
  const hour: number = Math.floor(elapsedMs / MS_PER_HOUR);
  const minute: number = Math.floor(elapsedMs / MS_PER_MINUTE);

  if (day > 0) {
    return $r('app.string.format_days_ago', day);
  }
  if (hour > 0) {
    return $r('app.string.format_hours_ago', hour);
  }
  if (minute > 0) {
    return $r('app.string.format_minutes_ago', minute);
  }
  return $r('app.string.recently');
}
