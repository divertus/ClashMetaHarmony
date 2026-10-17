/*
 * Headless external-control entry point.
 *
 * Ported from ClashMetaForAndroid:
 *   app/src/main/java/com/github/kr328/clash/ExternalControlActivity.kt
 *
 * Android exposes one translucent Activity for four public actions:
 *   android.intent.action.VIEW
 *     -> create a profile from `url` and open PropertiesActivity
 *   com.github.metacubex.clash.meta.action.TOGGLE_CLASH
 *   com.github.metacubex.clash.meta.action.START_CLASH
 *   com.github.metacubex.clash.meta.action.STOP_CLASH
 *
 * On HarmonyOS the equivalent entry point is the Want delivered to
 * EntryAbility.onCreate / onNewWant. A cold-start Want arrives before
 * `windowStage.loadContent` has created the page stack, so the request is
 * queued here and dispatched by `setReady()` from the loadContent callback.
 *
 * The three start/stop/toggle actions are real. Android drives them through the
 * bound service; HarmonyOS drives them through `@ohos.net.vpnExtension`, which
 * is the same thing the main screen's status card uses. The controller API
 * still cannot represent them -- there is no `/start` or `/stop`, only
 * `POST /restart` -- so the tunnel is controlled locally rather than remotely.
 *
 * Two entry shapes reach those three actions:
 *
 *   - Android's action names, for callers that send an explicit `action`.
 *   - `clash://toggle` / `clash://start` / `clash://stop`, and the
 *     `clashAction` Want parameter, for the static app shortcuts declared in
 *     `resources/base/profile/shortcuts_config.json`. Shortcut `wants` can only
 *     carry `parameters`, never an action, so a parameter is the only way a
 *     launcher shortcut can name one of these.
 *
 * Every parse is deliberately contained. A malformed URI, a malformed
 * `parameters` object, or a missing profile must leave the app running and
 * must not change the normal Index launch path.
 */

import { common, Want } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { url } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { vpnExtension } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Profile, ProfileType } from '../model/ProfileModels';
import {
  ProfileStore,
  loadProfileStore,
  profileActive,
  profileByUUID,
  profileCreate,
  profilePatch
} from './ProfileStore';
import { ensureProfileDir } from './ProfileFiles';
import { vpnTunnelParameters } from './VpnSettingsStore';
import { isVpnRunning } from './VpnRuntime';
import { startVpnKeepAlive, stopVpnKeepAlive } from './VpnKeepAlive';
import { showToast } from '../util/Platform';

const DOMAIN: number = 0x0000;

/** A failed tunnel action is worth a log line even though the UI only toasts. */
function hilogError(message: string, error: Object): void {
  hilog.error(DOMAIN, 'testTag', '%{public}s: %{public}s', message, JSON.stringify(error));
}

/** `Intent.ACTION_VIEW`. */
export const ACTION_VIEW: string = 'android.intent.action.VIEW';

/**
 * HarmonyOS's data-view action. The Android action remains the primary name;
 * this alias lets a URI Want declared with `ohos.want.action.viewData` reach
 * the same parser.
 */
export const ACTION_VIEW_DATA: string = 'ohos.want.action.viewData';

/** `Intents.ACTION_TOGGLE_CLASH`. */
export const ACTION_TOGGLE_CLASH: string =
  'com.github.metacubex.clash.meta.action.TOGGLE_CLASH';

/** `Intents.ACTION_START_CLASH`. */
export const ACTION_START_CLASH: string =
  'com.github.metacubex.clash.meta.action.START_CLASH';

/** `Intents.ACTION_STOP_CLASH`. */
export const ACTION_STOP_CLASH: string =
  'com.github.metacubex.clash.meta.action.STOP_CLASH';

/**
 * Want parameter a static shortcut uses to name a start/stop/toggle request.
 * Shortcut `wants` cannot carry an action, only `parameters`.
 */
export const PARAM_CLASH_ACTION: string = 'clashAction';

enum ExternalRequestKind {
  ViewImportedProfile,
  ViewExistingProfile,
  OpenProfiles,
  Toggle,
  Start,
  Stop
}

interface ExternalRequest {
  kind: ExternalRequestKind;
  uuid: string;
  profileType: ProfileType;
  name: string;
  source: string;
  interval: number;
}

interface PropertiesRouteParams {
  uuid: string;
}

function emptyRequest(kind: ExternalRequestKind): ExternalRequest {
  return {
    kind: kind,
    uuid: '',
    profileType: ProfileType.Url,
    name: '',
    source: '',
    interval: 0
  };
}

export class ExternalControl {
  private context: common.UIAbilityContext;
  private ready: boolean = false;
  private pending: ExternalRequest | null = null;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  /**
   * Capture a Want from either onCreate or onNewWant.
   *
   * A cold-start request is queued until `setReady()`; a hot-start request is
   * dispatched immediately because the page stack already exists.
   */
  handleWant(want: Want): void {
    try {
      hilog.info(DOMAIN, 'testTag', 'external control want: action=%{public}s uri=%{public}s clashAction=%{public}s',
        `${want.action}`, `${want.uri}`, `${this.parameterValue(want, PARAM_CLASH_ACTION)}`);
      const request: ExternalRequest | null = this.parse(want);
      if (request === null) {
        return;
      }
      if (this.ready) {
        this.dispatchSafely(request);
      } else {
        this.pending = request;
      }
    } catch (error) {
      // A malformed Want is ignored. It must never escape onCreate/onNewWant.
    }
  }

  /**
   * Called after `windowStage.loadContent('pages/Index', ...)` succeeds.
   * Index remains the unconditional first page; an external request is pushed
   * on top of it once the page stack exists.
   */
  setReady(): void {
    this.ready = true;
    const pending: ExternalRequest | null = this.pending;
    this.pending = null;
    if (pending !== null) {
      this.dispatchSafely(pending);
    }
  }

  private parse(want: Want): ExternalRequest | null {
    // Checked before `action`: a launcher delivers a shortcut Want with no
    // action of its own (and some launchers add `ohos.want.action.home`), so
    // the parameter has to win over the action switch.
    const shortcut: ExternalRequest | null = this.parseShortcutAction(want);
    if (shortcut !== null) {
      return shortcut;
    }

    const action: string | undefined = want.action;
    if (action === undefined) {
      return null;
    }

    // Keep Android's `when (intent.action)` precedence: VIEW first, then
    // toggle, start, and stop.
    if (action === ACTION_VIEW || action === ACTION_VIEW_DATA) {
      return this.parseView(want);
    }
    if (action === ACTION_TOGGLE_CLASH) {
      return emptyRequest(ExternalRequestKind.Toggle);
    }
    if (action === ACTION_START_CLASH) {
      return emptyRequest(ExternalRequestKind.Start);
    }
    if (action === ACTION_STOP_CLASH) {
      return emptyRequest(ExternalRequestKind.Stop);
    }
    return null;
  }

  /** The `clashAction` parameter behind the static app shortcuts. */
  private parseShortcutAction(want: Want): ExternalRequest | null {
    const raw: string | undefined = this.parameterValue(want, PARAM_CLASH_ACTION);
    if (raw === undefined) {
      return null;
    }
    return this.actionRequest(raw.trim().toLowerCase());
  }

  /** `toggle` / `start` / `stop`, shared by the action and URI entry points. */
  private actionRequest(name: string): ExternalRequest | null {
    if (name === 'toggle') {
      return emptyRequest(ExternalRequestKind.Toggle);
    }
    if (name === 'start') {
      return emptyRequest(ExternalRequestKind.Start);
    }
    if (name === 'stop') {
      return emptyRequest(ExternalRequestKind.Stop);
    }
    return null;
  }

  private parseView(want: Want): ExternalRequest | null {
    const rawUri: string | undefined = want.uri;
    let openProfiles: boolean = false;

    let source: string | undefined = undefined;
    let uuid: string | undefined = undefined;
    let type: string | undefined = undefined;
    let name: string | undefined = undefined;
    let updateInterval: string | undefined = undefined;

    if (rawUri !== undefined) {
      const parsed: url.URL = url.URL.parseURL(rawUri);
      const scheme: string = parsed.protocol.endsWith(':')
        ? parsed.protocol.substring(0, parsed.protocol.length - 1)
        : parsed.protocol;
      const host: string = parsed.hostname;

      if (scheme !== 'clash' && scheme !== 'clashmeta') {
        return null;
      }

      // `clash://toggle` and friends: the URI form of the three actions, for
      // callers that can send a URI but not an Android action name.
      const byUri: ExternalRequest | null = this.actionRequest(host.toLowerCase());
      if (byUri !== null) {
        return byUri;
      }

      if (host !== 'install-config' && host !== 'profiles') {
        return null;
      }
      openProfiles = host === 'profiles';

      source = this.queryValue(parsed.params, 'url');
      uuid = this.queryValue(parsed.params, 'uuid');
      type = this.queryValue(parsed.params, 'type');
      name = this.queryValue(parsed.params, 'name');
      updateInterval = this.queryValue(parsed.params, 'update-interval');
    }

    // URI query parameters are the Android contract. Want parameters are the
    // HarmonyOS equivalent for callers that pass values outside the URI.
    if (source === undefined) {
      source = this.parameterValue(want, 'url');
    }
    if (uuid === undefined) {
      uuid = this.parameterValue(want, 'uuid');
    }
    if (type === undefined) {
      type = this.parameterValue(want, 'type');
    }
    if (name === undefined) {
      name = this.parameterValue(want, 'name');
    }
    if (updateInterval === undefined) {
      updateInterval = this.parameterValue(want, 'update-interval');
    }

    if (source !== undefined) {
      const request: ExternalRequest = emptyRequest(ExternalRequestKind.ViewImportedProfile);
      request.profileType = this.profileType(type);
      request.name = name === undefined ? this.defaultProfileName() : name;
      request.source = source;
      request.interval = this.intervalMillis(updateInterval);
      return request;
    }

    if (uuid !== undefined) {
      const request: ExternalRequest = emptyRequest(ExternalRequestKind.ViewExistingProfile);
      request.uuid = uuid;
      return request;
    }

    if (openProfiles) {
      return emptyRequest(ExternalRequestKind.OpenProfiles);
    }

    // `clash://install-config` without a URL has nothing to view, matching
    // Android's `?: return finish()` for a missing `url` query parameter.
    return null;
  }

  private queryValue(params: url.URLParams, name: string): string | undefined {
    const value: string | null = params.get(name);
    return value === null ? undefined : value;
  }

  /**
   * Read a string from Want.parameters without letting a malformed parameters
   * object throw. `parameters` is a Record, so this is a typed lookup rather
   * than dynamic property access on an interface.
   */
  private parameterValue(want: Want, name: string): string | undefined {
    try {
      const parameters: Record<string, Object> | undefined = want.parameters;
      if (parameters === undefined) {
        return undefined;
      }
      const value: Object = parameters[name];
      if (typeof value === 'string') {
        return value;
      }
    } catch (error) {
      // Malformed parameters are ignored.
    }
    return undefined;
  }

  /** Mirrors Android's `type?.lowercase() == "url" / "file"` mapping. */
  private profileType(raw: string | undefined): ProfileType {
    if (raw !== undefined && raw.toLowerCase() === 'file') {
      return ProfileType.File;
    }
    return ProfileType.Url;
  }

  /** Mirrors `uri.getQueryParameter("name") ?: getString(R.string.new_profile)`. */
  private defaultProfileName(): string {
    try {
      return this.context.resourceManager.getStringSync($r('app.string.new_profile').id);
    } catch (error) {
      return 'New Profile';
    }
  }

  /**
   * Mirrors Android's:
   *   val parsedInterval = ...toLongOrNull() ?: 0L
   *   val updateInterval = if (parsedInterval > 0) parsedInterval.coerceAtLeast(15L) else 0L
   *   TimeUnit.MINUTES.toMillis(updateInterval)
   */
  private intervalMillis(raw: string | undefined): number {
    if (raw === undefined || !new RegExp('^[+-]?\\d+$').test(raw.trim())) {
      return 0;
    }
    const parsed: number = Number(raw.trim());
    if (!Number.isSafeInteger(parsed)) {
      return 0;
    }
    if (parsed <= 0) {
      return 0;
    }
    return Math.max(parsed, 15) * 60000;
  }

  private dispatchSafely(request: ExternalRequest): void {
    try {
      this.dispatch(request);
    } catch (error) {
      // The port must not let an external-control request take down the app.
      this.notPorted();
    }
  }

  private dispatch(request: ExternalRequest): void {
    if (request.kind === ExternalRequestKind.ViewImportedProfile) {
      this.viewImportedProfile(request);
      return;
    }
    if (request.kind === ExternalRequestKind.ViewExistingProfile) {
      this.viewExistingProfile(request.uuid);
      return;
    }
    if (request.kind === ExternalRequestKind.OpenProfiles) {
      this.openProfiles();
      return;
    }

    // Android toggles/starts/stops the local VpnService; HarmonyOS does the
    // same through `@ohos.net.vpnExtension`, i.e. the main screen's status card
    // without the UI.
    this.controlTunnel(request.kind);
  }

  /**
   * `when (intent.action)` for the three tunnel actions, plus the toggle the
   * tile and the shortcut both ask for.
   *
   * Android answers "is it running?" with `StatusClient.currentProfile()`. This
   * port answers it with the marker `ClashVpnExtension` maintains; see
   * `VpnRuntime.ets` for why there is no platform call for it.
   */
  private controlTunnel(kind: ExternalRequestKind): void {
    if (kind === ExternalRequestKind.Stop) {
      this.stopTunnel();
      return;
    }
    if (kind === ExternalRequestKind.Start) {
      this.startTunnel();
      return;
    }
    if (isVpnRunning(this.context)) {
      this.stopTunnel();
    } else {
      this.startTunnel();
    }
  }

  /**
   * Android's `startClashService()`.
   *
   * The system shows the VPN trust dialog the first time and resolves the call
   * before the tunnel is actually up, so the toast reports that the request was
   * accepted -- the same thing Android's `Toast(external_control_started)`
   * means. A rejection is reported as-is unless the marker shows the tunnel is
   * already up, which is Android's "already running" branch.
   */
  private startTunnel(): void {
    const profile: Profile | undefined = profileActive(loadProfileStore());
    hilog.info(DOMAIN, 'testTag', 'external control start: profile=%{public}s',
      profile === undefined ? '<none>' : profile.uuid);
    if (profile === undefined) {
      this.toast($r('app.string.not_selected'));
      return;
    }

    // Read at start time rather than cached: the network-settings screen may
    // have changed these since the last run.
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
      startVpnKeepAlive(this.context);
      this.toast($r('app.string.external_control_started'));
    }).catch((error: Object) => {
      if (isVpnRunning(this.context)) {
        this.toast($r('app.string.external_control_started'));
        return;
      }
      hilogError('startVpnExtensionAbility failed', error);
      this.toast(`${error}`);
    });
  }

  /** Android's `stopClashService()`, which tolerates "was not running". */
  private stopTunnel(): void {
    vpnExtension.stopVpnExtensionAbility({
      bundleName: 'com.example.clashmeta',
      abilityName: 'ClashVpnExtension'
    }).then(() => {
      stopVpnKeepAlive(this.context);
      this.toast($r('app.string.external_control_stopped'));
    }).catch((error: Object) => {
      hilogError('stopVpnExtensionAbility failed', error);
      this.toast($r('app.string.external_control_stopped'));
    });
  }

  private viewImportedProfile(request: ExternalRequest): void {
    const store: ProfileStore = loadProfileStore();
    const profile: Profile =
      profileCreate(store, request.profileType, request.name, '');

    // Android's `patch(...)` immediately fills the record created above.
    profilePatch(store, profile.uuid, request.name, request.source, request.interval, '');

    // `ProfileManager.create()` also lays out the profile directory. Failure
    // here must not stop the editor from opening.
    try {
      ensureProfileDir(this.context, profile.uuid);
    } catch (error) {
      // The profile record is still valid; the file tree is best effort.
    }

    this.pushProperties(profile.uuid);
  }

  private viewExistingProfile(uuid: string): void {
    const store: ProfileStore = loadProfileStore();
    const profile: Profile | undefined = profileByUUID(store, uuid);
    if (profile === undefined) {
      this.openProfiles();
      return;
    }
    this.pushProperties(uuid);
  }

  private openProfiles(): void {
    this.pushUrl({ url: 'pages/ProfilesPage' });
  }

  private pushProperties(uuid: string): void {
    const params: PropertiesRouteParams = { uuid: uuid };
    this.pushUrl({ url: 'pages/PropertiesPage', params: params });
  }

  private pushUrl(options: router.RouterOptions): void {
    try {
      router.pushUrl(options).catch((error: BusinessError) => {
        this.notPorted();
      });
    } catch (error) {
      this.notPorted();
    }
  }

  private toast(message: ResourceStr): void {
    try {
      showToast(message);
    } catch (error) {
      // If the UI is not available yet, there is no toast surface to use.
    }
  }

  private notPorted(): void {
    this.toast($r('app.string.not_ported'));
  }
}
