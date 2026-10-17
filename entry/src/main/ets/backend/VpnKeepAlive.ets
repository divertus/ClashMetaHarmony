/*
 * Keep the UIAbility process alive while the VPN extension is running.
 *
 * HarmonyOS documents one important lifecycle rule for third-party VPNs: the
 * system stops the VPN when the process that called
 * `startVpnExtensionAbility()` exits. The VpnExtensionAbility itself is a
 * separate process, so the caller has to stay alive as well.
 *
 * A continuous task is the supported way to keep a UIAbility process out of
 * the background-freeze path. `dataTransfer` is the closest public mode for a
 * tunnel that continuously moves network data; the notification it publishes
 * is also the user-visible "VPN is running" signal the platform guide asks
 * VPN clients to provide.
 */

import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'VpnKeepAlive';
const BACKGROUND_MODES: string[] = ['dataTransfer'];
const BUNDLE_NAME: string = 'com.example.clashmeta';
const ENTRY_ABILITY: string = 'EntryAbility';

/** -1 means no continuous task has been started by this process. */
let continuousTaskId: number = -1;
let listenersRegistered: boolean = false;

function registerListeners(): void {
  if (listenersRegistered) {
    return;
  }
  listenersRegistered = true;
  try {
    backgroundTaskManager.on('continuousTaskCancel',
      (info: backgroundTaskManager.ContinuousTaskCancelInfo) => {
        hilog.warn(DOMAIN, TAG, 'keep-alive canceled id=%{public}d reason=%{public}d',
          info.id, info.reason);
      });
    backgroundTaskManager.on('continuousTaskSuspend',
      (info: backgroundTaskManager.ContinuousTaskSuspendInfo) => {
        hilog.warn(DOMAIN, TAG, 'keep-alive suspended id=%{public}d reason=%{public}d',
          info.continuousTaskId, info.suspendReason);
      });
  } catch (error) {
    hilog.error(DOMAIN, TAG, 'continuous task listener registration failed: %{public}s',
      JSON.stringify(error));
  }
}

/** Start the caller-side keep-alive task once. */
export function startVpnKeepAlive(context: common.UIAbilityContext): void {
  registerListeners();
  if (continuousTaskId >= 0) {
    return;
  }

  const info: wantAgent.WantAgentInfo = {
    wants: [
      {
        bundleName: BUNDLE_NAME,
        abilityName: ENTRY_ABILITY
      }
    ],
    actionType: wantAgent.OperationType.START_ABILITY,
    requestCode: 0,
    actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
  };

  wantAgent.getWantAgent(info).then((agent: WantAgent) => {
    backgroundTaskManager.startBackgroundRunning(context, BACKGROUND_MODES, agent)
      .then((notification: backgroundTaskManager.ContinuousTaskNotification) => {
        const taskId: number = notification.continuousTaskId ?? -1;
        continuousTaskId = taskId;
        hilog.info(DOMAIN, TAG, 'keep-alive started id=%{public}d',
          taskId);
      })
      .catch((error: Object) => {
        hilog.error(DOMAIN, TAG, 'startBackgroundRunning failed: %{public}s',
          JSON.stringify(error));
      });
  }).catch((error: Object) => {
    hilog.error(DOMAIN, TAG, 'getWantAgent failed: %{public}s', JSON.stringify(error));
  });
}

/** Stop the keep-alive task; "not started" is harmless. */
export function stopVpnKeepAlive(context: common.UIAbilityContext): void {
  continuousTaskId = -1;
  backgroundTaskManager.stopBackgroundRunning(context).then(() => {
    hilog.info(DOMAIN, TAG, '%{public}s', 'keep-alive stopped');
  }).catch((error: Object) => {
    hilog.error(DOMAIN, TAG, 'stopBackgroundRunning failed: %{public}s',
      JSON.stringify(error));
  });
}
