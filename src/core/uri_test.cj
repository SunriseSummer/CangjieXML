package cangjie_xml.core

import std.unittest.*

@Test
public func testUriParseFull(): Unit {
    let u = Uri.parse("http://user:pw@example.com:8080/path/a?q=1#frag")
    @Expect(u.scheme, Some("http"))
    @Expect(u.authority, Some("user:pw@example.com:8080"))
    @Expect(u.path, "/path/a")
    @Expect(u.query, Some("q=1"))
    @Expect(u.fragment, Some("frag"))
    @Expect(u.isAbsolute(), true)
}

@Test
public func testUriParseRelative(): Unit {
    let u = Uri.parse("a/b/c?x#y")
    @Expect(u.scheme.isNone(), true)
    @Expect(u.authority.isNone(), true)
    @Expect(u.path, "a/b/c")
    @Expect(u.query, Some("x"))
    @Expect(u.fragment, Some("y"))
    @Expect(u.isAbsolute(), false)
}

@Test
public func testUriParseEmpty(): Unit {
    let u = Uri.parse("")
    @Expect(u.scheme.isNone(), true)
    @Expect(u.path, "")
}

@Test
public func testUriRoundTrip(): Unit {
    let samples = ["http://example.com/", "https://a.b/c?d=e#f", "mailto:user@example.com", "urn:oasis:names:tc:xml",
        "../a/b", "//example.com/x", "?just=query", "#just-fragment"]
    for (s in samples) {
        let u = Uri.parse(s)
        @Expect(u.toString(), s)
    }
}

/* RFC 3986 §5.4.1 normal examples: base = http://a/b/c/d;p?q */
@Test
public func testUriResolveNormalExamples(): Unit {
    let base = Uri.parse("http://a/b/c/d;p?q")
    let cases = [("g:h", "g:h"), ("g", "http://a/b/c/g"), ("./g", "http://a/b/c/g"), ("g/", "http://a/b/c/g/"),
        ("/g", "http://a/g"), ("//g", "http://g"), ("?y", "http://a/b/c/d;p?y"), ("g?y", "http://a/b/c/g?y"),
        ("#s", "http://a/b/c/d;p?q#s"), ("g#s", "http://a/b/c/g#s"), ("g?y#s", "http://a/b/c/g?y#s"),
        (";x", "http://a/b/c/;x"), ("g;x", "http://a/b/c/g;x"), ("g;x?y#s", "http://a/b/c/g;x?y#s"),
        ("", "http://a/b/c/d;p?q"), (".", "http://a/b/c/"), ("./", "http://a/b/c/"), ("..", "http://a/b/"),
        ("../", "http://a/b/"), ("../g", "http://a/b/g"), ("../..", "http://a/"), ("../../", "http://a/"),
        ("../../g", "http://a/g")]
    for ((refStr, expected) in cases) {
        let ref = Uri.parse(refStr)
        let resolved = ref.resolve(base)
        @Expect(resolved.toString(), expected)
    }
}

/* RFC 3986 §5.4.2 abnormal examples（部分）。 */
@Test
public func testUriResolveAbnormalExamples(): Unit {
    let base = Uri.parse("http://a/b/c/d;p?q")
    let cases = [("../../../g", "http://a/g"), ("../../../../g", "http://a/g"), ("/./g", "http://a/g"),
        ("/../g", "http://a/g"), ("g.", "http://a/b/c/g."), (".g", "http://a/b/c/.g"), ("g..", "http://a/b/c/g.."),
        ("..g", "http://a/b/c/..g")]
    for ((refStr, expected) in cases) {
        let ref = Uri.parse(refStr)
        @Expect(ref.resolve(base).toString(), expected)
    }
}

@Test
public func testUriNormalizeSchemeAndHostCase(): Unit {
    let u = Uri.parse("HTTP://User@Example.COM:80/a/./b/../c").normalize()
    @Expect(u.scheme, Some("http"))
    @Expect(u.authority, Some("User@example.com:80"))
    @Expect(u.path, "/a/c")
}

@Test
public func testUriNormalizeIpv6(): Unit {
    let u = Uri.parse("http://[::1]:8080/").normalize()
    @Expect(u.authority, Some("[::1]:8080"))
}

@Test
public func testUriTryParseGraceful(): Unit {
    // tryParse 目前不认为任何输入是"无法解析"（解析器宽松），
    // 这里只是验证接口可用。
    @Expect(Uri.tryParse("http://x/").isSome(), true)
}
