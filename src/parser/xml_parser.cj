package fastxml.parser

import fastxml.dom.*
import fastxml.error.*

/**
 * 结构性字面量常量，集中避免散落到多个函数
 *
 * 注意：以下 String 形式仅用于错误消息 / 静态结构；热路径上的前缀匹配使用
 * `source_cursor.cj` 中预编译的 `RUNE_*` 数组
 */
const EPILOGUE_LEN: Int64 = 3 // length of "-->" / "]]>"
private const DECLARATION_PREFIX_X: Byte = b'x'
private const DECLARATION_PREFIX_M: Byte = b'm'
private const DECLARATION_PREFIX_L: Byte = b'l'

/**
 * 递归下降 XML 解析器
 *
 * 类骨架定义在本文件；元素级与文档级语法分别由 `xml_parser_element.cj` /
 * `xml_parser_toplevel.cj` 通过 `extend XmlParser` 挂回
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
 * `XmlDocument.parseString` 透传
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

    // 不依赖解析状态机的小工具放在此处，使 extend 文件专注于节点级语法

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
     * 读取一个 XML Name（起始 `isNameStart`，后续 `isNameChar`）
     * 起始字符校验后通过 [SourceCursor.skipNameChars] 完成尾随扫描
     */
    func readName(): String {
        let start = cur.idx
        if (start >= cur.limit) {
            throw XmlParseException(InvalidText(cur.pos(), "unexpected EOF where name expected"))
        }
        let firstByte = cur.source[start]
        if (!isNameStartByte(firstByte)) {
            throw XmlParseException(InvalidText(cur.pos(), "expected name-start character"))
        }
        cur.skipNameChars()
        cur.sliceString(start, cur.idx)
    }
}

/**
 * 无状态纯函数：文本工具
 *
 * XML 1.0 §2.3 的空白集合（U+0020 / U+0009 / U+000A / U+000D）全是 ASCII
 * 单字节；UTF-8 多字节序列的所有字节均 ≥ 0x80。因此对"识别空白 / 在空白上
 * 切分"这类操作，按字节扫描结果与按 Rune 扫描完全一致，但无需对整段输入做
 * Rune 物化
 */
private const WS_SP: Byte = 0x20u8 // ' '
private const WS_HT: Byte = 0x09u8 // '\t'
private const WS_LF: Byte = 0x0Au8 // '\n'
private const WS_CR: Byte = 0x0Du8 // '\r'

private func isWsByte(b: Byte): Bool {
    b == WS_SP || b == WS_HT || b == WS_LF || b == WS_CR
}

func trimLeft(s: String): String {
    let inputLength = s.size
    var byteIndex = 0
    while (byteIndex < inputLength && isWsByte(s[byteIndex])) {
        byteIndex++
    }
    if (byteIndex == 0) {
        return s
    }
    if (byteIndex == inputLength) {
        return String.empty
    }
    s[byteIndex..inputLength]
}

// 若 payload 以 "xml" 起始，且后接空白 / 结束，则视为 XML 声明而非普通 PI
func isDeclarationPayload(trimmed: String): Bool {
    let payloadLength = trimmed.size
    if (payloadLength < 3) {
        return false
    }
    let startsWithX = trimmed[0] == DECLARATION_PREFIX_X
    let followedByM = trimmed[1] == DECLARATION_PREFIX_M
    let followedByL = trimmed[2] == DECLARATION_PREFIX_L
    let hasXmlPrefix = startsWithX && followedByM && followedByL
    if (!hasXmlPrefix) {
        return false
    }
    payloadLength == 3 || isWsByte(trimmed[3])
}

/**
 * Collapse 模式下把任意连续空白折叠为单个空格并去除首尾空白
 *
 * 实现按字节遍历——遇到非空白字节段时一次性 `append`，避免对每个 Rune 分别
 * 走 `s.runes()` 迭代器（UTF-8 多字节序列的所有字节均 ≥ 0x80，永远不会与
 * 空白字节冲突，因此对 ASCII 与非 ASCII 文本一视同仁）
 */
func collapseWhitespace(s: String): String {
    let inputLength = s.size
    let buffer = StringBuilder()
    var lastWasWs = false
    var emitted = false
    var byteIndex = 0
    while (byteIndex < inputLength) {
        let currentByte = s[byteIndex]
        if (isWsByte(currentByte)) {
            if (emitted) {
                lastWasWs = true
            }
            byteIndex++
            continue
        }
        if (lastWasWs) {
            buffer.append(r' ')
            lastWasWs = false
        }
        let segmentStart = byteIndex
        while (byteIndex < inputLength && !isWsByte(s[byteIndex])) {
            byteIndex++
        }
        buffer.append(s[segmentStart..byteIndex])
        emitted = true
    }
    buffer.toString()
}

func isAllWhitespace(s: String): Bool {
    let inputLength = s.size
    var byteIndex = 0
    while (byteIndex < inputLength) {
        if (!isWsByte(s[byteIndex])) {
            return false
        }
        byteIndex++
    }
    true
}
