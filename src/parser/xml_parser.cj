/*
 * parser — XmlParser：Token 流 → SaxEvent 流（核心类声明与字段）
 *
 * 对应 libxml2: `parser.c` 主解析函数 + `SAX2.c` 的回调聚合逻辑，但架构完全重写：
 *   - libxml2 以"回调 + 全局状态"的推式 SAX 为主；XmlParser 以 `Iterator<SaxEvent>`
 *     暴露，惰性求值；
 *   - 命名空间、属性聚合、实体展开、嵌套深度限制都在这一层完成；
 *   - 状态严格**不可变**对外：内部虽然有 Token 缓冲与栈，但事件一旦产出就是值。
 *
 * 为了保持单个源文件不超过 300 行且每个函数圈复杂度可控，该类的**实现**被按关注点
 * 拆分到同包多个 `extend` 文件（这是 Cangjie 的语言机制：
 *  主类只能访问主类自己的成员；extend 之间 / extend 到主类的调用可自由进行）：
 *   - `xml_parser_core.cj`     — `next` / `driveOnce` / 主分派
 *   - `xml_parser_decl.cj`     — XML 声明解析
 *   - `xml_parser_element.cj`  — 元素开始 / 结束 / 命名空间绑定
 *   - `xml_parser_text.cj`     — 文本 / 实体 / Characters 合并
 *   - `xml_parser_qname.cj`    — QName / 命名空间 package 级工具函数
 *
 * 事件生成规则（与 W3C XML + XML Namespaces 1.0 / 1.1 对齐）：
 *   - 无论源文档是否有 XML 声明，事件流恒以 `StartDocument` 开始、以 `EndDocument` 结束；
 *   - `StartElement` 携带当前 `NsContext`：每次进入新元素都基于父上下文 `push` 新绑定；
 *   - 连续的 `Text` / `CharRef` / `EntityRef`（已展开）合并为一个 `Characters`；
 *   - `CDataSection` 始终独立为 `Cdata` 事件；
 *   - `Comment` / `Pi` / `Doctype` 透传。
 */
package cangjie_xml.parser

import std.collection.*
import cangjie_xml.core.*

public class XmlParser <: Iterator<SaxEvent> {
    let lexer: Lexer
    let opts: ParserOptions
    let resolver: EntityResolver

    // 元素栈：保存开始标签的 QName + 位置，用于 EndElement 词法名比对。
    let elemStack: ArrayStack<(QName, Position)>
    // NsContext 栈：与 elemStack 同步 push / pop。
    let nsStack: ArrayStack<NsContext>
    // 待产出事件队列。
    let pending: ArrayDeque<SaxEvent>

    // 待 flush 的 Characters 片段（合并连续 Text / CharRef / EntityRef）。
    var pendingCharsPos: ?Position = None
    let pendingCharsBuf: StringBuilder = StringBuilder()

    var emittedStart: Bool = false
    var emittedEnd: Bool = false
    var finished: Bool = false
    var rootEmitted: Bool = false

    // Billion-Laughs 累计计数。
    var entityExpansionCharCount: Int64 = 0
    // 预读一个 token 的缓存。
    var pendingToken: ?Token = None

    public init(lexer: Lexer, opts!: ParserOptions = ParserOptions()) {
        this.lexer = lexer
        this.opts = opts
        this.resolver = match (opts.entityResolver) {
            case Some(r) => r
            case None => DefaultEntityResolver()
        }
        this.elemStack = ArrayStack<(QName, Position)>()
        this.nsStack = ArrayStack<NsContext>()
        this.nsStack.add(NsContext.root())
        this.pending = ArrayDeque<SaxEvent>()
    }

    /** 便利构造：直接从字符串（UTF-8）构造 XmlParser。 */
    public static func fromString(s: String, opts!: ParserOptions = ParserOptions()): XmlParser {
        return XmlParser(Lexer.fromString(s, version: opts.version), opts: opts)
    }

    // next() 的真正实现由 `xml_parser_core.cj` 中 extend 块的 pump 方法提供，
    // 但 Cangjie 主类体不可直接调用 extend 方法，故经由一个包级转发函数。
    public func next(): Option<SaxEvent> {
        return pumpXmlParser(this)
    }
}

/** 包级转发函数：把 next() 委派给 extend 中的 pump 实现。 */
func pumpXmlParser(p: XmlParser): Option<SaxEvent> {
    return p.pump()
}
