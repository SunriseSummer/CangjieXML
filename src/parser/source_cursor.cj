package fastxml.parser

import std.collection.*
import fastxml.error.*

// Parser 中常用的单字符 Rune 常量，集中声明便于复用。
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
/** UTF-8 BOM 的码点形式，对应 `text_escape.cj` 中的字节常量。 */
const RUNE_BOM: Rune = '\u{FEFF}'
const ASCII_LIMIT_BYTE: Byte = 0x80u8

/**
 * 注释 / CDATA / DOCTYPE 等结构关键串的预编译 `Array<Rune>` 形式，
 * 供 [SourceCursor.consumeIfMatch] 在热路径上避免重复字符串解码。
 */
let RUNE_COMMENT_OPEN_DASHES: Array<Rune> = [r'-', r'-']
let RUNE_CDATA_PROLOGUE: Array<Rune> = [r'[', r'C', r'D', r'A', r'T', r'A', r'[']
let RUNE_COMMENT_EPILOGUE: Array<Rune> = [r'-', r'-', r'>']
let RUNE_CDATA_EPILOGUE: Array<Rune> = [r']', r']', r'>']

/**
 * 基于 `Rune` 数组的前向游标，供 Parser 使用。
 *
 * 输入字符串在构造时一次性转为 `Array<Rune>`，使 `peek` / `advance` 与按码点
 * 计数的行列定位均为 O(1)。同时为纯 ASCII 输入提供快路径：跳过 `String.runes()`
 * 解码迭代器；并保留原始 `String` 供 [sliceString] 在 ASCII 路径上直接切片，
 * 避免 `String(runes[start..end])` 的 UTF-8 重编码。
 */
class SourceCursor {
    let runes: Array<Rune>
    /** 与 [runes] 等长的原串：ASCII 路径 byte index == rune index，可直接切片。 */
    let source: String
    /** 输入是否纯 ASCII（含构造时跳过 BOM 后再判定）。 */
    let isAsciiOnly: Bool
    var idx: Int64 = 0
    var line: Int64 = 1
    var column: Int64 = 1

    // 输入是否以 UTF-8 BOM 起首，由 parser 在构造文档后回写到
    // `XmlDocument.hasBom`，使 parse→write 往返保留 BOM 语义。
    let sawBom: Bool

    init(input: String, acceptBom: Bool) {
        if (isAsciiInput(input)) {
            this.sawBom = false
            this.source = input
            this.isAsciiOnly = true
            this.runes = Array<Rune>(input.size, {i => Rune(UInt32(input[i]))})
            return
        }
        // UTF-8 中字节数 ≥ 码点数，用 `input.size` 作上界一次到位预分配。
        let tmp = ArrayList<Rune>(input.size)
        for (r in input.runes()) {
            tmp.add(r)
        }
        var sawBomLocal = false
        var trimmedSource = input
        if (tmp.size > 0 && tmp[0] == RUNE_BOM) {
            if (!acceptBom) {
                throw XmlParseException(InvalidEncoding(SourcePos(0, 1, 1), "unexpected UTF-8 BOM (acceptBom = false)"))
            }
            tmp.remove(at: 0)
            sawBomLocal = true
            // BOM 是 3 字节序列 EF BB BF；剥掉后续 source 与 runes 重新对齐。
            trimmedSource = input[3..input.size]
        }
        this.sawBom = sawBomLocal
        this.runes = tmp.toArray()
        this.source = trimmedSource
        this.isAsciiOnly = false
    }

    private static func isAsciiInput(input: String): Bool {
        let n = input.size
        var i = 0
        while (i < n) {
            if (input[i] >= ASCII_LIMIT_BYTE) {
                return false
            }
            i++
        }
        true
    }

    /** 是否已到末尾。 */
    func eof(): Bool {
        idx >= runes.size
    }

    /** 当前字符；EOF 时返回 None。 */
    func peek(): ?Rune {
        if (eof()) {
            None
        } else {
            Some(runes[idx])
        }
    }

    /** 当前字符是否等于 `ch`；EOF 时返回 false，供 parser 热路径绕开 Option。 */
    func matches(ch: Rune): Bool {
        idx < runes.size && runes[idx] == ch
    }

    /** 偏移 `k` 位处字符是否等于 `ch`；越界时返回 false。 */
    func matchesAt(k: Int64, ch: Rune): Bool {
        let p = idx + k
        p >= 0 && p < runes.size && runes[p] == ch
    }

    /** 消费一个字符并返回；到达 EOF 返回 None。 */
    func advance(): ?Rune {
        if (eof()) {
            return None
        }
        let r = runes[idx]
        idx++
        if (r == CH_LF) {
            line++
            column = 1
        } else {
            column++
        }
        Some(r)
    }

    /** 跳过所有 XML 空白字符（空格 / 制表 / LF / CR）。 */
    func skipWhitespace(): Unit {
        let n = runes.size
        while (idx < n) {
            let r = runes[idx]
            if (r == CH_LF) {
                idx++
                line++
                column = 1
            } else if (r == r' ' || r == r'\t' || r == r'\r') {
                idx++
                column++
            } else {
                return
            }
        }
    }

    /**
     * 跳过所有 `isNameChar(r)` 字符，专为 [readName] 等热路径设计。
     *
     * `isNameChar` 判定按 ASCII 范围内联展开，避免把谓词作为闭包传入引发的
     * 堆分配；Name 字符不可能是 LF，因此不维护行号。
     */
    func skipNameChars(): Unit {
        let n = runes.size
        while (idx < n) {
            let r = runes[idx]
            var isName = false
            if (r >= r'a' && r <= r'z') {
                isName = true
            } else if (r >= r'A' && r <= r'Z') {
                isName = true
            } else if (r >= r'0' && r <= r'9') {
                isName = true
            } else if (r == r'_' || r == r':' || r == r'-' || r == r'.') {
                isName = true
            }
            if (isName) {
                idx++
                column++
            } else {
                return
            }
        }
    }

    /** 扫描到下一个 `<` 或 EOF；供 `parseTextBody` 使用，遇到 LF 时维护行号。 */
    func skipUntilLt(): Unit {
        let n = runes.size
        while (idx < n) {
            let r = runes[idx]
            if (r == CH_LT) {
                return
            }
            idx++
            if (r == CH_LF) {
                line++
                column = 1
            } else {
                column++
            }
        }
    }

    /**
     * 扫描属性值字符直到遇到 `quoteCh`、`<` 或 EOF。
     *
     * 返回 `true` 表示遇到引号成功停下；`false` 表示遇到 `<` 或 EOF，
     * 由调用方进一步区分并报错。
     */
    func skipAttrValueChars(quoteCh: Rune): Bool {
        let n = runes.size
        while (idx < n) {
            let r = runes[idx]
            if (r == quoteCh) {
                return true
            }
            if (r == CH_LT) {
                return false
            }
            idx++
            if (r == CH_LF) {
                line++
                column = 1
            } else {
                column++
            }
        }
        false
    }

    /**
     * 若后续以 `prefix` 起始则消费并返回 true，否则原位返回 false。
     *
     * 使用包级预编译的 `RUNE_*` 常量做一次性比较；前缀全为 ASCII，不可能含 LF，
     * 匹配成功后批量更新 `idx` 与 `column`。
     */
    func consumeIfMatch(prefix: Array<Rune>): Bool {
        let m = prefix.size
        if (idx + m > runes.size) {
            return false
        }
        var i = 0
        while (i < m) {
            if (runes[idx + i] != prefix[i]) {
                return false
            }
            i++
        }
        idx += m
        column += m
        true
    }

    /** 当前坐标的 `SourcePos`（offset 以码点计，行列从 1 起）。 */
    func pos(): SourcePos {
        SourcePos(idx, line, column)
    }

    /**
     * 取 `[start, end)` 区间的子串。
     *
     * - **ASCII 路径**：byte index == rune index，直接走 `source[start..end]`，
     *   避免 `String(runes[start..end])` 的 Rune 数组切片 + UTF-8 重编码。
     * - **非 ASCII 路径**：rune index 与 byte index 不一致，回退到从 Rune 数组重建。
     */
    func sliceString(start: Int64, end: Int64): String {
        if (end <= start) {
            return String.empty
        }
        if (isAsciiOnly) {
            return source[start..end]
        }
        String(runes[start..end])
    }
}

/** XML 规范 §2.3 定义的空白字符集合。 */
func isXmlWhitespace(r: Rune): Bool {
    r == r' ' || r == r'\t' || r == CH_LF || r == r'\r'
}

/** 名称起始字符（XML 1.0 Name 子集：字母 / `_` / `:`）。 */
func isNameStart(r: Rune): Bool {
    isAsciiLetter(r) || r == r'_' || r == r':'
}

/** 名称尾随字符——在起始字符基础上额外允许数字 / `-` / `.`。 */
func isNameChar(r: Rune): Bool {
    isNameStart(r) || isAsciiDigit(r) || r == r'-' || r == r'.'
}

func isAsciiLetter(r: Rune): Bool {
    (r >= r'A' && r <= r'Z') || (r >= r'a' && r <= r'z')
}

func isAsciiDigit(r: Rune): Bool {
    r >= r'0' && r <= r'9'
}
