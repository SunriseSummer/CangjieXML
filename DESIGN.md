# CangjieXML 软件设计文档

> 本文档描述用仓颉（Cangjie）编程语言对 [libxml2 v2.15.3](./.libxml2-2.15.3) 进行**优化重构式复刻**的架构与设计原则。
>
> 目标是在保持 W3C XML 规范语义与 libxml2 功能对等的前提下，摒弃 C 层面的指针、`void*`、全局 hook 风格，充分运用仓颉的现代语言特性，建立一个**类型安全、内存安全、线程友好、可组合、可扩展**的纯仓颉 XML 工具链。
>
> 本文件只描述 **做什么（What）** 与 **为什么（Why）**，不涉及具体代码。配套文件 [`ROADMAP.md`](./ROADMAP.md) 描述 **何时做（When）** 与 **如何分阶段（How）**。

---

## 目录

1. [背景与目标](#1-背景与目标)
2. [设计原则](#2-设计原则)
3. [术语与命名约定](#3-术语与命名约定)
4. [项目结构](#4-项目结构)
5. [数据模型](#5-数据模型)
6. [字符、编码与 I/O](#6-字符编码与-io)
7. [解析器架构](#7-解析器架构)
8. [树操作 API](#8-树操作-api)
9. [XPath 与 Pattern](#9-xpath-与-pattern)
10. [验证：DTD / XSD / RelaxNG / Schematron](#10-验证dtd--xsd--relaxng--schematron)
11. [输出：Writer / Save / C14N](#11-输出writer--save--c14n)
12. [HTML、XInclude、Catalog](#12-htmlxincludecatalog)
13. [并发模型](#13-并发模型)
14. [错误模型与诊断](#14-错误模型与诊断)
15. [安全默认](#15-安全默认)
16. [宏与元编程](#16-宏与元编程)
17. [测试策略](#17-测试策略)
18. [与 libxml2 的刻意差异](#18-与-libxml2-的刻意差异)
19. [架构决策记录（ADR）](#19-架构决策记录adr)
20. [与仓颉 SDK 的对齐](#20-与仓颉-sdk-的对齐)
21. [风险与缓解](#21-风险与缓解)

---

## 1. 背景与目标

### 1.1 libxml2 概览

libxml2 是 GNOME 项目孵化的 XML 工具集，以 C89 实现，约 17 万行核心 C 代码，按职能可划分为下列子系统：

| 领域                       | libxml2 主要源文件                                  |
| -------------------------- | --------------------------------------------------- |
| 树 / 节点模型              | `tree.c`, `include/libxml/tree.h`                   |
| 解析器（推 / 拉 / SAX）    | `parser.c`, `parserInternals.c`, `SAX2.c`           |
| 实体 / 字典 / 符号表       | `entities.c`, `dict.c`, `hash.c`, `list.c`          |
| 字符串 / 缓冲 / 字符类     | `xmlstring.c`, `buf.c`, `chvalid.c`                 |
| 字符编码                   | `encoding.c`                                        |
| I/O 抽象                   | `xmlIO.c`, `nanohttp.c`                             |
| URI / Catalog              | `uri.c`, `catalog.c`                                |
| DTD 验证                   | `valid.c`                                           |
| 正则 / 自动机 / 模式       | `xmlregexp.c`, `pattern.c`                          |
| XML Schema (XSD)           | `xmlschemas.c`, `xmlschemastypes.c`                 |
| RelaxNG / Schematron       | `relaxng.c`, `schematron.c`                         |
| XPath / XPointer / XInclude| `xpath.c`, `xpointer.c`, `xinclude.c`               |
| 规范化 C14N                | `c14n.c`                                            |
| 流式读 / 写                | `xmlreader.c`, `xmlwriter.c`, `xmlsave.c`           |
| HTML 解析与输出            | `HTMLparser.c`, `HTMLtree.c`                        |
| 错误 / 全局 / 线程         | `error.c`, `globals.c`, `threads.c`                 |
| 命令行 / 调试              | `xmllint.c`, `xmlcatalog.c`, `shell.c`, `debugXML.c`|

### 1.2 项目目标

1. **功能对等（核心子集）**：覆盖 XML 1.0/1.1 解析与序列化、命名空间、DTD、XPath 1.0、XInclude、C14N 1.0/1.1、XML Schema 1.0、RelaxNG 的主流使用场景。
2. **接口现代化**：摒弃 `void*` 上下文、`int` 返回码、全局 hook，改用仓颉的 `interface`、`enum`、`Option` / `Result`、`Iterable` 与 `Resource`。
3. **纯仓颉实现**：仅依赖 `std.*` 与必要的 `stdx.*`（如 TLS、压缩）；不调用 C 库、不走 CFFI。
4. **线程友好**：编译产物（`CompiledXPath`、`CompiledSchema`）与已构造的 `Document` 视为不可变，可被多线程共享；可变状态封装在解析器/写入器实例中，单实例单线程使用。
5. **可裁剪**：模块按 `cjpm` 子包划分，下游按需 import。
6. **可扩展**：用户可用 `extend` 为节点添加方法，可实现 `EntityResolver`、`ParserInputSource`、`OutputSink` 等接口替换默认行为。

### 1.3 非目标

- 不追求与 libxml2 ABI 兼容（结构布局、宏、函数名完全不同）。
- 不内嵌 HTTP / FTP 客户端；libxml2 的 `nanohttp.c` / `nanoftp.c` 不复刻，改为可插拔的 `EntityResolver` 接口，由调用方接入 `stdx.net.http`。
- 不提供 Python / Perl 绑定（属于宿主语言生态范畴）。
- 不复刻 `xmlmodule`（C 动态库插件机制）；改用仓颉 `package` + `interface` 的插件化方案。

---

## 2. 设计原则

| 编号 | 原则                | libxml2 的 C 做法                              | CangjieXML 的做法                                                            |
| ---- | ------------------- | ---------------------------------------------- | ---------------------------------------------------------------------------- |
| P1   | 代数数据类型优先    | `xmlElementType` + 单个超集 `xmlNode` 结构    | `sealed interface Node` + 各分支 `class`；用 `match` 穷尽处理                |
| P2   | 不可变字符串        | 自定义 `xmlChar*`（UTF-8 字节串）              | 直接使用仓颉 `String`（UTF-8）；需要原始字节时使用 `Array<Byte>`             |
| P3   | 类型化错误          | 全局 `xmlError` + 返回码                       | `enum XmlError` + `class XmlException <: Exception`；内部 `Result`，公共抛异常 |
| P4   | 安全的资源管理      | 手工 `xmlFree*`，易触发 UAF                   | 仓颉 GC + `Resource` / try-with-resources 管理 I/O 与锁                      |
| P5   | 组合优于继承        | SAX 回调为函数指针表                           | `interface SaxHandler` + 默认实现 + mixin 组合                               |
| P6   | 并发即一等公民      | 全局锁 + 线程局部                              | `Mutex` / `AtomicReference` / `spawn`；不可变制品多线程共享                  |
| P7   | 零拷贝读取          | 手写状态机 + 缓冲拷贝                          | 输入流分片 + `Array<Byte>` 视图 + 惰性字符串化                               |
| P8   | 迭代器与管道        | 手工 `next` / `prev` 指针                      | 全部容器实现 `Iterable`；用 `\|>` 拼接过滤、转换、序列化                      |
| P9   | 元编程消除样板      | 大量 `#define` 宏                              | 仓颉宏（`@Visitor`, `@SchemaModel`, `@XPathFunction`）派生样板               |
| P10  | 测试优先            | 外部 `runtest.c` + 黄金文件                    | 包内 `xxx_test.cj` + `@Test` + W3C TestSuite 驱动器                          |

---

## 3. 术语与命名约定

为避免规范分歧，本项目所有源代码与文档遵循如下命名约定（与 [`cangjie-regulations`](./.github/skills/cangjie-regulations/) 保持一致）。

### 3.1 标识符规则

| 类别                                | 规则                          | 示例                                         |
| ----------------------------------- | ----------------------------- | -------------------------------------------- |
| 包名                                | 全小写 + 下划线               | `core`, `parser`, `xpath`, `relaxng`         |
| 源文件名                            | 全小写 + 下划线 + `.cj`       | `name_table.cj`, `qname.cj`                  |
| `class` / `struct` / `interface` / `enum` / 类型别名 | 大驼峰（PascalCase）          | `XmlParser`, `SaxHandler`, `XPathContext`    |
| 函数 / 方法 / 局部变量              | 小驼峰（camelCase）           | `parseDocument`, `nodeName`                  |
| 全局 `let` / `static let` / `const` | 全大写 + 下划线               | `XML_NAMESPACE_URI`, `DEFAULT_MAX_DEPTH`     |
| 泛型类型参数                        | 单大写字母或 PascalCase       | `T`, `K`, `V`, `Item`                        |

### 3.2 缩写处理（PascalCase 中）

仓颉规范要求 PascalCase。所有 XML 领域常见缩写遵循"首字母大写其余小写"原则，唯一保留官方拼写形式的是 `XPath`：

| 含义              | 文档与代码统一写法 |
| ----------------- | ------------------ |
| XML               | `Xml`              |
| Document Type Definition | `Dtd`       |
| XML Schema (XSD)  | `Xsd`              |
| RelaxNG           | `RelaxNg`          |
| HTML              | `Html`             |
| URI               | `Uri`              |
| URL               | `Url`              |
| I/O               | `Io`               |
| SAX               | `Sax`              |
| CDATA             | `Cdata`            |
| BOM               | `Bom`              |
| UTF-8 / UTF-16    | `Utf8` / `Utf16`   |
| XPath / XPointer  | `XPath` / `XPointer`（保留惯例，唯二例外） |

由此派生的核心类型示例：`XmlParser`, `XmlReader`, `XmlWriter`, `XmlError`, `XmlException`, `SaxHandler`, `SaxEvent`, `DtdValidator`, `XsdValidator`, `RelaxNgValidator`, `HtmlParser`, `Uri`, `IoSource`, `XPathExpr`, `XPathContext`。

### 3.3 术语对照表

| W3C / libxml2 概念        | 本项目术语            | 说明                                       |
| ------------------------- | --------------------- | ------------------------------------------ |
| Element node              | `Element`             | 节点子类                                   |
| Attribute node            | `Attr`                | 节点子类                                   |
| Text node                 | `TextNode`            | 节点子类（避免与字段名 `text` 混淆）        |
| CDATA section             | `CdataSection`        | 节点子类                                   |
| Processing instruction    | `Pi`                  | 节点子类                                   |
| Document                  | `Document`            | 根节点                                     |
| Document fragment         | `DocumentFragment`    | 节点子类                                   |
| Notation                  | `Notation`            | DTD 元数据，不进入 `Node` 体系              |
| Entity declaration        | `EntityDecl`          | 同上                                        |
| Element declaration       | `ElementDecl`         | 同上                                        |
| Attribute declaration     | `AttributeDecl`       | 同上                                        |
| `xmlChar*`                | `String` / `Array<Byte>` | 视语义而定                              |
| `xmlNs`（命名空间节点）   | `Namespace`           | 仅作 XPath 语义节点存在，不进入 `Node` 体系 |
| `xmlDict`                 | `NameTable`           | 字符串 intern 池                           |
| `xmlSAXHandler`           | `SaxHandler`          | 接口而非函数指针表                         |
| `xmlParserCtxt`           | `XmlParser`           | 解析器实例                                  |
| `xmlTextReader`           | `XmlReader`           | 拉式读                                      |
| `xmlTextWriter`           | `XmlWriter`           | 流式写                                      |
| `xmlXPathContext`         | `XPathContext`        | XPath 求值上下文                           |
| `xmlXPathObject`          | `XPathItem`           | XPath 值（节点集 / 字符串 / 数 / 布尔）     |

---

## 4. 项目结构

采用 `cjpm` **工作区（workspace）** 布局；每个目录都是一个独立可发布的仓颉包，顶层 `cjpm.toml` 声明成员。包名内部不再加 `xml_` 冗余前缀——工作区本身已经叫 CangjieXML。

```
CangjieXML/
├── cjpm.toml                      # workspace + 顶层元数据
├── cangjie-format.toml            # 格式化配置
├── DESIGN.md                      # 本文件
├── ROADMAP.md                     # 渐进开发计划
├── README.md                      # 使用入门
├── docs/                          # 模块手册、设计补充、迁移指南
├── examples/                      # 端到端可运行示例
├── packages/
│   ├── core/                      # 字符类、缓冲、NameTable、错误、Position、Uri
│   ├── encoding/                  # 编码注册表、Decoder/Encoder、BOM 探测
│   ├── io/                        # IoSource / IoSink 接口与适配器
│   ├── parser/                    # 词法器 + 事件流（SaxEvent 生成器）
│   ├── tree/                      # Document / Node / Element / Attr / Namespace
│   ├── sax/                       # SaxHandler 接口与默认实现
│   ├── reader/                    # XmlReader（拉式）
│   ├── writer/                    # XmlWriter（流式写）
│   ├── save/                      # DocumentSerializer（DOM → 文本）
│   ├── regexp/                    # XSD 正则：AST → NFA → DFA
│   ├── pattern/                   # 流式 XPath 子集，用于 reader/schema selector
│   ├── xpath/                     # XPath 1.0 引擎
│   ├── xpointer/                  # XPointer（element() / xpath() 方案）
│   ├── dtd/                       # DTD 解析与验证
│   ├── schema/                    # XML Schema 1.0
│   ├── relaxng/                   # RelaxNG（Brzozowski 导数算法）
│   ├── schematron/                # Schematron（基于 xpath）
│   ├── catalog/                   # OASIS XML Catalog 1.1
│   ├── xinclude/                  # XInclude 1.0
│   ├── c14n/                      # C14N 1.0 / 1.1 / Exclusive
│   ├── html/                      # HTML 解析与序列化（共享 parser 词法）
│   ├── testkit/                   # W3C TestSuite 驱动器、黄金文件比对
│   └── facade/                    # 门面包：public import 上述常用 API
├── tools/
│   ├── xmllint/                   # 可执行：对应 libxml2 xmllint
│   └── xmlcatalog/                # 可执行：对应 libxml2 xmlcatalog
└── .libxml2-2.15.3/               # 上游参考源（只读）
```

每个包均遵循仓颉项目标准布局：

```
packages/<name>/
├── cjpm.toml
├── src/
│   ├── <main_files>.cj
│   └── <main_files>_test.cj      # 单元测试与被测文件同目录
└── examples/                      # 可选
```

### 4.1 依赖方向

```
core ──┬─> encoding ──> io ──> parser ──> sax ──> reader
       │                          │
       │                          └─> tree ──> writer ──> save
       │                                ↑
       ├─> regexp ──> pattern ──> xpath ──> xpointer
       │                            │
       │             dtd ───────────┘
       │             schema, relaxng, schematron ──> 依赖 xpath / regexp / pattern
       │
       └─> catalog, xinclude, c14n, html
                                   │
                                   ▼
                                facade ──> tools/xmllint, tools/xmlcatalog
```

依赖关系是**有向无环图**；所有跨包依赖均在各自 `cjpm.toml` 中显式声明。

---

## 5. 数据模型

### 5.1 节点树

libxml2 将 14 种节点塞进同一个超集结构 `xmlNode`，字段复用造成大量 `if (type == ...)` 分支，是历史上多次"类型混淆"CVE 的根源。CangjieXML 改用 `sealed interface` + 分支类：

```text
sealed interface Node {
    prop parent: ?Element
    prop document: ?Document
    func accept<R>(v: NodeVisitor<R>): R    // 配合 @Visitor 宏自动派生
}

class Document         <: Node { ... }      // 含 XmlDecl、Dtd?、根 Element
class Element          <: Node { ... }      // 名字、命名空间、属性表、子节点
class Attr             <: Node { ... }      // 属性节点
class TextNode         <: Node { ... }      // #text
class CdataSection     <: Node { ... }      // <![CDATA[...]]>
class Comment          <: Node { ... }      // <!-- ... -->
class Pi               <: Node { ... }      // <?target data?>
class EntityRef        <: Node { ... }      // &name;
class DocumentFragment <: Node { ... }      // 文档片段
class XIncludeMarker   <: Node { ... }      // 合并 XINCLUDE_START / XINCLUDE_END
```

设计要点：

- **`sealed`**：限制实现于 `tree` 包内，使外部 `match` 编译期穷尽。
- **公开访问**：节点字段全部走 `prop`/`mut prop`，避免 libxml2 中 `XML_DEPRECATED_MEMBER` 仍暴露字段的尴尬。
- **DTD 元数据**（`Notation` / `EntityDecl` / `ElementDecl` / `AttributeDecl`）**不进入** `Node`，而是 `Dtd` 的成员；它们从未出现在文档主干中，剥离即从类型上消除一类 CVE。
- **命名空间节点**：libxml2 中复用 `xmlNode` 布局但实质为 `xmlNs`，是历史 CVE 重灾区。CangjieXML 把命名空间节点仅作为 XPath 语义节点（`class XPathNamespaceNode`），不进入 `Node` 体系。

### 5.2 名字表（`NameTable`）

`xmlDict` 是 libxml2 性能核心。仓颉版本由于 `String` 不可变 + GC，去除了引用计数：

```text
class NameTable {
    func intern(s: String): String         // 返回池内规范实例
    func interned(s: String): ?String      // 仅查询不插入
}
```

可按 `Document` 作用域、按 `XmlParser` 作用域或全局共享；并发场景使用 `ConcurrentHashMap`（来自 `std.collection.concurrent`）。

### 5.3 限定名（`QName`）

```text
public struct QName {
    let localName: String
    let prefix:    ?String
    let uri:       ?String
}
```

- 比较走三元组等价（`(localName, uri)`），避免 libxml2 中 `prefix:localname` 字符串解析的反复重做。
- 不可变 `struct`，复用便利；构造点统一通过 `NameTable.intern`。

### 5.4 命名空间上下文（`NsContext`）

不可变持久化栈：`push(prefix, uri)` 返回新实例，结构共享。这与 C14N 命名空间作用域跟踪天然对齐，避免 libxml2 命名空间相关 CVE 的根因（指针与作用域混淆）。

### 5.5 URI

```text
public struct Uri {
    static func parse(s: String): Result<Uri, XmlError>
    func resolve(base: Uri): Uri
    func normalize(): Uri
    prop scheme:    ?String
    prop authority: ?String
    prop path:      String
    prop query:     ?String
    prop fragment:  ?String
}
```

严格遵循 RFC 3986；提供 `windowsPathCompat: Bool` 选项以兼容 libxml2 对 Windows 盘符的特殊处理。

---

## 6. 字符、编码与 I/O

### 6.1 字符类

对应 libxml2 `chvalid.c`。

```text
public const func isXmlNameStart(c: Rune, version: XmlVersion): Bool
public const func isXmlName(c: Rune, version: XmlVersion): Bool
public const func isXmlChar(c: Rune, version: XmlVersion): Bool
public const func isXmlWhitespace(c: Rune): Bool
public const func isPubidChar(c: Rune): Bool
```

- 全部 `const`，可在编译期常量折叠。
- 区分 XML 1.0 / 1.1 通过 `enum XmlVersion { V10 \| V11 }` 参数化。

### 6.2 编码（`encoding` 包）

```text
public interface Decoder {
    func decode(input: Array<Byte>, output: StringBuilder): DecodeStatus
    func reset(): Unit
}
public interface Encoder {
    func encode(input: String, output: GrowableBuffer): EncodeStatus
}
public enum DecodeStatus { Ok | Incomplete | Invalid(Int64) }
```

- 内置：`Utf8Decoder`/`Encoder`、`Utf16LeDecoder`/`...BeDecoder`、`Utf32LeDecoder`/`...BeDecoder`、`AsciiDecoder`、`Iso8859Decoder(part: Int)`。
- 其余编码（GB18030、Shift-JIS 等）通过 `EncodingRegistry.register(name, factory)` 可插拔，初版不内置。
- BOM 探测：`func detectBom(prefix: Array<Byte>): (BomKind, skipLen: Int64)`。

### 6.3 I/O（`io` 包）

```text
public interface IoSource <: Resource {
    func read(buffer: Array<Byte>): Int64       // -1 表示 EOF
    prop baseUri:  ?String
    prop encodingHint: ?String
}

public interface IoSink <: Resource {
    func write(bytes: Array<Byte>): Unit
    func flush(): Unit
}
```

适配器：`FileSource` / `MemorySource(bytes)` / `StringSource(s)` / `StreamSource(InputStream)`；输出端 `FileSink` / `MemorySink` / `StreamSink`。

装饰器（用 `|>` 组合，避免 libxml2 中函数指针海）：

- `BufferedSink(inner, bufSize)`
- `IndentingSink(inner, indent: String)`
- `EncodingSink(inner, encoder: Encoder)`

---

## 7. 解析器架构

### 7.1 五层流水线

将 libxml2 13k 行单文件 `parser.c` 拆为五层：

```
IoSource ──> ByteReader ──> RuneReader ──> Lexer ──> Parser ──> Iterator<SaxEvent>
            (回退缓冲)    (解码 + 行列号)  (词法)   (语法 + NS)
```

每层均为小状态机或纯函数；任何一层独立单测、可被替换。

### 7.2 统一事件流

```text
public enum SaxEvent {
    | StartDocument(decl: XmlDecl)
    | EndDocument
    | StartElement(name: QName, attrs: Array<Attribute>, ns: NsContext)
    | EndElement(name: QName)
    | Characters(text: String)
    | Cdata(text: String)
    | Comment(text: String)
    | Pi(target: String, data: String)
    | DtdEvent(dtd: DtdSubset)
    | EntityReference(name: String)
    | ParseError(err: XmlError)        // 容错模式下以事件形式流出
}
```

三种消费姿势共用同一份事件流：

| 风格        | 对应 libxml2          | CangjieXML 实现                                               |
| ----------- | --------------------- | ------------------------------------------------------------- |
| SAX（推）   | `xmlSAXUserParseMemory` | 外层把 `Iterator<SaxEvent>` 分派到 `SaxHandler`               |
| Reader（拉）| `xmlreader.c`           | 把迭代器再裹一层游标状态机，提供"当前节点"访问 API             |
| DOM（树）   | `xmlReadMemory`         | 内部用一个特殊的 `SaxHandler` 收集事件构建 `Document`         |

这一统一消除了 libxml2 中 push / pull 双实现行为偏差的隐患。

### 7.3 命名空间

`StartElement` 事件携带新 `NsContext`；前缀与 URI 一次性解析，下游不再重做字符串拆分。

### 7.4 实体处理

- 内置实体硬编码（`&lt;` `&gt;` `&amp;` `&apos;` `&quot;`）。
- 字符引用 `&#x...;` / `&#...;` 由解析器直接消费。
- 通用实体与参数实体：通过 `EntityResolver` 接口返回 `IoSource`，解析器递归下推。
- **Billion Laughs 检测器**：实体展开计数 + 嵌套深度阈值，可由 `ParserOptions` 调整。
- 默认 **拒绝外部实体**（XXE 防护），需显式 `loadExternal = true` 开启。

### 7.5 解析器选项

```text
public struct ParserOptions {
    var validate:           Bool        = false
    var substituteEntities: Bool        = true
    var loadExternal:       Bool        = false
    var huge:               Bool        = false
    var recover:            Bool        = false
    var keepBlanks:         Bool        = true
    var version:            XmlVersion  = V10
    var maxDepth:           Int64       = DEFAULT_MAX_DEPTH
    var maxEntityExpansion: Int64       = DEFAULT_MAX_ENTITY_EXPANSION
    var nameTable:          ?NameTable  = None
    var entityResolver:     ?EntityResolver = None
}
```

不再使用 libxml2 风格的位掩码——结构体 + 命名参数 + 默认值，调用点自解释。

---

## 8. 树操作 API

### 8.1 构建

```text
public class DocumentBuilder {
    static func from(events: Iterator<SaxEvent>, opts: BuildOptions): ParseResult
    static func build(scope: (DocumentScope) -> Unit): Document    // 流畅 API
}
```

借助仓颉尾随 lambda：

```text
let doc = DocumentBuilder.build { d =>
    d.root("book", ns: "http://...") { b =>
        b.attr("id", "1")
        b.child("title") { t => t.text("XML 之美") }
    }
}
```

### 8.2 遍历

`Node` 实现 `Iterable<Node>`（按文档顺序 DFS），并提供细分迭代器：

- `children()` / `descendants()` / `ancestors()`
- `followingSiblings()` / `precedingSiblings()`
- 全部惰性，避免 libxml2 中 `xmlNodeSet` 的全量复制。

### 8.3 修改

```text
extend Element {
    func appendChild(n: Node): Unit
    func insertBefore(newNode: Node, ref: Node): Unit
    func remove(child: Node): Unit
    func replaceWith(newNode: Node): Unit
}
```

不变量检查：

- `Node.detached: Bool`：节点必须为分离态才能再插入；重复插入立即抛 `XmlException`。
- 属性表内部为有序 `ArrayList<Attr>`（保留原始顺序，C14N 必需）+ 阈值切换的小哈希。

### 8.4 用户扩展

鼓励用户使用 `extend` 增加便利方法而非派生子类：

```text
extend Element {
    func getElementsByTagName(name: String): Iterable<Element> { ... }
    prop innerText: String { get() { ... } }
}
```

---

## 9. XPath 与 Pattern

### 9.1 XPath 1.0

三段式：

```
源串 ──> Lexer ──> Parser (AST: enum Expr / enum Step) ──> Evaluator ──> XPathItem
```

```text
public enum Expr {
    | Path(Array<Step>)
    | Binary(Op, Expr, Expr)
    | FuncCall(QName, Array<Expr>)
    | Literal(String)
    | Number(Float64)
    | VarRef(QName)
}

public enum Axis {
    | Self_      | Child      | Parent
    | Descendant | DescendantOrSelf
    | Ancestor   | AncestorOrSelf
    | Following  | FollowingSibling
    | Preceding  | PrecedingSibling
    | Attribute  | Namespace
}

public enum XPathItem {
    | NodeSet(NodeSet)
    | StringValue(String)
    | NumberValue(Float64)
    | BoolValue(Bool)
}
```

- AST 不可变；编译产物 `CompiledXPath` 可被多线程共享，配合不同 `XPathContext` 并发求值。
- `NodeSet` 内部为惰性迭代器 + 按需唯一化 / 文档序排序。
- 函数库：XPath 1.0 全部 28 个核心函数 + `XPathContext.registerFunction(name, fn)` 扩展点。

### 9.2 Pattern

`pattern` 包对应 libxml2 `pattern.c`：流式 XPath 严格下降子集（`/a/b/c`、`//x`、`*`、`@attr`），编译为自动机，**不走** XPath 完整求值器。供 reader 过滤、Schema selector 等高频路径使用。

### 9.3 XPointer

`xpointer` 包提供 `element()` 与 `xpath()` 方案；其余历史方案（`xmlns()`、`fragid`）按 libxml2 当前能力等价实现。

---

## 10. 验证：DTD / XSD / RelaxNG / Schematron

### 10.1 DTD（`dtd` 包）

- DTD 解析复用 `parser` 的词法层（DTD 是 XML 的子语言）。
- 内容模型编译为 NFA → DFA（复用 `regexp` 包）。
- 验证器实现 `interface Validator`：既可订阅 `SaxEvent` 流（流式），也可作用于 `Document`（树式）。

### 10.2 正则与自动机（`regexp` 包）

libxml2 `xmlregexp.c` / `xmlautomata.h` 是自家实现的 XSD 正则（不是 PCRE）。CangjieXML 做法：

```text
public sealed interface Re
class CharRe(c: Rune)         <: Re
class CharClassRe(set: CharSet) <: Re
class SeqRe(parts: Array<Re>) <: Re
class AltRe(parts: Array<Re>) <: Re
class RepRe(inner: Re, min: Int, max: ?Int) <: Re
```

- `CharSet` 使用排序区间数组 + ASCII bitset 加速；支持 Unicode 块（XSD `\p{...}`）。
- Thompson 构造 → NFA → 子集构造 DFA；提供"全匹配"与"流式进入 / 退出"两种 API。
- **不**作为通用正则对外暴露（那是 `std.regex` 的职责）。

### 10.3 XML Schema 1.0（`schema` 包）

三阶段：**parse**（XSD 文档 → 元模型）→ **compile**（解析组件引用、派生展开、组扁平化）→ **validate**。

```text
public sealed interface SchemaType
class SimpleType  <: SchemaType { ... }
class ComplexType <: SchemaType { ... }

public enum DerivationKind { Restriction | Extension | List | Union }

public enum Facet {
    | MinLength(Int64) | MaxLength(Int64) | Length(Int64)
    | Pattern(Re)      | Enumeration(Array<String>)
    | MinInclusive(String) | MaxInclusive(String)
    | MinExclusive(String) | MaxExclusive(String)
    | TotalDigits(Int64)   | FractionDigits(Int64)
    | WhiteSpace(WhiteSpaceTreatment)
}
```

- 内建 44 个 XSD 简单类型（`anyURI`, `dateTime`, `duration`, `decimal`, ...），每个都是 `class : SimpleType`，通过 `extend` 注册 `lexicalSpace` 与 `canonicalize`。
- 身份约束（`xs:unique` / `xs:key` / `xs:keyref`）调用 `xpath` 求值。

### 10.4 RelaxNG（`relaxng` 包）

采用 **Brzozowski 导数算法**而非 libxml2 的自动机法：代码量小、证明清晰、极度契合 `sealed class` + `match`。

```text
public sealed interface Pattern
class Empty       <: Pattern
class NotAllowed  <: Pattern
class Text        <: Pattern
class Choice(a, b: Pattern) <: Pattern
class Group(a, b: Pattern)  <: Pattern
class Interleave(a, b: Pattern) <: Pattern
class OneOrMore(p: Pattern) <: Pattern
class ElementPattern(name: NameClass, p: Pattern) <: Pattern
class AttributePattern(name: NameClass, p: Pattern) <: Pattern
class DataValue(t: Datatype, value: String) <: Pattern
```

每个 `Pattern` 实现 `func deriv(event: SaxEvent): Pattern`，验证即对事件流做导数。

### 10.5 Schematron（`schematron` 包）

本质是"按规则求 XPath"：极薄的一层，直接复用 `xpath`。输出 SVRL 报告。

---

## 11. 输出：Writer / Save / C14N

### 11.1 `XmlWriter`（流式，`writer` 包）

```text
public class XmlWriter <: Resource {
    init(sink: IoSink, opts: WriterOptions)
    func startDocument(version!: XmlVersion = V10, encoding!: ?String = None): Unit
    func endDocument(): Unit
    func startElement(name: QName): Unit
    func endElement(): Unit
    func attribute(name: QName, value: String): Unit
    func text(s: String): Unit
    func cdata(s: String): Unit
    func comment(s: String): Unit
    func pi(target: String, data: String): Unit
}
```

内部用元素栈跟踪，发现 API 误用（如 `endElement` 多于 `startElement`）立即抛 `XmlException`，避免 libxml2 中产生非良构输出的隐患。

### 11.2 `DocumentSerializer`（`save` 包）

```text
public struct SerializeOptions {
    var indent:        Bool       = false
    var indentString:  String     = "  "
    var omitXmlDecl:   Bool       = false
    var encoding:      ?String    = None
    var c14nMode:      ?C14NMode  = None
}
```

构建于 `XmlWriter` 之上；与 `c14n` 共享"命名空间作用域跟踪"基础设施。

### 11.3 C14N（`c14n` 包）

实现 C14N 1.0、Exclusive C14N、C14N 1.1。

- 严格确定性的命名空间与属性排序（命名空间序 < 属性序）。
- 节点过滤通过 `interface InclusionFilter { func includes(n: Node): Bool }`。
- 由于使用不可变 `NsContext`，从设计层面规避 libxml2 中 attr-axis 命名空间相关的 CVE。

---

## 12. HTML、XInclude、Catalog

### 12.1 HTML（`html` 包）

- **共享** `parser` 的词法层，在其上叠加 `HtmlInsertionMode` 状态机（对齐 WHATWG 解析算法核心插入模式）。
- 复用 `tree.Document`，加 `isHtml: Bool` 标记。
- 不追求完整 HTML5 DOM（如 shadow DOM），覆盖 libxml2 现有能力（XPath 抓取场景）。

### 12.2 XInclude（`xinclude` 包）

- 实现 `xi:include` + `xi:fallback`，支持 `text` / `xml` 两种解析。
- 与 `xpointer` 联动做 fragment 定位。

### 12.3 Catalog（`catalog` 包）

- 解析 OASIS XML Catalog 1.1，作为 `EntityResolver` 默认实现（"按 catalog 查找"）。
- 远程 schema 抓取交由调用方注入实现 `stdx.net.http`。

---

## 13. 并发模型

### 13.1 总原则

| 角色             | 可变性     | 并发使用                       |
| ---------------- | ---------- | ------------------------------ |
| `XmlParser`      | 可变       | 单实例单线程                   |
| `XmlWriter`      | 可变       | 单实例单线程                   |
| `Document`       | 构造后视为不可变 | 多线程共享读 / XPath / 序列化 |
| `CompiledXPath`  | 不可变     | 多线程共享                     |
| `CompiledSchema` | 不可变     | 多线程共享                     |
| `NameTable`      | 可变（线程安全实现） | 多线程共享                  |
| 编码注册表       | 启动期写、运行期只读 | 多线程读                |

### 13.2 显式注入替代全局状态

libxml2 大量使用全局 hook（`xmlSetExternalEntityLoader` 等），并发场景易冲突。CangjieXML 全部通过 `ParserOptions` / `WriterOptions` 显式注入；不存在隐式全局状态。

### 13.3 取消

所有长耗时 API（解析、验证、XPath）接受 `CancellationToken`（基于仓颉 `Future.cancel` / `ThreadLocal` 机制）；上层超时或停止时及时中断，替换 libxml2 仅靠 `xmlParserMaxDepth` 等粗粒度阈值的做法。

### 13.4 可选并行

ROADMAP Phase 13 提供 `ParallelValidator` / 文档分段并行解析等高级能力；MVP 阶段不引入。

---

## 14. 错误模型与诊断

```text
public enum XmlError {
    | WellFormed(WfKind, Position, String)
    | Validity(VKind, Position, String)
    | Namespace(String, Position)
    | Io(IoKind, String)
    | Encoding(String, Position)
    | Schema(SchemaKind, Position, String)
    | XPath(XPathKind, String)
    | Internal(String)
}

public struct Position {
    let uri:        ?String
    let line:       Int64
    let column:     Int64
    let byteOffset: Int64
}

public class XmlException <: Exception { ... }
```

- 库内部通过 `Result<T, XmlError>` 传播；公共 API 抛 `XmlException` 包装。
- 解析返回 `ParseResult { doc: ?Document, errors: ArrayList<XmlError> }`，便于 IDE/lint 工具批量呈现。
- 提供 `func formatError(err: XmlError, source: ?String): String`，模仿编译器风格（`file:line:column` + `^` 指针）。
- **无全局 last-error**：libxml2 的 `xmlGetLastError()` 是全局可变，CangjieXML 不复刻。

---

## 15. 安全默认

| 风险                  | 默认策略                           | 选项                                     |
| --------------------- | ---------------------------------- | ---------------------------------------- |
| XXE（外部实体）       | 拒绝加载                           | `ParserOptions.loadExternal = true`      |
| Billion Laughs        | 实体展开总数 ≤ `1e7`               | `ParserOptions.maxEntityExpansion`       |
| 嵌套深度              | ≤ 256                              | `ParserOptions.maxDepth`                 |
| DTD 大小              | 声明数量阈值                       | `ParserOptions.huge = true` 关闭         |
| URL 自动取回          | 拒绝                               | 注入自定义 `EntityResolver`              |
| 字符归一化            | 严格拒绝非法 UTF-8（不静默替换）    | 无                                       |

每条都对应明确的 `ParserOptions` 字段，便于安全审计。

---

## 16. 宏与元编程

仓颉宏（`std.ast`）用于消除样板与保证穷尽，**绝不**用作"魔法 DSL"：

| 宏                       | 用途                                                                  |
| ------------------------ | --------------------------------------------------------------------- |
| `@Visitor`               | 为 `sealed interface Node` 自动派生 `NodeVisitor<R>` 与各分支 `accept` |
| `@SchemaModel`           | 为 XSD 类型元模型派生 `derive(kind, base)` 等结构性函数                |
| `@XPathFunction("ns")`   | 标记 XPath 自定义函数，自动生成注册代码                                |

---

## 17. 测试策略

| 层次       | 内容                                                                                      |
| ---------- | ----------------------------------------------------------------------------------------- |
| 单元测试   | 每包 `src/xxx_test.cj`，使用 `@Test` / `@TestCase` / `@Expect` / `@PowerAssert`           |
| 黄金对比   | 拷贝 `.libxml2-2.15.3/test/` 与 `result/` 中的样例，作为端到端回归                        |
| 规范套件   | `testkit` 包提供 W3C `xmlconf` 驱动器，对应 libxml2 `runxmlconf.c`                        |
| 模糊测试   | 复用 `.libxml2-2.15.3/fuzz/` 语料，编写仓颉 harness 做随机变异                            |
| 性能基线   | 选 1 MB / 10 MB / 100 MB 三档 XML，跑解析 / XPath / 序列化基准；用 `cjprof` 做火焰图分析  |
| 覆盖率     | `cjcov` 分支覆盖率 ≥ 80%（关键包 ≥ 90%）                                                   |

---

## 18. 与 libxml2 的刻意差异

| libxml2 行为                                | CangjieXML 行为                          | 理由                       |
| ------------------------------------------- | ---------------------------------------- | -------------------------- |
| 默认加载外部 DTD / 实体                     | 默认禁用                                 | 安全默认                   |
| `xmlGetLastError` 线程局部全局              | 无全局；`ParseResult.errors`             | 可测、线程友好             |
| `void*` SAX `userData`                      | `class` / `interface` 显式               | 类型安全                   |
| `xmlNode` 超集结构                          | `sealed interface Node` + 分支类         | 类型安全 + 穷尽 `match`    |
| 内嵌 HTTP / FTP 客户端                      | 移除，留 `EntityResolver` 钩子           | 单一职责                   |
| iconv 耦合                                  | 纯仓颉编码表 + `Decoder` 接口            | 可移植、零原生依赖         |
| 手工引用计数 + `xmlFree*`                   | GC + `Resource`                          | 内存安全                   |
| `xmlXPathObjectPtr` 联合体                  | `enum XPathItem`                         | 表达力                     |
| 全局 hook 设置                              | `ParserOptions` / `WriterOptions` 注入   | 显式优于隐式               |

**所有差异均不违反 W3C 规范**；CangjieXML 与 libxml2 应通过同一批 W3C 测试。

---

## 19. 架构决策记录（ADR）

- **ADR-001**：节点采用 `sealed interface Node` + 分支类，而非单一 `enum Node`。理由：节点附带较多子状态，`class` 比带 payload 的 `enum` 在字段访问与扩展上更自然。
- **ADR-002**：解析器输出统一为 `Iterator<SaxEvent>`，SAX / Reader / DOM 均为其消费者。理由：单一真理来源，消除 push / pull 双实现行为偏差。
- **ADR-003**：不提供 C ABI / CFFI 绑定。理由：项目目标为"重构式复刻"；如需互操作，属于另立项目。
- **ADR-004**：用 `NameTable`（普通哈希 + GC）替换 `xmlDict` 引用计数字典。理由：仓颉不可变 `String` + GC 使引用计数失去意义。
- **ADR-005**：默认安全（禁用外部实体、深度 / 展开阈值默认开启）。理由：规避 libxml2 历史 CVE 模式。
- **ADR-006**：HTML 解析器与 XML 共享词法层。理由：减少重复代码，同步修复两端。
- **ADR-007**：RelaxNG 采用 Brzozowski 导数算法，而非 libxml2 的自动机法。理由：实现简洁、证明清晰、契合 `sealed` + `match`。
- **ADR-008**：移除每个包的 `xml_` 前缀，包名按职能命名（`core`、`parser`、`xpath` 等）。理由：工作区已名为 CangjieXML，前缀冗余且不优雅。

后续重大变更须追加 ADR。

---

## 20. 与仓颉 SDK 的对齐

| 类别        | 使用                                                                                       |
| ----------- | ------------------------------------------------------------------------------------------ |
| 标准库      | `std.collection`（HashMap/ArrayList）、`std.collection.concurrent`（ConcurrentHashMap）、 `std.sync`（Mutex/Atomic/Condition）、`std.io`、`std.fs`、`std.time`、`std.convert`、`std.unicode`、`std.ast`（宏）、`std.unittest` |
| 扩展库      | 仅 `tools/` 可选使用 `stdx.net.http`（远程 schema 抓取）、`stdx.encoding.json`（输出格式化） |
| 工具链      | `cjpm`（工作区 / 依赖 / 构建）、`cjfmt`（格式化）、`cjlint`（静态检查）、`cjcov`（覆盖率）、`cjprof`（性能分析）、`cjdb`（调试）|

格式化配置 `cangjie-format.toml` 与 lint 规则集统一在仓库根目录维护。

---

## 21. 风险与缓解

| 风险                                  | 缓解                                                                          |
| ------------------------------------- | ----------------------------------------------------------------------------- |
| XML Schema 规模大（28k 行）           | 拆 8a / 8b 两里程碑：先打通骨架（含 Schema-for-Schemas 自举），再补全语义       |
| XPath 求值性能                        | AST 编译期常量折叠 + NodeSet 惰性 + 文档序索引                                  |
| 多字节编码缺失                        | 通过 `EncodingRegistry` 开放注册；初版明确不支持 GB18030 等                     |
| 黄金对比差异（空白处理、声明顺序）    | 提供"语义等价比较器"：序列化 → parse → 再序列化，比较语义而非字节               |
| libxml2 历史 deprecated 字段          | 直接不复刻；在 `docs/migration.md` 提供迁移指南                                |
| 仓颉 SDK 快速迭代                     | `cjpm.toml` 锁定 SDK 1.0.5；升级走单独分支做整体回归                          |

---

_本文档遵循 [`cangjie-regulations`](./.github/skills/cangjie-regulations/) 中的项目结构、命名、格式化、文档规范。任何重大架构变更须补充 ADR 并在 §19 追加记录；命名/术语调整须同步更新 §3。_
