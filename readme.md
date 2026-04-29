# fastxml：仓颉高性能 xml 库

参考 [tinyxml2](https://github.com/leethomason/tinyxml2)，用仓颉语言实现了一个高性能 xml 库，充分发挥仓颉现代语言特性，更灵活易用。

- 完整 API 文档：[`doc/`](./doc/README.md)
- 性能数据：[`perf/report.md`](./perf/report.md)

## 特性

- DOM 内核、解析器、序列化器、文件 / 字节 IO 一次性齐备。
- API 贴合仓颉语言特性：`enum` / 模式匹配、`Option<T>`、`extend`、泛型。
- 类型化查询与 Builder DSL：`intAttribute` / `boolAttribute` / `XmlDocumentBuilder` 以
  声明式风格构造和读取文档。
- 两种遍历范式：函数式 `walk` 与经典 `XmlVisitor`。
- 确定性序列化：相同 DOM + 相同 `XmlWriteOptions` 产出逐字节一致的输出，天然适配
  diff / 缓存 / 签名场景。
- 单元测试 260 通过、E2E 15 例与 Python `xml.etree` 指纹一致。

## 当前状态

| 里程碑 | 名称 | 状态 |
|---|---|---|
| M0 | 项目脚手架 | 已完成 |
| M1 | DOM 内核 | 已完成 |
| M2 | Writer | 已完成 |
| M3 | Parser | 已完成 |
| M4 | Query + Builder | 已完成 |
| M5 | Visit | 已完成 |
| M6 | IO + Error + Options 收口 | 已完成 |
| M7 | Batch / Concurrency | 跳过（与 DOM 单线程契约冲突，留待后续大版本） |
| M8 | 回归 / E2E / 发布 | 已完成（15/15 fixture 与 Python `xml.etree` 指纹一致） |

## 环境要求

- 仓颉 SDK 1.0.5
- `cjpm` 在 PATH 中（`source /opt/cangjie/envsetup.sh`）
- 测试 `e2etest/excel` 案例需要 stdx

## 构建与测试

```bash
cjpm build
cjpm test
```

## 使用示例

### 手工构造 DOM 并序列化

```cangjie
import fastxml.dom.*
import fastxml.writer.*

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
import fastxml.dom.*
import fastxml.parser.*
import fastxml.error.*

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
import fastxml.dom.*
import fastxml.build.*
import fastxml.query.*

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
import fastxml.dom.*
import fastxml.visit.*

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
import fastxml.dom.*
import fastxml.io.*
import fastxml.error.*

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

## 模块结构

```
fastxml/        根包，仅含版本号
├── dom/        DOM 节点模型
├── parser/     递归下降解析器
├── writer/     序列化器、XmlSink、XmlWriteOptions
├── query/      类型化属性 / 子元素查询、codec
├── build/      Builder DSL
├── visit/      walk / XmlVisitor
├── io/         文件 / 字节 IO
├── error/      错误类型
└── internal/   内部工具，不对外开放
```

依赖方向严格单向（`dom` 在最下层），所有扩展通过 `extend` 单向植入到 DOM。

## 与 tinyxml2 的对应关系

| tinyxml2 | CangjieXML | 取舍 |
|---|---|---|
| `XMLHandle` / `XMLConstHandle` | `Option<T>` + `?.` / `??` | 语言特性天然覆盖 |
| `ToElement()` / `ToText()` | `match (node.kind())` | 模式匹配取代运行时转型 |
| `MemPool` / `StrPair` | （不提供） | GC 语言的职责边界 |
| 全局静态写出开关 | `XmlWriteOptions` struct | 显式配置、线程安全 |
| `XMLPrinter` | `XmlWriter` + `XmlSink` | Writer 与 Sink 解耦 |
| `XMLVisitor` | `XmlVisitor` + `walk` | 同时提供函数式 API |

完整对照见 [`DESIGN.md` §15](./DESIGN.md)。

## 路线图

见 [`ROADMAP.md`](./ROADMAP.md)。

## 许可证

待定。
