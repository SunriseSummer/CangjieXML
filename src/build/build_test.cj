package tinyxml2.build

import std.unittest.*
import std.unittest.testmacro.*
import tinyxml2.dom.*
import tinyxml2.query.*
import tinyxml2.writer.*
import tinyxml2.parser.*

// ====================================================================
// XmlDocumentBuilder / XmlElementBuilder 基础
// ====================================================================

@Test
func testBuildEmptyDocument(): Unit {
    let doc = XmlDocumentBuilder().root("r").build()
    @Expect(doc.rootElement.getOrThrow().name, "r")
}

@Test
func testBuildWithDeclaration(): Unit {
    let doc = XmlDocumentBuilder().declaration().root("r").build()
    @Expect(doc.declaration.isSome(), true)
    @Expect(doc.rootElement.getOrThrow().name, "r")
}

@Test
func testBuildDeclarationIdempotent(): Unit {
    // 调 declaration 两次只应该插入一次
    let doc = XmlDocumentBuilder().declaration().declaration().root("r").build()
    var count = 0
    for (n in doc.childNodes()) {
        if (let Declaration(_) <- n.kind()) { count++ }
    }
    @Expect(count, 1)
}

@Test
func testBuildNestedElements(): Unit {
    let doc = XmlDocumentBuilder()
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
    let books = root.childElementTexts("book")
    @Expect(books.size, 2)
    @Expect(books[0], "SICP")
    @Expect(books[1], "TAOCP")
}

@Test
func testBuildAttributeAs(): Unit {
    let doc = XmlDocumentBuilder()
        .root("row") { r =>
            r.attributeAs<Int64>("id", 42, INT64_CODEC)
             .attributeAs<Bool>("ok", true, BOOL_CODEC)
        }
        .build()
    let r = doc.rootElement.getOrThrow()
    @Expect(r.attribute("id").getOrThrow(), "42")
    @Expect(r.attribute("ok").getOrThrow(), "true")
}

@Test
func testBuildTextAndCdata(): Unit {
    let doc = XmlDocumentBuilder()
        .root("r") { r =>
            r.text("plain ")
             .text("<raw>", cdata: true)
        }
        .build()
    let root = doc.rootElement.getOrThrow()
    @Expect(root.textContent(), "plain <raw>")
    // 第二个子节点应当是 CDATA
    var cdataFound = false
    for (n in root.childNodes()) {
        if (let Text(t) <- n.kind()) {
            if (t.isCdata) { cdataFound = true }
        }
    }
    @Expect(cdataFound, true)
}

@Test
func testBuildComment(): Unit {
    let doc = XmlDocumentBuilder()
        .comment("top-level note")
        .root("r") { r =>
            r.comment("inner note").text("x")
        }
        .build()
    var topCommentCount = 0
    for (n in doc.childNodes()) {
        if (let Comment(_) <- n.kind()) { topCommentCount++ }
    }
    @Expect(topCommentCount, 1)

    var innerCommentCount = 0
    for (n in doc.rootElement.getOrThrow().childNodes()) {
        if (let Comment(_) <- n.kind()) { innerCommentCount++ }
    }
    @Expect(innerCommentCount, 1)
}

@Test
func testBuilderReturnsRegularDom(): Unit {
    // Builder 的产物应当能直接参与后续 DOM 操作（不是平行体系）
    let doc = XmlDocumentBuilder().root("r").build()
    let extra = doc.createElement("child")
    doc.rootElement.getOrThrow().appendChild(extra)
    @Expect(doc.rootElement.getOrThrow().childElement("child").isSome(), true)
}

// ====================================================================
// End-to-end：builder → writer → parser → query
// ====================================================================

@Test
func testRoundTripBuildWriteParseQuery(): Unit {
    let doc1 = XmlDocumentBuilder()
        .declaration()
        .root("catalog") { r =>
            r.element("book") { b =>
                b.attributeAs<Int64>("id", 1, INT64_CODEC)
                 .attributeAs<Bool>("avail", true, BOOL_CODEC)
                 .text("SICP")
            }
            r.element("book") { b =>
                b.attributeAs<Int64>("id", 2, INT64_CODEC)
                 .attributeAs<Bool>("avail", false, BOOL_CODEC)
                 .text("TAOCP")
            }
        }
        .build()

    // Writer
    let sink = StringXmlSink()
    XmlWriter(sink, options: XmlWriteOptions.compactPreset()).writeDocument(doc1)
    let xml = sink.toString()

    // Parser
    let doc2 = parseXml(xml)
    let root = doc2.rootElement.getOrThrow()

    // Query
    var idSum: Int64 = 0
    var availCount = 0
    for (b in root.childElements(name: Some("book"))) {
        idSum += b.intAttribute("id").getOrThrow()
        if (b.boolAttribute("avail").getOrThrow()) { availCount++ }
    }
    @Expect(idSum, 3) // 1 + 2
    @Expect(availCount, 1)

    // requiredChildElement + textContent
    @Expect(root.requiredChildElement("book").textContent(), "SICP")
}

@Test
func testRootUniquenessEnforced(): Unit {
    var caught = false
    try {
        XmlDocumentBuilder().root("a").root("b").build()
    } catch (_: Exception) {
        caught = true
    }
    @Expect(caught, true)
}
