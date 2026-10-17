# HomeTrans feedback — issues found while porting ClashMetaForAndroid

Everything here comes from one real port: ClashMetaForAndroid v2.11.35 ->
HarmonyOS NEXT (API 26), 17 of 20 activities, a working mihomo VPN/TUN data
path, verified on a HUAWEI Pocket 2. HomeTrans v0.1.20 was the workflow.

Each `issue-*.md` file is ready to file: the first line is the title, everything
after it is the body. Every claim has a file path plus a line number, or a
command whose output is quoted.

HomeTrans lives at <https://gitcode.com/SMAT/HomeTrans>, so `gh` will not reach
it. Either paste the body into a new issue there, or use the GitCode API.

## Index

| # | Kind | Title | Severity |
|---|---|---|---|
| 01 | bug | `npx --yes devecocli` always fails: that package does not exist on npm | high |
| 02 | bug | `hmos-precheck` imports `jsonc-parser` but the package does not declare it | high |
| 03 | bug | `ht init` copies `agents/scripts/**` without their dependencies | high |
| 04 | bug | The `codelinter` backend can never run, so precheck is permanently `ok:false` | medium |
| 05 | bug | `a2h_resource_convert.ts` header still lists XML-drawable→SVG as unimplemented | low |
| 06 | bug | Locale-only strings produce `does not have a base resource` warnings | low |
| 07 | enhancement | The self-test stage hard-depends on a paid external model key | medium |
| 08 | enhancement | No evidence standard for "the platform has no equivalent" claims | high |

## What worked well

Worth saying, because the issues below are all fixable and the shape of the
workflow is right:

- **The four-stage shape** (resources -> UI -> build -> verify) matched how the
  port actually had to go, and the per-stage artifacts (`inventory`,
  `mapping`, `records`) made the port auditable after the fact.
- **One converter instead of per-cell scripts.** The converter's own header
  says earlier runs had ten cells writing ten different scripts; the single
  implementation is why this port's resource step was reproducible. It ran
  2241 values entries + 52 drawables with zero failures.
- **`env-requirements.json` as a declarative tool check** is the right idea —
  it just needs to cover the packages the skills actually shell out to.
- **The "record what you could not do" convention.** Even where the skills had
  no answer, the project's docs convention (one markdown per finding, with
  file:line evidence) is what made these issues writable at all.

## Tool combination notes

See [`tool-combination.md`](tool-combination.md).
