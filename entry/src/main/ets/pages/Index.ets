/*
 * Main screen -- port of ClashMetaForAndroid `design_main.xml` + `MainActivity.kt`.
 *
 * Android structure (design/src/main/res/layout/design_main.xml):
 *   CoordinatorLayout
 *   +- ScrollView
 *      +- LinearLayout(vertical, paddingH 30dp, insets top/bottom)
 *         +- LinearLayout(horizontal, minHeight 90dp)   [logo 50dp in 70dp frame | app name Headline6]
 *         +- LargeActionCard  status    (cardBg = running ? started : stopped)
 *         +- LargeActionCard  proxy     (GONE unless running)
 *         +- LargeActionCard  profile
 *         +- LargeActionLabel providers (GONE unless running && hasProviders)
 *         +- LargeActionLabel logs / settings / help / about
 *
 * HarmonyOS mapping applied (per hmos-batch-ui-align mapping references):
 *   CoordinatorLayout -> Column          ScrollView -> Scroll
 *   LinearLayout v/h  -> Column/Row      FrameLayout -> Stack
 *   MaterialCardView  -> styled Column (radius + shadow), not a stretched SVG
 *   View.GONE         -> omitted from build (if), not Visibility.Hidden
 *   dp/sp             -> vp/fp
 *
 * Paradigm: V2 (@ComponentV2 / @Local / @Param / @Event / @ObservedV2 / @Trace).
 * Project was empty before this conversion, so the selector rule resolves to V2.
 *
 * Data behind the screen is NOT live yet -- see MainViewModel's header.
 */

import { MainRequest } from '../model/MainModels';
import { MainViewModel } from '../viewmodel/MainViewModel';
import { LargeActionCard } from '../view/LargeActionCard';
import { LargeActionLabel } from '../view/LargeActionLabel';

@Entry
@ComponentV2
struct Index {
  @Local vm: MainViewModel = new MainViewModel();

  aboutToAppear(): void {
    this.vm.refresh();
  }

  private request(request: MainRequest): void {
    // Mirrors MainActivity's `design.requests.onReceive`. Navigation targets
    // (ProxyActivity / ProfilesActivity / ...) are not ported yet; the status
    // toggle is the only one wired to the ViewModel.
    if (request === MainRequest.ToggleStatus) {
      this.vm.toggleStatus();
    }
  }

  build() {
    Scroll() {
      Column() {
        // ---- header: logo + application name ----
        Row() {
          Stack() {
            Image($r('app.media.ic_clash'))
              .width($r('app.float.main_logo_size'))
              .height($r('app.float.main_logo_size'))
              .objectFit(ImageFit.Contain)
          }
          .width($r('app.float.large_item_header_layout_size'))
          .height($r('app.float.large_item_header_layout_size'))

          Text($r('app.string.application_name'))
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .constraintSize({ minHeight: $r('app.float.main_top_banner_height') })

        // ---- status card (tap to start / stop) ----
        LargeActionCard({
          text: this.vm.state.running ? $r('app.string.running') : $r('app.string.stopped'),
          subtext: this.vm.state.running
            ? $r('app.string.format_traffic_forwarded', this.vm.forwardedText)
            : $r('app.string.tap_to_start'),
          icon: this.vm.state.running
            ? $r('app.media.ic_outline_check_circle')
            : $r('app.media.ic_outline_not_interested'),
          cardColor: this.vm.state.running
            ? $r('app.color.color_clash_started')
            : $r('app.color.color_clash_stopped'),
          onAction: () => {
            this.request(MainRequest.ToggleStatus);
          }
        })
          .margin({ top: $r('app.float.main_card_margin_vertical'), bottom: $r('app.float.main_card_margin_vertical') })

        // ---- proxy card (GONE unless running) ----
        if (this.vm.state.running) {
          LargeActionCard({
            text: $r('app.string.proxy'),
            subtext: this.vm.modeRes,
            icon: $r('app.media.ic_baseline_apps'),
            cardColor: $r('app.color.color_dark_surface'),
            onAction: () => {
              this.request(MainRequest.OpenProxy);
            }
          })
            .margin({ top: $r('app.float.main_card_margin_vertical'), bottom: $r('app.float.main_card_margin_vertical') })
        }

        // ---- profile card ----
        LargeActionCard({
          text: $r('app.string.profile'),
          subtext: this.vm.profileRes,
          icon: $r('app.media.ic_baseline_view_list'),
          cardColor: $r('app.color.color_dark_surface'),
          onAction: () => {
            this.request(MainRequest.OpenProfiles);
          }
        })
          .margin({ top: $r('app.float.main_card_margin_vertical'), bottom: $r('app.float.main_card_margin_vertical') })

        // ---- providers label (GONE unless running && hasProviders) ----
        if (this.vm.state.running && this.vm.state.hasProviders) {
          LargeActionLabel({
            text: $r('app.string.providers'),
            icon: $r('app.media.ic_baseline_swap_vertical_circle'),
            onAction: () => {
              this.request(MainRequest.OpenProviders);
            }
          })
            .margin({ top: $r('app.float.main_label_margin_vertical'), bottom: $r('app.float.main_label_margin_vertical') })
        }

        // ---- navigation labels ----
        LargeActionLabel({
          text: $r('app.string.logs'),
          icon: $r('app.media.ic_baseline_assignment'),
          onAction: () => {
            this.request(MainRequest.OpenLogs);
          }
        })
          .margin({ top: $r('app.float.main_label_margin_vertical'), bottom: $r('app.float.main_label_margin_vertical') })

        LargeActionLabel({
          text: $r('app.string.settings'),
          icon: $r('app.media.ic_baseline_settings'),
          onAction: () => {
            this.request(MainRequest.OpenSettings);
          }
        })
          .margin({ top: $r('app.float.main_label_margin_vertical'), bottom: $r('app.float.main_label_margin_vertical') })

        LargeActionLabel({
          text: $r('app.string.help'),
          icon: $r('app.media.ic_baseline_help_center'),
          onAction: () => {
            this.request(MainRequest.OpenHelp);
          }
        })
          .margin({ top: $r('app.float.main_label_margin_vertical'), bottom: $r('app.float.main_label_margin_vertical') })

        LargeActionLabel({
          text: $r('app.string.about'),
          icon: $r('app.media.ic_baseline_info'),
          onAction: () => {
            this.request(MainRequest.OpenAbout);
          }
        })
          .margin({ top: $r('app.float.main_label_margin_vertical'), bottom: $r('app.float.main_label_margin_vertical') })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: $r('app.float.main_padding_horizontal'),
        right: $r('app.float.main_padding_horizontal')
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }
}
