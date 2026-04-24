package cangjie_xml.io

import std.unittest.*
import std.io.*

@Test
public func testMemorySourceReadAll(): Unit {
    let s = MemorySource([0x41u8, 0x42u8, 0x43u8], baseUri: Some("mem://x"))
    @Expect(s.baseUri, Some("mem://x"))
    @Expect(s.encodingHint, None<String>)
    let all = readAll(s)
    @Expect(all.size, 3)
    @Expect(all[0], 0x41u8)
    @Expect(all[2], 0x43u8)
}

@Test
public func testMemorySourcePartialReads(): Unit {
    let s = MemorySource([1u8, 2u8, 3u8, 4u8, 5u8])
    let buf = Array<Byte>(2, repeat: 0u8)
    @Expect(s.read(buf), 2)
    @Expect(buf[0], 1u8)
    @Expect(buf[1], 2u8)
    @Expect(s.read(buf), 2)
    @Expect(buf[0], 3u8)
    @Expect(s.read(buf), 1)
    @Expect(buf[0], 5u8)
    @Expect(s.read(buf), 0) // EOF
}

@Test
public func testMemorySourceCloseStopsReads(): Unit {
    let s = MemorySource([1u8, 2u8])
    s.close()
    @Expect(s.isClosed(), true)
    let buf = Array<Byte>(2, repeat: 0u8)
    @Expect(s.read(buf), 0)
}

@Test
public func testStringSourceIsUtf8(): Unit {
    let s = StringSource("A中", baseUri: Some("file:///a"))
    @Expect(s.encodingHint, Some("utf-8"))
    let all = readAll(s)
    // 'A' + "中"(E4 B8 AD)
    @Expect(all.size, 4)
    @Expect(all[0], 0x41u8)
    @Expect(all[1], 0xE4u8)
    @Expect(all[2], 0xB8u8)
    @Expect(all[3], 0xADu8)
}

@Test
public func testStreamSourceWrapsByteBuffer(): Unit {
    let bb = ByteBuffer()
    bb.write([0x58u8, 0x59u8])
    let src = StreamSource(bb, encodingHint: Some("iso-8859-1"))
    @Expect(src.encodingHint, Some("iso-8859-1"))
    let all = readAll(src)
    @Expect(all.size, 2)
    @Expect(all[0], 0x58u8)
}
