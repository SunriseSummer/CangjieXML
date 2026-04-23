# CangjieXML 渐进开发计划（Roadmap）

> 本文件与 [`DESIGN.md`](./DESIGN.md) 配套使用。
> 开发基调：**小步快跑、每个里程碑可独立交付与回归**。每一阶段结束时项目都应处于"可编译、可测试、可运行示例"的状态。
>
> 工具链：`cjpm`（构建/依赖/测试）、`cjfmt`（格式化）、`cjlint`（静态检查）、`cjprof`（性能）、`cjcov`（覆盖率）。
> 仓颉 SDK：https://github.com/SunriseSummer/CangjieSDK/releases/download/1.0.5/cangjie-sdk-linux-x64-1.0.5.tar.gz

---

## 路线全景图

```
M0 项目脚手架 ──▶ M1 数据模型 ──▶ M2 序列化 ──▶ M3 解析器 ──▶ M4 查询/扩展/Builder
                                                                    │
                                      ┌─────────────────────────────┤
                                      ▼                             ▼
                               M5 访问者/迭代              M6 IO/错误/options 完善
                                      │                             │
                                      └──────────────┬──────────────┘
                                                     ▼
                                       M7 并发/线程安全/parseMany
                                                     ▼
                                        M8 回归/基准/文档 1.0
                                                     ▼
                                        M9+ 进阶（宏、SAX、XPath 子集）
```

每个里程碑包含：**目标（What） / 交付物（Deliverables） / 验收标准（DoD） / 技术要点 / 风险**。

---

## M0 — 工程脚手架与基础设施

### 目标
拉起可构建的仓颉项目骨架，接通测试与 CI。

### 交付物
- 根目录 `cjpm.toml`（module = `cangjie_xml`，版本 `0.1.0`）。
- `src/cangjie_xml/lib.cj` 导出占位 API，`src/cangjie_xml/prelude.cj` 定义 `MAX_ELEMENT_DEPTH` 等常量。
- `tests/smoke_test.cj`：调用一个占位函数并断言 `true`，跑通 `cjpm test`。
- `examples/hello/` 可以 `cjpm run`。
- `.gitignore`、`README.md`（项目简介 + 如何构建）。
- （可选）GitHub Actions：下载 SDK → `cjpm build` → `cjpm test`。

### DoD
- `cjpm build` 成功。
- `cjpm test` 所有用例通过。
- `cjfmt -c .` / `cjlint` 零告警。

### 风险
- SDK 下载与 CI 环境兼容性 → 在本地 Linux x64 先行验证。

---

## M1 — 核心 DOM 数据模型（只读骨架）

### 目标
落地 `XmlNode`/`XmlNodeKind`/`XmlElement`/`XmlAttribute`/`XmlText`/`XmlComment`/`XmlDeclaration`/`XmlUnknown`/`XmlDocument` 类型，以及内部的 `ChildList` 双向链表。**此阶段没有解析器**，只能通过 API 手工构造 DOM。

### 交付物
- `model` 子包全部文件。
- `errors/error.cj` 的 `XmlError` / `SourcePos` / `XmlException`（暂不填实现细节）。
- 基础单元测试：
  - 构造空文档、添加子元素、设置属性、读取属性。
  - `parent/document/firstChild/nextSibling` 链路正确。
  - `append/prepend/insertBefore/remove` 行为。
  - `shallowClone`、`shallowEqual`。
  - `kind()` 与模式匹配穷举性。

### 技术要点
- `sealed interface XmlNode` 保证仅内部实现子类。
- `XmlNodeKind` 枚举构造器承载具体子类型引用。
- 双向链表内部实现，O(1) 插入/删除；属性内部 `ArrayList<XmlAttribute>` + `HashMap<String, Int64>` 索引。
- 全部使用 `String`（不暴露 `Array<Byte>`）；内部暂不做零拷贝（v1.0 性能优化期再引入）。

### DoD
- 至少 30 个单元用例通过。
- `cjcov` 模型包覆盖率 ≥ 85%。

### 风险
- `sealed` + 跨包实现：确认所有节点子类必须与 `XmlNode` 同包（`cangjie_xml.model`）。

---

## M2 — 序列化器（Printer）

### 目标
先做"写"再做"读"——这样 M3 可以直接用 "构造 → 打印 → 字符串对比" 做测试。

### 交付物
- `print/printer.cj` 实现 `XmlPrinter`（至少支持写入 `StringOutput`）。
- `print/escape.cj`：文本/属性/CDATA 转义。
- `print/format.cj`：缩进、紧凑、自闭合元素策略。
- `XmlDocument.toString(compact! = false)` 接通。
- `XmlVisitor` 接口与 `XmlPrinter` 作为其实现。
- 单元测试：
  - 打印平凡文档、嵌套、属性、文本、CDATA、注释、声明、未知节点。
  - 紧凑 vs 缩进格式的黄金字符串。
  - 特殊字符转义。
  - 空元素自闭合。

### DoD
- 手工构造的 10+ DOM 场景，`toString()` 输出与 tinyxml2 参考输出（离线生成）字节一致（除可解释的空白差异外）。
- 公共 API 100% 文档注释。

### 风险
- tinyxml2 对空白与自闭合元素的细节差异——通过黄金文件对齐。

---

## M3 — 解析器（Parser）

### 目标
支持从 `String` / `Array<Byte>` / 文件路径解析出完整 DOM。

### 交付物
- `parse/source.cj`：`XmlSource`、BOM 识别、换行规范化、行偏移表。
- `parse/entity.cj`：预定义实体 + 字符引用解码。
- `parse/lexer.cj`：按需 token 化。
- `parse/parser.cj`：递归下降生成 DOM。
- `parse/options.cj`：`ParseOptions { whitespace, processEntities, maxDepth, strictUtf8 }`。
- `XmlDocument.parse` / `parseBytes` / `loadFile` 接通。
- 单元测试：
  - 所有节点类型（Element/Text/CDATA/Comment/PI/Declaration/Doctype-as-Unknown）。
  - 深度 499 成功 / 501 失败（`ElementDepthExceeded`）。
  - BOM、UTF-8 多字节内容。
  - 错误路径：`MismatchedElement`, `ParsingAttribute`, `EmptyDocument`, …
  - `ParseOptions.whitespace`: Preserve / Collapse / Pedantic。
  - **parse → print → parse 幂等测试**（与 M2 联动，至少 20 组）。

### 技术要点
- Slice 机制（`data` 引用 + start/end 下标）。
- 错误统一返回 `Result<_, XmlError>`；顶层 `parse` 再把 `Err` 同步写入 `XmlDocument.error` 字段并返回 `Err`。
- 源位置通过 `SourcePos` 精确指出（含行号）。

### DoD
- 从 tinyxml2 `test/resources` 移植≥ 8 个 XML 样例，全部通过 parse → print → parse 幂等。
- 18 个 `XMLError` 枚举值对应至少 1 个用例。
- `cjcov` parse 包覆盖率 ≥ 80%。

### 风险
- 实体解码、空白策略的细节；通过对照 tinyxml2 `xmltest.cpp` 的断言移植消化。
- UTF-8 非法字节的处理：固定"非严格"默认值，严格模式作为可选开关。

---

## M4 — 查询 / 扩展 / 构建器

### 目标
让日常使用体验达到"现代脚本语言"水准：类型化属性访问、方便的子节点查找、DSL 式构建。

### 交付物
- `query/element_attr_ext.cj`：`intAttr/boolAttr/...`、`queryXxxAttr` 返回 `Result`。
- `query/element_text_ext.cj`：`innerText/setInnerText`。
- `query/iteration.cj`：`children/elements/elements(name)/descendants/ancestors/siblings`。
- `query/find.cj`：`findFirst(predicate)` / `findAll(predicate)`。
- `XmlAttrConvertible` 接口 + `Int64/UInt64/Float64/Bool/String/Rune` 等内置扩展。
- `build/document_builder.cj` + `build/element_builder.cj` 构建器。
- 示例：`examples/config_reader/`、`examples/dsl_writer/`。
- 单元测试：
  - 类型化属性读写全类型覆盖，含错误路径。
  - 自定义类型通过 `XmlAttrConvertible` 双向转换。
  - 迭代器惰性求值（不应一次物化整个子树）。
  - Builder 链式构造得到的 DOM == 对应解析结果（深比较）。

### DoD
- `setAttr<T>` / `pushAttribute<T>` 支持所有内置数值类型 + `Bool` + `String`。
- 至少 25 个查询/构建用例通过。

### 风险
- 扩展函数的命名冲突（确保 `query` 子包独立，按需 `import`）。

---

## M5 — 访问者 & 高阶遍历

### 目标
提供两种遍历风格：OO 风格的 `XmlVisitor`、函数式的 `walk + WalkControl`。

### 交付物
- `visitor/visitor.cj`：`XmlVisitor` 接口（默认方法全部 `return true`）。
- `XmlDocument.accept(visitor)` / `XmlElement.accept(visitor)`（已在 M2 完成架子，这里补齐行为）。
- 函数式：`walk(node, (XmlNodeKind) -> WalkControl)`。
- 示例：提取所有 `<a href>` 链接、统计各 tag 出现次数。
- 用例：
  - Visitor 在 `visitEnter` 返回 `false` 时跳过子树。
  - `walk` 返回 `SkipChildren`/`Stop` 行为正确。
  - 序列化器正是一个 `XmlVisitor`（用黄金字符串验证）。

### DoD
- Visitor / walk 双路径均通过全部 M2 的打印测试。

---

## M6 — IO / 错误 / 选项完善

### 目标
补齐 `saveFile`、流式输入输出、`ParseOptions` / `PrinterOptions`，以及错误报告的长文本描述。

### 交付物
- `io/loader.cj`: `loadFile` 使用 `try-with-resources` + `InputStream.readToEnd()`。
- `io/writer.cj`: `saveFile(path, compact)`。
- `errors/error.cj`: `XmlError.message()` / `XmlError.pos()`, `XmlError.toLongForm()` 友好诊断（含行/列）。
- `PrinterOptions { compact, indent, selfClosing, boolFormat }`。
- 用例：
  - 文件不存在 → `FileNotFound`。
  - 写入只读目录 → `FileWriteError`。
  - 大文件（≥ 5 MB）可正常解析并打印。
  - `toLongForm()` 的断言文案。

### DoD
- 所有面向用户的错误场景都能给出"人类可读、含位置信息"的描述。

---

## M7 — 并发与线程安全

### 目标
落地并发解析能力 & 只读 DOM 共享安全保证。

### 交付物
- `XmlDocument.parseMany(inputs: Array<XmlSource>): Array<Result<XmlDocument, XmlError>>`：内部用 `spawn` + `Future` 并行化，线程数默认 = CPU 核心。
- `XmlDocument.withWriteLock { doc => ... }`：基于 `Mutex` 的可选写锁封装，帮助用户同步修改。
- 文档中明确"只读 DOM 多线程安全，写入需用户同步"的契约。
- 并发测试：
  - 4 线程并行解析 20 份文档全部成功，线性扩展 ≥ 3×。
  - 多线程只读迭代同一个 DOM 不崩溃、结果等价单线程。
  - 压力测试（1 分钟）无死锁、无异常逃逸。

### DoD
- 并发包全部测试在 `cjpm test --parallel` 模式下稳定通过 100 次。

### 风险
- `spawn` 与 GC 的交互 → 参考 `cangjie-lang-features/concurrency`，优先使用 `Future` 汇聚，避免裸线程生命周期管理。

---

## M8 — 1.0 回归、基准、文档

### 目标
**发布 `cangjie_xml` v1.0.0**。

### 交付物
- **回归套件**：把 tinyxml2 `xmltest.cpp` 的断言逐条移植（≥ 200 条），全部通过。
- **基准**：`cjprof` 脚本 + 一页 `BENCH.md` 报告：解析 MB/s、打印 MB/s、`parseMany` 线性比、峰值内存。
- **文档**：
  - `README.md`：安装、快速上手、API 一览表。
  - `docs/guide/` 目录：五到十篇教程（解析、构建、查询、访问者、并发、扩展自定义类型、错误处理、与 tinyxml2 迁移对照）。
  - API 注释全部到位，`cjdoc`（或等效工具）可生成。
- 打好 tag `v1.0.0`，在仓库 Release 页面发布。

### DoD
- 覆盖率 ≥ 85%（核心包 ≥ 90%）。
- 公共 API 100% 有文档。
- 基准达成 §DESIGN §10 的性能目标。
- CI 全绿。

---

## M9+ — 1.x 进阶特性（并行规划）

> 每一项独立里程碑，发布为 minor 版本。

### M9.1 — SAX 风格流式解析 (`v1.1`)
- 接口：`XmlDocument.stream(source: XmlSource): Iterator<XmlEvent>`。
- `XmlEvent` enum：`StartElement / EndElement / Text / Comment / Decl / Unknown / Error`。
- 适用于 > 100 MB 文档；不构建 DOM。

### M9.2 — 宏驱动的 POCO 绑定 (`v1.2`)
- 属性宏：`@XmlRoot("book") class Book { @XmlAttr("id") var id: Int64 = 0; @XmlElement("title") var title: String = "" }`。
- 代码生成 `fromXml / toXml`，与 `XmlDocument` 互通。
- 依赖 `std.ast`、`@Annotation`、反射（已评估仓颉支持）。

### M9.3 — XPath 子集 (`v1.3`)
- 支持 `/a/b`, `//b`, `//b[@x='1']`, `b[2]`, `text()`。
- 以 `XmlElement.xpath(expr: String): Iterable<XmlNode>` 暴露。

### M9.4 — 性能优化（可选 `v1.4`）
- 内部节点对象池（保持 API 不变）。
- `String` interning（tag/attr 名）。
- 解析阶段尝试零拷贝 `Slice` → `String` 延迟物化。

---

## 质量门禁（跨里程碑统一适用）

每次 PR（含中间推送）都必须满足：

1. `cjpm build` 零错误、零警告。
2. `cjpm test` 全通过。
3. `cjfmt -c .` 无变更建议。
4. `cjlint` 0 error。
5. 新增 / 变更代码必须带单元测试。
6. 公共 API 必须有 `///` 文档注释。
7. 不引入非仓颉标准库的三方依赖（`stdx.*` 可在明确需要时引入，需在 PR 描述中说明）。
8. 不含 `// TODO` 外的 FIXME；必要时用 issue 替代代码注释。

---

## 依赖与范围声明

- **仅使用**仓颉标准库 `std.*`：`std.collection`、`std.io`、`std.sync`、`std.unittest`、`std.time` 等。
- **不使用**：FFI/CFFI、C/C++ 源码、任何非仓颉包管理器的三方库。
- `stdx.*` 的使用策略：默认不启用；若在 M9+ 需要日志/编码辅助再评估引入，必须在 `DESIGN.md` 与 `ROADMAP.md` 中登记。

---

## 追溯矩阵：tinyxml2 功能 → 里程碑

| tinyxml2 能力 | 里程碑 |
|---|---|
| 空文档/声明解析 | M3 |
| 嵌套元素 + 属性 | M1 (模型)、M3 (解析) |
| CDATA / Comment / Doctype / PI | M3 |
| BOM / 换行规范化 | M3 |
| Whitespace 三模式 | M3 |
| 属性类型化访问（Int/Int64/UInt/UInt64/Bool/Float/Double） | M4 |
| QueryXxxAttribute（带错误码） | M4 |
| Printer（紧凑 / 缩进 / 流式） | M2 / M5 |
| Visitor | M2 骨架 / M5 完善 |
| Handle / ConstHandle | **删除**（由 `Option<T>` + `?.` 取代） |
| MemPool | **删除**（由 GC 替代，必要时 v1.4 内部优化） |
| 错误码 & `ErrorStr()` | M6 |
| `LoadFile` / `SaveFile` | M6 |
| 深度保护 500 | M3 |
| 并发（tinyxml2 本身无） | M7（**新增能力**） |

---

以上计划是"滚动式"的：每完成一个里程碑，回顾并调整后续计划中的细节。最终的验收标准以 `DESIGN.md` §10（性能目标）与本文件各 M 的 DoD 为准。
