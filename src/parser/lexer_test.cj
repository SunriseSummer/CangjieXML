/*
 * Lexer 单元测试。
 *
 * 覆盖：
 *   - 元素开 / 闭 / 自闭合 / 嵌套；
 *   - 属性名 / 等号 / 单双引号属性值；
 *   - 属性值内的字符引用与实体引用；
 *   - 文本、CDATA、注释、PI；
 *   - XML 声明；
 *   - DOCTYPE 头部（含 ExternalID、内部子集括号、带引号字符串）；
 *   - 错误情形：未闭合、'<' 出现在属性值、']]>' 出现在文本、非法字符引用、
 *     未终结实体引用、非法 XML 字符、XML 声明出现位置错误、PI target 为 xml；
 *   - 字符引用 10 进制与 16 进制；
 *   - 属性值换行折叠（CR/LF/TAB → SPACE）；
 *   - 位置信息（行列）。
 */
package cangjie_xml.parser

import std.unittest.*
import std.collection.*
import cangjie_xml.core.*

private func lex(s: String): ArrayList<Token> {
    let l = Lexer.fromString(s)
    let acc = ArrayList<Token>()
    while (true) {
        match (l.next()) {
            case Some(t) =>
                acc.add(t)
                match (t) {
                    case Eof(_) => return acc
                    case _ => ()
                }
            case None => return acc
        }
    }
    return acc
}

private func kind(t: Token): String {
    match (t) {
        case XmlDeclStart(_) => return "XmlDeclStart"
        case XmlDeclEnd(_) => return "XmlDeclEnd"
        case ElementOpenStart(_, _) => return "ElementOpenStart"
        case ElementSelfClose(_) => return "ElementSelfClose"
        case ElementOpenEnd(_) => return "ElementOpenEnd"
        case ElementClose(_, _) => return "ElementClose"
        case AttrName(_, _) => return "AttrName"
        case AttrEq(_) => return "AttrEq"
        case AttrValueStart(_, _) => return "AttrValueStart"
        case AttrValueChunk(_, _) => return "AttrValueChunk"
        case AttrValueEnd(_, _) => return "AttrValueEnd"
        case Text(_, _) => return "Text"
        case CDataSection(_, _) => return "CDataSection"
        case Comment(_, _) => return "Comment"
        case ProcessingInstruction(_, _, _) => return "ProcessingInstruction"
        case DoctypeStart(_, _) => return "DoctypeStart"
        case DoctypeEnd(_) => return "DoctypeEnd"
        case EntityRef(_, _) => return "EntityRef"
        case CharRef(_, _) => return "CharRef"
        case Eof(_) => return "Eof"
    }
}

@Test
public func testLexerEmptyElement(): Unit {
    let toks = lex("<a/>")
    @Expect(toks.size, 3)
    @Expect(kind(toks[0]), "ElementOpenStart")
    match (toks[0]) {
        case ElementOpenStart(_, n) => @Expect(n, "a")
        case _ => @Fail("expected ElementOpenStart")
    }
    @Expect(kind(toks[1]), "ElementSelfClose")
    @Expect(kind(toks[2]), "Eof")
}

@Test
public func testLexerOpenCloseTag(): Unit {
    let toks = lex("<root></root>")
    @Expect(toks.size, 4)
    @Expect(kind(toks[0]), "ElementOpenStart")
    @Expect(kind(toks[1]), "ElementOpenEnd")
    @Expect(kind(toks[2]), "ElementClose")
    match (toks[2]) {
        case ElementClose(_, n) => @Expect(n, "root")
        case _ => @Fail("expected ElementClose")
    }
}

@Test
public func testLexerNested(): Unit {
    let toks = lex("<a><b/></a>")
    @Expect(kind(toks[0]), "ElementOpenStart")
    @Expect(kind(toks[1]), "ElementOpenEnd")
    @Expect(kind(toks[2]), "ElementOpenStart")
    @Expect(kind(toks[3]), "ElementSelfClose")
    @Expect(kind(toks[4]), "ElementClose")
    @Expect(kind(toks[5]), "Eof")
}

@Test
public func testLexerAttributesDoubleQuote(): Unit {
    let toks = lex("<a x=\"1\"/>")
    // ElementOpenStart, AttrName(x), AttrEq, AttrValueStart("), AttrValueChunk(1), AttrValueEnd, ElementSelfClose, Eof
    @Expect(toks.size, 8)
    match (toks[1]) {
        case AttrName(_, n) => @Expect(n, "x")
        case _ => @Fail("expected AttrName")
    }
    @Expect(kind(toks[2]), "AttrEq")
    match (toks[3]) {
        case AttrValueStart(_, q) => @Expect(q == AttrQuote.Double, true)
        case _ => @Fail("unexpected token kind")
    }
    match (toks[4]) {
        case AttrValueChunk(_, v) => @Expect(v, "1")
        case _ => @Fail("unexpected token kind")
    }
    @Expect(kind(toks[5]), "AttrValueEnd")
    @Expect(kind(toks[6]), "ElementSelfClose")
}

@Test
public func testLexerAttributesSingleQuote(): Unit {
    let toks = lex("<a x='value'/>")
    match (toks[3]) {
        case AttrValueStart(_, q) => @Expect(q == AttrQuote.Single, true)
        case _ => @Fail("unexpected token kind")
    }
    match (toks[4]) {
        case AttrValueChunk(_, v) => @Expect(v, "value")
        case _ => @Fail("unexpected token kind")
    }
}

@Test
public func testLexerAttributeValueEntityRef(): Unit {
    let toks = lex("<a x=\"&amp;&lt;\"/>")
    // chunks: "" / EntityRef(amp) / "" / EntityRef(lt) / "" — actually fragments only emit chunk when non-empty text.
    // Sequence will be: AttrValueStart, EntityRef(amp), EntityRef(lt), AttrValueEnd
    // The lexer enters attr-value mode and at each iter looks at quote/ref/text.
    // Count by scanning.
    var refs = 0
    for (t in toks) {
        match (t) {
            case EntityRef(_, _) => refs += 1
            case _ => ()
        }
    }
    @Expect(refs, 2)
}

@Test
public func testLexerAttributeValueCharRef(): Unit {
    let toks = lex("<a x=\"&#65;&#x4E2D;\"/>")
    var refs = ArrayList<Int32>()
    for (t in toks) {
        match (t) {
            case CharRef(_, cp) => refs.add(cp)
            case _ => ()
        }
    }
    @Expect(refs.size, 2)
    @Expect(refs[0], 65i32)
    @Expect(refs[1], 0x4E2Di32)
}

@Test
public func testLexerAttributeValueNewlineFolding(): Unit {
    // XML §3.3.3: TAB / LF in attr value → SPACE
    let toks = lex("<a x=\"a\nb\tc\"/>")
    for (t in toks) {
        match (t) {
            case AttrValueChunk(_, v) => @Expect(v, "a b c")
            case _ => ()
        }
    }
}

@Test
public func testLexerText(): Unit {
    let toks = lex("<a>hello world</a>")
    var found = false
    for (t in toks) {
        match (t) {
            case Text(_, s) =>
                @Expect(s, "hello world")
                found = true
            case _ => ()
        }
    }
    @Expect(found, true)
}

@Test
public func testLexerCData(): Unit {
    let toks = lex("<a><![CDATA[<b>&amp;</b>]]></a>")
    var found = false
    for (t in toks) {
        match (t) {
            case CDataSection(_, s) =>
                @Expect(s, "<b>&amp;</b>")
                found = true
            case _ => ()
        }
    }
    @Expect(found, true)
}

@Test
public func testLexerComment(): Unit {
    let toks = lex("<a><!-- hello --></a>")
    var found = false
    for (t in toks) {
        match (t) {
            case Comment(_, s) =>
                @Expect(s, " hello ")
                found = true
            case _ => ()
        }
    }
    @Expect(found, true)
}

@Test
public func testLexerCommentDoubleDashRejected(): Unit {
    var threw = false
    try {
        let _ = lex("<a><!-- -- --></a>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testLexerProcessingInstruction(): Unit {
    let toks = lex("<a><?target some data?></a>")
    for (t in toks) {
        match (t) {
            case ProcessingInstruction(_, tgt, data) =>
                @Expect(tgt, "target")
                @Expect(data, "some data")
            case _ => ()
        }
    }
}

@Test
public func testLexerPiTargetXmlRejected(): Unit {
    var threw = false
    try {
        let _ = lex("<a><?xml version=\"1.0\"?></a>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testLexerXmlDeclaration(): Unit {
    let toks = lex("<?xml version=\"1.0\" encoding=\"UTF-8\"?><a/>")
    @Expect(kind(toks[0]), "XmlDeclStart")
    // version attr
    match (toks[1]) {
        case AttrName(_, n) => @Expect(n, "version")
        case _ => @Fail("unexpected token kind")
    }
    @Expect(kind(toks[2]), "AttrEq")
    @Expect(kind(toks[3]), "AttrValueStart")
    match (toks[4]) {
        case AttrValueChunk(_, v) => @Expect(v, "1.0")
        case _ => @Fail("unexpected token kind")
    }
    @Expect(kind(toks[5]), "AttrValueEnd")
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
    @Expect(kind(toks[1]), "DoctypeEnd")
}

@Test
public func testLexerDoctypeWithInternalSubset(): Unit {
    let toks = lex("<!DOCTYPE x [ <!ENTITY a \"b\"> ]><x/>")
    @Expect(kind(toks[0]), "DoctypeStart")
    @Expect(kind(toks[1]), "DoctypeEnd")
    @Expect(kind(toks[2]), "ElementOpenStart")
}

@Test
public func testLexerDoctypeWithExternalId(): Unit {
    let toks = lex("<!DOCTYPE x PUBLIC \"pub>id\" \"sys'id\"><x/>")
    // `>` inside the quoted string must not terminate DOCTYPE
    @Expect(kind(toks[0]), "DoctypeStart")
    @Expect(kind(toks[1]), "DoctypeEnd")
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
