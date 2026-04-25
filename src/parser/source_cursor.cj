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
 * Parser 反复使用的常量前缀，预先编译成 `Array<Rune>`。
 *
 * `consumeIfMatch` 每次进入注释/CDATA/DOCTYPE 内层循环都会被调用——以前每次
 * 调用都重新走 `toRuneArray(prefix: String)` 把 String 解码并 ArrayList
 * 扩容，对长 CDATA / 长注释会是 O(n) 次小堆分配。把这几个常量前缀缓存到
 * 包级 `let` 后，热路径上变成纯指针对比 + 数值比较。
 *
 * 对应 `xml_parser.cj` 中的 String 常量；命名一致以便维护。
 */
let RUNE_COMMENT_OPEN_DASHES: Array<Rune> = [r'-', r'-']
let RUNE_CDATA_PROLOGUE: Array<Rune> = [r'[', r'C', r'D', r'A', r'T', r'A', r'[']
let RUNE_COMMENT_EPILOGUE: Array<Rune> = [r'-', r'-', r'>']
let RUNE_CDATA_EPILOGUE: Array<Rune> = [r']', r']', r'>']

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
        // 直接索引扫描——避免 peek()/advance() 路径上的 Option 装箱与重复 eof
        // 检查；同时把 LF / 非 LF 的列号更新合并到一个分支里。skipWhitespace
        // 在 parser 的几乎每个状态切换点都会调用，是真正的热路径。
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
     * 跳过所有满足 `pred(r)` 的字符。
     *
     * 与"`peek` → 判定 → `advance`"循环等价，但直接索引 `runes` 数组：
     * 省掉 `peek()` 的 `Option<Rune>` 与 `advance()` 重复的 eof 检查，
     * 是 `readName` / `parseTextBody` / `readQuotedAttrValue` 等所有
     * 内层"扫描到指定字符为止"循环的统一基础设施。
     */
    func skipWhile(pred: (Rune) -> Bool): Unit {
        let n = runes.size
        while (idx < n) {
            let r = runes[idx]
            if (!pred(r)) { return }
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
     * 若后续以 `prefix` 起始则消费并返回 true，否则原位返回 false。
     *
     * 该函数接受预编译好的 `Array<Rune>`，避免在内层循环中反复
     * `toRuneArray(prefix: String)`——参见包级 `RUNE_*` 常量。
     */
    func consumeIfMatch(prefix: Array<Rune>): Bool {
        let m = prefix.size
        // 越界快速失败：剩余字符不足时直接返回，省掉 peekAt 的 Option 装箱。
        if (idx + m > runes.size) { return false }
        var i = 0
        while (i < m) {
            if (runes[idx + i] != prefix[i]) { return false }
            i++
        }
        // 全部匹配——批量消费。前缀都是 ASCII（`-` / `[` / `]` / `>` / `C` ...），
        // 不会出现 LF，因此可以一次性更新 idx 与 column，避免逐个 advance 的
        // 分支与函数调用开销。
        idx += m
        column += m
        true
    }

    /** 当前坐标的 `SourcePos`（offset = 码点下标，非字节；供诊断足够）。 */
    func pos(): SourcePos {
        SourcePos(idx, line, column)
    }

    /**
     * 从 `start`（含）到 `end`（不含）的切片拼成字符串。
     *
     * 改为 `String(Array<Rune>)` 一次性构造——比逐 Rune `StringBuilder.append`
     * 路径少一层 Builder 状态机和分摊扩容；对每个 name / 属性名 / 文本节点都
     * 命中，是 parse 热路径上最大的常量倍率优化点之一。
     */
    func sliceString(start: Int64, end: Int64): String {
        if (end <= start) { return String.empty }
        String(runes[start..end])
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
