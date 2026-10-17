/*
 * Profiles screen -- port of ClashMetaForAndroid `design_profiles.xml` +
 * `adapter_profile.xml` + `ProfilesActivity.kt` + `ProfilesDesign.kt`.
 *
 * Android structure:
 *   CoordinatorLayout
 *   +- common_recycler_list (profile cards)
 *   +- ActivityBarLayout
 *      +- common_activity_bar (back + title)
 *      +- update_view  (GONE unless some profile is `imported && type != File`)
 *      +- add_view
 *
 * Card (`adapter_profile.xml`): margin 5dp vertical / item_header_margin
 * horizontal, `bg_b` surface with an 8dp radius, elevation 5dp, then
 * [ RadioButton 30dp | name + type | elapsed | 2dp divider | more-vert ].
 *
 * Deviations from Android, all because the native core / platform is missing:
 *   - `Request.Update` and `Request.UpdateAll` fetch the subscription over HTTP
 *     and hand the result to the core. The fetch is ported
 *     (`ProfileFetch.applyProfile` rewrites `config.yaml`); the core reload is
 *     not, so only the download half of the Android flow happens.
 *   - `Request.ShareQrCode` renders the profile URL with ArkUI's built-in
 *     `QRCode` component. Android builds a ZXing bitmap and puts it in a
 *     `MaterialAlertDialog`; the port keeps the same dialog shape with a
 *     `bindContentCover` modal and the native component.
 *   - `Request.Active` on a *pending* profile shows an "unsaved" toast with an
 *     Edit action button. `promptAction` toasts have no action slot, so the
 *     port shows the same text without the button (the row menu still has Edit).
 *   - Android draws the per-profile menu in an `AppBottomSheetDialog` of
 *     `LargeActionLabel` rows; `bindMenu` is used here for the same reason the
 *     proxy overflow menu uses it (`MenuElement[]` cannot nest or set colours,
 *     so the Delete row is not tinted with the error colour).
 *   - `upload` / `download` / `total` / `expire` (the subscription usage block
 *     and its progress bar) come from the profile provider's HTTP headers, which
 *     only `ProfileProcessor` produces. Those views stay hidden, which is what
 *     Android renders for a profile that has never been fetched.
 */

import { router } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import { Profile, ProfileType, ProfilesRequest } from '../model/ProfileModels';
import {
  ProfileStore,
  loadProfileStore,
  profileActive,
  profileAll,
  profileClone,
  profileRemove,
  profileSetActive
} from '../backend/ProfileStore';
import { applyProfile, ProfileFetchResult, ProfileFetchStatus } from '../backend/ProfileFetch';
import { elapsedIntervalString } from '../model/ProviderModels';
import { showToast } from '../util/Platform';

@Entry
@ComponentV2
struct ProfilesPage {
  @Local store: ProfileStore = loadProfileStore();
  @Local now: number = Date.now();

  /**
   * Mirrors `ProfilesDesign.updatingAll` / `changeUpdateAllButtonStatus`: the
   * toolbar button becomes a spinner, and a second tap is ignored.
   */
  @Local updating: boolean = false;

  /** The URL shown by the Share QR code dialog; empty when it is closed. */
  @Local shareSource: string = '';
  @Local shareName: string = '';
  @Local sharingQr: boolean = false;

  /**
   * `ProfilesActivity` runs a one-minute ticker while the activity is started
   * so the elapsed labels stay current.
   */
  private ticker: number = -1;

  aboutToAppear(): void {
    this.ticker = setInterval(() => {
      this.now = Date.now();
    }, 60000);
  }

  aboutToDisappear(): void {
    if (this.ticker >= 0) {
      clearInterval(this.ticker);
      this.ticker = -1;
    }
  }

  /** Mirrors `patchProfiles()`'s `updatable` check for the toolbar icon. */
  private canUpdateAll(): boolean {
    return profileAll(this.store).some((profile: Profile) =>
      profile.imported && profile.type !== ProfileType.File);
  }

  /**
   * The list rows are keyed by content, not just `uuid`. `profileAll()` decodes
   * fresh `Profile` objects from the store's string, so a row whose name or type
   * changed would otherwise be reused with its old contents.
   */
  private rowKey(profile: Profile): string {
    return `${profile.uuid}|${profile.name}|${profile.type}|${profile.active}`
      + `|${profile.pending}|${profile.updatedAt}`;
  }

  /** Mirrors `I18nKt.toString(profile.type, context)`. */
  private typeText(profile: Profile): ResourceStr {
    if (profile.pending) {
      return $r('app.string.format_type_unsaved', this.typeWord(profile));
    }
    return this.typeWord(profile);
  }

  private typeWord(profile: Profile): ResourceStr {
    if (profile.type === ProfileType.Url) {
      return $r('app.string.url');
    }
    if (profile.type === ProfileType.External) {
      return $r('app.string.external');
    }
    return $r('app.string.file');
  }

  /** Mirrors `elapsedIntervalString(currentTime - profile.updatedAt)`. */
  private elapsedLabel(profile: Profile): ResourceStr {
    return elapsedIntervalString(this.now - profile.updatedAt);
  }

  /**
   * Mirrors `dialog_profiles_menu.xml`. The two conditional rows keep Android's
   * `visibility` expressions rather than always rendering.
   */
  private itemMenu(profile: Profile): MenuElement[] {
    const manager: resourceManager.ResourceManager = getContext(this).resourceManager;
    const items: MenuElement[] = [];

    if (profile.imported && profile.type !== ProfileType.File) {
      items.push({
        value: manager.getStringSync($r('app.string.update').id),
        action: () => {
          this.request(ProfilesRequest.Update, profile);
        }
      });
    }

    items.push({
      value: manager.getStringSync($r('app.string.edit').id),
      action: () => {
        this.request(ProfilesRequest.Edit, profile);
      }
    });

    if (profile.imported) {
      items.push({
        value: manager.getStringSync($r('app.string.duplicate').id),
        action: () => {
          this.request(ProfilesRequest.Duplicate, profile);
        }
      });
    }

    if (profile.imported && profile.type === ProfileType.Url && profile.source !== '') {
      items.push({
        value: manager.getStringSync($r('app.string.share_qr_code').id),
        action: () => {
          this.request(ProfilesRequest.ShareQrCode, profile);
        }
      });
    }

    items.push({
      value: manager.getStringSync($r('app.string.delete').id),
      action: () => {
        this.request(ProfilesRequest.Delete, profile);
      }
    });

    return items;
  }

  /** Mirrors `ProfilesActivity`'s `design.requests.onReceive` switch. */
  private request(request: ProfilesRequest, profile: Profile): void {
    if (request === ProfilesRequest.Update) {
      this.updateOne(profile);
      return;
    }
    if (request === ProfilesRequest.UpdateAll) {
      this.updateAll();
      return;
    }
    if (request === ProfilesRequest.Edit) {
      // Mirrors Request.Edit -> PropertiesActivity with the profile UUID.
      router.pushUrl({ url: 'pages/PropertiesPage', params: { uuid: profile.uuid } });
      return;
    }
    if (request === ProfilesRequest.Duplicate) {
      // Mirrors Request.Duplicate -> clone(uuid) -> PropertiesActivity.
      const copy: Profile | undefined = profileClone(this.store, profile.uuid);
      if (copy !== undefined) {
        router.pushUrl({ url: 'pages/PropertiesPage', params: { uuid: copy.uuid } });
      }
      return;
    }
    if (request === ProfilesRequest.ShareQrCode) {
      if (profile.type !== ProfileType.Url || profile.source === '') {
        return;
      }
      this.shareSource = profile.source;
      this.shareName = profile.name;
      this.sharingQr = true;
      return;
    }
    if (request === ProfilesRequest.Delete) {
      // Android deletes straight from the menu, with no confirmation dialog.
      profileRemove(this.store, profile.uuid);
      return;
    }
    if (request === ProfilesRequest.Active) {
      if (profile.imported) {
        profileSetActive(this.store, profile.uuid);
      } else {
        showToast($r('app.string.active_unsaved_tips'));
      }
      return;
    }
    if (request === ProfilesRequest.Create) {
      // Mirrors Request.Create -> NewProfileActivity.
      router.pushUrl({ url: 'pages/NewProfilePage' });
    }
  }

  /**
   * `Request.Update` -> `ProfileManager.update(uuid)`, which re-fetches the
   * subscription and then broadcasts completion. There is no broadcast here, so
   * the same two toasts are raised from the call site.
   */
  private async updateOne(profile: Profile): Promise<void> {
    if (this.updating) {
      return;
    }
    this.updating = true;
    const result: ProfileFetchResult =
      await applyProfile(getContext(this), this.store, profile.uuid);
    this.updating = false;
    this.reportUpdate(profile, result);
  }

  /**
   * `Request.UpdateAll` -> `update(uuid)` for every `imported && type != File`
   * profile, in list order. Android shows one completion toast per profile, so
   * the loop does too rather than inventing a summary string.
   */
  private async updateAll(): Promise<void> {
    if (this.updating) {
      return;
    }
    this.updating = true;

    const targets: Profile[] = profileAll(this.store).filter((profile: Profile) =>
      profile.imported && profile.type !== ProfileType.File);
    for (const target of targets) {
      const result: ProfileFetchResult =
        await applyProfile(getContext(this), this.store, target.uuid);
      this.reportUpdate(target, result);
    }

    this.updating = false;
  }

  /**
   * `ProfilesActivity.onProfileUpdateCompleted` / `onProfileUpdateFailed`. The
   * failure toast is raised here instead of by a broadcast receiver; Android's
   * toast also carries an "Edit" action button, which `promptAction` cannot
   * host (the row menu still has Edit).
   */
  private reportUpdate(profile: Profile, result: ProfileFetchResult): void {
    if (result.status === ProfileFetchStatus.Ok) {
      showToast($r('app.string.toast_profile_updated_complete', profile.name));
      return;
    }
    showToast($r('app.string.toast_profile_updated_failed', profile.name, result.message));
  }

  /**
   * Mirrors `ProfilesDesign.showProfileQrCode`: Android uses ZXing to make a
   * bitmap, catches `WriterException`, and shows the bitmap in a dialog.
   * ArkUI's `QRCode` component encodes declaratively, so there is no encoder
   * call whose error could be turned into `qr_code_generation_failed`.
   */
  @Builder
  shareQrDialog() {
    Column() {
      Column() {
        Text($r('app.string.share_qr_code'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text(this.shareName)
          .fontSize(14)
          .opacity(0.6)
          .width('100%')
          .textAlign(TextAlign.Start)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })

        // `dialog_profile_qr_code.xml` is a white, fit-center ImageView. The
        // native QRCode component owns the encoding; it has no observable
        // encoder error, so Android's `qr_code_generation_failed` branch has no
        // direct equivalent.
        QRCode(this.shareSource)
          .width(240)
          .height(240)
          .color(Color.Black)
          .backgroundColor(Color.White)
          .contentOpacity(1)
          .margin({ top: 20, bottom: 20 })

        Button($r('app.string.close'))
          .width('100%')
          .height(40)
          .fontSize(15)
          .onClick(() => {
            this.sharingQr = false;
            this.shareSource = '';
            this.shareName = '';
          })
      }
      .width('85%')
      .padding(20)
      .backgroundColor($r('app.color.color_surface'))
      .borderRadius(8)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#80000000')
  }

  /**
   * Mirrors the RadioButton in `adapter_profile.xml`: a 20dp ring that gains a
   * filled centre when the profile is active. `colorSecondary` is
   * `?attr/colorPrimary` in both themes, so the dot uses `color_primary`.
   */
  @Builder
  radioButton(active: boolean) {
    Stack() {
      Circle()
        .width(20)
        .height(20)
        .fill(Color.Transparent)
        .stroke($r('app.color.color_control_normal'))
        .strokeWidth(2)
        .opacity(0.54)

      if (active) {
        Circle()
          .width(10)
          .height(10)
          .fill($r('app.color.color_primary'))
      }
    }
    .width($r('app.float.item_header_component_size'))
    .height($r('app.float.item_header_component_size'))
    // `layout_marginHorizontal="@dimen/item_header_margin"` in
    // `adapter_profile.xml`.
    .margin({
      left: $r('app.float.item_header_margin'),
      right: $r('app.float.item_header_margin')
    })
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
            router.back();
          })

        // `android:label="@string/profiles"` on ProfilesActivity.
        Text($r('app.string.profiles'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .margin({ left: $r('app.float.item_text_margin') })

        // `update_view`: GONE unless some profile is imported and not a file.
        if (this.canUpdateAll()) {
          // `changeUpdateAllButtonStatus()` swaps the button for a progress
          // indicator while an update is running.
          if (this.updating) {
            LoadingProgress()
              .width($r('app.float.item_tailing_component_size'))
              .height($r('app.float.item_tailing_component_size'))
              .color($r('app.color.color_control_normal'))
              .margin({ right: $r('app.float.item_tailing_margin') })
          } else {
            Image($r('app.media.ic_baseline_sync'))
              .width($r('app.float.item_tailing_component_size'))
              .height($r('app.float.item_tailing_component_size'))
              .objectFit(ImageFit.Contain)
              .fillColor($r('app.color.color_control_normal'))
              .margin({ right: $r('app.float.item_tailing_margin') })
              .onClick(() => {
                this.request(ProfilesRequest.UpdateAll, new Profile());
              })
          }
        }

        // `add_view`.
        Image($r('app.media.ic_baseline_add'))
          .width($r('app.float.item_tailing_component_size'))
          .height($r('app.float.item_tailing_component_size'))
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.color_control_normal'))
          .onClick(() => {
            this.request(ProfilesRequest.Create, new Profile());
          })
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      List() {
        ForEach(profileAll(this.store), (profile: Profile) => {
          ListItem() {
            Row() {
              this.radioButton(profile.active)

              Column() {
                Text(profile.name)
                  .fontSize(16)
                  .width('100%')
                  .textAlign(TextAlign.Start)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(this.typeText(profile))
                  .fontSize(14)
                  .opacity(0.6)
                  .width('100%')
                  .textAlign(TextAlign.Start)
                  .margin({ top: $r('app.float.item_text_margin') })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              .padding({
                top: $r('app.float.item_padding_vertical'),
                bottom: $r('app.float.item_padding_vertical')
              })

              Text(this.elapsedLabel(profile))
                .fontSize(12)
                .margin({ right: $r('app.float.item_midden_margin') })

              // The 2dp separator before the menu; `adapter_profile.xml` colours
              // it with `@color/color_clash_dark`, not a theme attribute.
              //
              // Android gives it `layout_height="match_parent"`. A percentage
              // height here makes the whole card resolve against the List's
              // height and stretch to fill it, so the card's minimum height is
              // used instead.
              Divider()
                .vertical(true)
                .strokeWidth(2)
                .height($r('app.float.item_min_height'))
                .color($r('app.color.color_clash_dark'))

              Image($r('app.media.ic_baseline_more_vert'))
                .width($r('app.float.item_tailing_component_size'))
                .height($r('app.float.item_tailing_component_size'))
                .objectFit(ImageFit.Contain)
                .fillColor($r('app.color.color_control_normal'))
                .margin($r('app.float.item_tailing_margin'))
                .bindMenu(this.itemMenu(profile))
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .constraintSize({ minHeight: $r('app.float.item_min_height') })
            .backgroundColor($r('app.color.color_surface'))
            .borderRadius(8)
            .shadow({ radius: 5, color: '#33000000', offsetX: 0, offsetY: 2 })
            .onClick(() => {
              this.request(ProfilesRequest.Active, profile);
            })
          }
          .margin({
            top: 5,
            bottom: 5,
            left: $r('app.float.item_header_margin'),
            right: $r('app.float.item_header_margin')
          })
        }, (profile: Profile) => this.rowKey(profile))
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.color_background'))
    .bindContentCover(
      this.sharingQr,
      this.shareQrDialog(),
      { modalTransition: ModalTransition.NONE }
    )
  }
}
