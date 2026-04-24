package cangjie_xml.encoding

import std.unittest.*

@Test
public func testAsciiDecode(): Unit {
    let d = asciiDecoder()
    @Expect(d.decodeAll([0x41u8, 0x42u8, 0x43u8]), "ABC")
}

@Test
public func testAsciiRejectHighByte(): Unit {
    let d = asciiDecoder()
    let r = d.decode([0x41u8, 0xA3u8], 0, 2, true)
    match (r.status) {
        case InvalidBytes(off) => @Expect(off, 1)
        case _ => @Fail("expected InvalidBytes@1")
    }
    @Expect(r.text, "A")
}

@Test
public func testAsciiEncodeRejectsNonAscii(): Unit {
    let e = asciiEncoder()
    let r = e.encode("A中B")
    match (r.status) {
        case Unmappable(idx, _) => @Expect(idx, 1)
        case _ => @Fail("expected Unmappable@1")
    }
    @Expect(r.bytes.size, 1)
    @Expect(r.bytes[0], 0x41u8)
}

@Test
public func testIso88591IdentityRoundTrip(): Unit {
    let d = iso88591Decoder()
    let e = iso88591Encoder()
    // Latin-1 covers U+00A0..U+00FF identity mapped.
    let s = "naïve café — £100"  // some chars here are > U+00FF (—), so use pure latin-1 string:
    let pure = "naive cafe a\u{00E9} \u{00A3}100"
    let bytes = e.encodeAll(pure)
    @Expect(d.decodeAll(bytes), pure)
    let _ = s
}

@Test
public func testIso88591EncodeHighByte(): Unit {
    let e = iso88591Encoder()
    // 'é' = U+00E9 → 0xE9
    let r = e.encode("e\u{00E9}")
    match (r.status) {
        case Success => ()
        case _ => @Fail("expected Success")
    }
    @Expect(r.bytes[0], 0x65u8)
    @Expect(r.bytes[1], 0xE9u8)
}

@Test
public func testIso88592SpecificDiff(): Unit {
    // ISO-8859-2: 0xA1 = U+0104 (A with ogonek)
    let d = iso88592Decoder()
    @Expect(d.decodeAll([0xA1u8]), "\u{0104}")
    let e = iso88592Encoder()
    let r = e.encode("\u{0104}")
    @Expect(r.bytes[0], 0xA1u8)
}

@Test
public func testIso88593HasUndefined(): Unit {
    // 0xA5 在 ISO-8859-3 中未定义
    let d = iso88593Decoder()
    let r = d.decode([0xA5u8], 0, 1, true)
    match (r.status) {
        case InvalidBytes(off) => @Expect(off, 0)
        case _ => @Fail("expected InvalidBytes for undefined 0xA5 in ISO-8859-3")
    }
}

@Test
public func testIso88595Cyrillic(): Unit {
    // 0xD0 = U+0430 ("а" Cyrillic small letter a)
    let d = iso88595Decoder()
    @Expect(d.decodeAll([0xD0u8]), "\u{0430}")
    // 0xE0 = U+0440 ("р" Cyrillic small letter er)
    @Expect(d.decodeAll([0xE0u8]), "\u{0440}")
}

@Test
public func testIso88599TurkishGBreve(): Unit {
    // 0xD0 = U+011E (G with breve)
    let d = iso88599Decoder()
    @Expect(d.decodeAll([0xD0u8]), "\u{011E}")
}

@Test
public func testIso885915Euro(): Unit {
    // 0xA4 = U+20AC (€)
    let d = iso885915Decoder()
    @Expect(d.decodeAll([0xA4u8]), "\u{20AC}")
    let e = iso885915Encoder()
    let r = e.encode("€")
    @Expect(r.bytes[0], 0xA4u8)
}

@Test
public func testSingleByteEncoderUnmappable(): Unit {
    // 中文 U+4E2D 无法在 Latin-1 中表达
    let e = iso88591Encoder()
    let r = e.encode("A中B")
    match (r.status) {
        case Unmappable(idx, _) => @Expect(idx, 1)
        case _ => @Fail("expected Unmappable@1")
    }
}
