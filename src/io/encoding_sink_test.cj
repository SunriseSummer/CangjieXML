package cangjie_xml.io

import std.unittest.*
import cangjie_xml.encoding.*

@Test
public func testEncodingSinkUtf8PassThrough(): Unit {
    let mem = MemorySink()
    let enc = EncodingSink(mem, Utf8Encoder(), owned: false)
    enc.write("Hello 中".toArray())
    enc.flush()
    // UTF-8 → UTF-8 = identity
    let expected = "Hello 中".toArray()
    let actual = mem.toBytes()
    @Expect(actual.size, expected.size)
    for (i in 0..expected.size) {
        @Expect(actual[i], expected[i])
    }
}

@Test
public func testEncodingSinkUtf16BeSingleWrite(): Unit {
    let mem = MemorySink()
    // 使用 emitBom=true 的 encoder + writeBom=false 的 sink
    let enc = EncodingSink(mem, Utf16Encoder.bigEndian(emitBom: false), writeBom: true, owned: false)
    enc.write("AB".toArray())
    enc.flush()
    // Expected: BOM(FE FF) + 00 41 + 00 42
    let out = mem.toBytes()
    @Expect(out.size, 6)
    @Expect(out[0], 0xFEu8)
    @Expect(out[1], 0xFFu8)
    @Expect(out[2], 0x00u8)
    @Expect(out[3], 0x41u8)
    @Expect(out[4], 0x00u8)
    @Expect(out[5], 0x42u8)
}

@Test
public func testEncodingSinkUtf16BeNoBom(): Unit {
    let mem = MemorySink()
    let enc = EncodingSink(mem, Utf16Encoder.bigEndian(emitBom: false), owned: false)
    enc.write("A".toArray())
    enc.flush()
    let out = mem.toBytes()
    @Expect(out.size, 2)
    @Expect(out[0], 0x00u8)
    @Expect(out[1], 0x41u8)
}

@Test
public func testEncodingSinkAsciiUnmappableThrows(): Unit {
    let mem = MemorySink()
    let enc = EncodingSink(mem, asciiEncoder(), owned: false)
    var threw = false
    try {
        enc.write("Hi 中".toArray())
    } catch (_: Exception) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testEncodingSinkStreamingChunks(): Unit {
    // 把 "中文" (UTF-8 = E4 B8 AD E6 96 87) 拆成 3 片喂进去，UTF-16 BE 输出
    let mem = MemorySink()
    let enc = EncodingSink(mem, Utf16Encoder.bigEndian(emitBom: false), owned: false)
    enc.write([0xE4u8, 0xB8u8])    // 半截
    enc.write([0xADu8, 0xE6u8])    // 补完 "中" + 半截下一个
    enc.write([0x96u8, 0x87u8])    // 补完 "文"
    enc.flush()
    // "中" = U+4E2D BE → 4E 2D;   "文" = U+6587 BE → 65 87
    let out = mem.toBytes()
    @Expect(out.size, 4)
    @Expect(out[0], 0x4Eu8)
    @Expect(out[1], 0x2Du8)
    @Expect(out[2], 0x65u8)
    @Expect(out[3], 0x87u8)
}

@Test
public func testEncodingSinkFlushDetectsTruncation(): Unit {
    let mem = MemorySink()
    let enc = EncodingSink(mem, Utf8Encoder(), owned: false)
    enc.write([0xE4u8, 0xB8u8]) // 半截 UTF-8
    var threw = false
    try {
        enc.flush()
    } catch (_: Exception) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testEncodingSinkCloseFlushesAndClosesInner(): Unit {
    let mem = MemorySink()
    let enc = EncodingSink(mem, Utf8Encoder(), owned: true)
    enc.write("X".toArray())
    enc.close()
    @Expect(mem.isClosed(), true)
    @Expect(enc.isClosed(), true)
}
