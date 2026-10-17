# The self-test stage hard-depends on an external model key, with no offline path

**Kind:** enhancement · **Severity:** medium · **Affects:**
`hmos-integration-test`, `hmos-convert-pipeline` (stage 4)

## Summary

`hmos-integration-test` instructs the agent to stop and ask the user for
`HOMETRANS_MODEL_API_KEY` if it is not set. That key drives an external model
used to judge UI alignment. Without it the verification stage cannot run at
all, so a user who cannot or will not supply a key loses the last stage of the
pipeline — the one that is supposed to catch "it builds but it is wrong".

## Where

`skills/hmos-integration-test/SKILL.md:32`

```text
| `HOMETRANS_MODEL_API_KEY` | LLM api key (shared with UI alignment, set by `ht init`) | non-empty |
```

`skills/hmos-integration-test/SKILL.md:37`

```text
If `HOMETRANS_MODEL_API_KEY` is missing or empty, **stop and ask the user** to run `ht init` first.
```

`skills/hmos-convert-pipeline/SKILL.md:67` — the same dependency gates stage 4.

## Why it matters

The stages that need a model are the *judgement* ones (does this screen match,
does this look right). A large part of what a port needs to know is
*deterministic* and does not need a model at all:

- does the app still start, and is the process alive after N seconds
- does the page tree contain the labels the Android layout declares
- did the log gain a new error/warning line compared to the baseline
- did a tap on row X change the page at all (this port found several
  "click does nothing" rows this way)
- is the fd count / VPN tunnel still up after the test

Those checks caught more real defects in this port than any screenshot
comparison did.

## Suggested fix

Split the stage into a deterministic tier and a model tier:

1. **Deterministic tier (no key).** Run it always: launch, liveness, page-tree
   assertions from the Android layout's declared strings, log-diff against a
   baseline, and a "did the interaction change anything" check via viewtree
   hash. This tier alone would have caught the click-audit findings.
2. **Model tier (key).** Screenshot similarity and layout judgement. Skip with
   an explicit `skipped: no model key` in the report rather than aborting the
   run.

The report should always state which tier produced which verdict, so a
"passed" without a model key is not mistaken for a full pass.
