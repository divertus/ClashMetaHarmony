/*
 * Override settings screen -- port of ClashMetaForAndroid
 * `design_settings_overide.xml` + `OverrideSettingsActivity.kt` +
 * `OverrideSettingsDesign.kt`.
 *
 * The tree itself is a table (`OverrideModels.overrideSections()`: the
 * `general` category with 17 rows and the `dns` category with 17 rows), and the
 * whole scaffold -- toolbar, categories, the four row kinds and their editors,
 * the reset confirm -- is `view/PreferenceScreen.ets`, which this page shares
 * with `MetaFeatureSettingsPage`.
 *
 * What is left here is the part that is genuinely this page's: owning the
 * persisted record and handing the controller-mappable subset of it to the
 * running core on the way out.
 *
 * Android's `defer { withClash { patchOverride(Persist, configuration) } }`
 * writes the whole `ConfigurationOverride` into the core's persist slot and
 * lets the native side apply it when the core starts. The port has no
 * in-process core, so the override goes to the *running* core over the external
 * controller instead, and only the fields `PATCH /configs` carries can make the
 * trip (`OverrideModels.overridePatchBody` lists them). Those rows are stored
 * and displayed but reach nothing, which the row comments and the status doc
 * both say.
 */

import { router } from '@kit.ArkUI';
import { PreferenceSection, overridePatchBody, overrideSections } from '../model/OverrideModels';
import {
  OverrideStore,
  loadOverrideStore,
  overrideClear,
  overrideLoad,
  overrideSave
} from '../backend/OverrideStore';
import { loadControllerStore } from '../backend/ControllerStore';
import { ExternalControllerBackend } from '../backend/ExternalControllerBackend';
import { PreferenceScreen } from '../view/PreferenceScreen';
import { showToast } from '../util/Platform';

@Entry
@ComponentV2
struct OverrideSettingsPage {
  @Local store: OverrideStore = loadOverrideStore();

  /** The override record; absent keys are "do not modify". */
  @Local data: Record<string, string> = {};

  /** The two categories; built once, they never change. */
  private sections: PreferenceSection[] = [];

  private backend: ExternalControllerBackend | null = null;

  /** The override as it was when the screen opened, for the dirty check. */
  private initialEncoded: string = '{}';

  /** Set while leaving on purpose, so `onBackPress` lets the pop through. */
  private leaving: boolean = false;

  aboutToAppear(): void {
    this.sections = overrideSections();
    this.data = overrideLoad(this.store);
    this.initialEncoded = JSON.stringify(this.data);
    this.backend = new ExternalControllerBackend(loadControllerStore());
  }

  /**
   * The tail of `OverrideSettingsActivity.main()`: persist the record, and
   * forward the subset the controller understands -- but only when this visit
   * changed something. Android's patch is a write to a local service, while
   * this one reconfigures a core that is already running.
   */
  private commit(): void {
    overrideSave(this.store, this.data);

    const body: string = overridePatchBody(this.data);
    const backend: ExternalControllerBackend | null = this.backend;
    if (body === '{}' || backend === null) {
      return;
    }
    backend.patchConfigs(body).then((applied: boolean) => {
      if (!applied) {
        showToast($r('app.string.override_apply_failed'));
      }
    });
  }

  /** Whether anything changed since the screen was opened. */
  private dirty(): boolean {
    return JSON.stringify(this.data) !== this.initialEncoded;
  }

  /** The toolbar arrow; `router.back()` does not go through `onBackPress`. */
  private requestBack(): void {
    if (this.dirty()) {
      this.commit();
    }
    this.leaving = true;
    router.back();
  }

  /** Mirrors the `defer` block on the system back gesture. */
  onBackPress(): boolean {
    if (this.leaving) {
      return false;
    }
    if (this.dirty()) {
      this.commit();
    }
    this.leaving = true;
    return false;
  }

  /** The confirmed half of `Request.ResetOverride`: clear, then `finish()`. */
  private clearAndLeave(): void {
    overrideClear(this.store);
    this.data = {};
    this.leaving = true;
    router.back();
  }

  build() {
    // An `@Entry` page's `build` must have a single container as its root, and
    // a custom component does not count -- hence the wrapping `Column`.
    Column() {
      PreferenceScreen({
        pageTitle: $r('app.string.override'),
        sections: this.sections,
        data: this.data,
        onDataChange: (data: Record<string, string>) => {
          this.data = data;
        },
        onClear: () => {
          this.clearAndLeave();
        },
        onBack: () => {
          this.requestBack();
        }
      })
    }
    .width('100%')
    .height('100%')
  }
}
