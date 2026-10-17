/*
 * Local override store.
 *
 * Ported from ClashMetaForAndroid:
 *   app/src/main/java/com/github/kr328/clash/OverrideSettingsActivity.kt
 *   (`withClash { queryOverride(OverrideSlot.Persist) }` on entry,
 *    `withClash { patchOverride(OverrideSlot.Persist, configuration) }` on exit,
 *    `withClash { clearOverride(OverrideSlot.Persist) }` for the reset button)
 *
 * Android keeps the persist override inside the tunnel service, next to the
 * profiles; the port keeps the same value in `PersistenceV2` instead, because
 * there is no service to own it.
 *
 * The shape is the one `UiStore` and `ProfileStore` use: exactly one `@Trace`
 * string and no methods, with every operation a free function that decodes,
 * mutates and re-encodes it. Anything richer silently stops being saved.
 */

import { PersistenceV2 } from '@kit.ArkUI';
import { overrideParse } from '../model/OverrideModels';

@ObservedV2
export class OverrideStore {
  static readonly KEY: string = 'ClashOverrideStore';

  /** The override record as JSON; the store's only state. */
  @Trace encoded: string = '{}';
}

/** Load the persisted store, or create the default one on first run. */
export function loadOverrideStore(): OverrideStore {
  const store: OverrideStore | undefined =
    PersistenceV2.connect(OverrideStore, OverrideStore.KEY, () => new OverrideStore());
  return store ?? new OverrideStore();
}

/** Mirrors `queryOverride(Clash.OverrideSlot.Persist)`. */
export function overrideLoad(store: OverrideStore): Record<string, string> {
  return overrideParse(store.encoded);
}

/** Mirrors `patchOverride(Clash.OverrideSlot.Persist, configuration)`. */
export function overrideSave(store: OverrideStore, data: Record<string, string>): void {
  store.encoded = JSON.stringify(data);
}

/** Mirrors `clearOverride(Clash.OverrideSlot.Persist)`. */
export function overrideClear(store: OverrideStore): void {
  store.encoded = '{}';
}
