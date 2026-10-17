/*
 * The access-control preferences Android keeps in `ServiceStore` / `UiStore`,
 * plus the clipboard import/export the access-control overflow menu offers.
 *
 * Android structure:
 *   ServiceStore.accessControlMode       (NetworkSettingsDesign row)
 *   UiStore.accessControlSystemApp       (AccessControlMenu "System Apps")
 *   UiStore.accessControlSort            (AccessControlMenu sort group)
 *   UiStore.accessControlReverse         (AccessControlMenu "Reverse")
 *   ClipboardManager import/export       (AccessControlActivity requests)
 *
 * HarmonyOS mapping:
 *   SharedPreferences -> PersistenceV2, one `@Trace` field per store class and
 *   no methods, the shape `ProfileStore` documents.
 *     AccessControlModeStore  one enum-valued field, like `UiStore.darkMode`.
 *     AccessControlUiStore    one JSON string, like `ProfileStore.encoded`,
 *                             because three values would need three classes
 *                             otherwise.
 *   ClipboardManager -> `pasteboard`
 *
 * The clipboard split is not symmetric, and the asymmetry is a platform fact:
 *
 *   Writing needs nothing -- `SystemPasteboard.setDataSync` is permission-free,
 *   so "Export to Clipboard" behaves exactly as on Android.
 *
 *   Reading needs `ohos.permission.READ_PASTEBOARD`, which the local SDK's
 *   `toolchains/lib/PermissionDefinitions.json` marks
 *   `availableLevel: system_basic`, `grantMode: user_grant`: a normal
 *   third-party app can neither hold it nor be granted it at runtime. So
 *   `readClipboardText` reports the denial and the page falls back to a paste
 *   dialog -- the user pasting into a `TextArea` is a user-initiated pasteboard
 *   read and needs no permission.
 *
 *   ACTION NEEDED (out of this change's write scope): declaring
 *   `ohos.permission.READ_PASTEBOARD` in `module.json5` would not help; the
 *   level is system_basic. The paste dialog is the supported path.
 */

import { PersistenceV2 } from '@kit.ArkUI';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { AccessControlMode } from '../model/NetworkSettingsModels';
import { AccessControlSort, AccessControlUi } from '../model/AccessControlModels';

@ObservedV2
export class AccessControlModeStore {
  static readonly KEY: string = 'ClashAccessControlModeStore';

  /** `ServiceStore.accessControlMode`, default `AcceptAll`. */
  @Trace mode: AccessControlMode = AccessControlMode.AcceptAll;
}

/** Load the persisted access-control mode, or create the default one. */
export function loadAccessControlModeStore(): AccessControlModeStore {
  const store: AccessControlModeStore | undefined = PersistenceV2.connect(
    AccessControlModeStore, AccessControlModeStore.KEY, () => new AccessControlModeStore());
  return store ?? new AccessControlModeStore();
}

@ObservedV2
export class AccessControlUiStore {
  static readonly KEY: string = 'ClashAccessControlUiStore';

  /** Serialized `AccessControlUi`; the store's only state. */
  @Trace encoded: string = '';
}

/** Load the persisted list preferences, or create the default ones. */
export function loadAccessControlUiStore(): AccessControlUiStore {
  const store: AccessControlUiStore | undefined = PersistenceV2.connect(
    AccessControlUiStore, AccessControlUiStore.KEY, () => new AccessControlUiStore());
  return store ?? new AccessControlUiStore();
}

/** `UiStore` defaults: system apps hidden, sorted by label, not reversed. */
function defaultUi(): AccessControlUi {
  return { showSystem: false, sort: AccessControlSort.Label, reverse: false };
}

/**
 * Decode the persisted blob. A missing or corrupt value reads as the Android
 * defaults, so a first run and a damaged store behave the same way.
 */
export function accessControlUi(store: AccessControlUiStore): AccessControlUi {
  if (store.encoded.length === 0) {
    return defaultUi();
  }
  try {
    const parsed: AccessControlUi = JSON.parse(store.encoded) as AccessControlUi;
    const ui: AccessControlUi = defaultUi();
    ui.showSystem = parsed.showSystem === true;
    ui.reverse = parsed.reverse === true;
    if (parsed.sort === AccessControlSort.PackageName ||
      parsed.sort === AccessControlSort.InstallTime ||
      parsed.sort === AccessControlSort.UpdateTime ||
      parsed.sort === AccessControlSort.Label) {
      ui.sort = parsed.sort;
    }
    return ui;
  } catch (error) {
    return defaultUi();
  }
}

/** Persist one preference; the other two keep whatever they already had. */
export function saveAccessControlUi(
  store: AccessControlUiStore, showSystem: boolean, sort: AccessControlSort, reverse: boolean): void {
  const ui: AccessControlUi = { showSystem: showSystem, sort: sort, reverse: reverse };
  store.encoded = JSON.stringify(ui);
}

/**
 * The outcome of a programmatic clipboard read.
 *
 * `permissionDenied` is the expected answer for a normal app (see the file
 * header), so the page shows the paste dialog instead of an error.
 */
export class ClipboardRead {
  text: string = '';
  ok: boolean = false;
  permissionDenied: boolean = false;
}

/** `ClipboardManager.primaryClip.getItemAt(0).text`, when the platform allows it. */
export function readClipboardText(): ClipboardRead {
  const result: ClipboardRead = new ClipboardRead();
  try {
    const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
    if (!board.hasDataSync()) {
      result.ok = true;
      return result;
    }
    result.text = board.getDataSync().getPrimaryText();
    result.ok = true;
    return result;
  } catch (error) {
    const failure: BusinessError = error as BusinessError;
    result.permissionDenied = failure.code === 201;
    return result;
  }
}

/**
 * `ClipData.newPlainText("packages", selected.joinToString("\n"))`.
 *
 * Returns false when the platform rejected the write; the caller reports that
 * as `not_ported` rather than claiming success.
 */
export function writeClipboardText(text: string): boolean {
  try {
    const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
    board.setDataSync(pasteboard.createPlainTextData(text));
    return true;
  } catch (error) {
    return false;
  }
}
