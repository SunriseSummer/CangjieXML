package cangjie_xml.core

import std.unittest.*

@Test
public func testNameTableIntern(): Unit {
    let t = NameTable()
    let a = t.intern("hello")
    let b = t.intern("hello")
    @Expect(a, b)
    @Expect(t.size, 1)
    let c = t.intern("world")
    @Expect(t.size, 2)
    @Expect(t.contains("hello"), true)
    @Expect(t.contains("nope"), false)
    let _ = c
}

@Test
public func testNameTableInternedOnly(): Unit {
    let t = NameTable()
    @Expect(t.interned("x").isNone(), true)
    let _ = t.intern("x")
    @Expect(t.interned("x").isSome(), true)
}

@Test
public func testConcurrentNameTableBasic(): Unit {
    let t = ConcurrentNameTable()
    @Expect(t.intern("a"), "a")
    @Expect(t.intern("a"), "a")
    @Expect(t.contains("a"), true)
    @Expect(t.contains("b"), false)
}
