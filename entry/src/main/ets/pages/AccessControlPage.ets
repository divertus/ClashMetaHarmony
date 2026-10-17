/*
 * Access-control screen -- port of ClashMetaForAndroid
 * `AccessControlActivity.kt` + `AccessControlDesign.kt` + `design_access_control.xml`
 * + `adapter_app.xml` + `menu_access_control.xml`.
 *
 * Android structure:
 *   CoordinatorLayout
 *   +- common_recycler_list (one `AppAdapter` row per installed app)
 *   +- ActivityBarLayout
 *      +- common_activity_bar (back + title)
 *      +- search_view (opens the full-screen keyword dialog)
 *      +- menu_view (overflow: Select All/None/Invert, Filter>System Apps,
 *         Sort>Name/Package/Install/Update + Reverse, External>Import/Export)
 *
 * Each app row (`adapter_app.xml`, minHeight item_min_height):
 *   [ app icon 30dp, marginHorizontal item_header_margin ]
 *   [ vertical: label (Body1) / packageName (Body2) ]
 *   [ MaterialCheckBox, clickable=false; the whole row toggles selection ]
 *
 * HarmonyOS mapping:
 *   RecyclerView -> List + ForEach
 *   PackageManager -> `backend/InstalledApps.ets`
 *   Set<String> -> `AccessControlStore.encoded`
 *   UiStore access-control keys -> `AccessControlUiStore` (same three values)
 *   ClipboardManager -> `pasteboard`, with the asymmetry documented below
 *   Android search dialog -> an inline toolbar Search field; it applies the
 *   same label/packageName contains filter without an extra modal layer.
 *
 * ## The package list cannot be enumerated, so it is entered instead
 *
 * `AccessControlActivity` builds its rows from `PackageManager
 * .getInstalledPackages`. The HarmonyOS replacement
 * (`bundleManager.getInstalledBundleList`) requires
 * `ohos.permission.ENTERPRISE_GET_INSTALLED_BUNDLE_LIST`, which the local SDK
 * marks `availableLevel: system_basic` -- a normal app can never hold it, and
 * no other public API enumerates bundles. `backend/InstalledApps.ets` proves
 * this out in its header and reports the denial instead of hiding it.
 *
 * So this page keeps Android's layout and every Android interaction, but the
 * row source has two halves:
 *
 *   - whatever the platform did return (on a privileged build), and
 *   - the selected package names themselves, which are always rendered.
 *
 * The second half is what makes the screen usable today: the user adds package
 * names with the toolbar "+", or imports a newline-separated list with
 * "Import from Clipboard". A name the device can resolve
 * (`ohos.permission.GET_BUNDLE_INFO`, `availableLevel: normal`) gets its real
 * label and icon; one it cannot stays as a single dimmed package-name line,
 * which is honest about what is known rather than inventing a label.
 *
 * `access_control_packages_summary`'s row in NetworkSettingsPage is the entry
 * point, as on Android; the mode that decides whether the set means "only
 * these" or "all but these" is the `access_control_mode` row there.
 *
 * ## Clipboard
 *
 * Export is exact: `SystemPasteboard.setDataSync` needs no permission.
 * Import is not: reading the pasteboard needs `READ_PASTEBOARD`
 * (`system_basic`), so the port tries the read and falls back to a paste dialog
 * when the platform refuses -- pasting into a `TextArea` is a user-initiated
 * read and needs no permission. That is a deviation from Android's silent
 * clipboard read, and the only honest one available.
 *
 * Blocked:
 *   There is no Android VpnService or in-process service here, so the
 *   `stopClashService()` / `startClashService()` restart after a changed
 *   selection is reported as `not_ported`.
 */

import { router } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import { AccessControlApp, AccessControlSort, AccessControlUi } from '../model/AccessControlModels';
import {
  AccessControlStore,
  InstalledAppQuery,
  accessControlPackageList,
  accessControlReplaceAll,
  accessControlSetEnabled,
  loadAccessControlStore,
  looksLikePackageName,
  parsePackageList,
  queryInstalledApps,
  resolvePackages,
  scanInstalledApps,
  clearInstalledAppScanCache
} from '../backend/InstalledApps';
import {
  AccessControlUiStore,
  ClipboardRead,
  loadAccessControlUiStore,
  accessControlUi,
  readClipboardText,
  saveAccessControlUi,
  writeClipboardText
} from '../backend/AccessControlPrefs';
import { showToast } from '../util/Platform';

/** The label a row prints: `AppInfo.label`, or the package name when unknown. */
function displayLabel(app: AccessControlApp): string {
  return (app.label.length > 0 ? app.label : app.packageName).toLowerCase();
}

function compareStrings(left: string, right: string): number {
  if (left < right) {
    return -1;
  }
  if (left > right) {
    return 1;
  }
  return 0;
}

function compareNumbers(left: number, right: number): number {
  if (left < right) {
    return -1;
  }
  if (left > right) {
    return 1;
  }
  return 0;
}

@Entry
@ComponentV2
struct AccessControlPage {
  @Local store: AccessControlStore = loadAccessControlStore();
  @Local uiStore: AccessControlUiStore = loadAccessControlUiStore();

  /** Rows the platform returned; empty when the enumeration was denied. */
  @Local apps: AccessControlApp[] = [];

  /** Sorted snapshot of `accessControlPackages(store)` for rendering. */
  @Local selected: string[] = [];

  /** `UiStore.accessControlSystemApp`, inverted for readability. */
  @Local showSystem: boolean = false;

  /** `UiStore.accessControlSort` / `accessControlReverse`. */
  @Local sort: AccessControlSort = AccessControlSort.Label;
  @Local reverse: boolean = false;

  /** Mirrors the keyword dialog's query. */
  @Local query: string = '';

  @Local loading: boolean = true;

  /**
   * True while the uid scan is walking the application band. The scan is ~2k
   * synchronous bundle lookups split into chunks, so the page can show where it
   * is instead of appearing frozen.
   */
  @Local scanning: boolean = false;
  @Local scanProgress: string = '';

  /** True when the rows came from the uid scan rather than the platform list. */
  @Local scanned: boolean = false;

  /**
   * True when the platform refused the bundle list, i.e. when the manual and
   * clipboard paths are the only ways to fill the list. Drives the notice above
   * the list; the list itself renders either way.
   */
  @Local enumerationUnavailable: boolean = false;

  // ---- add / import dialog ----
  @Local adding: boolean = false;
  @Local addText: string = '';
  /** True when the dialog was opened by "Import from Clipboard". */
  @Local importing: boolean = false;

  /** Sorted selection at entry, used to detect a real change on exit. */
  private initialEncoded: string = '[]';

  /** The service restart is only meaningful after an actual set change. */
  private changed: boolean = false;

  /** Avoid reporting the same missing service twice on one exit. */
  private restartReported: boolean = false;

  aboutToAppear(): void {
    try {
      this.selected = accessControlPackageList(this.store);
      this.initialEncoded = JSON.stringify(this.selected);

      const ui: AccessControlUi = accessControlUi(this.uiStore);
      this.showSystem = ui.showSystem;
      this.sort = ui.sort;
      this.reverse = ui.reverse;

      this.loadApps();
    } catch (error) {
      // `aboutToAppear` must never throw: an uncaught error here kills the app.
      this.apps = [];
      this.loading = false;
    }
  }

  aboutToDisappear(): void {
    this.reportRestartIfNeeded();
  }

  /**
   * `PackageManager.getInstalledPackages`. `queryInstalledApps` never rejects,
   * but the synchronous context lookup can, so the page stays alive either way.
   */
  private loadApps(): void {
    try {
      const selfBundleName: string = getContext(this).applicationInfo.name;
      // Both the platform list and the uid scan are refused to a normally
      // signed app (see InstalledApps.ets), so this normally returns
      // `enumerated: false` and the page shows the manual/import notice. The
      // scan stays reachable from the overflow menu so it can be tried, and so
      // it starts working the day the app is signed with a privileged profile.
      queryInstalledApps(selfBundleName)
        .then((result: InstalledAppQuery) => {
          this.apps = result.apps;
          this.enumerationUnavailable = !result.enumerated;
          this.scanned = result.scanned;
          this.loading = false;
        })
        .catch(() => {
          this.apps = [];
          this.enumerationUnavailable = true;
          this.loading = false;
        });
    } catch (error) {
      this.apps = [];
      this.enumerationUnavailable = true;
      this.loading = false;
    }
  }

  /**
   * Overflow menu: "Scan installed apps". Drops the cached uid scan and walks
   * the band again, so a package installed after the page first opened shows up
   * without restarting the app.
   */
  private rescan(): void {
    if (this.scanning) {
      return;
    }
    this.scanning = true;
    this.scanProgress = '';
    clearInstalledAppScanCache();
    try {
      const selfBundleName: string = getContext(this).applicationInfo.name;
      scanInstalledApps(selfBundleName, (scanned: number, total: number) => {
        this.scanProgress = `${scanned}/${total}`;
      })
        .then((result: InstalledAppQuery) => {
          this.apps = result.apps;
          this.enumerationUnavailable = !result.enumerated;
          this.scanned = result.scanned;
          this.scanning = false;
          this.scanProgress = '';
          if (result.apps.length === 0) {
            // The uid walk is refused on a normal signature; say which
            // permission the platform asked for instead of silently doing
            // nothing.
            showToast($r('app.string.access_control_scan_denied'));
          }
        })
        .catch(() => {
          this.scanning = false;
          this.scanProgress = '';
          showToast($r('app.string.access_control_scan_denied'));
        });
    } catch (error) {
      this.scanning = false;
      this.scanProgress = '';
      showToast($r('app.string.access_control_scan_denied'));
    }
  }

  private isSelected(packageName: string): boolean {
    return this.selected.includes(packageName);
  }

  private refreshSelection(): void {
    this.selected = accessControlPackageList(this.store);
    this.changed = JSON.stringify(this.selected) !== this.initialEncoded;
  }

  private toggle(packageName: string): void {
    accessControlSetEnabled(this.store, packageName, !this.isSelected(packageName));
    this.refreshSelection();
  }

  /**
   * The tail of `AccessControlActivity`'s `defer`: it stops and restarts the
   * running Clash service after a changed package set. There is no service to
   * restart in this port.
   */
  private reportRestartIfNeeded(): void {
    if (!this.changed || this.restartReported) {
      return;
    }
    this.restartReported = true;
    showToast($r('app.string.not_ported'));
  }

  /** `router.back()` does not run `onBackPress`, so both paths use this. */
  private requestBack(): void {
    this.reportRestartIfNeeded();
    router.back();
  }

  onBackPress(): boolean {
    this.reportRestartIfNeeded();
    return false;
  }

  /**
   * The rows the list shows, in Android's order.
   *
   * Android's adapter holds `design.apps` -- what `loadApps` returned -- and
   * the selection is only a `Set<String>` painted onto those rows. Here the
   * selected names are rows in their own right, because a name the user typed
   * or imported has no `AppInfo` behind it. A name that *is* in `apps` stays a
   * single row: it is looked up by package name and skipped below.
   */
  private rows(): AccessControlApp[] {
    const keyword: string = this.query.trim().toLowerCase();
    const result: AccessControlApp[] = [];
    const known: Set<string> = new Set<string>();

    for (const app of this.apps) {
      known.add(app.packageName);
      if (!this.showSystem && app.systemApp) {
        continue;
      }
      if (keyword.length > 0 &&
        !app.label.toLowerCase().includes(keyword) &&
        !app.packageName.toLowerCase().includes(keyword)) {
        continue;
      }
      result.push(app);
    }

    for (const packageName of this.selected) {
      if (known.has(packageName)) {
        continue;
      }
      if (keyword.length > 0 && !packageName.toLowerCase().includes(keyword)) {
        continue;
      }
      const app: AccessControlApp = new AccessControlApp();
      app.packageName = packageName;
      app.label = '';
      app.resolved = false;
      result.push(app);
    }

    result.sort((left: AccessControlApp, right: AccessControlApp): number => {
      return this.compareRows(left, right);
    });
    return result;
  }

  /**
   * `AccessControlActivity.loadApps`'s comparator:
   *   `compareByDescending { it.packageName in selected }` then the sort key,
   *   with `reverse` flipping the sort key only -- the selected-first grouping
   *   stays descending in both branches.
   */
  private compareRows(left: AccessControlApp, right: AccessControlApp): number {
    const leftSelected: boolean = this.isSelected(left.packageName);
    const rightSelected: boolean = this.isSelected(right.packageName);
    if (leftSelected !== rightSelected) {
      return leftSelected ? -1 : 1;
    }

    let order: number = 0;
    if (this.sort === AccessControlSort.PackageName) {
      order = compareStrings(left.packageName.toLowerCase(), right.packageName.toLowerCase());
    } else if (this.sort === AccessControlSort.InstallTime) {
      order = compareNumbers(left.installTime, right.installTime);
    } else if (this.sort === AccessControlSort.UpdateTime) {
      order = compareNumbers(left.updateTime, right.updateTime);
    } else {
      order = compareStrings(displayLabel(left), displayLabel(right));
    }
    if (order !== 0) {
      return this.reverse ? -order : order;
    }

    // Equal sort keys (every unresolved row shares installTime 0) need a
    // tiebreaker, otherwise the list order would depend on insertion order.
    return compareStrings(left.packageName, right.packageName);
  }

  /**
   * The row key carries every rendered value. `ForEach` only re-runs its item
   * generator when the key changes, so selection must be part of the key for
   * the Switch to follow a tap.
   */
  private rowKey(app: AccessControlApp): string {
    return `${app.packageName}|${app.label}|${app.resolved}|${app.systemApp}|` +
      `${this.isSelected(app.packageName)}`;
  }

  // ---- overflow menu (menu_access_control.xml) ----

  private markActive(label: string, active: boolean): string {
    return active ? `${label} \u2713` : label;
  }

  /**
   * `AccessControlMenu`. Android nests Filter / Sort / External as submenus;
   * `bindMenu` takes a flat `MenuElement[]`, so the twelve entries are one list
   * and the checkmark carries the state that the submenus would have shown.
   */
  private menuItems(): MenuElement[] {
    const manager: resourceManager.ResourceManager = getContext(this).resourceManager;
    const selectAll: string = manager.getStringSync($r('app.string.select_all').id);
    const selectNone: string = manager.getStringSync($r('app.string.select_none').id);
    const selectInvert: string = manager.getStringSync($r('app.string.select_invert').id);
    const systemApps: string = manager.getStringSync($r('app.string.system_apps').id);
    const name: string = manager.getStringSync($r('app.string.name').id);
    const packageName: string = manager.getStringSync($r('app.string.package_name').id);
    const installTime: string = manager.getStringSync($r('app.string.install_time').id);
    const updateTime: string = manager.getStringSync($r('app.string.update_time').id);
    const reverse: string = manager.getStringSync($r('app.string.reverse').id);
    const importFrom: string = manager.getStringSync($r('app.string.import_from_clipboard').id);
    const exportTo: string = manager.getStringSync($r('app.string.export_to_clipboard').id);
    const scanApps: string = manager.getStringSync($r('app.string.access_control_scan_apps').id);

    return [
      {
        value: selectAll,
        action: () => {
          this.selectAll();
        }
      },
      {
        value: selectNone,
        action: () => {
          this.selectNone();
        }
      },
      {
        value: selectInvert,
        action: () => {
          this.selectInvert();
        }
      },
      {
        value: this.markActive(systemApps, this.showSystem),
        action: () => {
          this.setShowSystem(!this.showSystem);
        }
      },
      {
        value: this.markActive(name, this.sort === AccessControlSort.Label),
        action: () => {
          this.setSort(AccessControlSort.Label);
        }
      },
      {
        value: this.markActive(packageName, this.sort === AccessControlSort.PackageName),
        action: () => {
          this.setSort(AccessControlSort.PackageName);
        }
      },
      {
        value: this.markActive(installTime, this.sort === AccessControlSort.InstallTime),
        action: () => {
          this.setSort(AccessControlSort.InstallTime);
        }
      },
      {
        value: this.markActive(updateTime, this.sort === AccessControlSort.UpdateTime),
        action: () => {
          this.setSort(AccessControlSort.UpdateTime);
        }
      },
      {
        value: this.markActive(reverse, this.reverse),
        action: () => {
          this.setReverse(!this.reverse);
        }
      },
      {
        value: importFrom,
        action: () => {
          this.requestImport();
        }
      },
      {
        value: exportTo,
        action: () => {
          this.requestExport();
        }
      },
      {
        value: scanApps,
        action: () => {
          this.rescan();
        }
      }
    ];
  }

  /**
   * `Request.SelectAll`. Android maps `design.apps`; the port maps the rows the
   * list is actually showing, because the search field lives in the toolbar
   * here instead of in its own dialog -- "select all" then means "all shown".
   */
  private selectAll(): void {
    const packages: string[] = [];
    for (const app of this.rows()) {
      packages.push(app.packageName);
    }
    for (const packageName of this.selected) {
      if (!packages.includes(packageName)) {
        packages.push(packageName);
      }
    }
    accessControlReplaceAll(this.store, packages);
    this.refreshSelection();
  }

  /** `Request.SelectNone`: `selected.clear()`. */
  private selectNone(): void {
    accessControlReplaceAll(this.store, []);
    this.refreshSelection();
  }

  /**
   * `Request.SelectInvert`. Android computes
   * `design.apps.map { it.packageName }.toSet() - selected`; the port inverts
   * the visible rows for the reason `selectAll` gives.
   */
  private selectInvert(): void {
    const packages: string[] = [];
    for (const app of this.rows()) {
      if (!this.isSelected(app.packageName)) {
        packages.push(app.packageName);
      }
    }
    for (const packageName of this.selected) {
      if (!packages.includes(packageName)) {
        packages.push(packageName);
      }
    }
    accessControlReplaceAll(this.store, packages);
    this.refreshSelection();
  }

  private setShowSystem(value: boolean): void {
    this.showSystem = value;
    this.persistUi();
  }

  private setSort(value: AccessControlSort): void {
    this.sort = value;
    this.persistUi();
  }

  private setReverse(value: boolean): void {
    this.reverse = value;
    this.persistUi();
  }

  private persistUi(): void {
    saveAccessControlUi(this.uiStore, this.showSystem, this.sort, this.reverse);
  }

  // ---- add / import / export ----

  /** The toolbar "+": a package name, or a newline-separated batch. */
  private openAdd(): void {
    this.addText = '';
    this.importing = false;
    this.adding = true;
  }

  /**
   * `Request.Import`. Android reads the clipboard and intersects the lines with
   * the installed apps; the port cannot read the clipboard (`READ_PASTEBOARD`
   * is `system_basic`) and cannot enumerate apps, so it reads when it can and
   * otherwise hands the paste to the user.
   */
  private requestImport(): void {
    const read: ClipboardRead = readClipboardText();
    if (read.ok) {
      this.applyImport(read.text);
      return;
    }

    this.addText = '';
    this.importing = true;
    this.adding = true;
  }

  /** `Request.Export`: `selected.joinToString("\n")` onto the clipboard. */
  private requestExport(): void {
    if (!writeClipboardText(this.selected.join('\n'))) {
      showToast($r('app.string.not_ported'));
      return;
    }
    showToast($r('app.string.copied'));
  }

  /**
   * `selected.clear(); selected.addAll(...)`. Android intersects with the
   * installed apps first; that filter is impossible here, so every line is
   * kept and `resolvePackages` marks the ones this device does not know.
   */
  private applyImport(text: string): void {
    const names: string[] = parsePackageList(text);
    accessControlReplaceAll(this.store, names);
    this.refreshSelection();
    this.resolveAdded(names);
  }

  /** The "+" dialog's confirm: union with the current selection. */
  private confirmAdd(): void {
    const names: string[] = parsePackageList(this.addText);
    if (names.length === 0) {
      showToast($r('app.string.access_control_nothing_entered'));
      return;
    }

    if (this.importing) {
      // "Import from Clipboard" replaces, like Android's Request.Import.
      accessControlReplaceAll(this.store, names);
    } else {
      const packages: string[] = [];
      for (const packageName of this.selected) {
        packages.push(packageName);
      }
      for (const packageName of names) {
        if (!packages.includes(packageName)) {
          packages.push(packageName);
        }
      }
      accessControlReplaceAll(this.store, packages);
    }

    this.refreshSelection();
    this.adding = false;
    this.addText = '';
    this.resolveAdded(names);
  }

  /**
   * Give the newly entered names real labels and icons where the platform
   * allows it (`ohos.permission.GET_BUNDLE_INFO`). Anything that does not
   * resolve is already rendered from `selected`, so a failure here costs
   * nothing.
   */
  private resolveAdded(names: string[]): void {
    const candidates: string[] = [];
    for (const packageName of names) {
      if (looksLikePackageName(packageName)) {
        candidates.push(packageName);
      }
    }
    if (candidates.length === 0) {
      return;
    }

    resolvePackages(candidates)
      .then((resolved: AccessControlApp[]) => {
        const merged: AccessControlApp[] = [];
        for (const app of this.apps) {
          merged.push(app);
        }
        for (const app of resolved) {
          if (!app.resolved) {
            continue;
          }
          let exists: boolean = false;
          for (const known of merged) {
            if (known.packageName === app.packageName) {
              exists = true;
            }
          }
          if (!exists) {
            merged.push(app);
          }
        }
        merged.sort((left: AccessControlApp, right: AccessControlApp): number => {
          return compareStrings(displayLabel(left), displayLabel(right));
        });
        this.apps = merged;
      })
      .catch(() => {
        // An unresolved row is already on screen; nothing to recover.
      });
  }

  @Builder
  addDialog() {
    Column() {
      Column() {
        Text($r('app.string.access_control_add_package'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .width('100%')
          .textAlign(TextAlign.Start)

        if (this.importing) {
          Text($r('app.string.access_control_clipboard_read_denied'))
            .fontSize(12)
            .fontColor($r('app.color.color_error'))
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: 8 })
        }

        TextArea({
          text: this.addText,
          placeholder: $r('app.string.access_control_package_name_hint')
        })
          .width('100%')
          .height(120)
          .margin({ top: 16 })
          .onChange((value: string) => {
            this.addText = value;
          })

        Row() {
          Button($r('app.string.cancel'))
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .fontColor($r('app.color.color_control_normal'))
            .backgroundColor($r('app.color.color_surface'))
            .onClick(() => {
              this.adding = false;
              this.addText = '';
            })

          Button($r('app.string.ok'))
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .margin({ left: 8 })
            .onClick(() => {
              this.confirmAdd();
            })
        }
        .width('100%')
        .margin({ top: 20 })
      }
      .width('85%')
      .padding(20)
      .backgroundColor($r('app.color.color_surface'))
      .borderRadius(8)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#80000000')
  }

  build() {
    Column() {
      // ---- navigation bar (ActivityBarLayout + common_activity_bar) ----
      Row() {
        Image($r('app.media.ic_baseline_arrow_back'))
          .width($r('app.float.item_tailing_component_size'))
          .height($r('app.float.item_tailing_component_size'))
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.color_control_normal'))
          .onClick(() => {
            this.requestBack();
          })

        // `android:label="@string/access_control_packages"` on the activity.
        Text($r('app.string.access_control_packages'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: $r('app.float.item_text_margin') })

        // `dialog_search.xml`'s keyword field, kept inline so the list gesture
        // surface has no sibling overlay above it.
        Search({ value: this.query, placeholder: $r('app.string.keyword') })
          .width(120)
          .height(40)
          .backgroundColor($r('app.color.color_surface'))
          .onChange((value: string) => {
            this.query = value;
          })

        // No Android counterpart: the "+" that replaces PackageManager.
        Image($r('app.media.ic_baseline_add'))
          .width($r('app.float.item_tailing_component_size'))
          .height($r('app.float.item_tailing_component_size'))
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.color_control_normal'))
          .margin({ left: $r('app.float.item_tailing_margin') })
          .onClick(() => {
            this.openAdd();
          })

        Image($r('app.media.ic_baseline_more_vert'))
          .width($r('app.float.item_tailing_component_size'))
          .height($r('app.float.item_tailing_component_size'))
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.color_control_normal'))
          .margin({ left: $r('app.float.item_tailing_margin') })
          .bindMenu(this.menuItems())
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      // The one thing Android has no reason to say. Shown instead of the list
      // being silently empty, and it names the two ways to fill it.
      if (this.enumerationUnavailable && !this.loading) {
        Text($r('app.string.access_control_enumeration_unavailable'))
          .fontSize(12)
          .opacity(0.7)
          .width('100%')
          .textAlign(TextAlign.Start)
          .padding({
            left: $r('app.float.item_header_margin'),
            right: $r('app.float.item_tailing_margin'),
            top: $r('app.float.item_text_margin'),
            bottom: $r('app.float.item_text_margin')
          })
      }

      if (this.loading || this.scanning) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)

          if (this.scanning) {
            Text($r('app.string.access_control_scanning'))
              .fontSize(12)
              .opacity(0.7)
              .margin({ top: 8 })

            Text(this.scanProgress)
              .fontSize(12)
              .opacity(0.7)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.rows().length === 0) {
        // Android renders an empty RecyclerView here. The port uses the
        // imported `empty` string so an empty list is still legible.
        Column() {
          Text($r('app.string.empty'))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .opacity(0.6)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.rows(), (app: AccessControlApp) => {
            ListItem() {
              Row() {
                Image(app.icon)
                  .width($r('app.float.item_header_component_size'))
                  .height($r('app.float.item_header_component_size'))
                  .objectFit(ImageFit.Contain)
                  .margin({
                    left: $r('app.float.item_header_margin'),
                    right: $r('app.float.item_header_margin')
                  })

                if (app.resolved) {
                  Column() {
                    Text(app.label)
                      .fontSize(16)
                      .width('100%')
                      .textAlign(TextAlign.Start)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    Text(app.packageName)
                      .fontSize(14)
                      .opacity(0.6)
                      .width('100%')
                      .textAlign(TextAlign.Start)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: $r('app.float.item_text_margin') })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                } else {
                  // A name the platform would not resolve: one line, no
                  // invented label, and dimmed so it reads as "not confirmed".
                  Text(app.packageName)
                    .fontSize(16)
                    .opacity(0.6)
                    .layoutWeight(1)
                    .textAlign(TextAlign.Start)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }

                // `adapter_app.xml` uses a non-clickable MaterialCheckBox and
                // puts the gesture on the row; the ArkUI equivalent is a Switch
                // that does not participate in hit testing.
                Toggle({ type: ToggleType.Switch, isOn: this.isSelected(app.packageName) })
                  .selectedColor($r('app.color.color_primary'))
                  .hitTestBehavior(HitTestMode.None)
                  .margin({ right: $r('app.float.item_tailing_margin') })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .constraintSize({ minHeight: $r('app.float.item_min_height') })
              .padding({ right: $r('app.float.item_tailing_margin') })
              .onClick(() => {
                this.toggle(app.packageName);
              })
            }
          }, (app: AccessControlApp) => this.rowKey(app))
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.color_background'))
    // The add/paste dialog is a `bindContentCover` modal rather than a `Stack`
    // child or `.overlay()`: both of those put a full-size sibling above the
    // list and every gesture inside it stopped firing.
    .bindContentCover(
      this.adding,
      this.addDialog(),
      { modalTransition: ModalTransition.NONE }
    )
  }
}
