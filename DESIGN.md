# CangjieXML 软件设计文档

> 基于仓颉（Cangjie）编程语言对 [tinyxml2 v11.0.0](./.tinyxml2-11.0.0) 进行现代化重构与优化复刻。
> 目标：在保留 tinyxml2 功能完备性（XML 1.0 子集、DOM、打印器、访问者、句柄、错误报告）的前提下，
> 用仓颉的现代语言特性（enum + 模式匹配、扩展、泛型、Option、try/catch、并发、宏、属性等）
> 设计一套**类型安全、表达力强、并发友好、符合仓颉编码规范**的全新 API 与内部架构——而不是对 C++ 源码做机械翻译。

---

## 1. 概述

### 1.1 目标与非目标

**目标**
1. 功能对齐 tinyxml2 v11.0.0：解析、构建、修改、查询、打印 XML 文档；支持元素、属性、文本、CDATA、注释、声明、未知节点、Doctype(作为 Unknown) 等。
2. 遵循 XML 1.0 规范的 tinyxml2 子集（与 tinyxml2 保持相同的"不做"列表：DTD、XSchema、XPath、命名空间语义处理等）。
3. 提供**纯仓颉**实现，零 C/C++ 互操作，仅依赖仓颉标准库（`std.*`）与可选的扩展标准库（`stdx.*`）。
4. 重新设计 API：以**不可变值语义优先、错误即值、组合优于继承、迭代器/模式匹配驱动遍历**为核心，提供比 C++ 版本更友好的使用体验。
5. 提供线程安全的解析 API 与可选并发解析/序列化能力。

**非目标**
1. 不实现 DTD 校验、Schema 校验、XPath、XSLT、命名空间解析。
2. 不追求与 C++ 二进制 ABI/源码 API 完全一致；不追求与 `char*` 指针语义等价的 API。
3. 不使用 FFI/CFFI，不链接 C 库；不使用任何非仓颉标准库以外的三方库（stdx 仅在必要场景使用，如 `stdx.encoding.json` 等**本项目不启用**，日志使用 `std` 即可）。

### 1.2 设计原则

| 原则 | 说明 |
|------|------|
| **值语义优先** | 节点的不透明句柄使用引用类型（class），但对外暴露只读视图尽量以不可变值形式传递；构建/修改通过 builder 或显式 mutable API。 |
| **错误即值** | 解析/查询错误用 `Result<T, XmlError>` 或仓颉原生 `Option<T>` 表达，仅在**不可恢复**情况下抛异常（`XmlException`）。 |
| **enum + 模式匹配** | 节点种类用 enum 代数数据类型（ADT）承载，遍历与判别依赖 `match`，彻底摆脱 C++ 的 `dynamic_cast`/`ToElement()` 风格。 |
| **扩展代替膨胀** | C++ 把 `IntAttribute/DoubleAttribute/...` 全塞进 `XMLElement`。仓颉版用 `extend` 在独立包里提供类型化查询，核心类保持精简。 |
| **迭代器驱动遍历** | 子节点/属性/后代遍历全部实现 `Iterable<T>`，用 `for (x in node.children())` 代替手动 `FirstChild/NextSibling` 循环。 |
| **零拷贝解析** | 解析阶段以 `Array<Byte>`（或 `String` 的 UTF-8 视图）+ 偏移区间作为 Token，最终在构建 DOM 时才物化为 `String`。 |
| **线程安全** | `XmlDocument` 解析过程完全无共享可变状态；只读 DOM 可在多线程中共享；修改 DOM 由用户负责同步，必要处提供 `synchronized` 辅助。 |
| **用户体验优先** | 提供 `|>` 管道、尾随 lambda、命名参数、`?.`/`??`、字符串字面量构造等仓颉友好写法。 |

### 1.3 关键用户体验预览

```cangjie
import cangjie_xml.*

main() {
    // 解析
    let doc = XmlDocument.parse(
        """<?xml version="1.0" encoding="UTF-8"?>
           <config version="2">
               <item id="1">hello</item>
               <item id="2"><![CDATA[<raw>]]></item>
           </config>"""
    ).getOrThrow()

    // 迭代 + 模式匹配
    for (node in doc.root().children()) {
        match (node) {
            case Element(e) where e.name == "item" =>
                let id = e.attr("id").toIntOrDefault(0)
                println("item ${id} = ${e.innerText()}")
            case _ => ()
        }
    }

    // 构建 + 链式 API
    let out = XmlDocument.builder()
        .declaration(version: "1.0", encoding: "UTF-8")
        .element("root") { r =>
            r.element("name") { it.text("Cangjie") }
            r.element("year") { it.text(2026) }   // 整型经扩展自动转字符串
        }
        .build()

    // 序列化
    println(out.toString(compact: false))
}
```

---

## 2. tinyxml2 的系统分析

### 2.1 文件 & 规模

| 文件 | 行数 | 内容 |
|------|------|------|
| `tinyxml2.h` | ~2383 | 全部公共 API、内部辅助类声明 |
| `tinyxml2.cpp` | ~3019 | 解析器、打印器、内存池、类型转换实现 |
| `xmltest.cpp` | ~2772 | 功能/回归测试（一个大 `main`） |

### 2.2 关键抽象（C++ → 仓颉对应）

| tinyxml2 类/枚举 | 职责 | 仓颉中的对应 |
|---|---|---|
| `StrPair` | 字符串起止指针 + entity 处理标志，支持零拷贝"借用"和解码为"拥有"字符串 | 内部用 `Slice`(结构体: `data: Array<Byte>, start: Int64, end: Int64, flags: UInt8`) + `toString()` 物化；对外不暴露 |
| `DynArray<T,INIT>` | 模板小容量内联数组 | 直接用 `ArrayList<T>`（`std.collection`）；内联优化不做 |
| `MemPool` / `MemPoolT<SIZE>` | 定长对象池以加速分配 | **删除**。仓颉使用 GC，无需手动池化；如必要，内部用 `ArrayList` 聚合节点所有权 |
| `XMLNode`（抽象基类） | 父/子/兄弟指针、`Value`、virtual `Accept/ShallowClone/ShallowEqual` | 设计为 `sealed interface XmlNode` + 枚举 `XmlNodeKind`；节点对象由 `Document` 持有，统一用 `class` 承载可变性，但遍历时用 `XmlNodeKind` 做模式匹配 |
| `XMLElement` / `XMLText` / `XMLComment` / `XMLDeclaration` / `XMLUnknown` / `XMLDocument` | 具体节点类型 | 对应 `XmlElement` / `XmlText` / `XmlComment` / `XmlDeclaration` / `XmlUnknown` / `XmlDocument`（类），并作为 `XmlNodeKind` 枚举的构造器参数 |
| `XMLAttribute` | 单向链表的属性 | `XmlAttribute`（class），`XmlElement` 内部用 `ArrayList<XmlAttribute>`（保持插入顺序，哈希索引加速按名查询） |
| `XMLHandle` / `XMLConstHandle` | 空安全导航 | **删除**。仓颉 `?.` + `Option<T>` 天然实现安全导航 |
| `XMLVisitor` | 访问者模式遍历 | `interface XmlVisitor`，默认方法通过 `interface` 默认实现提供；另外提供 `node.walk { ... }` 高阶函数替代方案 |
| `XMLPrinter` | 串行化（内存 or FILE*） | `XmlPrinter`（class）：支持写入 `OutputStream`/`String` 缓冲；另配一个函数式 `xml.toString()` 便捷入口 |
| `XMLUtil` | UTF-8、数值↔字符串互转、空白跳过 | 拆到内部 `util` 子包：`Utf8`, `NumberFormat`, `Ws`；不对外导出 |
| `XMLError` | 错误码 enum | 仓颉 `enum XmlError`（含位置、消息等字段的构造器） |
| `Whitespace` | 空白处理策略 | `enum WhitespaceMode { Preserve \| Collapse \| Pedantic }` |
| `XML_MAX_ELEMENT_DEPTH = 500` | 栈溢出保护 | `const` 全局 `MAX_ELEMENT_DEPTH: Int64 = 500`，可通过 `ParseOptions` 覆盖 |

### 2.3 解析流程（tinyxml2 的实际做法）

1. 读入整段字节（或 `FILE*` 全量读入）。
2. 识别 BOM → 规范化换行（`\r\n` / `\r` → `\n`）。
3. **in-place 解析**：直接在输入缓冲区上原地解码实体（`&amp;` 等），通过指针对原始数据切片。
4. 递归下降构造 DOM：`ParseDeep` 处理 `<tag ...>`、文本、注释、CDATA、声明、Unknown(`<! ...>` / `<? ... ?>` 除 xml 声明外)。
5. 错误时设置 `_errorID` + 行号 + 附加字符串。

### 2.4 序列化流程

- `XMLPrinter` 继承 `XMLVisitor`，用 DFS 遍历 DOM。
- 维护 `_depth`、`_elementJustOpened` 状态；支持"紧凑模式"与自动缩进。
- 文本内容按需转义 `& < > " '`。
- 属性值同理。

### 2.5 测试与基准

- `xmltest.cpp` 覆盖：解析/错误码/BOM/空白模式/属性类型查询/CDATA/打印/深度限制/XPath-like handle/回归用例。
- `test/resources/` 放置样例 XML（如 `dream.xml`, `utf8test.xml`）。
- `docs/dox` 是文档配置。

---

## 3. 仓颉侧总体架构

### 3.1 包（Package）结构

采用仓颉标准工程结构，使用 `cjpm` 管理。

```
CangjieXML/                        # 项目根
├─ cjpm.toml                       # 项目清单，module = "cangjie_xml"
├─ src/
│   ├─ cangjie_xml/                # 对外根包 (package cangjie_xml)
│   │   ├─ lib.cj                  # public import 重导出所有公共 API
│   │   └─ prelude.cj              # 常量、通用 type aliases
│   ├─ cangjie_xml/model/          # DOM 数据模型
│   │   ├─ node.cj                 # XmlNodeKind / XmlNode / 基类 AbstractNode
│   │   ├─ element.cj              # XmlElement
│   │   ├─ attribute.cj            # XmlAttribute
│   │   ├─ text.cj                 # XmlText (含 CDATA 标志)
│   │   ├─ comment.cj              # XmlComment
│   │   ├─ declaration.cj          # XmlDeclaration
│   │   ├─ unknown.cj              # XmlUnknown
│   │   └─ document.cj             # XmlDocument（DOM 根 + 上下文）
│   ├─ cangjie_xml/parse/          # 解析器
│   │   ├─ options.cj              # ParseOptions (whitespace/processEntities/maxDepth…)
│   │   ├─ source.cj               # 输入源抽象 (String / Array<Byte> / InputStream)
│   │   ├─ lexer.cj                # Token 识别（零拷贝 slice）
│   │   ├─ parser.cj               # 递归下降构建 DOM
│   │   └─ entity.cj               # 预定义实体 & 字符引用解码
│   ├─ cangjie_xml/print/          # 序列化
│   │   ├─ printer.cj              # XmlPrinter（写入 Output）
│   │   ├─ format.cj               # 缩进/紧凑/自闭合策略
│   │   └─ escape.cj               # 文本/属性转义
│   ├─ cangjie_xml/query/          # 查询与类型化访问（扩展）
│   │   ├─ element_attr_ext.cj     # extend XmlElement { intAttr/boolAttr/... }
│   │   ├─ element_text_ext.cj     # extend XmlElement { innerText/setText/... }
│   │   ├─ iteration.cj            # children()/descendants()/siblings() 迭代器
│   │   └─ find.cj                 # findFirst / findAll / by tag name
│   ├─ cangjie_xml/build/          # 构建器
│   │   ├─ document_builder.cj     # XmlDocument.builder()
│   │   └─ element_builder.cj      # 链式 element { }
│   ├─ cangjie_xml/visitor/        # 访问者
│   │   └─ visitor.cj              # XmlVisitor interface + walk()
│   ├─ cangjie_xml/io/             # IO 适配
│   │   ├─ loader.cj               # loadFile / loadString / loadBytes
│   │   └─ writer.cj               # saveFile / saveString
│   ├─ cangjie_xml/errors/         # 错误模型
│   │   └─ error.cj                # XmlError enum, XmlException, Result<T>
│   └─ cangjie_xml/util/           # 内部工具（非 public）
│       ├─ utf8.cj                 # UTF-8 校验、解码
│       ├─ number.cj               # 数值↔字符串（Int/UInt/Int64/UInt64/Bool/Float/Double）
│       └─ ws.cj                   # 空白字符判断 / 换行规范化
├─ tests/                          # 单元测试（cjpm test，使用 std.unittest）
│   ├─ parse_test.cj
│   ├─ print_test.cj
│   ├─ query_test.cj
│   ├─ builder_test.cj
│   ├─ visitor_test.cj
│   └─ concurrent_test.cj
├─ resources/                      # 测试样例 XML（部分拷贝自 tinyxml2/test/resources）
├─ examples/                       # 使用样例（可独立 cjpm run）
├─ DESIGN.md                       # 本文件
├─ ROADMAP.md                      # 渐进开发计划
└─ README.md
```

### 3.2 层次依赖

```
io ─┐
    ▼
parse ──▶ model ◀── build
    ▲       ▲
    │       │
  errors  util     query (extend model)
               ▲
            print ──▶ visitor
```

- `model` 无外部依赖，提供中立的数据结构。
- `parse` 依赖 `model`、`errors`、`util`。
- `print` 依赖 `model`、`visitor`、`util`。
- `query` 通过 `extend` 给 `model` 增加语法糖 API，**不改变 model 源码**，保证核心包精简。
- `io` 只做"字节 ↔ `String`/`Array<Byte>`"适配，不包含语法知识。

---

## 4. 核心类型设计

### 4.1 DOM 数据模型

#### 4.1.1 `XmlNodeKind`：节点分类枚举（模式匹配主入口）

```cangjie
public enum XmlNodeKind {
    | Element(XmlElement)
    | Text(XmlText)
    | Comment(XmlComment)
    | Declaration(XmlDeclaration)
    | Unknown(XmlUnknown)
    | Document(XmlDocument)
}
```

用户永远通过 `XmlNodeKind` 做分支，不需要 `dynamic_cast`：

```cangjie
match (node.kind()) {
    case Element(e) => visit(e)
    case Text(t)    => sink.append(t.value)
    case _          => ()
}
```

#### 4.1.2 `interface XmlNode`：统一导航能力

```cangjie
public sealed interface XmlNode {
    prop parent: Option<XmlElement>
    prop document: XmlDocument
    prop firstChild: Option<XmlNode>
    prop lastChild: Option<XmlNode>
    prop previousSibling: Option<XmlNode>
    prop nextSibling: Option<XmlNode>
    func kind(): XmlNodeKind
    func accept(v: XmlVisitor): Bool
    func shallowClone(targetDoc!: Option<XmlDocument> = None): XmlNode
    func shallowEqual(other: XmlNode): Bool
}
```

- `sealed`：只允许本模块内实现 → 编译期模式匹配穷举性由 `XmlNodeKind` 保证。
- 属性 `parent/document/...` 用 `prop` 暴露，禁止外部直接赋值；修改必须经过 `XmlElement` 的方法。
- `Option<XmlNode>` 替代 C++ 空指针。

#### 4.1.3 `XmlElement`

```cangjie
public class XmlElement <: XmlNode {
    public var name: String
    // 属性保持插入顺序；按名查询走哈希索引
    private let _attrs: ArrayList<XmlAttribute>
    private let _attrIndex: HashMap<String, Int64>
    private let _children: /* 双向链表节点：见 4.1.5 */ ...

    public init(name: String)

    // 属性 API（精简核心）
    public func attr(name: String): Option<String>
    public func setAttr(name: String, value: String): Unit
    public func removeAttr(name: String): Bool
    public func attributes(): Iterable<XmlAttribute>

    // 子节点 API
    public func append(node: XmlNode): Unit
    public func prepend(node: XmlNode): Unit
    public func insertBefore(ref_: XmlNode, node: XmlNode): Unit
    public func remove(node: XmlNode): Bool
    public func children(): Iterable<XmlNode>
    public func elements(): Iterable<XmlElement>             // 只筛元素
    public func element(name: String): Option<XmlElement>    // 第一个匹配
    public func elements(name: String): Iterable<XmlElement> // 全部匹配

    // 文本
    public func innerText(): String        // 拼接直接子 Text 节点
    public func setInnerText(text: String): Unit
}
```

说明：
- `name: String` 直接暴露 `var`：**简化模型**，改名就是改名；内部在 `appendChild` 之前做 XML Name 合法性校验（由扩展提供的 setter 替身可改成 throw）。
- 属性查询/增删的 `Bool`/`Option` 风格取代 C++ 的 `Attribute(name, value)` 两用签名歧义。
- 类型化属性访问（`intAttr`、`queryInt` 等）**不**放在核心类里，见 §4.4。

#### 4.1.4 `XmlAttribute`

```cangjie
public class XmlAttribute {
    public var name: String
    public var value: String
    public prop lineNumber: Int64
    // 属性链表指针对用户隐藏；迭代器通过 XmlElement.attributes() 提供
}
```

C++ 中 `XMLAttribute` 既是"节点值"又是"链表元素"，仓颉里拆分为纯数据 + 由 `XmlElement` 持有的容器，消除隐式状态。

#### 4.1.5 子节点存储

tinyxml2 用双向链表（head/tail 指针 + 每个节点的 prev/next）。仓颉里保留双向链表，但以**私有类型**承载：

```cangjie
class ChildList {
    var head: Option<AbstractNode>
    var tail: Option<AbstractNode>
    var size: Int64
    // append / prepend / insertBefore / remove
    // 迭代器：实现 Iterable<XmlNode>
}

abstract class AbstractNode <: XmlNode {
    var prev: Option<AbstractNode>
    var next: Option<AbstractNode>
    var parent_: Option<XmlElement>
    var document_: XmlDocument
    // 默认 parent/document/... 实现
}
```

选择链表而非 `ArrayList` 的理由：插入/删除 O(1)、与 tinyxml2 行为一致、节点持有者确定（方便 `remove(node)` O(1)）。

#### 4.1.6 `XmlText`（含 CDATA）

```cangjie
public class XmlText <: XmlNode {
    public var value: String
    public var cdata: Bool      // 打印时决定是否包在 <![CDATA[...]]> 里
    public init(value!: String, cdata!: Bool = false)
}
```

#### 4.1.7 `XmlDocument`

```cangjie
public class XmlDocument <: XmlNode {
    public let options: ParseOptions
    public prop hasBom: Bool
    public var writeBom: Bool
    public prop error: Option<XmlError>

    // 工厂（替代 NewElement / NewText / NewComment / ...）
    public func createElement(name: String): XmlElement
    public func createText(value: String, cdata!: Bool = false): XmlText
    public func createComment(text: String): XmlComment
    public func createDeclaration(text!: Option<String> = None): XmlDeclaration
    public func createUnknown(text: String): XmlUnknown

    // 根元素
    public func root(): Option<XmlElement>

    // 静态入口
    public static func parse(input: String, options!: ParseOptions = ParseOptions.default()): Result<XmlDocument, XmlError>
    public static func parseBytes(bytes: Array<Byte>, options!: ParseOptions = ParseOptions.default()): Result<XmlDocument, XmlError>
    public static func loadFile(path: String, options!: ParseOptions = ParseOptions.default()): Result<XmlDocument, XmlError>
    public static func builder(): XmlDocumentBuilder

    // 序列化
    public func toString(compact!: Bool = false): String
    public func writeTo(out: OutputStream, compact!: Bool = false): Unit
    public func saveFile(path: String, compact!: Bool = false): Result<Unit, XmlError>
}
```

**关键差异**：仓颉下**没有**"document owns memory" 概念——所有节点由 GC 管理；`XmlDocument` 仍然保留，以承担解析上下文（选项、错误、BOM 标志）和作为所有节点的统一入口/根容器。

### 4.2 错误模型

```cangjie
public enum XmlError {
    | NoAttribute(name: String, at: SourcePos)
    | WrongAttributeType(name: String, expected: String, got: String, at: SourcePos)
    | FileNotFound(path: String)
    | FileReadError(path: String, cause: String)
    | FileWriteError(path: String, cause: String)
    | ParsingElement(at: SourcePos, msg: String)
    | ParsingAttribute(at: SourcePos, msg: String)
    | ParsingText(at: SourcePos, msg: String)
    | ParsingCData(at: SourcePos, msg: String)
    | ParsingComment(at: SourcePos, msg: String)
    | ParsingDeclaration(at: SourcePos, msg: String)
    | ParsingUnknown(at: SourcePos, msg: String)
    | EmptyDocument
    | MismatchedElement(opened: String, closed: String, at: SourcePos)
    | Parsing(at: SourcePos, msg: String)
    | CanNotConvertText(at: SourcePos)
    | NoTextNode(at: SourcePos)
    | ElementDepthExceeded(limit: Int64, at: SourcePos)
}

public struct SourcePos {
    public let line: Int64
    public let column: Int64
    public let offset: Int64
}

public class XmlException <: Exception {
    public let error: XmlError
    public init(error: XmlError)
}

public type Result<T, E> = ... // 别名，或直接使用 std.* 中等效类型
```

- 纯函数式 API（`parse`, `query ...`）返回 `Result<T, XmlError>`，也可用 `?`/`??`/`getOrThrow()` 风格消费。
- 不可恢复的误用（例如把一个 Document 节点当成 Element 插入另一个 Document）抛 `XmlException`。
- `XmlError` 作为 enum **带上下文字段**（源位置、期望/实际类型、路径），比 C++ 的单一 `XMLError` 枚举信息量大得多。

### 4.3 访问者 & 高阶遍历

#### 4.3.1 `interface XmlVisitor`

```cangjie
public interface XmlVisitor {
    func visitEnter(doc: XmlDocument): Bool { true }
    func visitExit(doc: XmlDocument): Bool { true }
    func visitEnter(el: XmlElement, attrs: Iterable<XmlAttribute>): Bool { true }
    func visitExit(el: XmlElement): Bool { true }
    func visit(n: XmlDeclaration): Bool { true }
    func visit(n: XmlText): Bool { true }
    func visit(n: XmlComment): Bool { true }
    func visit(n: XmlUnknown): Bool { true }
}
```

- 用 `interface` 默认实现取代 C++ 基类虚函数；实现者可只覆盖关心的方法。

#### 4.3.2 高阶遍历（函数式替代）

```cangjie
public func walk(node: XmlNode, visit: (XmlNodeKind) -> WalkControl): Unit

public enum WalkControl { Continue | SkipChildren | Stop }
```

用户可直接写：

```cangjie
walk(doc) { kind => match (kind) {
    case Element(e) where e.name == "link" =>
        urls.append(e.attr("href") ?? ""); WalkControl.Continue
    case _ => WalkControl.Continue
}}
```

### 4.4 扩展（`extend`）：类型化 & 便捷 API

将 C++ 中塞在 `XMLElement` 的 **40+** 个 `IntAttribute/QueryIntAttribute/SetAttribute(int)/…` 重载，迁移到独立扩展包 `cangjie_xml.query`，保持核心 `XmlElement` 简洁。

```cangjie
// element_attr_ext.cj
package cangjie_xml.query
import cangjie_xml.model.*
import cangjie_xml.errors.*

extend XmlElement {
    public func intAttr(name: String, default_!: Int64 = 0): Int64
    public func int64Attr(name: String, default_!: Int64 = 0): Int64
    public func uintAttr(name: String, default_!: UInt64 = 0): UInt64
    public func boolAttr(name: String, default_!: Bool = false): Bool
    public func doubleAttr(name: String, default_!: Float64 = 0.0): Float64
    public func floatAttr(name: String, default_!: Float32 = 0.0): Float32

    public func queryIntAttr(name: String): Result<Int64, XmlError>
    public func queryBoolAttr(name: String): Result<Bool, XmlError>
    // …

    public func setAttr<T>(name: String, value: T): Unit where T <: XmlAttrConvertible
}

public interface XmlAttrConvertible {
    func toXmlString(): String
    static func fromXmlString(s: String): Result<This, XmlError>
}
// 针对 Int64, UInt64, Float64, Bool, String, Rune 等类型提供扩展实现
```

**优势**：
- 扩展让用户**按需导入**类型化 API；极简场景下只依赖 `model` 包，不引入数值解析代码。
- `XmlAttrConvertible` 接口让用户可以给自己的类型（如 `Color`、`Duration`）实现 XML 序列化能力，调用 `el.setAttr("dur", myDuration)` 直接生效。

### 4.5 构建器（Builder）

```cangjie
public class XmlDocumentBuilder {
    public func declaration(version!: String = "1.0", encoding!: String = "UTF-8"): XmlDocumentBuilder
    public func bom(useBom: Bool): XmlDocumentBuilder
    public func element(name: String, build!: (XmlElementBuilder) -> Unit = {_ => ()}): XmlDocumentBuilder
    public func comment(text: String): XmlDocumentBuilder
    public func build(): XmlDocument
}

public class XmlElementBuilder {
    public func attr(name: String, value: String): XmlElementBuilder
    public func attr<T>(name: String, value: T): XmlElementBuilder where T <: XmlAttrConvertible
    public func text(s: String, cdata!: Bool = false): XmlElementBuilder
    public func text<T>(v: T): XmlElementBuilder where T <: XmlAttrConvertible
    public func element(name: String, build!: (XmlElementBuilder) -> Unit = {_ => ()}): XmlElementBuilder
    public func comment(text: String): XmlElementBuilder
}
```

使用尾随 lambda 让链式 DSL 贴近仓颉习惯：

```cangjie
let doc = XmlDocument.builder()
    .declaration()
    .element("catalog") { c =>
        c.element("book") { b =>
            b.attr("id", 1)
             .element("title") { it.text("SICP") }
             .element("year")  { it.text(1985) }
        }
    }
    .build()
```

### 4.6 迭代器

在 `query.iteration` 中提供：

- `children()` / `reverseChildren()`
- `elements()` / `elements(name: String)`
- `descendants()`（深度优先）
- `ancestors()`
- `siblings()`

实现思路：返回 `struct` 迭代器，实现 `Iterator<XmlNode>`（或 `Iterator<XmlElement>`），以 `for-in` 直接消费。对非无限流使用惰性求值，不预拷贝整个列表。

---

## 5. 解析器设计

### 5.1 输入抽象

```cangjie
public enum XmlSource {
    | Text(String)
    | Bytes(Array<Byte>)
    | Stream(InputStream)   // 会一次性 drain 到 Bytes（tinyxml2 行为一致）
}
```

- BOM 处理：识别 UTF-8 BOM（`EF BB BF`），记入 `XmlDocument.hasBom`；其它编码 BOM（UTF-16/32）本阶段不支持，返回 `ParsingElement`（或日后扩展为 `UnsupportedEncoding`）。
- 行尾规范化：`\r\n` / `\r` → `\n`（与 tinyxml2 一致）。
- 为了追踪源位置，规范化阶段同时构建**行偏移表**（稀疏采样），由 `SourcePos` 反查。

### 5.2 Lexer（零拷贝）

```cangjie
struct Slice {
    let data: Array<Byte>
    let start: Int64
    let endIx: Int64
}

enum Token {
    | TagOpen(Slice)          // <
    | TagClose                // >
    | TagSelfClose            // />
    | TagEndOpen              // </
    | Name(Slice)
    | Eq                      // =
    | Quote(Rune)             // ' or "
    | StringLit(Slice)        // 原始属性值（未解码实体）
    | TextSpan(Slice)
    | CDataSpan(Slice)
    | CommentSpan(Slice)      // 不含 <!-- -->
    | PiSpan(Slice)           // <? ... ?>
    | DeclSpan(Slice)         // <?xml ... ?>
    | DoctypeSpan(Slice)      // <!DOCTYPE ...>
    | Eof
}
```

Lexer 是**按需前进的状态机**：不预 tokenize 整个文档，解析器驱动 lexer 推进。

### 5.3 Parser：递归下降 + 深度限制

```cangjie
func parseDocument(src: Slice, opts: ParseOptions): Result<XmlDocument, XmlError>
func parseNode(ctx: ParseCtx, depth: Int64): Result<XmlNode, XmlError>
func parseElement(ctx: ParseCtx, depth: Int64): Result<XmlElement, XmlError>
func parseAttributes(ctx: ParseCtx): Result<ArrayList<XmlAttribute>, XmlError>
```

- 使用 `try`/`catch` 在解析边界统一捕获；深内部用 `Result` 早退。
- `depth > opts.maxDepth` → `ElementDepthExceeded`。
- 实体解码在"从 Slice 物化为 String"时完成；预定义实体 `&lt; &gt; &amp; &apos; &quot;`，加 `&#NNN;` / `&#xNN;` 字符引用。
- `ParseOptions.processEntities = false` 时保持原样。

### 5.4 空白模式（Whitespace）

```cangjie
public enum WhitespaceMode {
    | Preserve       // 保留所有空白文本节点（默认）
    | Collapse       // 连续空白合并为 1 个空格，纯空白节点丢弃
    | Pedantic       // 保留所有空白，但保持换行和原始格式（与 tinyxml2 PEDANTIC_WHITESPACE 语义一致）
}
```

### 5.5 并发解析策略

- **默认**：解析单个文档是单线程的；CPU 密集型，加 goroutine 风格并发意义不大。
- **多文档并发**：提供 `XmlDocument.parseMany(inputs: Array<XmlSource>)`，内部用 `spawn` + `Future` 并行解析，通过 `ArrayList<Future<Result<XmlDocument, XmlError>>>` 聚合结果。
- **超大文档（>10MB）分片**：可选的 "chunked parse"——在栈顶元素级别切分工作（实验性，不在 v1.0 必做项）。
- **线程安全**：解析器内部**无共享可变状态**，`ParseCtx` 是栈局部的；输入 `Array<Byte>` 只读；只要各解析任务使用不同的 `Array<Byte>` 就天然安全。

### 5.6 错误恢复

与 tinyxml2 一致——**首错即止**：记录错误并返回 `Err(XmlError)`，不尝试容错解析。错误包含 `SourcePos`（行/列/偏移）和人类可读消息。

---

## 6. 序列化器设计

### 6.1 输出抽象

```cangjie
public interface XmlOutput {
    func write(s: String): Unit
    func writeByte(b: Byte): Unit
    func flush(): Unit
}
// 内置实现
public class StringOutput <: XmlOutput      // 写到内部 StringBuilder
public class StreamOutput <: XmlOutput      // 包裹 std.io.OutputStream
public class FileOutput   <: XmlOutput      // 便捷：按路径打开
```

### 6.2 `XmlPrinter`

```cangjie
public class XmlPrinter <: XmlVisitor {
    public init(out: XmlOutput, compact!: Bool = false, indent!: String = "    ")

    // 流式：无需先构建 DOM
    public func pushHeader(writeBom!: Bool = false, writeDeclaration!: Bool = true): Unit
    public func openElement(name: String): XmlPrinter
    public func pushAttribute(name: String, value: String): XmlPrinter
    public func pushAttribute<T>(name: String, value: T): XmlPrinter where T <: XmlAttrConvertible
    public func pushText(text: String, cdata!: Bool = false): XmlPrinter
    public func pushComment(text: String): XmlPrinter
    public func pushDeclaration(text: String): XmlPrinter
    public func pushUnknown(text: String): XmlPrinter
    public func closeElement(): XmlPrinter

    // 访问者接口：供 XmlDocument.writeTo 调用
    public override func visitEnter(...): Bool
    // …
}
```

- 支持"**不需要 Document** 的流式输出"（对齐 tinyxml2 用法）。
- `compact = true` 时，不插入缩进和换行。
- 空元素输出 `<tag/>`（与 tinyxml2 默认一致）。

### 6.3 转义

- 文本内转义 `& < >`；属性值内转义 `& < > "` 或 `& < > '`（取决于所用引号，默认双引号）。
- CDATA 段内不做转义，但拒绝包含 `]]>`（序列化时报错/自动切分 —— v1.0 选择"拒绝并抛 `XmlException`"，安全优先）。

---

## 7. 测试策略

### 7.1 分层

| 层 | 工具 | 目标 |
|---|---|---|
| 单元 | `std.unittest` | 词法/解析/DOM/扩展/错误路径 |
| 黄金文件 | `std.unittest` + `resources/*.xml` | 从 tinyxml2 `test/resources` 移植；parse→print→parse 幂等 |
| 差异 | 自研脚本（cjpm run） | 用同一份输入同时喂给 **本库 + tinyxml2 可执行样例（离线预生成的参考输出）**，对比结果 |
| 并发 | `std.unittest` | 多线程 `parseMany`、只读共享 DOM 的并发访问 |
| 性能基准 | `cjprof` | 记录解析吞吐、峰值内存，作为回归基线 |
| 模糊 | 简易自研（分阶段） | 随机字节序列不应导致 panic，仅返回 `Err(XmlError)` |

### 7.2 从 tinyxml2 移植的关键用例

至少包含：
- 简单文档 / 空文档 / 只有声明
- 深度 500 / 501（验证 `ElementDepthExceeded`）
- CDATA、注释、PI、DOCTYPE
- UTF-8（`utf8test.xml`）、BOM
- 属性类型化查询（int/uint/int64/uint64/bool/double/float）
- 打印紧凑 / 缩进
- parse→print→parse 幂等
- 错误码分支（`MismatchedElement` / `ParsingAttribute` / `EmptyDocument` …）

---

## 8. 仓颉特性映射一览

| 仓颉特性 | 在本项目中的应用 |
|---|---|
| `enum` + 模式匹配 | `XmlNodeKind`、`XmlError`、`Token`、`WalkControl`、`WhitespaceMode` |
| `sealed interface` | `XmlNode` 穷举子类型，为 `XmlNodeKind` 匹配提供保证 |
| `Option<T>` + `?.` + `??` | 空节点导航（替代 `XMLHandle`） |
| `Result<T, E>` | `parse` / `query*Attr` / 文件 IO 的错误返回 |
| `try` / `catch` / `try-with-resources` | 解析外层 boundary、文件自动关闭 |
| `extend` | 给 `XmlElement` 增加类型化属性访问，保持核心包精简；允许用户为自定义类型实现 `XmlAttrConvertible` |
| 泛型 + where 约束 | `setAttr<T>` / `pushAttribute<T>` / `XmlAttrConvertible` |
| 型变 | `Iterable<XmlNode>` 协变，`elements()` 可作 `Iterable<XmlNode>` 使用 |
| `interface` 默认方法 | `XmlVisitor` 所有方法默认返回 `true` |
| 闭包 + 尾随 lambda | Builder DSL、`walk { ... }`、`element { ... }` |
| 命名参数 + 默认值 | `parse(..., options! = ...)`、`toString(compact! = false)`、`createText(..., cdata! = false)` |
| `synchronized` / `Mutex` | 可选：对共享 DOM 的写锁封装 `XmlDocument.withWriteLock { ... }` |
| `spawn` / `Future` | `XmlDocument.parseMany` |
| `const` / `const init` | `MAX_ELEMENT_DEPTH`、预定义实体表 |
| 宏 / `@Annotation` | 实验性：`@XmlRoot("book") class Book`（v2.0 目标，非 v1.0 范围） |
| 属性 `prop` | 只读字段暴露（`lineNumber`、`parent`、`document`） |
| 运算符重载 | `XmlElement / "child"` 作为便捷子元素查询（可选语法糖，默认不启用以避免困惑） |
| `|>` 管道 | `doc.root().getOrThrow() |> collectLinks` |

---

## 9. 与 tinyxml2 的**不复刻**项与理由

| 被舍弃的 C++ 设计 | 仓颉替代 |
|---|---|
| `MemPool`/`MemPoolT` 对象池 | 依赖仓颉 GC；性能基线若不达标，再在 `model` 内部引入"节点复用池"优化（内部实现细节，不污染 API） |
| `StrPair` 的"内存归属标志"（static / needs free / needs entity decode） | `String` 是不可变值对象；借用/拥有由 `Slice`（内部）和 `String`（对外）的边界区分 |
| `DynArray<T, INIT>` | `ArrayList<T>` |
| `XMLHandle` / `XMLConstHandle` | 原生 `Option<T>` + `?.` |
| `const XMLElement*` ↔ `XMLElement*` 两套重载 | 仓颉无 `const` 传染；由返回 `XmlElement` 类引用 + 方法签名控制可变性 |
| `Attribute(name, value)` 二义重载 | 拆成 `attr(name)` 和 `hasAttr(name, value)` 两个明确函数 |
| `ToElement()/ToText()/…` 全家桶强转 | `match (node.kind()) { case Element(e) => ... }` |
| `XMLError XMLError_COUNT` 哨兵 | 不需要——enum 不会有"数量哨兵" |
| 全局 `SetBoolSerialization` 静态状态 | 改为 `XmlPrinterOptions.boolFormat: (writeTrue: String, writeFalse: String)`，**线程安全** |
| `FILE*` 句柄 | `std.io.OutputStream` / 路径字符串 |

---

## 10. 性能目标与指标

| 指标 | 目标（相对 tinyxml2 单线程） |
|---|---|
| 解析吞吐 | 在不使用原生指针/FFI 前提下，目标 ≥ 60%（MB/s） |
| 序列化吞吐 | 目标 ≥ 70% |
| 峰值内存 | 2 ~ 3× （受 GC + `String` immutable 限制，可接受） |
| 冷启动 | 纯仓颉包，首次解析 < 10 ms（1 KB 文档） |
| `parseMany` 线性扩展比 | 4 线程下 ≥ 3× |

> 性能目标在 v1.0 不作为验收硬门槛，但每个里程碑都会纳入 `cjprof` 基准对比，发现显著回退立即回退。

---

## 11. 安全与健壮性

1. **深度上限**：默认 500（与 tinyxml2 一致），可配置；超出立即 `ElementDepthExceeded`，防止栈溢出。
2. **UTF-8 校验**：解析时对非法字节序列可选择严格报错或放行（由 `ParseOptions.strictUtf8` 控制，默认非严格，与 tinyxml2 对齐）。
3. **实体爆炸**：只支持预定义的 5 个实体 + 字符引用，**不支持用户自定义实体**，天然免疫 XXE / Billion Laughs。
4. **输入尺寸**：`parse` 一次性读入的字节数上限由调用者负责；流式解析不在 v1.0 范围。
5. **线程安全**：
   - 只读 DOM 多线程安全。
   - 写入 DOM 需要调用者同步；可用 `XmlDocument.withWriteLock { doc => ... }` 封装一个 `Mutex`。
6. **文件 IO**：一律使用 `try-with-resources` 自动关闭。

---

## 12. 示例：把 §1.3 的 C++ 风格用法翻译成仓颉

**tinyxml2 C++**
```cpp
XMLDocument doc;
doc.LoadFile("config.xml");
XMLElement* root = doc.RootElement();
for (XMLElement* item = root->FirstChildElement("item");
     item;
     item = item->NextSiblingElement("item")) {
    int id = 0;
    item->QueryIntAttribute("id", &id);
    printf("%d = %s\n", id, item->GetText());
}
```

**CangjieXML**
```cangjie
import cangjie_xml.*

let doc = XmlDocument.loadFile("config.xml").getOrThrow()
let root = doc.root() ?? return
for (item in root.elements("item")) {
    let id = item.intAttr("id")
    println("${id} = ${item.innerText()}")
}
```

差异：无裸指针、无 `&id` 输出参数、无手动兄弟迭代、类型化 API 走扩展、空安全由 `?.`/`??` 处理。

---

## 13. 未决 / 后续扩展点

- **v1.1**：`@XmlRoot/@XmlAttr/@XmlElement` 宏 + 反射，提供 POCO ↔ XML 的 ORM 风格映射。
- **v1.2**：流式解析器（SAX 风格 `Iterator<XmlEvent>`），适合大文件。
- **v1.3**：可选的 `XPath` 子集（`//tag[@attr='x']`）。
- **v1.4**：与 `stdx.serialization` 对接（若仓颉生态提供统一序列化接口）。
