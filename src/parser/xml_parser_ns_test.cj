/*
 * XmlParser 单元测试：命名空间绑定 / xml / xmlns 硬约束。
 */
package cangjie_xml.parser

import std.unittest.*
import cangjie_xml.core.*

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

