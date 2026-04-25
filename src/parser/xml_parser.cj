package cangjie_xml.parser

import cangjie_xml.dom.*
import cangjie_xml.error.*

// 结构性字面量常量，集中避免散落到多个函数。
// 注意：以下 String 形式仅用于错误消息 / 静态结构；热路径上的前缀匹配使用
// `source_cursor.cj` 中预编译的 `RUNE_*` 数组。
const EPILOGUE_LEN: Int64 = 3 // length of "-->" / "]]>"

/**
 * 递归下降 XML 解析器。
 *
 * 类骨架定义在本文件；元素级与文档级语法分别由 `xml_parser_element.cj` /
 * `xml_parser_toplevel.cj` 通过 `extend XmlParser` 挂回。
 *
 * ## 覆盖范围
 *
 * - XML 声明 `<?xml ... ?>`
 * - 注释 `<!-- ... -->`、CDATA `<![CDATA[ ... ]]>`
 * - `<!DOCTYPE ...>` 等以 `<!` 起始的未知节点（写入 `XmlUnknown`）
 * - 元素开 / 闭 / 自闭合；属性（单 / 双引号、实体还原）
 * - 文本节点、实体还原（`&amp; &lt; &gt; &quot; &apos; &#NN; &#xNN;`）
 * - 根元素唯一性、嵌套深度检查
 *
 * ## 错误模型
 *
 * 解析错误统一抛 `XmlParseException(XmlError, SourcePos)`，由公共入口
 * `XmlDocument.parseString` 透传。
 */
class XmlParser {
    let cur: SourceCursor
    let opts: XmlParseOptions
    let doc: XmlDocument

    init(source: String, options: XmlParseOptions, doc: XmlDocument) {
        this.cur = SourceCursor(source, options.acceptBom)
        this.opts = options
        this.doc = doc
    }

    // 不依赖解析状态机的小工具放在此处，使 extend 文件专注于节点级语法。

    func matchesChar(ch: Rune): Bool {
        cur.matches(ch)
    }

    func consumeExpected(ch: Rune): Unit {
        if (!cur.matches(ch)) {
            throw XmlParseException(InvalidText(cur.pos(), "expected '${ch}'"))
        }
        cur.advance()
    }

    /**
     * 读取一个 XML Name（起始 `isNameStart`，后续 `isNameChar`）。
     * 起始字符校验后通过 [SourceCursor.skipNameChars] 完成尾随扫描。
     */
    func readName(): String {
        let start = cur.idx
        if (start >= cur.runes.size) {
            throw XmlParseException(InvalidText(cur.pos(), "unexpected EOF where name expected"))
        }
        let r = cur.runes[start]
        if (!isNameStart(r)) {
            throw XmlParseException(InvalidText(cur.pos(), "expected name-start character"))
        }
        cur.skipNameChars()
        cur.sliceString(start, cur.idx)
    }
}

// ----------------------------------------------------------------------
// 无状态纯函数：文本工具
// ----------------------------------------------------------------------

func trimLeft(s: String): String {
    let rr = toRuneArray(s)
    var i = 0
    while (i < rr.size && isXmlWhitespace(rr[i])) {
        i++
    }
    let sb = StringBuilder()
    while (i < rr.size) {
        sb.append(rr[i])
        i++
    }
    sb.toString()
}

/** 若 payload 以 "xml" 起始，且后接空白 / 结束，则视为 XML 声明而非普通 PI。 */
func isDeclarationPayload(trimmed: String): Bool {
    let rr = toRuneArray(trimmed)
    if (rr.size < 3) {
        return false
    }
    if (rr[0] != r'x' || rr[1] != r'm' || rr[2] != r'l') {
        return false
    }
    rr.size == 3 || isXmlWhitespace(rr[3])
}

/** 在 Collapse 模式下，把任意连续空白折叠为单个空格并去除首尾空白。 */
func collapseWhitespace(s: String): String {
    let sb = StringBuilder()
    var lastWasWs = false
    var emitted = false
    for (r in s.runes()) {
        if (isXmlWhitespace(r)) {
            if (emitted) {
                lastWasWs = true
            }
        } else {
            if (lastWasWs) {
                sb.append(r' ')
                lastWasWs = false
            }
            sb.append(r)
            emitted = true
        }
    }
    sb.toString()
}

func isAllWhitespace(s: String): Bool {
    // XML 1.0 §2.3 的空白集合都是 ASCII 单字节；UTF-8 多字节序列的所有字节
    // 都 ≥ 0x80，因此按字节扫描结果与按 Rune 扫描完全一致，但更轻。
    let n = s.size
    var i = 0
    while (i < n) {
        let b = s[i]
        if (b != b' ' && b != b'\t' && b != b'\n' && b != b'\r') {
            return false
        }
        i++
    }
    true
}
