package cangjie_xml.encoding

import std.unittest.*

@Test
public func testUtf8AsciiRoundTrip(): Unit {
    let d = Utf8Decoder()
    @Expect(d.decodeAll("Hello, World!".toArray()), "Hello, World!")
    let e = Utf8Encoder()
    let bytes = e.encodeAll("Hello, World!")
    @Expect(bytes.size, 13)
}

@Test
public func testUtf8MultibyteRoundTrip(): Unit {
    let s = "中文 — 😀 © Ω"
    let e = Utf8Encoder()
    let bytes = e.encodeAll(s)
    let d = Utf8Decoder()
    @Expect(d.decodeAll(bytes), s)
}

@Test
public func testUtf8OverlongRejected(): Unit {
    // 超长编码 0xC0 0xAF 表示 '/' (0x2F) — 非法。
    let d = Utf8Decoder()
    let r = d.decode([0xC0u8, 0xAFu8], 0, 2, true)
    match (r.status) {
        case InvalidBytes(_) => ()
        case _ => @Fail("expected InvalidBytes for overlong")
    }
}

@Test
public func testUtf8SurrogateRejected(): Unit {
    // UTF-8 编码的 surrogate U+D800: ED A0 80 — 非法
    let d = Utf8Decoder()
    let r = d.decode([0xEDu8, 0xA0u8, 0x80u8], 0, 3, true)
    match (r.status) {
        case InvalidBytes(_) => ()
        case _ => @Fail("expected InvalidBytes for surrogate")
    }
}

@Test
public func testUtf8TruncatedAtEof(): Unit {
    // "中" = E4 B8 AD；截断到 E4 B8
    let d = Utf8Decoder()
    let r = d.decode([0xE4u8, 0xB8u8], 0, 2, true)
    match (r.status) {
        case InvalidBytes(_) => ()
        case _ => @Fail("expected InvalidBytes at EOF with truncated sequence")
    }
}

@Test
public func testUtf8StreamingAcrossChunks(): Unit {
    // 把 "中文" (E4 B8 AD E6 96 87) 拆成 [E4 B8], [AD E6 96], [87] 三片流式解码。
    let d = Utf8Decoder()
    var acc = ""
    let parts: Array<Array<Byte>> = [[0xE4u8, 0xB8u8], [0xADu8, 0xE6u8, 0x96u8], [0x87u8]]
    for (i in 0..parts.size) {
        let part = parts[i]
        let isLast = i == parts.size - 1
        let r = d.decode(part, 0, part.size, isLast)
        acc += r.text
        if (isLast) {
            match (r.status) {
                case Success => ()
                case _ => @Fail("expected Success at final chunk, got ${r.status}")
            }
        }
    }
    @Expect(acc, "中文")
}

@Test
public func testUtf8StraySuffixContinuation(): Unit {
    // 0x80 独立出现是非法的（续字节无头）
    let d = Utf8Decoder()
    let r = d.decode([0x41u8, 0x80u8, 0x42u8], 0, 3, true)
    match (r.status) {
        case InvalidBytes(off) => @Expect(off, 1)
        case _ => @Fail("expected InvalidBytes@1")
    }
    @Expect(r.text, "A")
}

@Test
public func testUtf8EmptyInput(): Unit {
    let d = Utf8Decoder()
    let r = d.decode([], 0, 0, true)
    match (r.status) {
        case Success => ()
        case _ => @Fail("expected Success on empty")
    }
    @Expect(r.text, "")
}
