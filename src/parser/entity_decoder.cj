package fastxml.parser

import fastxml.error.*

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
 * 解码失败统一抛 `XmlParseException(InvalidText(...))`，由上层捕获后按上下文
 * 合成 `InvalidAttribute` 等更细的错误枚举再重新抛出。
 */
const MAX_ENTITY_NAME_LEN: Int64 = 8 // "&quot;" 是最长的命名实体
const MAX_NUMERIC_ENTITY_DIGITS: Int64 = 8 // U+10FFFF 用 6 位十六进制足矣，8 为安全上限

private const ENTITY_AMP: Byte = 0x26u8 // '&'
private const ENTITY_SEMI: Byte = 0x3Bu8 // ';'
private const ENTITY_HASH: Byte = 0x23u8 // '#'

/**
 * 解码含实体的字符串；若无 `&` 则走快路径直接返回原串。
 *
 * 慢路径以字节扫描定位 `&`：XML 实体引用首字符 `&` 与终止符 `;` 都是 ASCII，
 * UTF-8 多字节序列的所有续字节均 ≥ 0x80，按字节扫描结果与按 Rune 扫描完全
 * 一致；以此跳过对整段输入做 Rune 物化。
 */
func decodeEntities(s: String, pos: SourcePos): String {
    let n = s.size
    var firstAmp = -1
    var i = 0
    while (i < n) {
        if (s[i] == ENTITY_AMP) {
            firstAmp = i
            break
        }
        i++
    }
    if (firstAmp < 0) {
        return s
    }
    let out = StringBuilder()
    if (firstAmp > 0) {
        out.append(s[0..firstAmp])
    }
    var cursor = firstAmp
    while (cursor < n) {
        if (s[cursor] == ENTITY_AMP) {
            cursor = decodeOneEntity(s, cursor, out, pos)
        } else {
            // 把直到下一个 `&` 之间的字节段一次性 append。
            var j = cursor + 1
            while (j < n && s[j] != ENTITY_AMP) {
                j++
            }
            out.append(s[cursor..j])
            cursor = j
        }
    }
    out.toString()
}

/**
 * 解析一个以 `&` 开头的实体，返回跨过 `;` 后的新索引。失败抛异常。
 *
 * 实体体（命名实体名 / 数值字符引用）必须全部为 ASCII，可直接按字节比较。
 */
func decodeOneEntity(s: String, start: Int64, out: StringBuilder, pos: SourcePos): Int64 {
    let n = s.size
    let endLimit = min(start + MAX_ENTITY_NAME_LEN + MAX_NUMERIC_ENTITY_DIGITS + 2, n)
    var semicolonIndex = -1
    var scanIndex = start + 1
    while (scanIndex < endLimit) {
        if (s[scanIndex] == ENTITY_SEMI) {
            semicolonIndex = scanIndex
            break
        }
        scanIndex++
    }
    if (semicolonIndex < 0) {
        throw XmlParseException(InvalidText(pos, "unterminated entity reference starting at index ${start}"))
    }
    let bodyStart = start + 1
    if (bodyStart == semicolonIndex) {
        throw XmlParseException(InvalidText(pos, "empty entity reference"))
    }
    if (s[bodyStart] == ENTITY_HASH) {
        appendNumericEntity(s, bodyStart + 1, semicolonIndex, out, pos)
    } else {
        appendNamedEntity(s, bodyStart, semicolonIndex, out, pos)
    }
    semicolonIndex + 1
}

private func appendNamedEntity(s: String, start: Int64, end: Int64, out: StringBuilder, pos: SourcePos): Unit {
    let len = end - start
    if (len == 2 && s[start] == b'l' && s[start + 1] == b't') {
        out.append(r'<')
        return
    }
    if (len == 2 && s[start] == b'g' && s[start + 1] == b't') {
        out.append(r'>')
        return
    }
    if (len == 3 && s[start] == b'a' && s[start + 1] == b'm' && s[start + 2] == b'p') {
        out.append(r'&')
        return
    }
    if (len == 4 && s[start] == b'q' && s[start + 1] == b'u' && s[start + 2] == b'o' && s[start + 3] == b't') {
        out.append(r'"')
        return
    }
    if (len == 4 && s[start] == b'a' && s[start + 1] == b'p' && s[start + 2] == b'o' && s[start + 3] == b's') {
        out.append(r'\'')
        return
    }
    throw XmlParseException(InvalidText(pos, "unknown named entity '&${s[start..end]};'"))
}

private func appendNumericEntity(
    s: String,
    start: Int64,
    end: Int64,
    out: StringBuilder,
    pos: SourcePos
): Unit {
    if (start >= end) {
        throw XmlParseException(InvalidText(pos, "empty numeric entity"))
    }
    var codepoint: Int64 = 0
    if (s[start] == b'x' || s[start] == b'X') {
        codepoint = parseHexDigits(s, start + 1, end, pos)
    } else {
        codepoint = parseDecimalDigits(s, start, end, pos)
    }
    if (!isValidXmlCodepoint(codepoint)) {
        throw XmlParseException(InvalidText(pos, "numeric entity yields invalid codepoint U+${codepoint}"))
    }
    out.append(Rune(UInt32(codepoint)))
}

private func parseHexDigits(s: String, start: Int64, end: Int64, pos: SourcePos): Int64 {
    if (start >= end) {
        throw XmlParseException(InvalidText(pos, "hex entity missing digits"))
    }
    var acc: Int64 = 0
    var i = start
    while (i < end) {
        let v = hexDigitValueByte(s[i])
        if (v < 0) {
            throw XmlParseException(InvalidText(pos, "non-hex character in numeric entity"))
        }
        acc = acc * 16 + v
        i++
    }
    acc
}

private func parseDecimalDigits(s: String, start: Int64, end: Int64, pos: SourcePos): Int64 {
    if (start >= end) {
        throw XmlParseException(InvalidText(pos, "decimal entity missing digits"))
    }
    var acc: Int64 = 0
    var i = start
    while (i < end) {
        let bv = s[i]
        if (bv < b'0' || bv > b'9') {
            throw XmlParseException(InvalidText(pos, "non-digit character in numeric entity"))
        }
        acc = acc * 10 + Int64(bv - b'0')
        i++
    }
    acc
}

private func hexDigitValueByte(bv: Byte): Int64 {
    if (bv >= b'0' && bv <= b'9') {
        return Int64(bv - b'0')
    }
    if (bv >= b'a' && bv <= b'f') {
        return Int64(bv - b'a') + 10
    }
    if (bv >= b'A' && bv <= b'F') {
        return Int64(bv - b'A') + 10
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
