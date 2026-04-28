package fastxml.parser

import fastxml.error.*

// Parser 中常用的单字符 Rune 常量，集中声明便于复用
const CH_LT: Rune = r'<'
const CH_GT: Rune = r'>'
const CH_AMP: Rune = r'&'
const CH_QUOT: Rune = r'"'
const CH_APOS: Rune = r'\''
const CH_SLASH: Rune = r'/'
const CH_QUESTION: Rune = r'?'
const CH_BANG: Rune = r'!'
const CH_EQUALS: Rune = r'='
const CH_LF: Rune = r'\n'
// UTF-8 BOM 的码点形式，对应 `text_escape.cj` 中的字节常量
const RUNE_BOM: Rune = '\u{FEFF}'

/**
 * 与 `CH_*: Rune` 对齐的字节常量，热路径上按字节比较即可，
 * 避免 `Rune == Rune` 带来的码点装箱比较
 */
const BY_LT: Byte = 0x3Cu8 // '<'
const BY_GT: Byte = 0x3Eu8 // '>'
const BY_AMP: Byte = 0x26u8 // '&'
const BY_QUOT: Byte = 0x22u8 // '"'
const BY_APOS: Byte = 0x27u8 // '\''
const BY_SLASH: Byte = 0x2Fu8 // '/'
const BY_QUESTION: Byte = 0x3Fu8 // '?'
const BY_BANG: Byte = 0x21u8 // '!'
const BY_EQUALS: Byte = 0x3Du8 // '='
const BY_LF: Byte = 0x0Au8 // '\n'
const BY_CR: Byte = 0x0Du8 // '\r'
const BY_TAB: Byte = 0x09u8 // '\t'
const BY_SP: Byte = 0x20u8 // ' '
const BY_LBRACK: Byte = 0x5Bu8 // '['
const BY_RBRACK: Byte = 0x5Du8 // ']'
const BY_UNDERSCORE: Byte = 0x5Fu8 // '_'
const BY_COLON: Byte = 0x3Au8 // ':'
const BY_HYPHEN: Byte = 0x2Du8 // '-'
const BY_DOT: Byte = 0x2Eu8 // '.'
const BY_0: Byte = 0x30u8 // '0'
const BY_9: Byte = 0x39u8 // '9'
const BY_A_UPPER: Byte = 0x41u8 // 'A'
const BY_Z_UPPER: Byte = 0x5Au8 // 'Z'
const BY_A_LOWER: Byte = 0x61u8 // 'a'
const BY_Z_LOWER: Byte = 0x7Au8 // 'z'
const BY_C_UPPER: Byte = 0x43u8 // 'C'
const BY_D_UPPER: Byte = 0x44u8 // 'D'
const BY_T_UPPER: Byte = 0x54u8 // 'T'

// ASCII 边界：`b < ASCII_LIMIT_BYTE` 即纯 ASCII 字节
const ASCII_LIMIT_BYTE: Byte = 0x80u8

// "无字节"哨兵——XML 文本中 0x00 本就非法，可安全用作越界返回值
const NO_BYTE: Byte = 0x00u8

// UTF-8 BOM 字节序列 `EF BB BF`
const BOM_BYTE_0: Byte = 0xEFu8
const BOM_BYTE_1: Byte = 0xBBu8
const BOM_BYTE_2: Byte = 0xBFu8
// UTF-8 BOM 长度（字节）
const BOM_BYTE_COUNT: Int64 = 3

/**
 * UTF-8 编码识别用位掩码 / 前缀
 *
 * 命名遵循 RFC 3629 中 leading byte 的形式：`UTF8_LEAD<N>_MASK` 提取序列长度
 * 判定位，`UTF8_LEAD<N>_PREFIX` 是序列首字节"长度位"的标准取值；
 * `UTF8_CONT_MASK` / `UTF8_CONT_PREFIX` 用于识别续字节（`10xxxxxx`）
 * `UTF8_LEAD<N>_PAYLOAD_MASK` 用于从首字节提取该长度对应的有效负载比特
 */

// 续字节判定：`(b & UTF8_CONT_MASK) == UTF8_CONT_PREFIX` 即 `10xxxxxx`
const UTF8_CONT_MASK: Byte = 0xC0u8
const UTF8_CONT_PREFIX: Byte = 0x80u8
// 续字节有效负载比特掩码（低 6 位）
const UTF8_CONT_PAYLOAD_MASK: Byte = 0x3Fu8

// 2 字节序列首字节判定：`(b & UTF8_LEAD2_MASK) == UTF8_LEAD2_PREFIX`
const UTF8_LEAD2_MASK: Byte = 0xE0u8
const UTF8_LEAD2_PREFIX: Byte = 0xC0u8
// 2 字节首字节有效负载（低 5 位）
const UTF8_LEAD2_PAYLOAD_MASK: Byte = 0x1Fu8

// 3 字节序列首字节判定
const UTF8_LEAD3_MASK: Byte = 0xF0u8
const UTF8_LEAD3_PREFIX: Byte = 0xE0u8
// 3 字节首字节有效负载（低 4 位）
const UTF8_LEAD3_PAYLOAD_MASK: Byte = 0x0Fu8

// 4 字节序列首字节判定
const UTF8_LEAD4_MASK: Byte = 0xF8u8
const UTF8_LEAD4_PREFIX: Byte = 0xF0u8
// 4 字节首字节有效负载（低 3 位）
const UTF8_LEAD4_PAYLOAD_MASK: Byte = 0x07u8

// 续字节贡献的有效比特数（每续字节贡献 6 位）
const UTF8_CONT_BITS: UInt32 = 6

// UTF-8 各类序列长度（字节），用于 `Utf8Decoded.byteLen` 与边界检查
const UTF8_LEN_2: Int64 = 2
const UTF8_LEN_3: Int64 = 3
const UTF8_LEN_4: Int64 = 4
// 解码失败回退的推进步长（按 1 字节滑过）
const UTF8_INVALID_ADVANCE: Int64 = 1

// Unicode 替换字符 U+FFFD，用于无法解码的 UTF-8 字节序列回退
const UTF8_REPLACEMENT_CODEPOINT: UInt32 = 0xFFFDu32

/**
 * 注释 / CDATA 等结构关键串的预编译字节序列
 *
 * 这些前缀全部为 ASCII，UTF-8 多字节序列的所有续字节均 ≥ 0x80，
 * 因此按字节比较与按 Rune 比较结果一致，但完全避免码点解码
 */
let BYTES_COMMENT_OPEN_DASHES: Array<Byte> = [BY_HYPHEN, BY_HYPHEN]
let BYTES_CDATA_PROLOGUE: Array<Byte> = [BY_LBRACK, BY_C_UPPER, BY_D_UPPER, BY_A_UPPER, BY_T_UPPER, BY_A_UPPER,
    BY_LBRACK] // "[CDATA["
let BYTES_COMMENT_EPILOGUE: Array<Byte> = [BY_HYPHEN, BY_HYPHEN, BY_GT]
let BYTES_CDATA_EPILOGUE: Array<Byte> = [BY_RBRACK, BY_RBRACK, BY_GT]

/**
 * 字节索引前向游标，供 Parser 使用
 *
 * ## 设计要点
 *
 * - 所有 XML 语法分隔符（`<`、`>`、`/`、`=`、引号、`&` 等）都是 ASCII 单字节；
 *   UTF-8 多字节序列的所有续字节均 ≥ 0x80，因此按字节扫描与按 Rune 扫描在
 *   "识别分隔符 / 在分隔符上切分"这件事上结果完全一致——但无需对整段输入做
 *   `Array<Rune>` 物化（旧实现对 5 MB ASCII 文件会预分配 20 MB Rune 数组，
 *   命中仓颉 `string_concat`/分配链路的弱项）
 *
 * - `idx` 与 `SourcePos.offset` 现统一为 **字节索引**；纯 ASCII 输入下与原先
 *   "码点索引"语义完全一致。`line` / `column` 仍按码点计数
 *
 * - 字符串切片 `source[start..end]` 直接命中底层 UTF-8 字节切片实现，
 *   名字 / 属性值 / 文本等输出无需重新编码
 */
class SourceCursor {
    let source: String
    // 当前字节位置；start = BOM 之后
    var idx: Int64 = 0
    var line: Int64 = 1
    var column: Int64 = 1

    // 总长度（字节）
    let limit: Int64

    /**
     * 输入是否以 UTF-8 BOM 起首，由 parser 在构造文档后回写到
     * `XmlDocument.hasBom`，使 parse→write 往返保留 BOM 语义
     */
    let sawBom: Bool

    init(input: String, acceptBom: Bool) {
        let inputSize = input.size
        var bomSeen = false
        var startByte = 0
        let hasEnoughBytesForBom = inputSize >= BOM_BYTE_COUNT
        let matchesBomByte0 = hasEnoughBytesForBom && input[0] == BOM_BYTE_0
        let matchesBomByte1 = hasEnoughBytesForBom && input[1] == BOM_BYTE_1
        let matchesBomByte2 = hasEnoughBytesForBom && input[2] == BOM_BYTE_2
        let matchesBomPrefix = matchesBomByte0 && matchesBomByte1 && matchesBomByte2
        let hasUtf8BomPrefix = matchesBomPrefix
        if (hasUtf8BomPrefix) {
            if (!acceptBom) {
                throw XmlParseException(InvalidEncoding(SourcePos(0, 1, 1), "unexpected UTF-8 BOM (acceptBom = false)"))
            }
            bomSeen = true
            startByte = BOM_BYTE_COUNT
        }
        this.sawBom = bomSeen
        if (startByte == 0) {
            this.source = input
        } else {
            // 与旧实现保持一致：BOM 剥离后才进入解析
            this.source = input[startByte..inputSize]
        }
        this.limit = this.source.size
    }

    // 是否已到末尾
    func eof(): Bool {
        idx >= limit
    }

    /**
     * 取当前位置的字节（要求 !eof）。供热路径上的 ASCII 比较使用——
     * 所有 XML 分隔符都是 ASCII 单字节，按字节比较安全
     */
    func currentByte(): Byte {
        source[idx]
    }

    /**
     * 取当前位置的字节，越界时返回 [NO_BYTE]。`NO_BYTE = 0x00` 在 XML 文本中本就
     * 是非法字符，可安全用作"无字节"哨兵值；供需要"无 EOF 检查"的等值比较使用
     */
    func currentByteOr0(): Byte {
        if (idx < limit) {
            source[idx]
        } else {
            NO_BYTE
        }
    }

    /**
     * 取偏移 `k` 字节处的字节，越界返回 [NO_BYTE]。`k` 一般为 1，用于 lookahead
     * 一个 ASCII 分隔符（如 `?>`、`</`）
     */
    func byteAtOffset(k: Int64): Byte {
        let targetIndex = idx + k
        if (targetIndex >= 0 && targetIndex < limit) {
            source[targetIndex]
        } else {
            NO_BYTE
        }
    }

    /**
     * 取当前位置的 Rune（用于错误消息或个别需要码点语义的场景）
     * ASCII 走快路径直接构造；非 ASCII 解码 UTF-8
     */
    func currentRune(): Rune {
        let currentByte = source[idx]
        if (currentByte < ASCII_LIMIT_BYTE) {
            return Rune(UInt32(currentByte))
        }
        decodeUtf8At(idx).rune
    }

    // 当前字符；EOF 时返回 None
    func peek(): ?Rune {
        if (eof()) {
            None
        } else {
            Some(currentRune())
        }
    }

    // 当前字符是否等于 `ch`；EOF 时返回 false
    func matches(ch: Rune): Bool {
        if (eof()) {
            return false
        }
        let cp = UInt32(ch)
        if (cp < UInt32(ASCII_LIMIT_BYTE)) {
            return source[idx] == UInt8(cp)
        }
        currentRune() == ch
    }

    // 偏移 `k` 字节处的字节是否等于 ASCII `ch`；越界返回 false
    func matchesAt(k: Int64, ch: Rune): Bool {
        // 全部调用点的 ch 都是 ASCII 分隔符（'/'、'>'）
        let cp = UInt32(ch)
        let targetIndex = idx + k
        targetIndex >= 0 && targetIndex < limit && source[targetIndex] == UInt8(cp)
    }

    // 消费一个字符并返回；到达 EOF 返回 None
    func advance(): ?Rune {
        if (eof()) {
            return None
        }
        let currentByte = source[idx]
        if (currentByte < ASCII_LIMIT_BYTE) {
            idx++
            if (currentByte == BY_LF) {
                line++
                column = 1
            } else {
                column++
            }
            return Some(Rune(UInt32(currentByte)))
        }
        // 非 ASCII：解码 UTF-8 序列长度，整段跳过；列号 +1
        let decoded = decodeUtf8At(idx)
        idx += decoded.byteLen
        column++
        Some(decoded.rune)
    }

    // 跳过所有 XML 空白字符（空格 / 制表 / LF / CR）
    func skipWhitespace(): Unit {
        while (idx < limit) {
            let currentByte = source[idx]
            if (currentByte == BY_LF) {
                idx++
                line++
                column = 1
            } else if (currentByte == BY_SP || currentByte == BY_TAB || currentByte == BY_CR) {
                idx++
                column++
            } else {
                return
            }
        }
    }

    /**
     * 跳过所有 `isNameChar(r)` 字符，专为 [readName] 等热路径设计
     *
     * Name 字符均为 ASCII（与 `isNameChar` 一致），因此按字节扫描即可
     * Name 字符不可能是 LF，因此不维护行号
     */
    func skipNameChars(): Unit {
        while (idx < limit) {
            let currentByte = source[idx]
            if (isNameCharByte(currentByte)) {
                idx++
                column++
            } else {
                return
            }
        }
    }

    // 扫描到下一个 `<` 或 EOF；供 `parseTextBody` 使用，遇到 LF 时维护行号
    func skipUntilLt(): Unit {
        while (idx < limit) {
            let currentByte = source[idx]
            if (currentByte == BY_LT) {
                return
            }
            idx++
            advanceColumnAfterByte(currentByte)
        }
    }

    /**
     * 扫描属性值字符直到遇到 `quoteCh`、`<` 或 EOF
     *
     * 返回 `true` 表示遇到引号成功停下；`false` 表示遇到 `<` 或 EOF，
     * 由调用方进一步区分并报错
     */
    func skipAttrValueChars(quoteCh: Rune): Bool {
        // quoteCh 必为 `"` 或 `'`，都是 ASCII
        let quoteByte = UInt8(UInt32(quoteCh))
        while (idx < limit) {
            let currentByte = source[idx]
            if (currentByte == quoteByte) {
                return true
            }
            if (currentByte == BY_LT) {
                return false
            }
            idx++
            advanceColumnAfterByte(currentByte)
        }
        false
    }

    /**
     * `idx` 已向前推进 1 字节后，按字节 `b` 的角色更新 `line` / `column`：
     *
     * - LF：换行，列号重置为 1
     * - 其他 ASCII 字节：列号 +1
     * - UTF-8 续字节（`10xxxxxx`）：列号不变
     * - UTF-8 序列首字节（≥ 0x80 且非续字节）：列号 +1（整个码点算一列）
     */
    private func advanceColumnAfterByte(b: Byte): Unit {
        if (b == BY_LF) {
            line++
            column = 1
        } else if (b < ASCII_LIMIT_BYTE) {
            column++
        } else if ((b & UTF8_CONT_MASK) != UTF8_CONT_PREFIX) {
            // 多字节序列首字节：整个码点只计一列
            column++
        }
    }

    /**
     * 若后续字节序列以 `prefix` 起始则消费并返回 true，否则原位返回 false
     *
     * 前缀全为 ASCII，不可能含 LF；命中后批量更新 `idx` 与 `column`
     */
    func consumeIfMatchBytes(prefix: Array<Byte>): Bool {
        let prefixLen = prefix.size
        if (idx + prefixLen > limit) {
            return false
        }
        var i = 0
        while (i < prefixLen) {
            if (source[idx + i] != prefix[i]) {
                return false
            }
            i++
        }
        idx += prefixLen
        column += prefixLen
        true
    }

    // 当前坐标的 `SourcePos`（offset 以字节计，行列从 1 起）
    func pos(): SourcePos {
        SourcePos(idx, line, column)
    }

    /**
     * 取 `[start, end)` 区间的子串（按字节）
     *
     * 字节切片直接命中 String 的底层 UTF-8 切片实现，对 ASCII / 非 ASCII
     * 输入一致——仅当切片边界落在 ASCII 字节（XML 分隔符）时才会被调用，
     * 不会切到 UTF-8 续字节中间
     */
    func sliceString(start: Int64, end: Int64): String {
        if (end <= start) {
            return String.empty
        }
        source[start..end]
    }

    /**
     * 在 `byteIndex` 处解码一个 UTF-8 码点。仅在非 ASCII 字节上调用——ASCII 走更快
     * 的字节路径。失败时退化为 U+FFFD 替换字符并按 [UTF8_INVALID_ADVANCE] 字节推进，
     * 避免热路径上分支爆炸
     */
    func decodeUtf8At(byteIndex: Int64): Utf8Decoded {
        let b0 = source[byteIndex]
        // 2 字节序列 `110xxxxx 10xxxxxx`
        if ((b0 & UTF8_LEAD2_MASK) == UTF8_LEAD2_PREFIX && byteIndex + 1 < limit) {
            let b1 = source[byteIndex + 1]
            if ((b1 & UTF8_CONT_MASK) == UTF8_CONT_PREFIX) {
                let leadPayload = UInt32(b0 & UTF8_LEAD2_PAYLOAD_MASK) << UTF8_CONT_BITS
                let continuationPayload = UInt32(b1 & UTF8_CONT_PAYLOAD_MASK)
                let cp = leadPayload | continuationPayload
                return Utf8Decoded(Rune(cp), UTF8_LEN_2)
            }
        }
        // 3 字节序列 `1110xxxx 10xxxxxx 10xxxxxx`
        if ((b0 & UTF8_LEAD3_MASK) == UTF8_LEAD3_PREFIX && byteIndex + 2 < limit) {
            let b1 = source[byteIndex + 1]
            let b2 = source[byteIndex + 2]
            let hasValidContinuationBytes = (b1 & UTF8_CONT_MASK) == UTF8_CONT_PREFIX && (b2 & UTF8_CONT_MASK) ==
                UTF8_CONT_PREFIX
            if (hasValidContinuationBytes) {
                let leadPayload = UInt32(b0 & UTF8_LEAD3_PAYLOAD_MASK) << (UTF8_CONT_BITS * 2)
                let midPayload = UInt32(b1 & UTF8_CONT_PAYLOAD_MASK) << UTF8_CONT_BITS
                let tailPayload = UInt32(b2 & UTF8_CONT_PAYLOAD_MASK)
                let cp = leadPayload | midPayload | tailPayload
                return Utf8Decoded(Rune(cp), UTF8_LEN_3)
            }
        }
        // 4 字节序列 `11110xxx 10xxxxxx 10xxxxxx 10xxxxxx`
        if ((b0 & UTF8_LEAD4_MASK) == UTF8_LEAD4_PREFIX && byteIndex + 3 < limit) {
            let b1 = source[byteIndex + 1]
            let b2 = source[byteIndex + 2]
            let b3 = source[byteIndex + 3]
            let isB1Continuation = (b1 & UTF8_CONT_MASK) == UTF8_CONT_PREFIX
            let isB2Continuation = (b2 & UTF8_CONT_MASK) == UTF8_CONT_PREFIX
            let isB3Continuation = (b3 & UTF8_CONT_MASK) == UTF8_CONT_PREFIX
            let hasValidContinuationBytes = isB1Continuation && isB2Continuation && isB3Continuation
            if (hasValidContinuationBytes) {
                let leadPayload = UInt32(b0 & UTF8_LEAD4_PAYLOAD_MASK) << (UTF8_CONT_BITS * 3)
                let upperMidPayload = UInt32(b1 & UTF8_CONT_PAYLOAD_MASK) << (UTF8_CONT_BITS * 2)
                let lowerMidPayload = UInt32(b2 & UTF8_CONT_PAYLOAD_MASK) << UTF8_CONT_BITS
                let tailPayload = UInt32(b3 & UTF8_CONT_PAYLOAD_MASK)
                let cp = leadPayload | upperMidPayload | lowerMidPayload | tailPayload
                return Utf8Decoded(Rune(cp), UTF8_LEN_4)
            }
        }
        // 非法 UTF-8：返回 U+FFFD 替换字符并按 1 字节推进
        Utf8Decoded(Rune(UTF8_REPLACEMENT_CODEPOINT), UTF8_INVALID_ADVANCE)
    }
}

// 描述一个 UTF-8 解码结果
struct Utf8Decoded {
    let rune: Rune
    let byteLen: Int64
    init(rune: Rune, byteLen: Int64) {
        this.rune = rune
        this.byteLen = byteLen
    }
}

// XML 规范 §2.3 定义的空白字符集合
func isXmlWhitespace(r: Rune): Bool {
    r == r' ' || r == r'\t' || r == CH_LF || r == r'\r'
}

// 名称起始字符（XML 1.0 Name 子集：字母 / `_` / `:`）
func isNameStart(r: Rune): Bool {
    isAsciiLetter(r) || r == r'_' || r == r':'
}

// 名称尾随字符——在起始字符基础上额外允许数字 / `-` / `.`
func isNameChar(r: Rune): Bool {
    isNameStart(r) || isAsciiDigit(r) || r == r'-' || r == r'.'
}

func isAsciiLetter(r: Rune): Bool {
    (r >= r'A' && r <= r'Z') || (r >= r'a' && r <= r'z')
}

func isAsciiDigit(r: Rune): Bool {
    r >= r'0' && r <= r'9'
}

// 字节版本：仅 ASCII 名称起始字符
func isNameStartByte(b: Byte): Bool {
    let isLowercaseAscii = b >= BY_A_LOWER && b <= BY_Z_LOWER
    let isUppercaseAscii = b >= BY_A_UPPER && b <= BY_Z_UPPER
    isLowercaseAscii || isUppercaseAscii || b == BY_UNDERSCORE || b == BY_COLON
}

func isNameCharByte(b: Byte): Bool {
    isNameStartByte(b) || isAsciiDigitByte(b) || b == BY_HYPHEN || b == BY_DOT
}

func isAsciiDigitByte(b: Byte): Bool {
    b >= BY_0 && b <= BY_9
}
