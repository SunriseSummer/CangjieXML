# CangjieXML 渐进式开发计划（Roadmap）

> 本计划与 [`DESIGN.md`](./DESIGN.md) 配套。按"先打地基、后盖楼"的顺序，把 libxml2 17 万行 C 的功能拆成 **13 个阶段**，每个阶段都要求可运行、可测试、可发布。目标：任何一个阶段完成后，项目都能独立向下游提供一个有意义的能力子集。
>
> 排期不写具体日期（工作量随团队规模浮动），用"里程碑 + 出口准则"驱动。

---

## 总览

| 阶段 | 名称 | 对应 libxml2 模块 | 关键交付 |
| --- | --- | --- | --- |
| Phase 0 | 项目骨架 | — | cjpm 工作区、CI、规范 |
| Phase 1 | 基础设施 | `chvalid`, `xmlstring`, `buf`, `dict`, `list`, `hash`, `error`, `uri` | `xml_core` 可用 |
| Phase 2 | 编码与 IO | `encoding`, `xmlIO` | `xml_encoding`, `xml_io` |
| Phase 3 | 词法 + 事件流 | `parser`（词法部分）, `parserInternals` | `xml_parser` 产出 `Iterator<SaxEvent>` |
| Phase 4 | DOM + SAX + Reader | `tree`, `SAX2`, `xmlreader` | `xml_tree`, `xml_sax`, `xml_reader` 初版 |
| Phase 5 | 输出侧 | `xmlwriter`, `xmlsave` | `xml_writer`, `xml_save` |
| Phase 6 | XPath 1.0 | `xpath` | `xml_xpath` + XPointer(element()) |
| Phase 7 | DTD 与正则/自动机 | `valid`, `xmlregexp`, `pattern` | `xml_dtd`, `xml_regexp`, `xml_pattern` |
| Phase 8 | XML Schema 1.0 | `xmlschemas`, `xmlschemastypes` | `xml_schema`（MVP 子集 → Full） |
| Phase 9 | RelaxNG + Schematron | `relaxng`, `schematron` | `xml_relaxng`, `xml_schematron` |
| Phase 10 | XInclude + C14N + Catalog | `xinclude`, `c14n`, `catalog`, `xpointer` | 三个独立子包 |
| Phase 11 | HTML 解析 | `HTMLparser`, `HTMLtree` | `xml_html` |
| Phase 12 | 工具链与发布 | `xmllint`, `xmlcatalog`, `shell`, `debugXML` | `tools/xmllint`、`tools/xmlcatalog`、v1.0 release |
| Phase 13 | 硬化与优化 | `runtest`, `fuzz`, `testlimits` | 性能、模糊、安全加固 |

---

## Phase 0：项目骨架

### 目标
建立仓颉工作区、约定规范、接入 CI；代码体积最小。

### 任务
- `cjpm.toml`：workspace 声明 + members 列表（初始只含 `packages/xml_core` 占位）。
- 顶层 `README.md`：项目简介、构建指令、贡献指南链接。
- `.editorconfig`、`.gitignore`（忽略 `target/`、`*.cjo` 等构建产物）。
- CI（GitHub Actions）：`cjpm build --all` + `cjpm test --all` + `cjfmt --check` + `cjlint`。
- 规范文档：复用 `cangjie-regulations` skill 里的项目结构/命名/文档规范作为基线。
- 为每个计划中的包创建空 `src/` 骨架 + `cjpm.toml`（可打开 lint 但暂无产物）。

### 出口准则
- `cjpm build --all` 成功；
- CI 绿；
- 所有计划包目录均已创建，后续阶段"填肉"即可。

---

## Phase 1：基础设施（`xml_core`）

### 范围
对应 libxml2: `chvalid.c`, `xmlstring.c`, `buf.c`, `dict.c`, `hash.c`, `list.c`, `error.c`, `uri.c`, 部分 `globals.c`。

### 任务
1. **字符类** `char_valid.cj`：
   - XML 1.0 / 1.1 的 NameStartChar、NameChar、Char、PubidChar、Whitespace。
   - const 函数 + 区间查表。
   - 单测与 W3C `xmltest` 字符边界用例对比。
2. **缓冲** `buffer.cj`：
   - `class GrowableBuffer` 基于 `ArrayList<Byte>`；
   - 预留 `append(s: String)`、`appendByte`、`slice`；
   - 上限可配（防 OOM），提供 `BoundedBuffer` 装饰器。
3. **字符串工具**：libxml2 的 `xmlStrcat/xmlStrEqual` 多数可被仓颉 `String` 原生替代；仅保留 `bytesToString(UTF-8)`、`escape(xml)`、`normalizeWhitespace` 等特有函数。
4. **NameTable**（替代 `xmlDict`）：`HashMap<String,String>` + `Mutex`，提供 `intern`。
5. **错误模型**：`XmlError` enum、`XmlException`、`Position`、`ErrorCollector` 接口，**还不接具体解析器**，先把类型定好。
6. **URI** `uri.cj`：
   - `struct Uri` + `parse/resolve/normalize/escape/unescape`；
   - 严格按 RFC 3986；同时实现 libxml2 的 "windows 盘符兼容" 行为并做开关。
7. （暂不实现 `list.c` 风格的通用链表——仓颉 `ArrayList`/`LinkedList` 足够）
8. （暂不实现 `hash.c` 通用哈希——直接用 `HashMap`）

### 出口准则
- `xml_core` 单测覆盖率 ≥ 90%；
- URI 模块通过 libxml2 `test/URI` 金标（预期字符串一致）；
- 字符类与 libxml2 `chvalid.c` 查表结果对每个码点一致（用脚本批量生成对照表）。

---

## Phase 2：编码与 IO（`xml_encoding`, `xml_io`）

### 范围
对应 libxml2: `encoding.c`, `xmlIO.c`（去掉 `nanohttp`/`nanoftp`）。

### 任务
1. **内置解码器**：UTF-8、UTF-16 LE/BE、UTF-32 LE/BE、ASCII、ISO-8859-1…15。
2. **BOM 探测器**：独立函数，返回 `(BomKind, skipLen)`。
3. **编码器**：UTF-8、UTF-16 LE/BE；其余通过接口可注册。
4. **`Decoder`/`Encoder` 接口**：支持流式（状态保留），暴露 `decodeChunk`。
5. **`ParserInputSource` / `OutputSink`** 接口及适配器：`FileInputSource`, `MemoryInputSource`, `StringInputSource`, `FileOutputSink`, `MemoryOutputSink`。
6. **装饰器**：`BufferedSink`, `IndentingSink`, `EncodingSink`。
7. 单测：编码往返、BOM 混用、错误字节序列报错位置。

### 出口准则
- 与 libxml2 `encoding.c` 输出对 UTF-16/32、Latin-1 等逐字节一致（选 10 个样本）。
- `IndentingSink + EncodingSink` 组合在中间层也能输出正确 BOM。

---

## Phase 3：词法 + 事件流（`xml_parser` — 非验证）

### 范围
`parser.c`/`parserInternals.c` 的**词法**与**语法骨架**；暂不做 DTD 校验，仅良构检查。

### 任务
1. **`ByteReader` + `RuneReader`**：行列号、字节偏移；换行归一化。
2. **`Lexer`**：`enum Token` + 大 match 状态机（限 XML 声明、元素标签、属性、文本、CDATA、注释、PI、DOCTYPE 头、实体引用）。
3. **`Parser`**：把 token 组合成 `SaxEvent` 序列。命名空间在此层组装 `QName` 的 `uri`。
4. **实体**：内置 5 个 + 字符引用（`&#x;`、`&#;`）；外部实体走 `EntityResolver` 接口（默认拒绝）。
5. **参数选项**：`ParserOptions` struct。
6. **Billion Laughs / 深度限制**：实现实体展开计数与栈深阈值。
7. **容错模式**：`recover=true` 时，词法错误降级为 `SaxEvent::Error`，不中断。

### 出口准则
- 通过 W3C 的 `xmltest/valid/sa/*.xml`（不含 DTD 验证项）约 200 条；
- 通过 `xmltest/not-wf/sa/*.xml`：能识别非良构且错误位置 ±1 行。
- 处理 10MB 文档不崩溃、内存稳定（事件迭代器惰性证明）。

---

## Phase 4：DOM + SAX + Reader（`xml_tree`, `xml_sax`, `xml_reader`）

### 范围
`tree.c`, `SAX2.c`, `xmlreader.c`（核心 API，不含验证集成）。

### 任务
1. **数据模型**：`sealed interface Node` 与全部具体分支类（§4 DESIGN）。
2. **`DocumentBuilder`**：从 `Iterator<SaxEvent>` 构造 `Document`；带命名空间、实体引用节点选项。
3. **`SAXHandler` 接口 + `DefaultSAXHandler`**：易于派生覆盖。
4. **`XmlReader`（拉）**：`class XmlReader { func read(): Bool; prop currentNode: ReaderNode; ... }`；内部就是缓存一层 event iterator。
5. **DOM 修改 API**：`appendChild/remove/replaceWith/insertBefore` 加不变量检查。
6. **遍历迭代器**：`children()`, `descendants()`, `ancestors()`, `followingSiblings()`, `precedingSiblings()`。
7. **`@Visitor` 宏**：自动派生 `accept` 和 `NodeVisitor<R>`。
8. **序列化（最小版）**：在 `xml_tree` 内置一个"便利"序列化（完整版在 Phase 5）。

### 出口准则
- DOM 往返：libxml2 `test/` 下 ~500 个 XML 文件 `parse → serialize → parse` 后语义等价（命名空间归一化之后）；
- `XmlReader` 驱动大文档（1GB 人工生成）内存不随文档增长；
- SAX 回调能正确收集与 libxml2 `testSAX` 相同的事件序列。

---

## Phase 5：输出侧（`xml_writer`, `xml_save`）

### 范围
`xmlwriter.c`, `xmlsave.c`（不含 C14N）。

### 任务
1. **`XmlWriter`**：所有 `startX/endX` 接口，内部用栈校验良构性（错用时抛 `XmlException`）。
2. **`DocumentSerializer`**：对 DOM 深度遍历，写入 `OutputSink`；支持缩进、编码、是否省略 XML 声明、是否包装为 CDATA。
3. **编码转换**：复用 `EncodingSink`。
4. **命名空间序列化**：与 C14N 共享"命名空间作用域跟踪"基础设施（为 Phase 10 做准备）。
5. 黄金测试：libxml2 `result/` 下 "save" 相关样例。

### 出口准则
- 语义等价：序列化结果 parse 回来与源文档相等；
- 字节等价（在同选项下）：对非缩进、UTF-8、保留空白的子集可与 libxml2 字节对齐。

---

## Phase 6：XPath 1.0（`xml_xpath`）

### 范围
`xpath.c`（XPath 1.0，不含 XPath 2 扩展）。不含 XPointer 高级方案与 XSLT。

### 任务
1. **Lexer + Parser** → `enum Expr`、`enum Step`、`enum Axis`。
2. **NodeSet**：惰性迭代 + 文档序索引（给每个 `Node` 附 `docOrderId`，解析完文档时一次性填）。
3. **函数库**：XPath 1.0 的 28 个核心函数（`position`, `last`, `count`, `string-length`, `substring`, `concat`, `normalize-space`, `translate`, `contains`, `starts-with`, `id`, `local-name`, `namespace-uri`, `name`, `number`, `boolean`, `not`, `true/false`, `lang`, `sum`, `floor`, `ceiling`, `round`, `string`, `boolean`, `text()`, `node()` 等节点测试）。
4. **变量 / 命名空间上下文**：`class XPathContext`。
5. **编译缓存**：`class CompiledXPath`；多线程安全复用。
6. **轻量 XPointer**（element() 方案）。
7. 单测覆盖 W3C XPath 测试集（核心 100+ 条）。

### 出口准则
- 通过 W3C XPath 1.0 测试集（MVP 子集）；
- 与 libxml2 `xmllint --xpath` 对 500 条随机表达式结果一致（节点集转字符串后比较）。

### 里程碑意义
**Phase 0–6 完成即构成"MVP 版本"**，已覆盖 80% 的 libxml2 使用场景（解析 + DOM + XPath + 序列化）。

---

## Phase 7：DTD 验证 + 正则自动机 + Pattern

### 范围
`valid.c`, `xmlregexp.c`, `pattern.c`, `xmlautomata.h`。

### 任务
1. **`xml_regexp`**：XSD 正则 AST → NFA（Thompson）→ DFA（子集构造）；支持 Unicode 类别与 XML 字符类。
2. **DTD 解析器**：在 `xml_parser` 基础上扩出 DTD 子语言解析；产出 `Dtd` AST（元素声明、属性声明、实体声明、Notation）。
3. **DTD 验证**：
   - 内容模型编译为 DFA（复用 `xml_regexp`）；
   - 属性类型校验（ID/IDREF/ENTITY…）；
   - 默认值/固定值填充；
   - 验证既可插到 `SaxEvent` 流（流式），也可作用于 `Document`（树式）。
4. **`xml_pattern`**：流式 XPath 子集（`/a/b/c`, `//x`, `*`, `@attr`）编译到自动机；用于 reader 筛选和 schema selector。
5. **与 `xml_reader` 集成**：`XmlReader` 支持开启 DTD 验证与 Pattern 过滤。

### 出口准则
- 通过 W3C `xmlconf` DTD 部分；
- 对 `test/valid/` 全通过；
- `pattern` 单测覆盖 90%；
- `xml_regexp` 对 libxml2 `testregexp` 中所有样例行为一致。

---

## Phase 8：XML Schema 1.0（`xml_schema`）

对应 libxml2 最大的单文件（`xmlschemas.c` 28k 行），拆成两里程碑。

### Phase 8a（MVP）
- XSD 文档解析：`schema / element / attribute / complexType / simpleType / group / attributeGroup / include / import`。
- 44 个内建简单类型 + facets（minLength/maxLength/pattern/enumeration/minInclusive/…）。
- 顶层 `class CompiledSchema` + `Validator`；仅 DOM 路径。
- 流式校验复用 `SaxEvent` 流。
- 单测：W3C XSD 测试集 "minimal" 子集 + Schema-for-Schemas 自举。

### Phase 8b（Full）
- 类型派生（Restriction/Extension/List/Union）完整语义；
- `xs:unique`/`xs:key`/`xs:keyref`（调用 `xml_xpath`）；
- `xsi:type`、`abstract`、`substitutionGroup`；
- 通配符 `xs:any`、`xs:anyAttribute`；
- W3C XSD 测试集官方通过率 ≥ 90%；
- 与 libxml2 `testSchemas` 输出对齐（错误消息大意一致）。

---

## Phase 9：RelaxNG + Schematron

### Phase 9a：RelaxNG（`xml_relaxng`）
- XML Syntax 解析 → `sealed class Pattern`；
- 采用 Brzozowski 导数算法做验证；
- 内建数据类型复用 `xml_schema` 的简单类型库；
- 通过 OASIS RelaxNG 官方测试集。

### Phase 9b：Schematron（`xml_schematron`）
- 解析 ISO Schematron（ISO/IEC 19757-3）规则文档；
- 调用 `xml_xpath` 做断言；
- 输出 SVRL 报告（结构化）。
- 范围比 libxml2 的 `schematron.c` 稍窄，但语义等价。

---

## Phase 10：XInclude + C14N + Catalog + XPointer

### Phase 10a：Catalog（`xml_catalog`）
- 解析 OASIS XML Catalog 1.1；
- 实现 `EntityResolver` 默认实现"按 catalog 查找"。
- 通过 `test/catalogs/` 全部样例。

### Phase 10b：XInclude（`xml_xinclude`）
- 处理 `xi:include` + fallback；
- 支持 text/xml 两种解析；
- 与 XPointer 联动（fragment 定位）。

### Phase 10c：XPointer（`xml_xptr`）
- 实现 element() 与 xpath() 方案；
- 其余方案（`xmlns()`, `fragid`）按 libxml2 现状实现。

### Phase 10d：C14N（`xml_c14n`）
- 1.0、Exclusive、1.1；
- 重新设计 attr-axis 命名空间处理（严格确定性排序）；
- 提供 `InclusionFilter`；
- 通过 W3C C14N 官方测试集。

---

## Phase 11：HTML（`xml_html`）

- 共享 `xml_parser` 词法；
- 增加 `HtmlInsertionMode` 状态机（WHATWG 子集）；
- 生成的 `Document.isHtml = true`；
- 支持宽松解析（属性值不引号、隐式闭合等）；
- 与 libxml2 `HTMLparser` 的行为差异在文档中逐条列出。

---

## Phase 12：工具链与 v1.0 发布

### 任务
1. **`tools/xmllint`**：
   - 覆盖 libxml2 `xmllint` 的高频子命令：`--noout`, `--xpath`, `--relaxng`, `--schema`, `--dtdvalid`, `--c14n`, `--xinclude`, `--format`, `--pretty`, `--encode`, `--stream`, `--walker`, `--shell`（交互式，基于 `xml_xpath`）。
2. **`tools/xmlcatalog`**：`--add`, `--del`, `--resolve`。
3. **`xml`（门面包）**：`public import` 常用 API，供 SDK 使用者一行 `import xml.*` 即可。
4. **文档站点**：`docs/` 下分模块 API 参考（可用 cjc 文档生成）、`guides/` 入门、迁移自 libxml2 指南。
5. **发布**：打 `v1.0.0` tag，在 GitLab/GitHub 发布说明里对照 libxml2 特性表。

### 出口准则
- `xmllint` 在选定 100 条典型命令行下，输出与 libxml2 `xmllint` 语义等价（退出码一致，文本输出一致或可通过 `--format` 归一化后一致）。

---

## Phase 13：硬化与优化

### 性能
- 使用 `cjprof` 找出热点：命名解析、编码解码、NodeSet 排序。
- 对 `xml_xpath` 加 NodeSet 复用池；
- 对解析器增加**SIMD 风格**的批量字符扫描（用仓颉循环 + 编译器向量化提示，不引入汇编）。
- Schema 编译结果缓存（LRU）；
- Benchmark 目标：相对 libxml2 单文件解析 ≥ 70% 吞吐；XPath ≥ 60%。

### 安全
- 接入项目内置的模糊器（基于 `.libxml2-2.15.3/fuzz/` 语料）；
- 复现 libxml2 历史 CVE，保证 CangjieXML 默认配置不中招；
- 启用 `cjlint` 的安全相关规则集。

### 并发
- 可选的"分段解析"并行实现（见 DESIGN §12.2）；
- Schema / RelaxNG 验证并行化；
- 提供 `ParallelValidator` 工具：多 Document × 1 Schema 并行。

### 维护
- 发布 `v1.1`：在 v1.0 基础上加性能 + 并行优化；
- 建立性能回归看板（每 PR 自动跑小 benchmark，超过阈值阻塞）。

---

## 关键依赖与顺序约束

以下是必须**严格顺序**的关键链：

```
Phase 0 → Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 ┐
                                           │              │
                                           └──> Phase 6 ──┤
                                                          │
                                   Phase 7 ←──────────────┘
                                      │
                   ┌──────────────────┼───────────────────┐
                   ▼                  ▼                   ▼
                Phase 8            Phase 9            Phase 10
                   │                  │                   │
                   └──────────────────┴───────────────────┘
                                      ▼
                                  Phase 11 & 12
                                      ▼
                                  Phase 13
```

- **Phase 10d (C14N)** 可提前到 Phase 5 之后并行启动（仅依赖 DOM + 序列化）。
- **Phase 11 (HTML)** 可与 Phase 6 之后的任意阶段并行（只依赖解析/DOM）。
- **Phase 9b (Schematron)** 依赖 Phase 6 (XPath) 即可，不必等 RelaxNG。

---

## 每阶段统一的"完成即合格"清单

一个阶段完成必须同时满足：

- [ ] 所有新包在 `cjpm build --all` 无警告编译通过；
- [ ] 单元测试覆盖率 ≥ 85%（通过 `cjcov`）；
- [ ] `cjfmt --check` / `cjlint` 零违规；
- [ ] 本阶段指定的黄金文件对比全通过；
- [ ] 至少 1 份示例程序放入 `examples/`；
- [ ] 本阶段涉及的 API 有仓颉 doc 注释与用法示例；
- [ ] ROADMAP 与 DESIGN 更新相应章节，必要时补 ADR。

---

## 技术验证 Demo 计划

（配合问题描述里的仓颉 SDK 1.0.5）

| 需要验证的技术点 | 建议的最小 Demo |
| --- | --- |
| `sealed interface` + `match` 在 20 种节点上的穷尽与性能 | 合成 100 万节点树、做一次 visitor 遍历 |
| Brzozowski 导数算法 | 写一个 100 行的 RelaxNG 子集原型验证子集验证正确性 |
| `Iterator<SaxEvent>` + 背压 | 从 5GB 合成 XML 流中只取前 100 事件，内存稳定 |
| NameTable 与 `String` intern 的 GC 行为 | 百万次相同 tag 解析的内存曲线 |
| NFA→DFA 构造 + Unicode 类别 | 对 XSD 正则 `[\p{IsBasicLatin}&&\w]` 等构造后匹配 |
| 多线程 XPath 并发求值 | 1 棵 DOM × N 线程 × M 查询的压测 |
| 宏派生 Visitor | 改一次 `Node` 分支，确认宏重新生成 visitor 接口 |

这些 Demo 都放在 `demos/` 顶层目录（不进发布产物），用来为每阶段关键设计**先立后破**，避免走回头路。

---

## 风险与缓解（与 DESIGN §21 呼应）

- **Schema 规模**：Phase 8 拆 a/b 两里程碑；8a 先打通端到端骨架。
- **W3C 测试套件获取/许可**：仅用公开、可转发的测试子集；`xml_testkit` 不包含套件本体，只给驱动器。
- **仓颉 SDK 快速迭代**：在 `cjpm.toml` 中锁定 SDK 版本 1.0.5；升级时在单独分支回归。
- **黄金文件差异维护**：所有差异都必须 `docs/libxml2-diff.md` 中注明，避免"看上去失败实际是预期差异"。

---

_计划内的所有任务都按仓颉 `cangjie-regulations` 的编码规范执行；本文件在每个阶段完成时更新进度，并与 DESIGN 保持一致。_
