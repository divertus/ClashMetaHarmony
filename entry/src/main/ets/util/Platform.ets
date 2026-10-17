/*
 * Small platform helpers shared by the settings-style screens.
 *
 * These replace the Android idioms the designs rely on:
 *   startActivity(Intent(ACTION_VIEW).setData(uri))  -> openInBrowser()
 *   showToast(...)                                   -> showToast()
 */

import { common, Want } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * Hand `url` to whatever app resolves a browsable view intent.
 *
 * Android used `Intent.ACTION_VIEW`; the HarmonyOS equivalent is an implicit
 * Want with `ohos.want.action.viewData` plus the browsable entity, which the
 * system browser declares.
 */
export function openInBrowser(context: common.UIAbilityContext, url: string): void {
  const want: Want = {
    action: 'ohos.want.action.viewData',
    entities: ['entity.system.browsable'],
    uri: url
  };

  context.startAbility(want).catch((error: BusinessError) => {
    showToast(error.message);
  });
}

/** Short toast, mirroring `Design.showToast`. */
export function showToast(message: ResourceStr): void {
  promptAction.showToast({ message: message, duration: 2000 });
}
