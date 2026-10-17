# Locale-only strings produce `does not have a base resource` warnings after conversion

**Kind:** bug · **Severity:** low · **Affects:** `hmos-resources-convert`

## Summary

When a key exists only in a qualifier directory (`values-zh/strings.xml` and no
base `values/strings.xml`), the converter emits it into
`resources/zh/element/string.json` with no corresponding base entry. HarmonyOS
then warns on every build.

## Evidence

After converting ClashMetaForAndroid's resources, `hvigorw` reported 15
`does not have a base resource` warnings, all for keys present only in a
locale-qualified file. The affected keys are ones upstream added to a
translation without adding them to the default locale — `tun_stack_*` is a
representative example, which is also why those strings fall back to English at
runtime.

Android tolerates this (a missing translation falls back), and so does
HarmonyOS at runtime, but the build tool warns.

## Suggested fix

Two acceptable behaviours; pick one and make it explicit in the inventory:

1. **Emit a base entry.** For each key that only exists in qualifier dirs, also
   emit it into `base/element/*.json` using the first available value (or the
   default locale's). The app then has a defined fallback and the warnings stop.
2. **Drop and record.** Skip the key and write it to the inventory as
   `pending: no base value`, matching how the converter already treats
   unmappable types. This is more faithful to upstream but leaves the warning.

Either way the inventory should distinguish "converted with a base entry" from
"converted into a qualifier only", because that difference is currently
invisible until the build warns about it.
