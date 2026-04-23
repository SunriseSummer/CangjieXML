package cangjie_xml.parser

import std.unittest.*

private func textOf(r: EntityResolution): String {
    match (r) {
        case Text(s) => return s
        case External(_, _, _) => return ""
    }
}

@Test
public func testDefaultResolverPredefined(): Unit {
    let r = DefaultEntityResolver()
    @Expect(textOf(r.resolveEntity("lt").getOrThrow()), "<")
    @Expect(textOf(r.resolveEntity("gt").getOrThrow()), ">")
    @Expect(textOf(r.resolveEntity("amp").getOrThrow()), "&")
    @Expect(textOf(r.resolveEntity("apos").getOrThrow()), "'")
    @Expect(textOf(r.resolveEntity("quot").getOrThrow()), "\"")
}

@Test
public func testDefaultResolverUnknown(): Unit {
    let r = DefaultEntityResolver()
    @Expect(r.resolveEntity("foo").isNone(), true)
    @Expect(r.resolveEntity("nbsp").isNone(), true)
}

@Test
public func testMapResolverExtra(): Unit {
    let r = MapEntityResolver([("nbsp", "\u{00A0}"), ("copy", "©")])
    @Expect(textOf(r.resolveEntity("nbsp").getOrThrow()), "\u{00A0}")
    @Expect(textOf(r.resolveEntity("copy").getOrThrow()), "©")
    // 预定义仍然可用
    @Expect(textOf(r.resolveEntity("amp").getOrThrow()), "&")
    // 未定义仍为 None
    @Expect(r.resolveEntity("whatever").isNone(), true)
}

@Test
public func testMapResolverPredefinedWins(): Unit {
    // 即使 user 试图覆盖预定义，DefaultEntityResolver 路径优先
    let r = MapEntityResolver([("amp", "HIJACK")])
    @Expect(textOf(r.resolveEntity("amp").getOrThrow()), "&")
}
