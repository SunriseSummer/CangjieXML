package fastxml.internal

/**
 * XML 文本转义工具。属于 internal——XML 语法层细节，不对外公开。
 *
 * 把任意 `String` 值按上下文（文本节点 / 属性值 / CDATA）转换为 XML 语法
 * 合法的形式；反方向的实体解码由 Parser 阶段的 `entity_decoder` 承担。
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
 * 字节级快速判定，无可转义内容时直接返回原串、零分配。
 */

// 集中常量定义：避免魔鬼字符串 / 魔鬼数字散落到多个函数中。

const CDATA_OPEN: String = "<![CDATA["
const CDATA_CLOSE: String = "]]>"
const CDATA_TERMINATOR: String = "]]>"
const CDATA_TERMINATOR_LEN: Int64 = 3
/** 拆分后在 `]]` 与 `>` 之间插入的分隔段，使两半分别落入相邻 CDATA。 */
const CDATA_REOPEN_AFTER_BRACKETS: String = "]]><![CDATA["

const BOM_BYTE_0: Byte = 0xEFu8
const BOM_BYTE_1: Byte = 0xBBu8
const BOM_BYTE_2: Byte = 0xBFu8

// 转义触发字节——以字节常量声明，避免在热路径上每次比较都做 `Rune → UInt8` 转换。
private const ESCAPE_AMP: Byte = 0x26u8 // '&'
private const ESCAPE_LT: Byte = 0x3Cu8  // '<'
private const ESCAPE_GT: Byte = 0x3Eu8  // '>'
private const ESCAPE_QUOT: Byte = 0x22u8 // '"'

/**
 * 把文本内容（PCDATA）按 XML 规则转义。
 *
 * 针对 `&` / `<` / `>` 做最小必要转义，不转义 `"` / `'`（文本节点无引号歧义）。
 * 若输入不包含任一待转义字符，直接返回原字符串，零分配快路径。
 *
 * 慢路径按字节扫描并以"区间拷贝 + 实体替换"成块输出：`& < >` 都是 ASCII
 * 单字节，UTF-8 多字节序列的所有字节均 ≥ 0x80，因此按字节定位边界与按
 * Rune 扫描结果一致但无需解码。
 */
public func escapeText(s: String): String {
    if (!needsTextEscape(s)) {
        return s
    }
    let n = s.size
    let sb = StringBuilder()
    var i = 0
    var lastEmit = 0
    while (i < n) {
        let b = s[i]
        if (b == ESCAPE_AMP) {
            if (i > lastEmit) { sb.append(s[lastEmit..i]) }
            sb.append("&amp;")
            lastEmit = i + 1
        } else if (b == ESCAPE_LT) {
            if (i > lastEmit) { sb.append(s[lastEmit..i]) }
            sb.append("&lt;")
            lastEmit = i + 1
        } else if (b == ESCAPE_GT) {
            if (i > lastEmit) { sb.append(s[lastEmit..i]) }
            sb.append("&gt;")
            lastEmit = i + 1
        }
        i++
    }
    if (lastEmit < n) { sb.append(s[lastEmit..n]) }
    sb.toString()
}

/**
 * 把属性值按 XML 规则转义。属性值总是以双引号 `"` 包裹，因此需转义 `"`。
 *
 * 对 `&` / `<` 必转义（`>` 在 tinyxml2 默认行为中也转义，为兼容保留）。
 * 性能策略与 `escapeText` 一致——纯字节扫描 + 区间拷贝。
 */
public func escapeAttribute(s: String): String {
    if (!needsAttrEscape(s)) {
        return s
    }
    let n = s.size
    let sb = StringBuilder()
    var i = 0
    var lastEmit = 0
    while (i < n) {
        let b = s[i]
        if (b == ESCAPE_AMP) {
            if (i > lastEmit) { sb.append(s[lastEmit..i]) }
            sb.append("&amp;")
            lastEmit = i + 1
        } else if (b == ESCAPE_LT) {
            if (i > lastEmit) { sb.append(s[lastEmit..i]) }
            sb.append("&lt;")
            lastEmit = i + 1
        } else if (b == ESCAPE_GT) {
            if (i > lastEmit) { sb.append(s[lastEmit..i]) }
            sb.append("&gt;")
            lastEmit = i + 1
        } else if (b == ESCAPE_QUOT) {
            if (i > lastEmit) { sb.append(s[lastEmit..i]) }
            sb.append("&quot;")
            lastEmit = i + 1
        }
        i++
    }
    if (lastEmit < n) { sb.append(s[lastEmit..n]) }
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
    sb.append(CDATA_OPEN)
    if (s.contains(CDATA_TERMINATOR)) {
        appendWithCdataSplit(sb, s)
    } else {
        sb.append(s)
    }
    sb.append(CDATA_CLOSE)
    sb.toString()
}

/** CDATA 内容中遇到 `]]>` 的分段处理：以字节扫描定位 `]]>`（全 ASCII，UTF-8
 *  多字节序列的所有字节均 ≥ 0x80）；命中时把 `]]` 与 `>` 分入相邻 CDATA 段。 */
func appendWithCdataSplit(sb: StringBuilder, s: String): Unit {
    let n = s.size
    var i = 0
    var lastEmit = 0
    while (i < n) {
        if (isCdataTerminatorAt(s, i, n)) {
            if (i > lastEmit) {
                sb.append(s[lastEmit..i])
            }
            // 把 `]]>` 拆成 `]]` + reopen + `>`，二者各自归属相邻的 CDATA 段。
            sb.append(s[i..i + 2])
            sb.append(CDATA_REOPEN_AFTER_BRACKETS)
            sb.append(s[i + 2..i + 3])
            i += CDATA_TERMINATOR_LEN
            lastEmit = i
        } else {
            i++
        }
    }
    if (lastEmit < n) {
        sb.append(s[lastEmit..n])
    }
}

/** 判断 `s[i..i+3]` 是否为 ASCII 字节 `]]>`。 */
func isCdataTerminatorAt(s: String, i: Int64, n: Int64): Bool {
    i + CDATA_TERMINATOR_LEN <= n
        && s[i] == 0x5Du8 // ']'
        && s[i + 1] == 0x5Du8
        && s[i + 2] == 0x3Eu8 // '>'
}

/** UTF-8 BOM 字节序列：EF BB BF。 */
public let UTF8_BOM: Array<Byte> = [BOM_BYTE_0, BOM_BYTE_1, BOM_BYTE_2]

/** UTF-8 BOM 的字符串表示（单个 U+FEFF 码点）。 */
public let UTF8_BOM_STRING: String = "\u{FEFF}"

// ----------------------------------------------------------------------
// 内部快路径：判断是否需要转义。
//
// 这两个判定函数对每个文本节点 / 每个属性值都会被调用。`& < > "` 都是 ASCII
// 单字节，UTF-8 多字节序列的所有字节均 ≥ 0x80，按字节扫描即可一次到位。
// ----------------------------------------------------------------------

func needsTextEscape(s: String): Bool {
    let n = s.size
    var i = 0
    while (i < n) {
        let b = s[i]
        if (b == ESCAPE_AMP || b == ESCAPE_LT || b == ESCAPE_GT) { return true }
        i++
    }
    false
}

func needsAttrEscape(s: String): Bool {
    let n = s.size
    var i = 0
    while (i < n) {
        let b = s[i]
        if (b == ESCAPE_AMP || b == ESCAPE_LT || b == ESCAPE_GT || b == ESCAPE_QUOT) {
            return true
        }
        i++
    }
    false
}
