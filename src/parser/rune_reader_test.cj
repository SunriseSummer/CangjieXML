/*
 * RuneReader 单元测试。
 *
 * 覆盖：
 *   - 基础 peek/advance；
 *   - 换行归一化（CR / CRLF / XML 1.1 NEL / LS）；
 *   - 行列号追踪；
 *   - consumeIf / consumeIfStr；
 *   - peek(k) 回看；
 *   - 中文字符（非 ASCII rune）；
 *   - EOF 语义；
 *   - close 级联。
 */
package cangjie_xml.parser

import std.unittest.*
import cangjie_xml.core.*
import cangjie_xml.io.*

private func mkReader(s: String, version!: XmlVersion = XmlVersion.V10): RuneReader {
    let ds = DecodingSource(StringSource(s))
    return RuneReader(ds, version: version)
}

@Test
public func testRuneReaderPeekAdvance(): Unit {
    let rr = mkReader("abc")
    @Expect(rr.peek().getOrThrow(), r'a')
    @Expect(rr.advance().getOrThrow(), r'a')
    @Expect(rr.advance().getOrThrow(), r'b')
    @Expect(rr.advance().getOrThrow(), r'c')
    @Expect(rr.isEof(), true)
    @Expect(rr.advance().isNone(), true)
}

@Test
public func testRuneReaderPeekK(): Unit {
    let rr = mkReader("abcd")
    @Expect(rr.peek(k: 0).getOrThrow(), r'a')
    @Expect(rr.peek(k: 1).getOrThrow(), r'b')
    @Expect(rr.peek(k: 2).getOrThrow(), r'c')
    @Expect(rr.peek(k: 3).getOrThrow(), r'd')
    @Expect(rr.peek(k: 4).isNone(), true)
}

@Test
public func testRuneReaderLineColumn(): Unit {
    let rr = mkReader("a\nb\nc")
    @Expect(rr.currentPosition().line, 1)
    @Expect(rr.currentPosition().column, 1)
    let _ = rr.advance() // 'a'
    @Expect(rr.currentPosition().line, 1)
    @Expect(rr.currentPosition().column, 2)
    let _ = rr.advance() // '\n'
    @Expect(rr.currentPosition().line, 2)
    @Expect(rr.currentPosition().column, 1)
    let _ = rr.advance() // 'b'
    @Expect(rr.currentPosition().line, 2)
    @Expect(rr.currentPosition().column, 2)
    let _ = rr.advance() // '\n'
    @Expect(rr.currentPosition().line, 3)
    @Expect(rr.currentPosition().column, 1)
}

@Test
public func testRuneReaderCrLfNormalization(): Unit {
    // CR + LF -> single LF
    let rr = mkReader("a\r\nb")
    @Expect(rr.advance().getOrThrow(), r'a')
    let nl = rr.advance().getOrThrow()
    @Expect(UInt32(nl), 0x0Au32)
    @Expect(rr.advance().getOrThrow(), r'b')
    @Expect(rr.isEof(), true)
}

@Test
public func testRuneReaderLoneCr(): Unit {
    // Lone CR -> LF
    let rr = mkReader("\ra")
    let nl = rr.advance().getOrThrow()
    @Expect(UInt32(nl), 0x0Au32)
    @Expect(rr.advance().getOrThrow(), r'a')
}

@Test
public func testRuneReaderCrLfLineCount(): Unit {
    let rr = mkReader("x\r\ny")
    let _ = rr.advance() // x
    let _ = rr.advance() // newline (from CRLF)
    @Expect(rr.currentPosition().line, 2)
    @Expect(rr.currentPosition().column, 1)
    let _ = rr.advance() // y
    @Expect(rr.currentPosition().column, 2)
}

@Test
public func testRuneReaderXml11Nel(): Unit {
    // XML 1.1 NEL (U+0085) → LF
    let sb = StringBuilder()
    sb.append(r'a')
    sb.append(Rune(0x85u32))
    sb.append(r'b')
    let rr = mkReader(sb.toString(), version: XmlVersion.V11)
    @Expect(rr.advance().getOrThrow(), r'a')
    let nl = rr.advance().getOrThrow()
    @Expect(UInt32(nl), 0x0Au32)
    @Expect(rr.advance().getOrThrow(), r'b')
}

@Test
public func testRuneReaderXml11LineSeparator(): Unit {
    // U+2028 LS → LF in XML 1.1
    let sb = StringBuilder()
    sb.append(r'a')
    sb.append(Rune(0x2028u32))
    sb.append(r'b')
    let rr = mkReader(sb.toString(), version: XmlVersion.V11)
    @Expect(rr.advance().getOrThrow(), r'a')
    let nl = rr.advance().getOrThrow()
    @Expect(UInt32(nl), 0x0Au32)
    @Expect(rr.advance().getOrThrow(), r'b')
}

@Test
public func testRuneReaderXml10DoesNotNormalizeNel(): Unit {
    // In XML 1.0, U+0085 is a normal character
    let sb = StringBuilder()
    sb.append(r'a')
    sb.append(Rune(0x85u32))
    sb.append(r'b')
    let rr = mkReader(sb.toString(), version: XmlVersion.V10)
    @Expect(rr.advance().getOrThrow(), r'a')
    let r = rr.advance().getOrThrow()
    @Expect(UInt32(r), 0x85u32)
}

@Test
public func testRuneReaderConsumeIf(): Unit {
    let rr = mkReader("<?xml")
    @Expect(rr.consumeIf(r'<'), true)
    @Expect(rr.consumeIf(r'X'), false)  // wrong char
    @Expect(rr.consumeIf(r'?'), true)
    @Expect(rr.consumeIfStr("xml"), true)
    @Expect(rr.isEof(), true)
}

@Test
public func testRuneReaderConsumeIfStrNoMatch(): Unit {
    let rr = mkReader("abcd")
    @Expect(rr.consumeIfStr("abx"), false)
    // 不应消费任何字符
    @Expect(rr.peek().getOrThrow(), r'a')
}

@Test
public func testRuneReaderUnicode(): Unit {
    let rr = mkReader("中文")
    let c1 = rr.advance().getOrThrow()
    @Expect(UInt32(c1), 0x4E2Du32) // 中
    let c2 = rr.advance().getOrThrow()
    @Expect(UInt32(c2), 0x6587u32) // 文
    @Expect(rr.isEof(), true)
}

@Test
public func testRuneReaderCharacterOffset(): Unit {
    let rr = mkReader("a\nb")
    @Expect(rr.characterOffset(), 0)
    let _ = rr.advance()
    @Expect(rr.characterOffset(), 1)
    let _ = rr.advance()
    @Expect(rr.characterOffset(), 2)
    let _ = rr.advance()
    @Expect(rr.characterOffset(), 3)
}

@Test
public func testRuneReaderCloseClosesDecodingSource(): Unit {
    let ds = DecodingSource(StringSource("hi"))
    let rr = RuneReader(ds, ownedSource: true)
    rr.close()
    @Expect(ds.isClosed(), true)
}
