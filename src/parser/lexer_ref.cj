/*
 * parser — Lexer 实体引用与字符引用
 *
 * 拆自原 `lexer.cj` 的 `readReference` / `readEntityRef` / `readCharRef`。
 */
package cangjie_xml.parser

import cangjie_xml.core.*

extend Lexer {
    func readReference(): Token {
        let startPos = reader.currentPosition()
        let _ = reader.advance() // 消费 '&'
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

    func readEntityRef(startPos: Position): Token {
        let name = readName()
        if (!reader.consumeIf(Rune(0x3Bu32))) {
            throw XmlException(XmlError.Malformed(
                reader.currentPosition(), "expected ';' at end of entity reference"
            ))
        }
        return Token.EntityRef(startPos, name)
    }

    func readCharRef(startPos: Position): Token {
        let hex = reader.consumeIf(Rune(0x78u32) /* 'x' */)
        let value = collectCharRefDigits(hex)
        if (!reader.consumeIf(Rune(0x3Bu32))) {
            throw XmlException(XmlError.Malformed(
                reader.currentPosition(), "expected ';' at end of character reference"
            ))
        }
        let cp = Int32(value)
        if (!isXmlChar(cp, version: version)) {
            throw XmlException(XmlError.Malformed(
                startPos, "character reference refers to character illegal in XML: U+${cp}"
            ))
        }
        return Token.CharRef(startPos, cp)
    }

    private func collectCharRefDigits(hex: Bool): Int64 {
        var value: Int64 = 0
        var seen = false
        let base: Int64 = if (hex) { 16 } else { 10 }
        while (true) {
            match (reader.peek()) {
                case None => break
                case Some(r) =>
                    let digit = charRefDigit(cp(r), hex)
                    if (digit < 0) {
                        break
                    }
                    seen = true
                    value = value * base + digit
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
        return value
    }

    /** 将一个字符码解析为 `0..9 | 10..15` 的数位值，非数字返回 -1。 */
    private static func charRefDigit(c: Int32, hex: Bool): Int64 {
        if (c >= 0x30 && c <= 0x39) {
            return Int64(c - 0x30)
        }
        if (!hex) {
            return -1
        }
        if (c >= 0x41 && c <= 0x46) {
            return Int64(c - 0x41) + 10
        }
        if (c >= 0x61 && c <= 0x66) {
            return Int64(c - 0x61) + 10
        }
        return -1
    }
}
