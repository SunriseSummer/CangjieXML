# CangjieXML 渐进式开发计划

> 本计划与 [`DESIGN.md`](./DESIGN.md) 配套。把 libxml2 v2.15.3 的全部能力拆成 **13 个阶段**，按"先打地基、再盖楼"的顺序推进。每个阶段都要求**可编译、可测试、可发布**——任意阶段完成后，项目都能向下游提供一个有意义的能力子集。
>
> 排期不写具体日期（工作量随团队规模浮动），用"里程碑 + 出口准则"驱动。

---

## 总览

| 阶段     | 名称              | 对应 libxml2 模块                                   | 关键交付包                                  |
| -------- | ----------------- | --------------------------------------------------- | ------------------------------------------- |
| Phase 0  | 项目骨架          | —                                                   | `cjpm.toml` workspace、CI、规范基线          |
| Phase 1  | 基础设施          | `chvalid`, `xmlstring`, `buf`, `dict`, `error`, `uri` | `core`                                      |
| Phase 2  | 编码与 I/O        | `encoding`, `xmlIO`                                 | `encoding`, `io`                            |
| Phase 3  | 词法 + 事件流     | `parser`（词法部分）, `parserInternals`             | `parser`                                    |
| Phase 4  | DOM + SAX + Reader| `tree`, `SAX2`, `xmlreader`                         | `tree`, `sax`, `reader`                     |
| Phase 5  | 输出侧            | `xmlwriter`, `xmlsave`                              | `writer`, `save`                            |
| Phase 6  | XPath 1.0         | `xpath`                                             | `xpath`, `xpointer`（element 方案）         |
| Phase 7  | DTD + 正则 + Pattern | `valid`, `xmlregexp`, `pattern`                  | `regexp`, `pattern`, `dtd`                  |
| Phase 8  | XML Schema 1.0    | `xmlschemas`, `xmlschemastypes`                     | `schema`（8a 骨架 → 8b 全功能）             |
| Phase 9  | RelaxNG + Schematron | `relaxng`, `schematron`                          | `relaxng`, `schematron`                     |
| Phase 10 | XInclude + C14N + Catalog + XPointer 完整 | `xinclude`, `c14n`, `catalog`, `xpointer` | `xinclude`, `c14n`, `catalog`         |
| Phase 11 | HTML 解析         | `HTMLparser`, `HTMLtree`                            | `html`                                      |
| Phase 12 | 工具链与发布      | `xmllint`, `xmlcatalog`, `shell`, `debugXML`        | `facade`, `tools/xmllint`, `tools/xmlcatalog` |
| Phase 13 | 硬化与优化        | `runtest`, `fuzz`, `testlimits`                     | 性能、模糊、安全加固                         |

---

## Phase 0：项目骨架

### 范围
建立工作区、规范与 CI；代码体积最小。

### 任务
- 顶层 `cjpm.toml` 声明 workspace；预创建所有计划包目录与各自 `cjpm.toml`（空 `src/`）。
- 顶层 `cangjie-format.toml`、`config/cjlint_rule_list.json`。
- `README.md`：项目简介、构建指令、贡献指南。
- `.editorconfig`、`.gitignore`（忽略 `target/`、`*.cjo`、`*.cjvis` 等构建产物）。
- CI（GitHub Actions）：`cjpm build --all` + `cjpm test --all` + `cjfmt --check` + `cjlint`。
- 文档基线：将 `cangjie-regulations` 的项目结构 / 命名 / 格式化规范作为本项目的代码基线。

### 出口准则
- `cjpm build --all` 成功；
- CI 全绿；
- 所有计划包目录就位，后续阶段"填肉"即可。

---

## Phase 1：基础设施（`core` 包）

### 范围
对应 libxml2: `chvalid.c`, `xmlstring.c`, `buf.c`, `dict.c`, `hash.c`, `list.c`, `error.c`, `uri.c`, 部分 `globals.c`。

### 新增类型
`XmlVersion`, `Position`, `XmlError`, `XmlException`, `ErrorCollector`, `GrowableBuffer`, `BoundedBuffer`, `NameTable`, `QName`, `Uri`。

### 任务
1. **字符类**（`char_valid.cj`）：XML 1.0 / 1.1 的 `NameStartChar`、`NameChar`、`Char`、`PubidChar`、`Whitespace`；`const` 函数 + 区间查表；与 libxml2 `chvalid.c` 逐码点对照测试。
2. **缓冲**：`GrowableBuffer`（基于 `ArrayList<Byte>`）+ `BoundedBuffer` 装饰器。
3. **字符串工具**：`bytesToString(UTF-8)`, `escape(xml)`, `normalizeWhitespace`。其余多由仓颉 `String` 原生覆盖。
4. **`NameTable`**：`HashMap<String, String>` + `Mutex`；并发场景使用 `ConcurrentHashMap` 实现。
5. **`QName`**：不可变 `struct`，与 `NameTable` 协同 intern。
6. **错误模型**：`XmlError` enum、`Position` struct、`XmlException` class、`ErrorCollector` interface。
7. **`Uri`**：严格 RFC 3986；可选 Windows 盘符兼容开关。

### 出口准则
- 单元测试覆盖率 ≥ 90%；
- `Uri` 通过 libxml2 `test/URI` 黄金对比；
- 字符类与 libxml2 对每个码点结果一致（脚本生成对照）。

---

## Phase 2：编码与 I/O（`encoding`, `io` 包）

### 范围
对应 libxml2: `encoding.c`, `xmlIO.c`（去掉 nano-HTTP / FTP）。

### 新增类型
`Decoder`, `Encoder`, `DecodeStatus`, `EncodeStatus`, `BomKind`, `EncodingRegistry`；`IoSource`, `IoSink`, `FileSource`, `MemorySource`, `StringSource`, `StreamSource`, `FileSink`, `MemorySink`, `StreamSink`, `BufferedSink`, `IndentingSink`, `EncodingSink`。

### 任务
1. 内置解码器：UTF-8、UTF-16 LE/BE、UTF-32 LE/BE、ASCII、ISO-8859-1…15。
2. 内置编码器：UTF-8、UTF-16 LE/BE。
3. BOM 探测器 + 跳过逻辑。
4. `Decoder` / `Encoder` 接口含**状态保留**的流式 API。
5. I/O 适配器与装饰器。
6. 单元测试：编码往返、BOM 混用、错误字节序列定位。

### 出口准则
- 与 libxml2 `encoding.c` 输出在 UTF-16/32、Latin-1 等 10 个样本上逐字节一致；
- `IndentingSink` + `EncodingSink` 组合输出正确 BOM。

---

## Phase 3：词法 + 事件流（`parser` 包）

### 范围
`parser.c` / `parserInternals.c` 的**词法**与**语法骨架**；不含 DTD 校验，仅良构检查。

### 新增类型
`ByteReader`, `RuneReader`, `Lexer`, `Token`, `XmlParser`, `ParserOptions`, `XmlDecl`, `Attribute`, `NsContext`, `EntityResolver`, `SaxEvent`。

### 任务
1. `ByteReader` + `RuneReader`：行列号、字节偏移；XML 1.1 换行归一化。
2. `Lexer`：`enum Token` + 大 `match` 状态机，覆盖 XML 声明、元素标签、属性、文本、CDATA、注释、PI、DOCTYPE 头、实体引用。
3. `XmlParser`：把 token 流组合成 `Iterator<SaxEvent>`，命名空间在此层组装 `QName.uri`。
4. 内置实体 + 字符引用；外部实体经 `EntityResolver`（默认拒绝）。
5. `ParserOptions` 全字段实现。
6. Billion Laughs 与深度限制。
7. 容错模式：`recover = true` 时词法错误降级为 `SaxEvent.ParseError`。

### 出口准则
- 通过 W3C `xmltest/valid/sa/*.xml`（不含 DTD 验证项）约 200 条；
- `xmltest/not-wf/sa/*.xml`：识别非良构且错误位置 ±1 行；
- 10 MB 文档解析过程内存稳定（事件迭代器惰性证明）。

---

## Phase 4：DOM + SAX + Reader（`tree`, `sax`, `reader` 包）

### 范围
`tree.c`, `SAX2.c`, `xmlreader.c`（核心 API，不含验证集成）。

### 新增类型
`Node`（sealed）、`Document`, `Element`, `Attr`, `TextNode`, `CdataSection`, `Comment`, `Pi`, `EntityRef`, `DocumentFragment`, `XIncludeMarker`, `Namespace`；`SaxHandler`, `DefaultSaxHandler`；`XmlReader`, `ReaderNode`, `ReaderState`；`DocumentBuilder`, `DocumentScope`, `BuildOptions`, `ParseResult`。

### 任务
1. 数据模型：`sealed interface Node` 及全部分支类（DESIGN §5）。
2. `DocumentBuilder`：从 `Iterator<SaxEvent>` 构造 `Document`；流畅 API（基于尾随 lambda）。
3. `SaxHandler` 接口与 `DefaultSaxHandler`（全部默认空实现，便于派生）。
4. `XmlReader`（拉式）：内部缓存事件；提供 `read() / nodeType / localName / value / moveToNextAttribute` 等。
5. DOM 修改 API + `detached` 不变量校验。
6. 全部遍历迭代器（`children`, `descendants`, `ancestors`, `followingSiblings`, `precedingSiblings`）。
7. `@Visitor` 宏：自动派生 `accept` 与 `NodeVisitor<R>`。
8. 序列化最小版（完整版在 Phase 5）。

### 出口准则
- DOM 往返：libxml2 `test/` 下约 500 个 XML 文件在 parse → serialize → parse 后语义等价；
- `XmlReader` 处理 1 GB 合成文档内存不随增长；
- SAX 回调事件序列与 libxml2 `testSAX` 一致。

---

## Phase 5：输出（`writer`, `save` 包）

### 范围
`xmlwriter.c`, `xmlsave.c`（不含 C14N）。

### 新增类型
`XmlWriter`, `WriterOptions`, `DocumentSerializer`, `SerializeOptions`。

### 任务
1. `XmlWriter`：所有 `startX / endX` 接口 + 元素栈不变量校验。
2. `DocumentSerializer`：DOM 深度遍历 → `IoSink`；支持缩进、编码、是否省略 XML 声明、CDATA 包装策略。
3. 编码转换借 `EncodingSink`。
4. 命名空间序列化：抽出"作用域跟踪"模块，与 C14N 共用。
5. 黄金对比：libxml2 `result/` 中 save 相关样例。

### 出口准则
- 语义等价：序列化结果可被 parse 回与源文档相等；
- 字节等价（同选项下）：对非缩进 / UTF-8 / 保留空白的子集与 libxml2 字节对齐。

---

## Phase 6：XPath 1.0（`xpath` 包）

### 范围
`xpath.c` 的 XPath 1.0 部分。

### 新增类型
`XPathLexer`, `XPathParser`, `Expr`, `Step`, `Axis`, `NodeTest`, `XPathItem`, `NodeSet`, `XPathContext`, `CompiledXPath`, `XPathFunction`, `XPathNamespaceNode`。

### 任务
1. Lexer + Parser → AST。
2. `NodeSet` 惰性迭代 + 文档序索引（构造 `Document` 时为每个节点附 `docOrderId`）。
3. XPath 1.0 全部 28 个核心函数。
4. `XPathContext` 含变量、命名空间、自定义函数；线程局部。
5. `CompiledXPath` 不可变；多线程共享。
6. 轻量 XPointer（`element()` 方案）。
7. 单元测试覆盖 W3C XPath 1.0 测试集核心用例。

### 出口准则
- 通过 W3C XPath 1.0 测试集（MVP 子集）；
- 与 libxml2 `xmllint --xpath` 对 500 条随机表达式结果一致（节点集转字符串后比较）。

> **里程碑（MVP）**：Phase 0–6 完成构成"MVP 版本"，覆盖 libxml2 80% 使用场景（解析 + DOM + SAX + Reader + 序列化 + XPath）。

---

## Phase 7：DTD + 正则 + Pattern（`regexp`, `pattern`, `dtd` 包）

### 范围
`valid.c`, `xmlregexp.c`, `pattern.c`, `xmlautomata.h`。

### 新增类型
`Re`（sealed）、`CharRe`, `CharClassRe`, `SeqRe`, `AltRe`, `RepRe`, `CharSet`, `Nfa`, `Dfa`；`PatternExpr`, `CompiledPattern`, `PatternMatcher`；`DtdParser`, `DtdSubset`, `ElementDecl`, `AttributeDecl`, `EntityDecl`, `Notation`, `DtdValidator`, `Validator`。

### 任务
1. `regexp`：AST → NFA（Thompson）→ DFA（子集构造）；支持 Unicode 类别 / XML 字符类。
2. `dtd` 解析器：复用 `parser` 词法，产出 `DtdSubset` AST。
3. `DtdValidator`：内容模型编译为 DFA；属性类型校验（ID/IDREF/ENTITY…）；默认值/固定值填充；同时支持流式（`SaxEvent`）与树式（`Document`）。
4. `pattern`：流式 XPath 子集编译到自动机。
5. `XmlReader` 集成：开启 DTD 验证 + Pattern 过滤。

### 出口准则
- 通过 W3C `xmlconf` DTD 部分；
- `test/valid/` 全通过；
- `pattern` 单元测试覆盖率 ≥ 90%；
- `regexp` 与 libxml2 `testregexp` 在所有样例上行为一致。

---

## Phase 8：XML Schema 1.0（`schema` 包）

对应 libxml2 最大单文件 `xmlschemas.c`（28k 行），分两里程碑。

### Phase 8a：MVP 骨架

- XSD 文档解析：`schema / element / attribute / complexType / simpleType / group / attributeGroup / include / import`。
- 44 个内建简单类型 + facets（`minLength / maxLength / pattern / enumeration / minInclusive / ...`）。
- `CompiledSchema` + `XsdValidator`；DOM 路径优先。
- 流式校验复用 `SaxEvent`。
- 自举：用 CangjieXML 验证 XSD 自身（Schema-for-Schemas）。

### Phase 8b：完整语义

- 派生（`Restriction / Extension / List / Union`）完整语义；
- `xs:unique` / `xs:key` / `xs:keyref`（调用 `xpath`）；
- `xsi:type`、`abstract`、`substitutionGroup`；
- 通配符 `xs:any` / `xs:anyAttribute`；
- W3C XSD 测试集通过率 ≥ 90%；
- 与 libxml2 `testSchemas` 输出在错误消息层面大意一致。

---

## Phase 9：RelaxNG + Schematron

### Phase 9a：RelaxNG（`relaxng` 包）

- XML Syntax 解析 → `sealed interface Pattern` 与各分支类；
- Brzozowski 导数算法做验证；
- 内建数据类型复用 `schema` 简单类型库；
- 通过 OASIS RelaxNG 官方测试集；
- Compact Syntax 转换器作为 `tools/` 中的独立子工具，非核心路径。

### Phase 9b：Schematron（`schematron` 包）

- 解析 ISO/IEC 19757-3 规则文档；
- 调用 `xpath` 求值；
- 输出 SVRL 报告。

---

## Phase 10：XInclude + C14N + Catalog + XPointer 完整

### Phase 10a：Catalog（`catalog` 包）

- 解析 OASIS XML Catalog 1.1；
- 实现 `EntityResolver` 默认实现（按 catalog 查找）；
- 通过 libxml2 `test/catalogs/` 全部样例。

### Phase 10b：XInclude（`xinclude` 包）

- 处理 `xi:include` + `xi:fallback`；支持 `text` / `xml` 两种解析；与 XPointer 联动定位 fragment。

### Phase 10c：XPointer 完整（`xpointer` 包）

- 完整实现 `element()` / `xpath()` 方案；
- `xmlns()` 与历史 `fragid` 与 libxml2 现状对齐。

### Phase 10d：C14N（`c14n` 包）

- C14N 1.0、Exclusive C14N、C14N 1.1；
- 不可变 `NsContext` 驱动的确定性命名空间排序；
- `InclusionFilter` 接口；
- 通过 W3C C14N 官方测试集。

---

## Phase 11：HTML（`html` 包）

- 共享 `parser` 词法层；
- 增加 `HtmlInsertionMode` 状态机（WHATWG 子集）；
- 复用 `Document`，`isHtml = true`；
- 支持宽松解析（属性值不引号、隐式闭合等）；
- 与 libxml2 `HTMLparser` 行为差异在 `docs/libxml2-diff.md` 中逐条记录。

---

## Phase 12：工具链与 v1.0 发布

### 任务
1. `facade` 包：`public import` 常用 API，使下游一行 `import cangjie_xml.*` 即可。
2. `tools/xmllint`：覆盖 libxml2 `xmllint` 高频子命令（`--noout`, `--xpath`, `--relaxng`, `--schema`, `--dtdvalid`, `--c14n`, `--xinclude`, `--format`, `--pretty`, `--encode`, `--stream`, `--walker`, `--shell`）。
3. `tools/xmlcatalog`：`--add` / `--del` / `--resolve`。
4. 文档站点：`docs/` 下分模块 API 参考（cjc 文档生成）、`guides/` 入门、`docs/libxml2-diff.md` 差异说明、`docs/migration.md` 从 libxml2 迁移指南。
5. 发布：打 `v1.0.0` tag，发布说明附 libxml2 特性对照表。

### 出口准则
- `xmllint` 在 100 条选定命令行上与 libxml2 `xmllint` 语义等价（退出码与文本输出一致或经 `--format` 归一化后一致）。

---

## Phase 13：硬化与优化

### 性能
- `cjprof` 找出热点：命名解析、编码解码、`NodeSet` 排序；
- `xpath` 增加 `NodeSet` 复用池；
- 解析器引入批量字符扫描（用循环 + 编译器向量化提示，不引入汇编）；
- `CompiledSchema` LRU 缓存；
- 基线目标：单文件解析吞吐 ≥ libxml2 的 70%；XPath 求值 ≥ 60%。

### 安全
- 接入项目内置模糊器（基于 `.libxml2-2.15.3/fuzz/` 语料）；
- 复现 libxml2 历史 CVE，确保 CangjieXML 默认配置不命中；
- 启用 `cjlint` 安全规则集。

### 并发
- 可选"分段解析"并行实现；
- Schema / RelaxNG 验证并行化；
- `ParallelValidator`（多 Document × 1 Schema 并行）。

### 维护
- 发布 `v1.1`；
- 性能回归看板：每 PR 自动跑小基准，超阈值阻塞合入。

---

## 依赖与并行机会

```
Phase 0 → Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 ──┐
                                          │                  │
                                          └──→ Phase 6 ──────┤
                                                             │
                                  Phase 7 ←──────────────────┘
                                     │
                  ┌──────────────────┼──────────────────┐
                  ▼                  ▼                  ▼
               Phase 8           Phase 9           Phase 10
                  │                  │                  │
                  └──────────────────┴──────────────────┘
                                     ▼
                                 Phase 11 & 12
                                     ▼
                                 Phase 13
```

**可并行机会**：

- Phase 10d（C14N）只依赖 Phase 5，可与 Phase 6 之后任意阶段并行。
- Phase 11（HTML）只依赖 Phase 4，可与 Phase 6 之后任意阶段并行。
- Phase 9b（Schematron）只依赖 Phase 6，无需等 Phase 9a。

---

## 每阶段完成合格清单

每个阶段宣告"完成"必须同时满足：

- [ ] 新包在 `cjpm build --all` 无警告通过；
- [ ] 单元测试覆盖率 ≥ 85%（`cjcov`）；
- [ ] `cjfmt --check` / `cjlint` 零违规；
- [ ] 本阶段指定的黄金文件对比全通过；
- [ ] `examples/` 提供至少 1 份可运行示例；
- [ ] 公共 API 完整 doc 注释；
- [ ] `DESIGN.md` 与 `ROADMAP.md` 相应章节同步更新，必要时追加 ADR。

---

## 技术验证 Demo 计划

利用问题描述提供的[仓颉 SDK 1.0.5](https://github.com/SunriseSummer/CangjieSDK/releases/download/1.0.5/cangjie-sdk-linux-x64-1.0.5.tar.gz) 在 `demos/` 目录下做"先立后破"的最小验证（不计入发布产物）：

| 验证点                                            | 最小 Demo                                              |
| ------------------------------------------------- | ------------------------------------------------------ |
| `sealed interface Node` + 大 `match` 的性能       | 合成 100 万节点树做一次 visitor 遍历                    |
| Brzozowski 导数算法                               | 100 行 RelaxNG 子集原型，验证子集语义正确性             |
| `Iterator<SaxEvent>` + 背压                      | 5 GB 合成 XML 流仅取前 100 事件，内存稳定               |
| `NameTable` 与 `String` intern 的 GC 表现        | 百万次相同 tag 解析的内存曲线                          |
| NFA → DFA 构造 + Unicode 类别                     | 对 XSD 正则 `[\p{IsBasicLatin}&&\w]` 等构造后匹配       |
| 多线程 XPath 并发求值                             | 1 棵 DOM × N 线程 × M 查询的压测                        |
| 宏派生 Visitor                                    | 改一次 `Node` 分支，确认宏重新生成 visitor 接口         |

---

## 风险与缓解

| 风险                                  | 缓解                                                                          |
| ------------------------------------- | ----------------------------------------------------------------------------- |
| Schema 体量大                         | Phase 8 拆 8a / 8b；8a 先打通骨架 + 自举                                       |
| W3C 测试套件许可                      | `testkit` 仅含驱动器，不含套件本体；用户自行获取                                |
| 仓颉 SDK 迭代                         | `cjpm.toml` 锁定 SDK 1.0.5；升级走单独分支整体回归                             |
| 黄金文件差异维护                      | 所有差异在 `docs/libxml2-diff.md` 标注，避免"看似失败实为预期差异"             |

---

_本计划遵循 [`cangjie-regulations`](./.github/skills/cangjie-regulations/) 的工程规范；阶段完成时更新进度，并与 [`DESIGN.md`](./DESIGN.md) 保持一致。_
