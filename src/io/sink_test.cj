package cangjie_xml.io

import std.unittest.*
import std.io.*

@Test
public func testMemorySinkAccumulates(): Unit {
    let sink = MemorySink()
    sink.write([0x41u8, 0x42u8])
    sink.write([0x43u8])
    @Expect(sink.size(), 3)
    let out = sink.toBytes()
    @Expect(out[0], 0x41u8)
    @Expect(out[2], 0x43u8)
}

@Test
public func testMemorySinkCloseRejectsWrites(): Unit {
    let sink = MemorySink()
    sink.close()
    @Expect(sink.isClosed(), true)
    var threw = false
    try {
        sink.write([0u8])
    } catch (_: Exception) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testStreamSinkWrapsByteBuffer(): Unit {
    let bb = ByteBuffer()
    let sink = StreamSink(bb)
    sink.write("hello".toArray())
    sink.flush()
    @Expect(String.fromUtf8(readToEnd(bb)), "hello")
}
