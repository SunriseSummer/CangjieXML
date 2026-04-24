package cangjie_xml.parser

import std.unittest.*

@Test
public func testNsRootHasXmlPrefix(): Unit {
    let root = NsContext.root()
    @Expect(root.resolve(Some("xml")).getOrThrow(), XML_NAMESPACE_URI)
    @Expect(root.defaultNs().isNone(), true)
}

@Test
public func testNsPushDefault(): Unit {
    let ns = NsContext.root().push(None<String>, Some("http://example.com/ns"))
    @Expect(ns.defaultNs().getOrThrow(), "http://example.com/ns")
    // xml 仍然可解析
    @Expect(ns.resolve(Some("xml")).getOrThrow(), XML_NAMESPACE_URI)
}

@Test
public func testNsPushPrefix(): Unit {
    let ns = NsContext.root().push(Some("a"), Some("urn:a"))
    @Expect(ns.resolve(Some("a")).getOrThrow(), "urn:a")
    @Expect(ns.resolve(Some("b")).isNone(), true)
}

@Test
public func testNsShadowing(): Unit {
    let outer = NsContext.root().push(Some("p"), Some("urn:outer"))
    let inner = outer.push(Some("p"), Some("urn:inner"))
    @Expect(inner.resolve(Some("p")).getOrThrow(), "urn:inner")
    // outer 不变
    @Expect(outer.resolve(Some("p")).getOrThrow(), "urn:outer")
}

@Test
public func testNsUnbindPrefix(): Unit {
    let outer = NsContext.root().push(Some("p"), Some("urn:a"))
    let inner = outer.push(Some("p"), None)
    @Expect(inner.resolve(Some("p")).isNone(), true)
    @Expect(outer.resolve(Some("p")).getOrThrow(), "urn:a")
}

@Test
public func testNsImmutability(): Unit {
    let r = NsContext.root()
    let a = r.push(Some("x"), Some("urn:1"))
    let b = r.push(Some("x"), Some("urn:2"))
    @Expect(a.resolve(Some("x")).getOrThrow(), "urn:1")
    @Expect(b.resolve(Some("x")).getOrThrow(), "urn:2")
    @Expect(r.resolve(Some("x")).isNone(), true)
}

@Test
public func testNsBindingsListsOnlyInnermost(): Unit {
    let ns = NsContext.root()
        .push(Some("p"), Some("urn:outer"))
        .push(Some("p"), Some("urn:inner"))
        .push(None<String>, Some("urn:default"))
    let b = ns.bindings()
    // 期望包含：default="urn:default"、p="urn:inner"、xml=固定
    var sawDefault = false
    var sawPInner = false
    var sawXml = false
    for ((pfx, uri) in b) {
        match (pfx) {
            case None =>
                sawDefault = true
                @Expect(uri.getOrThrow(), "urn:default")
            case Some(p) where p == "p" =>
                sawPInner = true
                @Expect(uri.getOrThrow(), "urn:inner")
            case Some(p) where p == "xml" =>
                sawXml = true
                @Expect(uri.getOrThrow(), XML_NAMESPACE_URI)
            case _ => ()
        }
    }
    @Expect(sawDefault, true)
    @Expect(sawPInner, true)
    @Expect(sawXml, true)
}

@Test
public func testNsXmlnsPrefixHardcoded(): Unit {
    let r = NsContext.root()
    @Expect(r.resolve(Some("xmlns")).getOrThrow(), XMLNS_NAMESPACE_URI)
}
