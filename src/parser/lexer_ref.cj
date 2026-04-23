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
                if (cp(r) == CHAR_HASH) {
                    let _ = reader.advance()
                    return readCharRef(startPos)
                }
                return readEntityRef(startPos)
        }
    }

    func readEntityRef(startPos: Position): Token {
        let name = readName()
        if (!reader.consumeIf(Rune(UInt32(CHAR_SEMI)))) {
            throw XmlException(XmlError.Malformed(
                reader.currentPosition(), "expected ';' at end of entity reference"
            ))
        }
        return Token.EntityRef(startPos, name)
    }

    func readCharRef(startPos: Position): Token {
        let hex = reader.consumeIf(Rune(UInt32(CHAR_LOWER_X)))
        let value = collectCharRefDigits(hex)
        if (!reader.consumeIf(Rune(UInt32(CHAR_SEMI)))) {
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
        let base: Int64 = if (hex) { HEX_BASE } else { DEC_BASE }
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
                    if (value > UNICODE_MAX_CODEPOINT) {
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
        if (c >= CHAR_DIGIT_0 && c <= CHAR_DIGIT_9) {
            return Int64(c - CHAR_DIGIT_0)
        }
        if (!hex) {
            return -1
        }
        if (c >= CHAR_UPPER_A && c <= CHAR_UPPER_F) {
            return Int64(c - CHAR_UPPER_A) + HEX_DIGIT_OFFSET
        }
        if (c >= CHAR_LOWER_A && c <= CHAR_LOWER_F) {
            return Int64(c - CHAR_LOWER_A) + HEX_DIGIT_OFFSET
        }
        return -1
    }
}
