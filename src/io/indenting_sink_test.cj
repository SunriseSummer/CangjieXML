package cangjie_xml.io

import std.unittest.*

@Test
public func testIndentingSinkPassThrough(): Unit {
    let mem = MemorySink()
    let ind = IndentingSink(mem, owned: false)
    ind.write("<a>".toArray())
    @Expect(String.fromUtf8(mem.toBytes()), "<a>")
}

@Test
public func testIndentingSinkWriteIndent(): Unit {
    let mem = MemorySink()
    let ind = IndentingSink(mem, indentUnit: "  ", owned: false)
    ind.write("<root>".toArray())
    ind.increaseIndent()
    ind.writeIndent()
    ind.write("<child/>".toArray())
    ind.decreaseIndent()
    ind.writeIndent()
    ind.write("</root>".toArray())
    @Expect(String.fromUtf8(mem.toBytes()), "<root>\n  <child/>\n</root>")
}

@Test
public func testIndentingSinkNested(): Unit {
    let mem = MemorySink()
    let ind = IndentingSink(mem, indentUnit: "\t", owned: false)
    ind.increaseIndent()
    ind.increaseIndent()
    @Expect(ind.currentLevel(), 2)
    ind.writeIndent()
    @Expect(String.fromUtf8(mem.toBytes()), "\n\t\t")
    ind.decreaseIndent()
    ind.decreaseIndent()
    ind.decreaseIndent() // 额外减，应静默
    @Expect(ind.currentLevel(), 0)
}

@Test
public func testIndentingSinkCustomNewline(): Unit {
    let mem = MemorySink()
    let ind = IndentingSink(mem, indentUnit: " ", newline: "\r\n", owned: false)
    ind.increaseIndent()
    ind.writeIndent()
    @Expect(String.fromUtf8(mem.toBytes()), "\r\n ")
}

@Test
public func testIndentingSinkClose(): Unit {
    let mem = MemorySink()
    let ind = IndentingSink(mem, owned: true)
    ind.close()
    @Expect(mem.isClosed(), true)
    @Expect(ind.isClosed(), true)
}
