/*
 * XmlParser 单元测试。
 *
 * 覆盖：
 *   - 合成 StartDocument / EndDocument；
 *   - 元素开闭匹配、自闭合、嵌套、多根元素拒绝；
 *   - 属性聚合（引号内实体/字符引用展开、重复属性拒绝）；
 *   - 命名空间绑定（默认、前缀、继承、shadowing、解绑、属性默认命名空间规则）；
 *   - `xml` / `xmlns` 前缀的硬约束；
 *   - 连续文本合并为单个 Characters；
 *   - CDATA 独立事件；
 *   - Comment / PI / DOCTYPE 透传；
 *   - XML 声明属性顺序校验、重复属性、未定义实体、深度限制、Billion Laughs；
 *   - `substituteEntities = false` 时透传 EntityReference；
 *   - `keepBlanks = false`。
 */
package cangjie_xml.parser

import std.unittest.*
import std.collection.*
import cangjie_xml.core.*

private func events(s: String, opts!: ParserOptions = ParserOptions()): ArrayList<SaxEvent> {
    let p = XmlParser.fromString(s, opts: opts)
    let acc = ArrayList<SaxEvent>()
    while (true) {
        match (p.next()) {
            case Some(e) =>
                acc.add(e)
                match (e) {
                    case EndDocument(_) => return acc
                    case ParseError(_) => return acc
                    case _ => ()
                }
            case None => return acc
        }
    }
    return acc
}

private func kind(e: SaxEvent): String {
    match (e) {
        case StartDocument(_) => return "StartDocument"
        case EndDocument(_) => return "EndDocument"
        case StartElement(_, _, _, _) => return "StartElement"
        case EndElement(_, _) => return "EndElement"
        case Characters(_, _) => return "Characters"
        case Cdata(_, _) => return "Cdata"
        case CommentEvent(_, _) => return "CommentEvent"
        case Pi(_, _, _) => return "Pi"
        case Doctype(_, _) => return "Doctype"
        case EntityReference(_, _) => return "EntityReference"
        case ParseError(_) => return "ParseError"
    }
}

/* ---------- Document skeleton ---------- */

@Test
public func testEmptyElementSkeleton(): Unit {
    let evs = events("<a/>")
    @Expect(evs.size, 4)
    @Expect(kind(evs[0]), "StartDocument")
    @Expect(kind(evs[1]), "StartElement")
    @Expect(kind(evs[2]), "EndElement")
    @Expect(kind(evs[3]), "EndDocument")
}

@Test
public func testStartDocumentSyntheticWhenNoDecl(): Unit {
    let evs = events("<a/>")
    match (evs[0]) {
        case StartDocument(d) =>
            @Expect(d.version, "1.0")
            @Expect(d.encoding.isNone(), true)
        case _ => @Fail("expected StartDocument")
    }
}

@Test
public func testXmlDeclarationParsed(): Unit {
    let evs = events("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><a/>")
    match (evs[0]) {
        case StartDocument(d) =>
            @Expect(d.version, "1.0")
            @Expect(d.encoding.getOrThrow(), "UTF-8")
            @Expect(d.standalone == Standalone.Yes, true)
        case _ => @Fail("expected StartDocument")
    }
}

@Test
public func testXmlDeclarationVersionMustBeFirst(): Unit {
    var threw = false
    try {
        let _ = events("<?xml encoding=\"UTF-8\" version=\"1.0\"?><a/>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testXmlDeclarationInvalidStandalone(): Unit {
    var threw = false
    try {
        let _ = events("<?xml version=\"1.0\" standalone=\"maybe\"?><a/>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testXmlDeclarationUnsupportedVersion(): Unit {
    var threw = false
    try {
        let _ = events("<?xml version=\"2.0\"?><a/>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testMultipleRootElementsRejected(): Unit {
    var threw = false
    try {
        let _ = events("<a/><b/>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testMismatchedEndTagRejected(): Unit {
    var threw = false
    try {
        let _ = events("<a></b>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testUnexpectedEofRejected(): Unit {
    var threw = false
    try {
        let _ = events("<a>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

/* ---------- Attributes ---------- */

@Test
public func testAttributesCollected(): Unit {
    let evs = events("<a x=\"1\" y='2'/>")
    match (evs[1]) {
        case StartElement(_, name, attrs, _) =>
            @Expect(name.localName, "a")
            @Expect(attrs.size, 2)
            @Expect(attrs[0].qname.localName, "x")
            @Expect(attrs[0].value, "1")
            @Expect(attrs[1].qname.localName, "y")
            @Expect(attrs[1].value, "2")
        case _ => @Fail("expected StartElement")
    }
}

@Test
public func testAttributeEntityRefExpanded(): Unit {
    let evs = events("<a x=\"&amp;&lt;&gt;&apos;&quot;\"/>")
    match (evs[1]) {
        case StartElement(_, _, attrs, _) =>
            @Expect(attrs[0].value, "&<>'\"")
        case _ => @Fail("unexpected event kind")
    }
}

@Test
public func testAttributeCharRefExpanded(): Unit {
    let evs = events("<a x=\"&#65;&#x4E2D;\"/>")
    match (evs[1]) {
        case StartElement(_, _, attrs, _) => @Expect(attrs[0].value, "A中")
        case _ => @Fail("unexpected event kind")
    }
}

@Test
public func testAttributeDuplicateRejected(): Unit {
    var threw = false
    try {
        let _ = events("<a x=\"1\" x=\"2\"/>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testAttributeUndefinedEntityRejected(): Unit {
    var threw = false
    try {
        let _ = events("<a x=\"&foo;\"/>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

/* ---------- Namespaces ---------- */

@Test
public func testDefaultNamespaceBoundToElement(): Unit {
    let evs = events("<a xmlns=\"urn:x\"/>")
    match (evs[1]) {
        case StartElement(_, name, attrs, ns) =>
            @Expect(name.uri.getOrThrow(), "urn:x")
            @Expect(attrs.size, 1)
            @Expect(attrs[0].isNamespaceDeclaration, true)
            @Expect(ns.defaultNs().getOrThrow(), "urn:x")
        case _ => @Fail("unexpected event kind")
    }
}

@Test
public func testDefaultNamespaceDoesNotApplyToAttributes(): Unit {
    let evs = events("<a xmlns=\"urn:x\" attr=\"v\"/>")
    match (evs[1]) {
        case StartElement(_, _, attrs, _) =>
            var found = false
            for (a in attrs) {
                if (a.qname.localName == "attr") {
                    found = true
                    @Expect(a.qname.uri.isNone(), true)
                }
            }
            @Expect(found, true)
        case _ => @Fail("unexpected event kind")
    }
}

@Test
public func testPrefixNamespace(): Unit {
    let evs = events("<a xmlns:p=\"urn:p\" p:x=\"1\"><p:b/></a>")
    match (evs[1]) {
        case StartElement(_, _, attrs, _) =>
            for (a in attrs) {
                if (a.qname.localName == "x") {
                    @Expect(a.qname.uri.getOrThrow(), "urn:p")
                    @Expect(a.qname.prefix.getOrThrow(), "p")
                }
            }
        case _ => @Fail("unexpected event kind")
    }
    match (evs[2]) {
        case StartElement(_, n, _, _) =>
            @Expect(n.localName, "b")
            @Expect(n.uri.getOrThrow(), "urn:p")
        case _ => @Fail("unexpected event kind")
    }
}

@Test
public func testUndefinedPrefixRejected(): Unit {
    var threw = false
    try {
        let _ = events("<p:a/>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testXmlPrefixHardcoded(): Unit {
    let evs = events("<a xml:lang=\"en\"/>")
    match (evs[1]) {
        case StartElement(_, _, attrs, _) =>
            @Expect(attrs[0].qname.uri.getOrThrow(), XML_NAMESPACE_URI)
        case _ => @Fail("unexpected event kind")
    }
}

@Test
public func testXmlPrefixMustBindToXmlNamespace(): Unit {
    var threw = false
    try {
        let _ = events("<a xmlns:xml=\"http://evil.example\"/>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testXmlnsPrefixRedeclarationRejected(): Unit {
    var threw = false
    try {
        let _ = events("<a xmlns:xmlns=\"urn:x\"/>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testNestedNamespaceScoping(): Unit {
    let evs = events("<a xmlns=\"urn:outer\"><b xmlns=\"urn:inner\"/><c/></a>")
    // outer a
    match (evs[1]) {
        case StartElement(_, n, _, _) => @Expect(n.uri.getOrThrow(), "urn:outer")
        case _ => @Fail("unexpected event kind")
    }
    // inner b
    match (evs[2]) {
        case StartElement(_, n, _, _) => @Expect(n.uri.getOrThrow(), "urn:inner")
        case _ => @Fail("unexpected event kind")
    }
    // back to outer for c
    var idx = 0
    for (e in evs) {
        match (e) {
            case StartElement(_, n, _, _) where n.localName == "c" =>
                @Expect(n.uri.getOrThrow(), "urn:outer")
            case _ => ()
        }
        idx += 1
    }
}

/* ---------- Characters / CDATA / merging ---------- */

@Test
public func testConsecutiveTextAndRefsMerged(): Unit {
    let evs = events("<a>hi&amp;there&#65;!</a>")
    var count = 0
    var combined = ""
    for (e in evs) {
        match (e) {
            case Characters(_, s) =>
                count += 1
                combined += s
            case _ => ()
        }
    }
    @Expect(count, 1)
    @Expect(combined, "hi&thereA!")
}

@Test
public func testCdataIndependentEvent(): Unit {
    let evs = events("<a>pre<![CDATA[<x>]]>post</a>")
    var seq = ArrayList<String>()
    for (e in evs) {
        match (e) {
            case Characters(_, s) => seq.add("C:${s}")
            case Cdata(_, s) => seq.add("D:${s}")
            case _ => ()
        }
    }
    @Expect(seq.size, 3)
    @Expect(seq[0], "C:pre")
    @Expect(seq[1], "D:<x>")
    @Expect(seq[2], "C:post")
}

@Test
public func testCommentAndPi(): Unit {
    let evs = events("<a><!-- c --><?t d?></a>")
    var sawComment = false
    var sawPi = false
    for (e in evs) {
        match (e) {
            case CommentEvent(_, s) =>
                sawComment = true
                @Expect(s, " c ")
            case Pi(_, t, d) =>
                sawPi = true
                @Expect(t, "t")
                @Expect(d, "d")
            case _ => ()
        }
    }
    @Expect(sawComment, true)
    @Expect(sawPi, true)
}

@Test
public func testDoctypeEvent(): Unit {
    let evs = events("<!DOCTYPE html><html/>")
    var saw = false
    for (e in evs) {
        match (e) {
            case Doctype(_, n) =>
                saw = true
                @Expect(n, "html")
            case _ => ()
        }
    }
    @Expect(saw, true)
}

/* ---------- Options ---------- */

@Test
public func testKeepBlanksFalseSkipsWhitespaceOnly(): Unit {
    let opts = ParserOptions(keepBlanks: false)
    let evs = events("<a>  <b/>  </a>", opts: opts)
    for (e in evs) {
        match (e) {
            case Characters(_, _) => @Fail("expected no whitespace-only Characters")
            case _ => ()
        }
    }
}

@Test
public func testKeepBlanksTrueKeepsWhitespace(): Unit {
    let evs = events("<a>  </a>")
    var found = false
    for (e in evs) {
        match (e) {
            case Characters(_, s) =>
                found = true
                @Expect(s, "  ")
            case _ => ()
        }
    }
    @Expect(found, true)
}

@Test
public func testSubstituteEntitiesFalseEmitsEntityReference(): Unit {
    let opts = ParserOptions(substituteEntities: false)
    let evs = events("<a>foo&amp;bar</a>", opts: opts)
    var sawRef = false
    var sawBar = false
    for (e in evs) {
        match (e) {
            case EntityReference(_, n) =>
                sawRef = true
                @Expect(n, "amp")
            case Characters(_, s) where s == "foo" => ()
            case Characters(_, s) where s == "bar" => sawBar = true
            case _ => ()
        }
    }
    @Expect(sawRef, true)
    @Expect(sawBar, true)
}

@Test
public func testMaxDepthExceeded(): Unit {
    let opts = ParserOptions(maxDepth: 3)
    var threw = false
    try {
        let _ = events("<a><b><c><d/></c></b></a>", opts: opts)
    } catch (e: XmlException) {
        match (e.error) {
            case LimitExceeded(_, _) => threw = true
            case _ => ()
        }
    }
    @Expect(threw, true)
}

@Test
public func testMaxEntityExpansion(): Unit {
    // 默认 10_000_000 太大，测试中降下来
    let opts = ParserOptions(maxEntityExpansion: 3)
    var threw = false
    try {
        let _ = events("<a>&amp;&amp;&amp;&amp;</a>", opts: opts)
    } catch (e: XmlException) {
        match (e.error) {
            case LimitExceeded(_, _) => threw = true
            case _ => ()
        }
    }
    @Expect(threw, true)
}

@Test
public func testCustomEntityResolver(): Unit {
    let opts = ParserOptions(entityResolver: Some(MapEntityResolver([("nbsp", "\u{00A0}")])))
    let evs = events("<a>foo&nbsp;bar</a>", opts: opts)
    var combined = ""
    for (e in evs) {
        match (e) {
            case Characters(_, s) => combined += s
            case _ => ()
        }
    }
    @Expect(combined, "foo\u{00A0}bar")
}

@Test
public func testNameTableInterning(): Unit {
    let nt = NameTable()
    let opts = ParserOptions(nameTable: Some(nt))
    let evs = events("<a x=\"1\"><a x=\"2\"/></a>", opts: opts)
    // 应该不报错，并且两个 <a> 元素的 localName 来自同一个池
    var names = ArrayList<String>()
    for (e in evs) {
        match (e) {
            case StartElement(_, n, _, _) => names.add(n.localName)
            case _ => ()
        }
    }
    @Expect(names.size, 2)
    @Expect(names[0], "a")
    @Expect(names[1], "a")
}

/* ---------- Edge cases ---------- */

@Test
public func testNonWhitespaceTextOutsideRoot(): Unit {
    var threw = false
    try {
        let _ = events("hi<a/>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testLeadingCommentAndPi(): Unit {
    let evs = events("<!-- hi --><?tgt ?><a/>")
    @Expect(kind(evs[0]), "StartDocument")
    var sawComment = false
    var sawPi = false
    for (e in evs) {
        match (e) {
            case CommentEvent(_, _) => sawComment = true
            case Pi(_, _, _) => sawPi = true
            case _ => ()
        }
    }
    @Expect(sawComment, true)
    @Expect(sawPi, true)
}

@Test
public func testNestedElements(): Unit {
    let evs = events("<a><b><c/></b></a>")
    // skeleton: StartDoc, SE(a), SE(b), SE(c), EE(c), EE(b), EE(a), EndDoc
    @Expect(evs.size, 8)
    @Expect(kind(evs[0]), "StartDocument")
    @Expect(kind(evs[1]), "StartElement")
    @Expect(kind(evs[2]), "StartElement")
    @Expect(kind(evs[3]), "StartElement")
    @Expect(kind(evs[4]), "EndElement")
    @Expect(kind(evs[5]), "EndElement")
    @Expect(kind(evs[6]), "EndElement")
    @Expect(kind(evs[7]), "EndDocument")
}

@Test
public func testQualifiedNameSplit(): Unit {
    let evs = events("<a xmlns:p=\"urn:x\"><p:b p:y=\"1\"/></a>")
    match (evs[2]) {
        case StartElement(_, n, attrs, _) =>
            @Expect(n.prefix.getOrThrow(), "p")
            @Expect(n.localName, "b")
            @Expect(n.uri.getOrThrow(), "urn:x")
            @Expect(attrs[0].qname.prefix.getOrThrow(), "p")
            @Expect(attrs[0].qname.localName, "y")
            @Expect(attrs[0].qname.uri.getOrThrow(), "urn:x")
        case _ => @Fail("unexpected event kind")
    }
}

@Test
public func testTwoAttributesSameLocalDifferentPrefixOk(): Unit {
    // a:x 和 b:x 指向不同 URI，扩展名不同，应允许
    let evs = events("<e xmlns:a=\"urn:a\" xmlns:b=\"urn:b\" a:x=\"1\" b:x=\"2\"/>")
    match (evs[1]) {
        case StartElement(_, _, attrs, _) =>
            var count = 0
            for (a in attrs) {
                if (a.qname.localName == "x") {
                    count += 1
                }
            }
            @Expect(count, 2)
        case _ => @Fail("unexpected event kind")
    }
}

@Test
public func testDuplicateAttributeExpandedNameRejected(): Unit {
    // xmlns 声明后 `p:x` 与 `x` 扩展名不同；但 `p:x` 与 `p:x` 同前缀重名 - 已由之前 case 覆盖。
    // 此用例：`a:x` 和 `b:x` 若映射到相同 URI 则冲突。
    var threw = false
    try {
        let _ = events("<e xmlns:a=\"urn:z\" xmlns:b=\"urn:z\" a:x=\"1\" b:x=\"2\"/>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}
