package fastxml.query

import std.unittest.*
import std.unittest.testmacro.*
import fastxml.dom.*
import fastxml.error.*

// ====================================================================
// 内置 codec
// ====================================================================

@Test
func testInt64CodecParse(): Unit {
    @Expect(INT64_CODEC.tryParse("42").getOrThrow(), 42)
    @Expect(INT64_CODEC.tryParse("  -7  ").getOrThrow(), -7)
    @Expect(INT64_CODEC.tryParse("").isNone(), true)
    @Expect(INT64_CODEC.tryParse("abc").isNone(), true)
    @Expect(INT64_CODEC.tryParse("3.14").isNone(), true)
}

@Test
func testInt64CodecFormat(): Unit {
    @Expect(INT64_CODEC.format(42), "42")
    @Expect(INT64_CODEC.format(-1), "-1")
    @Expect(INT64_CODEC.format(0), "0")
}

@Test
func testBoolCodecAcceptsVariants(): Unit {
    @Expect(BOOL_CODEC.tryParse("true").getOrThrow(), true)
    @Expect(BOOL_CODEC.tryParse("TRUE").getOrThrow(), true)
    @Expect(BOOL_CODEC.tryParse(" 1 ").getOrThrow(), true)
    @Expect(BOOL_CODEC.tryParse("false").getOrThrow(), false)
    @Expect(BOOL_CODEC.tryParse("FALSE").getOrThrow(), false)
    @Expect(BOOL_CODEC.tryParse("0").getOrThrow(), false)
    @Expect(BOOL_CODEC.tryParse("yes").isNone(), true)
}

@Test
func testBoolCodecFormat(): Unit {
    @Expect(BOOL_CODEC.format(true), "true")
    @Expect(BOOL_CODEC.format(false), "false")
}

@Test
func testFloat64Codec(): Unit {
    let v = FLOAT64_CODEC.tryParse("3.14").getOrThrow()
    @Expect(v > 3.13 && v < 3.15, true)
    @Expect(FLOAT64_CODEC.tryParse("not-a-number").isNone(), true)
}

@Test
func testStringCodec(): Unit {
    @Expect(STRING_CODEC.tryParse("anything").getOrThrow(), "anything")
    @Expect(STRING_CODEC.format("x"), "x")
}

// ====================================================================
// attribute-level query
// ====================================================================

func makeSample(): XmlElement {
    let doc = XmlDocument()
    let e = doc.createElement("row")
    doc.appendChild(e)
    e.setAttribute("id", "42")
    e.setAttribute("flag", "true")
    e.setAttribute("pi", "3.14")
    e.setAttribute("name", "alice")
    e.setAttribute("garbage", "not-an-int")
    e
}

@Test
func testIntAttributeHappy(): Unit {
    let e = makeSample()
    @Expect(e.intAttribute("id").getOrThrow(), 42)
}

@Test
func testIntAttributeMissing(): Unit {
    let e = makeSample()
    @Expect(e.intAttribute("missing").isNone(), true)
}

@Test
func testIntAttributeParseFailure(): Unit {
    let e = makeSample()
    @Expect(e.intAttribute("garbage").isNone(), true)
}

@Test
func testBoolAndDoubleAttribute(): Unit {
    let e = makeSample()
    @Expect(e.boolAttribute("flag").getOrThrow(), true)
    let pi = e.doubleAttribute("pi").getOrThrow()
    @Expect(pi > 3.13 && pi < 3.15, true)
}

@Test
func testRequiredAttribute(): Unit {
    let e = makeSample()
    @Expect(e.requiredAttribute("name"), "alice")
}

@Test
func testRequiredAttributeMissingThrows(): Unit {
    let e = makeSample()
    var caught = false
    try {
        e.requiredAttribute("nope")
    } catch (_: XmlException) {
        caught = true
    }
    @Expect(caught, true)
}

@Test
func testRequiredAttributeAsParseFailureThrows(): Unit {
    let e = makeSample()
    var caught = false
    try {
        e.requiredAttributeAs<Int64>("garbage", INT64_CODEC)
    } catch (_: XmlException) {
        caught = true
    }
    @Expect(caught, true)
}

@Test
func testAttributeOrFallback(): Unit {
    let e = makeSample()
    @Expect(e.attributeOr<Int64>("id", INT64_CODEC, 0), 42)
    @Expect(e.attributeOr<Int64>("missing", INT64_CODEC, 99), 99)
    @Expect(e.attributeOr<Int64>("garbage", INT64_CODEC, 7), 7)
}

// ====================================================================
// child-element query
// ====================================================================

func makeTree(): XmlElement {
    let doc = XmlDocument()
    let root = doc.createElement("catalog")
    doc.appendChild(root)
    let b1 = doc.createElement("book")
    b1.setAttribute("id", "1")
    b1.setTextContent("SICP")
    root.appendChild(b1)
    let b2 = doc.createElement("book")
    b2.setAttribute("id", "2")
    b2.setTextContent("TAOCP")
    root.appendChild(b2)
    let meta = doc.createElement("meta")
    meta.setTextContent("42")
    root.appendChild(meta)
    root
}

@Test
func testChildElement(): Unit {
    let root = makeTree()
    @Expect(root.childElement("book").getOrThrow().textContent(), "SICP")
    @Expect(root.childElement("none").isNone(), true)
}

@Test
func testRequiredChildElementThrows(): Unit {
    let root = makeTree()
    var caught = false
    try {
        root.requiredChildElement("none")
    } catch (_: XmlException) {
        caught = true
    }
    @Expect(caught, true)
    // happy path still works
    @Expect(root.requiredChildElement("meta").name, "meta")
}

@Test
func testChildElementText(): Unit {
    let root = makeTree()
    @Expect(root.childElementText("book").getOrThrow(), "SICP")
    @Expect(root.childElementText("none").isNone(), true)
}

@Test
func testChildElementTextAs(): Unit {
    let root = makeTree()
    @Expect(root.childElementTextAs<Int64>("meta", INT64_CODEC).getOrThrow(), 42)
    @Expect(root.childElementTextAs<Int64>("book", INT64_CODEC).isNone(), true)
}

@Test
func testChildElementTexts(): Unit {
    let root = makeTree()
    let all = root.childElementTexts("book")
    @Expect(all.size, 2)
    @Expect(all[0], "SICP")
    @Expect(all[1], "TAOCP")
    @Expect(root.childElementTexts("missing").size, 0)
}

// ======================================================================
// 覆盖率补充：Int32 / Float64 codec、int32Attribute、childElementTextAs None 分支
// ======================================================================

@Test
func testInt32CodecRoundTrip(): Unit {
    @Expect(INT32_CODEC.tryParse("42").getOrThrow(), 42i32)
    @Expect(INT32_CODEC.tryParse("  -7 ").getOrThrow(), -7i32)
    @Expect(INT32_CODEC.tryParse("").isNone(), true)
    @Expect(INT32_CODEC.tryParse("abc").isNone(), true)
    @Expect(INT32_CODEC.format(123i32), "123")
}

@Test
func testFloat64CodecRoundTrip(): Unit {
    @Expect(FLOAT64_CODEC.tryParse("3.14").getOrThrow(), 3.14)
    @Expect(FLOAT64_CODEC.tryParse("  -2.5 ").getOrThrow(), -2.5)
    @Expect(FLOAT64_CODEC.tryParse("").isNone(), true)
    @Expect(FLOAT64_CODEC.tryParse("xyz").isNone(), true)
    // format 只验证形状——具体小数文本由标准库决定
    @Expect(FLOAT64_CODEC.format(1.0).contains("1"), true)
}

@Test
func testInt32AttributeReadsValue(): Unit {
    let root = makeTree()
    let book = root.requiredChildElement("book")
    book.setAttribute("n", "-128")
    @Expect(book.int32Attribute("n").getOrThrow(), -128i32)
    @Expect(book.int32Attribute("missing").isNone(), true)
}

@Test
func testChildElementTextAsReturnsNoneWhenMissing(): Unit {
    // 覆盖 childElementTextAs 中 childElementText 返回 None 的分支。
    let root = makeTree()
    @Expect(root.childElementTextAs<Int64>("missing", INT64_CODEC).isNone(), true)
}
