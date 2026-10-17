# iOS ⇄ Android 代码互转开源项目调研

调研日期：2026-10-16
方法：GitHub API / `gh` 直接核实仓库元数据 + 读一手 README、官方文档（skip.dev、kotlinlang.org、swift.org）。
所有 star 数、最近提交时间均为 2026-10-16 当日抓取。

---

## 0. 先给结论

**目前 GitHub 上没有一个成熟的、双向的、能端到端迁移整个工程的 iOS ⇄ Android 源码翻译器。** 这个结论不是印象，是逐项核实后的结果：

- 真正做「源码到源码翻译」的项目，要么已经废弃，要么只做单向，要么明确声明"不产出生产可用代码"。
- 能覆盖「整个项目移植」或「部分功能迁移」的开源方案，走的都不是"翻译"这条路，而是另外三条路（共享代码 / 互操作 / LLM Agent 工程）。
- 方向严重不对称：**iOS → Android 有 Skip 这样一个可用的真产品；Android → iOS 没有任何活的 Kotlin→Swift 翻译器**，只有 KMP 共享逻辑和互操作。

### 四条技术路线一览

| 路线 | 代表项目 | 能否整工程移植 | 能否部分功能迁移 | 本质 |
|---|---|---|---|---|
| A. 源码翻译（transpiler） | SwiftKotlin、Kotlift†、J2ObjC | 否 | 只能生成"草稿" | 语法映射，框架不映射 |
| B. 共享代码 + 双端原生 UI | Skip、KMP + Compose Multiplatform | 是（但需改架构） | 是，且这是最现实的增量路径 | 不是翻译，是"一次编写双端编译" |
| C. 互操作 / FFI | swift-java、SKIE、J2ObjC、Multi-OS Engine、RoboVM | 否 | 是（业务逻辑层） | 不改代码，让一端调用另一端 |
| D. LLM / Agent 驱动的迁移工程 | RepoTransBench+RepoTransAgent、AlphaTrans、Konveyor Kai、Porter、harmonyos-ai-migration-rules | 是（研究中/alpha） | 是 | 用 Agent 重写，靠测试和静态分析兜底 |

† Kotlift 已归档并明确弃用。

### 三条最关键的判断

1. **"翻译"解决不了工程迁移。** Swift 和 Kotlin 的语言层相似度确实高（SwiftKotlin 作者实测各层 50%–90% 代码相似），但 iOS/Android 的**框架层、生命周期、并发模型、内存模型、构建系统**几乎完全不同。任何只做语法映射的工具，产出都只是"草稿"，人力成本会从"写代码"变成"审代码"。
2. **真正可落地的开源方案是 Skip（iOS 优先）和 KMP（Android/Kotlin 优先）**，二者都要求你先接受一个架构约束，再谈迁移。Skip 的 Lite 模式产物是可读 Kotlin，理论上可以"生成一次然后 eject"——这是唯一一条用工具把 iOS 代码变成 Android 代码的实用路径。
3. **LLM Agent 路线在学术界已经成型，但工业级开源工程仍是 alpha。** RepoTransBench 提供了 1897 个仓库级样本和可执行测试；AlphaTrans（FSE 2025）用"逆向调用图分解 + 逐片段翻译 + 测试验证 + 重组"把整仓翻译做成了可验证流程。但它们的语言对里**没有 Swift/Kotlin**——移动端是这块的空白。

---

## 1. 逐个核实过的项目

### 1.1 源码翻译类（transpiler）

| 项目 | Star | 最近提交 | 协议 | 方向 | 状态判断 |
|---|---|---|---|---|---|
| [google/j2objc](https://github.com/google/j2objc) | 6,033 | 2026-10-15 | Apache-2.0 | Java → Objective-C | 活着，但**只做非 UI 代码** |
| [angelolloqui/SwiftKotlin](https://github.com/angelolloqui/SwiftKotlin) | 2,915 | 2021-07-07 | MIT | Swift → Kotlin | **事实停更**（最后一次 commit 2020-12-08，18 个 open issue） |
| [studoverse/Kotlift](https://github.com/studoverse/Kotlift) | 394 | 2023-03-04 | Apache-2.0 | Kotlin → Swift | **已归档**，README 首行写"deprecated in favour of Kotlin Multiplatform Mobile" |
| [okaxaki/objc2swift](https://github.com/okaxaki/objc2swift) | 272 | 2023-07-16 | — | Objective-C → Swift | 停更 |

**J2ObjC 的一手原话**（README）：

> "The goal is to write an app's non-UI code (such as application logic and data models) in Java."
> "J2ObjC does not provide any sort of platform-independent UI toolkit, nor are there any plans to do so in the future."
> "J2ObjC cannot convert Android binary applications. Developers must have source code."
> "J2ObjC is currently beta quality."

也就是说，连 Google 自家这个投入了十几年的项目，也明确放弃 UI 层，且至今仍是 beta。

**SwiftKotlin 的一手原话**（README）：

> "This tool **does not have as a goal to produce production ready Kotlin code**, but just a Kotlin translation that **will require manual editing**."
> "The scope of this project is not mapping all existing methods and data types to their Kotlin counterpart, but to translate the language itself."

它的实现方式是「字符串变换 + 部分结构化变换」（如 `guard` → 反向 `if`），不覆盖系统框架映射。作者在同仓库中给出的实测数据是：Swift/Kotlin 各层代码相似度 50%–90%（非 UI 依赖层复用率远高于 UIKit 依赖层），当年手工迁移耗时约为重写的 30%。

**Kotlift 的一手原话**（README）：

> "This library is deprecated in favour of Kotlin Multiplatform Mobile."
> "The program is not intended to support the full Kotlin or Swift language... All framework interfacing code from Android or iOS/Cocoa is not supported."
> "Kotlift uses various regular expressions and a simple structure tree."

支持版本停留在 Kotlin 1.0.1 / Swift 2.2。

**结论：路线 A 在移动端基本是死路。** 唯一还活着的 J2ObjC 主动放弃 UI，且只支持 Java→ObjC 单向。任何声称"一键 iOS 转 Android"的开源项目，核实下来都落在这个区间。

### 1.2 共享代码类（跨端框架）

| 项目 | Star | 最近提交 | 协议 | 方向 | 定位 |
|---|---|---|---|---|---|
| [skiptools/skip](https://github.com/skiptools/skip) | 3,240 | 2026-10-13 | MPL-2.0 | Swift → iOS + Android | **iOS 优先的完整双端方案** |
| [JetBrains/compose-multiplatform](https://github.com/JetBrains/compose-multiplatform) | 19,424 | 2026-10-15 | Apache-2.0 | Kotlin → 全平台 UI | Android 优先 |
| [touchlab/KaMPKit](https://github.com/touchlab/KaMPKit) | 2,453 | 2026-10-05 | Apache-2.0 | KMP 起步模板 | 官方推荐的 KMP 落地样板 |
| [touchlab/SKIE](https://github.com/touchlab/SKIE) | 1,335 | 2026-10-08 | Apache-2.0 | Kotlin ⇄ Swift 接口增强 | 解决 KMP 在 Swift 侧 API 丑陋的问题 |
| [Kotlin/kmp-production-sample](https://github.com/Kotlin/kmp-production-sample) | 2,284 | 2026-10-08 | Apache-2.0 | KMP 生产级示例 | 官方 |
| [swiftlang/swift-android-examples](https://github.com/swiftlang/swift-android-examples) | 569 | 2026-09-09 | Apache-2.0 | Swift 原生跑 Android | 官方示例 |
| [swiftlang/swift-java](https://github.com/swiftlang/swift-java) | 1,252 | 2026-10-15 | Apache-2.0 | Swift ⇄ JVM 互操作 | 官方，2025 年新项目 |

#### Skip 的技术路线（最关键的一个）

Skip 的 README 和官方文档给出了非常清晰的实现分层，**这是目前唯一一个把"Swift 工程变成 Android 工程"做成了产品的开源项目**：

**两种模式，按 Swift module 粒度选择：**

- **Skip Fuse（编译模式，官方推荐）**：用[官方 Swift SDK for Android](https://www.swift.org/blog/swift-6.3-released/#android) 把 Swift **原生编译**到 Android。完整 Swift 语言、stdlib、Foundation，通过 bridging 调用 Kotlin/Java API。
- **Skip Lite（转译模式）**：把 Swift 源码**转译成等价的 Kotlin 源码**，再交给标准 Kotlin 编译器。与 Kotlin/Java 生态互操作最好。

> 一手原话："It is not uncommon to use both compiled and transpiled modules within a single Swift-on-Android app."

**UI 层**：通过 [SkipUI](https://github.com/skiptools/skip-ui) 兼容框架，把 SwiftUI 映射到 **Jetpack Compose**。产物是真正的原生 Compose，不是 WebView、不是自绘引擎。

**官方给出的取舍（这部分很有价值，直接决定了能不能用在生产）：**

| | Fuse（编译） | Lite（转译） |
|---|---|---|
| 语言覆盖 | 完整 Swift | 大部分 Swift（泛型模式、运算符重载等映射不了） |
| 内存模型 | 保留 Swift 确定性析构 | JVM GC，语义不等价 |
| Kotlin/Java 调用 | 需要 bridging | 直接调用 |
| 包体积 | **+约 60 MB** | 较小 |
| 构建速度 | 慢 | 快 |
| 调试 | 难（原生代码） | 容易（可读 Kotlin + Android Studio 断点） |
| **可退出性（ejectability）** | **不能**——停用 Skip 后只剩 iOS 工程，Android 没有独立 Kotlin 代码库 | **能**——产出完整 Kotlin 源码，可脱离 Skip 独立演进 |

**关于"部分功能迁移"，Skip 有一条官方支持的路**（`/docs/project-types/`）：

> "A Skip project is a strict superset of a conventional SwiftPM package, and can be included as a dependency of any other Swift package regardless of whether or not they use Skip."

意思是：你可以只为**一个功能**建一个 Skip module，把它作为依赖挂进现有 iOS 工程。这样"从现有 iOS 工程中迁移一部分功能到 Android"就有了工程化的做法，而不是全量重写。

**授权**：官方 FAQ 明确"Skip is now completely free and open-source"，所有 Skip 库统一 MPL-2.0。历史版本曾是 LGPL + 静态链接例外。`SkipZero` 可以在 iOS 构建中完全移除 Skip 框架痕迹，不影响 App Store 过审。

#### KMP 的增量迁移路线

Kotlin 官方教程 [Make your Android application work on iOS](https://kotlinlang.org/docs/multiplatform/multiplatform-integrate-in-existing-app.html) 给出了标准的 brownfield 流程：

1. 判断哪些代码适合共享（经验法则：业务逻辑优先，UI 保持原生）
2. 建一个 KMP shared module
3. 让现有 Android 应用依赖它
4. 用 `androidLibrary {}` 而不是 `kotlin.android {}`，把它当库用
5. iOS 侧通过 [framework 集成](https://kotlinlang.org/docs/multiplatform/multiplatform-ios-integration-overview.html)：direct integration（Xcode build phase 脚本）、SwiftPM 本地包、CocoaPods、或远程 XCFramework

注意方向：**KMP 是 Android/Kotlin 优先**。它能解决"Android 代码共享给 iOS"，但不解决"把已有 Swift 代码变成 Kotlin"——Swift 侧代码仍然要人手重写成 Kotlin 才能进 shared module。

### 1.3 互操作 / FFI 类（"让一端直接跑另一端的代码"）

| 项目 | Star | 最近提交 | 协议 | 说明 |
|---|---|---|---|---|
| [multi-os-engine/multi-os-engine](https://github.com/multi-os-engine/multi-os-engine) | 597 | 2026-07-05 | Apache-2.0 | 用 Java/Kotlin 直接写 iOS App |
| [robovm/robovm](https://github.com/robovm/robovm) | 1,635 | 2023-12-18 | — | JVM 跑在 iOS 上，事实停更 |
| [codenameone/CodenameOne](https://github.com/codenameone/CodenameOne) | 1,881 | 2026-10-16 | — | 一套 Java 代码多端，自绘 UI |
| [swiftlang/swift-java](https://github.com/swiftlang/swift-java) | 1,252 | 2026-10-15 | Apache-2.0 | Swift ⇄ JVM 双向互操作，官方 |

这条路线**不翻译代码**，而是让一种语言直接调用另一种语言。它的价值在于：你可以把一端的业务逻辑层原样搬过去跑，而不必重写。代价是引入额外运行时、体积和调试复杂度，而且只覆盖非 UI 层。

### 1.4 LLM / Agent 驱动的迁移工程

这是过去两年增长最快的方向，也是回答"完整工作流工程"的关键。

| 项目 | Star | 最近提交 | 协议 | 定位 |
|---|---|---|---|---|
| [DeepSoftwareAnalytics/RepoTransBench](https://github.com/DeepSoftwareAnalytics/RepoTransBench) | 26 | 2025-11-18 | **无 license** | **仓库级代码翻译基准 + RepoTransAgent 框架** |
| [Intelligent-CAT-Lab/AlphaTrans](https://github.com/Intelligent-CAT-Lab/AlphaTrans) | 38 | 2025-12-20 | NCSA | FSE 2025，神经-符号整仓翻译与验证 |
| [konveyor/kai](https://github.com/konveyor/kai) | 86 | 2026-09-30 | Apache-2.0 | **静态分析 + LLM** 驱动的应用现代化（CNCF） |
| [openrewrite/rewrite](https://github.com/openrewrite/rewrite) | 3,794 | 2026-10-16 | Apache-2.0 | 大规模确定性源码重构（JVM 生态） |
| [ast-grep/ast-grep](https://github.com/ast-grep/ast-grep) | 16,245 | 2026-10-15 | MIT | AST 结构化搜索/重写，做 Agent 的确定性底座 |
| [biomejs/gritql](https://github.com/biomejs/gritql) | 4,609 | 2026-10-15 | MIT | GritQL：结构化迁移查询语言 |
| [comby-tools/comby](https://github.com/comby-tools/comby) | 2,685 | 2026-06-08 | Apache-2.0 | 结构化查找替换，支持几乎所有语言 |
| [leog25/porter](https://github.com/leog25/porter) | 1 | 2026-08-09 | MIT | **Agent 舰队跑整仓迁移的编排框架（alpha）** |
| [htk007/harmonyos-ai-migration-rules](https://github.com/htk007/harmonyos-ai-migration-rules) | 2 | 2026-04-04 | Apache-2.0 | 移动端迁移的 **AI 规则集/skill** |
| [Xilantra/skills](https://github.com/Xilantra/skills) | 0 | 2026-08-05 | MIT | **跨平台移植 Agent Skill**（iOS↔Android 等） |

注意 RepoTransBench 仓库**没有 license 文件**，直接复用其数据集和代码存在授权风险，作为方法论参考更稳妥。

#### RepoTransBench / RepoTransAgent

- 1,897 个真实仓库样本，13 个语言对，7 种语言（C、C++、C#、Java、JavaScript、Python、Rust、Matlab）
- 平均每样本 23,966 token / 2,394 行 / 177 个函数 / 35 个类
- 每个样本带**可自动执行的测试套件**（行覆盖 81.89%，分支覆盖 72.61%）
- RepoTransAgent 是基于 ReAct 的 Agent 框架，工具集为：`ReadFile` / `CreateFile` / `ExecuteCommand` / `SearchContent` / `Finished`

**关键空白：语言对里没有 Swift/Kotlin。** 移动端迁移在这套框架里是缺席的。

#### AlphaTrans（FSE 2025）——最值得借鉴的工程方法

它把整仓翻译拆成了可验证的流水线：

1. 按**逆向调用图顺序**（reverse-call graph order）把项目分解成片段
2. 逐片段翻译
3. 每片段做多重验证：语法正确性、GraalVM 正确性、测试执行正确性
4. 重组（recompose）成完整项目
5. 用 EvoSuite 生成测试来提升覆盖率验证

这个"分解 → 逐片翻译 → 逐片验证 → 重组"的形状，是所有严肃的迁移工程都会收敛到的结构。

#### Konveyor Kai——静态分析 + LLM 的工业级范式

CNCF 项目，README 原话：

> "An AI-enabled tool that simplifies the process of modernizing application source code to a new platform. It uses **Large Language Models (LLMs) guided by static code analysis**, along with **data from Konveyor**."

它的架构要点：静态分析器产出"待迁移问题清单"，LLM 只负责在**有约束、有上下文**的情况下解决问题，并且把已解决的迁移案例存进 MCP solution server 复用。这是"不要让模型自由发挥"思路的代表。

#### Porter——"Agent 舰队 + 对抗式评审"的整仓迁移编排

虽然只有 1 star 且是 alpha，但它的方法论值得单独看（它自称把 Bun 的 100 万行 Zig→Rust 重写方法泛化了）：

- 工作单元队列 → 实现者 → diff → **两个对抗式评审者**（只拿到 diff 和原始文件，被要求假定改动是错的）→ 修复者 → 单条 scoped commit
- "实现者从不评审，评审者从不实现"
- 一切皆文件契约：Agent 必须写 `RESULT.json`，框架按 schema 校验，失败则把校验错误回灌重试
- 用 git worktree 分片，每个迁移单元一个 commit，"完成"状态从磁盘 + git 推导，任何时刻可中断可恢复
- 阶段门禁：先写 RULEBOOK 并对抗评审 → 小规模 trial → 大规模迁移 → 用编译器/测试/冒烟作为 oracle 逐轮收敛（converge）
- 核心口号："Fix the generator, not the output."（改生成规则，而不是改产物）

#### 移动端专用的 AI 规则集 / Skill

**harmonyos-ai-migration-rules** 是 Android/iOS → HarmonyOS(ArkTS/ArkUI) 的规则集仓库。它解决的问题陈述得非常准确：

> "Developers learn platform differences through trial and error; AI assistants hallucinate HarmonyOS APIs without proper guidance; every team reinvents the same mapping tables and conversion patterns; migration knowledge stays locked in individual heads or internal wikis."

它提供 Claude skill / Cursor `.mdc` / Copilot instructions / Windsurf rules / Cline rules / 通用 system prompt 六种接入形态，内容是按平台差异整理的组件映射、API 对照、架构模式、反模式、验证清单。

**Xilantra 的 `cross-platform-app-port` skill** 是直接针对 iOS↔Android 的 Agent Skill。它的立场很明确，值得引用：

> "Rebuild the product for the target platform. Preserve verified behavior, data semantics, and visual intent. **Do not translate source code line by line** or reproduce source technical debt without a documented reason."
> "Do not use it for... automatic source-to-source syntax translation."

它的工作流是：定义移植范围 → 刻画已验证行为 → 把"产品真相"和"源技术债"分离 → 映射目标平台等价物 → 先做**一个**目标平台垂直切片 → 构建/测试/截图/对比 → 不通过则归类 gap 回到上一步 → 记录证据和迁移状态 → 进入下一个切片 → 人工审批后才合并。

注意 README 里的自我披露："The included eval cases still need real-agent runs with and without the skill before claiming a measured pass rate." —— 也就是说它自己也没做过对照实验。

---

## 2. 四条路线的技术本质

### 路线 A：源码翻译

**做法**：解析源语言 AST → 映射到目标语言 AST → 生成代码。

**为什么在移动端失败**：

1. 语言映射只覆盖语法。`array.append()` → `array.add()` 这种能自动改，但 UIKit → Compose、CoreData → Room、GCD → Coroutines、Swift ARC → JVM GC 都改不了。
2. 移动端的"代码量"大头在 UI 和平台集成，而这恰恰是框架差异最大的部分。J2ObjC 直接放弃 UI 不是偷懒，是判断。
3. 构建系统、资源、签名、权限模型完全不同，翻译器管不到。

**残余价值**：作为 Agent 的**确定性前处理层**仍然有价值——把纯算法/数据模型/序列化这类框架无关的代码自动翻掉，让人和模型只处理框架层。

### 路线 B：共享代码 + 双端原生 UI

**做法**：把业务逻辑抽到一个共享 module，UI 各写各的（或 UI 也共享）。

**变体**：
- Skip：Swift 源码 → 双端。UI 通过 SkipUI 映射到 Compose。
- KMP + Compose Multiplatform：Kotlin 源码 → 双端。UI 可以是共享 Compose 或各自原生。
- KMP + 原生 UI（官方推荐默认）：只共享逻辑，UI 用 SwiftUI / Jetpack Compose 各写。

**这是唯一能真正"覆盖整个工程"的开源路线**，但代价是接受架构约束。它不叫迁移，叫**重构 + 收敛**。

### 路线 C：互操作 / FFI

**做法**：不改代码，让一端直接调用另一端编译出的库。

**典型**：KMP 的 iOS framework、SKIE、swift-java、J2ObjC（反向：Java 编译成 ObjC 后链进 iOS 工程）、Multi-OS Engine。

**适用**：业务逻辑层、算法、网络、数据模型。**不适用**：UI、平台服务。

### 路线 D：LLM / Agent 驱动

**做法**：Agent 读源码 → 理解语义 → 在目标工程里重写 → 用编译器/测试/截图做验证 → 迭代。

**关键技术组成**（把上面几个项目拼起来看，形状非常一致）：

1. **分解**：把整仓拆成可独立验证的单元（AlphaTrans 用逆向调用图；Xilantra skill 用"垂直切片"）
2. **约束**：用规则集 / RULEBOOK / skill 把平台差异固化成可复用知识（harmonyos-ai-migration-rules、Porter 的 RULEBOOK）
3. **确定性底座**：AST 结构化重写处理机械部分（ast-grep、GritQL、Comby、OpenRewrite）
4. **静态分析**：产出待迁移问题清单，让 LLM 有的放矢（Konveyor Kai）
5. **验证 oracle**：编译器、测试套件、冒烟命令、截图对比（RepoTransBench 的可执行测试、Porter 的 converge、Xilantra 的 parity gate）
6. **对抗式评审**：独立上下文审查 diff（Porter）
7. **状态与可恢复性**：`MIGRATION_STATE.json`、git worktree 分片、scoped commit
8. **人工门禁**：不可逆动作前必须人工批准（Xilantra skill 第 13 条）

---

## 3. 三种工作方式对比

### 3.1 裸 AI Agent（直接把 iOS 代码丢给 Claude Code / Codex / Cursor 让它转）

**好处**

- 零搭建成本，立刻能用
- 通用模型见过大量 iOS/Android 代码，对常见模式的映射直觉不差
- 能处理"框架差异"这类静态工具完全做不到的语义问题
- 灵活：任何技术栈、任何方向都能试

**坏处**

- **没有范围定义**：模型不知道"迁移"的边界在哪，容易把源工程的坏设计一起搬过去，或者顺手"改进"导致行为漂移
- **没有验证闭环**：模型说"改完了"，你只能靠人肉 review。整仓规模的幻觉会累积
- **上下文耗尽**：一个真实 App 的 iOS 工程远超单次上下文，模型看不到的部分就是盲区
- **不可恢复**：中断了要重来，没有状态机
- **知识不沉淀**：同一个平台差异，每个开发者、每次会话都要重新教一遍
- **成本不可控**：没有分片和 trial 机制，容易把预算烧在系统性错误上反复重试

### 3.2 AI Agent + Skill（把迁移方法论写成 skill）

**好处**

- **约束行为**：skill 明确"不要逐行翻译""保持行为不保持实现""不要静默改变用户可见行为"，这是裸 Agent 最容易犯的错
- **固化平台知识**：组件映射表、API 对照、反模式清单写一次，所有会话复用，直接消除 harmonyos-ai-migration-rules 里说的"每个团队重新发明映射表"
- **流程可复现**：分解 → 切片 → 验证 → 记录，形状固定，不同人跑出来结果一致
- **状态可恢复**：`MIGRATION_STATE.json` 这类产物让跨会话、跨人接手成为可能
- **有验证门禁**：parity gate、截图对比、构建/测试必须通过才进下一步
- **成本低**：不需要写代码，一个 Markdown 文件就能起步

**坏处**

- **Skill 只是提示词，不是执行器**。它约束不了模型的实际行为，也保证不了产物正确性——Xilantra 自己在 README 里承认 eval 还没做对照实验
- **没有确定性层**：机械的、重复的改写（比如 500 处 `append` → `add`）仍然靠模型逐个生成，又慢又不稳定
- **没有真正的编排**：串行、失败重试、预算控制、并行分片都得靠模型自己"记得"
- **没有仓库级索引**：Agent 还是靠 grep/read 找文件，大工程容易漏
- **生态上还很空**：我查了 skills.sh 注册表，`ios-design` 有 33 万安装、`mobile-android-design` 2.4 万、`argent-ios-simulator-setup` 2.4 万，但**没有一个高安装量的 iOS↔Android 代码移植 skill**。也就是说这条路目前没有经过大规模实战验证的公开资产

### 3.3 专用迁移工程（把上面的东西组装成流水线）

**好处**

- **有确定性层**：AST 重写（ast-grep / GritQL / Comby / OpenRewrite）处理机械部分，又快又不会漂移，模型只处理真正需要理解的部分
- **有静态分析做导航**：先产出问题清单，再让模型逐个解决（Konveyor Kai 的范式），避免"漫游式"改代码
- **有真实 oracle**：编译器、测试套件、冒烟脚本、截图对比是客观判据，不依赖模型自评
- **可编排**：分片、并行、失败重试、预算门禁、trial 先行（Porter 的 playbook → trial → mass → converge）
- **可对抗评审**：独立上下文的 reviewer 只看到 diff，被要求假定改动是错的——这能抓出模型自评抓不出的问题
- **可恢复、可审计**：每个单元一条 commit，带评审归属，状态从磁盘 + git 推导
- **知识可迭代**：系统性错误出现时改 RULEBOOK 重跑，而不是逐个修产物（"Fix the generator, not the output"）

**坏处**

- **建设成本高**：要写规则库、验证 harness、编排逻辑、状态管理，起步可能就要数周
- **移动端没有现成的**：RepoTransBench 的语言对里没有 Swift/Kotlin；Porter 是 alpha 且只有 1 star；AlphaTrans 是论文 artifact 不是产品；Konveyor 面向 Java 后端而非移动端。**你需要自己组装**
- **规则库是持续负债**：平台会变，规则要维护
- **前期投入与收益不匹配时是浪费**：迁移一次就不再用，就不值
- **可能过度工程**：为 3 个页面的迁移搭一套编排，不如直接让 Agent 干

### 3.4 选择建议

| 场景 | 建议 |
|---|---|
| 一次性迁移一个小功能（几个页面 / 一个流程） | 裸 Agent + 一份写清楚的 brief。别搭工程 |
| 要迁移一个子系统（登录、支付、阅读器等） | Agent + skill（用 Xilantra 那套结构，或自己写一份），配 parity 清单 |
| 要迁移整个 App 且长期双端维护 | **Skip（iOS 优先）或 KMP（Android 优先）**。这是唯一有产品级支持的路线 |
| 要迁移整个 App 但只做一次，之后双端各走各的 | Agent + skill + 确定性 AST 层 + 可执行测试 oracle，参考 AlphaTrans 的"分解-验证-重组"形状 |
| 只共享业务逻辑，UI 各写各的 | KMP + SKIE（Android 优先），或 Skip 的 module 依赖方式（iOS 优先） |

---

## 4. 针对"从现有 iOS 工程迁移一部分功能到 Android"的具体路径

这是你问题里最具体的一个场景，方向是 iOS → Android 的增量迁移。可选项：

**方案 1：Skip module（推荐，如果长期维护）**

为那个功能单独建一个 Skip module，作为依赖挂进现有 iOS 工程（官方明确支持 SwiftPM 依赖）。Skip Lite 模式产出可读 Kotlin，可以放进现有 Android 工程，也可以之后 eject 出来独立演进。代价是引入 Skip 工具链和 60MB（Fuse）或较小（Lite）的体积开销。

**方案 2：Agent + skill（推荐，如果只做一次）**

用 iOS 源码作为**产品参考**而非逐行翻译对象。先用可执行测试或截图把 iOS 侧行为刻画下来，再在 Android 工程里重写成目标平台惯用实现，用 parity gate 卡住行为一致性。这正是 Xilantra skill 的工作流。

**方案 3：SwiftKotlin 打底 + 人工修（不推荐，但可以省一点机械劳动）**

SwiftKotlin 停更于 2020，支持 Swift 5。对框架无关的纯逻辑（数据模型、算法、序列化）可以跑一遍拿到草稿，但 UI 和平台集成层它完全不覆盖，而且它自己不承诺产出可用代码。当作"省打字"工具可以，不能当迁移方案。

**方案 4：KMP 反哺（如果你的 Android 工程已经在用 KMP）**

把该功能的逻辑用 Kotlin 重写进 shared module，然后让 iOS 侧通过 framework 消费——但注意这意味着**功能真相从 Swift 转移到 Kotlin**，iOS 侧要改造成调用 shared module。只有当这个功能未来也要双端同步演进时才划算。

---

## 5. 一句话回答

**没有"iOS 代码一键转 Android 代码"的成熟开源项目，也没有反向的。** 真正的开源选择只有三条：接受架构约束用 Skip 或 KMP 做共享（这是唯一能覆盖整个工程的路线），用互操作让一端跑另一端的逻辑（只覆盖非 UI 层），或者用 Agent 重写并靠测试和静态分析兜底（学术界已成型，工业级开源仍是 alpha，且移动端是空白）。

**相比裸 Agent，专用工作流的价值不在"模型更聪明"，而在四件事：约束（不许逐行翻译、不许静默改行为）、知识沉淀（平台映射表写一次复用）、验证闭环（编译器/测试/截图做客观判据）、可恢复编排（分片、状态、预算门禁）。** 裸 Agent 最危险的不是写得不好，而是它"改完了"这句话本身无法验证。

**相比 Agent + skill，专用工程多的是一层确定性和一层编排。** Skill 是提示词，约束不了执行；ast-grep/GritQL/Comby 这类结构化重写器能保证机械改写的确定性，静态分析能保证 Agent 不迷路，测试 oracle 能保证收敛。代价是建设成本——只有迁移规模足够大、或者迁移会重复发生时，这笔投入才回得来。

---

## 6. 主要来源

一手来源（仓库 README / 官方文档）：

- [google/j2objc README](https://github.com/google/j2objc)
- [skiptools/skip README](https://github.com/skiptools/skip)、[Skip 官方文档：Lite 与 Fuse 模式](https://skip.dev/docs/modes/)、[Project Structure](https://skip.dev/docs/project-types/)、[Bridging Reference](https://skip.dev/docs/bridging/)、[Porting Swift Packages to Android](https://skip.dev/docs/porting/)、[FAQ](https://skip.dev/docs/faq/)
- [angelolloqui/SwiftKotlin README](https://github.com/angelolloqui/SwiftKotlin)
- [studoverse/Kotlift README](https://github.com/studoverse/Kotlift)
- [Kotlin 官方：Make your Android application work on iOS](https://kotlinlang.org/docs/multiplatform/multiplatform-integrate-in-existing-app.html)、[iOS integration methods](https://kotlinlang.org/docs/multiplatform/multiplatform-ios-integration-overview.html)
- [DeepSoftwareAnalytics/RepoTransBench README](https://github.com/DeepSoftwareAnalytics/RepoTransBench)
- [Intelligent-CAT-Lab/AlphaTrans README](https://github.com/Intelligent-CAT-Lab/AlphaTrans)
- [konveyor/kai README](https://github.com/konveyor/kai)
- [leog25/porter README](https://github.com/leog25/porter)
- [htk007/harmonyos-ai-migration-rules README](https://github.com/htk007/harmonyos-ai-migration-rules)
- [Xilantra/skills — cross-platform-app-port SKILL.md](https://github.com/Xilantra/skills)
- [Swift 官方：Swift 6.3 release（含 Android SDK）](https://www.swift.org/blog/swift-6.3-released/)

元数据：以上所有 star 数、最近提交时间、license 均通过 GitHub API 于 2026-10-16 直接查询获得。
