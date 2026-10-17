/*
 * Local profile store.
 *
 * Ported from ClashMetaForAndroid:
 *   service/src/main/java/com/github/kr328/clash/service/ProfileManager.kt
 *   app/src/main/java/com/github/kr328/clash/util/Profile.kt   (`withProfile`)
 *
 * Android keeps two tables -- `Pending` (records the user is still editing) and
 * `Imported` (records that have been committed) -- plus one directory per
 * profile under `files/profiles/<uuid>/`. `queryAll()` is the union of the two,
 * deduplicated. This port collapses both into one list with an `imported` flag,
 * because the only thing that distinguishes them at the UI level is that flag
 * (`adapter_profile.xml` prints "Unsaved" and the menu hides Update/Duplicate).
 *
 * The record and its `files/profiles/<uuid>/` tree are separate: this store
 * keeps the record, `ProfileFiles` lays out the tree, and `ProfileFetch` writes
 * `config.yaml` into it. A record can therefore exist with an empty
 * `config.yaml`, which is exactly what Android's `Pending` row means before its
 * first successful `commit`.
 *
 * Persistence is deliberately shaped like `UiStore`: the class carries one
 * `@Trace` string and nothing else, and every operation is a free function that
 * decodes, mutates and re-encodes it.
 *
 * Two dead ends are worth recording, because both look reasonable:
 *   - storing `Profile[]` directly in a `@Trace` field never reached disk.
 *     PersistenceV2 does not round-trip an array of `@ObservedV2` instances, and
 *     with the array present the whole save was dropped -- including the string
 *     field next to it.
 *   - keeping the CRUD as methods on the store did not save either, even after
 *     the array became a plain field. The shape that works is the one `UiStore`
 *     already uses: one `@Trace` field, no other state, no methods.
 *
 * The consequence for callers: `profileAll()` builds fresh `Profile` objects on
 * every call, so list rows must be keyed by content as well as `uuid`
 * (`ProfilesPage.rowKey`), otherwise ArkUI would reuse a row for a record whose
 * fields changed.
 */

import { PersistenceV2 } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { Profile, ProfileType } from '../model/ProfileModels';

/** The wire form of one `Profile`; plain data, so JSON round-trips exactly. */
interface ProfileRecord {
  uuid: string;
  name: string;
  type: string;
  source: string;
  active: boolean;
  interval: number;
  updatedAt: number;
  imported: boolean;
  pending: boolean;
  ageSecretKey: string;
}

function toRecord(profile: Profile): ProfileRecord {
  return {
    uuid: profile.uuid,
    name: profile.name,
    type: profile.type,
    source: profile.source,
    active: profile.active,
    interval: profile.interval,
    updatedAt: profile.updatedAt,
    imported: profile.imported,
    pending: profile.pending,
    ageSecretKey: profile.ageSecretKey
  };
}

function fromRecord(record: ProfileRecord): Profile {
  const profile: Profile = new Profile();
  profile.uuid = record.uuid;
  profile.name = record.name;
  profile.type = record.type as ProfileType;
  profile.source = record.source;
  profile.active = record.active;
  profile.interval = record.interval;
  profile.updatedAt = record.updatedAt;
  profile.imported = record.imported;
  profile.pending = record.pending;
  profile.ageSecretKey = record.ageSecretKey;
  return profile;
}

/** Decode `encoded`; a corrupt blob reads as an empty list. */
function decode(encoded: string): Profile[] {
  try {
    const records: ProfileRecord[] = JSON.parse(encoded) as ProfileRecord[];
    return records.map((record: ProfileRecord) => fromRecord(record));
  } catch (error) {
    return [];
  }
}

function encode(profiles: Profile[]): string {
  return JSON.stringify(profiles.map((profile: Profile) => toRecord(profile)));
}

@ObservedV2
export class ProfileStore {
  static readonly KEY: string = 'ClashProfileStore';

  /** Serialised `Profile[]`; the store's only state, persisted by PersistenceV2. */
  @Trace encoded: string = '[]';
}

/** Load the persisted store, or create the default one on first run. */
export function loadProfileStore(): ProfileStore {
  const store: ProfileStore | undefined =
    PersistenceV2.connect(ProfileStore, ProfileStore.KEY, () => new ProfileStore());
  return store ?? new ProfileStore();
}

/**
 * Mirrors `ProfileManager.queryAll()`: every record, in insertion order.
 * `queryAllUUIDs()` on the two Android tables has no explicit sort, so the port
 * keeps creation order.
 */
export function profileAll(store: ProfileStore): Profile[] {
  return decode(store.encoded);
}

/** Mirrors `ProfileManager.queryByUUID(uuid)`. */
export function profileByUUID(store: ProfileStore, uuid: string): Profile | undefined {
  return profileAll(store).find((profile: Profile) => profile.uuid === uuid);
}

/** Mirrors `ProfileManager.queryActive()`. */
export function profileActive(store: ProfileStore): Profile | undefined {
  return profileAll(store).find((profile: Profile) => profile.active);
}

/**
 * Mirrors `ProfileManager.create(type, name, source, ageSecretKey)`: a
 * *pending* record (`imported = false`) with no auto-update interval.
 */
export function profileCreate(
  store: ProfileStore, type: ProfileType, name: string, source: string): Profile {
  const profile: Profile = new Profile();
  profile.uuid = util.generateRandomUUID(true);
  profile.name = name;
  profile.type = type;
  profile.source = source;
  profile.active = false;
  profile.interval = 0;
  profile.updatedAt = Date.now();
  profile.imported = false;
  profile.pending = true;
  profile.ageSecretKey = '';

  const profiles: Profile[] = profileAll(store);
  profiles.push(profile);
  store.encoded = encode(profiles);
  return profile;
}

/**
 * Mirrors `ProfileManager.patch(uuid, name, source, interval, ageSecretKey)`:
 * edits land on the record and leave it pending until it is committed.
 */
export function profilePatch(
  store: ProfileStore, uuid: string, name: string, source: string,
  interval: number, ageSecretKey: string): void {
  const profiles: Profile[] = profileAll(store);
  const profile: Profile | undefined = profiles.find((item: Profile) => item.uuid === uuid);
  if (profile === undefined) {
    return;
  }

  profile.name = name;
  profile.source = source;
  profile.interval = interval;
  profile.ageSecretKey = ageSecretKey;
  profile.pending = true;
  store.encoded = encode(profiles);
}

/**
 * The tail of `ProfileManager.commit(uuid)`: the record stops being pending and
 * its timestamp advances. Android also fetches the profile at this point; the
 * port splits that out into `ProfileFetch.applyProfile`, which calls this once
 * the download succeeds.
 */
export function profileCommit(store: ProfileStore, uuid: string): void {
  const profiles: Profile[] = profileAll(store);
  const profile: Profile | undefined = profiles.find((item: Profile) => item.uuid === uuid);
  if (profile === undefined) {
    return;
  }

  profile.imported = true;
  profile.pending = false;
  profile.updatedAt = Date.now();
  store.encoded = encode(profiles);
}

/**
 * The `updateInterval` half of `ProfileProcessor.apply`: when the subscription
 * response carries a `profile-update-interval` header, a brand-new profile
 * adopts it. Android applies it only when the record had no interval of its own
 * and had never been imported, so that stays the caller's decision -- this
 * function just writes the value.
 */
export function profileSetAutoUpdateInterval(
  store: ProfileStore, uuid: string, interval: number): void {
  const profiles: Profile[] = profileAll(store);
  const profile: Profile | undefined = profiles.find((item: Profile) => item.uuid === uuid);
  if (profile === undefined) {
    return;
  }

  profile.interval = interval;
  store.encoded = encode(profiles);
}

/** Mirrors `ProfileManager.setActive(profile)`; the flag lives in `ServiceStore`. */
export function profileSetActive(store: ProfileStore, uuid: string): void {
  const profiles: Profile[] = profileAll(store);
  for (const profile of profiles) {
    profile.active = profile.uuid === uuid;
  }
  store.encoded = encode(profiles);
}

/** Mirrors `ProfileManager.delete(uuid)`. */
export function profileRemove(store: ProfileStore, uuid: string): void {
  const profiles: Profile[] = profileAll(store)
    .filter((profile: Profile) => profile.uuid !== uuid);
  store.encoded = encode(profiles);
}

/**
 * Mirrors `ProfileManager.clone(uuid)`. Android copies the record with the same
 * name but forces `Type.File` and leaves it pending, so the copy shows up as an
 * unsaved profile -- the port reproduces that rather than inventing a nicer
 * name.
 */
export function profileClone(store: ProfileStore, uuid: string): Profile | undefined {
  const profiles: Profile[] = profileAll(store);
  const source: Profile | undefined = profiles.find((item: Profile) => item.uuid === uuid);
  if (source === undefined) {
    return undefined;
  }

  const copy: Profile = new Profile();
  copy.uuid = util.generateRandomUUID(true);
  copy.name = source.name;
  copy.type = ProfileType.File;
  copy.source = source.source;
  copy.active = false;
  copy.interval = source.interval;
  copy.updatedAt = Date.now();
  copy.imported = false;
  copy.pending = true;
  copy.ageSecretKey = source.ageSecretKey;

  profiles.push(copy);
  store.encoded = encode(profiles);
  return copy;
}
