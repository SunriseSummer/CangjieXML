/*
 * reader — XmlReader 单元测试
 */
package cangjie_xml.reader

import std.unittest.*
import std.collection.*
import cangjie_xml.core.*
import cangjie_xml.parser.*

/* ---------- 工具：读出完整 (type, name) 序列 ---------- */

func walk(r: XmlReader): ArrayList<(ReaderNodeType, String)> {
    let out = ArrayList<(ReaderNodeType, String)>()
    while (r.read()) {
        out.add((r.nodeType(), r.localName()))
    }
    return out
}

func types(r: XmlReader): ArrayList<ReaderNodeType> {
    let out = ArrayList<ReaderNodeType>()
    while (r.read()) {
        out.add(r.nodeType())
    }
    return out
}

/* ---------- 基础遍历 ---------- */

@Test
public func testInitialState(): Unit {
    let r = XmlReader.fromString("<a/>")
    @Expect(r.readerState() == ReaderState.Initial, true)
    @Expect(r.nodeType() == ReaderNodeType.None, true)
    @Expect(r.depth(), -1)
}

@Test
public func testSimpleEmptyElement(): Unit {
    let r = XmlReader.fromString("<a/>")
    @Expect(r.read(), true) // StartDocument → XmlDeclaration
    @Expect(r.nodeType() == ReaderNodeType.XmlDeclaration, true)
    @Expect(r.read(), true) // StartElement a
    @Expect(r.nodeType() == ReaderNodeType.Element, true)
    @Expect(r.localName(), "a")
    @Expect(r.isEmptyElement(), true)
    @Expect(r.depth(), 0)
    @Expect(r.read(), true) // EndDocument (skipped EndElement since empty)
    @Expect(r.nodeType() == ReaderNodeType.EndDocument, true)
    @Expect(r.read(), false)
    @Expect(r.isEof(), true)
}

@Test
public func testElementWithText(): Unit {
    let r = XmlReader.fromString("<a>hello</a>")
    let seq = walk(r)
    @Expect(seq.size, 5)
    @Expect(seq[0][0] == ReaderNodeType.XmlDeclaration, true)
    @Expect(seq[1][0] == ReaderNodeType.Element, true)
    @Expect(seq[1][1], "a")
    @Expect(seq[2][0] == ReaderNodeType.Text, true)
    @Expect(seq[3][0] == ReaderNodeType.EndElement, true)
    @Expect(seq[3][1], "a")
    @Expect(seq[4][0] == ReaderNodeType.EndDocument, true)
}

@Test
public func testNestedElementsDepth(): Unit {
    let r = XmlReader.fromString("<a><b><c/></b></a>")
    let depths = ArrayList<Int64>()
    let kinds = ArrayList<ReaderNodeType>()
    while (r.read()) {
        kinds.add(r.nodeType())
        depths.add(r.depth())
    }
    // 序列：XmlDecl, E(a), E(b), E(c-empty), EE(b), EE(a), EndDocument
    @Expect(kinds.size, 7)
    @Expect(kinds[1] == ReaderNodeType.Element, true)  // a depth 0
    @Expect(depths[1], 0)
    @Expect(kinds[2] == ReaderNodeType.Element, true)  // b depth 1
    @Expect(depths[2], 1)
    @Expect(kinds[3] == ReaderNodeType.Element, true)  // c depth 2, empty
    @Expect(depths[3], 2)
    @Expect(kinds[4] == ReaderNodeType.EndElement, true) // </b>
    @Expect(kinds[5] == ReaderNodeType.EndElement, true) // </a>
    @Expect(kinds[6] == ReaderNodeType.EndDocument, true)
}

@Test
public func testMixedContent(): Unit {
    let r = XmlReader.fromString("<a>pre<b>in</b>post</a>")
    let kinds = types(r)
    // Decl, E(a), Text "pre", E(b), Text "in", EE(b), Text "post", EE(a), EndDoc
    @Expect(kinds.size, 9)
    @Expect(kinds[2] == ReaderNodeType.Text, true)
    @Expect(kinds[4] == ReaderNodeType.Text, true)
    @Expect(kinds[6] == ReaderNodeType.Text, true)
}

@Test
public func testCdata(): Unit {
    let r = XmlReader.fromString("<a><![CDATA[raw & <t>]]></a>")
    while (r.read()) {
        if (r.nodeType() == ReaderNodeType.Cdata) {
            @Expect(r.value(), "raw & <t>")
            return
        }
    }
    @Fail("no cdata node seen")
}

@Test
public func testComment(): Unit {
    let r = XmlReader.fromString("<!-- hi --><a/>")
    @Expect(r.read(), true) // XmlDecl
    @Expect(r.read(), true)
    @Expect(r.nodeType() == ReaderNodeType.Comment, true)
    @Expect(r.value(), " hi ")
}

@Test
public func testPi(): Unit {
    let r = XmlReader.fromString("<?pi d?><a/>")
    @Expect(r.read(), true) // XmlDecl
    @Expect(r.read(), true)
    @Expect(r.nodeType() == ReaderNodeType.Pi, true)
    @Expect(r.localName(), "pi")
    @Expect(r.value(), "d")
}

@Test
public func testWhitespaceVsText(): Unit {
    let r = XmlReader.fromString("<a>  \n  <b/>text</a>")
    var sawWs = false
    var sawText = false
    while (r.read()) {
        match (r.nodeType()) {
            case Whitespace => sawWs = true
            case Text => sawText = true
            case _ => ()
        }
    }
    @Expect(sawWs, true)
    @Expect(sawText, true)
}

/* ---------- 属性游标 ---------- */

@Test
public func testAttributeCursor(): Unit {
    let r = XmlReader.fromString("<a k=\"v\" x=\"y\"/>")
    @Expect(r.read(), true) // Decl
    @Expect(r.read(), true) // Element
    @Expect(r.hasAttributes(), true)
    @Expect(r.attributeCount(), 2)
    @Expect(r.moveToFirstAttribute(), true)
    @Expect(r.nodeType() == ReaderNodeType.Attribute, true)
    @Expect(r.localName(), "k")
    @Expect(r.value(), "v")
    @Expect(r.moveToNextAttribute(), true)
    @Expect(r.localName(), "x")
    @Expect(r.value(), "y")
    @Expect(r.moveToNextAttribute(), false)
    @Expect(r.moveToElement(), true)
    @Expect(r.nodeType() == ReaderNodeType.Element, true)
}

@Test
public func testMoveToAttributeByName(): Unit {
    let r = XmlReader.fromString("<a k=\"v\" x=\"y\"/>")
    r.read(); r.read()
    @Expect(r.moveToAttribute("x"), true)
    @Expect(r.value(), "y")
    @Expect(r.moveToAttribute("nope"), false)
    // 失败不移动游标：仍然 "x"
    @Expect(r.localName(), "x")
}

@Test
public func testMoveToAttributeIndexOutOfRange(): Unit {
    let r = XmlReader.fromString("<a k=\"v\"/>")
    r.read(); r.read()
    @Expect(r.moveToAttribute(5), false)
    @Expect(r.moveToAttribute(-1), false)
}

@Test
public func testHasValueAndName(): Unit {
    let r = XmlReader.fromString("<p:a xmlns:p=\"urn:p\" k=\"v\"/>")
    r.read(); r.read()
    @Expect(r.name(), "p:a")
    @Expect(r.prefix(), "p")
    @Expect(r.localName(), "a")
    @Expect(r.namespaceUri(), "urn:p")
    @Expect(r.hasValue(), false)  // element 本身没有 value
    r.moveToAttribute("k")
    @Expect(r.hasValue(), true)
}

/* ---------- skip ---------- */

@Test
public func testSkipElementSubtree(): Unit {
    let r = XmlReader.fromString("<a><b><c/>deep</b><d/></a>")
    r.read() // Decl
    r.read() // E a
    r.read() // E b
    @Expect(r.localName(), "b")
    @Expect(r.skip(), true)
    // skip 后光标应停在 </b>
    @Expect(r.nodeType() == ReaderNodeType.EndElement, true)
    @Expect(r.localName(), "b")
    // 继续读 → 下一兄弟 d
    @Expect(r.read(), true)
    @Expect(r.nodeType() == ReaderNodeType.Element, true)
    @Expect(r.localName(), "d")
}

@Test
public func testSkipEmptyElementEqualsRead(): Unit {
    let r = XmlReader.fromString("<a><b/><c/></a>")
    r.read() // Decl
    r.read() // E a
    r.read() // E b (empty)
    @Expect(r.isEmptyElement(), true)
    @Expect(r.skip(), true)
    // 下一节点应该是 E c
    @Expect(r.nodeType() == ReaderNodeType.Element, true)
    @Expect(r.localName(), "c")
}

@Test
public func testSkipOnNonElementActsAsRead(): Unit {
    let r = XmlReader.fromString("<a>t<b/></a>")
    r.read() // Decl
    r.read() // E a
    r.read() // Text
    @Expect(r.nodeType() == ReaderNodeType.Text, true)
    @Expect(r.skip(), true) // 等价 read 一次
    @Expect(r.nodeType() == ReaderNodeType.Element, true)
    @Expect(r.localName(), "b")
}

/* ---------- close / EOF ---------- */

@Test
public func testCloseStopsReading(): Unit {
    let r = XmlReader.fromString("<a/>")
    r.read()
    r.close()
    @Expect(r.isClosed(), true)
    @Expect(r.read(), false)
}

@Test
public func testReadAfterEofReturnsFalse(): Unit {
    let r = XmlReader.fromString("<a/>")
    while (r.read()) {
        // consume
    }
    @Expect(r.isEof(), true)
    @Expect(r.read(), false)
    @Expect(r.read(), false)
}

/* ---------- 错误处理 ---------- */

@Test
public func testParseErrorRaisesException(): Unit {
    let r = XmlReader.fromString("<a><b></a>")
    try {
        while (r.read()) {
            // walk until parser raises
        }
        @Fail("expected exception")
    } catch (_: XmlException) {
        @Expect(r.readerState() == ReaderState.Error, true)
        // 错误态后再 read 返回 false，不再抛
        @Expect(r.read(), false)
    }
}

/* ---------- fromParser ---------- */

@Test
public func testFromParser(): Unit {
    let p = XmlParser.fromString("<a/>")
    let r = XmlReader.fromParser(p)
    @Expect(r.read(), true)
    @Expect(r.read(), true)
    @Expect(r.nodeType() == ReaderNodeType.Element, true)
}

/* ---------- XmlDeclaration / Doctype ---------- */

@Test
public func testXmlDeclarationNode(): Unit {
    let r = XmlReader.fromString("<?xml version=\"1.0\" encoding=\"UTF-8\"?><a/>")
    @Expect(r.read(), true)
    @Expect(r.nodeType() == ReaderNodeType.XmlDeclaration, true)
    @Expect(r.value(), "1.0")
}

@Test
public func testDoctypeNode(): Unit {
    let r = XmlReader.fromString("<!DOCTYPE a><a/>")
    r.read() // decl
    @Expect(r.read(), true)
    @Expect(r.nodeType() == ReaderNodeType.Doctype, true)
    @Expect(r.localName(), "a")
}

/* ---------- position ---------- */

@Test
public func testPositionTracking(): Unit {
    let r = XmlReader.fromString("<a/>")
    r.read() // decl
    r.read() // element
    let p = r.position()
    @Expect(p.line >= 1, true)
}

/* ---------- 属性多元素复位 ---------- */

@Test
public func testAttributeCursorClearedOnNextRead(): Unit {
    let r = XmlReader.fromString("<a k=\"v\"><b/></a>")
    r.read() // decl
    r.read() // a
    r.moveToFirstAttribute()
    @Expect(r.nodeType() == ReaderNodeType.Attribute, true)
    r.read() // 前进到 b
    @Expect(r.nodeType() == ReaderNodeType.Element, true)
    @Expect(r.localName(), "b")
}

/* ---------- EntityReference ---------- */

@Test
public func testEntityReferenceExpanded(): Unit {
    // 默认 substituteEntities=true，所以 &amp; 应被展开为 '&' 的 Text
    let r = XmlReader.fromString("<a>x&amp;y</a>")
    var hasText = false
    while (r.read()) {
        if (r.nodeType() == ReaderNodeType.Text) {
            @Expect(r.value(), "x&y")
            hasText = true
        }
    }
    @Expect(hasText, true)
}
