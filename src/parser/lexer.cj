/*
 * parser — Lexer：XML 1.0 / 1.1 词法分析器
 *
 * 对应 libxml2: parser.c 中的词法路径（`xmlParseContent` / `xmlParseStartTag` /
 * `xmlParseAttribute` / `xmlParseCharData` / `xmlParsePI` / ...）。
 *
 * 设计要点：
 *   - 以 `Iterator<Token>` 暴露；每次 `next()` 推进最少 1 个 token。
 *   - 状态机手写，不使用正则：XML 词法有大量"直到某个多字符分隔符"的规则，
 *     逐字符 + `peek(k)` 的实现最清晰也最快。
 *   - 位置追踪全部依赖 `RuneReader.currentPosition()`，每个 token 的 Position
 *     取"该 token 第一字符刚被 RuneReader 指到的位置"——即 `produce` 前先 snapshot。
 *   - 严格的 well-formedness 在词法层能覆盖的部分：
 *     * `]]>` 不允许出现在文本中（除 CDATA 内）；
 *     * 注释不允许包含 `--`，末尾不允许 `--->`；
 *     * PI target 不区分大小写地不能是 `xml`（除非出现在文档最前面作为 XML 声明）；
 *     * 属性值中直接出现 `<` 非法；
 *     * XML 声明只能出现在最开始。
 *   - 跨 token 的一致性（元素开闭匹配、命名空间）留给 Parser 层。
 *   - 错误通过 `XmlException(XmlError)` 抛出，Position 精确到字符。
 */
package cangjie_xml.parser

import std.collection.*
import cangjie_xml.core.*
import cangjie_xml.io.*

public class Lexer <: Iterator<Token> {
    private let reader: RuneReader
    private let version: XmlVersion
    private var emittedEof: Bool
    // 词法状态：跨属性值 / DOCTYPE 内部子集时需要记忆。
    // 我们把"是否已经发过 XmlDecl"以及"是否在 element open tag 内"显式标记：
    private var sawXmlDecl: Bool
    private var sawNonWhitespace: Bool // XML 声明只能出现在最前面
    // 元素开口深度（仅用于判断"是否位于 element content 区域"决定文本处理规则）。
    private var openDepth: Int64
    // 当前属性值还未结束的状态：Some(quote) 表示我们在属性值内，下一次 next() 要返回
    // 文本 chunk / EntityRef / CharRef 或 AttrValueEnd。
    private var inAttrValue: ?AttrQuote
    // 当前是否处于 open tag 内（属性列表）：遇到 `>` 或 `/>` 时结束。
    private var inOpenTag: Bool
    // pending token 队列（少数规则需要一次产生多个 token）。
    private let pending: ArrayDeque<Token>

    public init(reader: RuneReader) {
        this.reader = reader
        this.version = reader.xmlVersion
        this.emittedEof = false
        this.sawXmlDecl = false
        this.sawNonWhitespace = false
        this.openDepth = 0
        this.inAttrValue = None
        this.inOpenTag = false
        this.pending = ArrayDeque<Token>()
    }

    /** 便利构造：直接从字符串（UTF-8）构造 Lexer。测试用。 */
    public static func fromString(s: String, version!: XmlVersion = XmlVersion.V10): Lexer {
        let src = StringSource(s)
        let ds = DecodingSource(src)
        let rr = RuneReader(ds, version: version)
        return Lexer(rr)
    }

    public func next(): Option<Token> {
        if (!pending.isEmpty()) {
            return pending.removeFirst()
        }
        if (emittedEof) {
            return None
        }
        let tok = readNext()
        match (tok) {
            case Eof(_) => emittedEof = true
            case _ => ()
        }
        return Some(tok)
    }

    /* ---------- 主状态分派 ---------- */

    private func readNext(): Token {
        // 1) 如果在属性值内，走属性值片段路径
        match (inAttrValue) {
            case Some(q) => return readAttrValueFragment(q)
            case None => ()
        }
        // 2) 如果在 open tag 内，走属性分派路径
        if (inOpenTag) {
            return readInsideOpenTag()
        }
        // 3) 顶层 / 元素内容路径
        return readContent()
    }

    /* ---------- 内容路径 ---------- */

    private func readContent(): Token {
        let pos = reader.currentPosition()
        match (reader.peek()) {
            case None =>
                return Token.Eof(pos)
            case Some(r) => ()
        }
        let r = reader.peek().getOrThrow()
        let cp = cp(r)
        if (cp == 0x3C /* '<' */) {
            return readTagLike()
        }
        if (cp == 0x26 /* '&' */) {
            return readReference()
        }
        return readText()
    }

    private func readText(): Token {
        let startPos = reader.currentPosition()
        let sb = StringBuilder()
        while (true) {
            match (reader.peek()) {
                case None => break
                case Some(r) =>
                    let cp = cp(r)
                    if (cp == 0x3C || cp == 0x26) {
                        break
                    }
                    // "]]>" 不允许出现在文本中（W3C XML §2.4）。
                    if (cp == 0x5D /* ']' */) {
                        if (peekIs3(0x5D, 0x5D, 0x3E)) {
                            throw XmlException(XmlError.Malformed(
                                reader.currentPosition(),
                                "literal ']]>' must not appear in character data"
                            ))
                        }
                    }
                    if (!isXmlChar(cp, version: version)) {
                        throw XmlException(XmlError.UnexpectedChar(
                            reader.currentPosition(), r,
                            "invalid XML character (code point ${cp})"
                        ))
                    }
                    sb.append(r)
                    let _ = reader.advance()
                    if (!isXmlWhitespace(cp)) {
                        sawNonWhitespace = true
                    }
            }
        }
        return Token.Text(startPos, sb.toString())
    }

    /* ---------- 标签类：以 `<` 开头 ---------- */

    private func readTagLike(): Token {
        let startPos = reader.currentPosition()
        // 消费 `<`
        let _ = reader.advance()
        match (reader.peek()) {
            case None =>
                throw XmlException(XmlError.UnexpectedEof(
                    reader.currentPosition(), "input ended after '<'"
                ))
            case Some(next) =>
                let cp1 = cp(next)
                if (cp1 == 0x21 /* '!' */) {
                    return readBangConstruct(startPos)
                }
                if (cp1 == 0x3F /* '?' */) {
                    return readPiOrXmlDecl(startPos)
                }
                if (cp1 == 0x2F /* '/' */) {
                    return readElementClose(startPos)
                }
                // 否则：元素开口
                return readElementOpen(startPos)
        }
    }

    /**
     * 解析 `<!...`：可能是 `<!--` / `<![CDATA[` / `<!DOCTYPE`。
     */
    private func readBangConstruct(startPos: Position): Token {
        // 已消费 `<`。现在 peek 就是 '!'
        let _ = reader.advance() // 消费 '!'
        if (reader.consumeIfStr("--")) {
            return readCommentBody(startPos)
        }
        if (reader.consumeIfStr("[CDATA[")) {
            return readCDataBody(startPos)
        }
        if (reader.consumeIfStr("DOCTYPE")) {
            return readDoctypeHead(startPos)
        }
        throw XmlException(XmlError.Malformed(
            reader.currentPosition(),
            "expected '<!--', '<![CDATA[' or '<!DOCTYPE'"
        ))
    }

    private func readCommentBody(startPos: Position): Token {
        let sb = StringBuilder()
        while (true) {
            match (reader.peek()) {
                case None =>
                    throw XmlException(XmlError.UnexpectedEof(
                        reader.currentPosition(), "unterminated comment"
                    ))
                case Some(r) =>
                    let cp = cp(r)
                    if (cp == 0x2D /* '-' */ && peekIs2(0x2D, 0x2D)) {
                        // 看到 "--"；之后必须是 '>'
                        let dashPos = reader.currentPosition()
                        let _ = reader.advance() // 消费第一个 '-'
                        let _ = reader.advance() // 消费第二个 '-'
                        if (!reader.consumeIf(Rune(0x3Eu32))) {
                            throw XmlException(XmlError.Malformed(
                                dashPos, "'--' is not allowed inside comment"
                            ))
                        }
                        return Token.Comment(startPos, sb.toString())
                    }
                    if (!isXmlChar(cp, version: version)) {
                        throw XmlException(XmlError.UnexpectedChar(
                            reader.currentPosition(), r,
                            "invalid XML character in comment"
                        ))
                    }
                    sb.append(r)
                    let _ = reader.advance()
            }
        }
        return Token.Comment(startPos, sb.toString())
    }

    private func readCDataBody(startPos: Position): Token {
        let sb = StringBuilder()
        while (true) {
            match (reader.peek()) {
                case None =>
                    throw XmlException(XmlError.UnexpectedEof(
                        reader.currentPosition(), "unterminated CDATA section"
                    ))
                case Some(r) =>
                    let cp = cp(r)
                    if (cp == 0x5D /* ']' */ && peekIs3(0x5D, 0x5D, 0x3E)) {
                        // 消费 "]]>"
                        let _ = reader.advance()
                        let _ = reader.advance()
                        let _ = reader.advance()
                        return Token.CDataSection(startPos, sb.toString())
                    }
                    if (!isXmlChar(cp, version: version)) {
                        throw XmlException(XmlError.UnexpectedChar(
                            reader.currentPosition(), r,
                            "invalid XML character in CDATA section"
                        ))
                    }
                    sb.append(r)
                    let _ = reader.advance()
            }
        }
        return Token.CDataSection(startPos, sb.toString())
    }

    private func readDoctypeHead(startPos: Position): Token {
        // 已消费 "<!DOCTYPE"。后面必须至少一个空白，然后是 Name。
        if (!skipWhitespace1Plus()) {
            throw XmlException(XmlError.Malformed(
                reader.currentPosition(), "expected whitespace after <!DOCTYPE"
            ))
        }
        let name = readName()
        // 本迭代不解析 ExternalID / internal subset；把它们留给 Parser 层（Phase 3b）
        // 的上层包装。为了让本词法器能被当作黑盒独立测试，我们在这里**粗略地**跳过
        // DOCTYPE 剩余部分：读到匹配层级的 `>` 为止，忽略 `[...]` 内部子集以及
        // 嵌套引号字符串。这不等于验证 DTD —— 只确保 Lexer 不会把 DOCTYPE 内部的
        // `<` / `&` 误当作元素/实体。
        scanThroughDoctypeTail()
        return Token.DoctypeStart(startPos, name)
    }

    private func scanThroughDoctypeTail(): Unit {
        var insideBrackets = false
        while (true) {
            match (reader.peek()) {
                case None =>
                    throw XmlException(XmlError.UnexpectedEof(
                        reader.currentPosition(), "unterminated DOCTYPE"
                    ))
                case Some(r) =>
                    let c = cp(r)
                    if (!insideBrackets && c == 0x3E /* '>' */) {
                        // DoctypeEnd 作为一个独立 token 推入 pending；但我们已经在
                        // readDoctypeHead 的返回值中只返回 DoctypeStart，所以这里直接
                        // 把 DoctypeEnd 排到 pending。
                        let endPos = reader.currentPosition()
                        let _ = reader.advance()
                        pending.addLast(Token.DoctypeEnd(endPos))
                        return
                    }
                    if (c == 0x5B /* '[' */ && !insideBrackets) {
                        insideBrackets = true
                        let _ = reader.advance()
                        continue
                    }
                    if (c == 0x5D /* ']' */ && insideBrackets) {
                        insideBrackets = false
                        let _ = reader.advance()
                        continue
                    }
                    // 跳过带引号字符串，避免误吃到结束符
                    if (c == 0x22 || c == 0x27) {
                        let qChar = c
                        let _ = reader.advance()
                        while (true) {
                            match (reader.peek()) {
                                case None =>
                                    throw XmlException(XmlError.UnexpectedEof(
                                        reader.currentPosition(),
                                        "unterminated quoted string in DOCTYPE"
                                    ))
                                case Some(q) =>
                                    let qcp = cp(q)
                                    let _ = reader.advance()
                                    if (qcp == qChar) {
                                        break
                                    }
                            }
                        }
                        continue
                    }
                    // 普通字符：仍需校验合法性
                    if (!isXmlChar(c, version: version)) {
                        throw XmlException(XmlError.UnexpectedChar(
                            reader.currentPosition(), r,
                            "invalid XML character in DOCTYPE"
                        ))
                    }
                    let _ = reader.advance()
            }
        }
    }

    /** `<?target data?>` 或 `<?xml ...?>`（XML 声明）。 */
    private func readPiOrXmlDecl(startPos: Position): Token {
        // 已消费 `<`，当前 peek 是 '?'
        let _ = reader.advance() // 消费 '?'
        let target = readName()
        let lower = target.toAsciiLower()
        if (lower == "xml") {
            // XML 声明只允许出现在文档最前面
            if (target != "xml") {
                throw XmlException(XmlError.Malformed(
                    startPos,
                    "processing instruction target must not be 'xml' / 'XML' / any case variant"
                ))
            }
            if (sawXmlDecl || sawNonWhitespace || openDepth > 0) {
                throw XmlException(XmlError.Malformed(
                    startPos,
                    "XML declaration must appear at the very start of the document"
                ))
            }
            sawXmlDecl = true
            // 进入 XML 声明模式：后续产生 AttrName / AttrEq / AttrValue* 序列，最后 XmlDeclEnd
            // 本轮先只发 XmlDeclStart，剩余通过 inOpenTag 状态处理（引用 open-tag 共同代码）
            inOpenTag = true
            xmlDeclMode = true
            return Token.XmlDeclStart(startPos)
        }
        // 普通 PI：target 不能是 "xml" 的任意大小写变体
        if (lower == "xml") {
            throw XmlException(XmlError.Malformed(
                startPos, "PI target cannot be 'xml'"
            ))
        }
        // 读可选空白 + data 直到 `?>`
        skipWhitespace0Plus()
        let data = StringBuilder()
        while (true) {
            match (reader.peek()) {
                case None =>
                    throw XmlException(XmlError.UnexpectedEof(
                        reader.currentPosition(), "unterminated processing instruction"
                    ))
                case Some(r) =>
                    let cp = cp(r)
                    if (cp == 0x3F /* '?' */ && peekIs2(0x3F, 0x3E)) {
                        let _ = reader.advance()
                        let _ = reader.advance()
                        return Token.ProcessingInstruction(startPos, target, data.toString())
                    }
                    if (!isXmlChar(cp, version: version)) {
                        throw XmlException(XmlError.UnexpectedChar(
                            reader.currentPosition(), r,
                            "invalid XML character in processing instruction"
                        ))
                    }
                    data.append(r)
                    let _ = reader.advance()
            }
        }
        // unreachable
        return Token.ProcessingInstruction(startPos, target, data.toString())
    }

    /** `</name S? >` */
    private func readElementClose(startPos: Position): Token {
        // 已消费 `<`，当前 peek 是 '/'
        let _ = reader.advance() // 消费 '/'
        let name = readName()
        skipWhitespace0Plus()
        match (reader.peek()) {
            case Some(r) where cp(r) == 0x3E =>
                let _ = reader.advance()
                if (openDepth > 0) {
                    openDepth -= 1
                }
                sawNonWhitespace = true
                return Token.ElementClose(startPos, name)
            case Some(r) =>
                throw XmlException(XmlError.UnexpectedChar(
                    reader.currentPosition(), r,
                    "expected '>' to close end tag"
                ))
            case None =>
                throw XmlException(XmlError.UnexpectedEof(
                    reader.currentPosition(), "unterminated end tag"
                ))
        }
    }

    /** `<name` —— 读到名字后进入 open tag 模式。 */
    private func readElementOpen(startPos: Position): Token {
        let name = readName()
        inOpenTag = true
        xmlDeclMode = false
        sawNonWhitespace = true
        return Token.ElementOpenStart(startPos, name)
    }

    /* ---------- 引用 ---------- */

    private func readReference(): Token {
        let startPos = reader.currentPosition()
        // 消费 '&'
        let _ = reader.advance()
        match (reader.peek()) {
            case None =>
                throw XmlException(XmlError.UnexpectedEof(
                    reader.currentPosition(), "unterminated reference after '&'"
                ))
            case Some(r) =>
                if (cp(r) == 0x23 /* '#' */) {
                    let _ = reader.advance()
                    return readCharRef(startPos)
                }
                return readEntityRef(startPos)
        }
    }

    private func readEntityRef(startPos: Position): Token {
        let name = readName()
        if (!reader.consumeIf(Rune(0x3Bu32))) {
            throw XmlException(XmlError.Malformed(
                reader.currentPosition(), "expected ';' at end of entity reference"
            ))
        }
        return Token.EntityRef(startPos, name)
    }

    private func readCharRef(startPos: Position): Token {
        var hex = false
        if (reader.consumeIf(Rune(0x78u32) /* 'x' */)) {
            hex = true
        }
        var value: Int64 = 0
        var seen = false
        while (true) {
            match (reader.peek()) {
                case None => break
                case Some(r) =>
                    let cp = cp(r)
                    let digit: Int64 = if (cp >= 0x30 && cp <= 0x39) {
                        Int64(cp - 0x30)
                    } else if (hex && cp >= 0x41 && cp <= 0x46) {
                        Int64(cp - 0x41) + 10
                    } else if (hex && cp >= 0x61 && cp <= 0x66) {
                        Int64(cp - 0x61) + 10
                    } else {
                        -1
                    }
                    if (digit < 0) {
                        break
                    }
                    seen = true
                    value = value * (if (hex) { 16 } else { 10 }) + digit
                    if (value > 0x10FFFF) {
                        throw XmlException(XmlError.Malformed(
                            reader.currentPosition(), "character reference out of Unicode range"
                        ))
                    }
                    let _ = reader.advance()
            }
        }
        if (!seen) {
            throw XmlException(XmlError.Malformed(
                reader.currentPosition(), "character reference has no digits"
            ))
        }
        if (!reader.consumeIf(Rune(0x3Bu32))) {
            throw XmlException(XmlError.Malformed(
                reader.currentPosition(), "expected ';' at end of character reference"
            ))
        }
        let cp = Int32(value)
        if (!isXmlChar(cp, version: version)) {
            throw XmlException(XmlError.Malformed(
                startPos,
                "character reference refers to character illegal in XML: U+${cp}"
            ))
        }
        return Token.CharRef(startPos, cp)
    }

    /* ---------- Open tag 内部（属性列表 / 结束符） ---------- */

    // 区分普通元素开口 vs XML 声明开口：结束符分别是 `>` / `/>` 与 `?>`。
    private var xmlDeclMode: Bool = false

    private func readInsideOpenTag(): Token {
        skipWhitespace0Plus()
        let pos = reader.currentPosition()
        match (reader.peek()) {
            case None =>
                throw XmlException(XmlError.UnexpectedEof(pos, "unterminated tag"))
            case Some(r) =>
                let c = cp(r)
                if (xmlDeclMode) {
                    if (c == 0x3F /* '?' */ && peekIs2(0x3F, 0x3E)) {
                        let _ = reader.advance()
                        let _ = reader.advance()
                        inOpenTag = false
                        xmlDeclMode = false
                        return Token.XmlDeclEnd(pos)
                    }
                } else {
                    if (c == 0x3E /* '>' */) {
                        let _ = reader.advance()
                        inOpenTag = false
                        openDepth += 1
                        return Token.ElementOpenEnd(pos)
                    }
                    if (c == 0x2F /* '/' */ && peekIs2(0x2F, 0x3E)) {
                        let _ = reader.advance()
                        let _ = reader.advance()
                        inOpenTag = false
                        // 自闭合不增加 openDepth
                        return Token.ElementSelfClose(pos)
                    }
                }
                // 属性名 / 属性等号 / 属性值 状态机
                if (c == 0x3D /* '=' */) {
                    let _ = reader.advance()
                    return Token.AttrEq(pos)
                }
                if (c == 0x22 || c == 0x27) {
                    let q = if (c == 0x22) { AttrQuote.Double } else { AttrQuote.Single }
                    let _ = reader.advance()
                    inAttrValue = Some(q)
                    return Token.AttrValueStart(pos, q)
                }
                // 必须是 Name 起始
                if (isNameStartChar(c)) {
                    let name = readName()
                    return Token.AttrName(pos, name)
                }
                throw XmlException(XmlError.UnexpectedChar(
                    pos, r, "unexpected character inside tag"
                ))
        }
    }

    /* ---------- 属性值内部 ---------- */

    private func readAttrValueFragment(q: AttrQuote): Token {
        let startPos = reader.currentPosition()
        let quoteCp: Int32 = match (q) {
            case Double => 0x22i32
            case Single => 0x27i32
        }
        // 优先处理结束 / 引用
        match (reader.peek()) {
            case None =>
                throw XmlException(XmlError.UnexpectedEof(
                    startPos, "unterminated attribute value"
                ))
            case Some(r) =>
                let c = cp(r)
                if (c == quoteCp) {
                    let _ = reader.advance()
                    inAttrValue = None
                    return Token.AttrValueEnd(startPos, q)
                }
                if (c == 0x26 /* '&' */) {
                    return readReference()
                }
                if (c == 0x3C /* '<' */) {
                    throw XmlException(XmlError.UnexpectedChar(
                        startPos, r, "literal '<' not allowed in attribute value"
                    ))
                }
        }
        // 累积文字块，直到遇到 `&` / `<` / quote / EOF
        let sb = StringBuilder()
        while (true) {
            match (reader.peek()) {
                case None => break
                case Some(r) =>
                    let c = cp(r)
                    if (c == quoteCp || c == 0x26 || c == 0x3C) {
                        break
                    }
                    if (!isXmlChar(c, version: version)) {
                        throw XmlException(XmlError.UnexpectedChar(
                            reader.currentPosition(), r,
                            "invalid XML character in attribute value"
                        ))
                    }
                    // 属性值内换行规则：XML §3.3.3 AttValue normalization 规定把 #x20 / #x9 /
                    // 以及已经归一化为 #xA 的换行都转成 #x20。RuneReader 已把所有换行归一
                    // 到 #xA，此处把 #x9 / #xA 再折叠为空格。
                    if (c == 0x09 || c == 0x0A) {
                        sb.append(Rune(0x20u32))
                    } else {
                        sb.append(r)
                    }
                    let _ = reader.advance()
            }
        }
        return Token.AttrValueChunk(startPos, sb.toString())
    }

    /* ---------- 辅助 ---------- */

    private func readName(): String {
        let sb = StringBuilder()
        match (reader.peek()) {
            case None =>
                throw XmlException(XmlError.UnexpectedEof(
                    reader.currentPosition(), "expected Name"
                ))
            case Some(r) =>
                let c = cp(r)
                if (!isNameStartChar(c)) {
                    throw XmlException(XmlError.UnexpectedChar(
                        reader.currentPosition(), r,
                        "invalid NameStartChar"
                    ))
                }
                sb.append(r)
                let _ = reader.advance()
        }
        while (true) {
            match (reader.peek()) {
                case None => break
                case Some(r) =>
                    let c = cp(r)
                    if (!isNameChar(c)) {
                        break
                    }
                    sb.append(r)
                    let _ = reader.advance()
            }
        }
        return sb.toString()
    }

    private func skipWhitespace0Plus(): Unit {
        while (true) {
            match (reader.peek()) {
                case Some(r) where isXmlWhitespace(cp(r)) =>
                    let _ = reader.advance()
                case _ => return
            }
        }
    }

    private func skipWhitespace1Plus(): Bool {
        var any = false
        while (true) {
            match (reader.peek()) {
                case Some(r) where isXmlWhitespace(cp(r)) =>
                    let _ = reader.advance()
                    any = true
                case _ => return any
            }
        }
        return any
    }

    private func peekIs2(a: Int32, b: Int32): Bool {
        match (reader.peek(k: 0)) {
            case Some(r) where cp(r) == a => ()
            case _ => return false
        }
        match (reader.peek(k: 1)) {
            case Some(r) where cp(r) == b => return true
            case _ => return false
        }
    }

    private func peekIs3(a: Int32, b: Int32, c: Int32): Bool {
        match (reader.peek(k: 0)) {
            case Some(r) where cp(r) == a => ()
            case _ => return false
        }
        match (reader.peek(k: 1)) {
            case Some(r) where cp(r) == b => ()
            case _ => return false
        }
        match (reader.peek(k: 2)) {
            case Some(r) where cp(r) == c => return true
            case _ => return false
        }
    }

    private func cp(r: Rune): Int32 {
        return Int32(UInt32(r))
    }
}
