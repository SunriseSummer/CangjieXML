package cangjie_xml.parser

import cangjie_xml.dom.*
import cangjie_xml.error.*

// 结构性字面量常量——集中避免魔鬼字符串散落到多个函数
const CDATA_PROLOGUE: String = "[CDATA["
const CDATA_EPILOGUE: String = "]]>"
const COMMENT_OPEN_DASHES: String = "--"
const COMMENT_EPILOGUE: String = "-->"
const EPILOGUE_LEN: Int64 = 3 // length of "-->" / "]]>"

/**
 * 递归下降 XML 解析器（M3）。
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
 *
 * ## 文件拆分
 *
 * 为保持单文件 ≤ 300 行并规避 cjc 1.0.5 的 `extend` 调用方向限制，实际的
 * 解析逻辑放入 `xml_parser_impl.cj` 的 `extend XmlParser` 中；本文件仅定义
 * 类骨架与不依赖解析状态机的纯工具函数。
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

    // 下列小工具不会反向调用 extend 中的解析函数，放在此处安全——
    // 也让 extend 文件专注于节点级语法。

    func matchesChar(ch: Rune): Bool {
        cur.peek() == Some(ch)
    }

    func consumeExpected(ch: Rune): Unit {
        if (!matchesChar(ch)) {
            throw XmlParseException(
                InvalidText(cur.pos(), "expected '${ch}'"))
        }
        cur.advance()
    }

    /** 读取一个 XML Name（起始 `isNameStart`，后续 `isNameChar`）。 */
    func readName(): String {
        let start = cur.idx
        match (cur.peek()) {
            case Some(r) =>
                if (!isNameStart(r)) {
                    throw XmlParseException(
                        InvalidText(cur.pos(), "expected name-start character"))
                }
            case None =>
                throw XmlParseException(
                    InvalidText(cur.pos(), "unexpected EOF where name expected"))
        }
        while (let Some(r) <- cur.peek()) {
            if (isNameChar(r)) {
                cur.advance()
            } else {
                break
            }
        }
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
    if (rr.size < 3) { return false }
    if (rr[0] != r'x' || rr[1] != r'm' || rr[2] != r'l') { return false }
    rr.size == 3 || isXmlWhitespace(rr[3])
}

/** 在 Collapse 模式下，把任意连续空白折叠为单个空格并去除首尾空白。 */
func collapseWhitespace(s: String): String {
    let sb = StringBuilder()
    var lastWasWs = false
    var emitted = false
    for (r in s.runes()) {
        if (isXmlWhitespace(r)) {
            if (emitted) { lastWasWs = true }
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
    for (r in s.runes()) {
        if (!isXmlWhitespace(r)) { return false }
    }
    true
}
