package fastxml.writer

import std.unittest.*
import std.unittest.testmacro.*
import fastxml.dom.*
import fastxml.internal.*

// ======================================================================
// Writer：行为测试
//
// 覆盖：
//   - 空文档 / 根元素为空 / 自闭合
//   - 声明输出（显式 vs 默认合成）
//   - 属性有序输出与转义
//   - 文本 / CDATA / 注释 / 未知节点
//   - 紧凑 vs 美化（含内联单文本子元素）
//   - BOM
//   - 确定性（相同 DOM + 相同 options → 相同输出）
// ======================================================================

// ---------- 辅助 ----------

func mkDoc(): XmlDocument {
    XmlDocument()
}

// ---------- 基础 ----------

@Test
func testEmptyDocumentDefault(): Unit {
    let doc = mkDoc()
    // 空文档只会输出默认声明
    let s = doc.writeToString()
    @Expect(s, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
}

@Test
func testEmptyDocumentSuppressDeclaration(): Unit {
    let doc = mkDoc()
    let s = doc.writeToString(XmlWriteOptions(writeDeclaration: false))
    @Expect(s, "")
}

@Test
func testSelfClosingElement(): Unit {
    let doc = mkDoc()
    let root = doc.createElement("root")
    doc.appendChild(root)
    let s = doc.writeToString(XmlWriteOptions(writeDeclaration: false))
    @Expect(s, "<root/>\n")
}

@Test
func testAttributesInOrder(): Unit {
    let doc = mkDoc()
    let e = doc.createElement("e")
    e.setAttribute("a", "1")
    e.setAttribute("b", "2")
    e.setAttribute("c", "3")
    doc.appendChild(e)
    let s = doc.writeToString(XmlWriteOptions(writeDeclaration: false))
    @Expect(s, "<e a=\"1\" b=\"2\" c=\"3\"/>\n")
}

@Test
func testAttributeEscaping(): Unit {
    let doc = mkDoc()
    let e = doc.createElement("e")
    e.setAttribute("x", "a&b<c>d\"e")
    doc.appendChild(e)
    let s = doc.writeToString(XmlWriteOptions(writeDeclaration: false))
    @Expect(s, "<e x=\"a&amp;b&lt;c&gt;d&quot;e\"/>\n")
}

@Test
func testTextEscaping(): Unit {
    let doc = mkDoc()
    let e = doc.createElement("e")
    doc.appendChild(e)
    e.setTextContent("a<b>c&d\"e")
    let s = doc.writeToString(XmlWriteOptions(writeDeclaration: false))
    // 注意：文本中 `"` 不需要转义
    @Expect(s, "<e>a&lt;b&gt;c&amp;d\"e</e>\n")
}

@Test
func testInlineSingleTextChild(): Unit {
    let doc = mkDoc()
    let e = doc.createElement("name")
    doc.appendChild(e)
    e.setTextContent("hello")
    let s = doc.writeToString(XmlWriteOptions(writeDeclaration: false))
    @Expect(s, "<name>hello</name>\n")
}

@Test
func testBlockWithChildElements(): Unit {
    let doc = mkDoc()
    let root = doc.createElement("r")
    doc.appendChild(root)
    root.appendChild(doc.createElement("a"))
    root.appendChild(doc.createElement("b"))
    let s = doc.writeToString(XmlWriteOptions(writeDeclaration: false))
    @Expect(s, "<r>\n    <a/>\n    <b/>\n</r>\n")
}

@Test
func testCustomIndent(): Unit {
    let doc = mkDoc()
    let root = doc.createElement("r")
    doc.appendChild(root)
    let inner = doc.createElement("i")
    root.appendChild(inner)
    inner.appendChild(doc.createElement("x"))
    let s = doc.writeToString(XmlWriteOptions(writeDeclaration: false, indent: "  "))
    @Expect(s, "<r>\n  <i>\n    <x/>\n  </i>\n</r>\n")
}

@Test
func testCompactMode(): Unit {
    let doc = mkDoc()
    let root = doc.createElement("r")
    doc.appendChild(root)
    let a = doc.createElement("a")
    root.appendChild(a)
    a.setTextContent("hi")
    root.appendChild(doc.createElement("b"))
    let s = doc.writeToString(XmlWriteOptions.compactPreset().withDeclarationOff())
    @Expect(s, "<r><a>hi</a><b/></r>")
}

@Test
func testComment(): Unit {
    let doc = mkDoc()
    let root = doc.createElement("r")
    doc.appendChild(root)
    root.appendChild(doc.createComment(" hello "))
    root.appendChild(doc.createElement("c"))
    let s = doc.writeToString(XmlWriteOptions(writeDeclaration: false))
    @Expect(s, "<r>\n    <!-- hello -->\n    <c/>\n</r>\n")
}

@Test
func testCdata(): Unit {
    let doc = mkDoc()
    let root = doc.createElement("r")
    doc.appendChild(root)
    root.appendChild(doc.createText("<not-escaped>&amp;", cdata: true))
    let s = doc.writeToString(XmlWriteOptions(writeDeclaration: false))
    // CDATA 被识别为"单文本子节点" → 走 inline 模式
    @Expect(s, "<r><![CDATA[<not-escaped>&amp;]]></r>\n")
}

@Test
func testCdataContainingTerminator(): Unit {
    let doc = mkDoc()
    let root = doc.createElement("r")
    doc.appendChild(root)
    root.appendChild(doc.createText("a]]>b", cdata: true))
    let s = doc.writeToString(XmlWriteOptions(writeDeclaration: false))
    @Expect(s, "<r><![CDATA[a]]]]><![CDATA[>b]]></r>\n")
}

@Test
func testDeclarationPreserved(): Unit {
    let doc = mkDoc()
    doc.appendChild(doc.createDeclaration(value: Some("xml version=\"1.0\" encoding=\"GBK\"")))
    let root = doc.createElement("r")
    doc.appendChild(root)
    let s = doc.writeToString()
    @Expect(s, "<?xml version=\"1.0\" encoding=\"GBK\"?>\n<r/>\n")
}

@Test
func testUnknownNode(): Unit {
    let doc = mkDoc()
    doc.appendChild(doc.createUnknown("DOCTYPE note SYSTEM \"Note.dtd\""))
    let root = doc.createElement("r")
    doc.appendChild(root)
    let s = doc.writeToString(XmlWriteOptions(writeDeclaration: false))
    @Expect(s, "<!DOCTYPE note SYSTEM \"Note.dtd\">\n<r/>\n")
}

@Test
func testBom(): Unit {
    let doc = mkDoc()
    doc.appendChild(doc.createElement("r"))
    let s = doc.writeToString(XmlWriteOptions(writeDeclaration: false, writeBom: true))
    @Expect(s, UTF8_BOM_STRING + "<r/>\n")
}

@Test
func testDocumentWriteBomFlag(): Unit {
    let doc = mkDoc()
    doc.writeBom = true
    doc.appendChild(doc.createElement("r"))
    let s = doc.writeToString(XmlWriteOptions(writeDeclaration: false))
    @Expect(s, UTF8_BOM_STRING + "<r/>\n")
}

@Test
func testElementWriteToString(): Unit {
    let doc = mkDoc()
    let r = doc.createElement("r")
    r.setAttribute("a", "1")
    r.setTextContent("x")
    doc.appendChild(r)
    // 元素级写出不含声明 / BOM
    let s = r.writeToString()
    @Expect(s, "<r a=\"1\">x</r>\n")
}

@Test
func testMixedContentInline(): Unit {
    let doc = mkDoc()
    let r = doc.createElement("r")
    doc.appendChild(r)
    r.appendChild(doc.createText("head "))
    let b = doc.createElement("b")
    r.appendChild(b)
    b.setTextContent("bold")
    r.appendChild(doc.createText(" tail"))
    // 含文本与元素的混合内容：整体单行以保留空白语义
    let s = doc.writeToString(XmlWriteOptions(writeDeclaration: false))
    @Expect(s, "<r>head <b>bold</b> tail</r>\n")
}

@Test
func testDeterminism(): Unit {
    // 相同 DOM + 相同 options 应产生逐字节相同的输出
    let doc = mkDoc()
    doc.appendChild(doc.createDeclaration())
    let root = doc.createElement("r")
    doc.appendChild(root)
    root.setAttribute("x", "1")
    root.setAttribute("y", "2")
    root.appendChild(doc.createComment("c"))
    let sub = doc.createElement("s")
    root.appendChild(sub)
    sub.setTextContent("text")

    let s1 = doc.writeToString()
    let s2 = doc.writeToString()
    @Expect(s1, s2)
    // 换个 options 仍具确定性
    let c1 = doc.writeToString(XmlWriteOptions.compactPreset())
    let c2 = doc.writeToString(XmlWriteOptions.compactPreset())
    @Expect(c1, c2)
}

@Test
func testEscapeTextFastPath(): Unit {
    // 不含特殊字符时 escapeText 应按快路径返回原串
    @Expect(escapeText("hello world"), "hello world")
    @Expect(escapeText("a&b"), "a&amp;b")
    @Expect(escapeText("<>&"), "&lt;&gt;&amp;")
    @Expect(escapeAttribute("a\"b"), "a&quot;b")
    @Expect(escapeAttribute("clean"), "clean")
}

// ---------- 辅助扩展 ----------
//
// 为测试方便而加的 option 变换器。放在 test 文件里以免污染生产 API

extend XmlWriteOptions {
    func withDeclarationOff(): XmlWriteOptions {
        XmlWriteOptions(
            compact: this.compact,
            indent: this.indent,
            lineEnd: this.lineEnd,
            writeDeclaration: false,
            writeBom: this.writeBom,
            boolTrueText: this.boolTrueText,
            boolFalseText: this.boolFalseText
        )
    }
}

// ======================================================================
// 以下为原 `writer_extra_test.cj`（已合并）—— "容易被改坏又难以肉眼发现" 的
// 边界：CDATA 拆分 / compact 预设 / 元素 writeToString 不带声明 / BOM 传递 /
// 自闭合 / 属性值转义 / XmlWritable 公共接口可见性
// ======================================================================

@Test
func testWriteCdataTerminatorIsSplit(): Unit {
    // CDATA 内容含 `]]>` 必须被拆成两段，否则写出的 XML 非法
    let doc = XmlDocument()
    let root = doc.createElement("r")
    doc.appendChild(root)
    root.appendChild(doc.createText("foo]]>bar", cdata: true))

    let opts = XmlWriteOptions(writeDeclaration: false, compact: true)
    let out = doc.writeToString(opts)
    @Expect(out, "<r><![CDATA[foo]]]]><![CDATA[>bar]]></r>")
}

@Test
func testWriteCompactPresetNoIndentFromHand(): Unit {
    // 不走 parser：完全用 DOM API 手动构造
    let doc = XmlDocument()
    let a = doc.createElement("a")
    doc.appendChild(a)
    a.appendChild(doc.createElement("b"))
    let c = doc.createElement("c")
    c.setTextContent("x")
    a.appendChild(c)
    let out = doc.writeToString(XmlWriteOptions.compactPreset())
    @Expect(out, "<?xml version=\"1.0\" encoding=\"UTF-8\"?><a><b/><c>x</c></a>")
}

@Test
func testWriteElementOnlyOmitsDeclaration(): Unit {
    // XmlElement.writeToString 只吐元素子树，不应带 <?xml ...?>
    let doc = XmlDocument()
    let r = doc.createElement("r")
    r.appendChild(doc.createElement("a"))
    doc.appendChild(r)
    let s = r.writeToString(XmlWriteOptions.compactPreset())
    @Expect(s.contains("<?xml"), false)
    @Expect(s.startsWith("<r>"), true)
}

@Test
func testWriteBomPropagatedFromDocument(): Unit {
    // doc.writeBom = true 且 options.writeBom = false → 仍应写 BOM
    let doc = XmlDocument()
    doc.appendChild(doc.createElement("r"))
    doc.writeBom = true
    let out = doc.writeToString(XmlWriteOptions(writeDeclaration: false))
    let bytes = out.toArray()
    @Expect(bytes.size >= 3, true)
    @Expect(bytes[0], 0xEFu8)
    @Expect(bytes[1], 0xBBu8)
    @Expect(bytes[2], 0xBFu8)
}

@Test
func testWriteEmptyElementSelfClosing(): Unit {
    let doc = XmlDocument()
    doc.appendChild(doc.createElement("x"))
    let out = doc.writeToString(XmlWriteOptions(writeDeclaration: false, compact: true))
    @Expect(out, "<x/>")
}

@Test
func testWriteAttributeValueEscapesQuote(): Unit {
    let doc = XmlDocument()
    let r = doc.createElement("r")
    r.setAttribute("msg", "she said \"hi\" & <3")
    doc.appendChild(r)
    let out = doc.writeToString(XmlWriteOptions(writeDeclaration: false, compact: true))
    @Expect(out, "<r msg=\"she said &quot;hi&quot; &amp; &lt;3\"/>")
}

@Test
func testXmlWritableIsAPublicInterface(): Unit {
    // 回归测试：`writeToString` 必须经由 `XmlWritable` 接口声明，才能在
    // `import fastxml.writer.*` 后被跨包调用方看到
    let doc = XmlDocument()
    let el = doc.createElement("r")
    doc.appendChild(el)

    let dw: XmlWritable = doc
    let ew: XmlWritable = el
    let docStr = dw.writeToString(XmlWriteOptions(writeDeclaration: false, compact: true))
    let elStr = ew.writeToString(XmlWriteOptions.compactPreset())
    @Expect(docStr, "<r/>")
    @Expect(elStr, "<r/>")
}

// ======================================================================
// 覆盖率补充：writeNode 分派 / inline 其他节点类型 / StringXmlSink 容量构造
// ======================================================================

@Test
func testStringXmlSinkInitialCapacityConstructor(): Unit {
    // 仅为构造兼容——内部不存储 capacity，但入参必须被接受
    let sink = StringXmlSink(1024)
    sink.write("hello")
    sink.write(" world")
    @Expect(sink.toString(), "hello world")
    sink.flush() // no-op
}

@Test
func testWriterWriteNodeDispatchesDocument(): Unit {
    // writeNode(doc) 应走 writeDocument 路径（带默认声明）
    let doc = XmlDocument()
    doc.appendChild(doc.createElement("r"))
    let sink = StringXmlSink()
    XmlWriter(sink).writeNode(doc)
    @Expect(sink.toString().contains("<?xml"), true)
    @Expect(sink.toString().contains("<r/>"), true)
}

@Test
func testWriterWriteNodeOnElement(): Unit {
    let doc = XmlDocument()
    let el = doc.createElement("x")
    doc.appendChild(el)
    let sink = StringXmlSink()
    XmlWriter(sink, options: XmlWriteOptions(writeDeclaration: false, compact: true)).writeNode(el)
    @Expect(sink.toString(), "<x/>")
}

@Test
func testWriterWriteNodeOnText(): Unit {
    let doc = XmlDocument()
    let t = doc.createText("hi&there")
    let sink = StringXmlSink()
    XmlWriter(sink, options: XmlWriteOptions(writeDeclaration: false, compact: true)).writeNode(t)
    @Expect(sink.toString(), "hi&amp;there")
}

@Test
func testWriterWriteNodeOnComment(): Unit {
    let doc = XmlDocument()
    let c = doc.createComment(" lone ")
    let sink = StringXmlSink()
    XmlWriter(sink, options: XmlWriteOptions(writeDeclaration: false, compact: true)).writeNode(c)
    @Expect(sink.toString(), "<!-- lone -->")
}

@Test
func testWriterWriteNodeOnUnknown(): Unit {
    let doc = XmlDocument()
    let u = doc.createUnknown("DOCTYPE html")
    let sink = StringXmlSink()
    XmlWriter(sink, options: XmlWriteOptions(writeDeclaration: false, compact: true)).writeNode(u)
    @Expect(sink.toString(), "<!DOCTYPE html>")
}

@Test
func testWriterWriteNodeOnDeclaration(): Unit {
    let doc = XmlDocument()
    let d = doc.createDeclaration(value: Some("xml version=\"1.1\""))
    let sink = StringXmlSink()
    XmlWriter(sink, options: XmlWriteOptions(writeDeclaration: false, compact: true)).writeNode(d)
    @Expect(sink.toString(), "<?xml version=\"1.1\"?>")
}

@Test
func testWriterInlineRendersAllChildKinds(): Unit {
    // 覆盖 writeNodeInline 的 Comment / Declaration / Unknown 三支——
    // 当外层元素被判为 Inline（含 Text 子节点）时，这些兄弟节点走 inline 分支
    let doc = XmlDocument()
    let r = doc.createElement("r")
    doc.appendChild(r)
    r.appendChild(doc.createText("a "))
    r.appendChild(doc.createComment("c"))
    r.appendChild(doc.createText(" b "))
    r.appendChild(doc.createUnknown("DOCTYPE x"))
    r.appendChild(doc.createText(" end"))
    let s = doc.writeToString(XmlWriteOptions(writeDeclaration: false, compact: true))
    @Expect(s.contains("<!--c-->"), true)
    @Expect(s.contains("<!DOCTYPE x>"), true)
    @Expect(s.startsWith("<r>a "), true)
    @Expect(s.endsWith(" end</r>"), true)
}

@Test
func testWriterInlineEmptyChildElementSelfCloses(): Unit {
    // 外层元素含文本+空子元素，触发 writeElementInline 的 "None" 分支（自闭合）
    let doc = XmlDocument()
    let r = doc.createElement("r")
    doc.appendChild(r)
    r.appendChild(doc.createText("x"))
    r.appendChild(doc.createElement("e")) // 空元素
    r.appendChild(doc.createText("y"))
    let s = doc.writeToString(XmlWriteOptions(writeDeclaration: false, compact: true))
    @Expect(s, "<r>x<e/>y</r>")
}
