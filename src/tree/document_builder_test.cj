/*
 * tree — DocumentBuilder 单元测试
 *
 * 覆盖 Phase 4a MVP 的全部路径：
 *   - 骨架：空根 / 自闭合 / 嵌套 / 深嵌套
 *   - 属性：普通 / 命名空间 / 实体展开后的属性值
 *   - 文本：Characters 合并 / CDATA 独立 / 混合 / 仅空白
 *   - Prolog / Epilog：Comment / PI 正确归位；DOCTYPE 不入 prolog 列表
 *   - 文本聚合：`directText` 浅、 `allText` 深
 *   - 查找：`findAttribute` / `findChildren`
 *   - 命名空间：Element.ns 保留上下文
 *   - 错误：无根元素 / ParseError → XmlException
 */
package cangjie_xml.tree

import std.unittest.*
import std.collection.*
import cangjie_xml.core.*
import cangjie_xml.parser.*

/* ---------- 骨架 ---------- */

@Test
public func testSelfClosingRoot(): Unit {
    let doc = DocumentBuilder.parseString("<a/>")
    @Expect(doc.root.qname.localName, "a")
    @Expect(doc.root.childCount(), 0)
    @Expect(doc.root.attributeCount(), 0)
    @Expect(doc.root.parent().isNone(), true)
}

@Test
public func testEmptyRootWithEndTag(): Unit {
    let doc = DocumentBuilder.parseString("<a></a>")
    @Expect(doc.root.qname.localName, "a")
    @Expect(doc.root.childCount(), 0)
}

@Test
public func testNestedElements(): Unit {
    let doc = DocumentBuilder.parseString("<a><b><c/></b></a>")
    @Expect(doc.root.qname.localName, "a")
    @Expect(doc.root.childCount(), 1)
    let b = doc.root.childAt(0)
    match (b) {
        case be: Element =>
            @Expect(be.qname.localName, "b")
            @Expect(be.parent().isSome(), true)
            @Expect(be.parent().getOrThrow().qname.localName, "a")
            @Expect(be.childCount(), 1)
            let c = be.childAt(0)
            match (c) {
                case ce: Element =>
                    @Expect(ce.qname.localName, "c")
                    @Expect(ce.parent().getOrThrow().qname.localName, "b")
                case _ => @Fail("c not Element")
            }
        case _ => @Fail("b not Element")
    }
}

@Test
public func testSiblingElements(): Unit {
    let doc = DocumentBuilder.parseString("<r><a/><b/><c/></r>")
    @Expect(doc.root.childCount(), 3)
    let locals = ArrayList<String>()
    for (ch in doc.root.children()) {
        match (ch) {
            case e: Element => locals.add(e.qname.localName)
            case _ => ()
        }
    }
    @Expect(locals.size, 3)
    @Expect(locals[0], "a")
    @Expect(locals[1], "b")
    @Expect(locals[2], "c")
}

/* ---------- 属性 ---------- */

@Test
public func testAttributes(): Unit {
    let doc = DocumentBuilder.parseString("<e x=\"1\" y='2'/>")
    @Expect(doc.root.attributeCount(), 2)
    @Expect(doc.root.findAttribute("x").getOrThrow().value, "1")
    @Expect(doc.root.findAttribute("y").getOrThrow().value, "2")
    @Expect(doc.root.findAttribute("z").isNone(), true)
}

@Test
public func testAttributeEntityExpansion(): Unit {
    let doc = DocumentBuilder.parseString("<e x=\"&amp;&lt;\"/>")
    @Expect(doc.root.findAttribute("x").getOrThrow().value, "&<")
}

@Test
public func testNamespacedAttribute(): Unit {
    let doc = DocumentBuilder.parseString("<e xmlns:p=\"urn:x\" p:k=\"v\"/>")
    // p:k 的扩展名为 (k, urn:x)
    @Expect(doc.root.findAttribute("k", uri: Some("urn:x")).getOrThrow().value, "v")
    // 无命名空间下查不到
    @Expect(doc.root.findAttribute("k").isNone(), true)
}

/* ---------- 文本 / CDATA ---------- */

@Test
public func testTextContent(): Unit {
    let doc = DocumentBuilder.parseString("<a>hello</a>")
    @Expect(doc.root.childCount(), 1)
    match (doc.root.childAt(0)) {
        case t: TextNode => @Expect(t.data, "hello")
        case _ => @Fail("expected TextNode")
    }
    @Expect(doc.root.directText(), "hello")
}

@Test
public func testMixedTextAndElements(): Unit {
    let doc = DocumentBuilder.parseString("<a>hi <b/> there</a>")
    @Expect(doc.root.childCount(), 3)
    @Expect(doc.root.allText(), "hi  there")
}

@Test
public func testCdataIndependentNode(): Unit {
    let doc = DocumentBuilder.parseString("<a>x<![CDATA[raw & <tag>]]>y</a>")
    @Expect(doc.root.childCount(), 3)
    match (doc.root.childAt(1)) {
        case c: CdataSection => @Expect(c.data, "raw & <tag>")
        case _ => @Fail("expected CdataSection")
    }
    @Expect(doc.root.directText(), "xraw & <tag>y")
}

@Test
public func testAllTextRecursive(): Unit {
    let doc = DocumentBuilder.parseString("<a>X<b>Y<c>Z</c>W</b>V</a>")
    @Expect(doc.root.allText(), "XYZWV")
    @Expect(doc.root.directText(), "XV")
}

/* ---------- Prolog / Epilog / Doctype ---------- */

@Test
public func testPrologCommentAndPi(): Unit {
    let doc = DocumentBuilder.parseString("<!-- hi --><?tgt d?><a/>")
    let prolog = ArrayList<Node>()
    for (n in doc.prolog()) {
        prolog.add(n)
    }
    @Expect(prolog.size, 2)
    match (prolog[0]) {
        case c: CommentNode => @Expect(c.data, " hi ")
        case _ => @Fail("expected Comment")
    }
    match (prolog[1]) {
        case p: PiNode =>
            @Expect(p.target, "tgt")
            @Expect(p.data, "d")
        case _ => @Fail("expected PiNode")
    }
}

@Test
public func testEpilogCommentAfterRoot(): Unit {
    let doc = DocumentBuilder.parseString("<a/><!-- bye -->")
    let epilog = ArrayList<Node>()
    for (n in doc.epilog()) {
        epilog.add(n)
    }
    @Expect(epilog.size, 1)
    match (epilog[0]) {
        case c: CommentNode => @Expect(c.data, " bye ")
        case _ => @Fail("expected Comment")
    }
}

@Test
public func testDoctypeCaptured(): Unit {
    let doc = DocumentBuilder.parseString("<!DOCTYPE root><root/>")
    @Expect(doc.doctype.isSome(), true)
    @Expect(doc.doctype.getOrThrow().name, "root")
    // DOCTYPE 不应同时出现在 prolog 迭代器中
    let prolog = ArrayList<Node>()
    for (n in doc.prolog()) {
        prolog.add(n)
    }
    @Expect(prolog.size, 0)
}

/* ---------- 查找 / 命名空间 ---------- */

@Test
public func testFindChildrenByLocalName(): Unit {
    let doc = DocumentBuilder.parseString("<r><a/><b/><a/></r>")
    let as_ = ArrayList<Element>()
    for (e in doc.root.findChildren("a")) {
        as_.add(e)
    }
    @Expect(as_.size, 2)
}

@Test
public func testFindChildrenByNamespace(): Unit {
    let doc = DocumentBuilder.parseString(
        "<r xmlns:p=\"urn:x\"><p:a/><a/><p:a/></r>"
    )
    let ns = ArrayList<Element>()
    for (e in doc.root.findChildren("a", uri: Some("urn:x"))) {
        ns.add(e)
    }
    let noNs = ArrayList<Element>()
    for (e in doc.root.findChildren("a")) {
        noNs.add(e)
    }
    @Expect(ns.size, 2)
    @Expect(noNs.size, 1)
}

@Test
public func testElementNsContextPreserved(): Unit {
    let doc = DocumentBuilder.parseString(
        "<r xmlns=\"urn:default\" xmlns:p=\"urn:x\"><p:c/></r>"
    )
    // 根元素绑定 urn:default
    @Expect(doc.root.qname.uri.getOrThrow(), "urn:default")
    // 子元素绑定 urn:x
    match (doc.root.childAt(0)) {
        case e: Element =>
            @Expect(e.qname.uri.getOrThrow(), "urn:x")
            // Element.ns 上下文可解析前缀 p
            @Expect(e.ns.resolve(Some("p")).getOrThrow(), "urn:x")
        case _ => @Fail("expected Element")
    }
}

/* ---------- 错误路径 ---------- */

@Test
public func testMalformedInputRaises(): Unit {
    var threw = false
    try {
        let _ = DocumentBuilder.parseString("<a><b></a>")
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testNodeKindsReportCorrectly(): Unit {
    let doc = DocumentBuilder.parseString("<!-- c --><?pi d?><a>t<![CDATA[x]]></a>")
    @Expect(doc.nodeKind(), NodeKind.DocumentNode)
    @Expect(doc.root.nodeKind(), NodeKind.ElementNode)
    match (doc.root.childAt(0)) {
        case t: TextNode => @Expect(t.nodeKind(), NodeKind.TextNodeKind)
        case _ => @Fail("expected Text")
    }
    match (doc.root.childAt(1)) {
        case c: CdataSection => @Expect(c.nodeKind(), NodeKind.CdataSectionNode)
        case _ => @Fail("expected Cdata")
    }
}

@Test
public func testXmlDeclCapturedOrSynthesized(): Unit {
    let docA = DocumentBuilder.parseString("<?xml version=\"1.0\" encoding=\"UTF-8\"?><r/>")
    @Expect(docA.xmlDecl.encoding.getOrThrow(), "UTF-8")

    let docB = DocumentBuilder.parseString("<r/>")
    // 无显式声明时也应返回合成的 XmlDecl；encoding 为 None
    @Expect(docB.xmlDecl.encoding.isNone(), true)
}
