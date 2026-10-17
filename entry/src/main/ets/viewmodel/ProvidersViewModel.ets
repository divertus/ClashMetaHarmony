/*
 * ViewModel for the providers screen.
 *
 * Ported from ClashMetaForAndroid `ProvidersActivity` / `ProvidersDesign`:
 *
 *   queryProviders().sorted()          -> listProviders()
 *   ticker(1 minute) -> updateElapsed() -> the elapsed column only
 *   Request.Update(index, provider)     -> updateProvider(type, name)
 *   requestUpdateAll()                  -> every idle, non-Inline provider
 *
 * Android reads the list from the native core and refreshes one provider
 * through `Clash.updateProvider`; both map onto the mihomo external-controller
 * API (`GET /providers/proxies` + `/providers/rules`, `PUT` on either).
 *
 * A failed refresh raises the same toast Android raises
 * (`ProvidersDesign.showExceptionToast`). It lives here rather than in the page
 * because `requestUpdateAll()` can fail for several providers in a row and the
 * original shows one toast per failure.
 */

import { promptAction } from '@kit.ArkUI';
import { ProviderItem } from '../model/ProviderModels';
import { ControllerStore } from '../backend/ControllerStore';
import { ExternalControllerBackend } from '../backend/ExternalControllerBackend';

@ObservedV2
export class ProvidersViewModel {
  @Trace items: ProviderItem[] = [];
  @Trace loading: boolean = true;
  @Trace lastError: string = '';

  /**
   * Clock behind the elapsed column. Android binds `ObservableCurrentTime` and
   * re-reads it once a minute; the row subtracts `item.updatedAt` from this.
   */
  @Trace now: number = Date.now();

  private backend: ExternalControllerBackend | null = null;

  /** Handle for the 1-minute elapsed ticker; -1 when not running. */
  private tickerId: number = -1;

  useController(store: ControllerStore): void {
    this.backend = new ExternalControllerBackend(store);
  }

  /** Mirrors the initial `queryProviders().sorted()`. */
  async reload(): Promise<void> {
    const backend: ExternalControllerBackend | null = this.backend;
    if (backend === null) {
      this.loading = false;
      this.lastError = 'no controller configured';
      return;
    }
    this.loading = true;
    try {
      const items: ProviderItem[] = await backend.listProviders();
      this.items = items;
      this.lastError = items.length === 0 ? 'controller unreachable' : '';
      this.now = Date.now();
    } catch (error) {
      this.lastError = 'controller unreachable';
    } finally {
      this.loading = false;
    }
  }

  /** Mirrors the 1-minute ticker that drives `ProvidersDesign.updateElapsed()`. */
  startTicker(): void {
    if (this.tickerId !== -1) {
      return;
    }
    this.tickerId = setInterval(() => {
      this.now = Date.now();
    }, 60000);
  }

  stopTicker(): void {
    if (this.tickerId === -1) {
      return;
    }
    clearInterval(this.tickerId);
    this.tickerId = -1;
  }

  /**
   * Mirrors `ProvidersDesign.requestUpdateAll()`: every provider that is idle
   * and not Inline is marked updating and refreshed. Inline providers have no
   * remote source to fetch, so Android hides their action entirely.
   */
  async updateAll(): Promise<void> {
    const pending: ProviderItem[] = [];
    for (const item of this.items) {
      if (item.updating || item.vehicleType === 'Inline') {
        continue;
      }
      item.updating = true;
      pending.push(item);
    }
    for (const item of pending) {
      await this.update(item);
    }
  }

  /**
   * Mirrors `Request.Update` -> `updateProvider(type, name)`, followed by
   * `notifyChanged` on success (stamp `updatedAt`) or `notifyUpdated` on
   * failure (keep the previous timestamp and show the failure toast).
   */
  async update(item: ProviderItem): Promise<boolean> {
    const backend: ExternalControllerBackend | null = this.backend;
    if (backend === null) {
      return false;
    }

    item.updating = true;
    const failure: string = await backend.updateProvider(item.type, item.name);
    item.updating = false;

    if (failure.length === 0) {
      item.updatedAt = Date.now();
      this.now = item.updatedAt;
      this.lastError = '';
      return true;
    }

    this.lastError = `Update ${item.name}`;
    promptAction.showToast({
      message: $r('app.string.format_update_provider_failure', item.name, failure)
    });
    return false;
  }
}
