/*
 * core — 字符串工具
 *
 * 对应 libxml2: xmlstring.c 的子集。
 * 仓颉 `String` 原生即为 UTF-8 不可变字符串，因此无需复刻 libxml2 的
 * `xmlChar*` 全族 API；本文件只提供 XML 语义特有的若干辅助。
 */
package cangjie_xml.core

/**
 * 把字节数组按 UTF-8 解码为 `String`。
 * 非法 UTF-8 序列会抛出 `XmlException(EncodingError)`。
 */
public func bytesToString(bytes: Array<Byte>): String {
    try {
        return String.fromUtf8(bytes)
    } catch (_: Exception) {
        throw XmlException(XmlError.EncodingError(Position.unknown(), "invalid UTF-8 byte sequence"))
    }
}

/**
 * 对一段文本做 XML 转义，用于元素内容 / 属性值序列化。
 *
 * - 始终转义：`& < >`；
 * - 属性值模式（`forAttribute = true`）下额外转义：`"` `'` `\t` `\n` `\r`（保证往返）。
 */
public func escapeXml(s: String, forAttribute!: Bool = false): String {
    let sb = StringBuilder()
    for (r in s.toRuneArray()) {
        match (r) {
            case r'&' => sb.append("&amp;")
            case r'<' => sb.append("&lt;")
            case r'>' => sb.append("&gt;")
            case r'"' =>
                if (forAttribute) {
                    sb.append("&quot;")
                } else {
                    sb.append(r'"')
                }
            case r'\'' =>
                if (forAttribute) {
                    sb.append("&apos;")
                } else {
                    sb.append(r'\'')
                }
            case r'\t' =>
                if (forAttribute) {
                    sb.append("&#9;")
                } else {
                    sb.append(r'\t')
                }
            case r'\n' =>
                if (forAttribute) {
                    sb.append("&#10;")
                } else {
                    sb.append(r'\n')
                }
            case r'\r' => sb.append("&#13;")
            case other => sb.append(other)
        }
    }
    return sb.toString()
}

/**
 * XML "空白归一化"（Attribute-Value Normalization 第二阶段，对非 CDATA 属性）：
 * - 将 `\t` / `\n` / `\r` 变为空格；
 * - 将连续空格压缩为单个空格；
 * - 去除首尾空格。
 */
public func normalizeWhitespace(s: String): String {
    if (s.isEmpty()) {
        return s
    }
    let sb = StringBuilder()
    var prevSpace = true // 初始视作前面有空格，以实现前导空格的裁剪
    for (r in s.toRuneArray()) {
        let isWs = r == r' ' || r == r'\t' || r == r'\n' || r == r'\r'
        if (isWs) {
            if (!prevSpace) {
                sb.append(r' ')
                prevSpace = true
            }
        } else {
            sb.append(r)
            prevSpace = false
        }
    }
    let out = sb.toString()
    // 压缩末尾空格
    if (out.endsWith(" ")) {
        return out[0..out.size - 1]
    }
    return out
}

/**
 * XML 1.1 换行归一化（`parser` 与 `encoding` 都可能用到）：
 * - `\r\n` → `\n`；
 * - 单独的 `\r` → `\n`；
 * - XML 1.1：`\u0085`（NEL）与 `\u2028`（LS）同样归一到 `\n`（仅在 `xml11` 为真时）。
 */
public func normalizeNewlines(s: String, xml11!: Bool = false): String {
    let sb = StringBuilder()
    let runes = s.toRuneArray()
    var i = 0
    while (i < runes.size) {
        let r = runes[i]
        if (r == r'\r') {
            sb.append(r'\n')
            if (i + 1 < runes.size && runes[i + 1] == r'\n') {
                i += 1
            }
        } else if (xml11 && (Int32(UInt32(r)) == 0x85 || Int32(UInt32(r)) == 0x2028)) {
            sb.append(r'\n')
        } else {
            sb.append(r)
        }
        i += 1
    }
    return sb.toString()
}
