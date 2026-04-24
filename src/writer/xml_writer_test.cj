/*
 * writer — XmlWriter 单元测试
 *
 * 覆盖 Phase 5b：
 *   - 基础：空元素 / 单个属性 / 嵌套 / 文本 / CDATA / Comment / PI / 命名空间
 *   - 缩进：pretty 模式 + 叶子文本保护
 *   - XML 声明 / DOCTYPE / prolog / epilog
 *   - 状态机违规：mismatched endElement / 属性错位 / 多根 / 无声明顺序 / after close
 *   - `close()` 强制闭合校验
 *   - 与 save.DocumentSerializer 字节对齐（同一抽象 DOM 的两种产出方式）
 */
package cangjie_xml.writer

import std.unittest.*
import cangjie_xml.core.*
import cangjie_xml.io.*

/* ---------- 工具：拿到写入字节的字符串视图 ---------- */

func newSink(): MemorySink {
    return MemorySink()
}

func writtenString(sink: MemorySink): String {
    return String.fromUtf8(sink.toBytes())
}

/* ---------- 基础 ---------- */

@Test
public func testWriteEmptyElementSelfClose(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement("a")
    w.endElement()
    w.close()
    @Expect(writtenString(sink), "<a/>")
}

@Test
public func testWriteElementWithAttribute(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement("a")
    w.writeAttribute("k", "v")
    w.endElement()
    w.close()
    @Expect(writtenString(sink), "<a k=\"v\"/>")
}

@Test
public func testAttributeEscaping(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement("a")
    w.writeAttribute("k", "a&b<c>\"d\"")
    w.endElement()
    w.close()
    @Expect(writtenString(sink), "<a k=\"a&amp;b&lt;c&gt;&quot;d&quot;\"/>")
}

@Test
public func testTextEscaping(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement("a")
    w.writeText("a & b < c > d")
    w.endElement()
    w.close()
    @Expect(writtenString(sink), "<a>a &amp; b &lt; c &gt; d</a>")
}

@Test
public func testNestedElements(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement("a")
    w.startElement("b")
    w.startElement("c")
    w.endElement()
    w.endElement()
    w.endElement()
    w.close()
    @Expect(writtenString(sink), "<a><b><c/></b></a>")
}

@Test
public func testMixedContent(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement("a")
    w.writeText("pre ")
    w.startElement("b")
    w.writeText("in")
    w.endElement()
    w.writeText(" post")
    w.endElement()
    w.close()
    @Expect(writtenString(sink), "<a>pre <b>in</b> post</a>")
}

@Test
public func testCdataSection(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement("a")
    w.writeCdata("raw & <t>")
    w.endElement()
    w.close()
    @Expect(writtenString(sink), "<a><![CDATA[raw & <t>]]></a>")
}

@Test
public func testCommentAndPiInContent(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement("a")
    w.writeComment(" c ")
    w.writePi("pi", data: Some("d"))
    w.endElement()
    w.close()
    @Expect(writtenString(sink), "<a><!-- c --><?pi d?></a>")
}

@Test
public func testNamespaceDeclarations(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement("r")
    w.writeNamespace(None, "urn:a")
    w.writeNamespace(Some("p"), "urn:b")
    w.startElement("p:c")
    w.endElement()
    w.endElement()
    w.close()
    @Expect(writtenString(sink), "<r xmlns=\"urn:a\" xmlns:p=\"urn:b\"><p:c/></r>")
}

@Test
public func testUseQNameApi(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement(QName("c", prefix: Some("p")))
    w.writeAttribute(QName("k", prefix: Some("q")), "v")
    w.endElement()
    w.close()
    @Expect(writtenString(sink), "<p:c q:k=\"v\"/>")
}

/* ---------- XML 声明 / DOCTYPE / Prolog / Epilog ---------- */

@Test
public func testXmlDeclarationAndRoot(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.writeXmlDeclaration(version: "1.0", encoding: Some("UTF-8"))
    w.startElement("a")
    w.endElement()
    w.close()
    @Expect(writtenString(sink), "<?xml version=\"1.0\" encoding=\"UTF-8\"?><a/>")
}

@Test
public func testStandaloneFlag(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.writeXmlDeclaration(standalone: Standalone3.Yes)
    w.startElement("a")
    w.endElement()
    w.close()
    @Expect(writtenString(sink), "<?xml version=\"1.0\" standalone=\"yes\"?><a/>")
}

@Test
public func testDoctype(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.writeDoctype("root")
    w.startElement("root")
    w.endElement()
    w.close()
    @Expect(writtenString(sink), "<!DOCTYPE root><root/>")
}

@Test
public func testPrologCommentAndPi(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.writeComment(" hi ")
    w.writePi("t", data: Some("d"))
    w.startElement("a")
    w.endElement()
    w.close()
    @Expect(writtenString(sink), "<!-- hi --><?t d?><a/>")
}

@Test
public func testEpilogComment(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement("a")
    w.endElement()
    w.writeComment(" bye ")
    w.close()
    @Expect(writtenString(sink), "<a/><!-- bye -->")
}

/* ---------- 缩进 pretty ---------- */

@Test
public func testPrettyIndentStructure(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink, opts: WriterOptions.pretty())
    w.startElement("a")
    w.startElement("b")
    w.endElement()
    w.startElement("c")
    w.writeText("x")
    w.endElement()
    w.endElement()
    w.close()
    let out = writtenString(sink)
    @Expect(out.contains("<a>"), true)
    @Expect(out.contains("  <b/>"), true)
    // c 只有文本，保持同行
    @Expect(out.contains("  <c>x</c>"), true)
    @Expect(out.contains("</a>"), true)
}

@Test
public func testPrettyLeafTextKeepsInline(): Unit {
    // 纯文本元素不应被缩进到下一行
    let sink = newSink()
    let w = XmlWriter(sink, opts: WriterOptions.pretty())
    w.startElement("a")
    w.writeText("hello")
    w.endElement()
    w.close()
    @Expect(writtenString(sink), "<a>hello</a>")
}

/* ---------- writeRawBytes ---------- */

@Test
public func testRawBytesPassthrough(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement("a")
    w.writeRawBytes("<!--already escaped-->".toArray())
    w.endElement()
    w.close()
    @Expect(writtenString(sink), "<a><!--already escaped--></a>")
}

/* ---------- 状态机违规 ---------- */

@Test
public func testXmlDeclarationNotFirstFails(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement("a")
    try {
        w.writeXmlDeclaration()
        @Fail("expected exception")
    } catch (_: XmlException) {
        @Expect(w.isFaulted(), true)
    }
}

@Test
public func testOmitXmlDeclarationPreventsCall(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink, opts: WriterOptions(omitXmlDeclaration: true))
    try {
        w.writeXmlDeclaration()
        @Fail("expected exception")
    } catch (_: XmlException) {
        @Expect(w.isFaulted(), true)
    }
}

@Test
public func testEndElementWithoutStartFails(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    try {
        w.endElement()
        @Fail("expected exception")
    } catch (_: XmlException) {
        @Expect(w.isFaulted(), true)
    }
}

@Test
public func testAttributeAfterContentFails(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement("a")
    w.writeText("x")
    try {
        w.writeAttribute("k", "v")
        @Fail("expected exception")
    } catch (_: XmlException) {
        @Expect(w.isFaulted(), true)
    }
}

@Test
public func testSecondRootFails(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement("a")
    w.endElement()
    try {
        w.startElement("b")
        @Fail("expected exception")
    } catch (_: XmlException) {
        @Expect(w.isFaulted(), true)
    }
}

@Test
public func testCloseWithUnclosedElementFails(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement("a")
    try {
        w.close()
        @Fail("expected exception")
    } catch (_: XmlException) {
        @Expect(w.isFaulted(), true)
    }
}

@Test
public func testWriteAfterCloseFails(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement("a")
    w.endElement()
    w.close()
    try {
        w.startElement("b")
        @Fail("expected exception")
    } catch (_: XmlException) {
        @Expect(w.isFaulted(), true)
    }
}

@Test
public func testCdataWithTerminatorFails(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement("a")
    try {
        w.writeCdata("oops ]]> nope")
        @Fail("expected exception")
    } catch (_: XmlException) {
        @Expect(w.isFaulted(), true)
    }
}

@Test
public func testCommentWithDoubleDashFails(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement("a")
    try {
        w.writeComment("bad -- dashes")
        @Fail("expected exception")
    } catch (_: XmlException) {
        @Expect(w.isFaulted(), true)
    }
}

@Test
public func testPiReservedTargetFails(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement("a")
    try {
        w.writePi("Xml", data: Some("d"))
        @Fail("expected exception")
    } catch (_: XmlException) {
        @Expect(w.isFaulted(), true)
    }
}

/* ---------- depth 追踪 ---------- */

@Test
public func testDepthTracking(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    @Expect(w.depth(), 0)
    w.startElement("a")
    @Expect(w.depth(), 1)
    w.startElement("b")
    @Expect(w.depth(), 2)
    w.endElement()
    @Expect(w.depth(), 1)
    w.endElement()
    @Expect(w.depth(), 0)
    w.close()
}

/* ---------- 与 save.DocumentSerializer 字节对齐 ---------- */

@Test
public func testCloseIsIdempotentOnClosed(): Unit {
    let sink = newSink()
    let w = XmlWriter(sink)
    w.startElement("a")
    w.endElement()
    w.close()
    // 再次 close 应幂等，不抛错
    w.close()
    @Expect(w.isClosed(), true)
}
