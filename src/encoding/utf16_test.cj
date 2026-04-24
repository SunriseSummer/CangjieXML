package cangjie_xml.encoding

import std.unittest.*

@Test
public func testUtf16BeRoundTrip(): Unit {
    let e = Utf16Encoder.bigEndian(emitBom: false)
    let d = Utf16Decoder.bigEndian()
    let bytes = e.encodeAll("Hello 中")
    @Expect(d.decodeAll(bytes), "Hello 中")
}

@Test
public func testUtf16LeRoundTrip(): Unit {
    let e = Utf16Encoder.littleEndian(emitBom: false)
    let d = Utf16Decoder.littleEndian()
    let bytes = e.encodeAll("abc — 😀")
    @Expect(d.decodeAll(bytes), "abc — 😀")
}

@Test
public func testUtf16BomPrefix(): Unit {
    // With emitBom default true, first 2 bytes should be the BOM.
    let be = Utf16Encoder.bigEndian()
    let b = be.encodeAll("A")
    @Expect(b[0], 0xFEu8)
    @Expect(b[1], 0xFFu8)
    @Expect(b[2], 0x00u8)
    @Expect(b[3], 0x41u8)

    let le = Utf16Encoder.littleEndian()
    let l = le.encodeAll("A")
    @Expect(l[0], 0xFFu8)
    @Expect(l[1], 0xFEu8)
    @Expect(l[2], 0x41u8)
    @Expect(l[3], 0x00u8)
}

@Test
public func testUtf16SurrogatePair(): Unit {
    // 😀 = U+1F600 → surrogate pair D83D DE00 (big-endian: D8 3D DE 00)
    let d = Utf16Decoder.bigEndian()
    let r = d.decode([0xD8u8, 0x3Du8, 0xDEu8, 0x00u8], 0, 4, true)
    match (r.status) {
        case Success => ()
        case _ => @Fail("expected Success")
    }
    @Expect(r.text, "😀")
}

@Test
public func testUtf16IsolatedLowSurrogate(): Unit {
    // Stand-alone low surrogate DC00 in BE: DC 00 → error
    let d = Utf16Decoder.bigEndian()
    let r = d.decode([0xDCu8, 0x00u8], 0, 2, true)
    match (r.status) {
        case InvalidBytes(_) => ()
        case _ => @Fail("expected InvalidBytes for isolated low surrogate")
    }
}

@Test
public func testUtf16HighSurrogateWithoutLow(): Unit {
    // D83D followed by plain BMP 0041 → error (missing low surrogate)
    let d = Utf16Decoder.bigEndian()
    let r = d.decode([0xD8u8, 0x3Du8, 0x00u8, 0x41u8], 0, 4, true)
    match (r.status) {
        case InvalidBytes(_) => ()
        case _ => @Fail("expected InvalidBytes")
    }
}

@Test
public func testUtf16OddBytesAtEof(): Unit {
    let d = Utf16Decoder.bigEndian()
    let r = d.decode([0x00u8, 0x41u8, 0x00u8], 0, 3, true)
    match (r.status) {
        case InvalidBytes(_) => ()
        case _ => @Fail("expected InvalidBytes for odd byte count at EOF")
    }
    @Expect(r.text, "A")
}

@Test
public func testUtf16StreamingOdd(): Unit {
    // "AB" = 00 41 00 42; feed [00 41 00], then [42].
    let d = Utf16Decoder.bigEndian()
    let r1 = d.decode([0x00u8, 0x41u8, 0x00u8], 0, 3, false)
    match (r1.status) {
        case NeedMoreInput => ()
        case _ => @Fail("expected NeedMoreInput on odd count")
    }
    @Expect(r1.text, "A")
    let r2 = d.decode([0x42u8], 0, 1, true)
    match (r2.status) {
        case Success => ()
        case _ => @Fail("expected Success on completion")
    }
    @Expect(r2.text, "B")
}
