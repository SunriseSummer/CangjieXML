package cangjie_xml.parser

import std.unittest.*
import cangjie_xml.core.*

@Test
public func testXmlDeclBasic(): Unit {
    let d = XmlDecl(version: "1.0", encoding: Some("UTF-8"), standalone: Standalone.Yes)
    @Expect(d.version, "1.0")
    @Expect(d.encoding.getOrThrow(), "UTF-8")
    @Expect(d.standalone == Standalone.Yes, true)
    @Expect(d.toString(), "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>")
}

@Test
public func testXmlDeclDefaults(): Unit {
    let d = XmlDecl()
    @Expect(d.version, "1.0")
    @Expect(d.encoding.isNone(), true)
    @Expect(d.standalone == Standalone.Unspecified, true)
}

@Test
public func testStandaloneEquality(): Unit {
    @Expect(Standalone.Yes == Standalone.Yes, true)
    @Expect(Standalone.Yes != Standalone.No, true)
    @Expect(Standalone.Unspecified == Standalone.Unspecified, true)
}

@Test
public func testAttributeToString(): Unit {
    let a = Attribute(QName("x"), "1")
    @Expect(a.toString(), "x=\"1\"")
    @Expect(a.isNamespaceDeclaration, false)
}

@Test
public func testSaxEventToString(): Unit {
    let e = SaxEvent.Characters(Position.unknown(), "hello")
    @Expect(e.toString(), "Characters(5 chars)")
    let s = SaxEvent.StartElement(Position.unknown(), QName("a"), [], NsContext.root())
    @Expect(s.toString(), "StartElement(a, 0 attrs)")
}

@Test
public func testSaxEventPosition(): Unit {
    let p = Position(source: "f.xml", line: 3, column: 7, byteOffset: 42)
    let e = SaxEvent.Characters(p, "x")
    @Expect(e.position().line, 3)
    @Expect(e.position().column, 7)
}
