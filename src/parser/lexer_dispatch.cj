/*
 * parser — Lexer 主状态分派 + 文本 / 标签入口
 *
 * 拆自原 `lexer.cj` 的 `readNext` / `readContent` / `readText` / `readTagLike` /
 * `readElementOpen` / `readElementClose`。
 */
package cangjie_xml.parser

import cangjie_xml.core.*

extend Lexer {
    /* ---------- 主状态分派 ---------- */

    func readNext(): Token {
        // 1) 属性值内：走属性值片段路径
        match (inAttrValue) {
            case Some(q) => return readAttrValueFragment(q)
            case None => ()
        }
        // 2) open tag 内：走属性分派路径
        if (inOpenTag) {
            return readInsideOpenTag()
        }
        // 3) 顶层 / 元素内容路径
        return readContent()
    }

    /* ---------- 内容路径 ---------- */

    func readContent(): Token {
        let pos = reader.currentPosition()
        match (reader.peek()) {
            case None => return Token.Eof(pos)
            case Some(r) =>
                let c = cp(r)
                if (c == 0x3C /* '<' */) {
                    return readTagLike()
                }
                if (c == 0x26 /* '&' */) {
                    return readReference()
                }
                return readText()
        }
    }

    func readText(): Token {
        let startPos = reader.currentPosition()
        let sb = StringBuilder()
        while (true) {
            match (reader.peek()) {
                case None => break
                case Some(r) =>
                    if (!appendTextRuneOrStop(sb, r)) {
                        break
                    }
            }
        }
        return Token.Text(startPos, sb.toString())
    }

    /** 返回 false 表示遇到 text 的分隔符，循环应停止；true 表示该字符已被消费并加入 sb。 */
    private func appendTextRuneOrStop(sb: StringBuilder, r: Rune): Bool {
        let c = cp(r)
        if (c == 0x3C || c == 0x26) {
            return false
        }
        // "]]>" 不允许出现在文本中（W3C XML §2.4）。
        if (c == 0x5D /* ']' */ && peekIs3(0x5D, 0x5D, 0x3E)) {
            throw XmlException(XmlError.Malformed(
                reader.currentPosition(),
                "literal ']]>' must not appear in character data"
            ))
        }
        if (!isXmlChar(c, version: version)) {
            throw XmlException(XmlError.UnexpectedChar(
                reader.currentPosition(), r,
                "invalid XML character (code point ${c})"
            ))
        }
        sb.append(r)
        let _ = reader.advance()
        if (!isXmlWhitespace(c)) {
            sawNonWhitespace = true
        }
        return true
    }

    /* ---------- 标签类：以 `<` 开头 ---------- */

    func readTagLike(): Token {
        let startPos = reader.currentPosition()
        let _ = reader.advance() // 消费 '<'
        match (reader.peek()) {
            case None =>
                throw XmlException(XmlError.UnexpectedEof(
                    reader.currentPosition(), "input ended after '<'"
                ))
            case Some(next) =>
                let c = cp(next)
                if (c == 0x21 /* '!' */) {
                    return readBangConstruct(startPos)
                }
                if (c == 0x3F /* '?' */) {
                    return readPiOrXmlDecl(startPos)
                }
                if (c == 0x2F /* '/' */) {
                    return readElementClose(startPos)
                }
                return readElementOpen(startPos)
        }
    }

    /** `</name S? >` */
    func readElementClose(startPos: Position): Token {
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
                    reader.currentPosition(), r, "expected '>' to close end tag"
                ))
            case None =>
                throw XmlException(XmlError.UnexpectedEof(
                    reader.currentPosition(), "unterminated end tag"
                ))
        }
    }

    /** `<name` —— 读到名字后进入 open tag 模式。 */
    func readElementOpen(startPos: Position): Token {
        let name = readName()
        inOpenTag = true
        xmlDeclMode = false
        sawNonWhitespace = true
        return Token.ElementOpenStart(startPos, name)
    }
}
