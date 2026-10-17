# `npx --yes devecocli` always fails: that package does not exist on npm

**Kind:** bug · **Severity:** high · **Affects:** `hmos-fix-build-errors`,
`hmos-integration-test`

## Summary

Ten command lines across two skills invoke `npx --yes devecocli ...`. There is
no npm package named `devecocli`, so every one of those commands fails before it
does anything. The real package is `@deveco/deveco-cli`; `devecocli` is only the
name of its `bin` entry.

## Steps to reproduce

```console
$ npm view devecocli version
npm error code E404
npm error 404 Not Found - GET https://registry.npmjs.org/devecocli - Not found

$ npm view @deveco/deveco-cli version
1.3.6
```

Same result on npmmirror. The other `npx --yes` packages the skills use do
resolve, so this is specific to `devecocli`:

```console
$ for p in homegraph a2h-resource arkanalysis devecocli; do printf '%-16s ' "$p"; npm view "$p" version 2>&1 | head -1; done
homegraph        1.6.1
a2h-resource     0.1.2
arkanalysis      0.1.0
devecocli        npm error code E404
```

## Where

`skills/hmos-fix-build-errors/SKILL.md`:

- L54 — "Use `npx --yes devecocli build` as the build entrypoint"
- L62 — "`devecocli build` exposes only `--product` / `--modules` / `--build-mode`"
- L106, L108, L112, L117 — the same command in the worked example
- L285 — "rerun `npx --yes devecocli build` so it can retry dependency install"

`skills/hmos-integration-test/SKILL.md`:

- L438 — `npx --yes devecocli device list`
- L441 — `npx --yes devecocli device list`

## Impact

These are not optional hints; they are the build and device steps. An agent
following the skill hits a 404 on its first real action and then improvises —
which is exactly what happened in this port. The agent ended up hand-rolling

```bash
u() { node <path>/node_modules/@deveco/deveco-cli/cli.js "$@"; }
```

and passing that wrapper to every later step. That works, but it is a workaround
the skill should not require the agent to invent, and it is invisible to
`env-requirements.json`'s tool checks.

## Suggested fix

1. Replace the command in all ten places. Because the bin name differs from the
   package name, the working form is:

   ```bash
   npx --yes @deveco/deveco-cli build      # bin: devecocli
   ```

   Pinning is worth it, since the CLI prints an update nag and its flags have
   changed across minor versions:

   ```bash
   npx --yes @deveco/deveco-cli@1.3.6 build
   ```

2. Better: define the resolution once instead of repeating a package spec in
   prose. Add `deveco-cli` to `env-requirements.json` with
   `aliases: ["devecocli"]` so `ht init` reports whether it is reachable, and
   have the skills call a single documented entrypoint rather than `npx`
   inline.

3. Consider shipping a `bin` shim named `devecocli` in the HomeTrans package
   that shells out to the real CLI. That keeps the skill text readable and
   makes the dependency one line in `package.json` instead of ten in prose.
