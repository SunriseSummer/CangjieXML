package cangjie_xml.parser

import std.unittest.*
import std.unittest.testmacro.*
import cangjie_xml.dom.*
import cangjie_xml.error.*
import cangjie_xml.writer.*

/**
 * 补充测试：parse 路径的边界与错误分支。
 *
 * 与 `parser_test.cj` 的职责分工：
 * - `parser_test.cj` —— 顺路径 / 主干特性 / round-trip 的行为覆盖；
 * - `parser_extra_test.cj`（本文件）—— 错误分支、边界输入、字符串 / 码点边界。
 *
 * 单独放一个文件是为满足"单文件 ≤ 300 行"的工程红线。
 */

@Test
func testParseEmojiNumericEntity(): Unit {
    // U+1F600 GRINNING FACE 是 4 字节 UTF-8；单独覆盖以防 Rune 构造路径回退。
    let doc = XmlDocument.parseString("<r>&#x1F600;</r>")
    @Expect(doc.rootElement.getOrThrow().textContent(), "\u{1F600}")
}

@Test
func testParseMixedDecimalAndHexEntities(): Unit {
    let doc = XmlDocument.parseString("<r>A=&#65; 中=&#x4E2D;</r>")
    @Expect(doc.rootElement.getOrThrow().textContent(), "A=A 中=中")
}

@Test
func testParseEmptyInputRejected(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("")
    } catch (e: XmlParseException) {
        if (let EmptyDocument <- e.error) { caught = true }
    }
    @Expect(caught, true)
}

@Test
func testParseOnlyWhitespaceRejected(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("   \n\t  ")
    } catch (e: XmlParseException) {
        if (let EmptyDocument <- e.error) { caught = true }
    }
    @Expect(caught, true)
}

@Test
func testParseDepthLimitHit(): Unit {
    // 构造深度 5 的嵌套；限制设为 3 必挂。
    let opts = XmlParseOptions(maxElementDepth: 3)
    var caught = false
    try {
        XmlDocument.parseString("<a><b><c><d><e/></d></c></b></a>", opts)
    } catch (e: XmlParseException) {
        if (let ElementDepthExceeded(_, _) <- e.error) { caught = true }
    }
    @Expect(caught, true)
}

@Test
func testParseDuplicateAttributeRejected(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r a='1' a='2'/>")
    } catch (e: XmlParseException) {
        if (let InvalidAttribute(name, _, _) <- e.error) {
            caught = (name == "a")
        }
    }
    @Expect(caught, true)
}

@Test
func testParseMultipleRootsRejected(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<a/><b/>")
    } catch (e: XmlParseException) {
        if (let InvalidText(_, _) <- e.error) { caught = true }
    }
    @Expect(caught, true)
}

@Test
func testParseUnterminatedEntityRejected(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r>&amp</r>")
    } catch (_: XmlParseException) {
        caught = true
    }
    @Expect(caught, true)
}

@Test
func testParseLessThanInsideAttrRejected(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r a='<bad'/>")
    } catch (e: XmlParseException) {
        if (let InvalidAttribute(_, _, _) <- e.error) { caught = true }
    }
    @Expect(caught, true)
}

@Test
func testParseWhitespaceCollapseMode(): Unit {
    let opts = XmlParseOptions(whitespace: Collapse)
    let doc = XmlDocument.parseString("<r>  hello   \n\n world  </r>", opts)
    // Collapse：内部连续空白折叠为单空格；首尾空白被吃掉（见 collapseWhitespace 实现）
    @Expect(doc.rootElement.getOrThrow().textContent(), "hello world")
}

@Test
func testParseWhitespaceCollapseDropsEmptyTextNodes(): Unit {
    // Collapse 模式下，"仅空白"的文本节点会被丢弃——这是 tinyxml2 语义。
    // 结果：<r> 之下只有 <a/>，无 Text 子节点。
    let opts = XmlParseOptions(whitespace: Collapse)
    let doc = XmlDocument.parseString("<r>  \n  <a/>  \n  </r>", opts)
    var textCount = 0
    var elemCount = 0
    for (n in doc.rootElement.getOrThrow().childNodes()) {
        match (n.kind()) {
            case Text(_) => textCount++
            case Element(_) => elemCount++
            case _ => ()
        }
    }
    @Expect(textCount, 0)
    @Expect(elemCount, 1)
}

// ====================================================================
// parse → write → parse 的 round-trip（需要同时依赖 writer），import 已在
// 文件头声明；parser 包本来就允许依赖 writer（与 parser_test.cj 同向）。
// ====================================================================

@Test
func testCdataTerminatorRoundTripsThroughWriter(): Unit {
    let doc = XmlDocument()
    let r = doc.createElement("r")
    doc.appendChild(r)
    r.appendChild(doc.createText("foo]]>bar", cdata: true))
    let sink = StringXmlSink()
    XmlWriter(sink, options: XmlWriteOptions(writeDeclaration: false, compact: true))
        .writeDocument(doc)
    let out = sink.toString()
    // 再解析：textContent 仍应等于原始串。
    let doc2 = XmlDocument.parseString(out)
    @Expect(doc2.rootElement.getOrThrow().textContent(), "foo]]>bar")
}

@Test
func testDoctypeUnknownRoundTrip(): Unit {
    let xml = "<!DOCTYPE note SYSTEM \"note.dtd\"><r/>"
    let doc = XmlDocument.parseString(xml)
    let sink = StringXmlSink()
    XmlWriter(sink, options: XmlWriteOptions(writeDeclaration: false, compact: true))
        .writeDocument(doc)
    let doc2 = XmlDocument.parseString(sink.toString())
    var unknownCount = 0
    for (n in doc2.childNodes()) {
        if (let Unknown(_) <- n.kind()) { unknownCount++ }
    }
    @Expect(unknownCount, 1)
}
