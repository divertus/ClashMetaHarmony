/*
 * Profile fetching -- the part of `ProfileProcessor` that runs before the core.
 *
 * Ported from ClashMetaForAndroid:
 *   service/src/main/java/com/github/kr328/clash/service/ProfileProcessor.kt
 *   core/src/main/golang/native/config/fetch.go            (`FetchAndValid`)
 *   core/src/foss/golang/clash/adapter/provider/subscription_info.go
 *
 * Android's fetch is `Clash.fetchAndValid`, one native call that (a) downloads
 * `source` into `<profile>/config.yaml`, (b) reads the subscription headers,
 * (c) walks the parsed YAML and downloads every provider, and (d) parses the
 * configuration to reject an invalid file. This port reproduces (a) and (b) --
 * the two steps that do not need mihomo -- and stops there:
 *
 *   - (c) provider downloads and (d) YAML validation are *not* implemented. The
 *     core does both itself when it loads `config.yaml`, and mihomo's own
 *     `FetchAndValid` already notes that pre-fetching a provider is only kept
 *     "for historical reasons". A profile mihomo would reject therefore still
 *     lands on disk here; the failure surfaces when the core loads it. Nothing
 *     in the UI claims the file was validated.
 *   - age decryption is not done while downloading: an encrypted subscription
 *     is written to `config.yaml` as the raw age payload, exactly like an
 *     unencrypted one. `ClashVpnExtension` passes the active profile's
 *     `ageSecretKey` to the core before `corePrepare`, and mihomo decrypts it
 *     inside `UnmarshalRawConfig`.
 *   - `content://` sources (Android's `OpenContent` bridge) have no HarmonyOS
 *     equivalent here: the fetcher runs headless, so the scheme is reported as
 *     unsupported rather than silently writing nothing. `fileIo` can read a
 *     picker URI, but only from a page that owns the picker result.
 *
 * Everything else mirrors Android: `http`/`https` only, the same
 * `ClashMetaForAndroid/<version>` User-Agent, a 60s read timeout, and
 * replacement of `config.yaml` with the downloaded body.
 */

import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { url, util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Profile, ProfileType } from '../model/ProfileModels';
import { ProfileStore, profileByUUID, profileCommit, profileSetAutoUpdateInterval } from './ProfileStore';
import { ensureProfileDir, profileRootDir, writeTextFile } from './ProfileFiles';

/**
 * `openUrl` in `fetch.go` sends
 * `"ClashMetaForAndroid/" + app.VersionName()`. The port is derived from
 * ClashMetaForAndroid 2.11.35, and subscription servers key their response
 * format off this prefix, so the string is pinned to the source version rather
 * than to the HarmonyOS bundle's own `versionName` (1.0.0). Sending `1.0.0`
 * would still start with the same prefix, but a server that echoes the version
 * back would then report a version the port does not implement.
 */
export const PROFILE_USER_AGENT: string = 'ClashMetaForAndroid/2.11.35';

/** `context.WithTimeout(context.Background(), 60*time.Second)` in `fetch()`. */
const READ_TIMEOUT_MS: number = 60000;

/** Android relies on the platform default here; 10s matches the controller client. */
const CONNECT_TIMEOUT_MS: number = 10000;

/** What `fetchProfileConfig` / `applyProfile` did. */
export enum ProfileFetchStatus {
  /** `config.yaml` was downloaded and written. */
  Ok,
  /** A `File` profile: Android fetches nothing because the file is local. */
  NotFetched,
  /** `source` is empty. */
  EmptySource,
  /** `source` is not `http`/`https` (this includes `content`). */
  UnsupportedScheme,
  /** The server answered with a non-200 status. */
  HttpError,
  /** The request threw: DNS, TLS, timeout, or no network. */
  NetworkError,
  /** The body could not be written to the profile directory. */
  WriteError,
  /** `applyProfile` was handed a uuid that is not in the store. */
  NotFound
}

/**
 * The subset of mihomo's `provider.SubscriptionInfo` this port reads, plus the
 * `profile-update-interval` header. `expire` and `updateInterval` are
 * milliseconds, matching the Android `FetchStatus` fields (mihomo sends
 * `expire * 1000`).
 */
export interface SubscriptionInfo {
  upload: number;
  download: number;
  total: number;
  expire: number;
  updateInterval: number;
}

/** The outcome of one fetch. `message` is `''` when there is nothing to add. */
export interface ProfileFetchResult {
  status: ProfileFetchStatus;
  /** Human-readable detail for the failure toast; `''` on success. */
  message: string;
  /** `url.Host`, for `format_fetching_configuration`. `''` when unparsable. */
  host: string;
  /** `null` when the response carried no subscription headers. */
  subscription: SubscriptionInfo | null;
  /** Size of the written `config.yaml`, in bytes. */
  bytes: number;
}

function result(status: ProfileFetchStatus, message: string, host: string,
  subscription: SubscriptionInfo | null, bytes: number): ProfileFetchResult {
  return {
    status: status,
    message: message,
    host: host,
    subscription: subscription,
    bytes: bytes
  };
}

/** `Uri.parse(source).scheme?.lowercase()` in `Pending.enforceFieldValid`. */
export function sourceScheme(source: string): string {
  const separator: number = source.indexOf(':');
  if (separator <= 0) {
    return '';
  }
  return source.substring(0, separator).toLowerCase();
}

/** `url.Host` as it appears in `Status.Args` for the fetch progress line. */
export function sourceHost(source: string): string {
  try {
    return url.URL.parseURL(source).hostname;
  } catch (error) {
    return '';
  }
}

/** `Error.message`, or `String(error)` for a thrown non-Error. */
function messageOf(error: Object): string {
  if (error instanceof Error) {
    return (error as Error).message;
  }
  return `${error}`;
}

/**
 * `provider.parseValue`: an integer, else a float truncated toward zero.
 * `undefined` replaces the Go error.
 */
function parseNumber(value: string): number | undefined {
  const trimmed: string = value.trim();
  if (/^[+-]?\d+$/.test(trimmed)) {
    const parsed: number = Number.parseInt(trimmed, 10);
    return Number.isSafeInteger(parsed) ? parsed : undefined;
  }
  if (/^[+-]?(\d+\.?\d*|\.\d+)$/.test(trimmed)) {
    const parsed: number = Number.parseFloat(trimmed);
    return Number.isNaN(parsed) ? undefined : Math.trunc(parsed);
  }
  return undefined;
}

/**
 * `provider.NewSubscriptionInfo`: lowercase, strip spaces, then read
 * `upload` / `download` / `total` / `expire` out of the `;`-separated pairs.
 * Unparsable fields are skipped, exactly as Go logs and continues.
 */
export function parseSubscriptionInfo(userinfo: string): SubscriptionInfo {
  const info: SubscriptionInfo = {
    upload: 0,
    download: 0,
    total: 0,
    expire: 0,
    updateInterval: 0
  };

  const normalised: string = userinfo.toLowerCase().replace(/ /g, '');
  for (const field of normalised.split(';')) {
    const separator: number = field.indexOf('=');
    if (separator < 0) {
      continue;
    }
    const name: string = field.substring(0, separator);
    const value: number | undefined = parseNumber(field.substring(separator + 1));
    if (value === undefined) {
      continue;
    }
    if (name === 'upload') {
      info.upload = value;
    } else if (name === 'download') {
      info.download = value;
    } else if (name === 'total') {
      info.total = value;
    } else if (name === 'expire') {
      // mihomo reports `info.Expire * 1000` to the UI layer.
      info.expire = value * 1000;
    }
  }
  return info;
}

/**
 * `parseProfileUpdateInterval`: the header is a count of hours, clamped up to
 * 15 minutes. A non-positive or unparsable value reads as "no interval".
 */
export function parseUpdateInterval(value: string): number {
  const hours: number | undefined = parseNumber(value);
  if (hours === undefined || hours <= 0) {
    return 0;
  }
  const interval: number = hours * 3600000;
  return interval < 900000 ? 900000 : interval;
}

/**
 * Case-insensitive header lookup. `HttpResponse.header` is typed `Object`, and
 * the net stack does not promise a particular casing, so the keys are compared
 * folded. A repeated header arrives as a list; the first value wins.
 */
function headerValue(header: Object, name: string): string {
  const map: Record<string, Object> = header as Record<string, Object>;
  const target: string = name.toLowerCase();

  for (const key of Object.keys(map)) {
    if (key.toLowerCase() !== target) {
      continue;
    }
    const value: Object = map[key];
    if (typeof value === 'string') {
      return value;
    }
    if (value instanceof Array) {
      const list: Object[] = value as Object[];
      if (list.length > 0 && typeof list[0] === 'string') {
        return list[0] as string;
      }
    }
  }
  return '';
}

/**
 * `writeFile` from `fetch.go`, with one deviation: the body goes to
 * `config.yaml.download` first and is renamed over `config.yaml` only after the
 * whole body arrived. Android truncates the real file and deletes it on a copy
 * error, which loses a working configuration when the network drops mid-fetch.
 * A rename is the same end state on success and keeps the previous file on
 * failure.
 */
function writeConfig(context: common.Context, uuid: string, body: string): number {
  const root: string = profileRootDir(context, uuid);
  const config: string = `${root}/config.yaml`;
  const staged: string = `${config}.download`;

  writeTextFile(staged, body);

  try {
    fs.renameSync(staged, config);
  } catch (error) {
    // `rename(2)` replaces the target on POSIX, but the sandbox wrapper is not
    // documented to, so the target is removed and the rename retried once.
    if (fs.accessSync(config)) {
      fs.unlinkSync(config);
    }
    fs.renameSync(staged, config);
  }

  return fs.statSync(config).size;
}

/** Remove the staging file, ignoring "already gone". */
function discardStaged(context: common.Context, uuid: string): void {
  const staged: string = `${profileRootDir(context, uuid)}/config.yaml.download`;
  try {
    if (fs.accessSync(staged)) {
      fs.unlinkSync(staged);
    }
  } catch (error) {
    // Nothing to clean up.
  }
}

/**
 * The `openUrl` + `fetch` half of `FetchAndValid`, for one profile.
 *
 * The caller is expected to have run `ensureProfileDir`; `applyProfile` does.
 */
export async function fetchProfileConfig(
  context: common.Context, profile: Profile): Promise<ProfileFetchResult> {
  // Android passes `force = type != Type.File`, so a File profile whose
  // `config.yaml` exists is never fetched. There is no source to fetch anyway.
  if (profile.type === ProfileType.File) {
    return result(ProfileFetchStatus.NotFetched, '', '', null, 0);
  }

  const source: string = profile.source.trim();
  if (source === '') {
    return result(ProfileFetchStatus.EmptySource, 'Empty url', '', null, 0);
  }

  const scheme: string = sourceScheme(source);
  if (scheme !== 'http' && scheme !== 'https') {
    // `content` lands here too; see the file header for why it is not opened.
    return result(ProfileFetchStatus.UnsupportedScheme,
      `Unsupported url scheme '${scheme}'`, sourceHost(source), null, 0);
  }

  const host: string = sourceHost(source);
  const header: Record<string, string> = {};
  header['User-Agent'] = PROFILE_USER_AGENT;

  const request: http.HttpRequest = http.createHttp();
  try {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: header,
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: READ_TIMEOUT_MS,
      expectDataType: http.HttpDataType.STRING,
      usingCache: false
    };

    const response: http.HttpResponse = await request.request(source, options);
    const code: number = response.responseCode;
    if (code !== 200) {
      return result(ProfileFetchStatus.HttpError, `HTTP ${code}`, host, null, 0);
    }

    const raw: string | Object | ArrayBuffer = response.result;
    let body: string = '';
    if (typeof raw === 'string') {
      body = raw;
    } else if (raw instanceof ArrayBuffer) {
      body = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(raw));
    }

    const userinfo: string = headerValue(response.header, 'subscription-userinfo');
    const intervalHeader: string = headerValue(response.header, 'profile-update-interval');
    let subscription: SubscriptionInfo | null = null;
    if (userinfo !== '' || intervalHeader !== '') {
      subscription = parseSubscriptionInfo(userinfo);
      subscription.updateInterval = parseUpdateInterval(intervalHeader);
    }

    try {
      const bytes: number = writeConfig(context, profile.uuid, body);
      return result(ProfileFetchStatus.Ok, '', host, subscription, bytes);
    } catch (error) {
      discardStaged(context, profile.uuid);
      return result(ProfileFetchStatus.WriteError, messageOf(error), host, null, 0);
    }
  } catch (error) {
    return result(ProfileFetchStatus.NetworkError, messageOf(error), host, null, 0);
  } finally {
    request.destroy();
  }
}

/**
 * `ProfileProcessor.apply`: lay out the profile directory, download the
 * configuration, then promote the record to imported. The provider walk and the
 * YAML parse from Android's `FetchAndValid` are the honest gap -- see the file
 * header.
 *
 * The record keeps its edits whether or not the download succeeds, matching
 * Android, where a failed `commit` leaves the pending record in place.
 */
export async function applyProfile(
  context: common.Context, store: ProfileStore, uuid: string): Promise<ProfileFetchResult> {
  const profile: Profile | undefined = profileByUUID(store, uuid);
  if (profile === undefined) {
    return result(ProfileFetchStatus.NotFound, 'Profile not found', '', null, 0);
  }

  try {
    ensureProfileDir(context, uuid);
  } catch (error) {
    return result(ProfileFetchStatus.WriteError, messageOf(error), '', null, 0);
  }

  const fetched: ProfileFetchResult = await fetchProfileConfig(context, profile);
  if (fetched.status !== ProfileFetchStatus.Ok) {
    return fetched;
  }

  // Android only adopts the header interval for a *new* record that had no
  // interval of its own:
  //   subscriptionInfo?.subUpdateInterval?.takeIf { old == null && interval == 0L }
  const wasImported: boolean = profile.imported;
  profileCommit(store, uuid);
  if (fetched.subscription !== null && fetched.subscription.updateInterval > 0
    && profile.interval === 0 && !wasImported) {
    profileSetAutoUpdateInterval(store, uuid, fetched.subscription.updateInterval);
  }

  return fetched;
}
