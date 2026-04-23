# CangjieXML 软件设计文档

> 用仓颉（Cangjie）编程语言对 [libxml2 v2.15.3](./.libxml2-2.15.3) 做**优化重构式复刻**。
> 目标是在保持 W3C XML 规范语义与 libxml2 主要功能对等的前提下，充分运用仓颉的现代语言特性（enum + 模式匹配、sealed 接口、扩展、泛型、Option/Result 式错误处理、M:N 协程、原子/互斥/条件变量、宏元编程、反射等），抛弃 C 层面的句柄/指针/void\* 风格，建立一个**类型安全、内存安全、线程友好、可组合**的 XML 工具链。
>
> 本文档只描述**做什么**与**为什么这样做**，不涉及具体代码实现。

---

## 1. 背景与目标

### 1.1 libxml2 是什么
libxml2 是 GNOME 项目孵化的 XML 工具集，以 C89 实现、约 17 万行核心 C 代码，提供：

| 领域 | libxml2 对应源文件 |
| --- | --- |
| DOM 树/节点模型 | `tree.c`, `include/libxml/tree.h` |
| 解析器（推/拉/块/SAX） | `parser.c`, `parserInternals.c`, `SAX2.c` |
| 实体、字典、符号表 | `entities.c`, `dict.c`, `hash.c`, `list.c` |
| 字符串/缓冲/字符类 | `xmlstring.c`, `buf.c`, `chvalid.c` |
| 编码 | `encoding.c` |
| IO 抽象 | `xmlIO.c`, `nanohttp.c` |
| URI / Catalog | `uri.c`, `catalog.c` |
| DTD 验证 | `valid.c` |
| 正则 / 自动机 / 模式 | `xmlregexp.c`, `pattern.c` |
| XML Schema (XSD) | `xmlschemas.c`, `xmlschemastypes.c` |
| RelaxNG / Schematron | `relaxng.c`, `schematron.c` |
| XPath / XPointer / XInclude | `xpath.c`, `xpointer.c`, `xinclude.c` |
| 规范化 C14N | `c14n.c` |
| 流式读 / 流式写 | `xmlreader.c`, `xmlwriter.c`, `xmlsave.c` |
| HTML 解析与输出 | `HTMLparser.c`, `HTMLtree.c` |
| 错误/全局/线程 | `error.c`, `globals.c`, `threads.c` |
| 命令行/调试 | `xmllint.c`, `xmlcatalog.c`, `shell.c`, `debugXML.c` |

### 1.2 项目目标
1. **功能对等（核心子集）**：支持 XML 1.0/1.1 解析与序列化、命名空间、DTD、XPath 1.0、XInclude、C14N 1.0/1.1、XML Schema 1.0 与 RelaxNG 的主要使用场景。
2. **接口现代化**：抛弃 `void*` 上下文、`int` 返回码、全局 hook，改用仓颉的 `interface`、`enum`、`Result`/`Option`、`Iterator`、`Resource`。
3. **纯仓颉实现**：只依赖 `std.*` 与 `stdx.*`（必要时，如压缩/TLS）；不调用 C 库、不走 CFFI。
4. **线程安全**：核心数据结构（字典、编码注册表、错误处理）天然多线程安全；解析器为"每文档一个实例"模型，可并发运行。
5. **可裁剪**：模块之间按 cjpm 子包划分，下游只导入需要的能力。
6. **可扩展**：用户可用仓颉的 `extend` 为 `Node`/`Document` 添加方法，用自定义 `interface` 替换 IO 层、错误层、URI 解析层。

### 1.3 非目标
- 不追求与 libxml2 ABI 级兼容（指针布局、宏、函数名完全不同）。
- 不内嵌 HTTP/FTP 客户端（libxml2 的 `nanohttp.c`/`nanoftp.c` 不复刻，改成可插拔 URI 加载器接口，用户自行提供 `stdx.net.http`）。
- 不提供 Python/Perl 绑定（属于宿主生态问题）。
- 初版不复刻 `xmlmodule`（C 动态库插件机制），改为仓颉的 `package` + `interface` 插件机制。

---

## 2. 设计原则（Cangjie-first）

| # | 原则 | libxml2 的 C 做法 | CangjieXML 的做法 |
| --- | --- | --- | --- |
| P1 | 代数数据类型优先 | `xmlElementType` 枚举 + 20 种布局略异的 `xmlNode` 结构 | 用 `sealed interface Node` + 各具体 `class`/`enum` 分支；用户用 `match` 穷尽处理 |
| P2 | 不可变字符串 | 自定义 `xmlChar*`（UTF-8 字节串） | 直接用仓颉 `String`（UTF-8）；需原始字节时用 `Array<Byte>` |
| P3 | 类型安全的错误 | `xmlError` 全局结构 + 返回码 | `enum XmlError` + `class XmlException <: Exception`；库内部用 `Result<T, XmlError>`，公共 API 用异常 |
| P4 | 所有权与生命周期 | 手动 `xmlFree*`，易出 UAF | 仓颉 GC + 资源类 (`Resource`/try-with-resources) 管理 IO/锁 |
| P5 | 组合优于继承 | SAX 回调为函数指针表 | `interface SAXHandler`，可用默认实现 + mixin 组合 |
| P6 | 并发即一等公民 | 全局锁 + 线程局部 | `Mutex`/`AtomicReference`/`spawn`；解析器为值化上下文 |
| P7 | 零拷贝读取 | 手写 parser state | 输入流分片 + `Array<Byte>` 视图 + 惰性字符串化 |
| P8 | 迭代器与管道 | 手工 `next`/`prev` 指针 | 实现 `Iterable<Node>`；用 `\|>` 管道组合 XPath/Pattern 过滤 |
| P9 | 元编程生成样板 | 宏 `#define XMLPUBFUN` | 用仓颉宏 (`@Visitor`, `@SchemaBuilder`) 自动派生访问器/构建器 |
| P10 | 可测试优先 | 外部 `runtest.c` + 黄金文件 | 仓颉 `@Test` 单元测试 + XML W3C TestSuite 驱动器 |

---

## 3. 项目结构（cjpm 工作区）

采用工作区（workspace）布局；每个目录是一个独立可发布的仓颉包，顶层 `cjpm.toml` 声明成员。

```
CangjieXML/
├── cjpm.toml                     # workspace + 顶层元数据
├── DESIGN.md                     # 本文
├── ROADMAP.md                    # 渐进开发计划
├── packages/
│   ├── xml_core/                 # 字符类、UTF 校验、缓冲、字典、URI、错误
│   │   └── src/
│   │       ├── char_valid.cj
│   │       ├── buffer.cj
│   │       ├── dict.cj            # 字符串 intern 池（替代 xmlDict）
│   │       ├── uri.cj
│   │       └── error.cj
│   ├── xml_encoding/             # 编码注册表、UTF-8/16/ISO-8859-x、BOM 检测
│   ├── xml_io/                   # ParserInputSource / OutputSink 抽象 + 文件/内存适配
│   ├── xml_tree/                 # Document / Node / Attr / Namespace / DTD 数据模型
│   ├── xml_sax/                  # SAXHandler 接口与缺省实现
│   ├── xml_parser/               # 推/拉解析器 + 命名空间 + 实体处理
│   ├── xml_html/                 # HTML5/4 宽松解析器（基于 xml_parser 复用词法器）
│   ├── xml_writer/               # 流式序列化 Writer
│   ├── xml_save/                 # DOM 序列化（缩进、编码转换）
│   ├── xml_c14n/                 # 规范化（1.0 / 1.1 / 排他）
│   ├── xml_dtd/                  # DTD 解析 + 验证
│   ├── xml_regexp/               # 基于 XSD 正则子集的自动机
│   ├── xml_pattern/              # 简化 XPath 模式匹配（用于 reader / schema）
│   ├── xml_xpath/                # XPath 1.0 引擎（AST + 求值）
│   ├── xml_xptr/                 # XPointer (element(), xpath())
│   ├── xml_xinclude/             # XInclude 处理器
│   ├── xml_schema/               # XML Schema 1.0 (XSD)
│   ├── xml_relaxng/              # RelaxNG Compact/XML 语法
│   ├── xml_schematron/           # Schematron（基于 xml_xpath）
│   ├── xml_catalog/              # XML Catalog v1.1
│   ├── xml_reader/               # 拉式流读（对应 xmlreader.c）
│   ├── xml_testkit/              # W3C TestSuite 驱动 + 黄金对比
│   ├── xml/                      # 门面包：public import 上述常用 API
│   └── tools/
│       ├── xmllint/              # 可执行：对应 xmllint
│       └── xmlcatalog/           # 可执行：对应 xmlcatalog
└── tests/                        # 工作区级集成测试（解析→验证→XPath 端到端）
```

**依赖方向**（箭头表示"依赖"）：

```
xml_core ──┬─> xml_encoding ──> xml_io ──> xml_sax ──> xml_parser ──> xml_tree ──┐
           │                                                                     │
           ├─> xml_regexp ──> xml_pattern ──> xml_xpath ──> xml_xptr ─────────────┤
           │                                                                     │
           │                           xml_dtd ───────────────────────────────> xml_reader
           │                           xml_schema, xml_relaxng, xml_schematron ─>┘
           │
           └─> xml_catalog, xml_c14n, xml_xinclude, xml_writer, xml_save, xml_html
```

**工具包**（`xml/`、`tools/*`）只做 public import，不加新逻辑。

---

## 4. 核心数据模型

### 4.1 节点树：`sealed interface Node` + 分支类

libxml2 用一个超集结构体（`xmlNode`）覆盖 14 种节点类型，字段复用导致大量 `if (type == …)` 分支与字段不可见性污染。CangjieXML 的做法：

```text
sealed interface Node {
    prop parent: ?Element
    prop document: ?Document
    func accept<R>(v: NodeVisitor<R>): R     // 访问者，和 match 二选一
}

class Document   <: Node { ... }              // 根，含 DTD、根元素、字符集、版本
class Element    <: Node { ... }              // 元素：名字、命名空间、属性集、子节点
class Attr       <: Node { ... }              // 属性：名字、命名空间、值（节点列表）
class TextNode   <: Node { ... }              // #text
class CData      <: Node { ... }              // CDATA section
class Comment    <: Node { ... }              // <!--  -->
class Pi         <: Node { ... }              // <?target data?>
class EntityRef  <: Node { ... }              // &name;
class DocFrag    <: Node { ... }              // 文档片段
class Dtd        <: Node { ... }              // <!DOCTYPE …>
class XIncludeMarker <: Node { ... }          // 合并 XINCLUDE_START/END
```

- `sealed` 保证外部无法新增分支 → `match` 编译期穷尽。
- 公开字段全部走 `prop`（仓颉属性），避免 libxml2 `XML_DEPRECATED_MEMBER` 标注仍暴露的问题。
- `EntityDecl`、`ElementDecl`、`AttributeDecl`、`Notation` 不进入通用 `Node`，而是作为 `Dtd` 的成员，因为它们从未出现在普通文档主干中；这修复 libxml2 中的"类型混淆"安全分类。
- **命名空间节点**（`XML_NAMESPACE_DECL`）在 libxml2 里偷用同样布局但实际是 `xmlNs`，历史上出过多次类型混淆 CVE。CangjieXML 把命名空间节点仅在 XPath 结果中作为独立 `class NsNode <: XPathItem` 出现，不混入 `Node`。

### 4.2 字符串表（Dict）

`xmlDict` 是 libxml2 性能核心（元素名/属性名去重）。仓颉版用 `HashMap<String, String>` 做不够，因为需要**引用相等比较**。设计：

- `class NameTable`：内部 `HashMap<String, String>`，`intern(s): String` 返回池内实例。
- 借助仓颉 `String` 不可变 + GC，免除 libxml2 里 `xmlDictReference` 的引用计数。
- `NameTable` 可按 `Document` 级作用域创建；一个进程内可安全多份（线程局部 or 按文档）。
- 通过 `extend String` 增加 `internedIn(t: NameTable)` 这种链式调用语法糖。

### 4.3 URI 与 Catalog

- `struct Uri` 为不可变值类型（仓颉 `struct`），提供 `parse / resolve / normalize`。
- `Catalog` 暴露为 `interface EntityResolver`；内置实现读 OASIS XML Catalog，用户也可替换为用 `stdx.net.http` 获取远程 schema 的解析器。

### 4.4 错误模型

```text
public enum XmlError {
    | WellFormed(WfKind, Position, String)
    | Validity(VKind, Position, String)
    | Namespace(String, Position)
    | Io(IoKind, String)
    | Encoding(String, Position)
    | Schema(SchemaKind, Position, String)
    | XPath(XpKind, String)
    | Internal(String)
}

public class XmlException <: Exception { ... }   // 包装 XmlError
```

- `Position` = `(uri: ?String, line: Int64, column: Int64, byteOffset: Int64)`。
- 库内部大量使用 `Result<T, XmlError>`（用 `enum Result<T,E>`，也可沿用仓颉惯例返回 `?T` + 旁路日志）。
- 公共 API 可选 fluent 模式："收集所有错误"或"首错即抛"，由 `ErrorCollector` 接口控制（替代 libxml2 `xmlStructuredErrorFunc` 全局函数指针）。
- 没有全局错误状态：libxml2 的 `xmlGetLastError()` 是全局可变，线程下易冲突；CangjieXML 显式通过 `ParseResult` 返回 `List<XmlError>`。

---

## 5. 字符/编码/IO 层

### 5.1 字符类（`xml_core.char_valid`）

libxml2 的 `chvalid.c` 手写了一堆 ASCII range。仓颉做法：

- 用 `const` 函数 + 区间查找（`const func isXmlNameStart(c: Rune): Bool`）在编译期常量折叠。
- 针对 XML 1.0 / 1.1 不同字符类，用**类型参数**区分：`XmlNameChecker<V>` where `V: XmlVersion`（零开销泛型）。
- 提供 `Iterator<Rune>` 的扩展函数 `.validateXmlChars()` 惰性校验输入。

### 5.2 编码（`xml_encoding`）

- 定义 `interface Decoder`（`decodeChunk(bytes: Array<Byte>, into: StringBuilder): DecodeStatus`）和 `interface Encoder`。
- 内置 UTF-8、UTF-16LE/BE、UTF-32LE/BE、ASCII、ISO-8859-1…15 纯仓颉实现。
- 其它编码（GB18030、Shift-JIS 等）通过 `interface Decoder` 可插拔注册，不在初版范围。
- BOM 检测器独立为 `enum BomKind { Utf8, Utf16LE, Utf16BE, Utf32LE, Utf32BE, None }` + `detect(bytes): (BomKind, prefixLen)`。
- 与 libxml2 不同：**不依赖 iconv**；编码不支持时直接 `XmlError.Encoding` 而非隐式回落。

### 5.3 IO 抽象（`xml_io`）

```text
public interface ParserInputSource <: Resource {
    func read(buf: Array<Byte>): Int64   // 返回读入字节数，-1 表示 EOF
    prop baseUri: ?String
    prop encoding: ?String   // 由 HTTP header 等带进来的提示
}

public interface OutputSink <: Resource {
    func write(bytes: Array<Byte>): Unit
    func flush(): Unit
}
```

适配器：

- `FileInputSource` / `FileOutputSink`（基于 `std.fs`）
- `MemoryInputSource(bytes: Array<Byte>)`
- `StringInputSource(s: String)` — 自动 BOM 跳过 + UTF-8 标记
- `ReaderInputSource` — 适配任意 `InputStream`

`OutputSink` 支持装饰器：

- `IndentingSink(inner, indent: String)`
- `EncodingSink(inner, encoder: Encoder)`
- `BufferedSink(inner, size: Int)`

用 `|>` 或 `~>`（仓颉函数组合）拼接，避免 libxml2 中 `xmlOutputBuffer` 的函数指针海。

---

## 6. 解析器设计

### 6.1 核心思想：**状态机 + 分层词法器**，避免 libxml2 13k 行单文件

把 libxml2 的 `parser.c` 拆成 5 层：

1. **字节流层** (`ByteReader`)：负责从 `ParserInputSource` 读入并维持回滚缓冲（至少 `LOOKAHEAD=8` 字节）。
2. **字符流层** (`RuneReader`)：按注册的 `Decoder` 把字节流转成 `Rune` 流，维护行列号、字节偏移。同时透明处理 XML 1.1 规定的换行归一化。
3. **词法层** (`Lexer`)：`enum Token { TagOpen, TagClose, AttrName, AttrValue(String), Text(String), Cdata(String), PI, Comment, Dtd, Ref(EntityKind, String) … }`；词法器是**一个函数 + match 大状态机**，每个分支不超过 80 行。
4. **语法层** (`Parser`)：不再用回调，而是**生成 `Iterator<SaxEvent>`**：
   ```text
   enum SaxEvent {
       StartDocument(XmlDecl)
       EndDocument
       StartElement(QName, attrs: Array<Attribute>, nsCtx: NsContext)
       EndElement(QName)
       Characters(String)  | CData(String)
       Comment(String)     | PI(target: String, data: String)
       Dtd(DtdDecl) | EntityRef(String)
       Error(XmlError)       // 非致命时以事件形式流出
   }
   ```
5. **高层外观** (`XmlParser`)：包一层 `Iterator<SaxEvent>`，提供三种消费姿势（见 6.2）。

这样每层都是纯函数或小状态机，**天然支持流式、易测、可惰性组合**。

### 6.2 三种消费接口，一体实现

| API 风格 | 对应 libxml2 | CangjieXML 做法 |
| --- | --- | --- |
| **SAX（推）** | `xmlSAXUserParseMemory` | 外部把 `Iterator<SaxEvent>` 分派到 `SAXHandler`（默认实现空函数，开发者只重写关心的） |
| **Reader（拉）** | `xmlreader.c` | 把迭代器再裹一层状态机，增加"当前节点类型/属性"访问 |
| **Tree/DOM** | `xmlReadMemory` | 消费事件构建 `Document`；内部就是个 SAX handler |

推式由**外**推事件到 handler，拉式由**外**驱动迭代器，本质是同一个生成器。这消除了 libxml2 里 push/pull 双实现不一致的顽疾。

### 6.3 命名空间

- `NsContext` 为不可变堆栈：`{ prefix -> uri }`，push 后返回新实例（结构共享，参考持久化栈）。
- 遇到 `xmlns` 属性，`StartElement` 事件同时携带新 `NsContext`。
- QName 统一为 `struct QName { localName: String, prefix: ?String, uri: ?String }`；比较走三元组，避免 libxml2 中混用 `prefix:localname` 字符串解析。

### 6.4 实体处理

- 内置实体（`&lt;` 等）硬编码；**参数实体**与**通用实体**由 `EntityResolver` 返回 `ParserInputSource`，解析器递归下推。
- 内建 `BillionLaughsDetector`：对实体展开计数 + 栈深度限制，默认阈值可由 `ParserOptions` 调整。
- 默认关闭外部实体加载（对齐 XXE 安全最佳实践，libxml2 默认开启导致大量 CVE），用 `ParserOptions.loadExternal = true` 显式开启。

### 6.5 解析器选项

```text
struct ParserOptions {
    validate: Bool = false
    substituteEntities: Bool = true
    loadExternal: Bool = false        // 默认安全
    huge: Bool = false                // 取消深度/大小限制
    recover: Bool = false             // 容错模式
    namespaces: Bool = true
    keepBlanks: Bool = true
    version: XmlVersion = V10
    maxDepth: Int64 = 256
    maxEntityExpansion: Int64 = 10_000_000
    nameTable: ?NameTable = None
}
```

不用 libxml2 的位掩码；仓颉结构体带命名参数 + 默认值，调用点自解释。

---

## 7. Tree / DOM API

### 7.1 构建

- `class DocumentBuilder`：**流畅 API**。利用仓颉的尾随 lambda：
  - `buildDoc { doc in doc.root("book") { b in b.attr("id","1").child("title"){...} } }`
- 也可从 `Iterator<SaxEvent>` 一次性构造：`Document.from(events)`。

### 7.2 遍历

- `Node` 实现 `Iterable<Node>`（按文档顺序 DFS），亦提供 `children()`, `descendants()`, `ancestors()`, `followingSiblings()` 等迭代器。
- 所有迭代器**惰性**；不再像 libxml2 拷贝 `xmlNodeSet`。

### 7.3 修改

- 节点提供 `appendChild/insertBefore/remove/replaceWith`。
- 为避免 libxml2 "同一节点被插到两处导致双链断裂" 的隐患，增加 `Node.detached: Bool` 检查；重复插入立即 `XmlException`。
- 属性表采用有序 `ArrayList<Attr>` + 小哈希（阈值切换）；既保留属性原始顺序（C14N 需要），又 O(1) 查找。

### 7.4 扩展（`extend`）

鼓励用户**用扩展加功能而非修改核心**：

- `extend Element` 添加 `getElementsByTagName`, `innerText`, `serialize`。
- `extend Node where Node <: Iterable<Node>` 可加 `findFirst(pred)`、`toList()` 等泛型工具。

---

## 8. XPath 1.0 引擎

### 8.1 架构三段式

```
Source String
   └─> Lexer   (enum Token)
          └─> Parser (产出 AST: enum Expr / enum Step)
                 └─> Evaluator (动态 dispatch on Expr, 访问 Node 树)
                        └─> XPathItem (Nodeset / Boolean / Number / StringValue)
```

### 8.2 语言对照优势

- `enum Expr { Path(Array<Step>), Binary(Op, Expr, Expr), FuncCall(String, Array<Expr>), Literal(String), Number(Float64), VarRef(QName) }` — 极简 AST，模式匹配求值。
- Axis 用 `enum Axis { Self, Child, Parent, Descendant, DescendantOrSelf, Ancestor, AncestorOrSelf, Following, FollowingSibling, Preceding, PrecedingSibling, Attribute, Namespace }`；每个 axis 实现为 `Iterator<Node>` 生成器。
- 节点集合用 `class NodeSet` 内部为**惰性迭代器 + 按需唯一化/文档序排序**，避免 libxml2 里频繁的全量拷贝。
- 函数库用 `HashMap<String, XPathFunc>` 注册；用户可扩展 `registerFunction`。

### 8.3 并发

- XPath AST 是**不可变**的；同一 compiled expression 可被多线程同时求值（每次求值自带上下文 `XPathContext`）。用 `class CompiledXPath` 提供 `eval(ctx: XPathContext): XPathItem`。

### 8.4 XPointer / Pattern

- `xml_xptr` 在 XPath 基础上实现 `element()` 与 `xpath()` 方案；
- `xml_pattern` 实现 libxml2 `pattern.c` 子集（流式节点匹配，用于 reader / schema 选择器）。它是 XPath 的"纯下降子集"，内部编译成自动机，**不走 XPath 完整求值器**。

---

## 9. 验证：DTD / XSD / RelaxNG / Schematron

### 9.1 DTD（`xml_dtd`）

- DTD 解析复用 `xml_parser` 的词法器（DTD 词法是 XML 一种子语言）。
- 内容模型编译为**非确定自动机** → 用子集构造法转 DFA（复用 `xml_regexp`）。
- 验证器实现 `interface Validator`：
  - SAX 式：订阅 `SaxEvent` 流，在线验证 → 适合 `xml_reader`。
  - Tree 式：对 DOM 遍历。

### 9.2 正则 / 自动机（`xml_regexp`）

libxml2 的 `xmlregexp.c`/`xmlautomata.h` 是自家实现的 XSD 正则（不是 PCRE）。CangjieXML 做法：

- `enum Re { Char(Rune), CharClass(CharSet), Seq(Array<Re>), Alt(Array<Re>), Rep(Re, min, max), Capture(Int, Re) }`。
- `CharSet` 使用**排序区间数组**（`Array<(Rune,Rune)>`) + bitset 加速 ASCII，支持 Unicode block（XSD 的 `\p{IsBasicLatin}` 等）。
- Thompson 构造 → NFA → 子集构造 DFA；提供"匹配"与"进入/退出"（流式）两种 API。
- **不**暴露给最终用户做通用正则（那是 `std.regex` 的事）；仅供 XSD/DTD/Schema 选择器使用。

### 9.3 XML Schema 1.0（`xml_schema`）

- 三阶段：**parse**（XSD 文档→元模型）、**compile**（解析组件引用、类型派生、group/attrGroup 展开）、**validate**（同时支持 DOM 与流式）。
- 元模型用大量 `sealed class` + `enum`：
  - `sealed class SchemaType` → `SimpleType` / `ComplexType`。
  - `enum DerivationKind { Restriction, Extension, List, Union }`。
- Facets 定义在 `enum Facet { MinLength(Int), MaxLength(Int), Pattern(Re), Enumeration(Array<String>), ... }`。
- 用 `xml_xpath` 做 XPath-based `xs:unique` / `xs:key` 约束。
- 内建 44 个 XSD 简单类型（anyURI, dateTime, duration, decimal…），每个都是 `class : SimpleType`，通过 `extend` 注册 `lexicalSpace` 和 `canonicalize`。

### 9.4 RelaxNG（`xml_relaxng`）

- 采用 "Derivative-based" 验证算法（Brzozowski 导数，比 libxml2 的自动机法更简洁正确）。
- Pattern 为 `sealed class`，导数运算是一组 `override func deriv(event): Pattern`。
- Compact syntax 由 `tools/` 中单独转换器转成 XML Syntax（非核心路径）。

### 9.5 Schematron（`xml_schematron`）

- 本质是"按规则求 XPath"：极薄的一层，直接复用 `xml_xpath`。

---

## 10. 输出侧

### 10.1 Writer（流式，`xml_writer`）

- 对应 libxml2 `xmlwriter.c`。
- API：`class XmlWriter(sink: OutputSink)` + 一组 `startElement / endElement / writeAttribute / writeText` 方法。
- 内部用栈跟踪打开的元素，避免 libxml2 里松散的 API 滥用导致的非良构输出。
- 支持缩进、编码转换（借 `EncodingSink`）。

### 10.2 Save（DOM 序列化，`xml_save`）

- 对应 libxml2 `xmlsave.c`。基于 Writer，再加上"优先使用 CDATA 段/字符引用"等选项。
- 序列化选项通过 `struct SaveOptions { indent, indentString, noDecl, asXmlElemOnly, encoding, c14nMode: ?C14NMode }`。

### 10.3 Canonicalization（`xml_c14n`）

- 实现 C14N 1.0、Exclusive C14N、C14N 1.1。
- 把历史上多次 CVE 的 attr-axis 实现重新设计：用**不可变** `NsContext` + **确定性排序**（命名空间序 < 属性序），天然避免类型混淆。
- 节点过滤用 `interface C14NInclusionFilter { func include(n: Node): Bool }`；默认全包含。

---

## 11. HTML（`xml_html`）

- libxml2 `HTMLparser.c` 是独立的宽松解析器。
- CangjieXML 做法：**共享** `xml_parser` 的词法层，但在 `Lexer` 之上加 `HtmlInsertionMode` 状态机（对齐 WHATWG HTML 解析算法的核心插入模式）。
- 文档模型复用 `xml_tree` 的 `Document` + 属性（`isHtml: Bool`）。
- 不追求完整 HTML5 DOM（如 shadow DOM），只覆盖 libxml2 当前能力（主要用于 xpath/scraping）。

---

## 12. 并发

### 12.1 总原则
- 数据结构默认**值语义**或**只读共享**；可变状态集中在"解析器实例"与"Writer 实例"上，单线程使用。
- 全局注册表（编码注册表、内建实体、默认 Entity Resolver）在进程启动期 `const` 或 `static` 初始化，运行期不再写。用户自定义注册通过**显式注入**进具体 `ParserOptions`，不走全局。
- 共享可变（字典、Schema 编译缓存）用 `Mutex` / `ReentrantLock` / `AtomicReference`。

### 12.2 并行能力
- `Document` 一旦构造完成视为不可变（不提供并发修改 API），多线程可同时：
  - XPath 查询（已编译表达式线程安全）
  - 序列化
  - 验证
- 大文档分片解析用 `spawn` + 多 `ParserInputSource`：例如根元素下 `chunked` 段，由上层切分后并行构造子树再拼装（作为可选优化，见 ROADMAP Phase 12）。
- Schema 编译结果（`CompiledSchema`）不可变，天然可被多线程共享 / 并发验证多个文档。

### 12.3 取消

所有长耗时 API（解析、验证、XPath）接受 `CancellationToken`（基于仓颉 `Future` 的 `cancel`/ `ThreadLocal` 机制），用于在超时或上层停止时及时中断，避免 libxml2 中靠全局 `xmlParserMaxDepth` 粗粒度保护的问题。

---

## 13. 宏与元编程

利用 `std.ast` 与仓颉宏，降低样板代码：

1. **`@Visitor`**：为 `sealed interface Node` 自动派生 `NodeVisitor<R>` 接口与 `accept` 实现。
   - 开发者只需写 `@Visitor class Node { ... }` 即可得到 `visitElement/visitText/...` 派生。
2. **`@SchemaModel`**：对 XSD 类型元模型的数据类自动派生 `derive(kind, base)` 等类型派生函数。
3. **`@XPathFunction("namespace-uri")`**：标记 XPath 自定义函数，自动生成注册代码。
4. **`@Test`**（沿用仓颉单测宏）：每个包自己的单元测试。

宏仅用于**消除样板与保证穷尽性**，不做"魔法" DSL，确保可读性。

---

## 14. 错误与诊断

- 每个事件/异常携带 `Position`。
- 解析器运行期产生 `List<XmlError>`，通过 `ParseResult { doc: ?Document, errors: List<XmlError> }` 返回，便于 IDE/工具逐条显示。
- 提供格式化器：`func formatError(err: XmlError, source: ?String): String`，模仿编译器风格（文件:行:列 + ^ 指针）。
- 调试包 `xml_debug`（暂不单独出包，合入 `xml_tree`）：`dump(n: Node): String` 打印结构，类似 `debugXML.c`。

---

## 15. 安全性默认

对齐 OWASP XML 处理安全建议：

| 风险 | 默认策略 |
| --- | --- |
| XXE（外部实体） | `loadExternal=false` |
| Billion Laughs | 实体展开计数阈值 1e7，超限抛错 |
| 深层嵌套 | `maxDepth=256` |
| DTD 大小 | DTD 声明数量有阈值 |
| URL 自动取回 | 默认禁止，需显式 `EntityResolver` |
| 字符归一化 | 严格拒绝非法 UTF-8，不使用"替换字符"静默替换 |

每条都对应一个显式 `ParserOptions` 字段，易审计。

---

## 16. 测试策略

1. **单元测试**：每包 `src/test/*.cj`，`@Test`；覆盖字符类、编码、URI、词法、AST、自动机构造等。
2. **属性测试**：为 `Uri.parse/normalize` 等写随机化属性（可先手工，框架化等 stdx 完善）。
3. **黄金文件**：从 `.libxml2-2.15.3/test/` 与 `result/` 目录拷贝标准测试集（数千个样例，涵盖 XML、DTD、Schema、XPath、C14N、XInclude），作为端到端回归。
4. **W3C TestSuite**：`xml_testkit` 提供驱动器，消费 `xmlconf/xmlconf.xml` 清单；对应 libxml2 `runxmlconf.c`。
5. **模糊测试**：`.libxml2-2.15.3/fuzz/` 里的种子语料库可直接喂给 CangjieXML 的解析器做崩溃测试（用仓颉简单 harness + 随机 mutation，先不接外部 libFuzzer）。
6. **性能基线**：选一组 XML（1MB / 10MB / 100MB）做解析/XPath/序列化 benchmark；用 `std.time` + 仓颉 `cjprof`。

---

## 17. 与 libxml2 行为差异（刻意不兼容的地方）

| libxml2 行为 | CangjieXML | 理由 |
| --- | --- | --- |
| 默认加载外部 DTD/实体 | 默认禁用 | 默认安全 |
| `xmlGetLastError` 线程局部全局 | 无全局；`ParseResult.errors` | 可测、线程友好 |
| `void*` SAX userData | `class`/`interface` 显式 | 类型安全 |
| `xmlNode` 超集结构 | `sealed interface` + 分支 | 类型安全 + 穷尽 match |
| 内嵌 HTTP/FTP | 去除，留 `EntityResolver` 钩子 | 单一职责 |
| iconv 耦合 | 纯仓颉编码表 + `Decoder` 接口 | 可移植 |
| 手工引用计数/free | GC + `Resource` | 内存安全 |
| XPath `xmlXPathObjectPtr` | `enum XPathItem` | 表达力 |

上述差异均**不违反 W3C 规范**；规范层面 CangjieXML 可通过同一批 W3C 测试。

---

## 18. 初版范围界定（MVP vs Full）

- **MVP（ROADMAP Phase 0–6）**：良构解析、DOM、SAX、Reader、命名空间、UTF-8/16、序列化、XPath 1.0、基本错误。
- **Full v1.0（Phase 7–12）**：DTD 验证、XSD、RelaxNG、XInclude、C14N、HTML、Catalog、`xmllint` 工具、性能优化。
- **Post v1.0**：Schematron 完整、XPath 2.0/3.x（如需）、Streaming Schema（单独项目）。

---

## 19. 决策记录（ADR 摘要）

- **ADR-001**：采用 `sealed interface Node` 而非枚举 `Node`。理由：节点附带大量子成员状态，`class` 比 `enum` payload 读写更自然。
- **ADR-002**：解析器输出 `Iterator<SaxEvent>` 统一 SAX/Reader/DOM。理由：单一真理来源。
- **ADR-003**：不提供 C ABI/CFFI 绑定。理由：目标是"重构式复刻"，下游仓颉项目通过包机制使用；如需与 C 互操作，属于另立项目。
- **ADR-004**：`xmlDict` 替换为 `NameTable`（普通哈希 + GC）。理由：仓颉 GC + 不可变 `String` 使引用计数字典失去意义。
- **ADR-005**：默认安全（禁用外部实体、深度/展开阈值）。理由：规避 libxml2 历史 CVE 模式。
- **ADR-006**：HTML 解析器与 XML 共享词法。理由：减少重复代码；同步修复两边。
- **ADR-007**：RelaxNG 采用 Brzozowski 导数而非 libxml2 的自动机。理由：代码少、证明清晰、易模式匹配。

---

## 20. 与仓颉 SDK 的对齐

- **标准库依赖**：`std.collection`（HashMap/ArrayList）、`std.sync`（Mutex/Atomic）、`std.io`（Stream）、`std.fs`、`std.time`、`std.convert`、`std.unicode`、`std.regex`（仅工具侧，不在核心路径）、`std.ast`（宏）、`std.unittest`（测试）。
- **扩展库**：仅 `tools/` 下可选使用 `stdx.net.http`（下载远程 schema）与 `stdx.encoding.json`（`xmllint` 输出格式化）。
- **工具链**：`cjpm` 做依赖管理与工作区；`cjfmt` 强制格式化；`cjlint` 与 `cangjie-regulations` 对齐；`cjcov` 做覆盖率；`cjprof` 做热点分析。

---

## 21. 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| XML Schema 规模大（libxml2 28k 行） | 分两步：先过 XML TestSuite 的 minimal 子集，再扩 XSD，用 Schema-for-Schemas 做自举测试 |
| XPath 求值性能 | 编译期常量折叠 + NodeSet 惰性 + 文档序索引 |
| 多字节编码缺失 | 以接口开放；初版明确不支持 GB18030 等，必要时由使用者注入 |
| 黄金对比差异（空白处理、编码声明顺序） | 建"规范化比较器"：序列化 → parse → 再序列化，比较语义等价而非字节等价 |
| libxml2 历史怪兽 API（deprecated 字段） | 直接不复刻；给迁移指南 |

---

## 22. 交付物

最终交付（见 ROADMAP 分期）：

1. 本设计文档（`DESIGN.md`）与渐进计划（`ROADMAP.md`）。
2. `cjpm` 工作区的多个包源码 + 单测 + 黄金测试。
3. CLI 工具 `xmllint`（仓颉可执行）。
4. `README.md` 快速上手；`docs/` 里按模块的 API 参考（通过仓颉 doc 生成）。
5. 与 libxml2 v2.15.3 功能对照表（作为独立文档，列出支持/不支持项）。

---

_本文件遵循 `cangjie-regulations` 中的项目结构、命名与文档规范；任何重大架构变更须补充 ADR 并在本文件 §19 追加记录。_
