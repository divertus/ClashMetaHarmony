/*
 * ViewModel for the proxy screen.
 *
 * Ported from ClashMetaForAndroid ProxyActivity:
 *
 *   queryProxyGroupNames(uiStore.proxyExcludeNotSelectable)  -> group names
 *   queryProxyGroup(name, uiStore.proxySort)                 -> { now, proxies, type }
 *   patchSelector(index, name)                               -> select a member
 *   healthCheck(index)                                       -> URL test
 *
 * Android reads those from the native core and reloads all groups concurrently
 * through a Semaphore(10). Here they come from the mihomo external-controller
 * API, which exposes the same data as a single `GET /proxies` document, so the
 * per-group fan-out collapses into one request.
 *
 * Because the core and the controller disagree about *which* groups exist,
 * `shape()` reproduces the three rules the native `QueryProxyGroupNames` +
 * `QueryProxyGroup` pair applies: the Direct/Global mode decides whether any
 * group is listed and whether `GLOBAL` is among them, the not-selectable flag
 * drops non-`Selector` groups, and the sort orders each group's members.
 */

import { ProxyGroup, ProxyNode, ProxySort } from '../model/ProxyModels';
import { TunnelMode } from '../model/MainModels';
import { ControllerStore } from '../backend/ControllerStore';
import { ProxyUiStore } from '../backend/ProxyUiStore';
import { ExternalControllerBackend } from '../backend/ExternalControllerBackend';

/**
 * mihomo always exposes a `GLOBAL` selector, but it only routes when the
 * tunnel runs in Global mode. `QueryProxyGroupNames` therefore surfaces it
 * only in that mode (`if mode == tunnel.Global { result = append(...) }`).
 */
const GLOBAL_GROUP: string = 'GLOBAL';

@ObservedV2
export class ProxyViewModel {
  @Trace groups: ProxyGroup[] = [];
  @Trace loading: boolean = true;
  @Trace lastError: string = '';
  @Trace selectedIndex: number = 0;

  /** Mirrors `ProxyState.urlTesting`: true while the delay test is running. */
  @Trace urlTesting: boolean = false;

  /** Current tunnel mode, used to tick the overflow menu. */
  @Trace mode: TunnelMode = TunnelMode.Rule;

  /** Mirrors `UiStore.proxyExcludeNotSelectable`. */
  @Trace excludeNotSelectable: boolean = false;

  /** Mirrors `UiStore.proxyLine`: 1, 2 or 3 members per row. */
  @Trace line: number = 2;

  /** Mirrors `UiStore.proxySort`. */
  @Trace sort: ProxySort = ProxySort.Default;

  private backend: ExternalControllerBackend | null = null;
  private ui: ProxyUiStore | null = null;

  /**
   * The last unfiltered read of `GET /proxies`. The filter and the sort are
   * applied on top of it, so changing either one re-shapes what is already on
   * screen instead of waiting for another round trip.
   */
  private raw: ProxyGroup[] = [];

  useController(store: ControllerStore): void {
    this.backend = new ExternalControllerBackend(store);
  }

  /** Adopt the persisted proxy preferences. */
  useUiStore(store: ProxyUiStore): void {
    this.ui = store;
    this.excludeNotSelectable = store.excludeNotSelectable;
    this.line = store.line;
    this.sort = store.sort;
  }

  /** Mirrors `UiStore.proxyExcludeNotSelectable` and the re-query it causes. */
  setExcludeNotSelectable(value: boolean): void {
    this.excludeNotSelectable = value;
    if (this.ui !== null) {
      this.ui.excludeNotSelectable = value;
    }
    this.reshape();
  }

  /** Mirrors `UiStore.proxyLine`. Layout only, so no re-query is needed. */
  setLine(line: number): void {
    this.line = line;
    if (this.ui !== null) {
      this.ui.line = line;
    }
  }

  /** Mirrors `UiStore.proxySort` and the re-query it causes. */
  setSort(sort: ProxySort): void {
    this.sort = sort;
    if (this.ui !== null) {
      this.ui.sort = sort;
    }
    this.reshape();
  }

  /** Mirrors the `queryOverride(Clash.OverrideSlot.Session).mode` read. */
  async loadMode(): Promise<void> {
    const backend: ExternalControllerBackend | null = this.backend;
    if (backend === null) {
      return;
    }
    const mode: TunnelMode | null = await backend.queryMode();
    if (mode !== null) {
      this.mode = mode;
      // The mode decides which groups exist at all, so the list has to be
      // re-shaped once the real mode is known.
      this.reshape();
    }
  }

  /** Mirrors ProxyDesign.Request.ReloadAll, collapsed to one request. */
  async reload(): Promise<void> {
    const backend: ExternalControllerBackend | null = this.backend;
    if (backend === null) {
      this.loading = false;
      this.lastError = 'no controller configured';
      return;
    }
    this.loading = true;
    try {
      const groups: ProxyGroup[] = await backend.listProxyGroups();
      this.raw = groups;
      this.applyGroups(this.shape(groups));
      // "controller unreachable" is for a controller that really returned
      // nothing. A filter that hides every group is a different state and
      // falls through to `proxy_empty_tips`.
      this.lastError = groups.length === 0 ? 'controller unreachable' : '';
    } catch (error) {
      this.lastError = 'controller unreachable';
    } finally {
      this.loading = false;
    }
  }

  /**
   * True when the group at `groupIndex` can be switched by hand, i.e. it is a
   * `Selector`. Android draws the member rows of every other group type with no
   * click listener at all (`ProxyView`); the page asks this before wiring the
   * tap so it can say why instead of going silent.
   */
  canSelect(groupIndex: number): boolean {
    if (groupIndex < 0 || groupIndex >= this.groups.length) {
      return false;
    }
    return this.groups[groupIndex].selectable;
  }

  /** Mirrors ProxyDesign.Request.Select: patchSelector(index, name). */
  async select(groupIndex: number, name: string): Promise<void> {
    const backend: ExternalControllerBackend | null = this.backend;
    if (backend === null || groupIndex < 0 || groupIndex >= this.groups.length) {
      return;
    }
    const group: ProxyGroup = this.groups[groupIndex];
    if (!group.selectable) {
      return;
    }
    const previous: string = group.now;
    // Optimistic: the list highlights immediately, and a failed PUT rolls back.
    group.now = name;
    // Keep the unfiltered copy in step, otherwise the next re-shape would
    // resurrect the previous selection.
    const rawGroup: ProxyGroup | undefined = this.rawGroup(group.name);
    if (rawGroup !== undefined) {
      rawGroup.now = name;
    }
    const ok: boolean = await backend.selectProxy(group.name, name);
    if (!ok) {
      group.now = previous;
      if (rawGroup !== undefined) {
        rawGroup.now = previous;
      }
      this.lastError = 'select failed';
    } else {
      this.lastError = '';
    }
  }

  get selectedGroup(): ProxyGroup | null {
    if (this.selectedIndex < 0 || this.selectedIndex >= this.groups.length) {
      return null;
    }
    return this.groups[this.selectedIndex];
  }

  /**
   * Mirrors `ProxyDesign.Request.UrlTest` + the `Reload(index)` that follows
   * it: run the group's delay test, then re-read that group so the fresh
   * numbers appear. Only the one group is replaced, so the page keeps its
   * tabs instead of dropping back to the loading spinner.
   */
  async urlTest(groupIndex: number): Promise<void> {
    const backend: ExternalControllerBackend | null = this.backend;
    if (backend === null || this.urlTesting) {
      return;
    }
    if (groupIndex < 0 || groupIndex >= this.groups.length) {
      return;
    }

    const groupName: string = this.groups[groupIndex].name;
    this.urlTesting = true;
    try {
      const ok: boolean = await backend.urlTestGroup(groupName);
      this.lastError = ok ? '' : 'delay test failed';
    } finally {
      this.urlTesting = false;
    }

    await this.refreshGroups();
  }

  /**
   * Mirrors `ProxyDesign.Request.Reload(index)`. The controller returns every
   * group in one document, so the per-group reload collapses into one read
   * followed by the same shaping the initial load applies.
   */
  private async refreshGroups(): Promise<void> {
    const backend: ExternalControllerBackend | null = this.backend;
    if (backend === null) {
      return;
    }
    try {
      this.raw = await backend.listProxyGroups();
      this.applyGroups(this.shape(this.raw));
    } catch (error) {
      // Keep the current list; the delay numbers simply stay stale.
    }
  }

  /**
   * Mirrors the shaping the native bridge does before the design ever sees a
   * group list:
   *   `QueryProxyGroupNames(excludeNotSelectable)` keeps `Selector` groups
   *   only, and `QueryProxyGroup(name, sort)` orders each group's members.
   *
   * Android runs those inside the core; the port owns its own list, so the
   * same two rules are applied here on top of the controller's response.
   */
  private shape(groups: ProxyGroup[]): ProxyGroup[] {
    // `QueryProxyGroupNames` bails out early in Direct mode: nothing is routed
    // through a proxy group, so there is no group to offer. The design then
    // falls back to its empty view.
    if (this.mode === TunnelMode.Direct) {
      return [];
    }

    const shaped: ProxyGroup[] = [];
    for (const group of groups) {
      if (group.name === GLOBAL_GROUP && this.mode !== TunnelMode.Global) {
        continue;
      }
      if (this.excludeNotSelectable && group.type !== 'Selector') {
        continue;
      }
      const copy: ProxyGroup = new ProxyGroup();
      copy.name = group.name;
      copy.type = group.type;
      copy.now = group.now;
      copy.selectable = group.selectable;
      copy.nodes = this.sortNodes(group.nodes);
      shaped.push(copy);
    }

    // The native list appends GLOBAL before the config's own groups, so it
    // leads the tab bar even when the controller returns it further down.
    if (this.mode === TunnelMode.Global) {
      for (let index = 0; index < shaped.length; index++) {
        if (shaped[index].name === GLOBAL_GROUP) {
          if (index > 0) {
            const moved: ProxyGroup[] = shaped.splice(index, 1);
            shaped.unshift(moved[0]);
          }
          break;
        }
      }
    }
    return shaped;
  }

  /**
   * Mirrors the `switch sortMode` in `QueryProxyGroup`: `Title` compares the
   * display title byte-wise, `Delay` compares the last measurement ascending,
   * and `Default` keeps the order the core returned. Nodes the core has not
   * measured sort first, matching the bridge's `Delay == 0` for those.
   */
  private sortNodes(nodes: ProxyNode[]): ProxyNode[] {
    const sorted: ProxyNode[] = nodes.slice();
    if (this.sort === ProxySort.Title) {
      sorted.sort((a: ProxyNode, b: ProxyNode) => {
        if (a.name === b.name) {
          return 0;
        }
        return a.name < b.name ? -1 : 1;
      });
    } else if (this.sort === ProxySort.Delay) {
      sorted.sort((a: ProxyNode, b: ProxyNode) => a.delay - b.delay);
    }
    return sorted;
  }

  /** Re-apply the filter and sort to the last unfiltered read. */
  private reshape(): void {
    this.applyGroups(this.shape(this.raw));
  }

  /** The unfiltered counterpart of a group, for writes that must survive a reshape. */
  private rawGroup(name: string): ProxyGroup | undefined {
    for (const group of this.raw) {
      if (group.name === name) {
        return group;
      }
    }
    return undefined;
  }

  /**
   * Store a freshly read group list.
   *
   * ArkUI's `ForEach` treats the key as the child's identity, so swapping in
   * new `ProxyGroup` instances that carry the same name leaves the rows already
   * on screen untouched. When the shape is unchanged the new values are merged
   * into the objects already on screen instead, which lets their `@Trace`
   * fields push the update out.
   */
  private applyGroups(fresh: ProxyGroup[]): void {
    const sameShape: boolean = fresh.length === this.groups.length &&
      fresh.every((group: ProxyGroup, index: number) => group.name === this.groups[index].name);

    if (sameShape) {
      for (let index = 0; index < fresh.length; index++) {
        this.mergeGroup(this.groups[index], fresh[index]);
      }
    } else {
      this.groups = fresh;
    }

    // The list can shrink under the selected tab (a filter, or a mode change
    // that drops GLOBAL); fall back to the first group when that happens.
    if (this.selectedIndex >= this.groups.length) {
      this.selectedIndex = 0;
    }
  }

  /** Copy `fresh` into `target` while keeping `target`'s identity. */
  private mergeGroup(target: ProxyGroup, fresh: ProxyGroup): void {
    target.type = fresh.type;
    target.now = fresh.now;
    target.selectable = fresh.selectable;

    const merged: ProxyNode[] = [];
    for (const node of fresh.nodes) {
      let existing: ProxyNode | undefined = undefined;
      for (const candidate of target.nodes) {
        if (candidate.name === node.name) {
          existing = candidate;
          break;
        }
      }

      if (existing === undefined) {
        merged.push(node);
      } else {
        existing.type = node.type;
        existing.delay = node.delay;
        merged.push(existing);
      }
    }

    target.nodes = merged;
  }

  /**
   * Mirrors `ProxyDesign.Request.PatchMode`: `PATCH /configs` with the chosen
   * mode. Android also offers "don't modify" (a null session override); the
   * controller has no override layer, its `mode` *is* the effective mode, so
   * that entry has no counterpart here.
   */
  async switchMode(mode: TunnelMode): Promise<void> {
    const backend: ExternalControllerBackend | null = this.backend;
    if (backend === null) {
      return;
    }
    const ok: boolean = await backend.patchMode(mode);
    if (ok) {
      this.mode = mode;
      this.lastError = '';
      // Switching to Direct empties the group list and switching to Global
      // adds the GLOBAL tab back, exactly as `QueryProxyGroupNames` would.
      this.reshape();
    } else {
      this.lastError = 'mode switch failed';
    }
  }
}
