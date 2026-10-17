# Combining HomeTrans with other tools

Notes from one real port, on which combinations earned their place and which
gaps were filled by hand. The ordering matters more than the list: each tool is
authoritative for exactly one question, and the port went wrong whenever a
question was answered by a tool that only approximates it.

## Who is authoritative for what

| Question | Authoritative tool | Not authoritative |
|---|---|---|
| Does it compile? | `devecocli build` / `hvigorw` | an ArkTS semantic check |
| Is the ArkTS semantically valid? | `hmos-precheck --profile arkts-diff` (SDK `ets-loader`) | a text/regex scan |
| What does the app look like right now? | `devecocli ui layout` + `ui screenshot` | the source |
| Is the app actually running / is the tunnel up? | `hdc shell` (`ps`, `ifconfig`, `netstat`) | the app's own UI |
| What did the platform really do? | `hdc shell hilog -T <tag>` | the app's own logs |
| Does this API exist, and can we hold it? | SDK `.d.ts` + `PermissionDefinitions.json` | memory, or a blog |
| Is the binary ABI what we think? | `llvm-nm -D` / `llvm-readelf` | a successful link |

The two that paid for themselves most: **`hdc` for ground truth** (the UI said
"running" while `ifconfig vpn-tun` said the interface was gone — `hdc` was
right) and **`hilog` for causes** (the "VPN randomly dies" symptom was a
`FdLeakInfo` line naming the real cause, `fdcnt:24626`).

## Combinations that worked

**`devecocli ui` + `hdc` + `hilog`, in that order.** Drive an interaction with
`devecocli ui click`, confirm the screen changed with `ui layout`, then confirm
*why* with `hilog`. Using only the first two produces "the click did nothing"
when the truth is often "the click worked and something reverted it".

**`hmos-precheck` before `build`.** The semantic check is seconds and catches
things the compiler phrases badly. It does not replace the build; run both.

**SDK `.d.ts` as the API oracle, before writing any code.** Grepping
`$DEVECO_SDK_HOME/default/openharmony/ets/api/` answers "does this exist" and
"what shape does it have" in one step, and
`toolchains/lib/PermissionDefinitions.json` answers "can a normal app hold it".
This port's worst architectural error (concluding HarmonyOS has no VPN API)
would have been avoided by five minutes of this.

**`llvm-nm -D --defined-only` after every core rebuild.** The NAPI layer calls C
symbols by name. When the Go export surface changes and the prebuilt library is
stale, the failure mode is a link error that reads like a code error. Checking
the symbol list is cheaper than debugging the link.

**A log-diff harness across a restart.** `hilog -r`, restart, `hilog -T <tag>`
and compare. This is how the port learned that a 62 MB library was not the
problem but a leaked fd was, and later that a WebSocket was.

## Gaps that had to be filled by hand

**No device-side interaction diff.** The port needed to know "did tapping this
row change anything at all", across ~20 screens, and ended up writing its own
click audit: tap, `ui layout`, hash, compare. HomeTrans has
`tools/bfs-crawl/android_viewtree_bfs_crawler.ts` for the Android side but
nothing equivalent for "is this HarmonyOS screen's interaction dead". This is
the highest-value missing tool — it found a whole class of defects.

**No deterministic verification tier.** `hmos-integration-test` depends on an
external model key (see issue 07). Everything listed in "who is authoritative"
above can run without a model, and most real defects in this port were found
that way.

**No long-run stability check.** "VPN dies after ~90 s" is invisible to a
build and to a screenshot. A stage that runs the app for N minutes and watches
`ps` / `ifconfig` / `hilog -e FdLeak` would have caught it on day one instead of
after a hand-written investigation.

**No "did the platform refuse us" reporting.** Several APIs answer 201 and the
only way to learn that is to call them and read the error. A tiny helper that
probes a list of candidate APIs and prints `{api, code, message}` would turn
each of those investigations into one command.

## Concrete suggestions

1. **One CLI resolution point.** The skills invoke `npx --yes <pkg>` inline in
   33 places, one of which (`devecocli`) does not exist. Resolve external tools
   once, in a script, and have skills call that. It also makes
   `env-requirements.json` a real check instead of a parallel description.
2. **Make `env-requirements.json` cover every package the skills shell out to**,
   not just the system tools. Right now it verifies `node`/`adb`/`git`/`hdc` but
   not the three `npx` packages, which is where the failures actually are.
3. **Add a `verify` step to `ht init`** that runs each installed script's
   `--help` and reports pass/fail per skill. Both remaining install-time bugs
   would have been caught by it.
4. **Bundle the scripts** (esbuild is already a devDependency). Removing the
   module resolution problem removes issues 02 and 03 at once.
5. **Pair every "we could not do X" with a probe.** The report format already
   asks for what was not done; asking for the command that proved it is a small
   change that makes the claim checkable (see issue 08).

## A note on what not to add

The port did not benefit from more screenshot comparison, and it did not
benefit from larger skills. The eight `hmos-*` skills total ~325 KB of
instruction text, which is a lot of context for guidance that is largely
procedural. The wins came from tools that answer one question authoritatively,
not from more prose about how to do the work.
