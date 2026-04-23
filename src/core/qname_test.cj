package cangjie_xml.core

import std.unittest.*

@Test
public func testQNameBasics(): Unit {
    let q = QName.of("name")
    @Expect(q.localName, "name")
    @Expect(q.prefix.isNone(), true)
    @Expect(q.uri.isNone(), true)
    @Expect(q.lexical(), "name")
    @Expect(q.expanded(), "name")
}

@Test
public func testQNameFromLexical(): Unit {
    let q = QName.fromLexical("xs:element")
    @Expect(q.prefix, Some("xs"))
    @Expect(q.localName, "element")
    @Expect(q.uri.isNone(), true)
    @Expect(q.lexical(), "xs:element")
}

@Test
public func testQNameEqualityIgnoresPrefix(): Unit {
    let nsUri = Some<String>("http://example.com/ns")
    let a = QName("elem", prefix: Some("p1"), uri: nsUri)
    let b = QName("elem", prefix: Some("p2"), uri: nsUri)
    let c = QName("elem", prefix: None, uri: nsUri)
    @Expect(a, b) // 命名空间与本地名一致
    @Expect(a, c)
    @Expect(a.hashCode(), b.hashCode())

    let d = QName("elem", prefix: None, uri: Some<String>("http://other"))
    @Expect(a != d, true)
}

@Test
public func testQNameBuilders(): Unit {
    let q = QName.of("foo").withPrefix(Some("p")).withUri(Some("urn:x"))
    @Expect(q.lexical(), "p:foo")
    @Expect(q.expanded(), "{urn:x}foo")
}
