/*
 * XmlParser 单元测试：文档骨架 / XML 声明。
 *
 * 共享辅助函数 `events` / `kind` 在 `xml_parser_test_helpers.cj` 中。
 */
package cangjie_xml.parser

import std.unittest.*
import cangjie_xml.core.*

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

