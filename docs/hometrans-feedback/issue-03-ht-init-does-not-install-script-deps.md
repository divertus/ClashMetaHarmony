# `ht init` copies `agents/scripts/**` without their dependencies

**Kind:** bug · **Severity:** high · **Affects:** `ht init`

## Summary

`ht init` copies the agent scripts into the editor's config directory, but
nothing installs or vendors what those scripts import. The installed copy is
therefore broken in the same way as a fresh package install — and worse, it is
broken in a directory the user did not create and will not think to inspect.

## Evidence

After `ht init -a`:

```console
$ ls ~/.codex/agents/scripts/
hmos-precheck  platform_query.mjs  platform_query.test.mjs

$ ls ~/.codex/agents/scripts/hmos-precheck/
backends  core  docs  index.mjs  invocation.mjs  rules

$ ls ~/.codex/agents/scripts/node_modules
ls: No such file or directory
```

There is no `package.json` and no `node_modules` next to the scripts, yet
`~/.codex/agents/scripts/hmos-precheck/core/sdk_context.mjs:4` imports
`jsonc-parser`. Node resolves modules upward from the importing file, so the
copy under `~/.codex/` can only work if something happens to exist in a parent
directory of the user's home — which it does not.

## Steps to reproduce

```console
$ npx --yes @buaa_smat/hometrans init -a
...
$ node ~/.codex/agents/scripts/hmos-precheck/index.mjs --help
Error [ERR_MODULE_NOT_FOUND]: Cannot find package 'jsonc-parser'
```

## Impact

The user-visible effect is subtle and bad: the skills that call `hmos-precheck`
report failures that look like project problems. In this port the precheck
always came back `ok:false` with `project-integrity` unavailable, and it took
reading the script to learn that the cause was a missing dependency in the
installed copy, not anything in the project.

## Suggested fix

Pick one and make it explicit:

1. **Install at init time.** Generate a `package.json` next to the copied
   scripts and run `npm i --omit=dev` in that directory, then verify by running
   the entrypoint's `--help`. Report the result in the same summary that
   already lists BLOCKED / LIMITED / OK per skill.
2. **Vendor.** Since the scripts are meant to be small and dependency-light,
   bundling them (esbuild, which the package already depends on for its own
   build) removes the problem entirely. A single bundled `.mjs` per script has
   nothing to resolve.
3. **Fail loudly.** If neither is done, `ht init` should say the installed
   scripts are unusable rather than reporting success.

Option 2 is the one that makes the failure impossible, and it matches the
existing claim in `a2h_resource_convert.ts` that the converter uses only Node
built-ins.
