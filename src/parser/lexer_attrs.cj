/*
 * parser — Lexer 开口标签内部（属性列表 / 属性值片段）
 *
 * 拆自原 `lexer.cj` 的 `readInsideOpenTag` / `readAttrValueFragment`。
 */
package cangjie_xml.parser

import cangjie_xml.core.*

extend Lexer {
    /* ---------- open tag 内部 ---------- */

    func readInsideOpenTag(): Token {
        skipWhitespace0Plus()
        let pos = reader.currentPosition()
        let r = match (reader.peek()) {
            case None => throw XmlException(XmlError.UnexpectedEof(pos, "unterminated tag"))
            case Some(x) => x
        }
        let c = cp(r)
        // 优先处理 tag 结束符
        let closer = tryCloseOpenTag(c, pos)
        match (closer) {
            case Some(t) => return t
            case None => ()
        }
        // 属性 `=` / 引号起始 / 属性名
        return readAttrOrPunct(c, r, pos)
    }

    private func tryCloseOpenTag(c: Int32, pos: Position): ?Token {
        if (xmlDeclMode) {
            if (c == 0x3F /* '?' */ && peekIs2(0x3F, 0x3E)) {
                let _ = reader.advance()
                let _ = reader.advance()
                inOpenTag = false
                xmlDeclMode = false
                return Some(Token.XmlDeclEnd(pos))
            }
            return None
        }
        if (c == 0x3E /* '>' */) {
            let _ = reader.advance()
            inOpenTag = false
            openDepth += 1
            return Some(Token.ElementOpenEnd(pos))
        }
        if (c == 0x2F /* '/' */ && peekIs2(0x2F, 0x3E)) {
            let _ = reader.advance()
            let _ = reader.advance()
            inOpenTag = false
            return Some(Token.ElementSelfClose(pos))
        }
        return None
    }

    private func readAttrOrPunct(c: Int32, r: Rune, pos: Position): Token {
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
        if (isNameStartChar(c)) {
            return Token.AttrName(pos, readName())
        }
        throw XmlException(XmlError.UnexpectedChar(
            pos, r, "unexpected character inside tag"
        ))
    }

    /* ---------- 属性值内部 ---------- */

    func readAttrValueFragment(q: AttrQuote): Token {
        let startPos = reader.currentPosition()
        let quoteCp: Int32 = match (q) {
            case Double => 0x22i32
            case Single => 0x27i32
        }
        // 优先处理结束 / 引用 / 非法 '<'
        let leading = handleAttrValueLeading(q, quoteCp, startPos)
        match (leading) {
            case Some(t) => return t
            case None => ()
        }
        // 累积文字块
        return collectAttrValueChunk(startPos, quoteCp)
    }

    private func handleAttrValueLeading(q: AttrQuote, quoteCp: Int32, startPos: Position): ?Token {
        let r = match (reader.peek()) {
            case None =>
                throw XmlException(XmlError.UnexpectedEof(startPos, "unterminated attribute value"))
            case Some(x) => x
        }
        let c = cp(r)
        if (c == quoteCp) {
            let _ = reader.advance()
            inAttrValue = None
            return Some(Token.AttrValueEnd(startPos, q))
        }
        if (c == 0x26 /* '&' */) {
            return Some(readReference())
        }
        if (c == 0x3C /* '<' */) {
            throw XmlException(XmlError.UnexpectedChar(
                startPos, r, "literal '<' not allowed in attribute value"
            ))
        }
        return None
    }

    private func collectAttrValueChunk(startPos: Position, quoteCp: Int32): Token {
        let sb = StringBuilder()
        while (true) {
            match (reader.peek()) {
                case None => break
                case Some(r) =>
                    let c = cp(r)
                    if (c == quoteCp || c == 0x26 || c == 0x3C) {
                        break
                    }
                    appendAttrValueRune(sb, r, c)
                    let _ = reader.advance()
            }
        }
        return Token.AttrValueChunk(startPos, sb.toString())
    }

    private func appendAttrValueRune(sb: StringBuilder, r: Rune, c: Int32): Unit {
        if (!isXmlChar(c, version: version)) {
            throw XmlException(XmlError.UnexpectedChar(
                reader.currentPosition(), r, "invalid XML character in attribute value"
            ))
        }
        // XML §3.3.3 AttValue normalization：RuneReader 已把换行归一到 #xA，
        // 此处把 #x9 / #xA 再折叠为空格。
        if (c == 0x09 || c == 0x0A) {
            sb.append(Rune(0x20u32))
        } else {
            sb.append(r)
        }
    }
}
