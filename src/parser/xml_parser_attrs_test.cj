/*
 * XmlParser 单元测试：属性聚合 / 重复 / 实体展开。
 */
package cangjie_xml.parser

import std.unittest.*
import cangjie_xml.core.*

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

