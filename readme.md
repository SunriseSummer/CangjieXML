# CangjieXML

> 纯仓颉实现的 XML 库——受 [tinyxml2](https://github.com/leethomason/tinyxml2) 启发，但
> **不是** 对 tinyxml2 的逐行翻译。在保留其务实的能力边界（DOM + 基础读写）的同时，
> 以仓颉的 `enum` / 模式匹配 / `Option` / 扩展 / 泛型 重建 API，使其"看起来像仓颉库"，
> 而不是"C++ 库的投影"。
>
> 设计详情见 [`DESIGN.md`](./DESIGN.md)，迭代节奏见 [`ROADMAP.md`](./ROADMAP.md)，
> 当前进度见 [`progress.md`](./progress.md)。

---

## 当前状态

| 里程碑 | 状态 |
|---|---|
| M0 项目脚手架 | ✅ |
| M1 DOM 内核  | ✅ |
| M2 Writer    | ✅ |
| M3 Parser    | ✅ |
| M4 Query + Builder | ✅ |
| M5 Visit     | ✅ |
| 质量红线（单文件 ≤ 300 行 / 无下划线前缀 / 常量化 / 低圈复杂度） | ✅ |

读写循环已闭合，类型化查询、Builder DSL 与访问者/函数式遍历均已就绪。测试 **107/107 通过**。

---

## 快速上手

### 构建与测试

```bash
source /opt/cangjie/envsetup.sh   # 或自行配置 cangjie SDK 1.0.5
cjpm build
cjpm test
```

### 示例：手工构造一棵 DOM 并序列化

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

### 示例：解析 XML 字符串

```cangjie
import cangjie_xml.dom.*
import cangjie_xml.parser.*
import cangjie_xml.error.*

main() {
    try {
        let doc = XmlDocument.parseString(
            "<catalog><book id=\"1\">SICP</book></catalog>")
        println(doc.rootElement.getOrThrow().firstChildElement(name: Some("book"))
                   .getOrThrow().textContent())
        // SICP

        // Collapse 模式：折叠空白并删除纯空白文本节点
        let opts = XmlParseOptions(whitespace: Collapse)
        let doc2 = XmlDocument.parseString("<r>  a\n  b  </r>", opts)
        println(doc2.rootElement.getOrThrow().textContent())
        // "a b"
    } catch (e: XmlParseException) {
        println("parse error: ${e.error}")
    }
    0
}
```

### 示例：Builder DSL + 类型化查询

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

    // 缺失/解析失败时的统一处理
    println(book.attributeOr<Int64>("missing", INT64_CODEC, 0))  // 0
    0
}
```

### 示例：遍历（函数式 / 访问者两种风格）

```cangjie
import cangjie_xml.dom.*
import cangjie_xml.visit.*

main() {
    let doc = /* ... */

    // 函数式 walk：收集所有 <book> 元素的 id
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

    // 经典 Visitor：对称的 enter/exit
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

> 注意：`walk` / `accept` 的回调是 lambda；cjc 1.0.5 禁止 lambda 捕获
> 可变 `var`，聚合计数时请把状态封装进 `class`（如示例中的 `Acc`）。

---

## 已实现模块

### `cangjie_xml`（根包）

- `CANGJIE_XML_VERSION: String`：版本号常量。
- `cangjieXmlVersion(): String`：运行时探测版本。

### `cangjie_xml.error`

| 类型 | 说明 |
|---|---|
| `SourcePos` | 源文本位置（`offset` / `line` / `column`）。`SourcePos.zero()` 提供默认值。 |
| `XmlError` | 库级错误枚举。共 14 个构造器，M1 仅启用 `DomOperationFailed`；其他构造器在 M3 / M4 / M6 激活。实现 `ToString`。 |
| `XmlException` | 不可预期的 API 误用异常（例如成环、跨文档插入）。 |

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

`XmlAttribute` 独立为一个简单数据类，**不是** `XmlNode` 的子类型——这符合 XML 规范中
"属性不是节点树成员"的语义。

#### 共通导航（`XmlNode`）

| 成员 | 说明 |
|---|---|
| `document: XmlDocument` | 节点所属文档；对 `XmlDocument` 自身返回 `this` |
| `parent: ?XmlElement` | 父元素；根元素 / 文档直挂节点为 `None` |
| `previousSibling: ?XmlNode` / `nextSibling: ?XmlNode` | 兄弟节点 |
| `kind(): XmlNodeKind` | 返回 `enum`，用于模式匹配 |
| `removeSelf(): Bool` | 从父节点脱离；若当前无父，返回 `false` |

> 模式匹配示例：
> ```cangjie
> match (node.kind()) {
>     case Element(e) => println(e.name)
>     case Text(t)    => println(t.value)
>     case _          => ()
> }
> ```

#### `XmlDocument`

- **节点工厂**：`createElement` / `createText(value, cdata:)` / `createComment` /
  `createDeclaration(value:)` / `createUnknown`。所有工厂方法自动将新节点绑定到
  当前文档。
- **顶层节点管理**：`appendChild` / `prependChild` / `removeChild` / `clear`。
  约束：
  - 最多一个根元素、最多一条 `XmlDeclaration`（且必须位于最前）；
  - 顶层不允许裸 `XmlText`；
  - 禁止跨文档插入。
- **便捷访问**：`rootElement: ?XmlElement`、`declaration: ?XmlDeclaration`、
  `firstChild` / `lastChild` / `childNodes()`。
- **文档级元信息**：`hasBom: Bool`（解析时填充，M3 起）、`writeBom: Bool`
  （写出时决定是否输出 BOM，M2 起使用）。

#### `XmlElement`

- **属性 API**
  - `attribute(name): ?String`
  - `hasAttribute(name, value: ?String)`
  - `setAttribute(name, value)`——同名后写覆盖，保留首次插入顺序
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
  - `textContent(): String`——递归拼接所有后代 `XmlText` 的 `value`；
  - `setTextContent(value)`——清空子节点后追加单个非 CDATA `XmlText`。

#### `XmlAttribute` / `XmlText` / `XmlComment` / `XmlDeclaration` / `XmlUnknown`

轻量数据类，字段均可变。`XmlText` 额外带 `isCdata: Bool` 标志 CDATA 段。

### `cangjie_xml.writer` —— 序列化

#### 公共入口

| API | 说明 |
|---|---|
| `XmlDocument.writeToString(options?): String` | 把整个文档序列化为字符串（可选配置） |
| `XmlElement.writeToString(options?): String` | 把单个元素子树序列化（不含声明 / BOM） |
| `XmlWriter(sink, options:)` | 底层 API：把 DOM 写入任意 `XmlSink` |
| `StringXmlSink` | 内存 Sink，暴露 `toString()` 读取结果 |
| `XmlSink` | 自定义 Sink 扩展点（M6 起可接文件 / 流） |

#### `XmlWriteOptions`

不可变 `struct`，所有字段一次构造一次生效，消除全局静态状态。

| 字段 | 默认 | 说明 |
|---|---|---|
| `compact` | `false` | `true` 紧凑单行；`false` 美化缩进 |
| `indent` | `"    "` | 每层嵌套的缩进串（仅美化模式） |
| `lineEnd` | `"\n"` | 行结束符（仅美化模式） |
| `writeDeclaration` | `true` | 是否输出 `<?xml ... ?>`；`true` 时已有声明原样输出，没有则合成默认 |
| `writeBom` | `false` | 是否在开头写入 UTF-8 BOM；也会因 `document.writeBom=true` 自动启用 |
| `boolTrueText` / `boolFalseText` | `"true"` / `"false"` | 留给 Query / Builder 层使用 |

便捷工厂：`XmlWriteOptions.default_()`、`XmlWriteOptions.compactPreset()`。

#### 排版规则（一图流）

| 元素内容 | 输出 |
|---|---|
| 无子节点 | `<e/>` |
| 单个文本子节点（常见） | `<e>text</e>` |
| 含文本的混合内容 | 全内联：`<e>a<b/>c</e>`（保留空白语义） |
| 仅元素 / 注释 / 未知节点子 | 块级：每个子节点独占一行，按 `indent` 缩进 |

#### 转义

- **文本节点**：`&` / `<` / `>` → 对应实体
- **属性值**：追加 `"` → `&quot;`
- **CDATA**：不转义；若内容含 `]]>` 自动按规范拆段
- **快路径**：输入不含任何需转义字符时直接返回原字符串，零分配

#### 确定性契约

**相同 DOM + 相同 `XmlWriteOptions` → 逐字节相同的输出**。专项测试
`testDeterminism` 保证；这使 diff、缓存失效、签名校验等外围工程成为可能。

---

## 与 tinyxml2 的映射

见 [`DESIGN.md` §15](./DESIGN.md)。关键差异：

| tinyxml2 | CangjieXML | 原因 |
|---|---|---|
| `XMLHandle` / `XMLConstHandle` | `Option<T>` + `?.` / `??` | 语言特性天然覆盖 |
| `ToElement()` / `ToText()` | `match (node.kind())` | 模式匹配优雅于运行时转型 |
| `MemPool` / `StrPair` | （不提供） | GC 语言的职责边界 |
| 全局静态写出开关 | `XmlWriteOptions` | 显式配置，多线程安全 |

---

## 路线图快照

```text
M0 脚手架  ✅
  ↓
M1 DOM 内核  ✅
  ↓
M2 Writer  ✅  ← 你当前所处的稳定面（DOM + 确定性序列化）
  ↓
M3 Parser
  ↓
M4 Query + Builder
  ↓
M5 Visit
  ↓
M6 IO + Error + Options 收口
  ↓
M7 Batch / Concurrency 边界
  ↓
M8 回归 / 基准 / 文档 / v1.0 发布
```

## 许可证

TBD。
