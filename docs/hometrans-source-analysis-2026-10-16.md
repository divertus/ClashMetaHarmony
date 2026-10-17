# HomeTrans 源码分析

仓库：<https://gitcode.com/SMAT/HomeTrans>（BUAA SMAT Lab）
npm：`@buaa_smat/hometrans` v0.1.20 ｜ MIT ｜ 39 star / 67 fork
分析版本：commit `53f6e5d`（= remote HEAD，2026-10-15 活跃）
分析日期：2026-10-16

---

## 0. 一句话定性

**HomeTrans 不是一个转译器，也不是一个代码转换工具。它是一个用 Markdown 提示词编排的 LLM Agent 迁移流水线，外面套了一层"确定性护栏"。**

- 转换本身 100% 由 LLM 完成（读 Android 代码 → 写 ArkTS）；
- 真正的工程价值集中在**护栏**上：代码图约束阅读范围、决策契约约束设计空间、静态检查约束产物、编译器和真机约束收敛；
- **编排层没有代码**——`hmos-convert-pipeline` 是一个 486 行的 Markdown 提示词，"流程控制"是写给模型看的自然语言。

这正好落在上一轮调研里"路线 D：LLM/Agent 驱动的迁移工程"这个格子里，而且它的护栏做得比大多数同类项目认真。

---

## 1. 仓库解剖：代码 / 提示词 / 文档

克隆后逐目录统计（行数）：

| 类别 | 位置 | 行数 | 占比 |
|---|---|---|---|
| 官方文档摘录 | `skills/*/references/**` | 50,383 | ~59% |
| Skill 提示词本体 | `skills/*/SKILL.md` 等 | ~4,671 | ~5% |
| Subagent 提示词 | `agents/*.md` | 1,985 | ~2% |
| **可执行代码** | `skills/**/*.ts` + `agents/scripts/**/*.mjs` + `src/**` + `tools/**` | **25,129** | ~29% |
| 其中测试 | `*.test.mjs` | 2,742 | ~3% |

**关键观察：references 占了近 60%。** 那 5 万行是把鸿蒙官方的 MVVM / 状态管理文档（`@State`、`@Prop`、`@Link`、`@ObservedV2`、`@Trace`、`AppStorage`… 共约 50 个文件）抄进了仓库，供 Agent 按需加载。这是"把平台知识固化下来、不让模型自由回忆"的做法——手法对，但也说明它本质上是一个**提示词工程仓库**。

可执行代码的分布：

| 位置 | 行数 | 干什么 |
|---|---|---|
| `skills/**/scripts/*.ts` | 14,261 | UI 采集、Android view tree 解析、资源转换、测试运行 |
| `agents/scripts/hmos-precheck/` | ~4,040 | 确定性 ArkTS 静态检查 |
| `agents/scripts/platform_query.mjs` | 626 | 平台知识查询 |
| `src/cli/` | 2,653 | CLI 安装器（`ht init`） |
| `tools/bfs-crawl/` | 1,735 | Android 页面 BFS 爬取 |

---

## 2. 整体架构

### 2.1 分发模型

```
npm i -g @buaa_smat/hometrans
        ↓
    ht init          ← 交互式：选 editor、填 DevEco SDK 路径、填多模态模型 API Key
        ↓
把 skills/ 和 agents/ 复制进编辑器配置目录 + 写 ~/.hometrans/config.json + 落环境变量
        ↓
在 Claude Code / Cursor / Codex / DevEco Code / OpenCode / CodeBuddy 里用 /skill 调用
```

`ht init` 还会读 `env-requirements.json`（声明式环境依赖表）来检查每个 skill/agent 是 `OK` / `LIMITED` / `BLOCKED`。`tools[].source` 支持 `path`（which/where 探测）和 `env-dir`（目录存在性）两种，`hdc` 还配了 fallback：PATH 找不到就在 `<DEVECO_SDK_HOME>/default/openharmony/toolchains/` 里找。这个设计很细，值得抄。

### 2.2 两条迁移路径

项目提供**两条并列的入口**，对应两种截然不同的迁移诉求：

**路径 A：UI 迁移（`hmos-batch-ui-align`）**
批量把一个 App 的所有 Activity 页面转成 ArkTS 页面。靠真机采集的 view tree + 截图作为事实来源。

**路径 B：逻辑迁移（`hmos-spec-generate` → `hmos-test-case-generation` → `hmos-convert-pipeline`）**
按需求规格文档（`REQ.txt` / `REQ.xlsx`）逐条实现业务逻辑，跑完整流水线。

两者可以组合：先用 A 把页面铺出来，再用 B 把逻辑填进去。

### 2.3 流水线的八个阶段

```
Stage 1     Logic Development (Context Builder)   -> plan.md（决策契约）
Stage 1a    Logic Coding                          -> ArkTS 代码 + commit
Stage 2     Compilation and Build                 -> HAP
Stage 3     Code Review + Fix      [              -> code-review-report.md
Stage 3b    Rebuild after Review   ]  最多 2 轮
Stage 4     Self-Testing (真机)     [              -> self-test-report.md
Stage 4a    Self-Test Fix          |  最多 2 轮
Stage 4b    Rebuild after Fix      ]
            ---------------------------------
            人工验收（读 manifest + 真机走查）
```

每轮产物快照到 `review-round-N/` / `round-N/`，汇总写进 `pipeline-manifest.md`（含耗时表和缺陷表）。

---

## 3. 逐层拆解：它到底怎么工作

### 3.1 编排层——486 行提示词，不是代码

`skills/hmos-convert-pipeline/SKILL.md`（486 行）是整个项目的"主程序"，但它没有一行可执行逻辑。它的内容是：

- 9 个位置参数的解析规则（含"要传可选参数必须先显式给出前面所有可选参数"这种只有提示词才需要的规定）；
- 每个阶段要启动哪个 subagent、传哪些参数；
- 循环的终止条件（`all_passed` / `no_progress` / `max_rounds_reached`）；
- 报告字段怎么提取（"从 **Overview** 段提取 Total Defects Found…"）；
- 计时怎么记（`date -Iseconds` 取开始和结束，算 `H:MM:SS`）。

**这就是"提示词即流程引擎"。** 好处是零构建成本、随时改；代价见第 5 节。

### 3.2 上下文约束层——`homegraph` 代码图 + 决策契约

这是整个项目最值得学的部分。

**问题**：让 Agent 在几十万行的 Android 工程里找"这个功能在哪里实现"，它必然退化成 `rg` 乱搜、`find` 乱翻，然后上下文中毒。

**解法一：先用代码图索引。**
`npx homegraph init -i <android_project_dir>` 在工程内建 `.homegraph/` 语义索引，然后用 `callers` / `callees` / `impact` / `query` / `node` / `files` / `explore` 做结构化查询。`hmos-spec-generate` 里写得很强硬：

> **Hard fail policy** — `homegraph` 不可达或报错就停下报错，**"do NOT degrade to `Read` + `Grep`"**；没有索引不生成 spec，"the resulting spec would miss code-grounded scenarios"。

**解法二：明确禁止无界搜索。**
`agents/logic-context-builder.md` 里写着：

> Do not use `rg --files`, `find . -name`, unscoped `ls`, or feature-term search loops.

取而代之的是一个"内部 Read Frontier"协议：维护 `question` / `decision impact` / bounded `anchors` / `status`，每次只读**最上游且还能改变决策**的那个问题；读完必须 resolve / reject / narrow 其中之一，否则停止该搜索模式。

**解法三：先出决策契约，再写代码。**
Stage 1 的产物是一份很短的 `plan.md`，必须回答六个问题：`target surface`、`truth owner/source`、`access path`、`forbidden paths`、`completion evidence`、blocking `Unknown`。它遵循一条因果链：

```
requested outcome -> target surface/effect -> truth owner/source -> writer
  -> reader/consumer -> triggered edge paths -> protected non-target behavior
```

而 Stage 1a（`logic-coder`）的契约是**"execute the narrowed plan.md contract without reopening design choices"**——规划者决策，执行者不许重新讨论设计。这是很标准也很正确的"规划/执行分离"。

### 3.3 平台知识层——`platform_query.mjs`（626 行）

Agent 不知道鸿蒙 API 怎么写，怎么办？它不查本地 SDK，而是查一个 DeepWiki 索引：

```js
const DEEPWIKI_URL = 'https://mcp.deepwiki.com/mcp';
const DEEPWIKI_REPO = 'jjjzzz666/dev_kb_repo';
const DEFAULT_API_LEVEL = 22;
```

设计上有几个刻意的约束：

**a. 槽位化输出契约。** 不允许模型自由发挥，必须按固定槽位返回事实：

- planner 槽位：`feasibility`、`owner_boundary`、`forbidden_path`、`version_gate`、`protocol_variant`、`fallback_gap`、`blocking_unknown`、`completion_evidence`、`implementation_implication`
- coder 槽位：`exact_api`、`exact_import`、`return_error`、`context_permission`、`lifecycle_threading`、`local_forbidden`、`local_validation`、`planned_fallback`、`blocking_unknown`

**b. 硬性预算。** `OUTPUT CONTRACT`：最多 1800 字符、8 行，每行必须是 `- slot: fact`，超预算时优先保留 `blocking_unknown`、`conflicts` 和会改变决策的事实。

**c. 反污染。** 有一组 `PREFACE_PATTERNS` 用来剥掉模型的开场白（`you are asking` / `based on` / `here are` / `summary:` …），还有 `PROVIDER_FAILURE_PATTERNS` 用来识别查询失败而不是把失败当答案。`MAX_RETRIES = 2`。

**d. 权限声明。** Agent 侧明文写着：

> The query returns evidence, **not authority**. … Never search local SDK/DevEco paths.

把"查到的资料"和"有权威性的依据"分开，是这套提示词里少见的克制。

### 3.4 确定性检查层——`hmos-precheck`

约 4,000 行实现 + 2,742 行测试，是仓库里最"工程"的部分。规则清单在 `rules/rule_inventory.csv`，63 条规则，每条带完整元数据：

```
rule_id, group, scope, phase, kind, source_class, implementation_status,
confidence, oracle, default_mode, severity, fix_policy, inventory_status, notes
```

三种模式：`enabled`（生效）/ `shadow`（影子运行，只报告不拦截）/ `disabled`。

架构文档里有几条设计原则值得单独拎出来：

> **Evidence policy**: Backend or capability absence is `not_checked`/unavailable, **never success**. Malformed structured reports fail closed.
> Heuristic project and ArkUI rules **remain shadow until an independent oracle supports promotion**.
> Source mutation is not implemented and the CLI **rejects `--fix`**.

翻成工程语言：

1. **能力缺失时报"未检查"，绝不报"通过"**——这两者在 CI 里是天壤之别；
2. **启发式规则不进主流程**，只在影子模式跑，等有独立 oracle 验证过再提升为拦截规则；
3. **检查器绝不改代码**——发现问题交给 Agent 修，自己保持只读。

规则分层也很清楚：

- **委托给官方检查器**（`source_class=official_checker`，`implementation_status=delegated`）：`arkts.syntax-type`、`arkts.strict-rules`、`arkts.module-resolution`、`arkts.sdk-hms-types`。备注写着"Enumerate concrete SDK rule IDs from structured diagnostics; do not hardcode a partial list"——不重复实现编译器。
- **自己实现的确定性规则**：`page-file-exists`、`route-map-schema`、`route-target-exists`、`module-ability-src-entry-exists`、`permission-reason-resource`、`model-version-consistency` 等，都是工程结构一致性问题。
- **启发式规则（shadow）**：`sys-resource-name`、`page-entry-count`、`component-decorator-version`、`entry-build-root` 等 ArkUI 建模问题，备注普遍写"build oracle is still missing"。

另外有一个独立的 `runtime-risk/` 分析器专做 ArkUI V1/V2 状态管理风险（7 条规则，每条配 positive / near_negative / boundary / suppression 四类用例）：

```
v2-once-requires-param     @Once 没有配 @Param
v2-param-requires-require  @Param 未初始化
v1-v2-member-mix           V1 用了 V2 装饰器（或反之）
v1-timer-cleanup           setInterval 句柄未清理
v1-state-write-on-disappear  aboutToDisappear 里写状态
```

这些都是从**真实迁移**里总结出来的坑，不是凭空想的。

### 3.5 资源转换层——解码 APK，而不是读源码

`hmos-resources-convert`（891 行，最长的 skill）的核心判断：

> `a2h-resource` reads the APK's `resources.arsc` — the fully-merged resource table produced at build time — so its output is the **complete merged resource set** (source + all library/AAR resources merged in at build time).
> 源码 `res/` 兜底路径 "is missing library resources, so some resource references become unresolvable"。

这个选择是对的：Android 工程的很多资源来自 AAR 依赖，只读源码目录必然漏。

它还处理了两个容易被忽略的角落：

- **Compose 的图标没有资源文件**。`androidx.compose.material:material-icons-*` 是编译进 `classes*.dex` 的 `ImageVector` 对象，既不进 `res/` 也不进 `resources.arsc`，所以"every `res/`-based step is blind to them"。它去 dex 里捞出来再合成鸿蒙 media 资源。
- **SVG 保真度门禁**。原文说得很到位：

> A drawable whose `clip-path` was dropped, or whose stroke-only path was given a solid `fill`, still has the **correct file name** — so every page that references it will **pass Phase 5's reference checks and compile cleanly while rendering wrong**.

因此资源转换后、页面转换前设了一道 gate：报告里出现 `error` 级 SVG 保真问题，必须先把资源修好。这是"缺陷发现的时机决定返工成本"的典型正确判断。

### 3.6 UI 迁移层——view tree 提供数值，多模态模型做判断

**采集**：`page_capture.ts` / `page_capture_burst.ts` 是零依赖纯 Node 脚本，同时支持 ADB（Android）和 HDC（鸿蒙）两种设备，能连续采集多状态（约 1s 间隔）。`tools/bfs-crawl/android_viewtree_bfs_crawler.ts` 则从运行时 view tree 出发 BFS 遍历所有可达页面。

**对比**：这里有个值得注意的细节——**它不是像素级 diff**。流程是让多模态模型（配置里推荐 Qwen 视觉系列）分别读两边的截图 + view tree，各自产出一份 `UI_Analysis.md`（用表格列出每个组件的位置、颜色、icon、大小、形状、文字、对齐），**然后基于这两份分析文档做对比**，而不是直接对着原始截图比：

> You MUST Read the already-written `android_page_*/UI_Analysis.md` and `hmos_page_*/UI_Analysis.md` … **Do NOT generate the comparison from raw view trees, screenshots, or source code directly** — the comparison must be derived from the two Analysis documents.

（这也是应对"跨设备间距和截图色彩必然有差异"的办法。）

**约束**：两条硬规则反复强调，防止模型"看着差不多就行"：

> Every UI property and transition condition MUST reference a source code location. **No estimation from screenshots.**
> **Value tracing rule**: Before fixing any dimension/size/icon-size/alignment diff, you MUST trace the target value back to Android source code (layout XML `layout_width`/`layout_height`/`padding`/`src`, drawable intrinsic size, or style definition). … "looks about right" is **NOT acceptable**.

**批量优化**：`hmos-batch-ui-align` 还会先做"结构同构分组"——把同一个 Activity 在不同数据/语言下的多份采集（resource-id 集合相同，或只差列表项数量）合并成**一个工作单元**转换。理由写得很清楚：分开转会"re-derive a structure the first already resolved, at full cost, for no new structural information"。

### 3.7 构建 oracle——把编译器当判据，把错误沉淀成知识

`hmos-fix-build-errors` 负责"构建 -> 解析错误 -> 修 -> 重试"直到通过。它有两个细节值得注意：

**签名模式由工程自己决定，不由调用者要求。** 参数表里写：

> `--signed` 是 **assertion**，不是 request：构建模式由 `build-profile.json5` 决定；这个 flag 只是把"工程没配签名"从"正常出未签名包"变成"硬失败"。

**错误模式会自我沉淀。** `references/known-patterns.md` 带一行头注释：

> This file is **auto-maintained by `a2h-retrospect`**. … Last updated: 2026-03-27

内容是真实迁移中遇到的编译错误及频率，例如：

```
arkts-identifiers-as-prop-names   85 次   ValuesBucket computed property name
type mismatch (EventData)        16 次
arkts-no-untyped-obj-literals     9 次
```

来源标注是"AntennaPod V1 migration"。**这是整个项目里唯一一处"用真实运行数据喂回提示词"的机制**——"Fix the generator, not the output"的雏形。

### 3.8 设备测试层——用 AI Agent 驱动真机

`hmos-integration-test`（464 行）不生成测试脚本，而是把测试用例交给 `@autotest/agent`——一个**用 LLM 驱动设备 UI 的 Agent**（截图 -> 决策 -> 点击）。支持 single 模式（单模型）和 layered 模式（Planner + Executor 双模型）。

这部分工程细节最密，有几个真实痛点处理得很好：

**HAP / HSP 必须一次性安装。**
> In-app HSPs **cannot install standalone** — they depend on the main HAP — so every listed path is gathered and installed together in one `hdc install -r` transaction.

因此有了 `Package-Set Collection` 这套流程：用 `BUILD_START` 标记 + `find -newer` 过滤掉增量构建留下的陈旧产物；未签名 HSP 采用"全有或全无"策略——只要有一个模块产出了未签名 `.hsp` 就判定集合不完整并降级，理由是"a single unsigned package fails the whole `hdc install -r`, so the entry would never install"。

**区分"环境失败"和"应用缺陷"。**
测试报告里如果有 `status: FAIL` 哨兵行，或者压根没写出报告，就判定为 environmental failure（设备没连、API Key 没配、batch_runner 崩了），走 `agent_early_exit`，**不进修复循环**——因为"the fixer cannot address them"。这个区分很关键，否则 Agent 会去"修"一个根本不是代码问题的失败。

**诚实停止。**
循环的终止条件之一是 `no_confirmed_defects`：如果所有测试失败经白盒复核都判定为误报，就停下，理由是"no code was changed, so repeating the test would yield identical results"。

### 3.9 状态与报告层

- `OUTPUT/pipeline-manifest.md`：耗时表（每阶段 `H:MM:SS`）+ 缺陷表（发现/修复/未修复/轮数/停止原因）；
- 每阶段 `commit-info.md` 记录 commit hash；
- **`logic-coder` 明确禁止 `git add -A`**："Stage only plan-required files"；
- `Output Directory Guard`：默认输出目录落在鸿蒙工程内（`.hometrans/`），所以会主动写进 `.gitignore` 并用 `git check-ignore -q` 验证——防止迁移产物污染工程。

### 3.10 上下文隔离

`agents/self-tester.md` 是一个 55 行的"thin wrapper"subagent，存在的唯一理由是：

> Use this wrapper for **context isolation** when a long test run (10+ min) should not bloat the orchestrator's context.

而且它反复声明"Do NOT re-implement the procedure here… **the skill wins**"——避免提示词在两层之间漂移。这是很务实的做法。

---

## 4. 设计手法摘录（可直接复用到别的迁移项目）

| 手法 | 在 HomeTrans 里的体现 |
|---|---|
| 代码图代替自由搜索 | `homegraph` 索引 + 禁止 `rg --files`/`find`/无界 `ls` |
| 决策契约先于编码 | `plan.md` 六要素 + "coder 不得重开设计决策" |
| 槽位化 RAG 输出 | `platform_query.mjs` 的 planner/coder 槽位 + 1800 字符预算 |
| 证据不等于权威 | "The query returns evidence, not authority"、"Never search local SDK paths" |
| 缺能力报"未检查" | "absence is `not_checked`, never success"；报告畸形则 fail closed |
| 启发式规则先跑影子 | `shadow` 模式，等独立 oracle 才提升为拦截 |
| 检查器只读 | precheck 拒绝 `--fix`，改代码是 Agent 的事 |
| 用构建产物而非源码 | 解码 APK 的 `resources.arsc` 拿合并资源集 |
| 缺陷前置门禁 | SVG 保真度 gate 放在页面转换之前 |
| 数值回溯源码 | "Value tracing rule"——尺寸/对齐必须引用 Android 源码位置 |
| 编译器当 oracle | 构建循环 + `known-patterns.md` 自动沉淀错误频率 |
| 区分环境失败与缺陷 | `status: FAIL` 哨兵不进修复循环 |
| 有界循环 + 诚实停止 | `no_progress` / `no_confirmed_defects` / `max_rounds_reached` |
| 上下文隔离 | `self-tester` thin wrapper |
| 不污染目标工程 | 输出目录自动加 `.gitignore` 并验证 |

---

## 5. 弱点与风险

### 5.1 编排是提示词，不是代码——没有可执行的流程约束

`hmos-convert-pipeline` 的 486 行提示词里，那些"必须做 X""如果 Y 就停止"的规则**没有任何东西在强制执行**。模型漏读一段、跳过一个检查、把 `max_rounds_review` 理解错，都不会报错。

而且判断"这轮是否通过"的，正是**写报告的那个模型自己**：Stage 3 让 `code-reviewer` 读自己写的 `code-review-report.md` 提取 `Overall Verdict`，Stage 4 让流水线读自己写的 `self-test-report.md` 提取通过率。这是自我评价闭环。

对照上一轮调研里的 Porter：它把同样的循环用代码编排（文件契约 + schema 校验 + git worktree 分片 + "done" 从磁盘和 git 推导），HomeTrans 没有这一层。

### 5.2 评审者和修复者是同一个 Agent

`agents/code-reviewer.md` 明说：

> Because the review and the fixes are done by the same agent in the same pass, there is **no separate verification step** for reported issues — you found them directly, so **trust your own findings** and fix them.

这是有意识的设计取舍，但它放弃了独立验证。Porter 的核心主张恰好相反（"The implementer never reviews; reviewers never implement"，且评审者拿到的是 fresh、isolated 的上下文，并被要求**假定改动是错的**）。

### 5.3 自测用 LLM 驱动 UI，flaky，且有"软逃生门"

用视觉模型点屏幕做端到端测试，稳定性天然有限。项目对此的应对是：失败经"白盒复核"后如果判定为误报，就以 `no_confirmed_defects` 停止循环。这个机制设计上是合理的（环境问题不该触发代码修改），但它同时也是一个**可以让真实缺陷以"误报"身份被关闭**的路径，而判定者还是模型。

### 5.4 质量是未测量的

仓库里没有发布任何通过率、准确率、人工成本对比，也没有 eval harness。唯一的量化数据是 `known-patterns.md` 里的编译错误频率——那是**构建通过率**的代理指标，不是**迁移正确率**。

对比上一轮的 Xilantra skill，后者至少在 README 里承认"eval cases still need real-agent runs with and without the skill before claiming a measured pass rate"。HomeTrans 连这个声明都没有。

### 5.5 平台知识依赖外部的、不可审计的仓库

`platform_query.mjs` 硬编码了 `DEEPWIKI_REPO = 'jjjzzz666/dev_kb_repo'`。整个"鸿蒙 API 怎么写"的知识来源是这个个人名下的仓库，而这个仓库的维护者、更新节奏、内容来源、与官方文档的一致性，在本仓库里**没有任何说明**。

风险是双重的：如果它停更，Agent 会逐渐依赖过时的 API；如果它被改，HomeTrans 的行为会**在没有任何版本变更的情况下改变**。这是个明确的供应链/可复现性问题。

### 5.6 环境依赖重，且有一个断链

需要：DevEco Studio、Android Studio、Node >= 22.18、adb、hdc、npm 包（`homegraph`、`arkanalysis`、`a2h-resource`、`@autotest/agent`）、一个多模态模型 API Key。

其中**`devecocli` 在 npmjs 和 npmmirror 上都查不到**（我实测 404），但 skills 里大量使用 `npx --yes devecocli docs search` / `build` / `device list` / `log`。README 的徽章指向 `gitcode.com/openharmony-sig/deveco-cli`。也就是说这条路径需要用户额外配置 registry 或全局安装，**照文档的 `npx` 写法可能直接失败**。

### 5.7 测试覆盖的是"能测的"，不是"会坏的"

2,742 行测试集中在 `hmos-precheck`（规则准确性、输出契约、性能）和 `platform_query`。而流水线本身、提示词的行为、阶段间的交接——也就是**最容易出问题的地方**——完全没有测试，因为它没有可测的代码实体。

### 5.8 版本信号

包版本 v0.1.20，2026-08-17 首次发布，2 个月内迭代 20 个 patch，git 历史在当前镜像上只有 1 个 commit。属于**活跃但早期**的项目。

---

## 6. 对你的鸿蒙移植的实际建议

**可以用它做什么**

1. **直接拿来跑 UI 迁移**（`hmos-batch-ui-align`）是最稳的用法：资源转换（APK 解码 + SVG 保真 gate）、页面采集（ADB BFS + view tree）、同构分组这些环节都是真实工程量，自己重写不划算。
2. **借它的护栏思路**，而不是它的流水线：`homegraph` 约束阅读范围、`plan.md` 决策契约、`platform_query` 的槽位化输出、`known-patterns.md` 的错误沉淀——这几条可以独立移植到任何 Agent 迁移工程里。
3. **`hmos-precheck` 单独用**：它是纯静态、无副作用的，可以接进你自己的 CI，作为"Agent 改完之后的自动门禁"，比让模型自评可靠。

**需要自己补的**

1. **把编排从提示词搬进代码**。至少要有一个真脚本负责：跑哪一步、循环几次、什么时候停、产物写哪里。LLM 只做单步转换，不做流程控制。
2. **评审与修复分离**。让 reviewer 拿到 fresh 上下文和 diff，而不是让它审自己刚写的代码。
3. **换掉平台知识源**。把 `jjjzzz666/dev_kb_repo` 换成一个你能控制、能版本化的知识库（官方文档快照 + 你自己的实践沉淀），否则迁移的可靠性不由你决定。
4. **先确认 `devecocli` 怎么装**。否则 `hmos-fix-build-errors` 这条最关键的构建循环第一步就走不通。
5. **建自己的度量**。哪怕只是"10 个页面里几个一次编译通过、几个人工返工点"，也比没有数据强——`known-patterns.md` 那套 retrospect 机制可以复用来做这件事。

---

## 附：核实过的外部依赖

| 包 / 工具 | 版本 | 说明 | 备注 |
|---|---|---|---|
| `@buaa_smat/hometrans` | 0.1.20 | 本体 | npm |
| `homegraph` | 1.6.1 | Android 语义代码图，"surgical context, fewer tool calls, 100% local" | npm，MIT |
| `arkanalysis` | 0.1.0 | ArkTS commit 上下文提取器（改动行范围 + 调用链 + 引用资源） | npm，MIT，源码 <https://gitcode.com/dspedor/ArkAnalysis> |
| `a2h-resource` | 0.1.2 | 纯 Node 的 APK 资源解码器，读 `resources.arsc` | npm，Apache-2.0 |
| `@autotest/agent` | 0.0.25 | LLM 驱动的自动化测试执行 Agent，支持 HarmonyOS/Android/iOS | npm，MIT |
| `devecocli` | — | DevEco CLI（构建 / 设备 / 日志 / 文档检索） | **npmjs 与 npmmirror 均 404**，来源 <https://gitcode.com/openharmony-sig/deveco-cli> |
