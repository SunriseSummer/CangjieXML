package tinyxml2.internal

import std.unittest.*
import std.unittest.testmacro.*

/**
 * 覆盖 `internal.text_escape` 的写出方向转义工具的单元测试。
 *
 * 直接对单一函数做边界断言（如 CDATA 中含 `]]>` 的分段），失败时能精确指到
 * "转义规则自身"这一层。
 */

@Test
func testEscapeTextNoEscapeNeeded(): Unit {
    @Expect(escapeText("hello world"), "hello world")
    @Expect(escapeText(""), "")
    @Expect(escapeText("中文 / emoji 🔍"), "中文 / emoji 🔍")
}

@Test
func testEscapeTextAllFiveSymbols(): Unit {
    // 文本节点：转义 & < >；保留 " 和 '
    @Expect(escapeText("a<b & c>d"), "a&lt;b &amp; c&gt;d")
    @Expect(escapeText("'x' \"y\""), "'x' \"y\"")
}

@Test
func testEscapeAttributeAddsQuotEscape(): Unit {
    // 属性值：在文本转义基础上加 &quot;
    @Expect(escapeAttribute("say \"hi\""), "say &quot;hi&quot;")
    @Expect(escapeAttribute("a & b"), "a &amp; b")
    @Expect(escapeAttribute("x < y > z"), "x &lt; y &gt; z")
    // 单引号在双引号包裹里是安全的，不转义
    @Expect(escapeAttribute("it's"), "it's")
}

@Test
func testEscapeCdataSimple(): Unit {
    @Expect(escapeCdata("plain"), "<![CDATA[plain]]>")
    @Expect(escapeCdata(""), "<![CDATA[]]>")
}

@Test
func testEscapeCdataSplitsTerminator(): Unit {
    // 关键不变量：输出串不包含裸的 `]]>`（除去合法的段结尾），
    // 每一段都以 `<![CDATA[` 开启、`]]>` 关闭。
    let got = escapeCdata("foo]]>bar")
    @Expect(got, "<![CDATA[foo]]]]><![CDATA[>bar]]>")
}

@Test
func testEscapeCdataMultipleTerminators(): Unit {
    let got = escapeCdata("a]]>b]]>c")
    @Expect(got, "<![CDATA[a]]]]><![CDATA[>b]]]]><![CDATA[>c]]>")
}

@Test
func testEscapeTextFastPathPreservesIdentity(): Unit {
    // 快路径：不需要转义时直接 return 原串；行为上表现为值相等。
    // （我们无法在用户层观察到"同一引用"，但能观察到等值。）
    let raw = "just text"
    @Expect(escapeText(raw), raw)
    let raw2 = "attr without specials"
    @Expect(escapeAttribute(raw2), raw2)
}

@Test
func testBomConstantsMatchSpec(): Unit {
    // UTF-8 BOM：EF BB BF（三字节）
    @Expect(UTF8_BOM.size, 3)
    @Expect(UTF8_BOM[0], 0xEFu8)
    @Expect(UTF8_BOM[1], 0xBBu8)
    @Expect(UTF8_BOM[2], 0xBFu8)
    // 字符串形态是 U+FEFF 单码点，长度 3 字节（UTF-8 编码）
    @Expect(UTF8_BOM_STRING.toArray().size, 3)
}
