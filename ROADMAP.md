# CangjieXML 渐进开发计划（Roadmap）

> 配套设计文档：[`DESIGN.md`](./DESIGN.md)。
> 参考实现：`.libxml2-2.15.3/`（只读基线）。
>
> 本计划按**里程碑（Milestone）**组织，每个里程碑都交付"**可独立构建、可测试、可回归**"的
> 工件；后一里程碑只依赖前面里程碑的稳定 API，避免大爆炸式集成。

## 里程碑总览

| 阶段 | 里程碑 | 主题 | 关键产出 | 退出标准（DoD） |
|---|---|---|---|---|
| 0 | **M0** | 技术预研与脚手架 | cjpm workspace、CI、demo 验证 | 所有 §19 Demo 通过；workspace `cjpm build` 成功 |
| 1 | **M1** | 基础设施 `base` + `diag` | chars/uri/intern/buf/io/encoding/diag | 各子包单测覆盖率 ≥ 80%；URI/UTF-8/UTF-16 通过 RFC 样例 |
| 2 | **M2** | 核心树模型 `core` | Node 代数、Document、Namespace、序列化 | 能手工构造/修改/序列化 DOM；往返序列化稳定 |
| 3 | **M3** | Well-formed XML 解析器 | tokenizer、SaxDriver、TreeBuilder、Reader | 通过 W3C XML Test Suite 的 **well-formed** 子集 100% |
| 4 | **M4** | DTD 解析与校验 | parser 中的 DTD + `validate.dtd` | 通过 libxml2 `test/VC/*`、`test/valid/*` 回归 |
| 5 | **M5** | 命名空间与 XPath 1.0 | `xpath`、`pattern`、`xpointer` | 通过 libxml2 `test/XPath/`、`test/xmlid/`、XPath 一致性测试 |
| 6 | **M6** | Writer / C14N / XInclude / Catalog | `writer`、`c14n`、`xinclude`、`catalog` | C14N 1.0/Exc-C14N 通过 W3C 测试；XInclude 通过 libxml2 `test/XInclude` |
| 7 | **M7** | HTML 解析器 | `html` 模块 | 通过 libxml2 `test/HTML/` 回归（差异白名单记录） |
| 8 | **M8** | XML Schema（XSD）1.0 | `validate.xsd`、`validate.xsd.types` | 通过 W3C XSD 测试套件（`xstc`）核心子集；能流式校验 |
| 9 | **M9** | RELAX NG + Schematron | `validate.relaxng`、`validate.schematron` | 通过 libxml2 `test/relaxng`、`test/schematron` |
| 10 | **M10** | CLI：xmllint / xmlcatalog | `cli.xmllint`、`cli.xmlcatalog` | 能按 libxml2 等价命令替换至少 80% 日常用法 |
| 11 | **M11** | 性能、Fuzz、硬化 | benchmarks、fuzz、限额、并发压测 | 解析吞吐 ≥ 0.7× libxml2；fuzz 24h 无 crash |
| 12 | **M12** | v1.0 发布与文档 | user-guide、migration、API doc | 发布 `v1.0.0` + 迁移指南 |

时间/工时评估按"每里程碑结束自然退出"原则不写死——由团队规模决定；本计划只聚焦**顺序与依赖**。

---

## M0 — 技术预研与脚手架

**目标**：验证仓颉语言关键机制能承载本项目设计，并搭好可持续交付的工程底座。

**任务清单**：
- [ ] 安装仓颉 SDK（`cangjie-sdk-linux-x64-1.0.5.tar.gz`），在 CI 中打通 `cjpm build/test`。
- [ ] 初始化 `cjpm.toml` 顶层工作区；创建 §17 描述的 `packages/` 骨架（空 package 亦可）。
- [ ] 接入 `.github/workflows/` 的 CI：构建 + 单测 + 格式化 + `cjlint`。
- [ ] 建立"参考源比对脚本"：自动列出 libxml2 对应 C 文件与 Cangjie 包的映射。
- [ ] 完成 **§19 列出的 8 个技术验证 Demo**，放入 `prototype/`：
  - [ ] D01 代数节点模型 vs. switch 遍历性能
  - [ ] D02 字符串驻留池（`StringPool`）雏形
  - [ ] D03 零拷贝 `ByteView` 切片
  - [ ] D04 并发解析隔离（两个独立 SaxDriver）
  - [ ] D05 `std.regex` 对 XSD pattern 的适配尝试
  - [ ] D06 `WeakRef<Node>` 父指针不阻止 GC
  - [ ] D07 `@derive`/自动派生用于 Debug 输出
  - [ ] D08 `cjpm` workspace + 条件 feature 编译
- [ ] 撰写《技术预研结论》附录，记录发现与对 `DESIGN.md` 的勘误。

**DoD**：
- `cjpm build` 与 `cjpm test` 在 CI 通过。
- 所有 Demo 在 `prototype/` 下可运行，结论写入 `docs/tech-spike.md`。
- 若发现设计阻塞项（例如 `WeakRef` 缺失、某语法不支持），升级 `DESIGN.md` 并说明替代方案。

---

## M1 — 基础设施 `base` + `diag`

**目标**：无业务的底层工具链就绪，上层可稳定开发。

**任务清单**：
- [ ] `base.chars`：XML 1.0 第五版 + XML 1.1 的 `Char`、`NameStartChar`、`NameChar`、
      `PubidChar`、空白判定。使用 `const` 函数 + 位图（Byte 数组 const）实现。
- [ ] `base.uri`：实现 RFC 3986 `Uri { scheme, authority, path, query, fragment }`；
      `parse/resolve/normalize/escape/unescape`。对照 libxml2 `uri.c` 用例迁移测试。
- [ ] `base.intern`：`StringPool` + `InternedName`（`struct`），并发安全写入。
- [ ] `base.buf`：`ByteView`（`struct`）、`GrowBuf`（`class`，amortized O(1)）。
- [ ] `base.io`：`InputSource`/`OutputSink` 接口 + `FileSource`、`MemorySource`、`StreamSource`。
- [ ] `base.encoding`：
  - [ ] `interface Codec`
  - [ ] UTF-8 decoder（零拷贝快路径）
  - [ ] UTF-16 LE/BE decoder（含代理对）
  - [ ] ISO-8859-1..16、US-ASCII、Windows-1252
  - [ ] BOM 识别 + XML 声明嗅探器
  - [ ] `CodecRegistry`（进程内可注册自定义 Codec）
- [ ] `diag`：`XmlError`/`XmlDomain`/`XmlSeverity`/`Location`/`ErrorSink`/`ErrorCollector`；
      `XmlException`；提供"错误格式化器"输出人类可读的多行报告（含上下文片段）。

**DoD**：
- 每个子包单测 ≥ 80% 行覆盖率。
- URI 解析通过 RFC 3986 附录 C 的所有示例。
- UTF-8/UTF-16 解码通过 `.libxml2-2.15.3/test/encoding/` 抽样样本。

---

## M2 — 核心树模型 `core`

**目标**：在不涉及解析器的情况下，DOM 就能手工构造、修改、比较、序列化。

**任务清单**：
- [ ] `core.node`：`sealed interface Node`、`Element`、`Attribute`、`CharDataNode`、
      `Namespace`、`Dtd`、`DocumentFragment`、`XIncludeMark` 等。
- [ ] `core.doc`：`Document`（入口、版本、编码、standalone、根元素、DTD 引用、字符串池）。
- [ ] 父子/兄弟指针 + `WeakRef` 父/文档指针；`append/prepend/insertBefore/remove/replace`
      的原子操作（单线程安全 + 维护链表/命名空间继承一致性）。
- [ ] `extend Node`/`extend Element`：遍历迭代器（XPath 轴的纯树版本）、快捷访问器。
- [ ] `core.ns`：命名空间查找（`lookupPrefix/lookupUri`），避免在树中重复同 URI 命名空间。
- [ ] `core.serialize`：同步地把 `Document` 序列化为字节（UTF-8/UTF-16），支持缩进、属性排序、
      XML 声明、CDATA 保持策略；暂不实现 C14N（M6）。
- [ ] `freeze()` / `AtomicBool frozen`，进入只读模式后禁止所有写操作（`throw IllegalStateError`）。
- [ ] 单测：手工构造若干文档 → 序列化 → 与预期字节比对。
- [ ] 基准：构造 10^6 节点树并序列化，记录基线。

**DoD**：
- `Document → bytes → Document`（借助 M3 能跑通后 loop）前半段稳定。
- 对外 API 稳定不再大改（否则 M3 连锁返工）。

---

## M3 — Well-formed XML 解析器

**目标**：完整实现一个 XML 1.0/1.1 解析器（不含 DTD 校验，仅"well-formedness"），三种消费模式
（SAX/DOM/Reader）统一后端。

**任务清单**：
- [ ] `parser.lex`：UTF-8 字节流 tokenizer（状态机用 `enum LexState` + `match`）。
- [ ] `parser.sax`：`Event` 枚举 + `interface SaxHandler`（全部默认实现）。
- [ ] `parser.entity`：内置实体 + 通用实体 + 展开限额；外部实体先占位（默认拒绝）。
- [ ] `parser.tree_builder`：`class TreeBuilder <: SaxHandler`，把事件流构造成 `Document`。
- [ ] `parser.reader`：`XmlReader` pull 游标 API（`read`、`localName`、`value`、`nodeType`、
      `depth`、`moveToNextAttribute`、`isEmptyElement` 等）。
- [ ] 字符/名称合法性使用 `base.chars`；错误带精确行列 + 字节偏移。
- [ ] 实体/深度/大小限额（`XmlOptions.entityExpansionLimit`、`maxDepth`、`hugeLimit`）。
- [ ] 恢复模式 `options.recover`：遇错后跳到下一个良好边界继续。
- [ ] DTD **解析**（不校验）：内部子集 + `<!ELEMENT/ATTLIST/ENTITY/NOTATION>` → `Document.dtd`。
- [ ] 参数实体在 DTD 内的替换。

**DoD**：
- 通过 W3C XML Test Suite 的 **well-formedness** 子集（对应 libxml2 `xmlconf/`）。
- `test/` 下 libxml2 的非校验类样例回归：解析器不崩溃，且 DOM 序列化结果 byte-equal
  （允许命名空间等价重写）。
- 流式 Reader 与 SAX 与 DOM 三种模式下，同一份文件产生的"抽象事件序列"一致。

---

## M4 — DTD 校验

**目标**：为已解析文档做 DTD 校验；并把默认属性、ID/IDREF 索引、实体声明等语义接入。

**任务清单**：
- [ ] `regex`：粒子 NFA → DFA（Thompson + 子集构造），支持 `(a,b,c)*`、`(a|b|c)?`、
      `minOccurs/maxOccurs`（M8 共用）。
- [ ] `validate.dtd.ContentModel`：把 `<!ELEMENT>` 的内容模型编译为粒子自动机。
- [ ] `validate.dtd.AttrCheck`：`CDATA/ID/IDREF/IDREFS/NMTOKEN/NMTOKENS/Enumeration/Notation`。
- [ ] 属性默认值（`#FIXED`、`#IMPLIED`、`#REQUIRED`、默认值）在解析阶段注入。
- [ ] `Document.ids: HashMap<String, Element>` 索引（通过 `getElementById`）。
- [ ] 外部 DTD 加载（在 `options.dtdLoad=true` 时通过 `ResourceLoader`/Catalog）。
- [ ] `DtdValidator.validate(doc) -> ArrayList<XmlError>` + 流式变种（接入 SAX 管道）。

**DoD**：
- 通过 libxml2 `test/VC/*`、`test/valid/*` 回归：结果与 libxml2 一致（差异记录白名单）。
- 错误消息至少给出：违反规则名、涉及元素/属性、位置。

---

## M5 — 命名空间与 XPath 1.0

**目标**：完成 XPath 1.0 求值、Pattern 匹配、XPointer `element()/xpath1()`。

**任务清单**：
- [ ] `xpath.ast`：`Expr`/`Step`/`Axis`/`NodeTest` 等 `enum`；递归下降 parser。
- [ ] `xpath.eval`：
  - [ ] `XValue { NodeSet | Number | Str | Bool }`
  - [ ] 13 个轴的惰性迭代器（复用 `core.node` extend）
  - [ ] `XPathContext`（变量绑定、函数表、命名空间映射）
  - [ ] 内建函数库（`string/boolean/number/node-set` 40+ 函数）
- [ ] 文档序维护：`NodeSet` 去重 + 排序，`NodeIndex` 可选（大文档优化）。
- [ ] `xpath.pattern`：XSLT/libxml2 风格的 pattern 编译器（XPath AST 子集 → 前缀自动机）。
- [ ] `xpointer`：仅 `element()`、`xpath1()`。
- [ ] 扩展点：`ctx.register(name, XFunc)`。

**DoD**：
- 通过 libxml2 `test/XPath/`（比对 `result/XPath/`）≥ 98% 用例。
- XPath 表达式 parse 错误可定位到字符列。

---

## M6 — Writer / C14N / XInclude / Catalog

**目标**：写入侧、规范化、包含、目录四件套齐备，形成"端到端可互换 libxml2"的完整线。

**任务清单**：
- [ ] `writer`：流式 `XmlWriter`（事件形态 API），自动维护命名空间栈、属性转义、缩进。
- [ ] `c14n`：Canonical XML 1.0（Inclusive/Exclusive），作为 `SaveOptions.canonicalize` 的
      实现。算法在 `c14n` 内部实现为"事件过滤 + 排序 + 序列化"管道。
- [ ] `xinclude`：`XIncludeProcessor`（解析 `xi:include`、支持 `xpointer`/`parse="text"`、
      回退内容、循环检测、fragment 级合并）。
- [ ] `catalog`：OASIS XML Catalog 1.1；公共/系统/重写/委托/`nextCatalog`；
      URI catalog；`XML_CATALOG_FILES` 环境变量默认值（可关闭）。
- [ ] `ResourceLoader` 默认实现接入 Catalog；CLI `xmlcatalog` 前置准备。

**DoD**：
- 通过 W3C C14N 测试套（IBM/Merlin XML C14n suite，libxml2 结果作为交叉对照）。
- 通过 libxml2 `test/XInclude/*`、`result/XInclude/*` 回归。
- 能根据 catalog 正确解析外部 DTD。

---

## M7 — HTML 解析器

**目标**：HTML 宽松解析并与 XML 树共享节点模型。

**任务清单**：
- [ ] `html.tokenizer`：HTML5 13 种以上的 tokenizer 状态（以 `enum` + `match`）。
- [ ] `html.tree_construction`：insertion modes + 异常行为（script/style、table、select 等）。
- [ ] `html.named_char_refs`：实体表作为 `const HashMap`（由工具脚本从 WHATWG 生成）。
- [ ] `Xml.parseHtml(...)` / `HtmlReader`。
- [ ] 兼容层：`HtmlOptions.legacy: Bool` 贴近 libxml2 HTML4 行为。

**DoD**：
- 通过 libxml2 `test/HTML/*` 回归（差异白名单：允许因 HTML5 更严格/更宽松而不同的项）。

---

## M8 — XML Schema 1.0

**目标**：XSD 校验落地（最大的工作量，分三个子阶段）。

### M8.1 简单类型与 facet
- [ ] 内建类型（`xs:string/boolean/decimal/integer/…/dateTime/duration/…` 等 44 种）
- [ ] `xsd.types.Value` 代数类型 + 解析器 + 规范化器
- [ ] facets：`length/min|maxLength/pattern/enumeration/whiteSpace/totalDigits/fractionDigits/minInclusive/…/maxExclusive`
- [ ] `xsd pattern` → `std.regex` 适配层（XML Schema 字符类/Unicode 块）

### M8.2 复杂类型与组件组装
- [ ] 组件模型 `enum XsdComponent`
- [ ] `include/import/redefine/override` 装配（含相对路径、Catalog 协作）
- [ ] `xsi:schemaLocation` 动态装配（流式模式下亦生效）
- [ ] 粒子自动机编译（`sequence/choice/all/group`）
- [ ] 替换组 / 抽象元素

### M8.3 校验器
- [ ] DOM 校验 `XsdValidator.validate(doc)`
- [ ] 流式校验 `XsdValidator.asHandler(): SaxHandler`（与 parser 管道对接）
- [ ] PSVI 附加（可关闭）
- [ ] Identity constraints（`unique/key/keyref`）

**DoD**：
- 通过 W3C XSD 测试套（`xstc`）核心子集 ≥ 95%；记录白名单。
- 流式校验在 SAX 管道上可运行，内存 O(深度 × 局部状态)。

---

## M9 — RELAX NG + Schematron

**目标**：补齐另外两大校验体系。

**任务清单**：
- [ ] `validate.relaxng`：
  - [ ] 读 RelaxNG XML syntax（Compact 方言可选，M9+ 再做）
  - [ ] Simplification 7 步（规范 §4）
  - [ ] Brzozowski 导数算法求值器
  - [ ] 数据类型库：`xsd:*` 子集 + RelaxNG builtin
- [ ] `validate.schematron`：
  - [ ] 解析 ISO Schematron（XSLT-free subset）
  - [ ] 规则 → XPath 编译（复用 M5）
  - [ ] SVRL 输出（结构化结果）

**DoD**：
- 通过 libxml2 `test/relaxng/*`、`test/schematron/*` 回归。
- 简单类型库使用 M8 成果，不重复实现。

---

## M10 — CLI：xmllint / xmlcatalog

**目标**：可执行命令行，便于替换现有 xmllint 用户脚本。

**任务清单**：
- [ ] `cli.xmllint`：`--noout`, `--valid`, `--dtdvalid`, `--schema`, `--relaxng`, `--schematron`,
      `--xinclude`, `--c14n`, `--xpath`, `--format`, `--encode`, `--memory`, `--recover`,
      `--nonet`, `--noent`, `--shell`, `--path`, `--maxmem`, `--huge`（与 libxml2 对齐的主力参数）。
- [ ] `cli.xmllint --shell`：`cd/ls/cat/pwd/dir/xpath/set/save/validate/help/quit` 等。
- [ ] `cli.xmlcatalog`：与 libxml2 参数对齐。
- [ ] 退出码与 stderr 格式尽量与 libxml2 一致，减少脚本迁移成本。
- [ ] 覆盖集成测试：把 libxml2 `test/schemas/*` 的 CLI 驱动脚本迁移为 cangjie 测试。

**DoD**：
- 至少 30 个典型 xmllint 用法能无缝替换（用例列在 `tests/cli/cases.md`）。

---

## M11 — 性能、Fuzz、硬化

**目标**：面向生产可用的质量。

**任务清单**：
- [ ] **基准**：
  - [ ] DOM 解析吞吐（小/中/大文档）
  - [ ] SAX 解析吞吐
  - [ ] XPath 求值（热/冷编译）
  - [ ] 序列化吞吐
  - [ ] 对照 libxml2 同机测试；目标 ≥ 0.7×。
- [ ] **性能优化迭代**：
  - [ ] 冷热分离 `LocInfo`
  - [ ] `ByteView` 零拷贝路径审计
  - [ ] 驻留池分桶/预热
  - [ ] 可选并发流水线（tokenize ↔ build ↔ validate）
  - [ ] `internal.unsafe.scan`（SIMD-ish）实验
- [ ] **Fuzz**：
  - [ ] `tests/fuzz/xml`、`xpath`、`html`、`schema`、`catalog` 五个 harness
  - [ ] 种子语料：`.libxml2-2.15.3/fuzz/` 迁移
  - [ ] 集成到 CI（短时长）+ 本地长时（24h）
- [ ] **硬化**：
  - [ ] 限额全链路生效审计
  - [ ] URI 规范化策略复核
  - [ ] XXE/Billion Laughs/ReDoS 专项样本
  - [ ] 并发压测（100 线程 × 混合读写）

**DoD**：
- 基准报告纳入发布说明；fuzz 24h 无新 crash；已知 limitation 形成清单。

---

## M12 — v1.0 发布与文档

**任务清单**：
- [ ] `docs/user-guide.md`：快速入门、常见场景、API 总览。
- [ ] `docs/migration-from-libxml2.md`：逐 API 映射 + 行为差异清单（§18）。
- [ ] `docs/api-overview.md`：每个 package 的公共 API 目录（可自动生成）。
- [ ] `CHANGELOG.md`：M1..M11 累积变更汇总。
- [ ] `SECURITY.md`：安全默认、限额、漏洞上报流程。
- [ ] 打 tag `v1.0.0`，在 GitHub Release 附带基准数据与 fuzz 报告摘要。

---

## 交付节奏与依赖

```
M0 → M1 → M2 → M3 → ┬─ M4 ─┬─ M5 ─┬─ M6 ─┬─ M7 ─┬─ M8 ─┬─ M9 ─┬─ M10 ─┬─ M11 ─→ M12
                    └──────┘      │     │             │
                                  └─────┴─ M8/M9 可与 M6/M7 部分并行 ─┘
```

- **M3 是硬阻塞**：之前所有里程碑都必须完成才能启动，之后多条并行线可拉开。
- **M8（XSD）体量大**：建议独立子团队持续推进，其他里程碑推进 CLI/XInclude/C14N 等不等它。
- **M11** 的部分基准可以在 M3 完成后就开始持续采集（回归曲线）。

---

## 每个里程碑的"质量门"（通用）

每个 milestone 必须同时满足：

1. **构建**：`cjpm build --release` 通过，零警告（`cjlint` 推荐集）。
2. **单测**：新增/修改模块覆盖率 ≥ 80% 行覆盖。
3. **集成**：本里程碑新增的"对照 libxml2 回归集"全部通过（或差异白名单有签名批准）。
4. **文档**：公共 API 有 doc-comment；`DESIGN.md` 若被打脸须同步更新。
5. **安全**：默认配置下通过 XXE/Billion Laughs 预设样本（从 M3 起持续）。
6. **性能**：与上个里程碑相比无回退 > 10%（性能 gate 从 M3 起开启）。
7. **示例**：至少 1 个使用新特性的 example 在 `examples/` 中可运行。

---

## 任务粒度建议（给实现者）

- 单个 Issue/PR 控制在 **≤ 800 行**（核心模块除外），带 1–2 个测试用例。
- 大模块拆分到**可独立 merge**的最小单元：例如 XPath 先合入 AST + parser + 少量求值，
  后续 PR 逐步补 13 个轴、函数库。
- 每个 PR 在描述中列出"对应 libxml2 哪个文件/函数"以便审阅者对照语义。
- **不允许**把 C 代码直接粘贴翻译；每次 PR 要展示"为什么仓颉形态更合适"（一句话即可）。

---

## 风险与应急

| 场景 | 应对 |
|---|---|
| 某仓颉语言特性在 SDK 1.0.5 下不可用 | 在 `docs/tech-spike.md` 记录；尝试替代方案；必要时升 `DESIGN.md` |
| `std.regex` 对 XSD pattern 支持不全 | 在 `regex` 包中补实现子集；与 `std.regex` 并存，不强依赖 |
| 性能 gate 连续未达 | 立刻开启 M11 的一部分工作（提前硬化） |
| 里程碑滑期 | 优先保证 M0–M6（核心 XML 能力），XSD/RNG/Schematron 可延后独立版本号 `v1.1` 发布 |

---

## 如何开始（Day-1 可执行）

1. 下载仓颉 SDK（`cangjie-sdk-linux-x64-1.0.5.tar.gz`），配置 `$CANGJIE_HOME` 与 `PATH`。
2. 在仓库根初始化 workspace：`cjpm init --type=workspace`（根据 cjpm 实际命令调整），
   按 §17 物理布局逐个 `cjpm new` 子包。
3. 接入 `.github/workflows/ci.yml`：构建 + 单测 + 格式化 + 参考文档生成。
4. 启动 **M0 Demo D01**（代数节点性能预研），边写边迭代 `DESIGN.md`。

> **节奏口号**：*每个里程碑都是一个可用且诚实的版本。*
