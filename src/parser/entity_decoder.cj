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
private const ENTITY_HEX_PREFIX_LOWER: Byte = b'x'
private const ENTITY_HEX_PREFIX_UPPER: Byte = b'X'
private const ENTITY_NAME_LT: String = "lt"
private const ENTITY_NAME_GT: String = "gt"
private const ENTITY_NAME_AMP: String = "amp"
private const ENTITY_NAME_QUOT: String = "quot"
private const ENTITY_NAME_APOS: String = "apos"
private const HEX_RADIX: Int64 = 16
private const DECIMAL_RADIX: Int64 = 10
private const HEX_ALPHA_OFFSET: Int64 = 10
private const XML_CHAR_TAB: Int64 = 0x9
private const XML_CHAR_LF: Int64 = 0xA
private const XML_CHAR_CR: Int64 = 0xD
private const XML_CHAR_VISIBLE_MIN: Int64 = 0x20
private const XML_CHAR_SURROGATE_RANGE_START: Int64 = 0xD800
private const XML_CHAR_SURROGATE_RANGE_END: Int64 = 0xDFFF
private const XML_CHAR_BMP_MAX: Int64 = 0xFFFD
private const XML_CHAR_SUPPLEMENTARY_MIN: Int64 = 0x10000
private const XML_CHAR_MAX: Int64 = 0x10FFFF

/**
 * 解码含实体的字符串；若无 `&` 则走快路径直接返回原串。
 *
 * 慢路径以字节扫描定位 `&`：XML 实体引用首字符 `&` 与终止符 `;` 都是 ASCII，
 * UTF-8 多字节序列的所有续字节均 ≥ 0x80，按字节扫描结果与按 Rune 扫描完全
 * 一致；以此跳过对整段输入做 Rune 物化。
 */
func decodeEntities(s: String, pos: SourcePos): String {
    let inputLength = s.size
    var firstAmp = -1
    var byteIndex = 0
    while (byteIndex < inputLength) {
        if (s[byteIndex] == ENTITY_AMP) {
            firstAmp = byteIndex
            break
        }
        byteIndex++
    }
    if (firstAmp < 0) {
        return s
    }
    let output = StringBuilder()
    if (firstAmp > 0) {
        output.append(s[0..firstAmp])
    }
    var cursor = firstAmp
    while (cursor < inputLength) {
        if (s[cursor] == ENTITY_AMP) {
            cursor = decodeOneEntity(s, cursor, output, pos)
        } else {
            // 把直到下一个 `&` 之间的字节段一次性 append。
            var nextAmpIndex = cursor + 1
            while (nextAmpIndex < inputLength && s[nextAmpIndex] != ENTITY_AMP) {
                nextAmpIndex++
            }
            output.append(s[cursor..nextAmpIndex])
            cursor = nextAmpIndex
        }
    }
    output.toString()
}

/**
 * 解析一个以 `&` 开头的实体，返回跨过 `;` 后的新索引。失败抛异常。
 *
 * 实体体（命名实体名 / 数值字符引用）必须全部为 ASCII，可直接按字节比较。
 */
func decodeOneEntity(s: String, start: Int64, out: StringBuilder, pos: SourcePos): Int64 {
    let inputLength = s.size
    let endLimit = min(start + MAX_ENTITY_NAME_LEN + MAX_NUMERIC_ENTITY_DIGITS + 2, inputLength)
    var semi = -1
    var scanIndex = start + 1
    while (scanIndex < endLimit) {
        if (s[scanIndex] == ENTITY_SEMI) {
            semi = scanIndex
            break
        }
        scanIndex++
    }
    if (semi < 0) {
        throw XmlParseException(InvalidText(pos, "unterminated entity reference starting at index ${start}"))
    }
    let bodyStart = start + 1
    if (bodyStart == semi) {
        throw XmlParseException(InvalidText(pos, "empty entity reference"))
    }
    if (s[bodyStart] == ENTITY_HASH) {
        appendNumericEntity(s, bodyStart + 1, semi, out, pos)
    } else {
        appendNamedEntity(s, bodyStart, semi, out, pos)
    }
    semi + 1
}

private func appendNamedEntity(s: String, start: Int64, end: Int64, out: StringBuilder, pos: SourcePos): Unit {
    let entityName = s[start..end]
    if (entityName == ENTITY_NAME_LT) {
        out.append(r'<')
        return
    }
    if (entityName == ENTITY_NAME_GT) {
        out.append(r'>')
        return
    }
    if (entityName == ENTITY_NAME_AMP) {
        out.append(r'&')
        return
    }
    if (entityName == ENTITY_NAME_QUOT) {
        out.append(r'"')
        return
    }
    if (entityName == ENTITY_NAME_APOS) {
        out.append(r'\'')
        return
    }
    throw XmlParseException(InvalidText(pos, "unknown named entity '&${entityName};'"))
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
    if (s[start] == ENTITY_HEX_PREFIX_LOWER || s[start] == ENTITY_HEX_PREFIX_UPPER) {
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
    var digitIndex = start
    while (digitIndex < end) {
        let digitValue = hexDigitValueByte(s[digitIndex])
        if (digitValue < 0) {
            throw XmlParseException(InvalidText(pos, "non-hex character in numeric entity"))
        }
        acc = acc * HEX_RADIX + digitValue
        digitIndex++
    }
    acc
}

private func parseDecimalDigits(s: String, start: Int64, end: Int64, pos: SourcePos): Int64 {
    if (start >= end) {
        throw XmlParseException(InvalidText(pos, "decimal entity missing digits"))
    }
    var acc: Int64 = 0
    var digitIndex = start
    while (digitIndex < end) {
        let currentByte = s[digitIndex]
        if (currentByte < b'0' || currentByte > b'9') {
            throw XmlParseException(InvalidText(pos, "non-digit character in numeric entity"))
        }
        acc = acc * DECIMAL_RADIX + Int64(currentByte - b'0')
        digitIndex++
    }
    acc
}

private func hexDigitValueByte(bv: Byte): Int64 {
    if (bv >= b'0' && bv <= b'9') {
        return Int64(bv - b'0')
    }
    if (bv >= b'a' && bv <= b'f') {
        return Int64(bv - b'a') + HEX_ALPHA_OFFSET
    }
    if (bv >= b'A' && bv <= b'F') {
        return Int64(bv - b'A') + HEX_ALPHA_OFFSET
    }
    -1
}

private func isValidXmlCodepoint(cp: Int64): Bool {
    // XML 1.0 §2.2 Char：0x9 | 0xA | 0xD | [0x20-0xD7FF] | [0xE000-0xFFFD] | [0x10000-0x10FFFF]
    cp == XML_CHAR_TAB || cp == XML_CHAR_LF || cp == XML_CHAR_CR
        || (cp >= XML_CHAR_VISIBLE_MIN && cp < XML_CHAR_SURROGATE_RANGE_START)
        || (cp > XML_CHAR_SURROGATE_RANGE_END && cp <= XML_CHAR_BMP_MAX)
        || (cp >= XML_CHAR_SUPPLEMENTARY_MIN && cp <= XML_CHAR_MAX)
}

private func min(a: Int64, b: Int64): Int64 {
    if (a < b) {
        a
    } else {
        b
    }
}
