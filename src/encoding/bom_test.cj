package cangjie_xml.encoding

import std.unittest.*

@Test
public func testDetectBomUtf8(): Unit {
    match (detectBom([0xEFu8, 0xBBu8, 0xBFu8, 0x41u8])) {
        case Some(k) => @Expect(k == BomKind.Utf8, true)
        case None => @Fail("expected Utf8 BOM")
    }
}

@Test
public func testDetectBomUtf16(): Unit {
    match (detectBom([0xFFu8, 0xFEu8, 0x41u8, 0x00u8])) {
        case Some(k) => @Expect(k == BomKind.Utf16Le, true)
        case _ => @Fail("expected Utf16Le")
    }
    match (detectBom([0xFEu8, 0xFFu8, 0x00u8, 0x41u8])) {
        case Some(k) => @Expect(k == BomKind.Utf16Be, true)
        case _ => @Fail("expected Utf16Be")
    }
}

@Test
public func testDetectBomUtf32BeforeUtf16(): Unit {
    // UTF-32 LE BOM 的前两字节与 UTF-16 LE 相同；探测器应优先选 UTF-32。
    match (detectBom([0xFFu8, 0xFEu8, 0x00u8, 0x00u8])) {
        case Some(k) => @Expect(k == BomKind.Utf32Le, true)
        case _ => @Fail("expected Utf32Le")
    }
    match (detectBom([0x00u8, 0x00u8, 0xFEu8, 0xFFu8])) {
        case Some(k) => @Expect(k == BomKind.Utf32Be, true)
        case _ => @Fail("expected Utf32Be")
    }
}

@Test
public func testDetectBomNone(): Unit {
    @Expect(detectBom([0x41u8, 0x42u8]).isNone(), true)
    @Expect(detectBom([]).isNone(), true)
    @Expect(detectBom([0x41u8]).isNone(), true)
}

@Test
public func testHeuristicDetect(): Unit {
    // "<?xm" in UTF-16 BE: 00 3C 00 3F
    match (heuristicDetect([0x00u8, 0x3Cu8, 0x00u8, 0x3Fu8])) {
        case Some(k) => @Expect(k == BomKind.Utf16Be, true)
        case _ => @Fail("expected heuristic Utf16Be")
    }
    // "<?xm" in UTF-16 LE: 3C 00 3F 00
    match (heuristicDetect([0x3Cu8, 0x00u8, 0x3Fu8, 0x00u8])) {
        case Some(k) => @Expect(k == BomKind.Utf16Le, true)
        case _ => @Fail("expected heuristic Utf16Le")
    }
    // ASCII "<?xm" → None（由声明定）
    @Expect(heuristicDetect([0x3Cu8, 0x3Fu8, 0x78u8, 0x6Du8]).isNone(), true)
}
