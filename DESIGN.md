# CangjieXML 软件设计文档

> 本文面向仓颉语言，系统分析 `.tinyxml2-11.0.0` 的功能边界与工程经验，给出一套更符合仓颉语言气质的 XML 库设计方案。
>
> 这不是把 tinyxml2 从 C++ 逐行翻译到仓颉，而是要在保持 XML 语义、DOM 能力与 tinyxml2 实用主义优势的前提下，借助仓颉的 `enum`、模式匹配、`Option`、扩展、泛型与并发能力，以及规范化包结构，设计一套 **结构清晰、命名优雅、职责对称、可渐进实现** 的纯仓颉 XML 库。

---

## 1. 文档目标

本文回答四个问题：

1. **tinyxml2 到底由哪些能力构成？**
2. **哪些能力应当继承，哪些设计应当舍弃？**
3. **仓颉版本的公共 API、包结构、内部边界应当怎样更合理？**
4. **如何在不透支复杂度的前提下，分阶段把设计落成实现？**

本文与 [`ROADMAP.md`](./ROADMAP.md) 配套：`DESIGN.md` 解决“**做成什么样**”，`ROADMAP.md` 解决“**按什么节奏做出来**”。

---

## 2. 设计立场

### 2.1 北极星目标

CangjieXML 的设计以五个目标为最高优先级：

1. **语义正确**：遵循 XML 1.0 与 tinyxml2 已定义的功能边界。
2. **接口自然**：API 要像仓颉库，而不是 C++ 库的投影。
3. **结构优雅**：模块、类型、文件、命名形成对称关系，便于长期维护。
4. **实现务实**：v1.0 不追求宏大特性，优先把 DOM / Parser / Writer 做扎实。
5. **渐进演化**：未来要能继续演进到流式解析、宏绑定与更强查询能力，而不推翻核心结构。

### 2.2 非目标

以下内容不纳入 v1.x 核心范围：

- DTD 校验、XML Schema 校验、XSLT。
- 完整 XPath / XQuery。
- 命名空间语义推理（仅保留原始名称字符串，不做前缀绑定解析）。
- 与 C / C++ / Java / Rust 等语言互操作。
- 机械复刻 tinyxml2 的内存池、裸指针、`FILE*`、句柄类等历史遗留 API。

### 2.3 设计原则

| 原则 | 说明 |
|---|---|
| **语义承继，接口重构** | 继承 tinyxml2 的能力边界与错误意识，但在仓颉中重做 API 形态。 |
| **核心简洁，能力外扩** | DOM 核心只保留最基本、最稳定的能力；类型化查询、DSL、批量并发等通过扩展层提供。 |
| **命名先行** | 先统一术语与命名，再设计层次和类型，避免 API 后期失去美感与一致性。 |
| **公共接口完整词，DSL 再短名** | 核心 API 使用完整单词，如 `attribute` / `setAttribute`；简写只在 DSL 或扩展层中提供。 |
| **组合优于继承** | 访问者、查询器、构建器、批量解析器都作为独立能力层，不让 `XmlDocument` 变成巨型上帝对象。 |
| **错误显式** | `Option` 表达“可能不存在”，`Result` 表达“可能失败”，异常只用于 API 误用或不可恢复错误。 |
| **并发可选而非内建** | DOM 模型本身保持朴素；并发能力通过独立工具层接入，不让所有对象都背上锁与状态负担。 |

---

## 3. tinyxml2 系统分析

### 3.1 源码构成

`.tinyxml2-11.0.0` 主要由三部分组成：

| 文件 | 规模 | 作用 |
|---|---:|---|
| `tinyxml2.h` | ~2383 行 | 公共 API、内部辅助类型声明 |
| `tinyxml2.cpp` | ~3019 行 | 解析、打印、工具函数、内存管理实现 |
| `xmltest.cpp` | ~2772 行 | 功能测试、回归测试与行为样例 |

这个结构非常典型：**一个头文件 + 一个实现文件 + 一个大测试文件**。优点是集成简单，缺点是职责高度耦合、公共 API 与内部机制交织在一起，不适合直接搬到仓颉。

### 3.2 tinyxml2 的核心能力

从公共接口与测试用例看，tinyxml2 的能力可以归纳为九类：

1. **DOM**：文档、元素、文本、注释、声明、未知节点、属性。
2. **解析**：从字符串、字节流、文件中读取 XML。
3. **序列化**：以紧凑或格式化形式输出 XML。
4. **类型化属性访问**：`IntAttribute` / `BoolAttribute` / `QueryXxxAttribute` 等。
5. **访问者遍历**：`XMLVisitor` + `Accept()`。
6. **安全导航**：`XMLHandle` / `XMLConstHandle`。
7. **错误报告**：错误码、行号、附加文本。
8. **空白策略**：保留、折叠、严格保留三种模式。
9. **工程性保护**：最大元素深度、防止栈溢出。

### 3.3 tinyxml2 的优点

值得继承的经验主要有：

- **功能边界克制**：只做 DOM 与基础读写，不把自己扩展为“XML 全家桶”。
- **错误意识强**：对不匹配标签、属性类型错误、文档深度等都有明确处理。
- **性能务实**：大量基于原地解析与零拷贝思想。
- **API 实用**：大量便捷函数降低使用门槛。

### 3.4 tinyxml2 在仓颉中不宜直接继承的部分

下列设计是 C++ 语境下的合理折中，但在仓颉中应主动放弃：

| C++ 设计 | tinyxml2 中的意义 | 仓颉中的问题 | CangjieXML 的处理 |
|---|---|---|---|
| `StrPair` | 指针切片 + 所有权标志 + 实体解码状态 | 侵入性强、暴露底层内存模型 | 仅在 `internal` 层保留 `Slice` / `NormalizedBuffer` 之类内部结构 |
| `MemPool` / `MemPoolT` | 避免频繁 `new/delete` | GC 语言中不应把手工池化放到 v1 核心 | v1 删除；性能瓶颈出现后再做内部优化 |
| `DynArray<T, INIT>` | 小容量数组优化 | 会污染设计关注点 | 直接使用标准库集合 |
| `XMLHandle` | 弱化空指针风险 | 仓颉已有 `Option` / `?.` / `??` | 删除 |
| `ToElement()/ToText()` | 运行时向下转型 | 不够优雅，也不符合模式匹配风格 | 由 `XmlNodeKind` + `match` 替代 |
| `FILE*` | 兼容 C 运行时 | 不符合仓颉 IO 习惯 | 使用路径字符串与 `OutputStream` |
| 全局静态状态 | 例如布尔序列化设置 | 线程安全差，语义漂移 | 移入 `XmlWriteOptions` |

### 3.5 tinyxml2 的可迁移抽象

尽管实现风格需要重构，但以下抽象非常值得迁移：

- 文档树（Document / Element / Text / Comment / Declaration / Unknown）
- 访问者模式
- 错误类别划分
- 空白模式
- 最大深度保护
- “先读完整文档，再构建 DOM”的简单工作流

### 3.6 对 tinyxml2 的总体判断

**tinyxml2 最值得学习的不是 C++ 技巧，而是它对边界的把握。**

因此，CangjieXML 的策略应当是：

- **保留 tinyxml2 的能力边界与朴素工作流；**
- **抛弃其受 C++ 时代限制的 API 形态与内存技巧；**
- **用仓颉的语言结构，把原本“可用”的设计提升为“好用、好读、好维护”的设计。**

---

## 4. 命名与结构基线

这一节直接吸收仓颉规范（尤其是包结构、命名和职责分层建议），作为整套设计的“美学地基”。

### 4.1 命名约定

| 类别 | 约定 | 示例 |
|---|---|---|
| 模块名 | 小写单词，必要时下划线 | `dom`, `parser`, `writer`, `query` |
| 文件名 | 小写下划线 | `xml_document.cj`, `xml_parse_options.cj` |
| 公共类型 | PascalCase | `XmlDocument`, `XmlNodeKind` |
| 公共函数 | camelCase | `parseString`, `writeToString`, `setAttribute` |
| 常量 | SCREAMING_SNAKE_CASE | `MAX_ELEMENT_DEPTH` |
| 选项类型 | `XmlXxxOptions` | `XmlParseOptions`, `XmlWriteOptions` |
| 编解码协议 | `XmlXxxCodec` | `XmlValueCodec`, `BoolTextCodec` |

### 4.2 术语约定

为保证 API 一致性，本文统一采用以下术语：

| 术语 | 含义 | 备注 |
|---|---|---|
| **DOM** | 内存中的树模型 | 核心层 |
| **Parser** | 解析 XML 输入为 DOM | 读入方向 |
| **Writer** | 把 DOM 或事件输出为 XML | 写出方向 |
| **Query** | 针对 DOM 的高层只读便利 API | 扩展层 |
| **Builder** | 用链式 DSL 构建 DOM | 扩展层 |
| **Visit** | 访问者与高阶遍历 | 访问层 |
| **Codec** | 自定义值与 XML 字符串之间的转换规则 | 可扩展机制 |

### 4.3 结构约束

1. **公共层与内部层分离**：公共 API 放在 `dom / parser / writer / query / build / visit / io / error`；批量与并发扩展可放在 `batch`；内部实现细节放在 `internal`。
2. **模块命名保持对称**：`parser` 与 `writer`，`query` 与 `build`，`visit` 独立于 `dom`。
3. **单数优先**：模块名用单数概念，如 `error` 而不是 `errors`，`visit` 而不是 `visitor`，强调“能力域”而非“对象集合”。
4. **公共类型显式带 `Xml` 前缀**：在多包导入场景下保持可读性和防冲突性。
5. **核心 API 用完整词**：例如 `attribute()` 而不是 `attr()`；如需短名，通过 DSL 或扩展单独提供。

这组约束的目的不是教条，而是让整个库在几年后仍然“看起来像同一个人设计的”。

---

## 5. 总体架构

### 5.1 推荐目录结构

```text
CangjieXML/
├─ cjpm.toml
├─ src/
│  └─ cangjie_xml/
│     ├─ lib.cj
│     ├─ version.cj
│     ├─ error/
│     │  ├─ source_pos.cj
│     │  └─ xml_error.cj
│     ├─ dom/
│     │  ├─ xml_node.cj
│     │  ├─ xml_node_kind.cj
│     │  ├─ xml_document.cj
│     │  ├─ xml_element.cj
│     │  ├─ xml_attribute.cj
│     │  ├─ xml_text.cj
│     │  ├─ xml_comment.cj
│     │  ├─ xml_declaration.cj
│     │  └─ xml_unknown.cj
│     ├─ parser/
│     │  ├─ xml_parser.cj
│     │  ├─ xml_parse_options.cj
│     │  └─ xml_source.cj
│     ├─ writer/
│     │  ├─ xml_writer.cj
│     │  └─ xml_write_options.cj
│     ├─ query/
│     │  ├─ xml_element_query_ext.cj
│     │  ├─ xml_node_iter_ext.cj
│     │  └─ xml_find_ext.cj
│     ├─ build/
│     │  ├─ xml_document_builder.cj
│     │  └─ xml_element_builder.cj
│     ├─ visit/
│     │  ├─ xml_visitor.cj
│     │  └─ xml_walk.cj
│     ├─ io/
│     │  ├─ xml_loader.cj
│     │  └─ xml_saver.cj
│     ├─ batch/                      # 可选：批量解析与并发能力
│     │  └─ xml_batch_parser.cj
│     └─ internal/
│        ├─ slice.cj
│        ├─ normalized_buffer.cj
│        ├─ entity_decoder.cj
│        ├─ utf8.cj
│        └─ text_escape.cj
├─ tests/
├─ resources/
├─ examples/
├─ DESIGN.md
└─ ROADMAP.md
```

### 5.2 分层关系

```text
           +-------------------+
           |      query        |
           +---------+---------+
                     |
+--------+  +--------v--------+  +--------+
| build  +->+       dom       +<-+ visit  |
+--------+  +---+----------+--+  +--------+
                ^          ^
                |          |
         +------+--+   +---+------+
         | parser  |   |  writer   |
         +----+----+   +-----+-----+
              ^                ^
              |                |
           +--+----------------+--+
           |         io            |
           +-----------+-----------+
                       |
                 +-----v-----+
                 |   error   |
                 +-----------+

   internal：仅供 parser / writer / io 复用，不直接暴露给用户
```

### 5.3 架构判断

- `dom` 是稳定中心。
- `parser` 与 `writer` 对称，围绕 `dom` 运作。
- `query` 与 `build` 是“体验层”，不污染 `dom` 核心。
- `visit` 是正交能力，不与 `writer` 或 `query` 互相绑死。
- `batch` 是可选能力层，用于承载并发与批处理，不反向污染 `dom`。
- `internal` 是性能与实现技巧的容器，不进入公共接口。

这种结构比 tinyxml2 的“单头文件大一统”更适合仓颉项目的长期维护，也更符合包职责清晰的规范。

---

## 6. 公共接口设计

### 6.1 节点体系

#### 6.1.1 `XmlNodeKind`

```cangjie
public enum XmlNodeKind {
    | Document(XmlDocument)
    | Element(XmlElement)
    | Text(XmlText)
    | Comment(XmlComment)
    | Declaration(XmlDeclaration)
    | Unknown(XmlUnknown)
}
```

这是模式匹配的入口，用来替代 `ToElement()` / `ToText()` 这一类 C++ 风格转型函数。

#### 6.1.2 `XmlNode`

```cangjie
public sealed interface XmlNode {
    prop document: XmlDocument
    prop parent: Option<XmlElement>
    prop previousSibling: Option<XmlNode>
    prop nextSibling: Option<XmlNode>

    func kind(): XmlNodeKind
    func removeSelf(): Bool
    func accept(visitor: XmlVisitor): Bool
}
```

设计要点：

- `XmlNode` 只表达**导航与统一行为**，不承担所有便利 API。
- `parent` / `previousSibling` / `nextSibling` 返回 `Option`，天然替代空指针与 Handle。
- 具体子类由 `kind()` 暴露给 `match` 使用。

### 6.2 `XmlDocument`

```cangjie
public class XmlDocument <: XmlNode {
    public prop rootElement: Option<XmlElement>
    public prop declaration: Option<XmlDeclaration>
    public prop hasBom: Bool
    public var writeBom: Bool

    public static func parseString(
        source: String,
        options!: XmlParseOptions = XmlParseOptions.default()
    ): Result<XmlDocument, XmlError>

    public static func parseBytes(
        source: Array<Byte>,
        options!: XmlParseOptions = XmlParseOptions.default()
    ): Result<XmlDocument, XmlError>

    public static func loadFile(
        path: String,
        options!: XmlParseOptions = XmlParseOptions.default()
    ): Result<XmlDocument, XmlError>

    public func createElement(name: String): XmlElement
    public func createText(value: String, cdata!: Bool = false): XmlText
    public func createComment(value: String): XmlComment
    public func createDeclaration(value!: Option<String> = None): XmlDeclaration
    public func createUnknown(value: String): XmlUnknown

    public func writeToString(
        options!: XmlWriteOptions = XmlWriteOptions.pretty()
    ): String

    public func saveFile(
        path: String,
        options!: XmlWriteOptions = XmlWriteOptions.pretty()
    ): Result<Unit, XmlError>
}
```

设计判断：

- 用 `parseString` / `parseBytes` / `loadFile` 明确输入来源，比 `Parse` 的多重语义更清晰。
- `writeToString` / `saveFile` 对称于读入 API。
- `XmlDocument` 只负责**文档级协调**，不塞进批量解析、锁管理、值编解码等跨领域能力。

### 6.3 `XmlElement`

```cangjie
public class XmlElement <: XmlNode {
    public var name: String

    public func attribute(name: String): Option<String>
    public func hasAttribute(name: String, value!: Option<String> = None): Bool
    public func setAttribute(name: String, value: String): Unit
    public func removeAttribute(name: String): Bool
    public func attributes(): Iterable<XmlAttribute>

    public func appendChild(node: XmlNode): Unit
    public func prependChild(node: XmlNode): Unit
    public func insertChildBefore(reference: XmlNode, node: XmlNode): Unit
    public func removeChild(node: XmlNode): Bool

    public func childNodes(): Iterable<XmlNode>
    public func childElements(name!: Option<String> = None): Iterable<XmlElement>
    public func firstChildElement(name!: Option<String> = None): Option<XmlElement>

    public func textContent(): String
    public func setTextContent(value: String): Unit
}
```

设计判断：

- 采用完整词 `attribute` / `childElements` / `textContent`，减少 API 的语义猜测成本。
- C++ 中 `Attribute(name, value)` 这种兼具“查值”和“比较”的接口被拆成 `attribute()` 与 `hasAttribute()`，更自然。
- 文本 API 用 `textContent`，更符合现代 DOM 语义，也比 `GetText()` 更清晰。

### 6.4 其他节点类型

```cangjie
public class XmlAttribute {
    public var name: String
    public var value: String
}

public class XmlText <: XmlNode {
    public var value: String
    public var isCdata: Bool
}

public class XmlComment <: XmlNode {
    public var value: String
}

public class XmlDeclaration <: XmlNode {
    public var value: String
}

public class XmlUnknown <: XmlNode {
    public var value: String
}
```

这里不引入多余继承层次；让类型的名字即其职责。

### 6.5 使用示例

```cangjie
import cangjie_xml.*
import cangjie_xml.query.*

main() {
    let doc = XmlDocument.parseString(
        """<catalog><book id="1">SICP</book></catalog>"""
    ).getOrThrow()

    if let root = doc.rootElement {
        for (book in root.childElements(name: Some("book"))) {
            let id = book.intAttribute("id").getOrDefault(0)
            println("${id}: ${book.textContent()}")
        }
    }
}
```

---

## 7. 核心实现模型

### 7.1 DOM 内部结构

tinyxml2 使用双向链表保存子节点，这一点在仓颉中依然有价值，因为 XML DOM 的典型操作是：

- 在已知节点附近插入新节点；
- 删除某个子节点；
- 顺序遍历；
- 很少按随机索引访问第 N 个孩子。

因此推荐：

- **节点之间仍采用双向链式关系；**
- `XmlElement` 内部维护私有的 child list；
- 对外只暴露 `Iterable<XmlNode>` 与 `Iterable<XmlElement>`；
- 属性使用 `ArrayList<XmlAttribute>` 保存插入顺序，再辅以名称索引加速查询。

### 7.2 为什么不直接用 `ArrayList<XmlNode>` 存孩子

虽然 `ArrayList` 更简单，但它会让以下操作成本变差：

- 中间插入 / 删除需要移动元素；
- `previousSibling` / `nextSibling` 需要回查索引；
- 节点自删时不够直接。

因此，v1.0 在子节点上保留链式结构，是合理的复杂度投入。

### 7.3 文档所有权模型

在 C++ 中，tinyxml2 通过 `XMLDocument` 持有节点内存；在仓颉中，这种“内存所有权”不再是核心问题。

仓颉版本中，`XmlDocument` 的职责应转化为：

1. 提供文档级根上下文；
2. 持有解析与写出相关元信息（如 BOM）；
3. 作为所有节点都可回溯到的“文档边界”。

也就是说：

- **文档是语义所有者，而不是手工内存所有者。**

这能让设计更贴合 GC 语言，也更符合用户直觉。

---

## 8. 解析器设计

### 8.1 输入抽象

```cangjie
public enum XmlSource {
    | StringSource(String)
    | ByteSource(Array<Byte>)
    | StreamSource(InputStream)
}
```

公共 API 不一定直接暴露 `XmlSource`，但内部可以用它统一解析入口。

### 8.2 解析流程

推荐的解析管线如下：

```text
Input
  -> BOM 识别
  -> 换行规范化
  -> 生成 NormalizedBuffer
  -> 词法扫描（按需）
  -> 递归下降解析
  -> 构建 DOM
  -> 返回 XmlDocument / XmlError
```

### 8.3 内部辅助结构

内部实现推荐使用：

| 类型 | 作用 |
|---|---|
| `Slice` | 在规范化缓冲区上表示 `[start, end)` 区间 |
| `NormalizedBuffer` | 保存 UTF-8 文本、BOM 标记、行偏移表 |
| `EntityDecoder` | 处理预定义实体与字符引用 |
| `ParserState` | 当前游标、深度、选项、行列信息 |

这些类型全部放在 `internal` 层，不暴露给用户。

### 8.4 `XmlParseOptions`

```cangjie
public enum XmlWhitespaceMode {
    | Preserve
    | Collapse
    | Pedantic
}

public struct XmlParseOptions {
    public let processEntities: Bool
    public let whitespaceMode: XmlWhitespaceMode
    public let maxElementDepth: Int64
    public let strictUtf8: Bool
}
```

命名上统一加 `Xml` 前缀，有两个好处：

- 多包引用时更清晰；
- `ParseOptions` 这类过泛名字不会污染调用点语义。

### 8.5 错误策略

解析器采用**首错即止**策略：

- 一旦遇到结构错误，立即返回 `Err(XmlError)`；
- 不尝试在非法文档上继续恢复；
- 保证错误位置、错误类别和辅助信息明确。

这是最符合 tinyxml2 精神，也最适合 v1.0 的策略。

### 8.6 深度保护

保持与 tinyxml2 一致的默认上限：

```cangjie
public const MAX_ELEMENT_DEPTH: Int64 = 500
```

但实现上把它变成 `XmlParseOptions.maxElementDepth` 的默认值，而不是硬编码到解析器内部。

这让 API 更弹性，也更符合配置对象的职责边界。

---

## 9. Writer 设计

### 9.1 为什么用 `Writer` 而不是 `Printer`

`Printer` 更偏向“格式化打印”的历史命名；而仓颉版本既要支持：

- 写到字符串；
- 写到文件；
- 写到流；
- 未来可能写事件流；

因此，**`XmlWriter` 是更稳定、语义更宽的核心名词**。

若后续需要兼容 tinyxml2 风格，可以再提供轻量适配名 `XmlPrinter`，但它不应成为核心设计中心。

### 9.2 `XmlWriteOptions`

```cangjie
public struct XmlWriteOptions {
    public let compact: Bool
    public let indent: String
    public let writeDeclaration: Bool
    public let writeBom: Bool
    public let boolTrueText: String
    public let boolFalseText: String
}
```

这样 tinyxml2 中原本依赖全局静态状态的部分，就被收敛为单次写出的显式配置。

### 9.3 输出抽象

```cangjie
public interface XmlSink {
    func write(text: String): Unit
    func flush(): Unit
}
```

默认实现可以有：

- `StringXmlSink`
- `StreamXmlSink`
- `FileXmlSink`

但它们属于实现细节或辅助层；用户通常直接用 `writeToString()` / `saveFile()` 即可。

### 9.4 Writer 与 Visit 的关系

推荐让 `XmlWriter` 复用访问者机制：

- `XmlWriter` 实现 `XmlVisitor`；
- `XmlDocument.accept(writer)` 驱动输出；
- 同时保留 `XmlWriter` 的流式手动接口，用于不构建 DOM 的简单场景。

这样可以形成一条优雅的一致性原则：

> **遍历是统一机制，写出只是遍历的一种实现。**

---

## 10. Query / Build / Visit：体验层设计

### 10.1 Query：把便利 API 放在扩展层

tinyxml2 把很多类型化查询直接堆进 `XMLElement`。在仓颉中，更优雅的方式是：

- `dom` 核心只提供 `attribute(name): Option<String>`；
- `query` 通过 `extend XmlElement` 提供：
  - `intAttribute(name)`
  - `boolAttribute(name)`
  - `doubleAttribute(name)`
  - `requiredAttribute(name)`
  - `childElement(name)` 等便捷能力。

这样可以避免 `XmlElement` 本体过度膨胀。

### 10.2 `XmlValueCodec`

比起 `XmlAttrConvertible`，`XmlValueCodec` 这个名字更准确：它强调的是**双向编解码协议**，而不是模糊的“可转换”。

推荐定义：

```cangjie
public interface XmlValueCodec<T> {
    func parse(text: String): Result<T, XmlError>
    func format(value: T): String
}
```

有了它：

- Builder 可以写 `setAttribute("id", id, using: Int64XmlCodec)`；
- Query 可以写 `attributeAs("id", using: Int64XmlCodec)`；
- 用户自定义类型也能优雅接入。

对常见类型，再在 `query` 中提供简明扩展函数，兼顾优雅与易用。

### 10.3 Build：Builder 只服务构建体验

```cangjie
public class XmlDocumentBuilder {
    public func declaration(
        version!: String = "1.0",
        encoding!: String = "UTF-8"
    ): XmlDocumentBuilder

    public func root(
        name: String,
        build!: (XmlElementBuilder) -> Unit = {_ => ()}
    ): XmlDocumentBuilder

    public func build(): XmlDocument
}
```

```cangjie
public class XmlElementBuilder {
    public func attribute(name: String, value: String): XmlElementBuilder
    public func text(value: String, cdata!: Bool = false): XmlElementBuilder
    public func element(
        name: String,
        build!: (XmlElementBuilder) -> Unit = {_ => ()}
    ): XmlElementBuilder
}
```

Builder 的关键要求是：

- **只负责提升构建体验；**
- **不成为另一套平行 DOM；**
- **最终产物必须仍是普通 `XmlDocument` / `XmlElement`。**

### 10.4 Visit：保留经典访问者，同时提供函数式遍历

```cangjie
public interface XmlVisitor {
    func visitEnter(document: XmlDocument): Bool { true }
    func visitExit(document: XmlDocument): Bool { true }
    func visitEnter(element: XmlElement): Bool { true }
    func visitExit(element: XmlElement): Bool { true }
    func visit(text: XmlText): Bool { true }
    func visit(comment: XmlComment): Bool { true }
    func visit(declaration: XmlDeclaration): Bool { true }
    func visit(unknown: XmlUnknown): Bool { true }
}
```

另外提供：

```cangjie
public enum XmlWalkControl {
    | Continue
    | SkipChildren
    | Stop
}

public func walk(
    node: XmlNode,
    visit: (XmlNodeKind) -> XmlWalkControl
): Unit
```

这让库同时兼顾：

- 传统 OO 访问者风格；
- 仓颉更轻量的函数式风格。

---

## 11. 错误模型

### 11.1 `XmlError`

推荐使用带上下文的枚举，而不是只有整数错误码：

```cangjie
public enum XmlError {
    | FileNotFound(path: String)
    | FileReadFailed(path: String, cause: String)
    | FileWriteFailed(path: String, cause: String)
    | EmptyDocument
    | MismatchedElement(openTag: String, closeTag: String, at: SourcePos)
    | InvalidAttribute(name: String, at: SourcePos, reason: String)
    | InvalidText(at: SourcePos, reason: String)
    | InvalidComment(at: SourcePos, reason: String)
    | InvalidDeclaration(at: SourcePos, reason: String)
    | InvalidUnknownNode(at: SourcePos, reason: String)
    | InvalidEncoding(at: SourcePos, reason: String)
    | ElementDepthExceeded(limit: Int64, at: SourcePos)
    | ValueDecodeFailed(targetType: String, text: String, at: SourcePos)
}
```

### 11.2 `SourcePos`

```cangjie
public struct SourcePos {
    public let offset: Int64
    public let line: Int64
    public let column: Int64
}
```

### 11.3 使用原则

- `Option<T>`：可预期的“没有值”。
- `Result<T, XmlError>`：可预期的“可能失败”。
- `XmlException`：调用方误用 API 或库内部不变量被破坏。

这种划分最符合仓颉的错误处理习惯，也比 tinyxml2 的单纯错误码更有表现力。

---

## 12. 并发设计：边界清晰，而不是处处上锁

### 12.1 设计判断

XML DOM 的核心价值是**结构清晰与确定性**，不是高并发读写。因此：

- v1.0 **不把锁直接内建进 `XmlDocument` / `XmlElement`**；
- 默认假定 DOM 在单线程上下文中构建和修改；
- 只读 DOM 可以安全地被多个线程共享；
- 并发能力主要体现在“多文档批量解析”与“只读并行消费”。

### 12.2 并发能力的承载位置

并发不放入 `dom`，而放在独立的辅助层，例如：

```text
cangjie_xml/batch/
├─ xml_batch_parser.cj
└─ xml_batch_result.cj
```

或在 `parser` 中以静态工具类型承载：

```cangjie
public class XmlBatchParser {
    public static func parseAll(
        sources: Array<XmlSource>,
        options!: XmlParseOptions = XmlParseOptions.default(),
        concurrency!: Int64 = 0
    ): Array<Result<XmlDocument, XmlError>>
}
```

### 12.3 为什么这样更合理

- 保持 DOM 核心无锁、轻量、确定。
- 不把“批量任务调度”错误塞给每个 `XmlDocument` 实例。
- 更符合单一职责原则。
- 如果未来并发策略变化，不会波及 DOM 设计。

**结论：并发是能力层，不是 DOM 的本体属性。**

---

## 13. 安全与健壮性

### 13.1 默认安全立场

1. 默认仅支持预定义实体和字符引用。
2. 不支持外部实体展开，因此天然规避 XXE / Billion Laughs 这一类问题。
3. 默认最大元素深度 500。
4. 文件读写错误与编码错误必须显式返回。
5. 非法 UTF-8 处理由 `strictUtf8` 控制，默认与 tinyxml2 一样偏务实，但提供严格模式。

### 13.2 行为约束

- 不记录敏感文件内容到错误信息中。
- 不在恢复失败的状态下继续构造半残缺 DOM。
- 所有公共写出接口都必须是确定性的：相同 DOM + 相同 `XmlWriteOptions` → 相同输出。

---

## 14. 测试与质量策略

### 14.1 测试来源

测试应来自三个层次：

1. **tinyxml2 现有样例与回归用例迁移**；
2. **仓颉风格 API 的新增行为测试**；
3. **边界与错误路径测试**。

### 14.2 测试分层

| 层次 | 内容 |
|---|---|
| DOM 单元测试 | 节点连接、属性增删、遍历、克隆、相等等 |
| Parser 单元测试 | 各节点类型、空白策略、错误位置、深度保护 |
| Writer 单元测试 | 转义、缩进、紧凑模式、BOM、声明输出 |
| Round-trip 测试 | parse → write → parse 一致性 |
| 回归测试 | 移植 tinyxml2 `xmltest.cpp` 的关键断言 |
| 并发测试 | 批量解析、只读共享访问 |
| 性能基准 | 大文档解析、批量解析、序列化吞吐 |

### 14.3 质量门禁

- `cjpm build`
- `cjpm test`
- `cjfmt`
- `cjlint`
- `cjcov`
- 对照 tinyxml2 回归样例

质量门禁不只是工程动作，也是一种设计反馈机制：任何让 API 失去一致性、让结构变丑的改动，最终都会在测试和评审中暴露出来。

---

## 15. 与 tinyxml2 的映射总表

| tinyxml2 | CangjieXML |
|---|---|
| `XMLDocument` | `XmlDocument` |
| `XMLElement` | `XmlElement` |
| `XMLText` | `XmlText` |
| `XMLComment` | `XmlComment` |
| `XMLDeclaration` | `XmlDeclaration` |
| `XMLUnknown` | `XmlUnknown` |
| `XMLAttribute` | `XmlAttribute` |
| `XMLVisitor` | `XmlVisitor` |
| `XMLPrinter` | `XmlWriter`（可选兼容别名：`XmlPrinter`） |
| `XMLError` | `XmlError` |
| `Whitespace` | `XmlWhitespaceMode` |
| `XMLHandle` | `Option` + `?.` / `??` |
| `StrPair` | `internal/Slice` + `NormalizedBuffer` |
| `MemPool` | 删除（由 GC 与后续内部优化替代） |

---

## 16. v1.0 的设计收敛点

为了避免设计过度膨胀，v1.0 必须收敛到以下最小完备集合：

1. `dom`
2. `parser`
3. `writer`
4. `error`
5. `query`（仅最核心便利能力）
6. `build`（轻量 DSL）
7. `visit`
8. `io`

而以下内容明确列为后续增强：

- SAX / Pull 风格流式解析
- 宏驱动的对象绑定
- XPath 子集
- 内部对象池与字符串驻留

**判断标准很简单：凡是不能直接提升 v1.0 的稳定可用性，就不应抢占 v1.0 的设计中心。**

---

## 17. 总结

CangjieXML 的核心设计判断可以概括为一句话：

> **保留 tinyxml2 的边界与朴素，放弃其历史包袱；用仓颉把 XML 库做成一个结构对称、命名干净、体验现代的基础库。**

对应到具体设计上，就是：

- 在能力上，学习 tinyxml2 的克制；
- 在接口上，采用仓颉的 `Option`、模式匹配、扩展与显式配置；
- 在结构上，坚持 `dom / parser / writer / query / build / visit / io / error / internal` 这组对称而稳定的边界；
- 在工程上，把并发、性能技巧和未来特性放到核心之外，按阶段自然生长。

这套设计既尊重 tinyxml2，也避免被 tinyxml2 绑定；既照顾实现可行性，也追求命名与结构上的审美完整性。
