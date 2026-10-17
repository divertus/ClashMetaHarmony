# The `codelinter` backend can never run, so precheck is permanently `ok:false`

**Kind:** bug · **Severity:** medium · **Affects:** `hmos-precheck`
`project-integrity` profile

## Summary

The `codelinter` backend looks for a `codelinter` executable on `PATH` or at
`<project>/codelinter/bin/codelinter`. DevEco Studio does not ship such an
executable — its linter exists only as an IDE plugin JAR. On a stock DevEco
install the backend therefore never runs, and because it is treated as
blocking, every `hmos-precheck` run ends `ok:false` regardless of the code.

## Where

`agents/scripts/hmos-precheck/backends/codelinter.mjs:8`

```js
const suffixes = process.platform.startsWith("win") ? ["codelinter.bat", "codelinter.cmd"] : ["codelinter"];
```

`agents/scripts/hmos-precheck/backends/codelinter.mjs:14` — also probes
`path.join(root, "codelinter", "bin", suffix)`.

`agents/scripts/hmos-precheck/backends/project_integrity.mjs:43` — additionally
wants a TypeScript copy at `<root>/codelinter/node_modules/typescript/lib/typescript.js`.

On the machine used for this port, DevEco ships:

```console
$ ls "/Applications/DevEco-Studio.app/Contents/plugins/codelinter/lib/"
instrumented-codelinter-26.0.0.461.jar

$ ls "/Applications/DevEco-Studio.app/Contents/tools/" | grep -i lint
(nothing)
```

## Impact

The practical damage is not the missing lint. It is that `ok:false` stops
carrying information. In this port the recorded precheck result was
`errorCount: 0` with `ok:false`, and the reason had to be written down by hand
as "known environment blocker" in every round. An agent that sees `ok:false`
every time learns to ignore the field, which defeats the gate for the failures
it *can* detect.

## Suggested fix

1. Make a missing tool an `unavailable` backend, not a blocking failure. The
   runner already has a vocabulary for this (`backend-unavailable`); use it for
   the *absence* of the tool and reserve blocking for the tool reporting
   problems.
2. If `codelinter` is genuinely required for a profile, say so in the profile
   name (`codelinter-diff`) and return a clear "not installed" result rather
   than a failure.
3. Document where the CLI is supposed to come from. If DevEco has no CLI, say
   that, and let users opt into a separately installed linter. Right now the
   skill implies it is part of the toolchain.
