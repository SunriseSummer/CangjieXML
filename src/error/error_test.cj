package tinyxml2.error

import std.unittest.*
import std.unittest.testmacro.*

/**
 * `XmlError` / `SourcePos` / 异常类型的单元测试。
 *
 * 这些类型绝大多数分支之前只被 parser_test 通过"真实解析错误"间接触达，
 * 而 `XmlError.toString` 的每个分支都是面向调用方的诊断面——值得直接钉死，
 * 以免某分支的格式被误改后只能靠集成测试才发现。
 */

@Test
func testSourcePosToString(): Unit {
    let p = SourcePos(42, 3, 5)
    @Expect(p.toString(), "line 3, column 5 (offset 42)")
}

@Test
func testSourcePosZeroSentinel(): Unit {
    let z = SourcePos.zero()
    @Expect(z.offset, 0)
    @Expect(z.line, 1)
    @Expect(z.column, 1)
}

@Test
func testXmlErrorToStringDomOperation(): Unit {
    let e = DomOperationFailed("cycle")
    @Expect(e.toString(), "DomOperationFailed: cycle")
}

@Test
func testXmlErrorToStringFileFamily(): Unit {
    @Expect(FileNotFound("/p").toString(), "FileNotFound: /p")
    @Expect(FileReadFailed("/p", "EACCES").toString(), "FileReadFailed: /p (EACCES)")
    @Expect(FileWriteFailed("/p", "ENOSPC").toString(), "FileWriteFailed: /p (ENOSPC)")
}

@Test
func testXmlErrorToStringStructuralFamily(): Unit {
    let at = SourcePos(1, 2, 3)
    @Expect(EmptyDocument.toString(), "EmptyDocument")
    @Expect(
        MismatchedElement("a", "b", at).toString(),
        "MismatchedElement: <a> vs </b> at line 2, column 3 (offset 1)"
    )
    @Expect(
        InvalidAttribute("id", at, "duplicate").toString(),
        "InvalidAttribute 'id' at line 2, column 3 (offset 1): duplicate"
    )
    @Expect(
        InvalidText(at, "no '<' allowed").toString(),
        "InvalidText at line 2, column 3 (offset 1): no '<' allowed"
    )
    @Expect(
        InvalidComment(at, "unterminated").toString(),
        "InvalidComment at line 2, column 3 (offset 1): unterminated"
    )
    @Expect(
        InvalidDeclaration(at, "bad").toString(),
        "InvalidDeclaration at line 2, column 3 (offset 1): bad"
    )
    @Expect(
        InvalidUnknownNode(at, "bad").toString(),
        "InvalidUnknownNode at line 2, column 3 (offset 1): bad"
    )
    @Expect(
        InvalidEncoding(at, "BOM").toString(),
        "InvalidEncoding at line 2, column 3 (offset 1): BOM"
    )
    @Expect(
        ElementDepthExceeded(500, at).toString(),
        "ElementDepthExceeded (limit=500) at line 2, column 3 (offset 1)"
    )
    @Expect(
        ValueDecodeFailed("Int64", "abc", at).toString(),
        "ValueDecodeFailed: cannot parse 'abc' as Int64 at line 2, column 3 (offset 1)"
    )
}

@Test
func testXmlExceptionCarriesMessage(): Unit {
    let e = XmlException("broken")
    @Expect(e.message, "broken")
    @Expect(e.getClassName(), "XmlException")
}

@Test
func testXmlParseExceptionExposesError(): Unit {
    let pe = XmlParseException(EmptyDocument)
    @Expect(pe.getClassName(), "XmlParseException")
    // `error` 字段必须可读，而不是被 super.message 吃掉
    match (pe.error) {
        case EmptyDocument => ()
        case _ => @Fail("XmlParseException.error lost the payload")
    }
    // message 应来自 error.toString()
    @Expect(pe.message, "EmptyDocument")
}
