package cangjie_xml.encoding

import std.unittest.*

@Test
public func testNormalize(): Unit {
    @Expect(EncodingRegistry.normalize("UTF-8"), "utf8")
    @Expect(EncodingRegistry.normalize("utf_8"), "utf8")
    @Expect(EncodingRegistry.normalize("utf 8"), "utf8")
    @Expect(EncodingRegistry.normalize("ISO-8859-1"), "iso88591")
    @Expect(EncodingRegistry.normalize("Latin-1"), "latin1")
}

@Test
public func testDefaultRegistryKnown(): Unit {
    let r = EncodingRegistry.defaultRegistry()
    @Expect(r.isKnown("UTF-8"), true)
    @Expect(r.isKnown("utf8"), true)
    @Expect(r.isKnown("UTF_8"), true)
    @Expect(r.isKnown("utf-16"), true)
    @Expect(r.isKnown("ISO-8859-1"), true)
    @Expect(r.isKnown("latin-1"), true)
    @Expect(r.isKnown("ascii"), true)
    @Expect(r.isKnown("iso-8859-15"), true)
    @Expect(r.isKnown("totally-made-up"), false)
}

@Test
public func testRegistryCanonicalize(): Unit {
    let r = EncodingRegistry.defaultRegistry()
    @Expect(r.canonicalize("Latin-1"), Some("iso88591"))
    @Expect(r.canonicalize("ASCII"), Some("usascii"))
    @Expect(r.canonicalize("utf-16"), Some("utf16be"))
}

@Test
public func testRegistryNewDecoderRoundTrip(): Unit {
    let r = EncodingRegistry.defaultRegistry()
    match (r.newDecoder("UTF-8")) {
        case Some(d) => @Expect(d.decodeAll([0x41u8]), "A")
        case None => @Fail("utf-8 decoder missing")
    }
    match (r.newDecoder("iso-8859-1")) {
        case Some(d) => @Expect(d.decodeAll([0xE9u8]), "\u{00E9}")
        case None => @Fail("latin-1 decoder missing")
    }
}

@Test
public func testRegistryNewEncoderRoundTrip(): Unit {
    let r = EncodingRegistry.defaultRegistry()
    match (r.newEncoder("us-ascii")) {
        case Some(e) =>
            let bytes = e.encodeAll("Hi")
            @Expect(bytes.size, 2)
        case None => @Fail("ascii encoder missing")
    }
}

@Test
public func testRegistryMissingEncoder(): Unit {
    let r = EncodingRegistry.defaultRegistry()
    // UTF-32 只注册了解码器，没有编码器。
    @Expect(r.newEncoder("utf-32be").isNone(), true)
    @Expect(r.newDecoder("utf-32be").isSome(), true)
}

@Test
public func testDecodeFactoryReturnsFreshInstance(): Unit {
    let r = EncodingRegistry.defaultRegistry()
    let d1 = r.newDecoder("utf-8").getOrThrow()
    let d2 = r.newDecoder("utf-8").getOrThrow()
    // 不同实例应各自带独立状态；即使 d1 被"污染"（喂了半截序列），
    // d2 仍从空状态开始。
    let _ = d1.decode([0xE4u8], 0, 1, false)
    let r2 = d2.decode([0x41u8], 0, 1, true)
    match (r2.status) {
        case Success => ()
        case _ => @Fail("d2 should be independent")
    }
    @Expect(r2.text, "A")
}
