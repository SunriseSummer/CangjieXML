package cangjie_xml.io

import std.unittest.*

@Test
public func testBufferedSinkAccumulatesThenFlushes(): Unit {
    let mem = MemorySink()
    let buf = BufferedSink(mem, capacity: 16, owned: false)
    buf.write("hi".toArray())
    // 未 flush 前下层空
    @Expect(mem.size(), 0)
    @Expect(buf.bufferedSize(), 2)
    buf.flush()
    @Expect(mem.size(), 2)
    @Expect(String.fromUtf8(mem.toBytes()), "hi")
}

@Test
public func testBufferedSinkAutoFlushesWhenFull(): Unit {
    let mem = MemorySink()
    let buf = BufferedSink(mem, capacity: 16, owned: false)
    // 先写 10 字节（< capacity），进缓冲
    buf.write("0123456789".toArray())
    @Expect(mem.size(), 0)
    @Expect(buf.bufferedSize(), 10)
    // 再写 10 字节；总 20 > 16，触发一次自动 flush，再把新 10 字节入缓冲
    buf.write("abcdefghij".toArray())
    @Expect(mem.size(), 10)
    @Expect(buf.bufferedSize(), 10)
    buf.flush()
    @Expect(mem.size(), 20)
    @Expect(String.fromUtf8(mem.toBytes()), "0123456789abcdefghij")
}

@Test
public func testBufferedSinkLargeWriteBypasses(): Unit {
    let mem = MemorySink()
    let buf = BufferedSink(mem, capacity: 16, owned: false)
    buf.write("abc".toArray())
    let big = Array<Byte>(32, repeat: 0x41u8) // 32 > capacity
    buf.write(big)
    // "abc" flushed + big written directly = 3 + 32
    @Expect(mem.size(), 35)
    @Expect(buf.bufferedSize(), 0)
}

@Test
public func testBufferedSinkCloseFlushes(): Unit {
    let mem = MemorySink()
    let buf = BufferedSink(mem, capacity: 32, owned: false)
    buf.write("tail".toArray())
    buf.close()
    @Expect(String.fromUtf8(mem.toBytes()), "tail")
    @Expect(buf.isClosed(), true)
}

@Test
public func testBufferedSinkOwnedClosesInner(): Unit {
    let mem = MemorySink()
    let buf = BufferedSink(mem, capacity: 16, owned: true)
    buf.close()
    @Expect(mem.isClosed(), true)
}

@Test
public func testBufferedSinkRejectsTinyCapacity(): Unit {
    let mem = MemorySink()
    var threw = false
    try {
        let _ = BufferedSink(mem, capacity: 4, owned: false)
    } catch (_: IllegalArgumentException) {
        threw = true
    }
    @Expect(threw, true)
}
