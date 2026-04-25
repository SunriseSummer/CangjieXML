package cangjie_xml.parser

import cangjie_xml.error.*

/**
 * XML 实体解码器。
 *
 * 支持的实体——与 XML 1.0 预定义实体 + 数值字符引用一致：
 *
 * - `&amp;` → `&`
 * - `&lt;`  → `<`
 * - `&gt;`  → `>`
 * - `&quot;`→ `"`
 * - `&apos;`→ `'`
 * - `&#N;`  → 码点 N（十进制）
 * - `&#xH;` → 码点 H（十六进制）
 *
 * 不支持 DTD 自定义实体（与 tinyxml2 对齐）。
 *
 * 解码失败统一抛 `XmlParseException(InvalidText(...))`，由上层捕获合成更细的错误枚举
 * （例如 `InvalidAttribute`）后再重新抛出，避免此处判断上下文带来的圈复杂度膨胀。
 */
const MAX_ENTITY_NAME_LEN: Int64 = 8 // "&quot;" 是最长的命名实体
const MAX_NUMERIC_ENTITY_DIGITS: Int64 = 8 // U+10FFFF 用 6 位十六进制足矣，8 为安全上限

/** 解码含实体的字符串；若无 `&` 则走快路径直接返回原串。 */
func decodeEntities(s: String, pos: SourcePos): String {
    if (!s.contains("&")) {
        return s
    }
    let runes = toRuneArray(s)
    let out = StringBuilder()
    var i = 0
    while (i < runes.size) {
        if (runes[i] == r'&') {
            i = decodeOneEntity(runes, i, out, pos)
        } else {
            out.append(runes[i])
            i++
        }
    }
    out.toString()
}

/** 解析一个以 `&` 开头的实体，返回跨过 `;` 后的新索引。失败抛异常。 */
func decodeOneEntity(runes: Array<Rune>, start: Int64, out: StringBuilder, pos: SourcePos): Int64 {
    // 寻找 ';'——限定搜索窗口避免扫到文档末尾
    let endLimit = min(start + MAX_ENTITY_NAME_LEN + MAX_NUMERIC_ENTITY_DIGITS + 2, runes.size)
    var semi = -1
    var j = start + 1
    while (j < endLimit) {
        if (runes[j] == r';') {
            semi = j
            break
        }
        j++
    }
    if (semi < 0) {
        throw XmlParseException(InvalidText(pos, "unterminated entity reference starting at index ${start}"))
    }
    let bodyStart = start + 1
    if (bodyStart == semi) {
        throw XmlParseException(InvalidText(pos, "empty entity reference"))
    }
    if (runes[bodyStart] == r'#') {
        appendNumericEntity(runes, bodyStart + 1, semi, out, pos)
    } else {
        appendNamedEntity(runes, bodyStart, semi, out, pos)
    }
    semi + 1
}

private func appendNamedEntity(runes: Array<Rune>, start: Int64, end: Int64, out: StringBuilder, pos: SourcePos): Unit {
    let len = end - start
    if (len == 2 && runes[start] == r'l' && runes[start + 1] == r't') {
        out.append(r'<')
        return
    }
    if (len == 2 && runes[start] == r'g' && runes[start + 1] == r't') {
        out.append(r'>')
        return
    }
    if (len == 3 && runes[start] == r'a' && runes[start + 1] == r'm' && runes[start + 2] == r'p') {
        out.append(r'&')
        return
    }
    if (len == 4 && runes[start] == r'q' && runes[start + 1] == r'u' && runes[start + 2] == r'o' && runes[start + 3] ==
        r't') {
        out.append(r'"')
        return
    }
    if (len == 4 && runes[start] == r'a' && runes[start + 1] == r'p' && runes[start + 2] == r'o' && runes[start + 3] ==
        r's') {
        out.append(r'\'')
        return
    }
    throw XmlParseException(InvalidText(pos, "unknown named entity '&${String(runes[start..end])};'"))
}

private func appendNumericEntity(
    runes: Array<Rune>,
    start: Int64,
    end: Int64,
    out: StringBuilder,
    pos: SourcePos
): Unit {
    if (start >= end) {
        throw XmlParseException(InvalidText(pos, "empty numeric entity"))
    }
    var codepoint: Int64 = 0
    if (runes[start] == r'x' || runes[start] == r'X') {
        codepoint = parseHexDigits(runes, start + 1, end, pos)
    } else {
        codepoint = parseDecimalDigits(runes, start, end, pos)
    }
    if (!isValidXmlCodepoint(codepoint)) {
        throw XmlParseException(InvalidText(pos, "numeric entity yields invalid codepoint U+${codepoint}"))
    }
    out.append(Rune(UInt32(codepoint)))
}

private func parseHexDigits(runes: Array<Rune>, start: Int64, end: Int64, pos: SourcePos): Int64 {
    if (start >= end) {
        throw XmlParseException(InvalidText(pos, "hex entity missing digits"))
    }
    var acc: Int64 = 0
    var i = start
    while (i < end) {
        let v = hexDigitValue(runes[i])
        if (v < 0) {
            throw XmlParseException(InvalidText(pos, "non-hex character in numeric entity"))
        }
        acc = acc * 16 + v
        i++
    }
    acc
}

private func parseDecimalDigits(runes: Array<Rune>, start: Int64, end: Int64, pos: SourcePos): Int64 {
    if (start >= end) {
        throw XmlParseException(InvalidText(pos, "decimal entity missing digits"))
    }
    var acc: Int64 = 0
    var i = start
    while (i < end) {
        let r = runes[i]
        if (!isAsciiDigit(r)) {
            throw XmlParseException(InvalidText(pos, "non-digit character in numeric entity"))
        }
        acc = acc * 10 + (Int64(UInt32(r)) - Int64(UInt32(r'0')))
        i++
    }
    acc
}

private func hexDigitValue(r: Rune): Int64 {
    if (r >= r'0' && r <= r'9') {
        return Int64(UInt32(r)) - Int64(UInt32(r'0'))
    }
    if (r >= r'a' && r <= r'f') {
        return Int64(UInt32(r)) - Int64(UInt32(r'a')) + 10
    }
    if (r >= r'A' && r <= r'F') {
        return Int64(UInt32(r)) - Int64(UInt32(r'A')) + 10
    }
    -1
}

private func isValidXmlCodepoint(cp: Int64): Bool {
    // XML 1.0 §2.2 Char：0x9 | 0xA | 0xD | [0x20-0xD7FF] | [0xE000-0xFFFD] | [0x10000-0x10FFFF]
    cp == 0x9 || cp == 0xA || cp == 0xD || (cp >= 0x20 && cp <= 0xD7FF) || (cp >= 0xE000 && cp <= 0xFFFD) || (cp >=
        0x10000 && cp <= 0x10FFFF)
}

private func min(a: Int64, b: Int64): Int64 {
    if (a < b) {
        a
    } else {
        b
    }
}
