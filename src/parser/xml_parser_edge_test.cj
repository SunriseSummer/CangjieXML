/*
 * XmlParser 单元测试：边界 & QName 扩展名冲突。
 */
package cangjie_xml.parser

import std.unittest.*
import cangjie_xml.core.*

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
