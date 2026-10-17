/*
 * Profile editor -- port of ClashMetaForAndroid `design_properties.xml` +
 * `component_action_text_field.xml` + `PropertiesActivity.kt` +
 * `PropertiesDesign.kt`.
 *
 * Android structure:
 *   CoordinatorLayout
 *   +- ObservableScrollView
 *      +- LinearLayout(vertical, paddingTop = insets.top + toolbar_height)
 *         +- tips row (ic_outline_info + tips_properties)
 *         +- ActionTextField name
 *         +- ActionTextField url       (disabled for Type.File)
 *         +- ActionTextField age key
 *         +- ActionTextField interval  (disabled for Type.File)
 *         +- ActionLabel    browse files -> FilesActivity
 *   +- ActivityBarLayout
 *      +- common_activity_bar (back + title)
 *      +- progress / save
 *
 * `PropertiesDesign` keeps a working copy and only writes it back on
 * `Request.Commit`, so the page holds the four edited values separately and
 * diffs them against the stored record to decide whether to warn on exit.
 *
 * Deviations:
 *   - `requestModelTextInput` is a Material `AlertDialog` with one text field.
 *     ArkUI's `promptAction` dialogs cannot host an input, so the same dialog is
 *     drawn in-page as a scrim + card.
 *   - `Request.BrowseFiles` opens `FilesActivity`, which is not ported.
 *   - `verifyAndCommit` on Android runs `withProfile { commit(uuid) }`, which
 *     fetches the profile and reloads the core. The fetch is ported
 *     (`ProfileFetch.applyProfile` downloads `config.yaml`), the core reload is
 *     not -- there is no core to hand the text to yet.
 *   - `ValidatorAgeSecretKey` calls `Clash.veritySecretKeys` (JNI). The port has
 *     no age implementation, so any value is accepted; the field is stored as-is.
 *   - the Android `ModelProgressBar` dialog is replaced by an inline row under
 *     the toolbar: `promptAction` has no modal progress dialog, and a
 *     `bindContentCover` would swallow the tap that starts the fetch.
 *
 * Implementation notes:
 *   - the four rows are `ActionTextField` components, not `@Builder` methods: a
 *     `@Builder` whose parameters are passed by value is not re-executed when
 *     the parent's state changes, so the row would keep showing whatever value
 *     it was first built with;
 *   - a gesture attached *inside* a `@Builder` body does not fire either, which
 *     is why the dark-mode row and the profile-provider rows are wrapped;
 *   - `bindContentCover` hosts the two dialogs. Putting them in a `Stack` above
 *     the page, or in `.overlay()`, made every gesture inside the `Scroll` stop
 *     firing while the toolbar kept working.
 */

import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { Profile, ProfileType, PropertiesRequest } from '../model/ProfileModels';
import {
  ProfileStore,
  loadProfileStore,
  profileByUUID,
  profileCommit,
  profilePatch
} from '../backend/ProfileStore';
import {
  applyProfile,
  ProfileFetchResult,
  ProfileFetchStatus,
  sourceHost
} from '../backend/ProfileFetch';
import { ActionLabel } from '../view/ActionLabel';
import { ActionTextField } from '../view/ActionTextField';
import { PreferenceTips } from '../view/PreferenceTips';
import { showToast } from '../util/Platform';

/** Which field the in-page text dialog is editing; -1 when it is closed. */
enum PropertyField {
  None = -1,
  Name = 0,
  Url = 1,
  AgeKey = 2,
  Interval = 3
}

interface PropertiesParams {
  uuid?: string;
}

@Entry
@ComponentV2
struct PropertiesPage {
  @Local store: ProfileStore = loadProfileStore();
  @Local profile: Profile | undefined = undefined;

  // ---- the working copy (`PropertiesDesign.profile`) ----
  @Local name: string = '';
  @Local source: string = '';
  @Local ageKey: string = '';
  /** `Profile.interval` in minutes, as the dialog edits it. */
  @Local intervalMinutes: number = 0;

  // ---- in-page replacement for `requestModelTextInput` ----
  @Local editing: PropertyField = PropertyField.None;
  @Local draft: string = '';
  @Local error: ResourceStr = '';

  /** Set when the "Exit without Save" dialog is on screen. */
  @Local confirmingExit: boolean = false;
  /** Set while leaving on purpose, so `onBackPress` lets the pop through. */
  private leaving: boolean = false;

  /**
   * Set while `applyProfile` is downloading. Android's `processing` flag does
   * the same job: it swaps the save button for a spinner and makes back a no-op.
   */
  @Local fetching: boolean = false;
  /** `url.Host` of the source being fetched, for `format_fetching_configuration`. */
  @Local fetchingHost: string = '';

  aboutToAppear(): void {
    const params: object | undefined = router.getParams();
    this.uuidFromParams(params);
  }

  private uuidFromParams(params: object | undefined): void {
    const uuid: string | undefined =
      params === undefined ? undefined : (params as PropertiesParams).uuid;
    if (uuid === undefined) {
      // Mirrors `intent.uuid ?: return finish()`.
      router.back();
      return;
    }

    const profile: Profile | undefined = profileByUUID(this.store, uuid);
    if (profile === undefined) {
      router.back();
      return;
    }

    this.profile = profile;
    this.name = profile.name;
    this.source = profile.source;
    this.ageKey = profile.ageSecretKey;
    this.intervalMinutes = Math.floor(profile.interval / 60000);
  }

  /** Mirrors `Event.ActivityStop`'s `profile != original` check. */
  private isDirty(): boolean {
    const profile: Profile | undefined = this.profile;
    if (profile === undefined) {
      return false;
    }
    return this.name !== profile.name
      || this.source !== profile.source
      || this.ageKey !== profile.ageSecretKey
      || this.intervalMinutes !== Math.floor(profile.interval / 60000);
  }

  /** Mirrors `PropertiesActivity.onBackPressed`. */
  onBackPress(): boolean {
    // Android ignores back while the progress dialog is up (`if (!progressing)`).
    if (this.fetching) {
      return true;
    }
    if (this.leaving || this.editing !== PropertyField.None) {
      return false;
    }
    if (!this.isDirty()) {
      return false;
    }

    // `requestExitWithoutSaving()` -- MaterialAlertDialog, drawn in-page.
    this.confirmingExit = true;
    return true;
  }

  /**
   * The toolbar arrow runs the same check as `onBackPress`: `router.back()` does
   * **not** go through `onBackPress`, so calling it directly would drop the
   * unsaved-changes prompt.
   */
  private requestBack(): void {
    if (this.fetching) {
      return;
    }
    if (this.leaving || this.editing !== PropertyField.None) {
      return;
    }
    if (!this.isDirty()) {
      this.leaving = true;
      router.back();
      return;
    }
    this.confirmingExit = true;
  }

  private fieldTitle(field: PropertyField): Resource {
    if (field === PropertyField.Url) {
      return $r('app.string.url');
    }
    if (field === PropertyField.AgeKey) {
      return $r('app.string.age_secret_key');
    }
    if (field === PropertyField.Interval) {
      return $r('app.string.auto_update');
    }
    return $r('app.string.name');
  }

  private fieldHint(field: PropertyField): Resource {
    if (field === PropertyField.Url) {
      return $r('app.string.profile_url');
    }
    if (field === PropertyField.AgeKey) {
      return $r('app.string.age_secret_key_hint');
    }
    if (field === PropertyField.Interval) {
      return $r('app.string.auto_update_minutes');
    }
    return $r('app.string.properties');
  }

  /** Mirrors `PropertiesDesign.inputX()`'s `initial` argument. */
  private openField(field: PropertyField): void {
    this.error = '';
    if (field === PropertyField.Url) {
      this.draft = this.source;
    } else if (field === PropertyField.AgeKey) {
      this.draft = this.ageKey;
    } else if (field === PropertyField.Interval) {
      this.draft = this.intervalMinutes === 0 ? '' : `${this.intervalMinutes}`;
    } else {
      this.draft = this.name;
    }
    this.editing = field;
  }

  /**
   * Mirrors `Validator.kt`'s four validators, minus `ValidatorAgeSecretKey`
   * (that one is a JNI call).
   */
  private acceptDraft(): void {
    if (this.editing === PropertyField.Name) {
      if (this.draft.trim() === '') {
        this.error = $r('app.string.should_not_be_blank');
        return;
      }
      this.name = this.draft;
    } else if (this.editing === PropertyField.Url) {
      const lower: string = this.draft.toLowerCase();
      if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
        this.error = $r('app.string.accept_http_content');
        return;
      }
      this.source = this.draft;
    } else if (this.editing === PropertyField.AgeKey) {
      this.ageKey = this.draft;
    } else if (this.editing === PropertyField.Interval) {
      // `ValidatorAutoUpdateInterval`: empty or at least 15 minutes.
      const minutes: number = this.draft === '' ? 0 : Number.parseInt(this.draft, 10);
      if (this.draft !== '' && (Number.isNaN(minutes) || minutes < 15)) {
        this.error = $r('app.string.at_least_15_minutes');
        return;
      }
      this.intervalMinutes = this.draft === '' ? 0 : minutes;
    }

    this.editing = PropertyField.None;
  }

  /**
   * Mirrors `PropertiesDesign.requestCommit` -> `PropertiesActivity.verifyAndCommit()`:
   * validate, patch the record, then fetch before leaving. A failure keeps the
   * editor open on the pending record, exactly as Android does.
   */
  private async commit(): Promise<void> {
    const profile: Profile | undefined = this.profile;
    if (profile === undefined || this.fetching) {
      return;
    }
    if (this.name.trim() === '') {
      showToast($r('app.string.empty_name'));
      return;
    }
    if (profile.type !== ProfileType.File && this.source.trim() === '') {
      showToast($r('app.string.invalid_url'));
      return;
    }

    profilePatch(this.store, profile.uuid, this.name, this.source,
      this.intervalMinutes * 60000, this.ageKey);

    // A `File` profile is local, so `commit` is the whole operation: Android's
    // `fetchAndValid` finds `config.yaml` present and skips the network.
    if (profile.type === ProfileType.File) {
      profileCommit(this.store, profile.uuid);
      this.leave();
      return;
    }

    this.fetching = true;
    this.fetchingHost = sourceHost(this.source);
    const result: ProfileFetchResult =
      await applyProfile(getContext(this), this.store, profile.uuid);
    this.fetching = false;

    if (result.status === ProfileFetchStatus.Ok) {
      this.leave();
      return;
    }

    // Android reports this with `showExceptionToast`; the profile list already
    // has a localized string for the same fetch failure, so it is reused here.
    showToast($r('app.string.toast_profile_updated_failed', this.name, result.message));
  }

  /** `setResult(RESULT_OK)` + `finish()`; `leaving` lets `onBackPress` pass. */
  private leave(): void {
    this.leaving = true;
    router.back();
  }

  /** `component_action_text_field.xml`: caption / value / underline + edit icon. */
  /** `app:enabled="@{profile.type != Type.File}"` -- URL and interval rows. */
  private editable(): boolean {
    const profile: Profile | undefined = this.profile;
    return profile !== undefined && profile.type !== ProfileType.File;
  }

  /** `app:text="@{profile.interval == 0 ? disabled : format_minutes(...)}"`. */
  private intervalText(): string {
    const manager: resourceManager.ResourceManager = getContext(this).resourceManager;
    if (this.intervalMinutes === 0) {
      return manager.getStringSync($r('app.string.disabled').id);
    }
    return manager.getStringSync($r('app.string.format_minutes').id, this.intervalMinutes);
  }

  /** The in-page stand-in for `requestModelTextInput`. */
  @Builder
  textInputDialog() {
    Column() {
      Column() {
        Text(this.fieldTitle(this.editing))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .width('100%')
          .textAlign(TextAlign.Start)

        TextInput({ text: this.draft, placeholder: this.fieldHint(this.editing) })
          .width('100%')
          .height(44)
          .margin({ top: 16 })
          .onChange((value: string) => {
            this.draft = value;
          })

        if (this.error !== '') {
          Text(this.error)
            .fontSize(12)
            .fontColor($r('app.color.color_error'))
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: 4 })
        }

        Row() {
          Button($r('app.string.cancel'))
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .fontColor($r('app.color.color_control_normal'))
            .backgroundColor($r('app.color.color_surface'))
            .onClick(() => {
              this.editing = PropertyField.None;
            })

          Button($r('app.string.ok'))
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .margin({ left: 8 })
            .onClick(() => {
              this.acceptDraft();
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

  /** `requestExitWithoutSaving()`, drawn in-page. */
  @Builder
  exitDialog() {
    Column() {
      Column() {
        Text($r('app.string.exit_without_save'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text($r('app.string.exit_without_save_warning'))
          .fontSize(15)
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ top: 12 })

        Row() {
          Button($r('app.string.cancel'))
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .fontColor($r('app.color.color_control_normal'))
            .backgroundColor($r('app.color.color_surface'))
            .onClick(() => {
              this.confirmingExit = false;
            })

          Button($r('app.string.ok'))
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .margin({ left: 8 })
            .onClick(() => {
              this.confirmingExit = false;
              this.leaving = true;
              router.back();
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

  /**
   * What `.overlay()` draws on top of the page. Both dialogs share one overlay
   * slot, and at most one of them is ever active.
   */
  @Builder
  overlayContent() {
    if (this.editing !== PropertyField.None) {
      this.textInputDialog()
    }

    if (this.confirmingExit) {
      this.exitDialog()
    }
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

          // `android:label="@string/profile"` on PropertiesActivity.
          Text($r('app.string.profile'))
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
            .margin({ left: $r('app.float.item_text_margin') })

          // `binding.processing` on Android hides the save button and shows a
          // spinner in its place; the same slot is used here.
          if (this.fetching) {
            LoadingProgress()
              .width($r('app.float.item_tailing_component_size'))
              .height($r('app.float.item_tailing_component_size'))
              .color($r('app.color.color_control_normal'))
          } else {
            Image($r('app.media.ic_baseline_save'))
              .width($r('app.float.item_tailing_component_size'))
              .height($r('app.float.item_tailing_component_size'))
              .objectFit(ImageFit.Contain)
              .fillColor($r('app.color.color_control_normal'))
              .onClick(() => {
                this.commit();
              })
          }
        }
        .width('100%')
        .height($r('app.float.toolbar_height'))
        .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      // Stands in for the `ModelProgressBar` dialog Android shows around the
      // fetch. Its text comes from the same `format_fetching_configuration`
      // resource the dialog used.
      if (this.fetching) {
        Text($r('app.string.format_fetching_configuration', this.fetchingHost))
          .fontSize(14)
          .fontColor($r('app.color.color_control_normal'))
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          .textAlign(TextAlign.Start)
      }

      Scroll() {
          Column() {
            PreferenceTips({
              raw: getContext(this).resourceManager
                .getStringSync($r('app.string.tips_properties').id)
            })

            // Each element carries `layout_marginVertical =
            // properties_element_margin_vertical`.
            ActionTextField({
              title: $r('app.string.name'),
              value: this.name,
              placeholder: $r('app.string.properties'),
              icon: $r('app.media.ic_outline_label'),
              onAction: () => {
                this.openField(PropertyField.Name);
              }
            })
              .margin({
                top: $r('app.float.properties_element_margin_vertical'),
                bottom: $r('app.float.properties_element_margin_vertical')
              })

            // `app:enabled="@{profile.type != Type.File}"`.
            ActionTextField({
              title: $r('app.string.url'),
              value: this.source,
              placeholder: $r('app.string.accept_http_content'),
              icon: $r('app.media.ic_outline_inbox'),
              rowEnabled: this.editable(),
              onAction: () => {
                this.openField(PropertyField.Url);
              }
            })
              .margin({
                top: $r('app.float.properties_element_margin_vertical'),
                bottom: $r('app.float.properties_element_margin_vertical')
              })

            ActionTextField({
              title: $r('app.string.age_secret_key'),
              value: this.ageKey,
              placeholder: $r('app.string.age_secret_key_hint'),
              icon: $r('app.media.ic_baseline_key'),
              onAction: () => {
                this.openField(PropertyField.AgeKey);
              }
            })
              .margin({
                top: $r('app.float.properties_element_margin_vertical'),
                bottom: $r('app.float.properties_element_margin_vertical')
              })

            ActionTextField({
              title: $r('app.string.auto_update'),
              value: this.intervalText(),
              placeholder: $r('app.string.at_least_15_minutes'),
              icon: $r('app.media.ic_outline_update'),
              rowEnabled: this.editable(),
              onAction: () => {
                this.openField(PropertyField.Interval);
              }
            })
              .margin({
                top: $r('app.float.properties_element_margin_vertical'),
                bottom: $r('app.float.properties_element_margin_vertical')
              })

            ActionLabel({
              text: $r('app.string.browse_files'),
              subtext: $r('app.string.browse_configuration_providers'),
              icon: $r('app.media.ic_outline_folder'),
              onAction: () => {
                // Mirrors Request.BrowseFiles -> FilesActivity.
                const profile: Profile | undefined = this.profile;
                if (profile !== undefined) {
                  router.pushUrl({
                    url: 'pages/FilesPage',
                    params: { uuid: profile.uuid }
                  });
                }
              }
            })
              .margin({
                top: $r('app.float.properties_element_margin_vertical'),
                bottom: $r('app.float.properties_element_margin_vertical')
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.color_background'))
    // The dialogs are a `bindContentCover` modal rather than `Stack` children or
    // `.overlay()`: both of those put a full-size sibling above the `Scroll` and
    // every gesture inside the list stopped firing (the toolbar kept working).
    // A content cover is presented over the page instead of inside it.
    .bindContentCover(
      this.editing !== PropertyField.None || this.confirmingExit,
      this.overlayContent(),
      { modalTransition: ModalTransition.NONE }
    )
  }
}
