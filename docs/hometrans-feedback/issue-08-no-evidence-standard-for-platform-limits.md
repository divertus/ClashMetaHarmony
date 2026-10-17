# No evidence standard for "the platform has no equivalent" claims

**Kind:** enhancement · **Severity:** high (this one caused a wrong conclusion
that had to be retracted) · **Affects:** all `hmos-*` skills

## Summary

The skills let an agent write down "HarmonyOS has no equivalent for X" as a
conclusion without requiring evidence. That is the single most expensive kind
of error in a port, because it stops work on a capability that may well exist,
and it is not detectable later — there is no failing test for "we decided not
to try".

It happened in this port. An early round concluded:

> `VpnService` 在 HarmonyOS NEXT 没有公开等价 API —— Clash 式的 TUN 流量接管无法照搬

That is wrong. HarmonyOS has `VpnExtensionAbility` +
`@ohos.net.vpnExtension` (API 11+), and this port went on to build a working
TUN with it. The retraction is recorded in the project's own status doc as
"§21 更正：HarmonyOS **有** 三方 VPN/TUN 能力" — the wrong conclusion sat in the
document for several rounds and shaped the architecture ("this is only a
controller for a remote mihomo") before anyone re-checked it.

## Why the current guidance does not prevent it

Nothing in the skills asks for a citation. The closest thing is the general
instruction to be honest about what was not done, which is a *reporting* rule,
not an *evidence* rule. An agent can be perfectly honest and still be wrong.

## Suggested fix

Add one rule, to the shared part of the skills or to each skill's
"conclusions" section:

> A claim that the platform has no equivalent API must carry one of:
>
> 1. **SDK evidence** — the symbol is absent from the OpenHarmony and HMS
>    `.d.ts` trees, *and*, if a permission-gated API exists, its
>    `availableLevel` from `toolchains/lib/PermissionDefinitions.json` (with the
>    path). "It needs a system_basic permission" is a conclusion that requires
>    that file, not a recollection.
> 2. **Device evidence** — the exact `BusinessError` code and message returned
>    on a real device, quoted.
>
> If neither is available, the claim must be written as `unverified` and listed
> as an open question, never as a conclusion.

Two supporting details that make the rule cheap to follow:

- Both SDKs are local. `$DEVECO_SDK_HOME/default/openharmony/ets/api/` and
  `.../hms/ets/api/` can be grepped, and
  `.../toolchains/lib/PermissionDefinitions.json` answers the permission
  question directly. There is no excuse for guessing.
- The skills should distinguish "no such API" from "such an API exists but is
  closed to a normal signature". They have opposite consequences: the first
  means redesign, the second means ship a degraded path and record it.

## A worked example of the standard

From this port, for the app-enumeration case — this is the shape the rule
should produce:

```text
claim:      a third-party app cannot enumerate installed apps on API 26
sdk:        bundleManager.getInstalledBundleList is @permission
            ohos.permission.ENTERPRISE_GET_INSTALLED_BUNDLE_LIST
            (@ohos.bundle.bundleManager.d.ts:2076); that permission is
            availableLevel: system_basic in toolchains/lib/PermissionDefinitions.json
device:     getBundleNameByUidSync(uid) -> BusinessError 201
            "forbidden by permission: ohos.permission.GET_BUNDLE_INFO or
             ohos.permission.GET_BUNDLE_INFO_PRIVILEGED"
            even though GET_BUNDLE_INFO is granted (bm dump reports
            reqPermissionStates [0,0,0])
conclusion: closed to a normal signature; ship the manual path
```

Note that the device step is what turned a plausible SDK reading ("GET_BUNDLE_INFO
is `normal`, so the by-uid lookup should work") into the actual answer. SDK
reading alone was not enough, which is why the rule allows either form but
prefers both.
