/*
 * XmlParser 单元测试：`ParserOptions` 的各项开关 / 资源限制。
 */
package cangjie_xml.parser

import std.unittest.*
import std.collection.*
import cangjie_xml.core.*

/* ---------- Options ---------- */

@Test
public func testKeepBlanksFalseSkipsWhitespaceOnly(): Unit {
    let opts = ParserOptions(keepBlanks: false)
    let evs = events("<a>  <b/>  </a>", opts: opts)
    for (e in evs) {
        match (e) {
            case Characters(_, _) => @Fail("expected no whitespace-only Characters")
            case _ => ()
        }
    }
}

@Test
public func testKeepBlanksTrueKeepsWhitespace(): Unit {
    let evs = events("<a>  </a>")
    var found = false
    for (e in evs) {
        match (e) {
            case Characters(_, s) =>
                found = true
                @Expect(s, "  ")
            case _ => ()
        }
    }
    @Expect(found, true)
}

@Test
public func testSubstituteEntitiesFalseEmitsEntityReference(): Unit {
    let opts = ParserOptions(substituteEntities: false)
    let evs = events("<a>foo&amp;bar</a>", opts: opts)
    var sawRef = false
    var sawBar = false
    for (e in evs) {
        match (e) {
            case EntityReference(_, n) =>
                sawRef = true
                @Expect(n, "amp")
            case Characters(_, s) where s == "foo" => ()
            case Characters(_, s) where s == "bar" => sawBar = true
            case _ => ()
        }
    }
    @Expect(sawRef, true)
    @Expect(sawBar, true)
}

@Test
public func testMaxDepthExceeded(): Unit {
    let opts = ParserOptions(maxDepth: 3)
    var threw = false
    try {
        let _ = events("<a><b><c><d/></c></b></a>", opts: opts)
    } catch (e: XmlException) {
        match (e.error) {
            case LimitExceeded(_, _) => threw = true
            case _ => ()
        }
    }
    @Expect(threw, true)
}

@Test
public func testMaxEntityExpansion(): Unit {
    // 默认 10_000_000 太大，测试中降下来
    let opts = ParserOptions(maxEntityExpansion: 3)
    var threw = false
    try {
        let _ = events("<a>&amp;&amp;&amp;&amp;</a>", opts: opts)
    } catch (e: XmlException) {
        match (e.error) {
            case LimitExceeded(_, _) => threw = true
            case _ => ()
        }
    }
    @Expect(threw, true)
}

@Test
public func testCustomEntityResolver(): Unit {
    let opts = ParserOptions(entityResolver: Some(MapEntityResolver([("nbsp", "\u{00A0}")])))
    let evs = events("<a>foo&nbsp;bar</a>", opts: opts)
    var combined = ""
    for (e in evs) {
        match (e) {
            case Characters(_, s) => combined += s
            case _ => ()
        }
    }
    @Expect(combined, "foo\u{00A0}bar")
}

@Test
public func testNameTableInterning(): Unit {
    let nt = NameTable()
    let opts = ParserOptions(nameTable: Some(nt))
    let evs = events("<a x=\"1\"><a x=\"2\"/></a>", opts: opts)
    // 应该不报错，并且两个 <a> 元素的 localName 来自同一个池
    var names = ArrayList<String>()
    for (e in evs) {
        match (e) {
            case StartElement(_, n, _, _) => names.add(n.localName)
            case _ => ()
        }
    }
    @Expect(names.size, 2)
    @Expect(names[0], "a")
    @Expect(names[1], "a")
}

