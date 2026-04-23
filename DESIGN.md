# CangjieXML 软件设计文档

> 以仓颉（Cangjie）语言对 libxml2（参考版本：2.15.3）进行**优化重构式复刻**。
> 目标是在遵从 XML 1.0/1.1 规范与 libxml2 功能边界的前提下，充分利用仓颉现代语言特性
> （扩展、模式匹配、并发、泛型、Option、接口默认实现、宏等），
> **因地制宜**地重新设计架构与 API，而不是对 C 源码做机械翻译。

---

## 1. 背景与目标

### 1.1 libxml2 现状概览

libxml2 是一个用 C89 实现的成熟 XML 工具箱，参考仓库 `.libxml2-2.15.3` 中共约 **17.5 万行** C 代码，
对外暴露约 40 个公共头文件。核心模块（按源码规模）：

| 量级 (LOC) | 模块 | 主要职责 |
|---|---|---|
| 28 492 | `xmlschemas.c` | XML Schema 1.0 校验 |
| 13 719 | `parser.c` | XML 1.0/1.1 解析器（pull + push） |
| 12 153 | `xpath.c` | XPath 1.0 引擎 |
| 10 760 | `relaxng.c` | RELAX NG 校验 |
|  8 901 | `tree.c` | DOM 树构造/遍历/查询/序列化 |
|  6 563 | `valid.c` | DTD 校验 |
|  6 394 | `xmlregexp.c` | 正则/NFA/DFA（用于 Schema/RelaxNG） |
|  6 129 | `xmlschemastypes.c` | XSD 内建数据类型 |
|  6 004 | `HTMLparser.c` | HTML 解析器（宽松模式） |
|  5 405 | `xmlreader.c` | 流式（pull）Reader API |
|  4 576 | `xmlwriter.c` | 流式 Writer API |
|  3 880 | `catalog.c` | XML Catalog（OASIS） |
|  3 003 | `encoding.c` | 字符集转换（UTF-8/16/ISO-8859-x/iconv/ICU） |
|  2 908 | `xmlIO.c` | I/O 缓冲、协议处理 |
|  2 842 | `SAX2.c` | SAX2 回调与 DOM 建树衔接 |
|  2 781 | `uri.c` | RFC 3986 URI 解析/合成 |
|  2 681 | `xmlsave.c` | 序列化 |
|  2 359 | `pattern.c` | XPath 子集（步骤模式） |
|  2 190 | `xinclude.c` | XInclude 1.0 |
|  2 168 | `c14n.c` | Canonical XML 1.0 |
|  2 014 | `schematron.c` | Schematron |
|  …    | `dict.c` / `hash.c` / `list.c` / `buf.c` / `threads.c` / `xmlmemory.c` / `xmlstring.c` / `chvalid.c` / `xmlunicode.c` / `error.c` / `globals.c` / `xmlmodule.c` / `nanohttp.c` / `entities.c` / `debugXML.c` / `xpointer.c` / `xlink.c` | 基础设施 |

可执行程序：`xmllint`、`xmlcatalog`；测试：`runtest`、`testparser`、`testchar`、`runsuite`、`runxmlconf`、`testapi`、`fuzz/`。

### 1.2 libxml2 关键特性要点（复刻范围）

1. **两种解析模型**：
   - 全量 DOM（`xmlReadFile/Doc/Memory/Fd/IO` → `xmlDoc`）。
   - 流式：
     - SAX/SAX2 回调（push + pull，事件驱动）。
     - `xmlTextReader`（类似 .NET `XmlReader`，pull 游标式）。
2. **序列化**：`xmlSave*` / `xmlTextWriter`，支持 UTF-8/UTF-16、缩进、C14N 1.0（含 Exc-C14N）。
3. **校验**：DTD、XML Schema 1.0、RELAX NG、Schematron；XSD 简单类型库。
4. **查询**：XPath 1.0、XPointer、XInclude 1.0、Pattern（XSLT 步骤模式子集）。
5. **基础设施**：UTF-8 字符串（`xmlChar*` = `unsigned char*`）、字典（字符串驻留）、哈希/链表、错误与结构化错误回调、线程局部全局、内存钩子、动态模块、URI、Catalog、HTTP（已废弃）。
6. **HTML**：宽松 HTML4/5 片段解析，与 XML 树共享节点模型。
7. **C14N**：规范化（规范比较、签名预处理）。

### 1.3 本项目目标

- **范围**：以"可实际替代 libxml2 绝大多数用户场景"为原型目标。
- **不做**的事：
  - C 互操作（CFFI）、libiconv/ICU/zlib/readline 绑定——全部用仓颉标准库/扩展库实现。
  - SAX1（libxml2 自己已废弃）。
  - `nanohttp`（libxml2 2.15 已移除实现，仅保 ABI 占位）。
  - `xmlmodule`（动态模块加载，与语言模型不符）。
  - Python 绑定。
- **必做**的事：遵从 XML 1.0 第五版、Namespaces 1.0、XML 1.1（可选编译开关对齐）、XPath 1.0、
  C14N 1.0/Exc-C14N、XInclude 1.0、XSD 1.0、RELAX NG、DTD 校验。
- **质量目标**：
  - 通过 W3C XML 测试套件（对照 libxml2 `runxmlconf`）；
  - 通过 libxml2 回归样本（`.libxml2-2.15.3/test/` 与 `result/` 作为黄金输出）；
  - 默认"安全优先"：无 UAF/内存越界（仓颉内存安全 + 严格溢出策略）；
  - 基准解析性能与 libxml2 差距在同数量级（目标 ≥ 0.7×），流式解析吞吐可比肩。

### 1.4 设计准则（必须遵守）

1. **仓颉优先**：放弃 C 的手写内存管理、宏开关、void* 回调注册；使用 class/struct、enum、
   interface、extend、模式匹配、Option、Future、Mutex 等原生机制。
2. **规范而非实现**：以 W3C 规范为权威来源，libxml2 仅作功能基线与兼容参照（测试/语义）。
3. **接口窄、扩展宽**：每个核心模块提供"最小稳定 API" + 通过 `extend` 提供增强能力。
4. **无全局可变状态**：libxml2 的 `globals.c`/`xmlThrDef*`/`xmlDefault*` 一律改为显式
   `XmlOptions` / 依赖注入，便于并发与测试。
5. **零 `unsafe`**：全库默认不使用 `unsafe`；只有在做极端性能优化的"字节级 SIMD 内核"中，
   才允许在受控模块内（明确命名 `internal.unsafe`，可编译开关禁用）使用。
6. **安全默认**：默认关闭网络取外部实体、DTD 外部子集、实体替换（抵御 XXE/Billion laughs）；
   使用者需显式打开。
7. **并发就绪**：只读 Document/Element 可跨线程共享；可变操作通过类型系统或运行时守卫显式表达。
8. **错误可诊断**：错误带行/列/字节偏移/URI/上下文片段；用 `enum` + 模式匹配代替整型码。

---

## 2. 顶层架构

### 2.1 包划分（对应仓颉 `package`/`cjpm` 模块）

所有包以 `cangjie_xml` 为根命名空间（仓颉风格下划线），库名 `cangjie-xml`。

```
cangjie_xml                               ← 顶层 facade（re-export 常用 API）
├── base                                  ← 基础设施层（无业务语义）
│   ├── chars         字符分类、XML/XML 1.1 合法性、Unicode 块
│   ├── uri           RFC 3986 URI（替代 uri.c）
│   ├── intern        字符串驻留池（替代 dict.c）
│   ├── buf           增长缓冲 / 字节视图（替代 buf.c）
│   ├── io            输入/输出抽象 + 编码检测（替代 xmlIO.c）
│   └── encoding      编解码器注册表 + UTF-8/16/ISO-8859-x/Latin1（替代 encoding.c）
├── diag                                  ← 诊断与错误（替代 error.c / xmlerror.h）
├── core                                  ← DOM 节点模型（替代 tree.c / entities.c）
│   ├── node          抽象节点代数类型（enum Node）
│   ├── doc           Document
│   ├── ns            Namespace
│   ├── dtd           DTD 声明节点
│   └── serialize     序列化（替代 xmlsave.c）
├── parser                                ← 解析器（替代 parser.c / parserInternals.c / SAX2.c）
│   ├── lex           词法
│   ├── sax           SAX2 事件类型与处理接口（替代 SAX.h/SAX2.h）
│   ├── tree_builder  SAX → DOM 建树
│   ├── reader        流式 Reader（替代 xmlreader.c）
│   └── entity        实体解析 / XXE 防护
├── html                                  ← HTML5 宽松解析（替代 HTMLparser.c/HTMLtree.c）
├── writer                                ← 流式 Writer（替代 xmlwriter.c）
├── xpath                                 ← XPath 1.0（替代 xpath.c + pattern.c 子集）
│   ├── ast
│   ├── eval
│   └── pattern
├── xpointer                              ← XPointer（替代 xpointer.c / xlink.c）
├── xinclude                              ← XInclude 1.0（替代 xinclude.c）
├── c14n                                  ← Canonical XML（替代 c14n.c）
├── regex                                 ← Schema/RelaxNG 用 NFA/DFA（替代 xmlregexp.c）
│                                            ※ 复用 std.regex 能力 + 额外的"粒子自动机"
├── validate                              ← 校验门面
│   ├── dtd           DTD 校验（替代 valid.c）
│   ├── xsd           XML Schema 1.0（替代 xmlschemas.c + xmlschemastypes.c）
│   ├── relaxng       RELAX NG（替代 relaxng.c）
│   └── schematron    Schematron（替代 schematron.c）
├── catalog                               ← XML Catalog（替代 catalog.c）
├── cli                                   ← 可执行命令行
│   ├── xmllint
│   └── xmlcatalog
└── tests                                 ← 集成与回归（用 std.unittest）
```

包设计原则：
- **上层可依赖下层，不可反向**；跨层通信通过 `interface`（如 `core` 暴露
  `interface ParseSink`/`interface Serializable` 给 `parser`/`writer` 实现）。
- **可选特性**通过 **cjpm feature（条件编译）** 关闭整包编译，等价于 libxml2 的
  `--with-xpath/--with-schemas` 等开关。
- **`cangjie_xml` 顶层 facade** 只做 `public import`，对外用户零感知包细节。

### 2.2 分层与数据流

```
             ┌────────────────────────────────────────────────────────┐
             │                    用户 API (facade)                    │
             │   Xml.parse / Xml.load / Xml.save / Xml.xpath / ...     │
             └──────┬────────────┬───────────────┬───────────────┬──────┘
                    │            │               │               │
                 parser        writer         xpath /         validate
                 reader        c14n           xpointer        (dtd/xsd/rng/sch)
                    │            │               │               │
                    └────────┬───┴───────┬───────┘               │
                             ▼           ▼                        │
                         core (Node / Doc / Ns) ◀──────────  xinclude / catalog
                             │
                             ▼
                diag ◀── base (chars / uri / intern / buf / io / encoding)
```

所有模块**只通过 `core` 的抽象节点和 `base` 的类型** 进行互通；诊断统一走 `diag`。

---

## 3. 核心领域模型

### 3.1 字符串与驻留池

libxml2 使用 `xmlChar*`（UTF-8 `unsigned char*`）+ `xmlDict`（树级字符串驻留）。
仓颉中：

- 对外 API 统一使用 `String`（UTF-8 封装）。内部读写两类容器：
  - `ByteView`（值类型 `struct`，`base.buf` 提供，`{ data: Array<Byte>, start: Int, len: Int }`）：
    零拷贝切片，供词法/编码使用。
  - `InternedName`（`base.intern` 提供，`struct` + `id: UInt32`）：驻留后的元素名/属性名/
    命名空间前缀。相等性 O(1) 比较。
- `StringPool`（`class`）：封装一个哈希 + 紧凑字节区，线程安全（原子递增 id + 写锁），
  提供 `intern(ByteView) -> InternedName`。每个 `Document` 拥有独立的池，解析器跨文档
  共享根池（可选，类似 libxml2 `xmlDictReference`）。

**仓颉特性利用**：
- `extend ByteView <: Hashable & Equatable`：为切片提供原地哈希（等价比较 InternedName 前使用）。
- `prop` 访问器：`InternedName.view: ByteView`。
- 编译期：`const` 初始化常用保留名（`xml`, `xmlns`, `id` 等）。

### 3.2 节点代数（`core.node`）

libxml2 用同一个 `xmlNode` 结构 + `type` 字段表达 20+ 种节点，字段复用歧义大（注释里反复
说"此场景下这个字段含义是…"）。仓颉采用**代数数据类型（sealed interface + enum）**清晰表达：

```text
sealed interface Node { ... }                           // 所有节点共同的位置/父子/命名 API

// —— 文档族（可作为解析/序列化入口）——
class Document   <: Node                                 // 替代 xmlDoc / XML_HTML_DOCUMENT_NODE
class DocumentFragment <: Node

// —— 结构性节点 ——
class Element    <: Node                                 // 替代 XML_ELEMENT_NODE
class Attribute  <: Node                                 // 替代 XML_ATTRIBUTE_NODE
class Namespace  <: Node                                 // 替代 xmlNs / XML_NAMESPACE_DECL

// —— 内容节点 ——
enum CharData {                                          // 可用模式匹配穷举
    | Text(String)
    | CData(String)
    | Comment(String)
    | PI(target: InternedName, data: String)
    | EntityRef(name: InternedName)
}
class CharDataNode <: Node { let kind: CharData; ... }

// —— DTD 相关 ——
class Dtd        <: Node
enum DtdDecl {
    | ElementDecl(...)
    | AttributeDecl(...)
    | EntityDecl(...)
    | NotationDecl(...)
}
class DtdDeclNode <: Node { let decl: DtdDecl; ... }

// —— XInclude 标记 ——
class XIncludeMark <: Node { let side: XIncludeSide }     // Start / End
```

**关键设计**：
- 子节点指针以 `var first: ?Node` / `var last: ?Node`、兄弟指针 `prev/next: ?Node` 的
  **双向侵入式链表**表达。节点引用使用仓颉对象引用（GC 管理），避免 libxml2 手动 free。
- `parent`、`doc` 字段为 **弱引用**（`std.ref.WeakRef`），防止树被持有导致无法释放子树。
- 属性列表 `Element.attrs` 采用 `ArrayList<Attribute>`，顺序敏感；命名空间 `Element.nsDefs`
  独立维护（与 libxml2 一致）。
- **`extend` 应用**：
  ```text
  extend Node {                                // 公共遍历 / 查询工具
      public func ancestors(): Iterator<Node>
      public func descendants(): Iterator<Node>
      public func following(): Iterator<Node>  // XPath 轴
      public func preceding(): Iterator<Node>
      public func isTextLike(): Bool
  }
  extend Element {                              // 便捷选择器
      public prop tagName: String
      public func attr(name: String, ns!: ?String = None): ?String
      public func children(): Iterator<Node>
      public operator func [](name: String): ?Element   // 快速单选子元素
  }
  ```
- **模式匹配示例**：
  ```text
  match (n) {
      case e: Element where e.localName == "item" => process(e)
      case cd: CharDataNode => match (cd.kind) {
          case Text(s) => append(s)
          case CData(s) => append(s)
          case _ => ()
      }
      case _ => ()
  }
  ```
  XPath/序列化/比较逻辑全部可用 `match` 表达，替代 libxml2 的巨型 `switch (node->type)` 语句。

### 3.3 命名空间

- `Namespace { prefix: ?InternedName, uri: InternedName, parent: WeakRef<Element> }`
- 解析时构建"命名空间栈"（`ArrayList<Namespace>`），退栈时不销毁（命名空间跟随声明它的
  Element 生命周期），以此自然支持 "XML namespace scoping"。
- 解析期 QName 通过**模式匹配**分派：
  ```text
  match (name.indexOf(':')) {
      case Some(i) => // prefix:local
      case None    => // default ns
  }
  ```

### 3.4 文档选项 `XmlOptions`

libxml2 通过 `xmlParserOption` 位掩码 + 一堆全局变量控制行为。本项目统一用**值对象**：

```text
public struct XmlOptions {
    public var recover: Bool = false
    public var noEnt: Bool = false           // 默认不展开外部实体 (抗 XXE)
    public var dtdLoad: Bool = false         // 默认不加载外部 DTD
    public var dtdAttr: Bool = false
    public var dtdValid: Bool = false
    public var noError: Bool = false
    public var noWarning: Bool = false
    public var preserveWhitespace: Bool = false
    public var noBlanks: Bool = false
    public var sax1: Bool = false            // 不支持（预留开关）
    public var xinclude: Bool = false
    public var nsClean: Bool = false
    public var cdataAsText: Bool = false
    public var compact: Bool = true
    public var big: Bool = false             // 允许 >10M 文档
    public var hugeLimit: Int64 = 10_000_000
    public var entityExpansionLimit: Int64 = 100_000
    public var maxDepth: Int = 256
    public var resourceLoader: ?ResourceLoader = None
    public var catalog: ?Catalog = None
    // ... 可扩展
}
```

使用 `Builder` 扩展：`XmlOptions().withXInclude(true).withRecovery(true)`。

### 3.5 诊断 `diag`

- 错误用 `enum XmlError`（可穷举）代替 libxml2 的 ~1000 个 `XML_ERR_*`：
  ```text
  public enum XmlDomain   { | Parser | Namespace | Dtd | Xsd | Xpath | IO | Encoding | Uri | Catalog | Internal | ... }
  public enum XmlSeverity { | Warning | Recoverable | Fatal }
  public struct XmlError <: ToString {
      public let domain: XmlDomain
      public let code: XmlErrorCode    // 细分枚举，每个 domain 独立
      public let severity: XmlSeverity
      public let where_: Location      // uri, line, column, byteOffset
      public let message: String
      public let context: ?String      // 源码片段/指示符（类似 libxml2 `xmlParserPrintFileContext`）
      public let cause: ?Exception
  }
  ```
- 错误传递：
  - **可恢复错误**通过 `interface ErrorSink { func report(e: XmlError) }` 回调（解析器持有）。
  - **致命错误**以仓颉异常抛出：`class XmlException <: Exception { let error: XmlError }`。
- 收集器：`class ErrorCollector <: ErrorSink`（ArrayList 收集 + thread-safe 版本）。
- libxml2 的 `xmlStructuredError` 由 ErrorSink 直接实现。

---

## 4. 解析器子系统

### 4.1 架构

```
           ┌───────────────────────────┐
           │         XmlReader         │  (流式 pull，对应 xmlTextReader)
           └───────────┬───────────────┘
                       │ 包装
           ┌───────────▼───────────────┐
           │         SaxDriver         │  (把 Events 送给 handler)
           │  implements Iterator<Evt> │
           └───────────┬───────────────┘
                       │ 产出
           ┌───────────▼───────────────┐
           │         Tokenizer         │  (UTF-8 字节层 / 状态机)
           └───────────┬───────────────┘
                       │ 读取
           ┌───────────▼───────────────┐
           │       InputSource         │  (编码检测 + 解码 + Byte 缓冲)
           └───────────────────────────┘
```

- **单一核心**：只有一个底层 `SaxDriver` 产生事件流（`enum Event`）；其他模式都是适配器：
  - `Xml.parse(...) → Document`：`TreeBuilder: SaxHandler` 消费事件，组装 DOM。
  - `XmlReader`：把事件流再包装成"pull 游标"（类似 .NET `XmlReader`）。
  - 用户自定义 SAX：直接实现 `SaxHandler`。
  - `XPathStreaming`（可选）：用 pattern 匹配边流式处理边裁剪。
- 这消除了 libxml2 中"push parser / pull parser / reader"三套实现的重复。

### 4.2 事件类型

```text
public enum Event {
    | StartDocument(version: String, encoding: ?String, standalone: ?Bool)
    | EndDocument
    | Doctype(name: String, publicId: ?String, systemId: ?String, internalSubset: ?String)
    | StartElement(name: QName, attrs: ArrayList<AttrEvt>, nsDecls: ArrayList<NsDecl>)
    | EndElement(name: QName)
    | Text(String)
    | CData(String)
    | Comment(String)
    | PI(target: String, data: String)
    | EntityRef(name: String)
    | Whitespace(String)
    | Error(XmlError)                 // 非致命，驱动器会继续
}
```

`SaxHandler` 接口**全部方法提供默认实现**（仓颉 `interface` 默认实现）——
消费者只需覆盖关心的事件，对照 libxml2 SAX2 的"几十个函数指针默认填 NULL"更易用。

### 4.3 编码检测与解码

`base.encoding` 提供 `interface Codec`，注册 UTF-8、UTF-16LE/BE、UTF-32LE/BE、
ISO-8859-1..16、US-ASCII、Windows-1252（基本覆盖 libxml2 `iso8859x`）。
BOM 检测 + `<?xml encoding="…"?>` 嗅探：前 4 字节判别 + 声明重扫描。
**不引入 iconv/ICU**；如使用者需要更多编码，可注册自定义 Codec。

### 4.4 实体处理与安全策略

- 内建实体：`&amp; &lt; &gt; &apos; &quot;`。
- 通用实体：默认**不展开**；展开时跟踪"展开字符数/递归深度"，超 `entityExpansionLimit`
  立即报 `EntityExpansionLimit` 并终止——抗"Billion laughs/ quadratic blowup"。
- 外部实体：由 `ResourceLoader` 负责加载；默认实现只允许 `file://` 白名单，显式开启
  `allowNetwork` 才能访问 `http(s)`。
- DTD 外部子集：默认不加载；开启 `dtdLoad` 后，从 Catalog 或 ResourceLoader 获取。

### 4.5 流式 Reader 的状态机

用 `enum ReaderState` + 模式匹配代替 libxml2 中若干个 `int` 字段：

```text
enum ReaderState {
    | Initial
    | Interactive(cursor: CursorNode, depth: Int)
    | Eof
    | Error(XmlError)
    | Closed
}
```

`Reader.read(): ReadResult` 返回 `enum ReadResult { | Advanced | End | Failed(XmlError) }`。

### 4.6 并发

- `SaxDriver` 本身**非线程安全**（对应一条输入流），这符合 libxml2 语义。
- 但同一个 `Document` 的**只读**遍历/查询可并行：内部计数字段（行号等）解析完成后
  不再修改；`Document` 冻结后进入"只读模式"，`AtomicBool frozen`+`prop immutable: Bool`
  由用户显式调用 `doc.freeze()`；未冻结时修改需持有文档 `Mutex`。
- 大文档解析可做"**并行 tokenizer 预扫描**"优化（分块 UTF-8 校验 + `<` `>` 的 SIMD 搜索），
  放在 `internal.unsafe` 中作为可选加速；默认走纯仓颉安全实现。
- 顶层 API 提供 `Future<Document>`：
  ```text
  let fut = spawn { Xml.parse(input) }
  let doc = fut.get()
  ```

---

## 5. 序列化与写入

- `writer` 模块提供流式 `XmlWriter`（事件驱动，`startElement/endElement/text/...`）。
- `core.serialize` 提供从 DOM 序列化，内部就是把 `Document` 转为事件序列喂给 `XmlWriter`。
- 缩进/换行/属性顺序/命名空间去冗通过 `SaveOptions` 值对象控制：
  ```text
  public struct SaveOptions {
      var indent: ?String = Some("  ")
      var newline: String = "\n"
      var emitXmlDecl: Bool = true
      var encoding: String = "UTF-8"
      var canonicalize: ?C14nMode = None      // C14N / Exc-C14N / C14N 1.1
      var sortNamespaces: Bool = false
      ...
  }
  ```
- C14N 作为 `SaveOptions.canonicalize` 的一个模式，由 `c14n` 模块实现，复用 writer 管道。

---

## 6. XPath / XPointer / XInclude / Pattern

### 6.1 XPath 1.0（`xpath`）

- 词法/语法用**递归下降**（libxml2 也是这样，但用了大量手工栈），仓颉中自然用递归 +
  `enum Expr` 表达 AST：
  ```text
  enum Expr {
      | Path(steps: ArrayList<Step>)
      | Union(Expr, Expr)
      | Filter(Expr, ArrayList<Expr> /* predicates */)
      | Func(name: String, args: ArrayList<Expr>)
      | BinOp(Op, Expr, Expr)
      | UnaryMinus(Expr)
      | Literal(XValue)        // String / Number / Boolean
      | VarRef(QName)
  }
  enum Step { | AxisStep(axis: Axis, test: NodeTest, preds: ArrayList<Expr>) }
  enum Axis { | Child | Parent | Self | Desc | DescSelf | Anc | AncSelf | Following | Preceding | FollowingSib | PrecedingSib | Attribute | Namespace }
  ```
- 求值：`interface Evaluator`；`NodeSet`/`Number`/`String`/`Boolean` 四值合一 `enum XValue`。
- 函数库：通过**接口 + extend + HashMap**注册，核心函数表作为 `const`；第三方可扩展：
  ```text
  let ctx = XPath.Context()
  ctx.register("my:hello", { args => XValue.Str("hi") })
  ```
- 性能：对 `Step` 做"轴迭代器"惰性遍历，`NodeSet` 使用"文档序维护的 ArrayList + dedup set"
  结构；`sorted` 属性延迟计算。

### 6.2 Pattern（`xpath.pattern`）

libxml2 的 `xmlPattern` 是 XPath 子集，用于高速选择（XSLT 场景）。本项目把它实现为
"XPath AST 的一个子集 + 专门的前缀自动机编译器"，与完整 XPath 共用解析层。

### 6.3 XInclude（`xinclude`）

- 单独处理器 `XIncludeProcessor`：遍历 DOM，找 `xi:include`，递归加载/替换。
- 依赖 `ResourceLoader` + `catalog`。
- 循环检测：显式维护"正在包含的 URI 集合"，命中即 `XIncludeLoopError`。

### 6.4 XPointer / XLink

- XPointer 仅实现 `element()`、`xpath1()` 两种 scheme（与 libxml2 2.15 一致），其余返回
  `UnsupportedScheme`。

---

## 7. 校验子系统

### 7.1 通用自动机（`regex`）

libxml2 的 `xmlregexp.c` 是专用于 Schema/RelaxNG 的"粒子自动机"，功能上并不等同于一般正则。
本项目：
- `base.regex`（可选改名 `automata`）提供**粒子 NFA → DFA 构造**（Thompson 构造 + 子集构造），
  带"一次性消耗计数"的扩展（XSD 的 `minOccurs/maxOccurs`）。
- 对于"纯字符串正则"（XSD `pattern`、RelaxNG pattern），**直接使用仓颉标准库 `std.regex`**；
  对其 XSD 方言做语法适配层（字符类/转义/Unicode 块）。

### 7.2 DTD（`validate.dtd`）

- 解析阶段由 `parser` 完成（DTD 声明进入 `Document.dtd: ?Dtd`）。
- 校验阶段 `DtdValidator` 遍历文档树：元素内容用 NFA，属性默认值/ID/IDREF/实体检查等。
- 用模式匹配替代 libxml2 大量 `xmlElementType == XXX` 判定。

### 7.3 XML Schema（`validate.xsd`）

最大模块。分阶段：
1. **schema 解析**（Schema for Schemas）：把 `.xsd` 作为普通 XML 解析后，构建组件对象模型
   （`enum XsdComponent { | SimpleType | ComplexType | Element | Attribute | Group | ... }`）。
2. **组件解析**（import/include/redefine/assembly）。
3. **组件编译**（简单类型 facet 编译、复杂类型内容模型编译为自动机）。
4. **实例校验**：流式实现 `SaxHandler`（与解析器管道对接），使之可以"一边解析一边校验"。
5. **PSVI**（post-schema-validation infoset）可选，附加在节点上（`Element.psvi: ?PsviInfo`）。

**仓颉特性受益**：
- 枚举 + 模式匹配大幅简化 libxml2 上万行 `switch (type)`。
- `interface XsdFacet` + 每个 facet 作为 `class` 实现 + `extend` 注册内建类型，替代 C 中"巨型函数 + 分支"。
- `std.math.numeric.Decimal` 用于 `xs:decimal`（若标准库没有，可实现在 `xsd.types`）。

### 7.4 RELAX NG（`validate.relaxng`）

- 先反糖化：Compact → XML → 简单化（Simplification 7 步），按规范重排为派生核心。
- 以 Derivative（Brzozowski 导数）算法实现：每个节点推进 pattern 导数，`nullable?` 判断匹配。
- 内存上用**不可变 pattern 树 + 记忆化**（哈希消除公共子表达式）。

### 7.5 Schematron（`validate.schematron`）

- 作为 XPath 引擎的应用层：解析 `sch:pattern/rule/assert/report`，对每条规则编译成
  XPath，遍历文档求值并收集 SVRL 输出。

---

## 8. Catalog、I/O 与资源加载

- `catalog`：实现 OASIS XML Catalog 1.1（`public`/`system`/`rewriteSystem`/`delegateSystem`/
  `nextCatalog` 等），用 `enum CatalogEntry` + 递归查找。
- `base.io.InputSource` / `OutputSink`：顶层接口只依赖 `std.io.InputStream` / `OutputStream`。
  支持 `FileSource`, `MemorySource`, `StreamSource`, 自定义。
- `ResourceLoader`：
  ```text
  public interface ResourceLoader {
      public func load(url: Uri, kind: ResourceKind, base!: ?Uri): ?InputSource
  }
  ```
  默认实现 `DefaultResourceLoader` 仅支持 `file://`，并先咨询 `Catalog`。
- **不实现 HTTP/FTP**（对照 libxml2，`nanohttp` 已被上游废弃/移除）。需要的用户可在应用层
  实现自定义 `ResourceLoader`（可基于 `stdx.net.http`）。

---

## 9. HTML 解析

- `html` 模块按 HTML5 规范的 "tokenizer + tree construction" 实现，状态机用 `enum` + `match`。
- 与 XML 共享 `core` 节点模型；命名空间规则按 HTML5（默认 `http://www.w3.org/1999/xhtml`）。
- 与 libxml2 的 HTML4 行为对齐程度：**默认使用 HTML5**；提供 `HtmlOptions.legacy: Bool` 开关
  模拟 libxml2 旧行为（宽松程度）。

---

## 10. 错误恢复与限额

- 所有解析器实现"配额收集器" `Limits` 贯穿整个解析生命周期：
  - 当前深度、节点总数、字符总数、实体展开计数、外部实体引用计数。
- 超限即抛 `XmlException(LimitExceeded)`，恢复模式下降级为 `Fatal` 事件但继续。
- 默认值遵循 libxml2 `XML_PARSE_HUGE` 关闭时的上限。

---

## 11. 性能设计

1. **零拷贝词法**：tokenizer 输出 `ByteView`（不拷贝），上层有需要时再 `ByteView.toString()`。
2. **字符串驻留**：所有 QName、属性名、命名空间 URI 驻留，等值比较 O(1)。
3. **紧凑属性**：`Element.attrs: ArrayList<Attribute>`，小属性数（<8）时 ArrayList 内联
   存储（通过对 ArrayList 行为假设，后期可做特化）。
4. **冷热分离**：`Element` 仅存热字段（name, first/last child, next/prev, attrs）；行号、
   URI、base URI 等放入 `Element.locInfo: ?LocInfo`，非调试场景为 `None`。
5. **SIMD 可选**：在 `internal.unsafe.scan` 中实现 `<`、`>`、`&` 的批量搜索（类 simdjson 结构），
   仅在 `build-mode=fast` 时启用。
6. **并发流水线**：大文档解析可选将"tokenize"/"tree-build"/"validate"拆成 3 阶段流水线，
   用仓颉 `spawn` + 有界 `Channel`（`std.sync` / 自建环形缓冲）连接。
7. **分配器**：依赖仓颉 GC；对于已知生命周期的"解析期临时对象"（局部栈、token 缓冲）
   使用 `struct`（栈上）避免 GC 压力。

---

## 12. 并发设计（显式策略）

| 场景 | 策略 |
|---|---|
| 同一 `SaxDriver`/`Reader` 多线程调用 | 禁止。`Reader` 内部 `nonReentrant` 断言。 |
| 不同文档、不同解析器并行 | 支持。所有解析器为独立对象，不共享可变状态。 |
| 只读 `Document` 多线程查询（XPath 等） | 支持。要求文档已 `freeze()`，进入只读模式；`freeze()` 发布使用内存屏障（通过 Atomic）。|
| 可变 `Document` 共享修改 | 用户自备 `Mutex`；`core` 不自动加锁（避免性能损耗）。 |
| XPath 编译结果 | 编译后 AST 不可变，线程安全；`Context` 非线程安全，一线程一份。|
| 全局注册表（编码 Codec、XPath 扩展函数） | 启动期注册；运行期只读。写操作用 `std.sync.Mutex` 保护。 |

---

## 13. 安全与硬化

- **默认关闭**：外部实体、外部 DTD、网络加载、`xinclude`。
- **限额**：见 §10。
- **URI 规范化**：解析前做 `Uri.normalize()`，阻止 `..`/混合编码逃逸。
- **命名空间严格**：默认按 NS 1.0 严格解析；`lenient` 开关仅影响恢复模式。
- **整数**：关键计数字段使用 `Int64` 并配合 `@OverflowThrowing` 注解；溢出即错误。
- **fuzz 测试**：对应 libxml2 `fuzz/`，在 `tests/fuzz/` 中提供 `xml/xpath/html/schema/catalog`
  5 个 fuzz 目标（种子语料从 libxml2 迁移 + 自生成）。

---

## 14. 测试策略

| 层次 | 工具 | 对标 |
|---|---|---|
| 单元 | `std.unittest` + 各模块 `*_test.cj` | libxml2 `testchar/testdict/testmodule/...` |
| 集成 | 自建 harness 驱动 `test/` 样例 + 对比 `result/` | libxml2 `runtest` |
| 规范一致性 | 驱动 W3C XML Conformance Suite | libxml2 `runxmlconf` |
| Schema/RNG | driver + `xstc/` | libxml2 `runsuite` |
| API | 公共 API 覆盖 | libxml2 `testapi`（自动生成） |
| Fuzz | 基于 `cjpm` 集成 fuzzer（TODO: 视工具链支持） | libxml2 `fuzz/` |
| 基准 | `std.unittest` 基准 + 自研 bench runner | libxml2 自带基准 |

测试数据直接复用 `.libxml2-2.15.3/test/`、`result/`、`xstc/`（路径保持，避免重复拷贝）。

---

## 15. 公共 API 速览

```text
// Facade 示例
public class Xml {
    public static func parse(source: String): Document
    public static func parse(source: InputSource, options!: XmlOptions = XmlOptions()): Document
    public static func parseFile(path: String, options!: XmlOptions = XmlOptions()): Document
    public static func reader(source: InputSource, options!: XmlOptions = XmlOptions()): XmlReader
    public static func driveSax(source: InputSource, handler: SaxHandler,
                                options!: XmlOptions = XmlOptions()): Unit
    public static func save(doc: Document, sink: OutputSink, options!: SaveOptions = SaveOptions()): Unit
    public static func evaluate(doc: Document, expr: String, ctx!: XPathContext = XPathContext()): XValue
}
```

```text
// 典型使用
let doc = Xml.parseFile("a.xml")
for (it in doc.root.descendants() | filterByName("item")) {
    println(it.attr("id") ?? "—")
}

let items = Xml.evaluate(doc, "//item[@kind='a']").asNodeSet()
```

### 15.1 与 libxml2 API 的 Mapping（节选）

| libxml2 | CangjieXML |
|---|---|
| `xmlReadFile` / `xmlReadMemory` / `xmlReadIO` | `Xml.parseFile` / `Xml.parse(String)` / `Xml.parse(InputSource)` |
| `xmlNewTextReaderFilename` | `Xml.reader(FileSource(...))` |
| `xmlSAX2* callbacks` | `implements SaxHandler` + 覆盖想处理的方法 |
| `xmlNewDoc` / `xmlNewNode` / `xmlAddChild` | `Document()`、`Element(...)`、`parent.append(child)` |
| `xmlSaveDoc` / `xmlSaveFile` | `Xml.save(doc, sink, SaveOptions(...))` |
| `xmlXPathCompile` / `xmlXPathEvalExpression` | `XPath.compile(expr)` / `expr.evaluate(ctx)` |
| `xmlValidateDtd` | `DtdValidator(dtd).validate(doc)` |
| `xmlSchemaValidate*` | `XsdValidator(schema).validate(doc|stream)` |
| `xmlRelaxNGValidateDoc` | `RelaxNgValidator(schema).validate(doc)` |
| `xmlC14NDocSaveTo` | `Xml.save(doc, sink, SaveOptions(canonicalize=Some(C14n_1_0)))` |
| `xmlXIncludeProcess` | `XIncludeProcessor(options).process(doc)` |
| `xmlCatalogResolve` | `catalog.resolve(publicId, systemId)` |

---

## 16. CLI 工具

- `xmllint`：`cli.xmllint` 包构建为可执行。参数用 `std.console` / 自建 `ArgParser`
  （或等价的 stdx 组件）。覆盖 libxml2 `xmllint` 的主要子命令：
  `--noout --valid --schema --relaxng --xinclude --c14n --xpath --format --encode --memory --shell`。
- `xmlcatalog`：`cli.xmlcatalog`。
- `xmllint --shell` 交互模式用 `match` 分派命令，实现类 libxml2 `shell.c` 体验。

---

## 17. 项目布局（物理层面）

```
CangjieXML/
├── cjpm.toml                   ← 顶层工作区
├── packages/
│   ├── cangjie_xml/            ← facade（root package）
│   ├── base/
│   │   ├── chars/
│   │   ├── uri/
│   │   ├── intern/
│   │   ├── buf/
│   │   ├── io/
│   │   └── encoding/
│   ├── diag/
│   ├── core/
│   ├── parser/
│   ├── html/
│   ├── writer/
│   ├── xpath/
│   ├── xpointer/
│   ├── xinclude/
│   ├── c14n/
│   ├── regex/
│   ├── validate/
│   │   ├── dtd/
│   │   ├── xsd/
│   │   ├── relaxng/
│   │   └── schematron/
│   ├── catalog/
│   └── cli/
│       ├── xmllint/
│       └── xmlcatalog/
├── tests/
│   ├── unit/           ← 每个模块的单测入口（或内联在各模块 `tests/` 中）
│   ├── conformance/    ← W3C 套件驱动
│   ├── regression/     ← 用 libxml2 test/ + result/
│   └── fuzz/
├── benches/
├── docs/
│   ├── user-guide.md
│   ├── api-overview.md
│   └── migration-from-libxml2.md
├── DESIGN.md                   ← 本文
├── ROADMAP.md                  ← 开发计划
└── .libxml2-2.15.3/            ← 参考源（只读，不改动）
```

`cjpm.toml` 使用 workspace + 多 package；条件 feature：`xpath`, `xinclude`, `c14n`,
`xsd`, `relaxng`, `schematron`, `html`, `catalog`, `cli`（默认全开）。

---

## 18. 与 libxml2 行为差异（显式声明）

为避免用户预期错位，以下差异**明确写入**用户手册：

1. **UTF-8 优先**：API 以 `String` 暴露；不再有 `xmlChar*` 概念。
2. **内存管理**：无需 `xmlFree*`；对象由 GC 回收。显式 `doc.close()` 只释放持有的 IO 资源。
3. **全局状态**：不再有 `xmlKeepBlanksDefault`、`xmlIndentTreeOutput` 等"进程级开关"；
   全部改为 `XmlOptions` / `SaveOptions` 参数。
4. **线程模型**：不再有 `xmlInitThreads/xmlLockLibrary`；并发由仓颉模型承担，见 §12。
5. **SAX1**：不支持（上游已废弃）。
6. **HTTP/FTP**：不支持；由用户自定义 `ResourceLoader` 扩展。
7. **动态模块**：不支持（`xmlmodule`）。
8. **编码**：默认内建集不依赖 iconv；需要额外编码时由用户注册 Codec。
9. **错误码**：从"整型全局"改为"域+枚举码"；提供 libxml2 码到新码的映射表（`diag.legacy`）。

---

## 19. 关键技术方案与 Demo 验证点

以下点在开发前建议用"**最小 Demo**（<200 行）"做验证（对应 ROADMAP M0）：

1. **代数节点模型 + 模式匹配遍历速度**：构造 10^6 节点，比较 `match` vs. `if-else` 遍历耗时。
2. **字符串驻留池的哈希冲突与内存**：压测 10^5 不同 QName。
3. **UTF-8 零拷贝切片**：`ByteView.toString()` 是否仅在需要时触发拷贝。
4. **并发 Reader**：两个文件并行解析，验证无共享状态。
5. **std.regex 是否满足 XSD pattern**：试 `^(?:[A-Z]{3}[0-9]{3,5}|N/A)$` 等。
6. **弱引用 `WeakRef<Node>`**：验证父指针不阻止子树 GC。
7. **宏 `@derive ToString` / 自动派生**：验证节点 Debug 输出可自动生成。
8. **cjpm workspace + feature flags**：多包条件编译能否按需裁剪。

Demo 在 `prototype/` 目录内（ROADMAP M0 阶段产出，随后删除或归档）。

---

## 20. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| 仓颉 GC 延迟在 XML 大文档序列化中不可预测 | 性能回退 | 冷热分离 / struct 栈分配 / 允许 `compact` 文档模式；在 benchmark 中早期测量 |
| XML Schema 复杂度极高，易延期 | 里程碑滑移 | ROADMAP 将 XSD 拆成 3 个子里程碑；先交付简单类型+基本 particle |
| XPath 1.0 文档序相关 bug 难发现 | 功能正确性 | 直接驱动 libxml2 `runtest` 的 XPath 用例作为黄金对照 |
| 字符集不依赖 iconv 覆盖不全 | 解析文件失败 | 提供可插拔 Codec + 清单化支持的编码列表；文档明确说明 |
| 并发安全在可变 DOM 上被误用 | 数据竞争 | 文档明确：可变 DOM 非线程安全；`freeze()` 提供只读快照 |
| 与 std.regex 语义差异 | XSD pattern 误判 | 编写适配层 + 完整的合规测试 |

---

## 21. 总结

本设计用仓颉语言的代数数据类型、模式匹配、扩展、接口默认实现、Option/错误处理、并发
原语等特性，把 libxml2 的 20+ 年 C 代码重新映射为一个**模块化清晰、默认安全、并发友好、
接口窄而扩展丰富**的现代 XML 工具箱。架构上保留 libxml2 对规范的覆盖面（核心解析、SAX、
Reader、Writer、XPath、XInclude、C14N、DTD/XSD/RNG/Schematron、Catalog），但在 API 形态、
错误模型、资源管理、全局状态、并发模型等方面按仓颉范式重构，避免机械搬运 C 结构。
开发节奏见 `ROADMAP.md`。
