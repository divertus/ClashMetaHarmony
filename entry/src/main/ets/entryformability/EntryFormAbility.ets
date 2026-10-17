/*
 * Service-card provider for the Clash tunnel.
 *
 * Android's TileService is not available to third-party apps on HarmonyOS.
 * The supported replacement is a service card: this FormExtensionAbility
 * receives the card's message events and performs the same local tunnel
 * actions as `ExternalControl`.
 *
 * The card cannot call the UI-side `ExternalControl` directly because
 * `ExternalControl` owns UI toasts and a UIAbility context. The start/stop
 * payload is therefore rebuilt here from the same stores and sent to
 * `ClashVpnExtension` with `@ohos.net.vpnExtension`. The card's status comes
 * from the cross-process marker maintained by `VpnRuntime`.
 */

import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { vpnExtension } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Profile } from '../model/ProfileModels';
import { loadProfileStore, profileActive } from '../backend/ProfileStore';
import { vpnTunnelParameters } from '../backend/VpnSettingsStore';
import { isVpnRunning } from '../backend/VpnRuntime';

const DOMAIN: number = 0x0000;
const COMMAND_START: string = 'clash:start';
const COMMAND_STOP: string = 'clash:stop';
const COMMAND_TOGGLE: string = 'clash:toggle';

interface FormCardData {
  running: string;
  statusText: string;
  profileText: string;
}

function logError(message: string, error: Object): void {
  hilog.error(DOMAIN, 'testTag', '%{public}s: %{public}s', message, JSON.stringify(error));
}

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    return this.createFormData();
  }

  onUpdateForm(formId: string): void {
    this.updateForm(formId);
  }

  onFormEvent(formId: string, message: string): void {
    const command: string = message.trim().toLowerCase();
    hilog.info(DOMAIN, 'testTag', 'form event: formId=%{public}s command=%{public}s', formId, command);

    if (command === COMMAND_START) {
      this.startTunnel(formId);
      return;
    }
    if (command === COMMAND_STOP) {
      this.stopTunnel(formId);
      return;
    }
    if (command === COMMAND_TOGGLE) {
      this.toggleTunnel(formId);
      return;
    }
  }

  onRemoveForm(formId: string): void {
    // No card-owned resources to release.
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  private createFormData(): formBindingData.FormBindingData {
    let running: boolean = false;
    try {
      running = isVpnRunning(this.context);
    } catch (error) {
      // The marker is advisory; a card can still be rendered when it is absent.
    }

    let profileName: string = '';
    try {
      const profile: Profile | undefined = profileActive(loadProfileStore());
      if (profile !== undefined) {
        profileName = profile.name;
      }
    } catch (error) {
      // The active profile is display data only.
    }

    const data: FormCardData = {
      running: running ? 'true' : 'false',
      statusText: this.resolveString(running ? $r('app.string.running') : $r('app.string.stopped')),
      profileText: profileName.length > 0
        ? profileName
        : this.resolveString($r('app.string.not_selected'))
    };
    return formBindingData.createFormBindingData(data);
  }

  private resolveString(resource: Resource): string {
    try {
      return this.context.resourceManager.getStringSync(resource.id);
    } catch (error) {
      return '';
    }
  }

  private updateForm(formId: string): void {
    formProvider.updateForm(formId, this.createFormData()).catch((error: BusinessError) => {
      logError('form update failed', error);
    });
  }

  private startTunnel(formId: string): void {
    try {
      const profile: Profile | undefined = profileActive(loadProfileStore());
      if (profile === undefined) {
        this.updateForm(formId);
        return;
      }

      const parameters: Record<string, Object> = vpnTunnelParameters();
      parameters['profileUuid'] = profile.uuid;
      parameters['profileSource'] = profile.source;
      parameters['ageSecretKey'] = profile.ageSecretKey;

      const want: Want = {
        bundleName: 'com.example.clashmeta',
        abilityName: 'ClashVpnExtension',
        parameters: parameters
      };
      vpnExtension.startVpnExtensionAbility(want).then(() => {
        this.updateForm(formId);
      }).catch((error: BusinessError) => {
        logError('form startVpnExtensionAbility failed', error);
        this.updateForm(formId);
      });
    } catch (error) {
      logError('form start failed', error);
      this.updateForm(formId);
    }
  }

  private stopTunnel(formId: string): void {
    vpnExtension.stopVpnExtensionAbility({
      bundleName: 'com.example.clashmeta',
      abilityName: 'ClashVpnExtension'
    }).then(() => {
      // `onDestroy` removes the marker asynchronously; refresh after it lands.
      this.updateForm(formId);
      setTimeout(() => {
        this.updateForm(formId);
      }, 1000);
    }).catch((error: BusinessError) => {
      logError('form stopVpnExtensionAbility failed', error);
      this.updateForm(formId);
    });
  }

  private toggleTunnel(formId: string): void {
    let running: boolean = false;
    try {
      running = isVpnRunning(this.context);
    } catch (error) {
      // Treat an unreadable marker as stopped.
    }
    if (running) {
      this.stopTunnel(formId);
    } else {
      this.startTunnel(formId);
    }
  }
}
