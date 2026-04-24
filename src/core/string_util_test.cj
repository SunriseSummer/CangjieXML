package cangjie_xml.core

import std.unittest.*

@Test
public func testEscapeXmlText(): Unit {
    @Expect(escapeXml("a & b < c > d"), "a &amp; b &lt; c &gt; d")
    // 文本模式下单双引号、换行等保持原样
    @Expect(escapeXml("he said \"hi\""), "he said \"hi\"")
    @Expect(escapeXml("line1\nline2"), "line1\nline2")
}

@Test
public func testEscapeXmlAttribute(): Unit {
    @Expect(escapeXml("a&b", forAttribute: true), "a&amp;b")
    @Expect(escapeXml("\"quoted\"", forAttribute: true), "&quot;quoted&quot;")
    @Expect(escapeXml("'q'", forAttribute: true), "&apos;q&apos;")
    @Expect(escapeXml("tab\tnl\nCR\r", forAttribute: true), "tab&#9;nl&#10;CR&#13;")
}

@Test
public func testNormalizeWhitespace(): Unit {
    @Expect(normalizeWhitespace("  a   b\tc\nd  "), "a b c d")
    @Expect(normalizeWhitespace(""), "")
    @Expect(normalizeWhitespace("   "), "")
    @Expect(normalizeWhitespace("one"), "one")
}

@Test
public func testNormalizeNewlines(): Unit {
    @Expect(normalizeNewlines("a\r\nb\rc\n"), "a\nb\nc\n")
    @Expect(normalizeNewlines("xyz"), "xyz")
    // XML 1.1 还应归一 NEL / LS
    let nel = String.fromUtf8([0x61u8, 0xC2u8, 0x85u8, 0x62u8]) // "a<NEL>b"
    @Expect(normalizeNewlines(nel, xml11: true), "a\nb")
    @Expect(normalizeNewlines(nel, xml11: false), nel) // 1.0 下不变
}

@Test
public func testBytesToStringInvalid(): Unit {
    var thrown = false
    try {
        let _ = bytesToString([0xC3u8, 0x28u8]) // 非法 UTF-8
    } catch (_: XmlException) {
        thrown = true
    }
    @Expect(thrown, true)
}
