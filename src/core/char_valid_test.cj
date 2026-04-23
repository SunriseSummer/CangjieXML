package cangjie_xml.core

import std.unittest.*

@Test
public func testAsciiNameChars(): Unit {
    // 'A' .. 'Z' / 'a' .. 'z' / '_' / ':'
    @Expect(isNameStartChar(Int32(UInt32(r'A'))), true)
    @Expect(isNameStartChar(Int32(UInt32(r'z'))), true)
    @Expect(isNameStartChar(Int32(UInt32(r'_'))), true)
    @Expect(isNameStartChar(Int32(UInt32(r':'))), true)
    // 数字与 '-' 不能作为首字符
    @Expect(isNameStartChar(Int32(UInt32(r'0'))), false)
    @Expect(isNameStartChar(Int32(UInt32(r'-'))), false)
    // 但可作为后续 NameChar
    @Expect(isNameChar(Int32(UInt32(r'0'))), true)
    @Expect(isNameChar(Int32(UInt32(r'-'))), true)
    @Expect(isNameChar(Int32(UInt32(r'.'))), true)
}

@Test
public func testXmlCharRanges(): Unit {
    // XML 1.0 禁用 NUL / 控制符（除了 \t \n \r）
    @Expect(isXmlChar(0x0), false)
    @Expect(isXmlChar(0x1), false)
    @Expect(isXmlChar(0x9), true)
    @Expect(isXmlChar(0xA), true)
    @Expect(isXmlChar(0xC), false)
    @Expect(isXmlChar(0xD), true)
    @Expect(isXmlChar(0x1F), false)
    @Expect(isXmlChar(0x20), true)
    @Expect(isXmlChar(0xD7FF), true)
    @Expect(isXmlChar(0xD800), false) // surrogate
    @Expect(isXmlChar(0xDFFF), false)
    @Expect(isXmlChar(0xE000), true)
    @Expect(isXmlChar(0xFFFD), true)
    @Expect(isXmlChar(0xFFFE), false)
    @Expect(isXmlChar(0x10000), true)
    @Expect(isXmlChar(0x10FFFF), true)
    @Expect(isXmlChar(0x110000), false)

    // XML 1.1 允许 [#x1-#x8] 等（但仍需字符引用），但 NUL 除外
    @Expect(isXmlChar(0x0, version: XmlVersion.V11), false)
    @Expect(isXmlChar(0x1, version: XmlVersion.V11), true)
    @Expect(isXmlChar(0xC, version: XmlVersion.V11), true)
}

@Test
public func testWhitespaceAndPubid(): Unit {
    @Expect(isXmlWhitespace(Int32(UInt32(r' '))), true)
    @Expect(isXmlWhitespace(Int32(UInt32(r'\t'))), true)
    @Expect(isXmlWhitespace(Int32(UInt32(r'\n'))), true)
    @Expect(isXmlWhitespace(Int32(UInt32(r'\r'))), true)
    @Expect(isXmlWhitespace(Int32(UInt32(r'A'))), false)

    @Expect(isPubidChar(Int32(UInt32(r'A'))), true)
    @Expect(isPubidChar(Int32(UInt32(r'0'))), true)
    @Expect(isPubidChar(Int32(UInt32(r'-'))), true)
    @Expect(isPubidChar(Int32(UInt32(r'/'))), true)
    @Expect(isPubidChar(Int32(UInt32(r'&'))), false)
    @Expect(isPubidChar(0xA1), false) // 非 ASCII
}

@Test
public func testValidName(): Unit {
    @Expect(isValidName("element"), true)
    @Expect(isValidName("ns:element"), true)
    @Expect(isValidName("_x"), true)
    @Expect(isValidName("a-b.c_d"), true)
    @Expect(isValidName("中文"), true)
    @Expect(isValidName(""), false)
    @Expect(isValidName("1abc"), false)
    @Expect(isValidName("-abc"), false)
    @Expect(isValidName("a b"), false)

    @Expect(isValidNcName("element"), true)
    @Expect(isValidNcName("ns:element"), false)
    @Expect(isValidNcName("中文"), true)
}

@Test
public func testValidXmlString(): Unit {
    @Expect(isValidXmlString("hello world"), true)
    @Expect(isValidXmlString("line1\nline2\tfoo"), true)
    @Expect(isValidXmlString("中文字符串"), true)
    // NUL 永远非法
    let withNul = String.fromUtf8([0x41u8, 0x0u8, 0x42u8])
    @Expect(isValidXmlString(withNul), false)
}

@Test
public func testXml11RestrictedChars(): Unit {
    @Expect(isXml11RestrictedChar(0x1), true)
    @Expect(isXml11RestrictedChar(0x9), false)
    @Expect(isXml11RestrictedChar(0xA), false)
    @Expect(isXml11RestrictedChar(0xD), false)
    @Expect(isXml11RestrictedChar(0x7F), true)
    @Expect(isXml11RestrictedChar(0x85), false) // 合法 NEL（虽然需归一化）
    @Expect(isXml11RestrictedChar(0x20), false)
}
