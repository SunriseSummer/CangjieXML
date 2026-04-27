# 11 — 示例集

本章收录覆盖多包、可直接复制使用的端到端示例。本章的每一段仓颉代码都在
`src/doc_examples/doc_examples_test.cj` 中作为 `@Test` 被执行——你看到的
断言就是实际运行时的断言。

---

## 1. 构造：手工 DOM vs Builder DSL

### 手工

```cangjie
import fastxml.dom.*

let doc = XmlDocument()
doc.appendChild(doc.createDeclaration())

let root = doc.createElement("catalog")
doc.appendChild(root)

let book = doc.createElement("book")
book.setAttribute("id", "1")
book.setTextContent("SICP")
root.appendChild(book)
```

### Builder

```cangjie
import fastxml.dom.*
import fastxml.build.*

let doc = XmlDocumentBuilder()
    .declaration()
    .root("catalog") { r =>
        r.element("book") { b =>
            b.attribute("id", "1").text("SICP")
        }
    }
    .build()
```

两种结果逐字节一致。

---

## 2. Round-trip：解析 → 序列化 → 再解析

```cangjie
import fastxml.dom.*
import fastxml.parser.*
import fastxml.writer.*

let src = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" +
          "<catalog><book id=\"1\">SICP</book></catalog>"

let d1 = parseXml(src)
let xml = d1.writeToString(XmlWriteOptions.compactPreset())
let d2 = parseXml(xml)

// d1 与 d2 的根元素语义一致
d2.rootElement.getOrThrow().requiredChildElement("book").textContent()   // "SICP"
```

由于 Writer 的**确定性契约**，`d1.writeToString(opts) == d2.writeToString(opts)`
永远成立（对同一 `opts`）。

---

## 3. 空白折叠：从 pretty-printed 中提取语义值

```cangjie
import fastxml.dom.*
import fastxml.parser.*

// 典型的被人工美化过的 XML
let src = "<r>  a\n  b  </r>"

// Preserve（默认）：保留所有空白
let d1 = parseXml(src)
d1.rootElement.getOrThrow().textContent()    // "  a\n  b  "

// Collapse：折叠连续空白 + 去除纯空白
let d2 = parseXml(src, XmlParseOptions(whitespace: Collapse))
d2.rootElement.getOrThrow().textContent()    // "a b"
```

---

## 4. 类型化查询：一次拿到强类型业务值

```cangjie
import fastxml.dom.*
import fastxml.parser.*
import fastxml.query.*

let src = "<book id=\"42\" price=\"19.99\" avail=\"true\">SICP</book>"
let book = parseXml(src).rootElement.getOrThrow()

book.intAttribute("id").getOrThrow()                 // 42
book.doubleAttribute("price").getOrThrow()           // 19.99
book.boolAttribute("avail").getOrThrow()             // true

// 缺失的兜底
book.attributeOr<Int64>("stock", INT64_CODEC, 0)     // 0
```

---

## 5. 遍历：收集所有 `<book>` 的标题

### walk 风格

```cangjie
import fastxml.dom.*
import fastxml.build.*
import fastxml.visit.*
import std.collection.*

let doc = XmlDocumentBuilder()
    .root("catalog") { r =>
        r.element("book") { b => b.attribute("id", "1").text("SICP") }
        r.element("book") { b => b.attribute("id", "2").text("TAOCP") }
    }.build()

class TitleBag { public let titles: ArrayList<String> = ArrayList<String>() }
let bag = TitleBag()

walk(doc) { kind =>
    match (kind) {
        case Element(e) where e.name == "book" =>
            bag.titles.add(e.textContent()); SkipChildren
        case _ => Continue
    }
}
// bag.titles == ["SICP", "TAOCP"]
```

### Visitor 风格

```cangjie
import fastxml.dom.*
import fastxml.visit.*
import std.collection.*

class BookCollector <: XmlVisitor {
    public let titles: ArrayList<String> = ArrayList<String>()
    public func visitEnter(element: XmlElement): Bool {
        if (element.name == "book") {
            titles.add(element.textContent())
            return false     // 不下钻到 book 内部
        }
        true
    }
}

let c = BookCollector()
doc.accept(c)
// c.titles == ["SICP", "TAOCP"]
```

---

## 6. 文件 IO + 健壮错误处理

```cangjie
import fastxml.dom.*
import fastxml.io.*
import fastxml.error.*

let path = "/tmp/catalog.xml"
saveXmlToFile(doc, path)     // 先序列化到内存再一次写盘——失败不留半成品

let loaded = try {
    loadXmlFromFile(path)
} catch (e: XmlIoException) {
    match (e.error) {
        case FileNotFound(p) =>
            println("missing: ${p}"); return
        case FileReadFailed(p, msg) =>
            println("read ${p}: ${msg}"); return
        case _ =>
            throw e
    }
}
```

---

## 7. 大文档：流式写盘

```cangjie
import fastxml.dom.*
import fastxml.writer.*
import fastxml.io.*

try (sink = FileXmlSink("/tmp/big.xml")) {
    let w = XmlWriter(sink)
    w.writeDocument(doc)
}
```

相比 `saveXmlToFile` 的"整篇文档在内存中攒成一个字符串再落盘"，`FileXmlSink`
逐段 `flush`——代价是链路失败时文件可能处于半写入状态。

---

## 8. 自定义 Sink：写到任意目的地

```cangjie
import fastxml.writer.*

// 仅用作示范：把 XML 写到一个 StringBuilder，然后计算长度
class CountingSink <: XmlSink {
    public var n: Int64 = 0
    public func write(text: String): Unit { n += text.size }
    public func flush(): Unit {}
}

let s = CountingSink()
let w = XmlWriter(s, options: XmlWriteOptions.compactPreset())
w.writeDocument(doc)
// s.n 即为 UTF-16 字符数（仓颉 String.size 的含义）
```

---

## 9. CDATA：保留原文的文本

```cangjie
import fastxml.dom.*
import fastxml.writer.*

let doc = XmlDocument()
let r = doc.createElement("code")
doc.appendChild(r)
r.appendChild(doc.createText("x < 3 && y > 1", cdata: true))

doc.writeToString(XmlWriteOptions(writeDeclaration: false))
// <code><![CDATA[x < 3 && y > 1]]></code>
```

---

## 10. 自定义 codec：草图

> 本节为**示意草图**，展示如何扩展 `XmlValueCodec<T>`；不在 `doc_examples_test.cj`
> 的自动化断言范围内。生产实现需要谨慎处理 radix / 溢出 / 大小写等边界。

```cangjie
import fastxml.query.*

// 伪代码：用户按自己的格式化约定补齐 tryParse / format 两个方法即可。
public class HexInt64Codec <: XmlValueCodec<Int64> {
    public func tryParse(text: String): ?Int64 { /* ... */ None }
    public func format(value: Int64): String  { value.toString() }
}
```

一旦实现完成，`HexInt64Codec` 即可在 `attributeAs<Int64>` / `requiredAttributeAs<Int64>` /
`attributeOr<Int64>` / `childElementTextAs<Int64>` 以及 Builder 的 `attributeAs<Int64>`
中被当作一等公民使用——与内建 `INT64_CODEC` 完全对等。

---

## 11. 版本探测

```cangjie
import fastxml.*

println(CANGJIE_XML_VERSION)    // "0.1.0"
println(cangjieXmlVersion())    // "0.1.0"
```
