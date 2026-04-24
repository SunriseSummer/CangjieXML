/*
 * save — DocumentSerializer 单元 + 往返测试
 *
 * 覆盖 Phase 5a 的核心路径：
 *   - 基础标签：自闭合 / 成对 / 嵌套
 *   - 属性转义
 *   - 命名空间声明透传
 *   - Text / CDATA 转义规则差异
 *   - Comment / PI 透传
 *   - XML 声明：保留源声明 / 跳过合成声明 / 强制 omit
 *   - DOCTYPE 输出
 *   - 缩进 pretty-print
 *   - 选项 `cdataAsText`
 * 端到端 **round-trip**：
 *   parse → serialize → parse → DOM 语义等价（根名 / 孩子数 / 属性 / 文本聚合）
 */
package cangjie_xml.save

import std.unittest.*
import std.collection.*
import cangjie_xml.core.*
import cangjie_xml.parser.*
import cangjie_xml.tree.*

/* ---------- 基础 ---------- */

@Test
public func testSelfClosingEmpty(): Unit {
    let doc = DocumentBuilder.parseString("<a/>")
    @Expect(DocumentSerializer.toString(doc), "<a/>")
}

@Test
public func testPairedWithText(): Unit {
    let doc = DocumentBuilder.parseString("<a>hi</a>")
    @Expect(DocumentSerializer.toString(doc), "<a>hi</a>")
}

@Test
public func testNestedDefaultNoIndent(): Unit {
    let doc = DocumentBuilder.parseString("<a><b><c/></b></a>")
    @Expect(DocumentSerializer.toString(doc), "<a><b><c/></b></a>")
}

@Test
public func testAttributesEscapedAndQuoted(): Unit {
    let doc = DocumentBuilder.parseString("<e x=\"1\" y='&amp;&lt;'/>")
    // 序列化应用双引号 + 属性规则转义
    @Expect(DocumentSerializer.toString(doc), "<e x=\"1\" y=\"&amp;&lt;\"/>")
}

@Test
public func testNamespaceDeclarationsPreserved(): Unit {
    let src = "<r xmlns=\"urn:a\" xmlns:p=\"urn:b\"><p:c/></r>"
    let doc = DocumentBuilder.parseString(src)
    @Expect(DocumentSerializer.toString(doc), src)
}

@Test
public func testTextContentEscaped(): Unit {
    let doc = DocumentBuilder.parseString("<a>&amp; &lt; &gt; x</a>")
    // 文本中 &/</> 需要重新转义；apos/quot 在文本里不强制转义
    @Expect(DocumentSerializer.toString(doc), "<a>&amp; &lt; &gt; x</a>")
}

@Test
public func testCdataPreservedByDefault(): Unit {
    let doc = DocumentBuilder.parseString("<a><![CDATA[raw & <t>]]></a>")
    @Expect(DocumentSerializer.toString(doc), "<a><![CDATA[raw & <t>]]></a>")
}

@Test
public func testCdataAsTextLowers(): Unit {
    let doc = DocumentBuilder.parseString("<a><![CDATA[raw & <t>]]></a>")
    @Expect(
        DocumentSerializer.toString(doc, opts: SerializeOptions(cdataAsText: true)),
        "<a>raw &amp; &lt;t&gt;</a>"
    )
}

/* ---------- Prolog / Epilog / 声明 / DOCTYPE ---------- */

@Test
public func testCommentAndPiInProlog(): Unit {
    let doc = DocumentBuilder.parseString("<!-- hi --><?t d?><a/>")
    @Expect(DocumentSerializer.toString(doc), "<!-- hi --><?t d?><a/>")
}

@Test
public func testCommentInEpilog(): Unit {
    let doc = DocumentBuilder.parseString("<a/><!-- bye -->")
    @Expect(DocumentSerializer.toString(doc), "<a/><!-- bye -->")
}

@Test
public func testRealXmlDeclPreserved(): Unit {
    let doc = DocumentBuilder.parseString("<?xml version=\"1.0\" encoding=\"UTF-8\"?><a/>")
    @Expect(DocumentSerializer.toString(doc), "<?xml version=\"1.0\" encoding=\"UTF-8\"?><a/>")
}

@Test
public func testSyntheticXmlDeclOmittedByDefault(): Unit {
    let doc = DocumentBuilder.parseString("<a/>")
    // 默认 omitSyntheticXmlDeclaration=true → 不输出合成声明
    @Expect(DocumentSerializer.toString(doc), "<a/>")
}

@Test
public func testOmitXmlDeclarationForces(): Unit {
    let doc = DocumentBuilder.parseString("<?xml version=\"1.0\"?><a/>")
    @Expect(
        DocumentSerializer.toString(doc, opts: SerializeOptions(omitXmlDeclaration: true)),
        "<a/>"
    )
}

@Test
public func testDoctypeEmitted(): Unit {
    let doc = DocumentBuilder.parseString("<!DOCTYPE root><root/>")
    @Expect(DocumentSerializer.toString(doc), "<!DOCTYPE root><root/>")
}

@Test
public func testStandaloneFlags(): Unit {
    let a = DocumentBuilder.parseString("<?xml version=\"1.0\" standalone=\"yes\"?><r/>")
    @Expect(DocumentSerializer.toString(a), "<?xml version=\"1.0\" standalone=\"yes\"?><r/>")
    let b = DocumentBuilder.parseString("<?xml version=\"1.0\" standalone=\"no\"?><r/>")
    @Expect(DocumentSerializer.toString(b), "<?xml version=\"1.0\" standalone=\"no\"?><r/>")
}

/* ---------- 缩进 pretty-print ---------- */

@Test
public func testPrettyIndent(): Unit {
    let doc = DocumentBuilder.parseString("<a><b/><c>x</c></a>")
    let out = DocumentSerializer.toString(doc, opts: SerializeOptions.pretty())
    @Expect(out.contains("<a>"), true)
    @Expect(out.contains("  <b/>"), true)
    @Expect(out.contains("  <c>x</c>"), true)
    @Expect(out.contains("</a>"), true)
    // 仍可 parse 回良构文档；缩进引入的 whitespace-only 文本节点不影响结构
    let doc2 = DocumentBuilder.parseString(out)
    @Expect(doc2.root.qname.localName, "a")
    var elemChildren = 0
    for (c in doc2.root.children()) {
        match (c) {
            case _: Element => elemChildren += 1
            case _ => ()
        }
    }
    @Expect(elemChildren, 2)
}

@Test
public func testPrettyCustomIndentString(): Unit {
    let doc = DocumentBuilder.parseString("<a><b/></a>")
    let out = DocumentSerializer.toString(
        doc,
        opts: SerializeOptions(indent: true, indentString: "\t")
    )
    @Expect(out.contains("\t<b/>"), true)
}

/* ---------- elementToString 片段 ---------- */

@Test
public func testElementToStringFragment(): Unit {
    let doc = DocumentBuilder.parseString("<root><a k=\"1\">t</a></root>")
    match (doc.root.childAt(0)) {
        case e: Element =>
            @Expect(DocumentSerializer.elementToString(e), "<a k=\"1\">t</a>")
        case _ => @Fail("expected Element")
    }
}

/* ---------- Round-trip：parse → serialize → parse ---------- */

func roundTrip(src: String): Document {
    let once = DocumentBuilder.parseString(src)
    let out = DocumentSerializer.toString(once)
    return DocumentBuilder.parseString(out)
}

@Test
public func testRoundTripSimple(): Unit {
    let d = roundTrip("<a><b/><c>x</c></a>")
    @Expect(d.root.qname.localName, "a")
    @Expect(d.root.childCount(), 2)
    @Expect(d.root.allText(), "x")
}

@Test
public func testRoundTripAttributesAndNs(): Unit {
    let d = roundTrip("<r xmlns=\"urn:a\" xmlns:p=\"urn:b\" k=\"v\"><p:c x=\"1\"/></r>")
    @Expect(d.root.qname.uri.getOrThrow(), "urn:a")
    @Expect(d.root.findAttribute("k").getOrThrow().value, "v")
    match (d.root.childAt(0)) {
        case e: Element =>
            @Expect(e.qname.uri.getOrThrow(), "urn:b")
            @Expect(e.findAttribute("x").getOrThrow().value, "1")
        case _ => @Fail("expected Element")
    }
}

@Test
public func testRoundTripMixedContent(): Unit {
    let d = roundTrip("<a>hi <b>inner</b> there <!-- c --><?pi d?></a>")
    @Expect(d.root.qname.localName, "a")
    @Expect(d.root.allText(), "hi inner there ")
    var commentCount = 0
    var piCount = 0
    for (c in d.root.children()) {
        match (c) {
            case _: CommentNode => commentCount += 1
            case _: PiNode => piCount += 1
            case _ => ()
        }
    }
    @Expect(commentCount, 1)
    @Expect(piCount, 1)
}

@Test
public func testRoundTripCdata(): Unit {
    let d = roundTrip("<a>before<![CDATA[x & <y>]]>after</a>")
    // CDATA 经往返后仍然作为独立 CdataSection 节点存在
    var sawCdata = false
    for (c in d.root.children()) {
        match (c) {
            case cc: CdataSection =>
                @Expect(cc.data, "x & <y>")
                sawCdata = true
            case _ => ()
        }
    }
    @Expect(sawCdata, true)
    @Expect(d.root.allText(), "beforex & <y>after")
}

@Test
public func testRoundTripEntitiesInAttribute(): Unit {
    let d = roundTrip("<a k=\"&amp;&lt;&quot;\"/>")
    @Expect(d.root.findAttribute("k").getOrThrow().value, "&<\"")
}

@Test
public func testRoundTripPrettyPreservesStructure(): Unit {
    let once = DocumentBuilder.parseString("<a><b><c/></b><d>t</d></a>")
    let pretty = DocumentSerializer.toString(once, opts: SerializeOptions.pretty())
    let d = DocumentBuilder.parseString(pretty)
    @Expect(d.root.qname.localName, "a")
    // 缩进引入 whitespace-only 文本节点；我们只关心元素子节点的语义
    let elems = ArrayList<Element>()
    for (c in d.root.children()) {
        match (c) {
            case e: Element => elems.add(e)
            case _ => ()
        }
    }
    @Expect(elems.size, 2)
    @Expect(elems[0].qname.localName, "b")
    @Expect(elems[1].qname.localName, "d")
    @Expect(elems[1].directText(), "t")
}
