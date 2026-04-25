# CangjieXML

> 纯仓颉语言实现的 XML 库 —— 以 [tinyxml2](https://github.com/leethomason/tinyxml2)
> 为参照，在保留其务实能力边界（DOM + 基础读写）的同时，用仓颉的 `enum` /
> 模式匹配 / `Option` / 扩展 / 泛型 重建 API。**不是** 对 tinyxml2 的逐行翻译，
> 而是一次面向仓颉现代语言特性的重构复刻。

设计详情见 [`DESIGN.md`](./DESIGN.md)，迭代节奏见 [`ROADMAP.md`](./ROADMAP.md)，
开发进度见 [`progress.md`](./progress.md)，
完整 API 文档见 [`doc/`](./doc/README.md)。

---

## 目录

- [特性亮点](#特性亮点)
- [当前状态](#当前状态)
- [快速上手](#快速上手)
- [使用示例](#使用示例)
- [模块概览](#模块概览)
- [与 tinyxml2 的映射](#与-tinyxml2-的映射)
- [路线图](#路线图)
- [许可证](#许可证)

---

## 特性亮点

- **纯仓颉实现**：零 C/C++ 依赖，与 `cjpm` 工具链无缝集成。
- **完整读写闭环**：DOM 内核、解析器、序列化器、文件与字节 IO 一次性齐备。
- **现代 API 风格**：`Option<T>` 安全导航、`enum` 错误语义、模式匹配分派、
  泛型值编解码。
- **类型化查询 + Builder DSL**：`intAttribute` / `boolAttribute` /
  `XmlDocumentBuilder` 以声明式风格构造和读取文档。
- **两种遍历范式**：函数式 `walk` 与经典 `XmlVisitor`，按偏好选择。
- **确定性序列化**：相同 DOM + 相同 `XmlWriteOptions` → 逐字节一致输出，
  天然适配 diff、缓存、签名场景。
- **工程化质量红线**：单文件 ≤ 300 行、无下划线前缀、低圈复杂度、常量化、
  **单元测试 119/119 通过**、**E2E 10/10 指纹与 Python `xml.etree` 一致**。

---

## 当前状态

| 里程碑 | 名称                         | 状态                                              |
| ------ | ---------------------------- | ------------------------------------------------- |
| M0     | 项目脚手架                   | ✅ 完成                                            |
| M1     | DOM 内核                     | ✅ 完成                                            |
| M2     | Writer                       | ✅ 完成                                            |
| M3     | Parser                       | ✅ 完成                                            |
| M4     | Query + Builder              | ✅ 完成                                            |
| M5     | Visit                        | ✅ 完成                                            |
| M6     | IO + Error + Options 收口    | ✅ 完成                                            |
| M7     | Batch / Concurrency          | ⛔ 跳过（与 DOM 单线程契约冲突，留待后续大版本） |
| M8     | 回归 / E2E / 发布            | ✅ 10/10 fixture 与 Python `xml.etree` 指纹一致   |
| —      | 质量红线                     | ✅ 单文件 ≤ 300 行 / 无下划线前缀 / 常量化 / 低圈复杂度 |

读写循环已闭合，类型化查询、Builder DSL、访问者 / 函数式遍历、文件 / 字节 IO、
以及对照 Python 标准库的端到端验收均已就绪。

---

## 快速上手

### 环境要求

- 仓颉 SDK **1.0.5**
- 仓颉项目管理器 `cjpm`

### 构建与测试

```bash
source /opt/cangjie/envsetup.sh   # 或自行配置仓颉 SDK
cjpm build
cjpm test
```

---

## 使用示例

### 手工构造 DOM 并序列化

```cangjie
import cangjie_xml.dom.*
import cangjie_xml.writer.*

main() {
    let doc = XmlDocument()
    doc.appendChild(doc.createDeclaration())          // <?xml version="1.0" encoding="UTF-8"?>

    let root = doc.createElement("catalog")
    doc.appendChild(root)

    let book = doc.createElement("book")
    book.setAttribute("id", "1")
    book.setTextContent("SICP")
    root.appendChild(book)

    // 美化输出（默认）
    println(doc.writeToString())
    // <?xml version="1.0" encoding="UTF-8"?>
    // <catalog>
    //     <book id="1">SICP</book>
    // </catalog>

    // 紧凑输出
    println(doc.writeToString(XmlWriteOptions.compactPreset()))
    // <?xml version="1.0" encoding="UTF-8"?><catalog><book id="1">SICP</book></catalog>

    0
}
```

### 解析 XML 字符串

```cangjie
import cangjie_xml.dom.*
import cangjie_xml.parser.*
import cangjie_xml.error.*

main() {
    try {
        let doc = parseXml(
            "<catalog><book id=\"1\">SICP</book></catalog>")
        println(doc.rootElement.getOrThrow().firstChildElement(name: Some("book"))
                   .getOrThrow().textContent())
        // SICP

        // Collapse 模式：折叠空白并删除纯空白文本节点
        let opts = XmlParseOptions(whitespace: Collapse)
        let doc2 = parseXml("<r>  a\n  b  </r>", opts)
        println(doc2.rootElement.getOrThrow().textContent())
        // "a b"
    } catch (e: XmlParseException) {
        println("parse error: ${e.error}")
    }
    0
}
```

### Builder DSL + 类型化查询

```cangjie
import cangjie_xml.dom.*
import cangjie_xml.build.*
import cangjie_xml.query.*

main() {
    // 用 Builder 构造
    let doc = XmlDocumentBuilder()
        .declaration()
        .root("catalog") { r =>
            r.element("book") { b =>
                b.attributeAs<Int64>("id", 1, INT64_CODEC)
                 .attributeAs<Bool>("avail", true, BOOL_CODEC)
                 .text("SICP")
            }
        }
        .build()

    let root = doc.rootElement.getOrThrow()
    let book = root.requiredChildElement("book")
    println(book.intAttribute("id"))       // Some(1)
    println(book.boolAttribute("avail"))   // Some(true)
    println(book.textContent())            // "SICP"

    // 缺失 / 解析失败时的统一处理
    println(book.attributeOr<Int64>("missing", INT64_CODEC, 0))  // 0
    0
}
```

### 遍历：函数式 walk 与经典 Visitor

```cangjie
import cangjie_xml.dom.*
import cangjie_xml.visit.*

main() {
    let doc = /* ... */

    // 函数式 walk：统计所有 <book> 元素数量
    class Acc { public var n: Int64 = 0 }
    let count = Acc()
    walk(doc) { kind =>
        match (kind) {
            case Element(e) where e.name == "book" =>
                count.n++
                SkipChildren           // 不再进入 book 的子树
            case _ => Continue
        }
    }
    println(count.n)

    // 经典 Visitor：对称的 enter / exit
    class NamePrinter <: XmlVisitor {
        public func visitEnter(element: XmlElement): Bool {
            println("<${element.name}>")
            true
        }
    }
    doc.accept(NamePrinter())
    0
}
```

> **注意**：`walk` / `accept` 的回调是 lambda；cjc 1.0.5 禁止 lambda 捕获可变
> `var`，聚合计数时请把状态封装进 `class`（如示例中的 `Acc`）。

### 文件 / 字节 IO

```cangjie
import cangjie_xml.dom.*
import cangjie_xml.io.*
import cangjie_xml.error.*

main() {
    let doc = /* ... build or parse ... */

    // 一次性落盘：先序列化到内存再写文件，语义像事务（失败不留半成品）
    saveXmlToFile(doc, "/tmp/out.xml")

    // 读回
    let back = try {
        loadXmlFromFile("/tmp/out.xml")
    } catch (e: XmlIoException) {
        match (e.error) {
            case FileNotFound(p)        => { println("missing: ${p}"); return 1 }
            case FileReadFailed(p, msg) => { println("read ${p}: ${msg}"); return 1 }
            case _ => throw e
        }
    }

    // 字节形态：HTTP body、JDBC BLOB …
    let bytes = writeXmlToBytes(doc)
    let fromBytes = parseXmlBytes(bytes)

    // 大文档流式落盘：避免先把整个文档放进 StringBuilder
    try (sink = FileXmlSink("/tmp/big.xml")) {
        let w = XmlWriter(sink)
        w.writeDocument(doc)
    }
    0
}
```

> **错误分层**：`XmlIoException` 只负责 IO 边界（文件不存在 / 磁盘错误 /
> 非法 UTF-8）；落盘之后的语法错误原样以 `XmlParseException` 抛出，两者不互相嵌套。

---

## 模块概览

### `cangjie_xml`（根包）

| 符号                            | 说明                |
| ------------------------------- | ------------------- |
| `CANGJIE_XML_VERSION: String`   | 编译期版本号常量    |
| `cangjieXmlVersion(): String`   | 运行时版本探测函数  |

### `cangjie_xml.error`

| 类型            | 说明                                                                                       |
| --------------- | ------------------------------------------------------------------------------------------ |
| `SourcePos`     | 源文本位置（`offset` / `line` / `column`）；`SourcePos.zero()` 提供默认值。                |
| `XmlError`      | 库级错误枚举，共 14 个构造器，覆盖 DOM / 解析 / IO 三类场景，实现 `ToString`。             |
| `XmlException`  | 不可预期的 API 误用异常（例如成环、跨文档插入）。                                          |

### `cangjie_xml.dom` —— DOM 内核

#### 类型总览

```text
XmlNode (sealed abstract)
├─ XmlDocument      // 文档根
├─ XmlElement       // 元素
├─ XmlText          // 文本 / CDATA
├─ XmlComment       // 注释
├─ XmlDeclaration   // <?xml ... ?>
└─ XmlUnknown       // <!DOCTYPE ...> 等
```

`XmlAttribute` 独立为一个简单数据类，**不是** `XmlNode` 的子类型 —— 这符合
XML 规范中"属性不是节点树成员"的语义。

#### 共通导航（`XmlNode`）

| 成员                                                  | 说明                                             |
| ----------------------------------------------------- | ------------------------------------------------ |
| `document: XmlDocument`                               | 节点所属文档；对 `XmlDocument` 自身返回 `this`   |
| `parent: ?XmlElement`                                 | 父元素；根元素 / 文档直挂节点为 `None`           |
| `previousSibling: ?XmlNode` / `nextSibling: ?XmlNode` | 兄弟节点                                         |
| `kind(): XmlNodeKind`                                 | 返回 `enum`，用于模式匹配                        |
| `removeSelf(): Bool`                                  | 从父节点脱离；若当前无父，返回 `false`           |

模式匹配示例：

```cangjie
match (node.kind()) {
    case Element(e) => println(e.name)
    case Text(t)    => println(t.value)
    case _          => ()
}
```

#### `XmlDocument`

- **节点工厂**：`createElement` / `createText(value, cdata:)` / `createComment` /
  `createDeclaration(value:)` / `createUnknown`，自动将新节点绑定到当前文档。
- **顶层节点管理**：`appendChild` / `prependChild` / `removeChild` / `clear`。
  - 最多一个根元素、最多一条 `XmlDeclaration`（且必须位于最前）；
  - 顶层不允许裸 `XmlText`；
  - 禁止跨文档插入。
- **便捷访问**：`rootElement: ?XmlElement`、`declaration: ?XmlDeclaration`、
  `firstChild` / `lastChild` / `childNodes()`。
- **文档级元信息**：`hasBom: Bool`（解析时填充）、`writeBom: Bool`
  （写出时决定是否输出 BOM）。

#### `XmlElement`

- **属性 API**
  - `attribute(name): ?String`
  - `hasAttribute(name, value: ?String)`
  - `setAttribute(name, value)` —— 同名后写覆盖，保留首次插入顺序
  - `removeAttribute(name): Bool`
  - `attributes(): Iterable<XmlAttribute>`（按插入顺序）
  - `attributeCount(): Int64`
- **子节点 API**
  - `appendChild` / `prependChild` / `insertChildBefore(reference, node)` / `removeChild`
  - `childNodes()` / `childElements(name:)` / `firstChildElement(name:)`
  - `firstChild: ?XmlNode` / `lastChild: ?XmlNode` / `isEmpty(): Bool`
  - **安全约束**：
    - 禁止将节点作为自己的祖先 / 后代（成环检测）；
    - 禁止跨文档插入；
    - 节点从其他父节点 / 文档插入时自动先解挂（DOM 移动语义）；
    - 禁止将 `XmlDocument` 或 `XmlDeclaration` 作为元素子节点。
- **文本 API**
  - `textContent(): String` —— 递归拼接所有后代 `XmlText` 的 `value`；
  - `setTextContent(value)` —— 清空子节点后追加单个非 CDATA `XmlText`。

#### `XmlAttribute` / `XmlText` / `XmlComment` / `XmlDeclaration` / `XmlUnknown`

轻量数据类，字段均可变。`XmlText` 额外带 `isCdata: Bool` 用以标记 CDATA 段。

### `cangjie_xml.writer` —— 序列化

#### 公共入口

| API                                           | 说明                                                    |
| --------------------------------------------- | ------------------------------------------------------- |
| `XmlDocument.writeToString(options?): String` | 把整个文档序列化为字符串（可选配置）                    |
| `XmlElement.writeToString(options?): String`  | 把单个元素子树序列化（不含声明 / BOM）                  |
| `XmlWriter(sink, options:)`                   | 底层 API：把 DOM 写入任意 `XmlSink`                     |
| `StringXmlSink`                               | 内存 Sink，通过 `toString()` 读取结果                   |
| `XmlSink`                                     | 自定义 Sink 扩展点（可接文件 / 流）                     |

#### `XmlWriteOptions`

不可变 `struct`，所有字段一次构造一次生效，消除全局静态状态。

| 字段                              | 默认              | 说明                                                                                                |
| --------------------------------- | ----------------- | --------------------------------------------------------------------------------------------------- |
| `compact`                         | `false`           | `true` 紧凑单行；`false` 美化缩进                                                                   |
| `indent`                          | `"    "`          | 每层嵌套的缩进串（仅美化模式）                                                                      |
| `lineEnd`                         | `"\n"`            | 行结束符（仅美化模式）                                                                              |
| `writeDeclaration`                | `true`            | 是否输出 `<?xml ... ?>`；已有声明原样输出，没有则合成默认                                           |
| `writeBom`                        | `false`           | 是否在开头写入 UTF-8 BOM；也会因 `document.writeBom=true` 自动启用                                  |
| `boolTrueText` / `boolFalseText`  | `"true"` / `"false"` | 留给 Query / Builder 层使用                                                                       |

便捷工厂：`XmlWriteOptions.default_()`、`XmlWriteOptions.compactPreset()`。

#### 排版规则

| 元素内容                  | 输出                                               |
| ------------------------- | -------------------------------------------------- |
| 无子节点                  | `<e/>`                                             |
| 单个文本子节点（常见）    | `<e>text</e>`                                      |
| 含文本的混合内容          | 全内联：`<e>a<b/>c</e>`（保留空白语义）            |
| 仅元素 / 注释 / 未知子节点 | 块级：每个子节点独占一行，按 `indent` 缩进         |

#### 转义

- **文本节点**：`&` / `<` / `>` → 对应实体
- **属性值**：追加 `"` → `&quot;`
- **CDATA**：不转义；若内容含 `]]>` 自动按规范拆段
- **快路径**：输入不含任何需转义字符时直接返回原字符串，零分配

#### 确定性契约

**相同 DOM + 相同 `XmlWriteOptions` → 逐字节一致的输出**。专项测试
`testDeterminism` 保证；这使 diff、缓存失效、签名校验等外围工程成为可能。

---

## 与 tinyxml2 的映射

完整对照见 [`DESIGN.md` §15](./DESIGN.md)。关键差异：

| tinyxml2                         | CangjieXML                      | 原因                             |
| -------------------------------- | ------------------------------- | -------------------------------- |
| `XMLHandle` / `XMLConstHandle`   | `Option<T>` + `?.` / `??`       | 语言特性天然覆盖                 |
| `ToElement()` / `ToText()`       | `match (node.kind())`           | 模式匹配优雅于运行时转型         |
| `MemPool` / `StrPair`            | （不提供）                      | GC 语言的职责边界                |
| 全局静态写出开关                 | `XmlWriteOptions`               | 显式配置，多线程安全             |

