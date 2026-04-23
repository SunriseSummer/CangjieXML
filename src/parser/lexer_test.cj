/*
 * Lexer 单元测试：共享辅助 + 基本词法（元素 / 属性 / 文本 / CDATA / 注释 / PI / XML 声明）。
 *
 * 其余测试（DOCTYPE / 错误情形 / 字符引用 / 属性值换行折叠 / 位置信息）见
 * `lexer_errors_test.cj`。
 */
package cangjie_xml.parser

import std.unittest.*
import std.collection.*
import cangjie_xml.core.*

/** 把 `Lexer` 的整个 token 流收集为列表（到 Eof 截止）。 */
func lex(s: String): ArrayList<Token> {
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

/** 返回 token 种类的短字符串名，便于 `@Expect` 比对。 */
func lexKind(t: Token): String {
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
    @Expect(lexKind(toks[0]), "ElementOpenStart")
    match (toks[0]) {
        case ElementOpenStart(_, n) => @Expect(n, "a")
        case _ => @Fail("expected ElementOpenStart")
    }
    @Expect(lexKind(toks[1]), "ElementSelfClose")
    @Expect(lexKind(toks[2]), "Eof")
}

@Test
public func testLexerOpenCloseTag(): Unit {
    let toks = lex("<root></root>")
    @Expect(toks.size, 4)
    @Expect(lexKind(toks[0]), "ElementOpenStart")
    @Expect(lexKind(toks[1]), "ElementOpenEnd")
    @Expect(lexKind(toks[2]), "ElementClose")
    match (toks[2]) {
        case ElementClose(_, n) => @Expect(n, "root")
        case _ => @Fail("expected ElementClose")
    }
}

@Test
public func testLexerNested(): Unit {
    let toks = lex("<a><b/></a>")
    @Expect(lexKind(toks[0]), "ElementOpenStart")
    @Expect(lexKind(toks[1]), "ElementOpenEnd")
    @Expect(lexKind(toks[2]), "ElementOpenStart")
    @Expect(lexKind(toks[3]), "ElementSelfClose")
    @Expect(lexKind(toks[4]), "ElementClose")
    @Expect(lexKind(toks[5]), "Eof")
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
    @Expect(lexKind(toks[2]), "AttrEq")
    match (toks[3]) {
        case AttrValueStart(_, q) => @Expect(q == AttrQuote.Double, true)
        case _ => @Fail("unexpected token kind")
    }
    match (toks[4]) {
        case AttrValueChunk(_, v) => @Expect(v, "1")
        case _ => @Fail("unexpected token kind")
    }
    @Expect(lexKind(toks[5]), "AttrValueEnd")
    @Expect(lexKind(toks[6]), "ElementSelfClose")
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
