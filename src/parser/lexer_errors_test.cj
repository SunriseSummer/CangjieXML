/*
 * Lexer 单元测试：XML 声明位置 / DOCTYPE / 错误情形 / 字符引用 / 属性值换行折叠 / 位置信息。
 *
 * 共享辅助 `lex` / `lexKind` 在 `lexer_test.cj` 中。
 */
package cangjie_xml.parser

import std.unittest.*
import std.collection.*
import cangjie_xml.core.*


@Test
public func testLexerXmlDeclaration(): Unit {
    let toks = lex("<?xml version=\"1.0\" encoding=\"UTF-8\"?><a/>")
    @Expect(lexKind(toks[0]), "XmlDeclStart")
    // version attr
    match (toks[1]) {
        case AttrName(_, n) => @Expect(n, "version")
        case _ => @Fail("unexpected token kind")
    }
    @Expect(lexKind(toks[2]), "AttrEq")
    @Expect(lexKind(toks[3]), "AttrValueStart")
    match (toks[4]) {
        case AttrValueChunk(_, v) => @Expect(v, "1.0")
        case _ => @Fail("unexpected token kind")
    }
    @Expect(lexKind(toks[5]), "AttrValueEnd")
    // encoding attr
    match (toks[6]) {
        case AttrName(_, n) => @Expect(n, "encoding")
        case _ => @Fail("unexpected token kind")
    }
    // ... XmlDeclEnd somewhere before ElementOpenStart
    var sawDeclEnd = false
    var sawElem = false
    for (t in toks) {
        match (t) {
            case XmlDeclEnd(_) => sawDeclEnd = true
            case ElementOpenStart(_, _) => sawElem = true
            case _ => ()
        }
    }
    @Expect(sawDeclEnd, true)
    @Expect(sawElem, true)
}

@Test
public func testLexerXmlDeclMustBeFirst(): Unit {
    var threw = false
    try {
        let _ = lex("<a><?xml version=\"1.0\"?></a>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testLexerDoctypeSimple(): Unit {
    let toks = lex("<!DOCTYPE html><html/>")
    match (toks[0]) {
        case DoctypeStart(_, n) => @Expect(n, "html")
        case _ => @Fail("unexpected token kind")
    }
    @Expect(lexKind(toks[1]), "DoctypeEnd")
}

@Test
public func testLexerDoctypeWithInternalSubset(): Unit {
    let toks = lex("<!DOCTYPE x [ <!ENTITY a \"b\"> ]><x/>")
    @Expect(lexKind(toks[0]), "DoctypeStart")
    @Expect(lexKind(toks[1]), "DoctypeEnd")
    @Expect(lexKind(toks[2]), "ElementOpenStart")
}

@Test
public func testLexerDoctypeWithExternalId(): Unit {
    let toks = lex("<!DOCTYPE x PUBLIC \"pub>id\" \"sys'id\"><x/>")
    // `>` inside the quoted string must not terminate DOCTYPE
    @Expect(lexKind(toks[0]), "DoctypeStart")
    @Expect(lexKind(toks[1]), "DoctypeEnd")
}

@Test
public func testLexerLiteralLtInAttrValueRejected(): Unit {
    var threw = false
    try {
        let _ = lex("<a x=\"<\"/>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testLexerCDataEndInTextRejected(): Unit {
    var threw = false
    try {
        let _ = lex("<a>foo]]>bar</a>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testLexerUnterminatedElement(): Unit {
    var threw = false
    try {
        let _ = lex("<a")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testLexerCharRefOutOfRange(): Unit {
    var threw = false
    try {
        let _ = lex("<a>&#xFFFFFFFF;</a>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testLexerCharRefEmpty(): Unit {
    var threw = false
    try {
        let _ = lex("<a>&#;</a>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testLexerCharRefIllegalXmlChar(): Unit {
    // U+0000 is never allowed in XML 1.0 or 1.1
    var threw = false
    try {
        let _ = lex("<a>&#0;</a>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testLexerEntityRefWithoutSemicolon(): Unit {
    var threw = false
    try {
        let _ = lex("<a>&amp</a>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testLexerUnterminatedComment(): Unit {
    var threw = false
    try {
        let _ = lex("<a><!-- oops")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testLexerUnterminatedCData(): Unit {
    var threw = false
    try {
        let _ = lex("<a><![CDATA[hi")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testLexerPositionTracking(): Unit {
    let toks = lex("<a>\n  <b/>\n</a>")
    // 找到 <b/> ElementOpenStart
    var bpos: Position = Position.unknown()
    for (t in toks) {
        match (t) {
            case ElementOpenStart(p, n) where n == "b" => bpos = p
            case _ => ()
        }
    }
    // <b/> 位于第 2 行第 4 列（1-based：两个空格 + '<' + 'b'，'<' 在第 3 列）
    // ElementOpenStart 的 Position 指向 '<'，即第 2 行 3 列；但我们的实现把 ElementOpenStart
    // 定位到"读到名字起点"，实际实现把 startPos = 读 '<' 之前的位置。
    @Expect(bpos.line, 2)
    @Expect(bpos.column, 3)
}

@Test
public func testLexerTextBeforeRootIsWhitespaceOk(): Unit {
    // 文档开头的空白（在 XML 声明之后 / 根元素之前）
    let toks = lex("<?xml version=\"1.0\"?>\n<a/>")
    var sawElem = false
    for (t in toks) {
        match (t) {
            case ElementOpenStart(_, n) where n == "a" => sawElem = true
            case _ => ()
        }
    }
    @Expect(sawElem, true)
}

@Test
public func testLexerMultipleAttributes(): Unit {
    let toks = lex("<a x=\"1\" y='2' z=\"3\"/>")
    var names = ArrayList<String>()
    for (t in toks) {
        match (t) {
            case AttrName(_, n) => names.add(n)
            case _ => ()
        }
    }
    @Expect(names.size, 3)
    @Expect(names[0], "x")
    @Expect(names[1], "y")
    @Expect(names[2], "z")
}

@Test
public func testLexerElementNameWithColonAndDash(): Unit {
    let toks = lex("<xmlns:pre-fix/>")
    match (toks[0]) {
        case ElementOpenStart(_, n) => @Expect(n, "xmlns:pre-fix")
        case _ => @Fail("unexpected token kind")
    }
}

@Test
public func testLexerCrlfNormalizedInText(): Unit {
    // RuneReader 把 CRLF -> LF
    let toks = lex("<a>a\r\nb</a>")
    for (t in toks) {
        match (t) {
            case Text(_, s) => @Expect(s, "a\nb")
            case _ => ()
        }
    }
}
