package cangjie_xml.io

import std.unittest.*
import cangjie_xml.encoding.*

@Test
public func testDecodingSourceUtf8NoBom(): Unit {
    let src = StringSource("Hello 中")
    let ds = DecodingSource(src)
    @Expect(ds.detectedEncoding, "utf-8")
    @Expect(ds.bom.isNone(), true)
    @Expect(ds.readAllAsString(), "Hello 中")
}

@Test
public func testDecodingSourceUtf8WithBom(): Unit {
    // EF BB BF + "Hi"
    let src = MemorySource([0xEFu8, 0xBBu8, 0xBFu8, 0x48u8, 0x69u8])
    let ds = DecodingSource(src)
    @Expect(ds.detectedEncoding, "utf-8")
    match (ds.bom) {
        case Some(k) => @Expect(k == BomKind.Utf8, true)
        case None => @Fail("expected Utf8 BOM")
    }
    @Expect(ds.readAllAsString(), "Hi")
}

@Test
public func testDecodingSourceUtf16BeBom(): Unit {
    // FE FF + 00 41 + 00 42
    let src = MemorySource([0xFEu8, 0xFFu8, 0x00u8, 0x41u8, 0x00u8, 0x42u8])
    let ds = DecodingSource(src)
    @Expect(ds.detectedEncoding, "utf-16be")
    @Expect(ds.readAllAsString(), "AB")
}

@Test
public func testDecodingSourceUtf16LeBom(): Unit {
    // FF FE + 41 00 + 42 00
    let src = MemorySource([0xFFu8, 0xFEu8, 0x41u8, 0x00u8, 0x42u8, 0x00u8])
    let ds = DecodingSource(src)
    @Expect(ds.detectedEncoding, "utf-16le")
    @Expect(ds.readAllAsString(), "AB")
}

@Test
public func testDecodingSourceUtf32LeBomPriorityOverUtf16(): Unit {
    // FF FE 00 00 + 41 00 00 00 → UTF-32 LE "A"
    let src = MemorySource([0xFFu8, 0xFEu8, 0x00u8, 0x00u8, 0x41u8, 0x00u8, 0x00u8, 0x00u8])
    let ds = DecodingSource(src)
    @Expect(ds.detectedEncoding, "utf-32le")
    @Expect(ds.readAllAsString(), "A")
}

@Test
public func testDecodingSourceEncodingHint(): Unit {
    // 无 BOM，提示 iso-8859-1；0xE9 → U+00E9
    let src = MemorySource([0xE9u8, 0x21u8], encodingHint: Some("iso-8859-1"))
    let ds = DecodingSource(src)
    @Expect(ds.detectedEncoding, "iso-8859-1")
    @Expect(ds.readAllAsString(), "\u{00E9}!")
}

@Test
public func testDecodingSourceExplicitOverridesHint(): Unit {
    // hint 是 latin-1 但显式指定为 ascii；字节全在 ASCII 范围则 ok
    let src = MemorySource([0x41u8, 0x42u8], encodingHint: Some("iso-8859-1"))
    let ds = DecodingSource(src, explicitEncoding: Some("us-ascii"))
    @Expect(ds.detectedEncoding, "us-ascii")
    @Expect(ds.readAllAsString(), "AB")
}

@Test
public func testDecodingSourceDefaultsToUtf8(): Unit {
    // 无 BOM、无 hint、无显式 → UTF-8
    let src = MemorySource([0x78u8])
    let ds = DecodingSource(src)
    @Expect(ds.detectedEncoding, "utf-8")
    @Expect(ds.readAllAsString(), "x")
}

@Test
public func testDecodingSourceEmptyInput(): Unit {
    let src = MemorySource([])
    let ds = DecodingSource(src)
    @Expect(ds.detectedEncoding, "utf-8")
    @Expect(ds.readAllAsString(), "")
    @Expect(ds.isEof(), true)
}

@Test
public func testDecodingSourceInvalidBytesThrow(): Unit {
    // 无 BOM → UTF-8；喂 0xFF 0xFE 0xFD（全是非法 UTF-8 首字节）
    let src = MemorySource([0xFFu8, 0xFEu8, 0xFDu8])
    var threw = false
    try {
        // 注意：FF FE 会被 BOM 检测吃掉两字节作为 UTF-16 LE……
        // 这里用三字节序列来避免歧义：用 0xC0 0x80（UTF-8 非法超长编码），
        // 但构造器要先读 4 字节探测。改为喂 0xC0 0x80 0x41 一字节组合。
        let src2 = MemorySource([0xC0u8, 0x80u8, 0x41u8])
        let ds = DecodingSource(src2)
        let _ = ds.readAllAsString()
    } catch (_: Exception) {
        threw = true
    }
    @Expect(threw, true)
    let _ = src
}

@Test
public func testDecodingSourceClosePropagates(): Unit {
    let src = MemorySource([0x41u8])
    let ds = DecodingSource(src, ownedSource: true)
    ds.close()
    @Expect(src.isClosed(), true)
    @Expect(ds.isClosed(), true)
}
