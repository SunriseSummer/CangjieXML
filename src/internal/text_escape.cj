package cangjie_xml.internal

import std.collection.*

/**
 * XML 文本转义工具。
 *
 * ## 职责
 *
 * 把任意 `String` 值按上下文（文本节点 / 属性值）转换为 XML 语法合法的形式。
 * 本模块仅做"写出方向"的转义；反方向的实体解码由 Parser 阶段的
 * `internal.entity_decoder`（M3）承担。
 *
 * ## 转义矩阵
 *
 * |          | `&` | `<` | `>` | `"` | `'` | 备注 |
 * |----------|-----|-----|-----|-----|-----|------|
 * | 文本节点 | ✅  | ✅  | ✅  | —   | —   | 与 tinyxml2 `XMLPrinter::PrintString` 行为一致 |
 * | 属性值   | ✅  | ✅  | —   | ✅  | —   | 属性以双引号包裹，故不转义 `>`，转义 `"` |
 * | CDATA    | 均不转义，内容原样进入 `<![CDATA[ ... ]]>` | | | | | 若 `value` 含 `]]>` 将按 XML 规范分段（见 `escapeCdata`） |
 *
 * ## 为什么是 internal
 *
 * 转义规则属于 XML 语法层的实现细节，不应成为公共 API。如果未来想允许用户
 * 自定义转义策略（例如保留 Unicode 实体），那是单独 RFC，不在 v1.0 范围内。
 */

/**
 * 把文本内容（PCDATA）按 XML 规则转义。
 *
 * 针对 `&` / `<` / `>` 做最小必要转义。不转义 `"` / `'`，因为文本节点无引号歧义。
 *
 * 若输入不包含任一待转义字符，直接返回原字符串（零分配快路径）。
 */
public func escapeText(s: String): String {
    if (!_needsTextEscape(s)) {
        return s
    }
    let sb = StringBuilder()
    for (ch in s.runes()) {
        match (ch) {
            case r'&' => sb.append("&amp;")
            case r'<' => sb.append("&lt;")
            case r'>' => sb.append("&gt;")
            case _    => sb.append(ch)
        }
    }
    sb.toString()
}

/**
 * 把属性值按 XML 规则转义。属性值总是以双引号 `"` 包裹，因此需转义 `"`。
 *
 * 对 `&` / `<` 必转义（`>` 在 tinyxml2 默认行为中也转义，为兼容保留）。
 */
public func escapeAttribute(s: String): String {
    if (!_needsAttrEscape(s)) {
        return s
    }
    let sb = StringBuilder()
    for (ch in s.runes()) {
        match (ch) {
            case r'&' => sb.append("&amp;")
            case r'<' => sb.append("&lt;")
            case r'>' => sb.append("&gt;")
            case r'"' => sb.append("&quot;")
            case _    => sb.append(ch)
        }
    }
    sb.toString()
}

/**
 * 构造合法的 CDATA 段内容。
 *
 * XML 规范禁止 CDATA 段内出现子串 `]]>`。一旦出现，通过把 `]]>` 拆成
 * `]]` 与 `>` 分属两个 CDATA 段的做法来保持可往返性：
 *
 * - 原始：`foo]]>bar`
 * - 输出：`<![CDATA[foo]]]]><![CDATA[>bar]]>`
 *
 * 该函数返回包含 `<![CDATA[` 与 `]]>` 分隔符的完整段，调用方直接把结果写入即可。
 */
public func escapeCdata(s: String): String {
    let sb = StringBuilder()
    sb.append("<![CDATA[")
    if (s.contains("]]>")) {
        // 使用字符级扫描，寻找 "]]>"
        let runes = _toRunes(s)
        var i = 0
        while (i < runes.size) {
            if (i + 2 < runes.size && runes[i] == r']' && runes[i + 1] == r']' && runes[i + 2] == r'>') {
                sb.append(r']')
                sb.append(r']')
                sb.append("]]><![CDATA[")
                sb.append(r'>')
                i += 3
            } else {
                sb.append(runes[i])
                i++
            }
        }
    } else {
        sb.append(s)
    }
    sb.append("]]>")
    sb.toString()
}

/** UTF-8 BOM 字节序列：EF BB BF。 */
public let UTF8_BOM: Array<Byte> = [0xEFu8, 0xBBu8, 0xBFu8]

/** UTF-8 BOM 的字符串表示（单个 U+FEFF 码点）。 */
public let UTF8_BOM_STRING: String = "\u{FEFF}"

// ----------------------------------------------------------------------
// 内部快路径：判断是否需要转义
// ----------------------------------------------------------------------

func _needsTextEscape(s: String): Bool {
    for (ch in s.runes()) {
        match (ch) {
            case r'&' | r'<' | r'>' => return true
            case _ => ()
        }
    }
    false
}

func _needsAttrEscape(s: String): Bool {
    for (ch in s.runes()) {
        match (ch) {
            case r'&' | r'<' | r'>' | r'"' => return true
            case _ => ()
        }
    }
    false
}

/** 把字符串拉平为 `Rune` 数组，便于随机访问查找 `]]>`。 */
func _toRunes(s: String): Array<Rune> {
    let list = ArrayList<Rune>()
    for (r in s.runes()) {
        list.add(r)
    }
    list.toArray()
}
