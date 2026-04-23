/*
 * core — 字符类（XML 1.0 / XML 1.1）
 *
 * 对应 libxml2: chvalid.c
 *
 * 根据 https://www.w3.org/TR/xml/ 与 https://www.w3.org/TR/xml11/ 规范，
 * 提供 XML 字符判定与名字字符判定。全部基于不可变 Unicode 码点区间表 +
 * 二分查找实现，无运行时分配。
 */
package cangjie_xml.core

/** XML 版本。1.0 与 1.1 的字符合法域不同。 */
public enum XmlVersion {
    | V10
    | V11
}

/* ---------- 码点区间表 ---------- */

// XML 1.0 合法字符：#x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]
let XML10_CHAR_RANGES: Array<(Int32, Int32)> = [
    (0x9, 0x9),
    (0xA, 0xA),
    (0xD, 0xD),
    (0x20, 0xD7FF),
    (0xE000, 0xFFFD),
    (0x10000, 0x10FFFF)
]

// XML 1.1 合法字符：[#x1-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]
let XML11_CHAR_RANGES: Array<(Int32, Int32)> = [
    (0x1, 0xD7FF),
    (0xE000, 0xFFFD),
    (0x10000, 0x10FFFF)
]

// NameStartChar（W3C XML 1.0 第 4e 产生式）。
let NAME_START_RANGES: Array<(Int32, Int32)> = [
    (0x3A, 0x3A), // ':'
    (0x41, 0x5A), // A-Z
    (0x5F, 0x5F), // '_'
    (0x61, 0x7A), // a-z
    (0xC0, 0xD6),
    (0xD8, 0xF6),
    (0xF8, 0x2FF),
    (0x370, 0x37D),
    (0x37F, 0x1FFF),
    (0x200C, 0x200D),
    (0x2070, 0x218F),
    (0x2C00, 0x2FEF),
    (0x3001, 0xD7FF),
    (0xF900, 0xFDCF),
    (0xFDF0, 0xFFFD),
    (0x10000, 0xEFFFF)
]

// NameChar 的增量部分（相对 NameStartChar）：
// "-" | "." | [0-9] | #xB7 | [#x0300-#x036F] | [#x203F-#x2040]
let NAME_CHAR_EXTRA_RANGES: Array<(Int32, Int32)> = [
    (0x2D, 0x2E), // '-' '.'
    (0x30, 0x39), // 0-9
    (0xB7, 0xB7),
    (0x0300, 0x036F),
    (0x203F, 0x2040)
]

// PubidChar: #x20 | #xD | #xA | [a-zA-Z0-9] | [-'()+,./:=?;!*#@$_%]
const PUBID_CHAR_SET: String = " \r\n-'()+,./:=?;!*#@$_%"

/* ---------- 核心 API ---------- */

/** 判断码点是否在某个按 `(lo, hi)` 升序的区间表中。O(log n)。 */
public func contains(ranges: Array<(Int32, Int32)>, cp: Int32): Bool {
    if (ranges.size == 0) {
        return false
    }
    var lo = 0
    var hi = ranges.size - 1
    while (lo <= hi) {
        let mid = (lo + hi) >> 1
        let (rlo, rhi) = ranges[mid]
        if (cp < rlo) {
            hi = mid - 1
        } else if (cp > rhi) {
            lo = mid + 1
        } else {
            return true
        }
    }
    return false
}

/** 该码点是否为 XML（指定版本）合法字符。 */
public func isXmlChar(cp: Int32, version!: XmlVersion = XmlVersion.V10): Bool {
    match (version) {
        case V10 => contains(XML10_CHAR_RANGES, cp)
        case V11 => contains(XML11_CHAR_RANGES, cp)
    }
}

/** 判断是否为 XML 1.1 "受限字符"（须以字符引用形式出现）。 */
public func isXml11RestrictedChar(cp: Int32): Bool {
    if (cp >= 0x1 && cp <= 0x8) {
        return true
    }
    if (cp == 0xB || cp == 0xC) {
        return true
    }
    if (cp >= 0xE && cp <= 0x1F) {
        return true
    }
    if (cp >= 0x7F && cp <= 0x84) {
        return true
    }
    if (cp >= 0x86 && cp <= 0x9F) {
        return true
    }
    return false
}

/** NameStartChar（W3C XML 1.0 第 4e 产生式）。 */
public func isNameStartChar(cp: Int32): Bool {
    return contains(NAME_START_RANGES, cp)
}

/** NameChar（W3C XML 1.0 第 4 产生式）。 */
public func isNameChar(cp: Int32): Bool {
    return isNameStartChar(cp) || contains(NAME_CHAR_EXTRA_RANGES, cp)
}

/** XML 空白字符：space / tab / LF / CR（S，W3C 第 3 产生式）。 */
public func isXmlWhitespace(cp: Int32): Bool {
    return cp == 0x20 || cp == 0x9 || cp == 0xA || cp == 0xD
}

/** PubidChar：合法的 PUBLIC 标识字符。 */
public func isPubidChar(cp: Int32): Bool {
    if (cp > 127) {
        return false
    }
    // [a-zA-Z0-9]
    if ((cp >= 0x41 && cp <= 0x5A) || (cp >= 0x61 && cp <= 0x7A) || (cp >= 0x30 && cp <= 0x39)) {
        return true
    }
    for (r in PUBID_CHAR_SET.toRuneArray()) {
        if (Int32(UInt32(r)) == cp) {
            return true
        }
    }
    return false
}

/** 整串校验：每个字符都必须满足 `isXmlChar`；NUL 永远非法。 */
public func isValidXmlString(s: String, version!: XmlVersion = XmlVersion.V10): Bool {
    for (r in s.toRuneArray()) {
        let cp = Int32(UInt32(r))
        if (cp == 0) {
            return false
        }
        if (!isXmlChar(cp, version: version)) {
            return false
        }
    }
    return true
}

/** 整串校验：第一个字符必须是 `NameStartChar`，其余为 `NameChar`。 */
public func isValidName(s: String): Bool {
    if (s.isEmpty()) {
        return false
    }
    let runes = s.toRuneArray()
    if (!isNameStartChar(Int32(UInt32(runes[0])))) {
        return false
    }
    for (i in 1..runes.size) {
        if (!isNameChar(Int32(UInt32(runes[i])))) {
            return false
        }
    }
    return true
}

/** NCName（无冒号名字）——等价于 `isValidName(s) && !s.contains(":")`。 */
public func isValidNcName(s: String): Bool {
    if (!isValidName(s)) {
        return false
    }
    return !s.contains(":")
}
