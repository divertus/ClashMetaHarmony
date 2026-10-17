# Profile subscription fetch on HarmonyOS

Scope: the `ProfileProcessor` half of ClashMetaForAndroid that turns a profile's
`source` into `<filesDir>/profiles/<uuid>/config.yaml`, ported so a real mihomo
core can later be pointed at that file.

## What Android does

`PropertiesActivity.verifyAndCommit()` and `ProfilesActivity`'s Update /
Update All both end in the same two steps:

1. `ProfileManager.patch(...)` writes the edited record.
2. `ProfileManager.commit(uuid)` / `update(uuid)` calls
   `ProfileProcessor.apply` / `.update`, which calls the native
   `Clash.fetchAndValid(path, url, force, callback)`.

`fetchAndValid` is one native call that does four things
(`core/src/main/golang/native/config/fetch.go`):

1. **Download** `source` into `<path>/config.yaml` (unless the file already
   exists and `force == false`; the caller passes `force = type != File`).
   `http`/`https` go through mihomo's `HttpRequest` with
   `User-Agent: ClashMetaForAndroid/<versionName>`; `content://` goes through the
   Android `OpenContent` bridge. A 60s context timeout applies.
2. **Read the subscription headers**: `subscription-userinfo`
   (`upload`/`download`/`total`/`expire`) and `profile-update-interval` (hours,
   clamped up to 15 minutes).
3. **Walk the parsed YAML** and download every provider with a `url` + `path`,
   reporting progress per provider.
4. **Parse the configuration** to reject an invalid file.

## What the port does

`entry/src/main/ets/backend/ProfileFetch.ets` reproduces steps 1 and 2 --
everything that does not need mihomo -- and stops there:

| Step | Port status |
| --- | --- |
| Download `source` -> `config.yaml` | done (`http` / `https`) |
| `User-Agent: ClashMetaForAndroid/2.11.35` | done |
| 60s read timeout | done (`READ_TIMEOUT_MS`) |
| `subscription-userinfo` parsing | done, mirrors `provider.NewSubscriptionInfo` |
| `profile-update-interval` parsing | done, mirrors `parseProfileUpdateInterval` |
| Provider downloads (step 3) | **not ported** -- see below |
| YAML validation (step 4) | **not ported** -- see below |
| age decryption | **not ported** -- see below |
| `content://` sources | **not ported** -- reported as unsupported |
| Core reload after commit | **not ported** -- no core yet |

### Honest degradations

**Provider downloads (step 3).** Not implemented. mihomo downloads a provider
itself when it loads the configuration, and the Android core's own comment says
the eager fetch is only kept "due to historical reasons... we don't need to
extract the file here; the core will do it". So nothing is lost once the core
runs; a provider is simply fetched later than on Android.

**YAML validation (step 4).** Not implemented. There is no YAML parser in this
project (`oh-package.json5` has no dependency for one, and writing a YAML parser
by hand is out of scope for this change). A profile that mihomo would reject
therefore still lands on disk with an `Ok` status. The failure surfaces when the
core loads it. No UI string claims the configuration was verified.

**age decryption.** Not implemented. Android calls
`Clash.setAgeSecretKey(...)` and lets the core decrypt the `--age` payload. The
port writes whatever the server returned to `config.yaml` verbatim, so an
encrypted subscription produces a file the core cannot parse. `ageSecretKey` is
still stored on the record (`ProfileStore`), so the value survives for a core
that can use it. `PropertiesPage` already documents that its age-key validator
is a no-op because `Clash.veritySecretKeys` is JNI.

**`content://` sources.** Android's `OpenContent` bridge has no headless
equivalent here; `fileIo` can read a picker URI, but only from a page that owns
the picker result, and the fetcher has no page. Such a source is reported as
`UnsupportedScheme` rather than silently writing an empty file.

**Core reload.** `commit` / `update` stop after the download. Android's
`ProfileProcessor` also hands the result to the tunnel service and schedules the
next auto-update (`ProfileReceiver.schedule`); neither exists yet.

### One deliberate deviation

`writeConfig` stages the body at `config.yaml.download` and renames it over
`config.yaml` only after the whole response arrived. Android truncates the real
file first and deletes it if the copy fails, which loses a working
configuration when the network drops mid-fetch. The rename gives the same end
state on success and keeps the previous file on failure.

## Wiring

| Caller | Behaviour |
| --- | --- |
| `PropertiesPage.commit()` (save button) | `File` -> `profileCommit` only, as on Android. `Url` / `External` -> `applyProfile`, which downloads, then commits. The toolbar swaps the save icon for a spinner and shows `format_fetching_configuration`; back is ignored while the fetch runs. A failure keeps the editor open on the pending record. |
| `ProfilesPage` row menu -> Update | `applyProfile` + `toast_profile_updated_complete` / `_failed`. |
| `ProfilesPage` toolbar -> Update All | `applyProfile` for every `imported && type != File` profile, in list order, one toast each (Android shows one per profile too). The toolbar button becomes a spinner. |

`applyProfile` also adopts the `profile-update-interval` header, but only for a
brand-new profile that had no interval of its own -- the same
`takeIf { old == null && interval == 0L }` condition Android applies.

## API

```ts
import { applyProfile, fetchProfileConfig, ProfileFetchResult,
         ProfileFetchStatus } from '../backend/ProfileFetch';

// download + promote the record (what commit/update call)
const result: ProfileFetchResult =
  await applyProfile(context, store, uuid);

// download only, leaving the record alone
const result2: ProfileFetchResult =
  await fetchProfileConfig(context, profile);
```

`ProfileFetchStatus`: `Ok`, `NotFetched` (a `File` profile), `EmptySource`,
`UnsupportedScheme`, `HttpError`, `NetworkError`, `WriteError`, `NotFound`.
`ProfileFetchResult.message` is `''` on success and carries the detail (an HTTP
status, an errno string, `Error.message`) on failure.

## Not verified

- No on-device run. Nothing here was exercised against a real subscription; the
  only check run was the ArkTS static precheck
  (`errorCount` 0 for these files, the one remaining error belongs to a
  different in-flight change).
- The `User-Agent` value is pinned to `ClashMetaForAndroid/2.11.35` (the version
  this port derives from) rather than read from the bundle. If a server is found
  to branch on the version, revisit.
- Whether the HarmonyOS net stack decompresses a gzip'd subscription body is
  assumed (the platform handles `Content-Encoding`), not measured.
- `subscription-userinfo` values are parsed and returned but nothing displays
  them yet: the usage block in `ProfilesPage` stays hidden, as it does on
  Android for a profile that has never been fetched.
