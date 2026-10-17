/*
 * Domain model for the profile screens.
 *
 * Ported from ClashMetaForAndroid:
 *   service/src/main/java/com/github/kr328/clash/service/model/Profile.kt
 *   design/src/main/java/com/github/kr328/clash/design/ProfilesDesign.kt
 *   design/src/main/java/com/github/kr328/clash/design/PropertiesDesign.kt
 *   design/src/main/java/com/github/kr328/clash/design/NewProfileDesign.kt
 *   design/src/main/java/com/github/kr328/clash/design/model/ProfileProvider.kt
 *
 * Android keeps profiles in a SQLite database owned by the tunnel service and
 * reaches it through `withProfile { ... }`; this port has no service, so
 * `ProfileStore` holds the same records with PersistenceV2 instead.
 *
 * Fields that only exist because Android has a native core are kept but unused:
 * `upload` / `download` / `total` / `expire` come from the subscription's HTTP
 * headers and are read by `ProfileProcessor`, which has no counterpart here.
 * They are not modelled at all rather than carried around as dead state.
 */

/** Mirrors `Profile.Type`. The string values match the Android enum names. */
export enum ProfileType {
  File = 'File',
  Url = 'Url',
  External = 'External'
}

/**
 * One profile record.
 *
 * `@ObservedV2` + `@Trace` matters here: the list rows are keyed by `uuid`, so
 * ArkUI reuses the row component when a profile is replaced. Mutating the
 * existing instance is what makes the row update (same constraint the proxy
 * list hit -- see the `ForEach` note in `ProxyViewModel.mergeGroup`).
 */
@ObservedV2
export class Profile {
  /** `Profile.uuid`. */
  @Trace uuid: string = '';

  /** `Profile.name`. */
  @Trace name: string = '';

  /** `Profile.type`. */
  @Trace type: ProfileType = ProfileType.File;

  /** `Profile.source`: the URL for `Url`, the file path for `File`. */
  @Trace source: string = '';

  /** `Profile.active`; at most one profile has this set. */
  @Trace active: boolean = false;

  /** `Profile.interval`, in milliseconds; 0 means "no auto update". */
  @Trace interval: number = 0;

  /** `Profile.updatedAt`, in milliseconds since the epoch. */
  @Trace updatedAt: number = 0;

  /** `Profile.imported`: false while a new profile has not been saved yet. */
  @Trace imported: boolean = false;

  /** `Profile.pending`: the record has edits that were not committed. */
  @Trace pending: boolean = false;

  /** `Profile.ageSecretKey`; empty when unset. */
  @Trace ageSecretKey: string = '';
}

/**
 * The three built-in profile sources, in the order
 * `NewProfileActivity.queryProfileProviders()` lists them. Android appends one
 * entry per installed `ACTION_PROVIDE_URL` handler; HarmonyOS has no such
 * intent contract, so only the built-ins exist here.
 */
export enum ProfileProviderKind {
  File,
  Url,
  Qr
}

/** Requests raised by the profile list. Mirrors `ProfilesDesign.Request`. */
export enum ProfilesRequest {
  UpdateAll,
  Create,
  Active,
  Update,
  Edit,
  Duplicate,
  ShareQrCode,
  Delete
}

/** Requests raised by the profile editor. Mirrors `PropertiesDesign.Request`. */
export enum PropertiesRequest {
  Commit,
  BrowseFiles
}
