package fastxml.internal

/**
 * XML 文本转义工具。属于 internal——XML 语法层细节，不对外公开
 *
 * 把任意 `String` 值按上下文（文本节点 / 属性值 / CDATA）转换为 XML 语法
 * 合法的形式；反方向的实体解码由 Parser 阶段的 `entity_decoder` 承担
 *
 * ## 转义矩阵
 *
 * |          | `&` | `<` | `>` | `"` | `'` | 备注 |
 * |----------|-----|-----|-----|-----|-----|------|
 * | 文本节点 | ✅  | ✅  | ✅  | —   | —   | 与 tinyxml2 `XMLPrinter::PrintString` 一致 |
 * | 属性值   | ✅  | ✅  | ✅  | ✅  | —   | 属性以双引号包裹，故转义 `"` |
 * | CDATA    | 均不转义，内容原样进入 `<![CDATA[ ... ]]>` | | | | | 含 `]]>` 时按 XML 规范分段（见 `escapeCdata`） |
 *
 * 三个公共入口（[escapeText] / [escapeAttribute] / [escapeCdata]）都先做
 * 字节级快速判定，无可转义内容时直接返回原串、零分配
 */

// 集中常量定义：避免魔鬼字符串 / 魔鬼数字散落到多个函数中

const CDATA_OPEN: String = "<![CDATA["
const CDATA_CLOSE: String = "]]>"
const CDATA_TERMINATOR: String = "]]>"
const CDATA_TERMINATOR_LEN: Int64 = 3
// 拆分后在 `]]` 与 `>` 之间插入的分隔段，使两半分别落入相邻 CDATA
const CDATA_REOPEN_AFTER_BRACKETS: String = "]]><![CDATA["
private const CDATA_RBRACKET_BYTE: Byte = 0x5Du8 // ']'
private const CDATA_GT_BYTE: Byte = 0x3Eu8 // '>'

const BOM_BYTE_0: Byte = 0xEFu8
const BOM_BYTE_1: Byte = 0xBBu8
const BOM_BYTE_2: Byte = 0xBFu8

// 转义触发字节——以字节常量声明，避免在热路径上每次比较都做 `Rune → UInt8` 转换
private const ESCAPE_AMP: Byte = 0x26u8 // '&'
private const ESCAPE_LT: Byte = 0x3Cu8 // '<'
private const ESCAPE_GT: Byte = 0x3Eu8 // '>'
private const ESCAPE_QUOT: Byte = 0x22u8 // '"'

/**
 * 把文本内容（PCDATA）按 XML 规则转义
 *
 * 针对 `&` / `<` / `>` 做最小必要转义，不转义 `"` / `'`（文本节点无引号歧义）
 * 若输入不包含任一待转义字符，直接返回原字符串，零分配快路径
 *
 * 慢路径按字节扫描并以"区间拷贝 + 实体替换"成块输出：`& < >` 都是 ASCII
 * 单字节，UTF-8 多字节序列的所有字节均 ≥ 0x80，因此按字节定位边界与按
 * Rune 扫描结果一致但无需解码
 */
public func escapeText(s: String): String {
    if (!needsTextEscape(s)) {
        return s
    }
    let inputLength = s.size
    let buffer = StringBuilder()
    var byteIndex = 0
    var lastWriteIndex = 0
    while (byteIndex < inputLength) {
        let currentByte = s[byteIndex]
        if (currentByte == ESCAPE_AMP) {
            if (byteIndex > lastWriteIndex) {
                buffer.append(s[lastWriteIndex..byteIndex])
            }
            buffer.append("&amp;")
            lastWriteIndex = byteIndex + 1
        } else if (currentByte == ESCAPE_LT) {
            if (byteIndex > lastWriteIndex) {
                buffer.append(s[lastWriteIndex..byteIndex])
            }
            buffer.append("&lt;")
            lastWriteIndex = byteIndex + 1
        } else if (currentByte == ESCAPE_GT) {
            if (byteIndex > lastWriteIndex) {
                buffer.append(s[lastWriteIndex..byteIndex])
            }
            buffer.append("&gt;")
            lastWriteIndex = byteIndex + 1
        }
        byteIndex++
    }
    if (lastWriteIndex < inputLength) {
        buffer.append(s[lastWriteIndex..inputLength])
    }
    buffer.toString()
}

/**
 * 把属性值按 XML 规则转义。属性值总是以双引号 `"` 包裹，因此需转义 `"`
 *
 * 对 `&` / `<` 必转义（`>` 在 tinyxml2 默认行为中也转义，为兼容保留）
 * 性能策略与 `escapeText` 一致——纯字节扫描 + 区间拷贝
 */
public func escapeAttribute(s: String): String {
    if (!needsAttrEscape(s)) {
        return s
    }
    let inputLength = s.size
    let buffer = StringBuilder()
    var byteIndex = 0
    var lastWriteIndex = 0
    while (byteIndex < inputLength) {
        let currentByte = s[byteIndex]
        if (currentByte == ESCAPE_AMP) {
            if (byteIndex > lastWriteIndex) {
                buffer.append(s[lastWriteIndex..byteIndex])
            }
            buffer.append("&amp;")
            lastWriteIndex = byteIndex + 1
        } else if (currentByte == ESCAPE_LT) {
            if (byteIndex > lastWriteIndex) {
                buffer.append(s[lastWriteIndex..byteIndex])
            }
            buffer.append("&lt;")
            lastWriteIndex = byteIndex + 1
        } else if (currentByte == ESCAPE_GT) {
            if (byteIndex > lastWriteIndex) {
                buffer.append(s[lastWriteIndex..byteIndex])
            }
            buffer.append("&gt;")
            lastWriteIndex = byteIndex + 1
        } else if (currentByte == ESCAPE_QUOT) {
            if (byteIndex > lastWriteIndex) {
                buffer.append(s[lastWriteIndex..byteIndex])
            }
            buffer.append("&quot;")
            lastWriteIndex = byteIndex + 1
        }
        byteIndex++
    }
    if (lastWriteIndex < inputLength) {
        buffer.append(s[lastWriteIndex..inputLength])
    }
    buffer.toString()
}

/**
 * 构造合法的 CDATA 段内容
 *
 * XML 规范禁止 CDATA 段内出现子串 `]]>`。一旦出现，通过把 `]]>` 拆成
 * `]]` 与 `>` 分属两个 CDATA 段的做法来保持可往返性：
 *
 * - 原始：`foo]]>bar`
 * - 输出：`<![CDATA[foo]]]]><![CDATA[>bar]]>`
 *
 * 该函数返回包含 `<![CDATA[` 与 `]]>` 分隔符的完整段，调用方直接把结果写入即可
 */
public func escapeCdata(s: String): String {
    let buffer = StringBuilder()
    buffer.append(CDATA_OPEN)
    if (s.contains(CDATA_TERMINATOR)) {
        appendWithCdataSplit(buffer, s)
    } else {
        buffer.append(s)
    }
    buffer.append(CDATA_CLOSE)
    buffer.toString()
}

/**
 * CDATA 内容中遇到 `]]>` 的分段处理：以字节扫描定位 `]]>`（全 ASCII，UTF-8
 * 多字节序列的所有字节均 ≥ 0x80）；命中时把 `]]` 与 `>` 分入相邻 CDATA 段
 */
func appendWithCdataSplit(buffer: StringBuilder, s: String): Unit {
    let inputLength = s.size
    var byteIndex = 0
    var lastWriteIndex = 0
    while (byteIndex < inputLength) {
        if (isCdataTerminatorAt(s, byteIndex, inputLength)) {
            if (byteIndex > lastWriteIndex) {
                buffer.append(s[lastWriteIndex..byteIndex])
            }
            // 把 `]]>` 拆成 `]]` + reopen + `>`，二者各自归属相邻的 CDATA 段
            buffer.append(s[byteIndex..byteIndex + 2])
            buffer.append(CDATA_REOPEN_AFTER_BRACKETS)
            buffer.append(s[byteIndex + 2..byteIndex + 3])
            byteIndex += CDATA_TERMINATOR_LEN
            lastWriteIndex = byteIndex
        } else {
            byteIndex++
        }
    }
    if (lastWriteIndex < inputLength) {
        buffer.append(s[lastWriteIndex..inputLength])
    }
}

// 判断 `s[i..i+3]` 是否为 ASCII 字节 `]]>`
func isCdataTerminatorAt(s: String, candidateIndex: Int64, inputLength: Int64): Bool {
    if (candidateIndex + CDATA_TERMINATOR_LEN > inputLength) {
        return false
    }
    let hasLeadingBrackets = s[candidateIndex] == CDATA_RBRACKET_BYTE && s[candidateIndex + 1] == CDATA_RBRACKET_BYTE
    let hasTrailingGt = s[candidateIndex + 2] == CDATA_GT_BYTE
    hasLeadingBrackets && hasTrailingGt
}

// UTF-8 BOM 字节序列：EF BB BF
public let UTF8_BOM: Array<Byte> = [BOM_BYTE_0, BOM_BYTE_1, BOM_BYTE_2]

// UTF-8 BOM 的字符串表示（单个 U+FEFF 码点）
public let UTF8_BOM_STRING: String = "\u{FEFF}"

/**
 * 内部快路径：判断是否需要转义
 *
 * 这两个判定函数对每个文本节点 / 每个属性值都会被调用。`& < > "` 都是 ASCII
 * 单字节，UTF-8 多字节序列的所有字节均 ≥ 0x80，按字节扫描即可一次到位
 */
func needsTextEscape(s: String): Bool {
    let inputLength = s.size
    var byteIndex = 0
    while (byteIndex < inputLength) {
        let currentByte = s[byteIndex]
        if (isTextEscapeByte(currentByte)) {
            return true
        }
        byteIndex++
    }
    false
}

func needsAttrEscape(s: String): Bool {
    let inputLength = s.size
    var byteIndex = 0
    while (byteIndex < inputLength) {
        let currentByte = s[byteIndex]
        if (isAttrEscapeByte(currentByte)) {
            return true
        }
        byteIndex++
    }
    false
}

func isTextEscapeByte(currentByte: Byte): Bool {
    currentByte == ESCAPE_AMP || currentByte == ESCAPE_LT || currentByte == ESCAPE_GT
}

func isAttrEscapeByte(currentByte: Byte): Bool {
    isTextEscapeByte(currentByte) || currentByte == ESCAPE_QUOT
}
