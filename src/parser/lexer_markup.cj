/*
 * parser — Lexer `<!...` 与 `<?...?>` 构造的词法读取
 *
 * 拆自原 `lexer.cj` 的 `readBangConstruct` / `readCommentBody` / `readCDataBody` /
 * `readDoctypeHead` / `scanThroughDoctypeTail` / `readPiOrXmlDecl`。
 */
package cangjie_xml.parser

import cangjie_xml.core.*

extend Lexer {
    /** 解析 `<!...`：可能是 `<!--` / `<![CDATA[` / `<!DOCTYPE`。 */
    func readBangConstruct(startPos: Position): Token {
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
            reader.currentPosition(), "expected '<!--', '<![CDATA[' or '<!DOCTYPE'"
        ))
    }

    /* ---------- Comment ---------- */

    func readCommentBody(startPos: Position): Token {
        let sb = StringBuilder()
        while (true) {
            let r = requirePeek("unterminated comment")
            let c = cp(r)
            if (c == 0x2D /* '-' */ && peekIs2(0x2D, 0x2D)) {
                return finishComment(startPos, sb)
            }
            ensureXmlChar(c, r, "invalid XML character in comment")
            sb.append(r)
            let _ = reader.advance()
        }
        return Token.Comment(startPos, sb.toString())
    }

    private func finishComment(startPos: Position, sb: StringBuilder): Token {
        let dashPos = reader.currentPosition()
        let _ = reader.advance() // 消费第一个 '-'
        let _ = reader.advance() // 消费第二个 '-'
        if (!reader.consumeIf(Rune(0x3Eu32))) {
            throw XmlException(XmlError.Malformed(dashPos, "'--' is not allowed inside comment"))
        }
        return Token.Comment(startPos, sb.toString())
    }

    /* ---------- CDATA ---------- */

    func readCDataBody(startPos: Position): Token {
        let sb = StringBuilder()
        while (true) {
            let r = requirePeek("unterminated CDATA section")
            let c = cp(r)
            if (c == 0x5D /* ']' */ && peekIs3(0x5D, 0x5D, 0x3E)) {
                let _ = reader.advance()
                let _ = reader.advance()
                let _ = reader.advance()
                return Token.CDataSection(startPos, sb.toString())
            }
            ensureXmlChar(c, r, "invalid XML character in CDATA section")
            sb.append(r)
            let _ = reader.advance()
        }
        return Token.CDataSection(startPos, sb.toString())
    }

    /* ---------- DOCTYPE ---------- */

    func readDoctypeHead(startPos: Position): Token {
        if (!skipWhitespace1Plus()) {
            throw XmlException(XmlError.Malformed(
                reader.currentPosition(), "expected whitespace after <!DOCTYPE"
            ))
        }
        let name = readName()
        // 本词法器粗略跳过 DOCTYPE 剩余部分（不解析 DTD 内部子集），只确保 Lexer 不会把
        // DOCTYPE 内部的 '<' / '&' 误当作元素/实体。
        scanThroughDoctypeTail()
        return Token.DoctypeStart(startPos, name)
    }

    private func scanThroughDoctypeTail(): Unit {
        var insideBrackets = false
        while (true) {
            let r = requirePeek("unterminated DOCTYPE")
            let c = cp(r)
            if (!insideBrackets && c == 0x3E /* '>' */) {
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
            if (c == 0x22 || c == 0x27) {
                skipQuotedStringInDoctype(c)
                continue
            }
            ensureXmlChar(c, r, "invalid XML character in DOCTYPE")
            let _ = reader.advance()
        }
    }

    private func skipQuotedStringInDoctype(qChar: Int32): Unit {
        let _ = reader.advance() // 消费开头引号
        while (true) {
            let q = requirePeek("unterminated quoted string in DOCTYPE")
            let qcp = cp(q)
            let _ = reader.advance()
            if (qcp == qChar) {
                return
            }
        }
    }

    /* ---------- PI / XmlDecl ---------- */

    /** `<?target data?>` 或 `<?xml ...?>`（XML 声明）。 */
    func readPiOrXmlDecl(startPos: Position): Token {
        let _ = reader.advance() // 消费 '?'
        let target = readName()
        if (isXmlTargetName(target)) {
            return enterXmlDeclMode(startPos, target)
        }
        return readPiBody(startPos, target)
    }

    private static func isXmlTargetName(target: String): Bool {
        return target.toAsciiLower() == "xml"
    }

    private func enterXmlDeclMode(startPos: Position, target: String): Token {
        // XML 声明必须使用小写 "xml"；任何大小写变体作为 PI target 都非法
        if (target != "xml") {
            throw XmlException(XmlError.Malformed(
                startPos, "processing instruction target must not be 'xml' / 'XML' / any case variant"
            ))
        }
        if (sawXmlDecl || sawNonWhitespace || openDepth > 0) {
            throw XmlException(XmlError.Malformed(
                startPos, "XML declaration must appear at the very start of the document"
            ))
        }
        sawXmlDecl = true
        inOpenTag = true
        xmlDeclMode = true
        return Token.XmlDeclStart(startPos)
    }

    private func readPiBody(startPos: Position, target: String): Token {
        skipWhitespace0Plus()
        let data = StringBuilder()
        while (true) {
            let r = requirePeek("unterminated processing instruction")
            let c = cp(r)
            if (c == 0x3F /* '?' */ && peekIs2(0x3F, 0x3E)) {
                let _ = reader.advance()
                let _ = reader.advance()
                return Token.ProcessingInstruction(startPos, target, data.toString())
            }
            ensureXmlChar(c, r, "invalid XML character in processing instruction")
            data.append(r)
            let _ = reader.advance()
        }
        return Token.ProcessingInstruction(startPos, target, data.toString())
    }
}
