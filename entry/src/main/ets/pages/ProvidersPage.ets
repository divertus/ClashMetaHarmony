/*
 * Providers screen -- port of ClashMetaForAndroid `design_providers.xml` +
 * `ProvidersActivity.kt` + `ProviderAdapter` / `adapter_provider.xml`.
 *
 * Android structure:
 *   CoordinatorLayout
 *   +- RecyclerView#main_list          (one row per provider)
 *   +- ActivityBarLayout
 *      +- common_activity_bar          (back + title)
 *      +- ImageView#update_view        (sync icon -> requestUpdateAll)
 *
 * Each row (`adapter_provider.xml`, minHeight 75dp):
 *   [ Column: name (Body1) / type (Body2) ]   [ elapsed ]   [ divider ]
 *   [ end view: swap-vert icon, or a spinner while updating ]
 * Inline providers have no remote source, so their elapsed text, divider and
 * end view are all hidden (`ProviderAdapter.onBindViewHolder`).
 *
 * HarmonyOS mapping (per hmos-batch-ui-align references):
 *   RecyclerView -> List + ForEach    View.GONE -> omitted from build (if)
 *   ProgressBar  -> LoadingProgress   View divider -> Divider(vertical)
 *
 * `format_provider_type` is `%s(%s)` (the converter emitted Android's
 * `%1$s(%2$s)`; indexed placeholders were normalised to `%s` because ArkUI's
 * resource formatter documents only `%d` / `%s` / `%f`). The two words are
 * resolved through the resource manager so the label stays localized.
 */

import { router } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import { ProviderItem, elapsedIntervalString } from '../model/ProviderModels';
import { ProvidersViewModel } from '../viewmodel/ProvidersViewModel';
import { loadControllerStore } from '../backend/ControllerStore';

@Entry
@ComponentV2
struct ProvidersPage {
  @Local vm: ProvidersViewModel = new ProvidersViewModel();

  aboutToAppear(): void {
    this.vm.useController(loadControllerStore());
    this.vm.reload();
    this.vm.startTicker();
  }

  aboutToDisappear(): void {
    this.vm.stopTicker();
  }

  /** `Provider.Type` -> the localized word (`proxy` / `rule`). */
  private typeResourceId(type: string): number {
    return type === 'Rule' ? $r('app.string.rule').id : $r('app.string.proxy').id;
  }

  /** `Provider.VehicleType` -> the localized word. */
  private vehicleResourceId(vehicleType: string): number {
    if (vehicleType === 'File') {
      return $r('app.string.file').id;
    }
    if (vehicleType === 'Inline') {
      return $r('app.string.inline').id;
    }
    if (vehicleType === 'Compatible') {
      return $r('app.string.compatible').id;
    }
    return $r('app.string.http').id;
  }

  /** Mirrors `Provider.type(context)`: `format_provider_type(type, vehicle)`. */
  private typeLabel(item: ProviderItem): ResourceStr {
    const manager: resourceManager.ResourceManager = getContext(this).resourceManager;
    const typeWord: string = manager.getStringSync(this.typeResourceId(item.type));
    const vehicleWord: string = manager.getStringSync(this.vehicleResourceId(item.vehicleType));
    return $r('app.string.format_provider_type', typeWord, vehicleWord);
  }

  /** Mirrors `elapsedIntervalString(currentTime - state.updatedAt)`. */
  private elapsedLabel(item: ProviderItem): ResourceStr {
    return elapsedIntervalString(this.vm.now - item.updatedAt);
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

        Text($r('app.string.providers'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .margin({ left: $r('app.float.item_text_margin') })

        // Mirrors ImageView#update_view -> requestUpdateAll().
        Image($r('app.media.ic_baseline_sync'))
          .width($r('app.float.item_tailing_component_size'))
          .height($r('app.float.item_tailing_component_size'))
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.color_control_normal'))
          .onClick(() => {
            this.vm.updateAll();
          })
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      if (this.vm.loading) {
        LoadingProgress()
          .width(48)
          .height(48)
          .margin({ top: 48 })
      } else if (this.vm.items.length === 0) {
        // `design_providers.xml` has no empty view, so Android renders a blank
        // list here; this port says why instead, matching ProxyPage's empty
        // state. `lastError` is the same string the update path records.
        Text(this.vm.lastError.length > 0 ? this.vm.lastError : 'no providers')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .opacity(0.7)
          .margin({ top: 96 })
      } else {
        List() {
          ForEach(this.vm.items, (item: ProviderItem) => {
            ListItem() {
              Row() {
                Column() {
                  Text(item.name)
                    .fontSize(16)
                    .width('100%')
                    .textAlign(TextAlign.Start)

                  Text(this.typeLabel(item))
                    .fontSize(14)
                    .opacity(0.6)
                    .width('100%')
                    .textAlign(TextAlign.Start)
                    .margin({ top: $r('app.float.item_text_margin') })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                // Inline providers have no remote source to refresh.
                if (item.vehicleType !== 'Inline') {
                  Text(this.elapsedLabel(item))
                    .fontSize(14)
                    .margin({ right: $r('app.float.item_midden_margin') })

                  Divider()
                    .vertical(true)
                    .height(45)
                    // Divider.strokeWidth takes Length, not a Resource, so the
                    // converted `divider_size` (1vp) is inlined here.
                    .strokeWidth(1)
                    // `adapter_provider.xml` gives this divider
                    // `android:background="?attr/colorControlHighlight"`.
                    .color($r('app.color.color_control_highlight'))

                  Stack() {
                    if (item.updating) {
                      LoadingProgress()
                        .width($r('app.float.item_tailing_component_size'))
                        .height($r('app.float.item_tailing_component_size'))
                    } else {
                      Image($r('app.media.ic_baseline_swap_vert'))
                        .width($r('app.float.item_tailing_component_size'))
                        .height($r('app.float.item_tailing_component_size'))
                        .objectFit(ImageFit.Contain)
                        .fillColor($r('app.color.color_control_normal'))
                    }
                  }
                  .padding($r('app.float.item_tailing_margin'))
                  .onClick(() => {
                    if (!item.updating) {
                      this.vm.update(item);
                    }
                  })
                }
              }
              .width('100%')
              .constraintSize({ minHeight: $r('app.float.item_min_height') })
              .padding({ left: $r('app.float.item_header_margin') })
              .alignItems(VerticalAlign.Center)
            }
          }, (item: ProviderItem) => item.name)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.color_background'))
  }
}
