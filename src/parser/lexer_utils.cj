/*
 * parser — Lexer 通用辅助：Name / 空白 / peek-N / 字符分类
 *
 * 拆自原 `lexer.cj` 的 `readName` / `skipWhitespace*` / `peekIs2` / `peekIs3` / `cp`。
 * 新增：
 *   - `requirePeek` — 峰值或 EOF 抛异常，避免在多个 `readBody*` 中重复 `case None =>`。
 *   - `ensureXmlChar` — 统一的 XML 字符合法性检查 + 出错抛异常。
 */
package cangjie_xml.parser

import cangjie_xml.core.*

extend Lexer {
    func readName(): String {
        let sb = StringBuilder()
        readNameStartChar(sb)
        readNameRest(sb)
        return sb.toString()
    }

    private func readNameStartChar(sb: StringBuilder): Unit {
        match (reader.peek()) {
            case None =>
                throw XmlException(XmlError.UnexpectedEof(
                    reader.currentPosition(), "expected Name"
                ))
            case Some(r) =>
                if (!isNameStartChar(cp(r))) {
                    throw XmlException(XmlError.UnexpectedChar(
                        reader.currentPosition(), r, "invalid NameStartChar"
                    ))
                }
                sb.append(r)
                let _ = reader.advance()
        }
    }

    private func readNameRest(sb: StringBuilder): Unit {
        while (true) {
            match (reader.peek()) {
                case None => return
                case Some(r) =>
                    if (!isNameChar(cp(r))) {
                        return
                    }
                    sb.append(r)
                    let _ = reader.advance()
            }
        }
    }

    func skipWhitespace0Plus(): Unit {
        while (true) {
            match (reader.peek()) {
                case Some(r) where isXmlWhitespace(cp(r)) =>
                    let _ = reader.advance()
                case _ => return
            }
        }
    }

    func skipWhitespace1Plus(): Bool {
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

    /** 峰值当前字符，若 EOF 则抛带 `msg` 的异常。 */
    func requirePeek(msg: String): Rune {
        match (reader.peek()) {
            case Some(r) => return r
            case None =>
                throw XmlException(XmlError.UnexpectedEof(reader.currentPosition(), msg))
        }
    }

    /** XML 字符合法性兜底校验，非法则抛 `UnexpectedChar`。 */
    func ensureXmlChar(c: Int32, r: Rune, msg: String): Unit {
        if (!isXmlChar(c, version: version)) {
            throw XmlException(XmlError.UnexpectedChar(reader.currentPosition(), r, msg))
        }
    }

    func peekIs2(a: Int32, b: Int32): Bool {
        return matchPeekCp(0, a) && matchPeekCp(1, b)
    }

    func peekIs3(a: Int32, b: Int32, c: Int32): Bool {
        return matchPeekCp(0, a) && matchPeekCp(1, b) && matchPeekCp(2, c)
    }

    private func matchPeekCp(k: Int64, expect: Int32): Bool {
        match (reader.peek(k: k)) {
            case Some(r) where cp(r) == expect => return true
            case _ => return false
        }
    }

    func cp(r: Rune): Int32 {
        return Int32(UInt32(r))
    }
}
