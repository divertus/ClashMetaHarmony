/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { vpnExtension } from '@kit.NetworkKit';
import { ExternalControl } from '../backend/ExternalControl';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private externalControl: ExternalControl | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    try {
      this.externalControl = new ExternalControl(this.context);
      this.externalControl.handleWant(want);
      this.maybeStartVpnDebug(want);
    } catch (error) {
      hilog.error(DOMAIN, 'testTag', 'Failed to handle external control Want. Cause: %{public}s',
        JSON.stringify(error));
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      this.activateExternalControl();
    });
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onNewWant');
    try {
      const externalControl: ExternalControl | null = this.externalControl;
      if (externalControl !== null) {
        externalControl.handleWant(want);
      }
    } catch (error) {
      hilog.error(DOMAIN, 'testTag', 'Failed to handle external control Want. Cause: %{public}s',
        JSON.stringify(error));
    }
  }

  private activateExternalControl(): void {
    try {
      const externalControl: ExternalControl | null = this.externalControl;
      if (externalControl !== null) {
        externalControl.setReady();
      }
    } catch (error) {
      hilog.error(DOMAIN, 'testTag', 'Failed to activate external control. Cause: %{public}s',
        JSON.stringify(error));
    }
  }

  /**
   * Temporary hook for the VPN experiment.
   *
   * `hdc shell aa start -a EntryAbility -b com.example.clashmeta --ps vpnDebug 1`
   * asks the system to start `ClashVpnExtension`, which creates an inert TUN and
   * logs its descriptor. This exists so the VPN path can be exercised before
   * there is a core to pump the interface; the real start/stop path belongs on
   * the main screen once the data plane exists.
   */
  private maybeStartVpnDebug(want: Want): void {
    try {
      const parameters: Record<string, Object> | undefined = want.parameters;
      if (parameters === undefined || parameters['vpnDebug'] !== '1') {
        return;
      }
      const target: Want = {
        bundleName: 'com.example.clashmeta',
        abilityName: 'ClashVpnExtension',
        parameters: {
          vpnRoutes: '1'
        }
      };
      vpnExtension.startVpnExtensionAbility(target).then(() => {
        hilog.info(DOMAIN, 'testTag', '%{public}s', 'VPN extension start requested');
      }).catch((error: Object) => {
        hilog.error(DOMAIN, 'testTag', 'VPN extension start failed: %{public}s',
          JSON.stringify(error));
      });
    } catch (error) {
      hilog.error(DOMAIN, 'testTag', 'VPN debug hook failed: %{public}s', JSON.stringify(error));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
