package cangjie_xml.parser

import std.collection.*
import cangjie_xml.error.*

// Unicode 字符常量：避免字面量散落
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
/** BOM 的 Rune（码点）形式，区别于 `text_escape.cj` 中字节级的 `BOM_BYTE_*`。 */
const RUNE_BOM: Rune = '\u{FEFF}'

/**
 * 基于 `Rune` 数组的前向游标，供 Parser 使用。
 *
 * ## 为什么是 Rune 数组而非 String
 *
 * XML 内容以码点为最小语义单元（例如字符实体 `&#xNN;`）。把整串一次性转为
 * `Array<Rune>` 后：
 *
 * - `peek(offset)` / `advance()` 均为 O(1)；
 * - 行列定位（为 `SourcePos`）按 `Rune` 计数，与"列号以码点计"的约定吻合；
 * - 代价是一次前置分配，对 M3 典型输入规模（KB~MB）完全可接受，
 *   性能优化（流式 UTF-8 扫描）推迟到 M8 基准阶段按需展开。
 */
class SourceCursor {
    let runes: Array<Rune>
    var idx: Int64 = 0
    var line: Int64 = 1
    var column: Int64 = 1

    // 解析前输入是否以 UTF-8 BOM 起首——由 parser 在构造文档后回写到
    // `XmlDocument.hasBom`，以便 parse→write 的往返保留 BOM 语义。
    let sawBom: Bool

    init(input: String, acceptBom: Bool) {
        let tmp = ArrayList<Rune>()
        for (r in input.runes()) {
            tmp.add(r)
        }
        // 剥离 BOM（仅当起首出现 U+FEFF 时）
        var sawBomLocal = false
        if (tmp.size > 0 && tmp[0] == RUNE_BOM) {
            if (!acceptBom) {
                throw XmlParseException(
                    InvalidEncoding(SourcePos(0, 1, 1),
                        "unexpected UTF-8 BOM (acceptBom = false)"))
            }
            tmp.remove(at: 0)
            sawBomLocal = true
        }
        this.sawBom = sawBomLocal
        this.runes = tmp.toArray()
    }

    /** 是否已到末尾。 */
    func eof(): Bool {
        idx >= runes.size
    }

    /** 当前字符；EOF 时返回 None。 */
    func peek(): ?Rune {
        if (eof()) { None } else { Some(runes[idx]) }
    }

    /** 偏移 k 位处的字符；越界返回 None。 */
    func peekAt(k: Int64): ?Rune {
        let p = idx + k
        if (p < 0 || p >= runes.size) { None } else { Some(runes[p]) }
    }

    /** 消费一个字符并返回；到达 EOF 返回 None。 */
    func advance(): ?Rune {
        if (eof()) { return None }
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
        while (let Some(r) <- peek()) {
            if (isXmlWhitespace(r)) {
                advance()
            } else {
                return
            }
        }
    }

    /** 若后续以 `prefix` 起始则消费并返回 true，否则原位返回 false。 */
    func consumeIfMatch(prefix: String): Bool {
        let pr = toRuneArray(prefix)
        var i = 0
        while (i < pr.size) {
            match (peekAt(i)) {
                case Some(r) => if (r != pr[i]) { return false }
                case None => return false
            }
            i++
        }
        // 匹配成功，逐个 advance 以保持行列正确
        i = 0
        while (i < pr.size) {
            advance()
            i++
        }
        true
    }

    /** 当前坐标的 `SourcePos`（offset = 码点下标，非字节；供诊断足够）。 */
    func pos(): SourcePos {
        SourcePos(idx, line, column)
    }

    /** 从 `start`（含）到 `end`（不含）的切片拼成字符串。 */
    func sliceString(start: Int64, end: Int64): String {
        let sb = StringBuilder()
        var i = start
        while (i < end) {
            sb.append(runes[i])
            i++
        }
        sb.toString()
    }
}

/** XML 规范 §2.3 定义的空白字符集合。 */
func isXmlWhitespace(r: Rune): Bool {
    r == r' ' || r == r'\t' || r == CH_LF || r == r'\r'
}

/** 名称起始字符（简化版本：M3 采用 XML 1.0 Name 子集：字母 / 数字 / `_:-.`）。 */
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

/** 小工具：把 String 平铺为 Rune 数组（内联使用，避免依赖 internal 包）。 */
func toRuneArray(s: String): Array<Rune> {
    let list = ArrayList<Rune>()
    for (r in s.runes()) {
        list.add(r)
    }
    list.toArray()
}
