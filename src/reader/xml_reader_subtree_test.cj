/*
 * reader — XmlReader 子树提取 API 测试（Phase 4c+）
 *
 * 覆盖：
 *   - readOuterXml / readInnerXml：空元素 / 文本子 / 嵌套 / 属性 / 混合 / CDATA / 注释
 *   - readSubtree：基础转发 / 保留属性 / 支持 isEmptyElement / 嵌套独立前进 / 原 reader 游标位置
 *   - 前置条件：非 Element 上调用 → 抛 XmlException
 *   - 端到端：readOuterXml 返回值可被再次 parse（XML 自洽）
 */
package cangjie_xml.reader

import std.unittest.*
import cangjie_xml.core.*
import cangjie_xml.parser.*
import cangjie_xml.tree.*

/* ---------- 辅助：推进 reader 到第一个名为 name 的 Element ---------- */

func advanceToElement(r: XmlReader, name: String): Bool {
    while (r.read()) {
        if (r.nodeType() == ReaderNodeType.Element && r.localName() == name) {
            return true
        }
    }
    return false
}

/* ---------- readOuterXml ---------- */

@Test
public func testReadOuterXmlSelfClosing(): Unit {
    let r = XmlReader.fromString("<root><a/></root>")
    @Expect(advanceToElement(r, "a"), true)
    @Expect(r.readOuterXml(), "<a/>")
}

@Test
public func testReadOuterXmlWithText(): Unit {
    let r = XmlReader.fromString("<root><a>hi</a></root>")
    @Expect(advanceToElement(r, "a"), true)
    @Expect(r.readOuterXml(), "<a>hi</a>")
}

@Test
public func testReadOuterXmlNested(): Unit {
    let r = XmlReader.fromString("<root><a><b>1</b><c/></a></root>")
    @Expect(advanceToElement(r, "a"), true)
    @Expect(r.readOuterXml(), "<a><b>1</b><c/></a>")
}

@Test
public func testReadOuterXmlWithAttributes(): Unit {
    let r = XmlReader.fromString("<root><a id=\"1\" cls=\"x\"/></root>")
    @Expect(advanceToElement(r, "a"), true)
    @Expect(r.readOuterXml(), "<a id=\"1\" cls=\"x\"/>")
}

@Test
public func testReadOuterXmlMixedContent(): Unit {
    let r = XmlReader.fromString("<root><a>hello <b>bold</b> end</a></root>")
    @Expect(advanceToElement(r, "a"), true)
    @Expect(r.readOuterXml(), "<a>hello <b>bold</b> end</a>")
}

@Test
public func testReadOuterXmlWithCdata(): Unit {
    let r = XmlReader.fromString("<root><a><![CDATA[<x>]]></a></root>")
    @Expect(advanceToElement(r, "a"), true)
    @Expect(r.readOuterXml(), "<a><![CDATA[<x>]]></a>")
}

@Test
public func testReadOuterXmlWithComment(): Unit {
    let r = XmlReader.fromString("<root><a><!-- c --></a></root>")
    @Expect(advanceToElement(r, "a"), true)
    @Expect(r.readOuterXml(), "<a><!-- c --></a>")
}

@Test
public func testReadOuterXmlAdvancesCursorPastEnd(): Unit {
    // 调用 readOuterXml 后，再次 read() 应该看到 root 的 EndElement。
    let r = XmlReader.fromString("<root><a><b/></a></root>")
    @Expect(advanceToElement(r, "a"), true)
    let _ = r.readOuterXml()
    @Expect(r.read(), true)
    @Expect(r.nodeType() == ReaderNodeType.EndElement, true)
    @Expect(r.localName(), "root")
}

@Test
public func testReadOuterXmlSiblingsAreVisitedSeparately(): Unit {
    let r = XmlReader.fromString("<root><a>1</a><a>2</a></root>")
    @Expect(advanceToElement(r, "a"), true)
    @Expect(r.readOuterXml(), "<a>1</a>")
    @Expect(advanceToElement(r, "a"), true)
    @Expect(r.readOuterXml(), "<a>2</a>")
}

/* ---------- readInnerXml ---------- */

@Test
public func testReadInnerXmlEmpty(): Unit {
    let r = XmlReader.fromString("<root><a/></root>")
    @Expect(advanceToElement(r, "a"), true)
    @Expect(r.readInnerXml(), "")
}

@Test
public func testReadInnerXmlWithText(): Unit {
    let r = XmlReader.fromString("<root><a>hi</a></root>")
    @Expect(advanceToElement(r, "a"), true)
    @Expect(r.readInnerXml(), "hi")
}

@Test
public func testReadInnerXmlNested(): Unit {
    let r = XmlReader.fromString("<root><a><b>1</b><c/></a></root>")
    @Expect(advanceToElement(r, "a"), true)
    @Expect(r.readInnerXml(), "<b>1</b><c/>")
}

@Test
public func testReadInnerXmlMixedContent(): Unit {
    let r = XmlReader.fromString("<root><a>hi<b/>end</a></root>")
    @Expect(advanceToElement(r, "a"), true)
    @Expect(r.readInnerXml(), "hi<b/>end")
}

@Test
public func testReadInnerXmlAdvancesCursorPastEnd(): Unit {
    let r = XmlReader.fromString("<root><a>x</a><b/></root>")
    @Expect(advanceToElement(r, "a"), true)
    let _ = r.readInnerXml()
    @Expect(r.read(), true)
    @Expect(r.nodeType() == ReaderNodeType.Element, true)
    @Expect(r.localName(), "b")
}

/* ---------- readSubtree ---------- */

@Test
public func testReadSubtreeBasic(): Unit {
    let r = XmlReader.fromString("<root><a><b>1</b></a></root>")
    @Expect(advanceToElement(r, "a"), true)
    let sub = r.readSubtree()
    // sub 的第一次 read() 应当命中 Element "a"
    @Expect(sub.read(), true)
    @Expect(sub.nodeType() == ReaderNodeType.Element, true)
    @Expect(sub.localName(), "a")
    // 继续 read：进入 b
    @Expect(sub.read(), true)
    @Expect(sub.nodeType() == ReaderNodeType.Element, true)
    @Expect(sub.localName(), "b")
}

@Test
public func testReadSubtreeReachesEof(): Unit {
    let r = XmlReader.fromString("<root><a><b/></a></root>")
    @Expect(advanceToElement(r, "a"), true)
    let sub = r.readSubtree()
    // 走完整个子树
    while (sub.read()) {
        ()
    }
    @Expect(sub.isEof(), true)
}

@Test
public func testReadSubtreeLeavesOuterReaderPastEnd(): Unit {
    let r = XmlReader.fromString("<root><a><b/></a><c/></root>")
    @Expect(advanceToElement(r, "a"), true)
    let _ = r.readSubtree()
    // 外 reader 下次 read 应看到 c（a 的同级）
    @Expect(r.read(), true)
    @Expect(r.localName(), "c")
}

@Test
public func testReadSubtreeEmptyElement(): Unit {
    let r = XmlReader.fromString("<root><a/></root>")
    @Expect(advanceToElement(r, "a"), true)
    let sub = r.readSubtree()
    @Expect(sub.read(), true)
    @Expect(sub.localName(), "a")
    @Expect(sub.isEmptyElement(), true)
    // 空元素：后续 read 应到 EOF（不暴露配对 EndElement）
    @Expect(sub.read(), false)
}

@Test
public func testReadSubtreePreservesAttributes(): Unit {
    let r = XmlReader.fromString("<root><a k=\"v\"/></root>")
    @Expect(advanceToElement(r, "a"), true)
    let sub = r.readSubtree()
    @Expect(sub.read(), true)
    @Expect(sub.localName(), "a")
    @Expect(sub.attributeCount(), 1)
    @Expect(sub.moveToFirstAttribute(), true)
    @Expect(sub.localName(), "k")
    @Expect(sub.value(), "v")
}

/* ---------- 前置条件违反 ---------- */

@Test
public func testReadOuterXmlOnTextThrows(): Unit {
    let r = XmlReader.fromString("<root>hi</root>")
    // 跳过 XmlDeclaration / 可能的 prolog，找到 Text 节点
    while (r.read()) {
        if (r.nodeType() == ReaderNodeType.Text) {
            break
        }
    }
    @Expect(r.nodeType() == ReaderNodeType.Text, true)
    var threw = false
    try {
        let _ = r.readOuterXml()
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
public func testReadSubtreeOnNonElementThrows(): Unit {
    let r = XmlReader.fromString("<root>x</root>")
    while (r.read()) {
        if (r.nodeType() == ReaderNodeType.Text) {
            break
        }
    }
    @Expect(r.nodeType() == ReaderNodeType.Text, true)
    var threw = false
    try {
        let _ = r.readSubtree()
    } catch (_: XmlException) {
        threw = true
    }
    @Expect(threw, true)
}

/* ---------- 端到端：readOuterXml 输出可被再次 parse ---------- */

@Test
public func testOuterXmlIsWellFormedAndReparseable(): Unit {
    let r = XmlReader.fromString("<root><a><b>t</b><c k=\"v\"/></a></root>")
    @Expect(advanceToElement(r, "a"), true)
    let xml = r.readOuterXml()
    // 再次用 DocumentBuilder 解析
    let doc = DocumentBuilder.parseString(xml)
    @Expect(doc.root.qname.localName, "a")
    @Expect(doc.root.childCount(), 2)
}
