package cangjie_xml.doc_examples

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import std.fs.*

import cangjie_xml.*
import cangjie_xml.dom.*
import cangjie_xml.parser.*
import cangjie_xml.writer.*
import cangjie_xml.query.*
import cangjie_xml.build.*
import cangjie_xml.visit.*
import cangjie_xml.io.*
import cangjie_xml.error.*

// ======================================================================
// 文档示例验证套件
//
// 本文件里的每一个 @Test 都精确对应 `doc/*.md` 中的一段仓颉代码示例。
// 目的是：一旦公共 API 发生不兼容的变动，`cjpm test` 会立即报错，从而把
// "文档与代码漂移"问题挡在合入之前。
//
// 与其他 _test.cj 的分工：
//   - `src/dom/*_test.cj`、`src/writer/*_test.cj` 等覆盖细粒度行为边界；
//   - 本文件则专注于"文档示例的外观契约"（输出串、典型返回值等）。
// ======================================================================

// ----------------------------------------------------------------------
// 02 快速上手：构造 + 写出（美化）
// ----------------------------------------------------------------------
@Test
func docGettingStartedBuildAndPrettyPrint(): Unit {
    let doc = XmlDocument()
    doc.appendChild(doc.createDeclaration())

    let root = doc.createElement("catalog")
    doc.appendChild(root)

    let book = doc.createElement("book")
    book.setAttribute("id", "1")
    book.setTextContent("SICP")
    root.appendChild(book)

    let s = doc.writeToString()
    @Expect(s,
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
        "<catalog>\n" +
        "    <book id=\"1\">SICP</book>\n" +
        "</catalog>\n")
}

@Test
func docGettingStartedCompactPrint(): Unit {
    let doc = XmlDocument()
    doc.appendChild(doc.createDeclaration())
    let root = doc.createElement("catalog")
    doc.appendChild(root)
    let book = doc.createElement("book")
    book.setAttribute("id", "1")
    book.setTextContent("SICP")
    root.appendChild(book)

    let s = doc.writeToString(XmlWriteOptions.compactPreset())
    @Expect(s,
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" +
        "<catalog><book id=\"1\">SICP</book></catalog>")
}

// ----------------------------------------------------------------------
// 02 快速上手：解析
// ----------------------------------------------------------------------
@Test
func docGettingStartedParseString(): Unit {
    let doc = XmlDocument.parseString(
        "<catalog><book id=\"1\">SICP</book></catalog>")
    let root = doc.rootElement.getOrThrow()
    let book = root.firstChildElement(name: Some("book")).getOrThrow()
    @Expect(book.textContent(), "SICP")
}

// ----------------------------------------------------------------------
// 03 DOM：文档级便捷访问、工厂自绑定
// ----------------------------------------------------------------------
@Test
func docDomEmptyDocumentDefaults(): Unit {
    let doc = XmlDocument()
    @Expect(doc.rootElement.isNone(), true)
    @Expect(doc.declaration.isNone(), true)
    @Expect(doc.hasBom, false)
    @Expect(doc.writeBom, false)
    @Assert(refEq(doc.document, doc))
}

@Test
func docDomFactoryBinding(): Unit {
    let doc = XmlDocument()
    let e = doc.createElement("r")
    let t = doc.createText("x")
    let c = doc.createComment("c")
    let d = doc.createDeclaration()
    @Assert(refEq(e.document, doc))
    @Assert(refEq(t.document, doc))
    @Assert(refEq(c.document, doc))
    @Assert(refEq(d.document, doc))
}

@Test
func docDomTopLevelKindsIterate(): Unit {
    let doc = XmlDocument()
    doc.appendChild(doc.createDeclaration())
    let root = doc.createElement("catalog")
    doc.appendChild(root)
    doc.appendChild(doc.createComment("end"))

    var kinds = ""
    for (n in doc.childNodes()) {
        match (n.kind()) {
            case Declaration(_) => kinds += "D"
            case Element(_)     => kinds += "E"
            case Comment(_)     => kinds += "C"
            case _              => kinds += "?"
        }
    }
    @Expect(kinds, "DEC")
}

@Test
func docDomAttributesOrderAndHas(): Unit {
    let doc = XmlDocument()
    let e = doc.createElement("book")
    e.setAttribute("id", "1")
    e.setAttribute("lang", "en")
    doc.appendChild(e)

    @Expect(e.attribute("id").getOrThrow(), "1")
    @Expect(e.attributeCount(), 2)
    @Expect(e.hasAttribute("lang"), true)
    @Expect(e.hasAttribute("id", value: Some("1")), true)
    @Expect(e.hasAttribute("id", value: Some("9")), false)

    // 顺序保留
    var names = ""
    for (a in e.attributes()) { names += a.name; names += "," }
    @Expect(names, "id,lang,")
}

// ----------------------------------------------------------------------
// 04 Parser：空白折叠
// ----------------------------------------------------------------------
@Test
func docParserPreserveVsCollapse(): Unit {
    let src = "<r>  a\n  b  </r>"
    let d1 = XmlDocument.parseString(src)
    @Expect(d1.rootElement.getOrThrow().textContent(), "  a\n  b  ")

    let d2 = XmlDocument.parseString(src, XmlParseOptions(whitespace: Collapse))
    @Expect(d2.rootElement.getOrThrow().textContent(), "a b")
}

@Test
func docParserSelfClosingAndAttributes(): Unit {
    let doc = XmlDocument.parseString("<book id=\"42\" lang='en'/>")
    let r = doc.rootElement.getOrThrow()
    @Expect(r.name, "book")
    @Expect(r.attribute("id").getOrThrow(), "42")
    @Expect(r.attribute("lang").getOrThrow(), "en")
}

// ----------------------------------------------------------------------
// 05 Writer：空文档 / 自闭合 / 属性顺序 / 转义
// ----------------------------------------------------------------------
@Test
func docWriterEmptyDocumentDefault(): Unit {
    let doc = XmlDocument()
    @Expect(doc.writeToString(), "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
}

@Test
func docWriterSelfClosing(): Unit {
    let doc = XmlDocument()
    doc.appendChild(doc.createElement("root"))
    @Expect(doc.writeToString(XmlWriteOptions(writeDeclaration: false)),
        "<root/>\n")
}

@Test
func docWriterAttributeEscaping(): Unit {
    let doc = XmlDocument()
    let e = doc.createElement("e")
    e.setAttribute("x", "a&b<c>d\"e")
    doc.appendChild(e)
    @Expect(doc.writeToString(XmlWriteOptions(writeDeclaration: false)),
        "<e x=\"a&amp;b&lt;c&gt;d&quot;e\"/>\n")
}

@Test
func docWriterTextEscaping(): Unit {
    let doc = XmlDocument()
    let e = doc.createElement("e")
    doc.appendChild(e)
    e.setTextContent("a<b>c&d\"e")
    // 文本节点的 `"` 不需转义
    @Expect(doc.writeToString(XmlWriteOptions(writeDeclaration: false)),
        "<e>a&lt;b&gt;c&amp;d\"e</e>\n")
}

@Test
func docWriterCustomIndent(): Unit {
    let doc = XmlDocument()
    let root = doc.createElement("catalog")
    doc.appendChild(root)
    let book = doc.createElement("book")
    book.setAttribute("id", "1")
    book.setTextContent("SICP")
    root.appendChild(book)

    let s = doc.writeToString(XmlWriteOptions(writeDeclaration: false, indent: "  "))
    @Expect(s,
        "<catalog>\n" +
        "  <book id=\"1\">SICP</book>\n" +
        "</catalog>\n")
}

// ----------------------------------------------------------------------
// 05 Writer：确定性
// ----------------------------------------------------------------------
@Test
func docWriterDeterminism(): Unit {
    let doc = XmlDocument()
    let root = doc.createElement("r")
    doc.appendChild(root)
    let e = doc.createElement("e")
    e.setAttribute("a", "1")
    e.setAttribute("b", "2")
    root.appendChild(e)
    let opts = XmlWriteOptions.default_()
    let s1 = doc.writeToString(opts)
    let s2 = doc.writeToString(opts)
    @Expect(s1, s2)
}

// ----------------------------------------------------------------------
// 06 Query：类型化属性、兜底、必填
// ----------------------------------------------------------------------
@Test
func docQueryTypedAttributes(): Unit {
    let src = "<book id=\"42\" price=\"19.99\" avail=\"true\">SICP</book>"
    let book = XmlDocument.parseString(src).rootElement.getOrThrow()

    @Expect(book.intAttribute("id").getOrThrow(), 42)
    let price = book.doubleAttribute("price").getOrThrow()
    @Expect(price > 19.98 && price < 20.0, true)
    @Expect(book.boolAttribute("avail").getOrThrow(), true)
    @Expect(book.doubleAttribute("missing").isNone(), true)

    // 兜底
    @Expect(book.attributeOr<Int64>("stock", INT64_CODEC, 0), 0)
}

@Test
func docQueryRequiredAttributeThrowsOnMissing(): Unit {
    let doc = XmlDocument()
    let e = doc.createElement("book")
    doc.appendChild(e)
    var caught = false
    try {
        let _ = e.requiredAttribute("missing")
    } catch (_: XmlException) {
        caught = true
    }
    @Expect(caught, true)
}

@Test
func docQueryChildElementText(): Unit {
    let doc = XmlDocument.parseString(
        "<store><name>SICP</name><price>42.5</price></store>")
    let root = doc.rootElement.getOrThrow()

    @Expect(root.childElementText("name").getOrThrow(), "SICP")
    let price = root.childElementTextAs<Float64>("price", FLOAT64_CODEC)
        .getOrThrow()
    @Expect(price > 42.4 && price < 42.6, true)
    @Expect(root.requiredChildElement("name").textContent(), "SICP")
}

// ----------------------------------------------------------------------
// 07 Builder：DSL + 输出
// ----------------------------------------------------------------------
@Test
func docBuilderBasicDSL(): Unit {
    let doc = XmlDocumentBuilder()
        .declaration()
        .root("catalog") { r =>
            r.element("book") { b =>
                b.attribute("id", "1").text("SICP")
            }
            r.element("book") { b =>
                b.attribute("id", "2").text("TAOCP")
            }
        }
        .build()

    let root = doc.rootElement.getOrThrow()
    @Expect(root.name, "catalog")
    let books = root.childElementTexts("book")
    @Expect(books.size, 2)
    @Expect(books[0], "SICP")
    @Expect(books[1], "TAOCP")
}

@Test
func docBuilderDeclarationIdempotent(): Unit {
    // declaration() 多次调用不重复写入
    let doc = XmlDocumentBuilder().declaration().declaration().root("r").build()
    var count = 0
    for (n in doc.childNodes()) {
        if (let Declaration(_) <- n.kind()) { count++ }
    }
    @Expect(count, 1)
}

@Test
func docBuilderTypedAttribute(): Unit {
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

    let book = doc.rootElement.getOrThrow().requiredChildElement("book")
    @Expect(book.intAttribute("id").getOrThrow(), 1)
    @Expect(book.boolAttribute("avail").getOrThrow(), true)
    @Expect(book.textContent(), "SICP")
}

@Test
func docBuilderMixedTextAndChild(): Unit {
    let doc = XmlDocumentBuilder()
        .root("p") { p =>
            p.text("Hello ")
             .element("b") { b => b.text("world") }
             .text("!")
        }
        .build()
    let s = doc.writeToString(XmlWriteOptions(writeDeclaration: false))
    @Expect(s, "<p>Hello <b>world</b>!</p>\n")
}

@Test
func docBuilderCdata(): Unit {
    let doc = XmlDocumentBuilder()
        .root("code") { c =>
            c.text("x = 1; y = 2;", cdata: true)
        }
        .build()
    let s = doc.writeToString(XmlWriteOptions(writeDeclaration: false))
    @Expect(s, "<code><![CDATA[x = 1; y = 2;]]></code>\n")
}

// ----------------------------------------------------------------------
// 08 Visit：walk + XmlVisitor
// ----------------------------------------------------------------------
class DocCounter { public var n: Int64 = 0 }

class DocTitleBag { public let titles: ArrayList<String> = ArrayList<String>() }

@Test
func docVisitWalkCountsBooks(): Unit {
    let doc = XmlDocumentBuilder()
        .root("catalog") { r =>
            r.element("book") { b => b.attribute("id", "1").text("SICP") }
            r.element("book") { b => b.attribute("id", "2").text("TAOCP") }
        }.build()

    let count = DocCounter()
    walk(doc) { kind =>
        match (kind) {
            case Element(e) where e.name == "book" =>
                count.n++
                SkipChildren
            case _ => Continue
        }
    }
    @Expect(count.n, 2)
}

@Test
func docVisitWalkCollectsTitles(): Unit {
    let doc = XmlDocumentBuilder()
        .root("catalog") { r =>
            r.element("book") { b => b.text("SICP") }
            r.element("book") { b => b.text("TAOCP") }
        }.build()

    let bag = DocTitleBag()
    walk(doc) { kind =>
        match (kind) {
            case Element(e) where e.name == "book" =>
                bag.titles.add(e.textContent())
                SkipChildren
            case _ => Continue
        }
    }
    @Expect(bag.titles.size, 2)
    @Expect(bag.titles[0], "SICP")
    @Expect(bag.titles[1], "TAOCP")
}

class DocBookCollector <: XmlVisitor {
    public let titles: ArrayList<String> = ArrayList<String>()
    public func visitEnter(element: XmlElement): Bool {
        if (element.name == "book") {
            titles.add(element.textContent())
            return false     // 不下钻
        }
        true
    }
}

@Test
func docVisitXmlVisitorCollectsTitles(): Unit {
    let doc = XmlDocumentBuilder()
        .root("catalog") { r =>
            r.element("book") { b => b.text("SICP") }
            r.element("book") { b => b.text("TAOCP") }
        }.build()

    let c = DocBookCollector()
    doc.accept(c)
    @Expect(c.titles.size, 2)
    @Expect(c.titles[0], "SICP")
    @Expect(c.titles[1], "TAOCP")
}

// ----------------------------------------------------------------------
// 09 IO：文件 round-trip + 字节 round-trip
// ----------------------------------------------------------------------
const DOC_TMP_ROOT: String = "/tmp/cangjie_xml_doc_examples"

class DocTempFile {
    public let path: String
    public init(name: String) {
        if (!exists(Path(DOC_TMP_ROOT))) {
            Directory.create(Path(DOC_TMP_ROOT), recursive: true)
        }
        this.path = "${DOC_TMP_ROOT}/${name}"
        removeIfExists(Path(this.path), recursive: false)
    }
    public func cleanup(): Unit {
        removeIfExists(Path(path), recursive: false)
    }
}

func docMakeSampleDoc(): XmlDocument {
    XmlDocumentBuilder()
        .declaration()
        .root("catalog") { r =>
            r.element("book") { b =>
                b.attribute("id", "1").text("SICP")
            }
        }
        .build()
}

@Test
func docIoFileRoundTrip(): Unit {
    let tmp = DocTempFile("round_trip.xml")
    try {
        saveXmlToFile(docMakeSampleDoc(), tmp.path)
        let loaded = loadXmlFromFile(tmp.path)
        let root = loaded.rootElement.getOrThrow()
        @Expect(root.name, "catalog")
        @Expect(root.requiredChildElement("book").intAttribute("id").getOrThrow(), 1)
    } finally {
        tmp.cleanup()
    }
}

@Test
func docIoBytesRoundTrip(): Unit {
    let doc = docMakeSampleDoc()
    let bytes = writeXmlToBytes(doc)
    @Expect(bytes.size > 0, true)
    let back = parseXmlBytes(bytes)
    @Expect(back.rootElement.getOrThrow().name, "catalog")
}

@Test
func docIoFileNotFoundIsXmlIoException(): Unit {
    var matched = false
    try {
        let _ = loadXmlFromFile("${DOC_TMP_ROOT}/definitely_does_not_exist.xml")
    } catch (e: XmlIoException) {
        match (e.error) {
            case FileNotFound(_) => matched = true
            case _ => ()
        }
    }
    @Expect(matched, true)
}

// ----------------------------------------------------------------------
// 10 错误模型：DOM 不变量触发 XmlException
// ----------------------------------------------------------------------
@Test
func docErrorsDuplicateRootRejected(): Unit {
    let doc = XmlDocument()
    doc.appendChild(doc.createElement("a"))
    var caught = false
    try {
        doc.appendChild(doc.createElement("b"))
    } catch (_: XmlException) {
        caught = true
    }
    @Expect(caught, true)
}

@Test
func docErrorsParseExceptionCarriesXmlError(): Unit {
    var matched = false
    try {
        let _ = XmlDocument.parseString("<a></b>")
    } catch (e: XmlParseException) {
        match (e.error) {
            case MismatchedElement(_, _, _) => matched = true
            case _ => ()
        }
    }
    @Expect(matched, true)
}

// ----------------------------------------------------------------------
// 11 示例集：Round-trip 确定性
// ----------------------------------------------------------------------
@Test
func docExampleRoundTripDeterminism(): Unit {
    let src = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" +
              "<catalog><book id=\"1\">SICP</book></catalog>"
    let d1 = XmlDocument.parseString(src)
    let xml = d1.writeToString(XmlWriteOptions.compactPreset())
    let d2 = XmlDocument.parseString(xml)
    @Expect(d2.rootElement.getOrThrow()
        .requiredChildElement("book").textContent(), "SICP")
    // 对相同 DOM + options，两次序列化完全一致
    @Expect(
        d1.writeToString(XmlWriteOptions.compactPreset()),
        d2.writeToString(XmlWriteOptions.compactPreset()))
}

// ----------------------------------------------------------------------
// 版本探测
// ----------------------------------------------------------------------
@Test
func docVersionProbe(): Unit {
    @Expect(CANGJIE_XML_VERSION, "0.1.0")
    @Expect(cangjieXmlVersion(), CANGJIE_XML_VERSION)
}
