package cangjie_xml.encoding

import std.unittest.*

@Test
public func testUtf32BeBasic(): Unit {
    let d = Utf32Decoder.bigEndian()
    // 'A' = 00 00 00 41
    let r = d.decode([0x00u8, 0x00u8, 0x00u8, 0x41u8], 0, 4, true)
    match (r.status) {
        case Success => ()
        case _ => @Fail("expected Success")
    }
    @Expect(r.text, "A")
}

@Test
public func testUtf32LeMultibyte(): Unit {
    // "中" = U+4E2D → LE: 2D 4E 00 00
    let d = Utf32Decoder.littleEndian()
    let r = d.decode([0x2Du8, 0x4Eu8, 0x00u8, 0x00u8], 0, 4, true)
    @Expect(r.text, "中")
}

@Test
public func testUtf32SupplementaryPlane(): Unit {
    // 😀 = U+1F600 → BE: 00 01 F6 00
    let d = Utf32Decoder.bigEndian()
    let r = d.decode([0x00u8, 0x01u8, 0xF6u8, 0x00u8], 0, 4, true)
    @Expect(r.text, "😀")
}

@Test
public func testUtf32RejectSurrogate(): Unit {
    let d = Utf32Decoder.bigEndian()
    // U+D800 → 00 00 D8 00
    let r = d.decode([0x00u8, 0x00u8, 0xD8u8, 0x00u8], 0, 4, true)
    match (r.status) {
        case InvalidBytes(_) => ()
        case _ => @Fail("expected InvalidBytes for surrogate")
    }
}

@Test
public func testUtf32RejectOutOfRange(): Unit {
    let d = Utf32Decoder.bigEndian()
    // U+00110000 → 00 11 00 00
    let r = d.decode([0x00u8, 0x11u8, 0x00u8, 0x00u8], 0, 4, true)
    match (r.status) {
        case InvalidBytes(_) => ()
        case _ => @Fail("expected InvalidBytes")
    }
}

@Test
public func testUtf32NonMultipleOfFourAtEof(): Unit {
    let d = Utf32Decoder.bigEndian()
    let r = d.decode([0x00u8, 0x00u8, 0x00u8, 0x41u8, 0x00u8], 0, 5, true)
    match (r.status) {
        case InvalidBytes(_) => ()
        case _ => @Fail("expected InvalidBytes at trailing bytes")
    }
    @Expect(r.text, "A")
}

@Test
public func testUtf32Streaming(): Unit {
    let d = Utf32Decoder.bigEndian()
    let r1 = d.decode([0x00u8, 0x00u8, 0x00u8], 0, 3, false)
    match (r1.status) {
        case NeedMoreInput => ()
        case _ => @Fail("expected NeedMoreInput")
    }
    let r2 = d.decode([0x41u8], 0, 1, true)
    match (r2.status) {
        case Success => ()
        case _ => @Fail("expected Success")
    }
    @Expect(r2.text, "A")
}
