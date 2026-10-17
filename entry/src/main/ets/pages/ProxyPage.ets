/*
 * Proxy screen -- port of ClashMetaForAndroid `design_proxy.xml` + `ProxyActivity.kt`.
 *
 * Android structure:
 *   CoordinatorLayout
 *   +- TextView#empty_view            (centred, GONE unless there are no groups)
 *   +- ViewPager2#pages_view          (one page per proxy group)
 *   +- LinearLayout (top overlay)
 *      +- ActivityBarLayout           (back + title, delay-test icon, overflow)
 *      +- TabLayout#tab_layout_view   (scrollable, one tab per group)
 *      +- divider View
 *   +- FloatingActionButton           (delay test, bottom end)
 *
 * HarmonyOS mapping (per hmos-batch-ui-align references):
 *   ViewPager2 + TabLayout -> Tabs + TabContent (the documented pairing)
 *   CoordinatorLayout      -> Column with a fixed Navigation bar
 *   RecyclerView           -> List + ForEach
 *   View.GONE              -> omitted from build (if)
 *
 * Row rendering follows ProxyView.kt / ProxyViewState.kt:
 *   - the selected member (`proxy.name == parent.now`) is drawn on a
 *     `colorPrimary` card; every other member sits on `colorSurface`
 *   - the delay is the bare number from `proxy.delay`, in the same colour as
 *     the rest of the row (ProxyViewState.delayText = proxy.delay.toString())
 *   - a member that is itself a group shows `type(now)` as its subtitle
 *   - only a `Selector` group takes taps (`ProxyView` attaches no listener
 *     otherwise, and `ProxyViewModel.select` is documented to ignore the rest);
 *     tapping a member of an auto-selected group says so rather than going
 *     silent
 *
 * Title-bar actions and the overflow menu follow design_proxy.xml +
 * ProxyDesign + ProxyMenu:
 *   url_test_view   flash icon -> Request.UrlTest (swapped for a spinner while
 *                   the test runs)
 *   menu_view       more-vert   -> filter / mode / layout / sort
 *   url_test_float_view  the same delay test as a floating button, hidden while
 *                   a test runs
 *
 * Android pushes "exclude non-selectable groups" and the sort into the native
 * core's queries (`queryProxyGroupNames` / `queryProxyGroup`). The port owns
 * its own list, so `ProxyViewModel.shape()` applies the same two rules on top
 * of the controller's single `GET /proxies` response.
 *
 * Row layout follows ProxyView + ProxyViewConfig + ProxyPageFactory: a
 * 6-column grid whose cards span 6 / 3 / 2 columns for 1 / 2 / 3 columns per
 * row, with Android's paddings, card radius and one uniform text size for the
 * title, the subtitle and the delay.
 */

import { router } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import { ProxyGroup, ProxyNode, ProxySort } from '../model/ProxyModels';
import { TunnelMode } from '../model/MainModels';
import { ProxyViewModel } from '../viewmodel/ProxyViewModel';
import { loadControllerStore } from '../backend/ControllerStore';
import { loadProxyUiStore } from '../backend/ProxyUiStore';
import { showToast } from '../util/Platform';

/*
 * Row metrics from `design/src/main/res/values/dimens.xml` + `ProxyViewConfig`:
 * `proxyLine == 2` is the only branch with its own values, everything else
 * (including 1 and 3) shares the `_grid3` set.
 */
const PROXY_LAYOUT_PADDING: number = 3;
const PROXY_CARD_RADIUS: number = 5;
const PROXY_CONTENT_PADDING: number = 15;
const PROXY_CONTENT_PADDING_GRID3: number = 12;
const PROXY_TEXT_MARGIN: number = 10;
const PROXY_TEXT_MARGIN_GRID3: number = 5;
const PROXY_TEXT_SIZE: number = 12;
const PROXY_TEXT_SIZE_GRID3: number = 11;
/**
 * `ProxyView.onMeasure` sizes a row from the *tight* bounds of the text, not
 * the line height. For the default font that bound is about 0.73em, which is
 * what turns the Android formula into a concrete vp value here.
 */
const PROXY_TEXT_BOUND_RATIO: number = 0.73;

@Entry
@ComponentV2
struct ProxyPage {
  @Local vm: ProxyViewModel = new ProxyViewModel();
  private tabsController: TabsController = new TabsController();

  aboutToAppear(): void {
    this.vm.useController(loadControllerStore());
    this.vm.useUiStore(loadProxyUiStore());
    this.vm.reload();
    this.vm.loadMode();
  }

  /**
   * Mirrors ProxyViewState.delayText: the raw millisecond count, or an empty
   * string when the core has no measurement (`delay !in 0..Short.MAX_VALUE`).
   * Android appends no unit.
   */
  private delayLabel(delay: number): string {
    if (delay < 0) {
      return '';
    }
    return `${delay}`;
  }

  /**
   * Mirrors `ProxyActivity.Request.PatchMode`: the design shows the
   * `mode_switch_tips` toast first, then patches the override. Android's
   * fourth entry ("don't modify") clears a session override; the controller
   * has no override layer, so only the three concrete modes are offered.
   */
  private switchMode(mode: TunnelMode): void {
    showToast($r('app.string.mode_switch_tips'));
    this.vm.switchMode(mode);
  }

  private requestUrlTest(): void {
    this.vm.urlTest(this.vm.selectedIndex);
  }

  /** Ticks the entry that matches the state the controller reported. */
  private markActive(label: string, active: boolean): string {
    return active ? `${label} \u2713` : label;
  }

  /** `ProxyViewConfig.contentPadding`. */
  private contentPadding(): number {
    return this.vm.line === 2 ? PROXY_CONTENT_PADDING : PROXY_CONTENT_PADDING_GRID3;
  }

  /** `ProxyViewConfig.textMargin`. */
  private textMargin(): number {
    return this.vm.line === 2 ? PROXY_TEXT_MARGIN : PROXY_TEXT_MARGIN_GRID3;
  }

  /** `ProxyViewConfig.textSize`; the title, subtitle and delay all share it. */
  private textSize(): number {
    return this.vm.line === 2 ? PROXY_TEXT_SIZE : PROXY_TEXT_SIZE_GRID3;
  }

  /**
   * Mirrors `ProxyView.onMeasure`:
   *   layoutPadding*2 + contentPadding*2 + textHeight*2 + textMargin
   */
  private rowHeight(): number {
    return PROXY_LAYOUT_PADDING * 2 +
      this.contentPadding() * 2 +
      this.textSize() * PROXY_TEXT_BOUND_RATIO * 2 +
      this.textMargin();
  }

  /**
   * Android draws the text at `layoutPadding + contentPadding` from the cell
   * edge in every mode. In a single column the row background is full-bleed,
   * so that offset has to come from the padding here; otherwise the card is
   * already inset by `layoutPadding` and only `contentPadding` is left.
   */
  private horizontalPadding(): number {
    if (this.vm.line === 1) {
      return PROXY_LAYOUT_PADDING + this.contentPadding();
    }
    return this.contentPadding();
  }

  /** `ProxyPageFactory`: 6 grid columns, one card spanning 6 / 3 / 2 of them. */
  private columnsTemplate(): string {
    if (this.vm.line === 1) {
      return '1fr';
    }
    return this.vm.line === 3 ? '1fr 1fr 1fr' : '1fr 1fr';
  }

  /**
   * `ProxyViewConfig.selectedBackground` is `colorPrimary`, and the unselected
   * background is transparent in a single column and `colorSurface` otherwise.
   */
  private rowBackground(node: ProxyNode, group: ProxyGroup): ResourceColor {
    if (node.name === group.now) {
      return $r('app.color.color_primary');
    }
    if (this.vm.line === 1) {
      return Color.Transparent;
    }
    return $r('app.color.color_surface');
  }

  /** `ProxyView.draw` only rounds the card when there is more than one column. */
  private rowRadius(): number {
    return this.vm.line === 1 ? 0 : PROXY_CARD_RADIUS;
  }

  /**
   * Mirrors `menu_proxy.xml` + `ProxyMenu`.
   *
   * Android nests the entries under four submenu titles (Filter / Mode /
   * Layout / Sort) and draws a check icon on the active entry. `MenuElement[]`
   * has no nested form and `bindMenu` given a `@Builder` does not open in this
   * component, so the four groups are flattened into one list: the group name
   * prefixes the label and the active entry gets the tick.
   */
  private proxyMenuItems(): MenuElement[] {
    const manager: resourceManager.ResourceManager = getContext(this).resourceManager;
    const filter: string = manager.getStringSync($r('app.string.filter').id);
    const notSelectable: string = manager.getStringSync($r('app.string.not_selectable').id);
    const mode: string = manager.getStringSync($r('app.string.mode').id);
    const direct: string = manager.getStringSync($r('app.string.direct_mode').id);
    const global: string = manager.getStringSync($r('app.string.global_mode').id);
    const rule: string = manager.getStringSync($r('app.string.rule_mode').id);
    const layout: string = manager.getStringSync($r('app.string.layout').id);
    const single: string = manager.getStringSync($r('app.string.single').id);
    const doubles: string = manager.getStringSync($r('app.string.doubles').id);
    const multiple: string = manager.getStringSync($r('app.string.multiple').id);
    const sort: string = manager.getStringSync($r('app.string.sort').id);
    const defaultSort: string = manager.getStringSync($r('app.string.default_').id);
    const byName: string = manager.getStringSync($r('app.string.name').id);
    const byDelay: string = manager.getStringSync($r('app.string.delay').id);

    const items: MenuElement[] = [
      {
        value: this.markActive(`${filter}: ${notSelectable}`, this.vm.excludeNotSelectable),
        action: () => {
          this.vm.setExcludeNotSelectable(!this.vm.excludeNotSelectable);
        }
      },
      {
        value: this.markActive(`${mode}: ${direct}`, this.vm.mode === TunnelMode.Direct),
        action: () => {
          this.switchMode(TunnelMode.Direct);
        }
      },
      {
        value: this.markActive(`${mode}: ${global}`, this.vm.mode === TunnelMode.Global),
        action: () => {
          this.switchMode(TunnelMode.Global);
        }
      },
      {
        value: this.markActive(`${mode}: ${rule}`, this.vm.mode === TunnelMode.Rule),
        action: () => {
          this.switchMode(TunnelMode.Rule);
        }
      },
      {
        value: this.markActive(`${layout}: ${single}`, this.vm.line === 1),
        action: () => {
          this.vm.setLine(1);
        }
      },
      {
        value: this.markActive(`${layout}: ${doubles}`, this.vm.line === 2),
        action: () => {
          this.vm.setLine(2);
        }
      },
      {
        value: this.markActive(`${layout}: ${multiple}`, this.vm.line === 3),
        action: () => {
          this.vm.setLine(3);
        }
      },
      {
        value: this.markActive(`${sort}: ${defaultSort}`, this.vm.sort === ProxySort.Default),
        action: () => {
          this.vm.setSort(ProxySort.Default);
        }
      },
      {
        value: this.markActive(`${sort}: ${byName}`, this.vm.sort === ProxySort.Title),
        action: () => {
          this.vm.setSort(ProxySort.Title);
        }
      },
      {
        value: this.markActive(`${sort}: ${byDelay}`, this.vm.sort === ProxySort.Delay),
        action: () => {
          this.vm.setSort(ProxySort.Delay);
        }
      }
    ];
    return items;
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        // ---- navigation bar (ActivityBarLayout) ----
        Row() {
          Image($r('app.media.ic_baseline_arrow_back'))
            .width($r('app.float.item_tailing_component_size'))
            .height($r('app.float.item_tailing_component_size'))
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.color_control_normal'))
            .onClick(() => {
              router.back();
            })

          Text($r('app.string.proxy'))
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
            .margin({ left: $r('app.float.item_text_margin') })

          // Mirrors url_test_view / url_test_progress_view: hidden entirely
          // when there is nothing to test.
          if (this.vm.groups.length > 0) {
            if (this.vm.urlTesting) {
              LoadingProgress()
                .width($r('app.float.item_tailing_component_size'))
                .height($r('app.float.item_tailing_component_size'))
                .margin({ right: $r('app.float.item_tailing_margin') })
            } else {
              Image($r('app.media.ic_baseline_flash_on'))
                .width($r('app.float.item_tailing_component_size'))
                .height($r('app.float.item_tailing_component_size'))
                .objectFit(ImageFit.Contain)
                .fillColor($r('app.color.color_control_normal'))
                .margin({ right: $r('app.float.item_tailing_margin') })
                .onClick(() => {
                  this.requestUrlTest();
                })
            }
          }

          // Mirrors menu_view. Android keeps this visible even when the group
          // list is empty.
          Image($r('app.media.ic_baseline_more_vert'))
            .width($r('app.float.item_tailing_component_size'))
            .height($r('app.float.item_tailing_component_size'))
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.color_control_normal'))
            .bindMenu(this.proxyMenuItems())
        }
        .width('100%')
        .height(56)
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)

        if (this.vm.loading) {
          LoadingProgress()
            .width(48)
            .height(48)
            .margin({ top: 48 })
        } else if (this.vm.groups.length === 0) {
          // Mirrors the `empty_view` TextView in design_proxy.xml.
          Text(this.vm.lastError.length > 0 ? this.vm.lastError : $r('app.string.proxy_empty_tips'))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .opacity(0.7)
            .margin({ top: 96 })
        } else {
          Tabs({ barPosition: BarPosition.Start, controller: this.tabsController }) {
          ForEach(this.vm.groups, (group: ProxyGroup, index: number) => {
            TabContent() {
              Grid() {
                ForEach(group.nodes, (node: ProxyNode) => {
                  GridItem() {
                    Row() {
                      Column() {
                        Text(node.name)
                          .fontSize(this.textSize())
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%')
                          .textAlign(TextAlign.Start)
                        if (node.type.length > 0) {
                          Text(node.type)
                            .fontSize(this.textSize())
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .width('100%')
                            .textAlign(TextAlign.Start)
                        }
                      }
                      .layoutWeight(1)
                      .height('100%')
                      .alignItems(HorizontalAlign.Start)
                      // ProxyView draws the title at 1/3 and the subtitle at
                      // 2/3 of the card height.
                      .justifyContent(FlexAlign.SpaceEvenly)

                      Text(this.delayLabel(node.delay))
                        .fontSize(this.textSize())
                    }
                    .width('100%')
                    .height('100%')
                    .alignItems(VerticalAlign.Center)
                    .padding({ left: this.horizontalPadding(), right: this.horizontalPadding() })
                    .backgroundColor(this.rowBackground(node, group))
                    .borderRadius(this.rowRadius())
                    .onClick(() => {
                      if (this.vm.canSelect(index)) {
                        this.vm.select(index, node.name);
                      } else {
                        // Android leaves these rows unclickable, so the tap is a
                        // no-op there too; say why instead of ignoring it.
                        showToast($r('app.string.not_selectable'));
                      }
                    })
                  }
                  .height(this.rowHeight())
                  .padding(this.vm.line === 1 ? 0 : PROXY_LAYOUT_PADDING)
                }, (node: ProxyNode) => node.name)
              }
              .columnsTemplate(this.columnsTemplate())
              .columnsGap(0)
              .rowsGap(0)
              .width('100%')
              .height('100%')
              .scrollBar(BarState.Off)
            }
            .tabBar(group.name)
          }, (group: ProxyGroup) => group.name)
          }
          .barMode(BarMode.Scrollable)
          .layoutWeight(1)
          .onChange((index: number) => {
            this.vm.selectedIndex = index;
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.color_background'))

      // Mirrors url_test_float_view: the same delay test as a floating button,
      // hidden while a test runs and when there is no group to test.
      if (!this.vm.loading && !this.vm.urlTesting && this.vm.groups.length > 0) {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_baseline_flash_on'))
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
            .fillColor(Color.White)
        }
        .width(56)
        .height(56)
        // Material's FloatingActionButton defaults to backgroundTint
        // ?attr/colorSecondary and tint ?attr/colorOnSecondary, both of which
        // resolve to colorPrimary / white in this app's themes.
        .backgroundColor($r('app.color.color_primary'))
        .shadow({ radius: 6, color: '#33000000', offsetX: 0, offsetY: 3 })
        .margin({
          right: $r('app.float.item_tailing_margin'),
          bottom: $r('app.float.item_tailing_margin')
        })
        .onClick(() => {
          this.requestUrlTest();
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
