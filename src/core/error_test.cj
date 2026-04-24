package cangjie_xml.core

import std.unittest.*

@Test
public func testPositionKnown(): Unit {
    let p = Position(source: Some("a.xml"), line: 3, column: 5, byteOffset: 42)
    @Expect(p.isKnown(), true)
    @Expect(p.toString(), "a.xml:3:5")
}

@Test
public func testPositionUnknown(): Unit {
    let p = Position.unknown()
    @Expect(p.isKnown(), false)
    @Expect(p.toString().contains("?"), true)
}

@Test
public func testXmlErrorProperties(): Unit {
    let p = Position(source: Some("doc.xml"), line: 1, column: 1, byteOffset: 0)
    let e = XmlError.Malformed(p, "stray gt")
    @Expect(e.position() == p, true)
    @Expect(e.message(), "malformed: stray gt")
    match (e.defaultSeverity()) {
        case Fatal => ()
        case _ => @Fail("expected Fatal")
    }
}

@Test
public func testListErrorCollector(): Unit {
    let c = ListErrorCollector()
    @Expect(c.isEmpty(), true)
    c.report(Severity.Warning, XmlError.Other(Position.unknown(), "m1"))
    c.report(Severity.Fatal, XmlError.UnexpectedEof(Position.unknown(), "m2"))
    @Expect(c.size(), 2)
    @Expect(c.hasFatal(), true)
    @Expect(c.entries().size, 2)
}

@Test
public func testXmlException(): Unit {
    let ex = XmlException(XmlError.UriError("bad"))
    @Expect(ex.message.contains("URI error"), true)
    match (ex.error) {
        case UriError(m) => @Expect(m, "bad")
        case _ => @Fail("wrong error variant")
    }
}
