/*
 * "Is the tunnel up?" -- the question Android answers with
 * `StatusClient(this).currentProfile()`.
 *
 * HarmonyOS has no public API that reports whether *this* app's
 * `VpnExtensionAbility` is currently running: `@ohos.net.vpnExtension` exposes
 * `createVpnConnection()` (extension side) and
 * `startVpnExtensionAbility()` / `stopVpnExtensionAbility()` (UI side), and its
 * `VpnObserver` only reports the user's answer to the trust dialog. There is no
 * `isRunning()`.
 *
 * So the extension publishes the fact itself: `ClashVpnExtension` writes a
 * marker file once the core has taken over the TUN fd, and removes it in
 * `onDestroy`. A file rather than `PersistenceV2`, because the extension runs
 * in its own process (`com.example.clashmeta:vpn`) and `PersistenceV2` caches
 * per process -- the UI process would keep reading its own stale copy.
 *
 * Known limit, kept honest here rather than hidden: a force-stop kills the
 * extension process without `onDestroy`, so the marker can outlive the tunnel.
 * The toggle shortcut therefore treats "marker present" as a hint, and the
 * start path stays idempotent (`startVpnExtensionAbility` on a running
 * extension is an error the caller already tolerates).
 */

import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';

const MARKER_NAME: string = 'vpn.running';

function markerPath(context: common.Context): string {
  return `${context.filesDir}/${MARKER_NAME}`;
}

/** Called by `ClashVpnExtension` after the core owns the TUN descriptor. */
export function markVpnRunning(context: common.Context, running: boolean): void {
  const path: string = markerPath(context);
  try {
    if (running) {
      const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      fs.closeSync(file);
      return;
    }
    fs.unlinkSync(path);
  } catch (error) {
    // The marker is advisory. A failure to write or remove it must never take
    // down the tunnel or the caller.
  }
}

/** `true` while the extension has published a running tunnel. */
export function isVpnRunning(context: common.Context): boolean {
  try {
    fs.accessSync(markerPath(context));
    return true;
  } catch (error) {
    return false;
  }
}
