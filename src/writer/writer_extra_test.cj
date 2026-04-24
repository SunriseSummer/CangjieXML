package cangjie_xml.writer

import std.unittest.*
import std.unittest.testmacro.*
import cangjie_xml.dom.*

/**
 * Writer 补充测试：针对"容易被改坏又难以肉眼发现"的边界。
 *
 * 分文件理由：`writer_test.cj` 已接近 300 行的红线；本文件聚焦"仅 writer"
 * 场景——不 import parser，避免 test-only 的循环依赖。
 * 涉及 parse→write→parse 的 round-trip 放在 `parser_extra_test.cj`。
 */

@Test
func testWriteCdataTerminatorIsSplit(): Unit {
    // CDATA 内容含 `]]>` 必须被拆成两段，否则写出的 XML 非法。
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
    // 不走 parser：完全用 DOM API 手动构造。
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
    // doc.writeBom = true 且 options.writeBom = false → 仍应写 BOM。
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

