# `a2h_resource_convert.ts` header still lists XML-drawable→SVG as unimplemented

**Kind:** bug (documentation vs. behaviour) · **Severity:** low · **Affects:**
`hmos-resources-convert`

## Summary

The converter's header block lists XML drawable conversion under
"尚未覆盖（后续期次，当前只登记为 pending，不静默丢弃）". The converter does
implement it. An agent reading the header will either skip drawables or write a
second script for them — which is exactly the duplication the file's own header
says it exists to prevent.

## Evidence

`skills/hmos-resources-convert/scripts/a2h_resource_convert.ts`, header:

```text
 * 覆盖范围（第一期）:
 *   - values/*.xml → base/element/*.json（string / color / float / integer / ...）
 *   ...
 *
 * 尚未覆盖（后续期次，当前只登记为 pending，不静默丢弃）:
 *   - XML drawable → SVG（vector / shape / layer-list / selector）
 *   - adaptive-icon → layered-image JSON + 纯色 PNG
 *   - 引用解析链、系统资源表、fallback
```

The implementation is in the same file, at line 421:

```ts
// XML drawable → SVG
```

with helpers at L429 (`#AARRGGBB` → SVG fill + opacity), L441 (`24dp` → SVG user
units), and qualifier handling for drawable dirs at L458.

Observed on a real run (ClashMetaForAndroid v2.11.35): **2241 values entries +
52 XML drawables converted to SVG, 0 failures.**

## Suggested fix

Move the drawable line into 覆盖范围 and delete it from 尚未覆盖. While there,
check the other two bullets — `adaptive-icon → layered-image` may also have
landed. Stale "not implemented" notes are more damaging than missing ones,
because they redirect the agent away from working code.

## Why this is worth fixing despite being "just a comment"

The whole point of collapsing ten per-cell scripts into one implementation was
reproducibility. That only holds if the single implementation's own description
is true. This is the cheapest possible fix with a direct effect on agent
behaviour.
