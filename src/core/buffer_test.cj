package cangjie_xml.core

import std.unittest.*

@Test
public func testGrowableBufferBasic(): Unit {
    let b = GrowableBuffer()
    @Expect(b.isEmpty(), true)
    b.writeString("hello ")
    b.writeString("world")
    @Expect(b.toString(), "hello world")
    @Expect(b.size, 11)

    b.clear()
    @Expect(b.isEmpty(), true)
}

@Test
public func testGrowableBufferWriteCodePoint(): Unit {
    let b = GrowableBuffer()
    b.writeCodePoint(Int32(UInt32(r'A'))) // 1 字节
    b.writeCodePoint(0xA9) // 2 字节 © (U+00A9)
    b.writeCodePoint(0x4E2D) // 3 字节 中
    b.writeCodePoint(0x1F600) // 4 字节 😀
    let s = b.toString()
    @Expect(s, "A\u{00A9}中\u{1F600}")
}

@Test
public func testBoundedBufferEnforcesLimit(): Unit {
    let b = BoundedBuffer(maxBytes: 4)
    b.writeString("abcd")
    @Expect(b.size, 4)
    var thrown = false
    try {
        b.writeByte(0x41u8)
    } catch (_: XmlException) {
        thrown = true
    }
    @Expect(thrown, true)
}

@Test
public func testBoundedBufferRejectsEarly(): Unit {
    let b = BoundedBuffer(maxBytes: 3)
    var thrown = false
    try {
        b.writeString("four") // 4 字节 > 3
    } catch (_: XmlException) {
        thrown = true
    }
    @Expect(thrown, true)
    @Expect(b.size, 0)
}
