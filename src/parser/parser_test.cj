package cangjie_xml.parser

import std.unittest.*
import std.unittest.testmacro.*
import cangjie_xml.dom.*
import cangjie_xml.error.*
import cangjie_xml.writer.*

// ====================================================================
// M3 Parser：顺路径行为测试。
//
// 组织方式：核心输入用例覆盖主要语法分支，round-trip 测试验证
// "parse → write → 再 parse → 语义一致"。
// ====================================================================

@Test
func testParseSelfClosingRoot(): Unit {
    let doc = XmlDocument.parseString("<root/>")
    match (doc.rootElement) {
        case Some(r) => @Expect(r.name, "root")
        case None => @Assert(false)
    }
}

@Test
func testParseRootWithAttributes(): Unit {
    let doc = XmlDocument.parseString("<book id=\"42\" lang='en'/>")
    let r = doc.rootElement.getOrThrow()
    @Expect(r.name, "book")
    @Expect(r.attribute("id").getOrThrow(), "42")
    @Expect(r.attribute("lang").getOrThrow(), "en")
}

@Test
func testParseWithDeclaration(): Unit {
    let doc = XmlDocument.parseString("<?xml version=\"1.0\"?><r/>")
    @Expect(doc.declaration.isSome(), true)
    @Expect(doc.rootElement.getOrThrow().name, "r")
}

@Test
func testParseCommentsAtTop(): Unit {
    let doc = XmlDocument.parseString("<!-- hi --><r/><!-- bye -->")
    // 根元素仍然正确
    @Expect(doc.rootElement.getOrThrow().name, "r")
    // 顶层节点应当包含两个 Comment + 一个 Element
    var commentCount = 0
    for (n in doc.childNodes()) {
        if (let Comment(_) <- n.kind()) { commentCount++ }
    }
    @Expect(commentCount, 2)
}

@Test
func testParseNestedElementsAndText(): Unit {
    let src = "<root><a>hello</a><b>world</b></root>"
    let doc = XmlDocument.parseString(src)
    let root = doc.rootElement.getOrThrow()
    var names = ""
    var texts = ""
    for (c in root.childElements()) {
        names += c.name
        texts += c.textContent()
    }
    @Expect(names, "ab")
    @Expect(texts, "helloworld")
}

@Test
func testParseEntityReferences(): Unit {
    let doc = XmlDocument.parseString(
        "<r t=\"a&amp;b&lt;c&gt;d&quot;e&apos;f\">1&amp;2&#65;&#x42;</r>")
    let r = doc.rootElement.getOrThrow()
    @Expect(r.attribute("t").getOrThrow(), "a&b<c>d\"e'f")
    @Expect(r.textContent(), "1&2AB")
}

@Test
func testParseCdata(): Unit {
    let doc = XmlDocument.parseString("<r><![CDATA[raw & <stuff>]]></r>")
    let r = doc.rootElement.getOrThrow()
    // textContent 应返回 CDATA 的字面内容（不再做实体解码）
    @Expect(r.textContent(), "raw & <stuff>")
    // 且应该是一个 CDATA 标记的 XmlText
    match (r.firstChild) {
        case Some(n) =>
            match (n.kind()) {
                case Text(t) =>
                    @Expect(t.isCdata, true)
                    @Expect(t.value, "raw & <stuff>")
                case _ => @Assert(false)
            }
        case None => @Assert(false)
    }
}

@Test
func testParseDoctypeIsUnknown(): Unit {
    let doc = XmlDocument.parseString("<!DOCTYPE html><r/>")
    // 顶层第一个非声明节点应为 XmlUnknown
    var firstUnknownFound = false
    for (n in doc.childNodes()) {
        if (let Unknown(_) <- n.kind()) {
            firstUnknownFound = true
            break
        }
    }
    @Expect(firstUnknownFound, true)
}

@Test
func testParseMixedContent(): Unit {
    let doc = XmlDocument.parseString("<r>hello <b>bold</b> world</r>")
    let r = doc.rootElement.getOrThrow()
    @Expect(r.textContent(), "hello bold world")
}

@Test
func testParseRoundTripSimple(): Unit {
    let original = "<root><a id=\"1\"/><b>text</b></root>"
    let doc1 = XmlDocument.parseString(original)
    let sink1 = StringXmlSink()
    XmlWriter(sink1, options: XmlWriteOptions.compactPreset()).writeDocument(doc1)
    let emitted = sink1.toString()
    // 再 parse 一次，结构等价
    let doc2 = XmlDocument.parseString(emitted)
    @Expect(doc2.rootElement.getOrThrow().name, "root")
    let sink2 = StringXmlSink()
    XmlWriter(sink2, options: XmlWriteOptions.compactPreset()).writeDocument(doc2)
    @Expect(emitted, sink2.toString())
}

@Test
func testParseRoundTripWithEntities(): Unit {
    // 原文里的 & < > 等在写出时会被转义，parse 后文本内容应一致
    let expectedText = "a & b < c"
    let doc1 = XmlDocument()
    let root = doc1.createElement("r")
    doc1.appendChild(root)
    root.appendChild(doc1.createText(expectedText))
    let sink = StringXmlSink()
    XmlWriter(sink, options: XmlWriteOptions.compactPreset()).writeDocument(doc1)
    let doc2 = XmlDocument.parseString(sink.toString())
    @Expect(doc2.rootElement.getOrThrow().textContent(), expectedText)
}

// ====================================================================
// 错误路径
// ====================================================================

@Test
func testErrorEmptyDocument(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("   ")
    } catch (e: XmlParseException) {
        if (let EmptyDocument <- e.error) { caught = true }
    }
    @Expect(caught, true)
}

@Test
func testErrorMismatchedEndTag(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<a></b>")
    } catch (e: XmlParseException) {
        if (let MismatchedElement(_, _, _) <- e.error) { caught = true }
    }
    @Expect(caught, true)
}

@Test
func testErrorMultipleRoots(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<a/><b/>")
    } catch (e: XmlParseException) {
        caught = true
    }
    @Expect(caught, true)
}

@Test
func testErrorUnknownEntity(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r>&unknown;</r>")
    } catch (e: XmlParseException) {
        if (let InvalidText(_, _) <- e.error) { caught = true }
    }
    @Expect(caught, true)
}

@Test
func testErrorUnterminatedAttribute(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r a=\"oops/>")
    } catch (e: XmlParseException) {
        if (let InvalidAttribute(_, _, _) <- e.error) { caught = true }
    }
    @Expect(caught, true)
}

@Test
func testErrorLessThanInAttribute(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r a=\"<\"/>")
    } catch (e: XmlParseException) {
        if (let InvalidAttribute(_, _, _) <- e.error) { caught = true }
    }
    @Expect(caught, true)
}

@Test
func testErrorDepthExceeded(): Unit {
    let opts = XmlParseOptions(maxElementDepth: 3)
    var caught = false
    try {
        XmlDocument.parseString("<a><b><c><d/></c></b></a>", opts)
    } catch (e: XmlParseException) {
        if (let ElementDepthExceeded(_, _) <- e.error) { caught = true }
    }
    @Expect(caught, true)
}

// ====================================================================
// 空白策略
// ====================================================================

@Test
func testCollapseWhitespace(): Unit {
    let opts = XmlParseOptions(whitespace: Collapse)
    let doc = XmlDocument.parseString("<r>  hello\n  world  </r>", opts)
    @Expect(doc.rootElement.getOrThrow().textContent(), "hello world")
}

@Test
func testPreserveWhitespaceByDefault(): Unit {
    let doc = XmlDocument.parseString("<r>  hello\n  world  </r>")
    @Expect(doc.rootElement.getOrThrow().textContent(), "  hello\n  world  ")
}

@Test
func testCollapseSkipsWhitespaceOnlyBetweenElements(): Unit {
    let opts = XmlParseOptions(whitespace: Collapse)
    let doc = XmlDocument.parseString("<r>\n  <a/>\n  <b/>\n</r>", opts)
    let root = doc.rootElement.getOrThrow()
    var elementCount = 0
    var textCount = 0
    for (n in root.childNodes()) {
        match (n.kind()) {
            case Element(_) => elementCount++
            case Text(_) => textCount++
            case _ => ()
        }
    }
    @Expect(elementCount, 2)
    @Expect(textCount, 0)
}

// ====================================================================
// BOM 处理
// ====================================================================

@Test
func testBomAccepted(): Unit {
    let withBom = "\u{FEFF}<r/>"
    let doc = XmlDocument.parseString(withBom)
    @Expect(doc.rootElement.getOrThrow().name, "r")
}

@Test
func testBomRejectedWhenDisabled(): Unit {
    let withBom = "\u{FEFF}<r/>"
    let opts = XmlParseOptions(acceptBom: false)
    var caught = false
    try {
        XmlDocument.parseString(withBom, opts)
    } catch (e: XmlParseException) {
        if (let InvalidEncoding(_, _) <- e.error) { caught = true }
    }
    @Expect(caught, true)
}
