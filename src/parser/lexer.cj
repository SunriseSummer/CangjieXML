/*
 * parser — Lexer：XML 1.0 / 1.1 词法分析器（核心类声明与字段）
 *
 * 对应 libxml2: parser.c 中的词法路径。以 `Iterator<Token>` 暴露，手写状态机。
 *
 * 为了保持单个源文件不超过 300 行并控制圈复杂度，Lexer 的实现按关注点拆分到同包
 * 多个 `extend` 文件：
 *   - `lexer_dispatch.cj` — 主状态分派 + 文本 / 标签入口
 *   - `lexer_markup.cj`   — `<!-- -->` / `<![CDATA[ ]]>` / `<!DOCTYPE ...>` / `<?...?>`
 *   - `lexer_attrs.cj`    — 属性列表 + 属性值片段
 *   - `lexer_ref.cj`      — `&entity;` / `&#ref;`
 *   - `lexer_utils.cj`    — `readName` / 空白 / peekN / cp 辅助
 */
package cangjie_xml.parser

import std.collection.*
import cangjie_xml.core.*
import cangjie_xml.io.*

public class Lexer <: Iterator<Token> {
    let reader: RuneReader
    let version: XmlVersion
    var emittedEof: Bool = false
    // 词法状态：跨属性值 / DOCTYPE 内部子集时需要记忆。
    var sawXmlDecl: Bool = false
    var sawNonWhitespace: Bool = false // XML 声明只能出现在最前面
    // 元素开口深度。
    var openDepth: Int64 = 0
    // 属性值状态：Some(quote) 表示我们在属性值内，下次 next() 应该产出 Chunk / Ref / End。
    var inAttrValue: ?AttrQuote = None
    // 是否处于 open tag 内（属性列表）。
    var inOpenTag: Bool = false
    // 区分普通元素开口 vs XML 声明开口：结束符分别是 `>`/`/>` 与 `?>`。
    var xmlDeclMode: Bool = false
    // pending token 队列（少数规则如 DOCTYPE 需要一次产生多个 token）。
    let pending: ArrayDeque<Token>

    public init(reader: RuneReader) {
        this.reader = reader
        this.version = reader.xmlVersion
        this.pending = ArrayDeque<Token>()
    }

    /** 便利构造：直接从字符串（UTF-8）构造 Lexer。测试用。 */
    public static func fromString(s: String, version!: XmlVersion = XmlVersion.V10): Lexer {
        let src = StringSource(s)
        let ds = DecodingSource(src)
        let rr = RuneReader(ds, version: version)
        return Lexer(rr)
    }

    public func next(): Option<Token> {
        if (!pending.isEmpty()) {
            return pending.removeFirst()
        }
        if (emittedEof) {
            return None
        }
        let tok = lexerReadNext(this)
        match (tok) {
            case Eof(_) => emittedEof = true
            case _ => ()
        }
        return Some(tok)
    }
}

/** 包级转发：把 next() 的主分派委托给 extend 中的 readNext。 */
func lexerReadNext(l: Lexer): Token {
    return l.readNext()
}
