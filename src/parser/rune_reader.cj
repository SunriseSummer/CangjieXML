/*
 * parser — RuneReader：字符级输入 + 行列号跟踪 + 换行归一化
 *
 * 对应 libxml2: parserInternals.c 中的 `xmlCurrentChar` / `xmlNextChar` /
 * 输入指针步进、行号更新、`xmlParserInputRead` 换行归一化相关逻辑。
 *
 * 与 libxml2 的差异：
 *   - 这里以 **仓颉 `Rune`（Unicode 码点）** 为基本单元，已经越过"字节"与"UTF-16
 *     代码单元"的层次；解码工作交给上一迭代的 `DecodingSource`。
 *   - `peek(k)` 支持 0..=3 的回看，用于探测 `]]>` / `-->` / `?>` 多字符结束标记。
 *   - 行列号对齐 W3C XML 规范：
 *     * XML 1.0 归一化换行：`#xD #xA → #xA`、`#xD → #xA`；
 *     * XML 1.1 额外归一化：`#x85 → #xA`、`#x2028 → #xA`、`#xD #x85 → #xA`、`#xD → #xA`。
 *     详见 https://www.w3.org/TR/xml/#sec-line-ends 与 https://www.w3.org/TR/xml11/#sec-line-ends。
 *   - 所有位置以 **1-based 行、1-based 列** 暴露；`byteOffset` 保留为 `Position` 的
 *     兜底字段（归一化后的字节偏移），`charOffset` 提供精确字符级偏移。
 */
package cangjie_xml.parser

import std.collection.*
import cangjie_xml.core.*
import cangjie_xml.io.*

public class RuneReader {
    private let ds: DecodingSource
    private let version: XmlVersion
    private let sourceUri: ?String
    // 本字段保留用户指定的 XML 1.1 行为（构造时固定）。
    private let ownedSource: Bool

    // 已解码但尚未消费的字符缓冲；队首即下一个 peek(0)。
    private let lookahead: ArrayDeque<Rune>
    // 每个 lookahead 字符的预计算位置：消费 peek(k) 后 (line, column) 切换到该字符的位置。
    // 存放的是"**该字符起点**"位置，即 advance() 之前 peek(0) 所在处。
    private let positions: ArrayDeque<(Int32, Int32)>

    // 下一个尚未填入 lookahead 的字符位置（即缓冲尾部之后即将出现的字符的位置）。
    private var nextLine: Int32
    private var nextCol: Int32
    // 跨次分片读取时 prev 字符，用于 CR+LF / CR+NEL 折叠。
    // 仅记录"刚返回给调用方的最近一个字符"是否为 CR，以便跳过紧随其后的 LF/NEL。
    private var pendingCrFold: Bool
    private var eof: Bool
    // 字符级偏移（归一化之后）。
    private var charOff: Int64

    /**
     * @param source 已解码的字符源
     * @param version XML 版本（决定换行归一化规则与合法字符域）
     * @param sourceUri 用于填入 `Position.source`；默认取自 `DecodingSource` 底层源（若有）
     * @param ownedSource 关闭时是否级联关闭 `DecodingSource`
     */
    public init(
        source: DecodingSource,
        version!: XmlVersion = XmlVersion.V10,
        sourceUri!: ?String = None,
        ownedSource!: Bool = true
    ) {
        this.ds = source
        this.version = version
        this.sourceUri = sourceUri
        this.ownedSource = ownedSource
        this.lookahead = ArrayDeque<Rune>()
        this.positions = ArrayDeque<(Int32, Int32)>()
        this.nextLine = 1
        this.nextCol = 1
        this.pendingCrFold = false
        this.eof = false
        this.charOff = 0
    }

    /* ---------- 公共只读 API ---------- */

    /** 当前位置（即下次 `advance()` 将消费的那个字符的位置）。EOF 时给出文档末尾。 */
    public func currentPosition(): Position {
        ensureBuffered(1)
        let (l, c) = if (positions.isEmpty()) {
            (nextLine, nextCol)
        } else {
            positions.first.getOrThrow()
        }
        return Position(source: sourceUri, line: l, column: c, byteOffset: charOff)
    }

    /** 字符级偏移（归一化后），便于错误高亮。 */
    public func characterOffset(): Int64 {
        return charOff
    }

    /** 当前配置的 XML 版本。 */
    public prop xmlVersion: XmlVersion {
        get() {
            return version
        }
    }

    /** 源 URI。 */
    public prop source: ?String {
        get() {
            return sourceUri
        }
    }

    /** 是否到达输入末尾。注意 `peek` / `advance` 会自动推进检测，调用方也可直接用。 */
    public func isEof(): Bool {
        ensureBuffered(1)
        return lookahead.isEmpty()
    }

    /* ---------- peek / advance ---------- */

    /**
     * 窥视下一个（k=0）至后续第 k 个字符，不消费。
     * @return `None` 表示该位置已越过 EOF。
     *
     * 复杂度 O(k)；k ≤ 3 时实际无额外开销（主要供多字符分隔符探测）。
     */
    public func peek(k!: Int64 = 0): ?Rune {
        if (k < 0) {
            throw IllegalArgumentException("peek k must be >= 0")
        }
        ensureBuffered(k + 1)
        if (lookahead.size <= k) {
            return None
        }
        // ArrayDeque 不支持随机索引；遍历至第 k 个。
        var i = 0
        for (r in lookahead) {
            if (i == k) {
                return Some(r)
            }
            i += 1
        }
        return None
    }

    /** 消费下一个字符并返回；EOF 返回 `None`。 */
    public func advance(): ?Rune {
        ensureBuffered(1)
        if (lookahead.isEmpty()) {
            return None
        }
        let r = lookahead.removeFirst().getOrThrow()
        let _ = positions.removeFirst()
        charOff += 1
        return Some(r)
    }

    /**
     * 如果下一个字符等于 `r`，消费并返回 true；否则不消费，返回 false。
     * 词法器高频使用。
     */
    public func consumeIf(r: Rune): Bool {
        match (peek()) {
            case Some(x) where x == r =>
                let _ = advance()
                return true
            case _ => return false
        }
    }

    /**
     * 匹配并消费一个定长字符串。要么整体消费，要么完全不动。
     */
    public func consumeIfStr(s: String): Bool {
        let runes = ArrayList<Rune>()
        for (r in s.runes()) {
            runes.add(r)
        }
        let n = runes.size
        ensureBuffered(n)
        if (lookahead.size < n) {
            return false
        }
        var i = 0
        for (r in lookahead) {
            if (i == n) {
                break
            }
            if (r != runes[i]) {
                return false
            }
            i += 1
        }
        // 全部匹配，消费 n 个
        for (_ in 0..n) {
            let _ = advance()
        }
        return true
    }

    /* ---------- 关闭 ---------- */

    public func close(): Unit {
        if (ownedSource) {
            ds.close()
        }
    }

    /* ---------- 内部：缓冲填充 ---------- */

    /**
     * 确保 `lookahead` 至少有 `n` 个字符（或已 EOF）。
     * 每次从 `DecodingSource.readChunk()` 拉一片原始字符，执行换行归一化，
     * 同时计算每个字符的起点 (line, column)。
     */
    private func ensureBuffered(n: Int64): Unit {
        while (!eof && lookahead.size < n) {
            let piece = ds.readChunk()
            if (piece.isEmpty()) {
                if (ds.isEof()) {
                    eof = true
                    return
                }
                // 解码器暂时没有新字符（分片依赖），继续再拉。
                continue
            }
            // 逐字符喂进归一化
            for (r in piece.runes()) {
                feedNormalizedRune(r)
            }
        }
    }

    /**
     * 换行归一化 + 行列计算。
     *
     * 规则（参考 W3C XML §2.11）：
     *   XML 1.0：
     *     #xD #xA   → #xA
     *     #xD       → #xA
     *   XML 1.1：
     *     #xD #xA   → #xA
     *     #xD #x85  → #xA
     *     #xD       → #xA
     *     #x85      → #xA
     *     #x2028    → #xA
     *
     * 实现策略：遇到 CR 时置 `pendingCrFold = true`，当前 CR 归一化为 LF 推入；
     * 下一个字符若为 LF（两版本）或 NEL/0x85（仅 1.1）则丢弃。
     */
    private func feedNormalizedRune(r: Rune): Unit {
        let cp = Int32(UInt32(r))
        if (pendingCrFold) {
            pendingCrFold = false
            if (cp == CHAR_LF) {
                return
            }
            if (isV11() && cp == NEL_CODEPOINT) {
                return
            }
            // 不是被折叠的那个字符，继续正常处理
        }
        if (cp == CHAR_CR) {
            pendingCrFold = true
            pushRune(Rune(UInt32(CHAR_LF)))
            return
        }
        if (isV11() && (cp == NEL_CODEPOINT || cp == LINE_SEPARATOR_CODEPOINT)) {
            pushRune(Rune(UInt32(CHAR_LF)))
            return
        }
        pushRune(r)
    }

    private func isV11(): Bool {
        match (version) {
            case V11 => return true
            case _ => return false
        }
    }

    /** 把归一化后的字符入缓冲，同时记录其位置并推进下一字符位置。 */
    private func pushRune(r: Rune): Unit {
        positions.addLast((nextLine, nextCol))
        lookahead.addLast(r)
        let cp = Int32(UInt32(r))
        if (cp == CHAR_LF) {
            nextLine += 1
            nextCol = 1
        } else {
            nextCol += 1
        }
    }
}
