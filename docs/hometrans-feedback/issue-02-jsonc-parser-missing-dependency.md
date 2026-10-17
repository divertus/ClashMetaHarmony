# `hmos-precheck` imports `jsonc-parser` but the package does not declare it

**Kind:** bug · **Severity:** high · **Affects:** `hmos-precheck` (used by every
skill that runs the ArkTS check)

## Summary

Two files under `agents/scripts/hmos-precheck/` import `jsonc-parser`, but
`jsonc-parser` is not in `package.json`'s `dependencies`. A fresh install
therefore has a precheck that cannot start.

## Where

`agents/scripts/hmos-precheck/core/sdk_context.mjs:4`

```js
import { parse as parseJsonc } from "jsonc-parser";
```

`agents/scripts/hmos-precheck/backends/project_integrity.mjs:4` — the same
import.

`package.json` — `dependencies` is:

```json
{
  "@autotest/agent": "0.0.3",
  "@modelcontextprotocol/sdk": "^1.0.4",
  "chalk": "^5.6.2",
  "figlet": "^1.11.0",
  "fs-extra": "11.3.0",
  "inquirer": "^14.0.0"
}
```

No `jsonc-parser`.

## Steps to reproduce

```console
$ mkdir /tmp/ht && cd /tmp/ht && npm i @buaa_smat/hometrans
$ node node_modules/@buaa_smat/hometrans/agents/scripts/hmos-precheck/index.mjs --help
Error [ERR_MODULE_NOT_FOUND]: Cannot find package 'jsonc-parser'
    imported from .../hmos-precheck/core/sdk_context.mjs
```

It happens to work on a machine where `jsonc-parser` is already present higher
up the tree, which is why it is easy to miss.

## Impact

`hmos-precheck` is the semantic gate every other skill defers to. When it cannot
start, the gate silently disappears: agents fall back to text scanning or to
"the build passed", and the `ok:false` they eventually see has a cause
(missing `jsonc-parser`) unrelated to the code under test. In this port the
workaround was `npm i jsonc-parser` in the package directory by hand.

## Suggested fix

1. Add it: `"jsonc-parser": "^3.3.1"` in `dependencies`.
2. Add a smoke test to CI that installs the published tarball into an empty
   directory and runs `hmos-precheck --help`. `npm pack` + install + run is
   enough; this class of bug is invisible from inside the repo.
3. Audit the other `import` statements under `agents/scripts/` the same way.
   `hmos-resources-convert/scripts/a2h_resource_convert.ts` advertises "零第三方
   依赖，仅使用 Node 内置模块" — worth making that true for the whole
   `agents/scripts` tree and then asserting it, rather than fixing imports one
   at a time.
