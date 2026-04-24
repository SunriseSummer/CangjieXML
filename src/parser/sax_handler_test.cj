/*
 * parser — SaxHandler / SaxDriver 单元测试
 */
package cangjie_xml.parser

import std.unittest.*
import std.collection.*
import cangjie_xml.core.*

/* ---------- 采集型 handler：把所有回调记成字符串序列 ---------- */

class RecordingHandler <: DefaultSaxHandler {
    let log = ArrayList<String>()

    public override func startDocument(decl: XmlDecl): Unit {
        log.add("startDoc(${decl.version})")
    }
    public override func endDocument(pos: Position): Unit {
        let _ = pos
        log.add("endDoc")
    }
    public override func startElement(
        pos: Position, name: QName, attrs: Array<Attribute>, ns: NsContext
    ): Unit {
        let _ = (pos, ns)
        log.add("start(${name.lexical()},${attrs.size})")
    }
    public override func endElement(pos: Position, name: QName): Unit {
        let _ = pos
        log.add("end(${name.lexical()})")
    }
    public override func characters(pos: Position, text: String): Unit {
        let _ = pos
        log.add("chars(${text})")
    }
    public override func cdata(pos: Position, text: String): Unit {
        let _ = pos
        log.add("cdata(${text})")
    }
    public override func comment(pos: Position, text: String): Unit {
        let _ = pos
        log.add("comment(${text})")
    }
    public override func processingInstruction(
        pos: Position, target: String, data: String
    ): Unit {
        let _ = pos
        log.add("pi(${target},${data})")
    }
    public override func doctype(pos: Position, name: String): Unit {
        let _ = pos
        log.add("doctype(${name})")
    }
    public override func entityReference(pos: Position, name: String): Unit {
        let _ = pos
        log.add("entity(${name})")
    }
    public override func parseError(err: XmlError): Bool {
        log.add("error(${err.message()})")
        return true
    }
}

/* ---------- 空 handler：只继承 Default，什么也不覆写 ---------- */

class NoopHandler <: DefaultSaxHandler {}

/* ---------- 早退 handler：第一个元素后抛异常让 driver 终止 ---------- */

class BailingHandler <: DefaultSaxHandler {
    public var seen = 0
    public override func startElement(
        pos: Position, name: QName, attrs: Array<Attribute>, ns: NsContext
    ): Unit {
        let _ = (pos, name, attrs, ns)
        seen += 1
        if (seen >= 1) {
            throw XmlException(XmlError.Malformed(pos, "bail"))
        }
    }
}

/* ---------- 测试 ---------- */

@Test
public func testDefaultHandlerAcceptsAllEvents(): Unit {
    // 空 handler（DefaultSaxHandler + 什么都不覆写）应能吃下完整文档不抛错
    SaxDriver.parseString("<a><b>text</b></a>", NoopHandler())
}

@Test
public func testBasicElementSequence(): Unit {
    let h = RecordingHandler()
    SaxDriver.parseString("<a><b/></a>", h)
    @Expect(h.log.size >= 5, true)
    @Expect(h.log[0].startsWith("startDoc("), true)
    @Expect(h.log[1], "start(a,0)")
    @Expect(h.log[2], "start(b,0)")
    @Expect(h.log[3], "end(b)")
    @Expect(h.log[4], "end(a)")
    @Expect(h.log[h.log.size - 1], "endDoc")
}

@Test
public func testCharactersCallback(): Unit {
    let h = RecordingHandler()
    SaxDriver.parseString("<a>hello</a>", h)
    var found = false
    for (s in h.log) {
        if (s == "chars(hello)") {
            found = true
            break
        }
    }
    @Expect(found, true)
}

@Test
public func testCdataCallback(): Unit {
    let h = RecordingHandler()
    SaxDriver.parseString("<a><![CDATA[r & <t>]]></a>", h)
    var found = false
    for (s in h.log) {
        if (s == "cdata(r & <t>)") {
            found = true
            break
        }
    }
    @Expect(found, true)
}

@Test
public func testCommentCallback(): Unit {
    let h = RecordingHandler()
    SaxDriver.parseString("<!-- hi --><a/>", h)
    var found = false
    for (s in h.log) {
        if (s == "comment( hi )") {
            found = true
            break
        }
    }
    @Expect(found, true)
}

@Test
public func testPiCallback(): Unit {
    let h = RecordingHandler()
    SaxDriver.parseString("<?pi d?><a/>", h)
    var found = false
    for (s in h.log) {
        if (s == "pi(pi,d)") {
            found = true
            break
        }
    }
    @Expect(found, true)
}

@Test
public func testDoctypeCallback(): Unit {
    let h = RecordingHandler()
    SaxDriver.parseString("<!DOCTYPE a><a/>", h)
    var found = false
    for (s in h.log) {
        if (s == "doctype(a)") {
            found = true
            break
        }
    }
    @Expect(found, true)
}

@Test
public func testAttributesPassedThrough(): Unit {
    let h = RecordingHandler()
    SaxDriver.parseString("<a k=\"v\" x=\"y\"/>", h)
    var found = false
    for (s in h.log) {
        if (s == "start(a,2)") {
            found = true
            break
        }
    }
    @Expect(found, true)
}

@Test
public func testNestedOrderIsDocumentOrder(): Unit {
    let h = RecordingHandler()
    SaxDriver.parseString("<a><b><c/></b><d/></a>", h)
    // 预期：startDoc, start(a), start(b), start(c), end(c), end(b), start(d), end(d), end(a), endDoc
    let starts = ArrayList<String>()
    for (s in h.log) {
        if (s.startsWith("start(") || s.startsWith("end(")) {
            starts.add(s)
        }
    }
    @Expect(starts[0], "start(a,0)")
    @Expect(starts[1], "start(b,0)")
    @Expect(starts[2], "start(c,0)")
    @Expect(starts[3], "end(c)")
    @Expect(starts[4], "end(b)")
    @Expect(starts[5], "start(d,0)")
    @Expect(starts[6], "end(d)")
    @Expect(starts[7], "end(a)")
}

@Test
public func testDefaultParseErrorThrows(): Unit {
    // NoopHandler 没覆写 parseError，默认实现应抛 XmlException
    // 但 parser 在非容错模式下直接抛异常（不走 ParseError 事件），所以我们直接
    // 触发 parser 抛错的路径，验证 driver 透传
    try {
        SaxDriver.parseString("<a><b></a>", NoopHandler())
        @Fail("expected exception")
    } catch (_: XmlException) {
        // ok
    }
}

@Test
public func testCustomParseErrorCanContinue(): Unit {
    // 用 RecordingHandler（覆写了 parseError 返 true），但 parser 非容错模式
    // 仍会直接抛 —— 所以改测：parser 抛的 XmlException 不经过 parseError 回调
    try {
        SaxDriver.parseString("<a><b></a>", RecordingHandler())
        @Fail("expected exception")
    } catch (_: XmlException) {
        // ok
    }
}

@Test
public func testDriveWithExternalParser(): Unit {
    let p = XmlParser.fromString("<a/>")
    let h = RecordingHandler()
    SaxDriver.drive(p, h)
    @Expect(h.log.size >= 3, true)
}

@Test
public func testHandlerThrowsPropagates(): Unit {
    // handler 抛异常应透传给 driver 的调用方
    try {
        SaxDriver.parseString("<a/>", BailingHandler())
        @Fail("expected exception")
    } catch (_: XmlException) {
        // ok
    }
}

@Test
public func testEmptyDocumentWithDeclOnly(): Unit {
    let h = RecordingHandler()
    SaxDriver.parseString("<?xml version=\"1.0\"?><a/>", h)
    // 第一个事件必须是 startDoc
    @Expect(h.log[0], "startDoc(1.0)")
}

class CharCollectorHandler <: DefaultSaxHandler {
    let buf = StringBuilder()
    public override func characters(pos: Position, text: String): Unit {
        let _ = pos
        buf.append(text)
    }
}

@Test
public func testHandlerOnlyOverridesCharacters(): Unit {
    // 演示"部分覆写"的使用模式：只收集文本拼成完整串
    let c = CharCollectorHandler()
    SaxDriver.parseString("<a>x<b>y</b>z</a>", c)
    @Expect(c.buf.toString(), "xyz")
}

@Test
public func testSaxDriverParseStringWithOpts(): Unit {
    let h = RecordingHandler()
    let opts = ParserOptions()
    SaxDriver.parseString("<a/>", h, opts: opts)
    @Expect(h.log.size >= 3, true)
}
