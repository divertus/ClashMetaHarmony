/*
 * Dynamic desktop shortcut pinning through AppGallery Kit.
 *
 * Android's ShortcutManager can publish shortcuts directly. HarmonyOS does not
 * expose that API to ordinary apps, but AppGallery Kit's productViewManager
 * can request that a static shortcut already declared by the app be pinned to
 * the launcher. This is the supported equivalent: the shortcut definition is
 * still static, while the "add to desktop" action is dynamic and user-driven.
 */

import { common, Want } from '@kit.AbilityKit';
import { productViewManager } from '@kit.AppGalleryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { showToast } from '../util/Platform';

const SHORTCUT_ID: string = 'clash_toggle';
const LABEL_RESOURCE: string = 'shortcut_toggle_short';
const ICON_RESOURCE: string = 'ic_baseline_swap_vert';

/** Ask AppGallery to pin the existing "toggle Clash" shortcut. */
export function pinClashToggleShortcut(context: common.UIAbilityContext): void {
  const want: Want = {
    bundleName: 'com.example.clashmeta',
    moduleName: 'entry',
    abilityName: 'EntryAbility',
    parameters: {
      clashAction: 'toggle'
    }
  };

  try {
    productViewManager.checkPinShortcutPermitted(
      context,
      SHORTCUT_ID,
      want,
      LABEL_RESOURCE,
      ICON_RESOURCE
    ).then((result: productViewManager.CheckShortcutResult) => {
      const tid: string = result.tid ?? '';
      if (tid.length === 0) {
        showToast($r('app.string.shortcut_pin_failed'));
        return;
      }
      productViewManager.requestNewPinShortcut(context, tid).then(() => {
        showToast($r('app.string.shortcut_pin_success'));
      }).catch((error: BusinessError) => {
        showToast($r('app.string.shortcut_pin_failed'));
      });
    }).catch((error: BusinessError) => {
      showToast($r('app.string.shortcut_pin_failed'));
    });
  } catch (error) {
    showToast($r('app.string.shortcut_pin_failed'));
  }
}
