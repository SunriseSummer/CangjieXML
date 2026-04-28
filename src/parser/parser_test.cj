package fastxml.parser

import std.unittest.*
import std.unittest.testmacro.*
import fastxml.dom.*
import fastxml.error.*
import fastxml.writer.*

// ====================================================================
// Parser：顺路径行为测试
//
// 组织方式：核心输入用例覆盖主要语法分支，round-trip 测试验证
// "parse → write → 再 parse → 语义一致"
// ====================================================================

@Test
func testParseSelfClosingRoot(): Unit {
    let doc = XmlDocument.parseString("<root/>")
    match (doc.rootElement) {
        case Some(r) => @Expect(r.name, "root")
        case None => @Assert(false)
    }
}

@Test
func testParseRootWithAttributes(): Unit {
    let doc = XmlDocument.parseString("<book id=\"42\" lang='en'/>")
    let r = doc.rootElement.getOrThrow()
    @Expect(r.name, "book")
    @Expect(r.attribute("id").getOrThrow(), "42")
    @Expect(r.attribute("lang").getOrThrow(), "en")
}

@Test
func testParseWithDeclaration(): Unit {
    let doc = XmlDocument.parseString("<?xml version=\"1.0\"?><r/>")
    @Expect(doc.declaration.isSome(), true)
    @Expect(doc.rootElement.getOrThrow().name, "r")
}

@Test
func testParseCommentsAtTop(): Unit {
    let doc = XmlDocument.parseString("<!-- hi --><r/><!-- bye -->")
    // 根元素仍然正确
    @Expect(doc.rootElement.getOrThrow().name, "r")
    // 顶层节点应当包含两个 Comment + 一个 Element
    var commentCount = 0
    for (n in doc.childNodes()) {
        if (let Comment(_) <- n.kind()) {
            commentCount++
        }
    }
    @Expect(commentCount, 2)
}

@Test
func testParseNestedElementsAndText(): Unit {
    let src = "<root><a>hello</a><b>world</b></root>"
    let doc = XmlDocument.parseString(src)
    let root = doc.rootElement.getOrThrow()
    var names = ""
    var texts = ""
    for (c in root.childElements()) {
        names += c.name
        texts += c.textContent()
    }
    @Expect(names, "ab")
    @Expect(texts, "helloworld")
}

@Test
func testParseEntityReferences(): Unit {
    let doc = XmlDocument.parseString("<r t=\"a&amp;b&lt;c&gt;d&quot;e&apos;f\">1&amp;2&#65;&#x42;</r>")
    let r = doc.rootElement.getOrThrow()
    @Expect(r.attribute("t").getOrThrow(), "a&b<c>d\"e'f")
    @Expect(r.textContent(), "1&2AB")
}

@Test
func testParseCdata(): Unit {
    let doc = XmlDocument.parseString("<r><![CDATA[raw & <stuff>]]></r>")
    let r = doc.rootElement.getOrThrow()
    // textContent 应返回 CDATA 的字面内容（不再做实体解码）
    @Expect(r.textContent(), "raw & <stuff>")
    // 且应该是一个 CDATA 标记的 XmlText
    match (r.firstChild) {
        case Some(n) =>
            match (n.kind()) {
                case Text(t) =>
                    @Expect(t.isCdata, true)
                    @Expect(t.value, "raw & <stuff>")
                case _ => @Assert(false)
            }
        case None => @Assert(false)
    }
}

@Test
func testParseDoctypeIsUnknown(): Unit {
    let doc = XmlDocument.parseString("<!DOCTYPE html><r/>")
    // 顶层第一个非声明节点应为 XmlUnknown
    var firstUnknownFound = false
    for (n in doc.childNodes()) {
        if (let Unknown(_) <- n.kind()) {
            firstUnknownFound = true
            break
        }
    }
    @Expect(firstUnknownFound, true)
}

@Test
func testParseMixedContent(): Unit {
    let doc = XmlDocument.parseString("<r>hello <b>bold</b> world</r>")
    let r = doc.rootElement.getOrThrow()
    @Expect(r.textContent(), "hello bold world")
}

@Test
func testParseRoundTripSimple(): Unit {
    let original = "<root><a id=\"1\"/><b>text</b></root>"
    let doc1 = XmlDocument.parseString(original)
    let sink1 = StringXmlSink()
    XmlWriter(sink1, options: XmlWriteOptions.compactPreset()).writeDocument(doc1)
    let emitted = sink1.toString()
    // 再 parse 一次，结构等价
    let doc2 = XmlDocument.parseString(emitted)
    @Expect(doc2.rootElement.getOrThrow().name, "root")
    let sink2 = StringXmlSink()
    XmlWriter(sink2, options: XmlWriteOptions.compactPreset()).writeDocument(doc2)
    @Expect(emitted, sink2.toString())
}

@Test
func testParseRoundTripWithEntities(): Unit {
    // 原文里的 & < > 等在写出时会被转义，parse 后文本内容应一致
    let expectedText = "a & b < c"
    let doc1 = XmlDocument()
    let root = doc1.createElement("r")
    doc1.appendChild(root)
    root.appendChild(doc1.createText(expectedText))
    let sink = StringXmlSink()
    XmlWriter(sink, options: XmlWriteOptions.compactPreset()).writeDocument(doc1)
    let doc2 = XmlDocument.parseString(sink.toString())
    @Expect(doc2.rootElement.getOrThrow().textContent(), expectedText)
}

// ====================================================================
// 错误路径
// ====================================================================

@Test
func testErrorEmptyDocument(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("   ")
    } catch (e: XmlParseException) {
        if (let EmptyDocument <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testErrorMismatchedEndTag(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<a></b>")
    } catch (e: XmlParseException) {
        if (let MismatchedElement(_, _, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testErrorMultipleRoots(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<a/><b/>")
    } catch (e: XmlParseException) {
        caught = true
    }
    @Expect(caught, true)
}

@Test
func testErrorUnknownEntity(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r>&unknown;</r>")
    } catch (e: XmlParseException) {
        if (let InvalidText(_, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testErrorUnterminatedAttribute(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r a=\"oops/>")
    } catch (e: XmlParseException) {
        if (let InvalidAttribute(_, _, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testErrorLessThanInAttribute(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r a=\"<\"/>")
    } catch (e: XmlParseException) {
        if (let InvalidAttribute(_, _, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testErrorDepthExceeded(): Unit {
    let opts = XmlParseOptions(maxElementDepth: 3)
    var caught = false
    try {
        XmlDocument.parseString("<a><b><c><d/></c></b></a>", opts)
    } catch (e: XmlParseException) {
        if (let ElementDepthExceeded(_, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

// ====================================================================
// 空白策略
// ====================================================================

@Test
func testCollapseWhitespace(): Unit {
    let opts = XmlParseOptions(whitespace: Collapse)
    let doc = XmlDocument.parseString("<r>  hello\n  world  </r>", opts)
    @Expect(doc.rootElement.getOrThrow().textContent(), "hello world")
}

@Test
func testPreserveWhitespaceByDefault(): Unit {
    let doc = XmlDocument.parseString("<r>  hello\n  world  </r>")
    @Expect(doc.rootElement.getOrThrow().textContent(), "  hello\n  world  ")
}

@Test
func testCollapseSkipsWhitespaceOnlyBetweenElements(): Unit {
    let opts = XmlParseOptions(whitespace: Collapse)
    let doc = XmlDocument.parseString("<r>\n  <a/>\n  <b/>\n</r>", opts)
    let root = doc.rootElement.getOrThrow()
    var elementCount = 0
    var textCount = 0
    for (n in root.childNodes()) {
        match (n.kind()) {
            case Element(_) => elementCount++
            case Text(_) => textCount++
            case _ => ()
        }
    }
    @Expect(elementCount, 2)
    @Expect(textCount, 0)
}

// ====================================================================
// BOM 处理
// ====================================================================

@Test
func testBomAccepted(): Unit {
    let withBom = "\u{FEFF}<r/>"
    let doc = XmlDocument.parseString(withBom)
    @Expect(doc.rootElement.getOrThrow().name, "r")
}

@Test
func testBomPropagatesToDocument(): Unit {
    // 回归：parser 剥离 BOM 时必须把 doc.hasBom=true；否则 parse→write 丢 BOM
    let doc = XmlDocument.parseString("\u{FEFF}<r/>")
    @Expect(doc.hasBom, true)
    @Expect(doc.writeBom, false) // writeBom 不应被连带打开
    @Expect(XmlDocument.parseString("<r/>").hasBom, false)
}

@Test
func testBomRejectedWhenDisabled(): Unit {
    let withBom = "\u{FEFF}<r/>"
    let opts = XmlParseOptions(acceptBom: false)
    var caught = false
    try {
        XmlDocument.parseString(withBom, opts)
    } catch (e: XmlParseException) {
        if (let InvalidEncoding(_, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

// ====================================================================
// 数值实体 / 空输入 / 深度超限 / 重复属性 / round-trip 等边界用例
// ====================================================================

@Test
func testParseEmojiNumericEntity(): Unit {
    // U+1F600 GRINNING FACE 是 4 字节 UTF-8；单独覆盖以防 Rune 构造路径回退
    let doc = XmlDocument.parseString("<r>&#x1F600;</r>")
    @Expect(doc.rootElement.getOrThrow().textContent(), "\u{1F600}")
}

@Test
func testParseMixedDecimalAndHexEntities(): Unit {
    let doc = XmlDocument.parseString("<r>A=&#65; 中=&#x4E2D;</r>")
    @Expect(doc.rootElement.getOrThrow().textContent(), "A=A 中=中")
}

@Test
func testParseEmptyInputRejected(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("")
    } catch (e: XmlParseException) {
        if (let EmptyDocument <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseOnlyWhitespaceRejected(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("   \n\t  ")
    } catch (e: XmlParseException) {
        if (let EmptyDocument <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseDepthLimitHit(): Unit {
    // 构造深度 5 的嵌套；限制设为 3 必挂
    let opts = XmlParseOptions(maxElementDepth: 3)
    var caught = false
    try {
        XmlDocument.parseString("<a><b><c><d><e/></d></c></b></a>", opts)
    } catch (e: XmlParseException) {
        if (let ElementDepthExceeded(_, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseDuplicateAttributeRejected(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r a='1' a='2'/>")
    } catch (e: XmlParseException) {
        if (let InvalidAttribute(name, _, _) <- e.error) {
            caught = (name == "a")
        }
    }
    @Expect(caught, true)
}

@Test
func testParseUnterminatedEntityRejected(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r>&amp</r>")
    } catch (_: XmlParseException) {
        caught = true
    }
    @Expect(caught, true)
}

@Test
func testParseWhitespaceCollapseMode(): Unit {
    let opts = XmlParseOptions(whitespace: Collapse)
    let doc = XmlDocument.parseString("<r>  hello   \n\n world  </r>", opts)
    // Collapse：内部连续空白折叠为单空格；首尾空白被吃掉（见 collapseWhitespace 实现）
    @Expect(doc.rootElement.getOrThrow().textContent(), "hello world")
}

@Test
func testParseWhitespaceCollapseDropsEmptyTextNodes(): Unit {
    // Collapse 模式下，"仅空白"的文本节点会被丢弃——这是 tinyxml2 语义
    // 结果：<r> 之下只有 <a/>，无 Text 子节点
    let opts = XmlParseOptions(whitespace: Collapse)
    let doc = XmlDocument.parseString("<r>  \n  <a/>  \n  </r>", opts)
    var textCount = 0
    var elemCount = 0
    for (n in doc.rootElement.getOrThrow().childNodes()) {
        match (n.kind()) {
            case Text(_) => textCount++
            case Element(_) => elemCount++
            case _ => ()
        }
    }
    @Expect(textCount, 0)
    @Expect(elemCount, 1)
}

// ====================================================================
// parse → write → parse 的 round-trip（需要同时依赖 writer）
// ====================================================================

@Test
func testCdataTerminatorRoundTripsThroughWriter(): Unit {
    let doc = XmlDocument()
    let r = doc.createElement("r")
    doc.appendChild(r)
    r.appendChild(doc.createText("foo]]>bar", cdata: true))
    let sink = StringXmlSink()
    XmlWriter(sink, options: XmlWriteOptions(writeDeclaration: false, compact: true)).writeDocument(doc)
    let out = sink.toString()
    // 再解析：textContent 仍应等于原始串
    let doc2 = XmlDocument.parseString(out)
    @Expect(doc2.rootElement.getOrThrow().textContent(), "foo]]>bar")
}

@Test
func testDoctypeUnknownRoundTrip(): Unit {
    let xml = "<!DOCTYPE note SYSTEM \"note.dtd\"><r/>"
    let doc = XmlDocument.parseString(xml)
    let sink = StringXmlSink()
    XmlWriter(sink, options: XmlWriteOptions(writeDeclaration: false, compact: true)).writeDocument(doc)
    let out = sink.toString()
    // 回归："<!" / "!"" 双重包装曾把 <!DOCTYPE ...> 写成 <!!DOCTYPE ...>
    // 正确：输出必须与输入一字不差
    @Expect(out, xml)
    let doc2 = XmlDocument.parseString(out)
    var unknownCount = 0
    for (n in doc2.childNodes()) {
        if (let Unknown(_) <- n.kind()) {
            unknownCount++
        }
    }
    @Expect(unknownCount, 1)
}

@Test
func testProcessingInstructionInsideElementRoundTrip(): Unit {
    // 元素内的 <?target data?> 存为 XmlUnknown("?target data?")
    // 写回时必须仍是 <?target data?>，不能变成 <!?target data?>
    let xml = "<r><?xml-stylesheet href=\"a.xsl\"?><a/></r>"
    let doc = XmlDocument.parseString(xml)
    let sink = StringXmlSink()
    XmlWriter(sink, options: XmlWriteOptions(writeDeclaration: false, compact: true)).writeDocument(doc)
    let out = sink.toString()
    @Expect(out, xml)
}

// ====================================================================
// 覆盖率补充：顶层 / 元素级错误分支与 options.toString
// ====================================================================

@Test
func testXmlWhitespaceModeToString(): Unit {
    @Expect(Preserve.toString(), "Preserve")
    @Expect(Collapse.toString(), "Collapse")
}

@Test
func testXmlParseOptionsDefaultFactory(): Unit {
    let o = XmlParseOptions.default_()
    @Expect(o.maxElementDepth, DEFAULT_MAX_ELEMENT_DEPTH)
    @Expect(o.acceptBom, true)
}

@Test
func testParseStrayEndTagAtTopLevel(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("</oops>")
    } catch (e: XmlParseException) {
        if (let MismatchedElement(_, _, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseUnexpectedTextAtTopLevel(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("bare text<r/>")
    } catch (e: XmlParseException) {
        if (let InvalidText(_, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseEofAfterLtAtTopLevel(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<")
    } catch (e: XmlParseException) {
        if (let InvalidText(_, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseUnterminatedProcessingInstructionAtTopLevel(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<?xml version=\"1.0\"")
    } catch (e: XmlParseException) {
        if (let InvalidDeclaration(_, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseCdataAtTopLevelRejected(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<![CDATA[x]]><r/>")
    } catch (e: XmlParseException) {
        if (let InvalidText(_, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseUnterminatedComment(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<!-- oops")
    } catch (e: XmlParseException) {
        if (let InvalidComment(_, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseUnterminatedCdataInsideElement(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r><![CDATA[oops</r>")
    } catch (e: XmlParseException) {
        if (let InvalidText(_, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseDoctypeWithInternalSubsetBrackets(): Unit {
    // 覆盖 `<!` markup 的 `[`/`]` 括号深度处理——DOCTYPE 内含 `[...]`
    // 的子集声明时，`>` 应仅在方括号配平后才终止节点
    let xml = "<!DOCTYPE r [<!ELEMENT r (#PCDATA)>]><r/>"
    let doc = XmlDocument.parseString(xml)
    var foundUnknown = false
    for (n in doc.childNodes()) {
        if (let Unknown(u) <- n.kind()) {
            if (u.value.contains("[")) {
                foundUnknown = true
            }
        }
    }
    @Expect(foundUnknown, true)
    @Expect(doc.rootElement.getOrThrow().name, "r")
}

@Test
func testParseUnterminatedBangMarkup(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<!DOCTYPE x")
    } catch (e: XmlParseException) {
        if (let InvalidUnknownNode(_, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

// --- 元素级错误分支 -------------------------------------------------

@Test
func testParseEofInsideStartTag(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r ")
    } catch (e: XmlParseException) {
        if (let InvalidAttribute(_, _, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseAttributeMissingEquals(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r a 'v'/>")
    } catch (e: XmlParseException) {
        if (let InvalidAttribute(name, _, _) <- e.error) {
            caught = (name == "a")
        }
    }
    @Expect(caught, true)
}

@Test
func testParseUnquotedAttributeValue(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r a=v/>")
    } catch (e: XmlParseException) {
        if (let InvalidAttribute(_, _, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseEofInsideAttributeValue(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r a=")
    } catch (e: XmlParseException) {
        if (let InvalidAttribute(_, _, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseUnterminatedAttributeValue(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r a=\"oops")
    } catch (e: XmlParseException) {
        if (let InvalidAttribute(_, _, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseEofAfterLtInsideElement(): Unit {
    // 元素内遇到 `<` 之后 EOF——触发 xml_parser_element.cj 的相应分支
    var caught = false
    try {
        XmlDocument.parseString("<r><")
    } catch (e: XmlParseException) {
        if (let InvalidText(_, _) <- e.error) {
            caught = true
        }
        if (let MismatchedElement(_, _, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseElementEofBeforeEndTag(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r>hello")
    } catch (e: XmlParseException) {
        if (let MismatchedElement(_, close, _) <- e.error) {
            caught = (close == "(EOF)")
        }
    }
    @Expect(caught, true)
}

@Test
func testParseUnterminatedPiInsideElement(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r><?target data")
    } catch (e: XmlParseException) {
        if (let InvalidUnknownNode(_, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseAttributeNameStartsWithDigitRejected(): Unit {
    // 覆盖 readName 的 "expected name-start character" 分支
    var caught = false
    try {
        XmlDocument.parseString("<1bad/>")
    } catch (e: XmlParseException) {
        if (let InvalidText(_, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseAttributeValueWithUpperHexEntity(): Unit {
    // 命中 `A-F` 范围的 hexDigitValue 分支
    let doc = XmlDocument.parseString("<r a=\"&#x4e2D;&#X20AC;\"/>")
    @Expect(doc.rootElement.getOrThrow().attribute("a").getOrThrow(), "中€")
}

@Test
func testParseInvalidHexEntityNonHexChar(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r>&#xZZ;</r>")
    } catch (e: XmlParseException) {
        if (let InvalidText(_, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseInvalidDecimalEntityNonDigit(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r>&#1a2;</r>")
    } catch (e: XmlParseException) {
        if (let InvalidText(_, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseEmptyNumericEntity(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r>&#;</r>")
    } catch (e: XmlParseException) {
        if (let InvalidText(_, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseHexEntityMissingDigits(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r>&#x;</r>")
    } catch (e: XmlParseException) {
        if (let InvalidText(_, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseEmptyEntityReferenceBody(): Unit {
    var caught = false
    try {
        XmlDocument.parseString("<r>&;</r>")
    } catch (e: XmlParseException) {
        if (let InvalidText(_, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseInvalidCodepointEntity(): Unit {
    // `&#0;` → 码点 0 不在 XML 1.0 §2.2 Char 定义内
    var caught = false
    try {
        XmlDocument.parseString("<r>&#0;</r>")
    } catch (e: XmlParseException) {
        if (let InvalidText(_, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}

@Test
func testParseSelfClosingMissingGtTriggersConsumeExpected(): Unit {
    // `<r/` 后应是 `>`，此处给了 `x`——触发 `consumeExpected(CH_GT)` 抛错
    var caught = false
    try {
        XmlDocument.parseString("<r/x>")
    } catch (e: XmlParseException) {
        if (let InvalidText(_, _) <- e.error) {
            caught = true
        }
    }
    @Expect(caught, true)
}
