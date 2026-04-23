/*
 * parser — XmlParser：Token 流 → SaxEvent 流
 *
 * 对应 libxml2: `parser.c` 主解析函数 + `SAX2.c` 的回调聚合逻辑（`xmlSAX2StartElementNs`
 * / `xmlSAX2EndElementNs` / `xmlSAX2Characters` 等），但架构完全重写：
 *
 *   - libxml2 以"回调 + 全局状态"的推式 SAX 为主；XmlParser 以 `Iterator<SaxEvent>`
 *     暴露，惰性求值；
 *   - 命名空间、属性聚合、实体展开、嵌套深度限制都在这一层完成；
 *   - 状态严格**不可变**对外：内部虽然有 Token 缓冲与栈，但事件一旦产出就是值。
 *
 * 事件生成规则（与 W3C XML + XML Namespaces 1.0 / 1.1 对齐）：
 *   - 无论源文档是否有 XML 声明，事件流恒以 `StartDocument` 开始、以 `EndDocument`
 *     结束；
 *   - `<?xml...?>` 的属性（version/encoding/standalone）在同一事件内通过 `XmlDecl`
 *     结构体给出，非独立事件；
 *   - `StartElement` 携带当前 `NsContext`：每次进入新元素都基于父上下文 `push`
 *     新绑定；事件消费方可安全保存该上下文；
 *   - 连续的 `Text` / `CharRef` / `EntityRef`（已展开）合并为一个 `Characters`；
 *   - `CDataSection` 始终独立为 `Cdata` 事件（不合并为 `Characters`，以便保留语义）；
 *   - `Comment` / `Pi` / `Doctype` 透传。
 */
package cangjie_xml.parser

import std.collection.*
import cangjie_xml.core.*

public class XmlParser <: Iterator<SaxEvent> {
    private let lexer: Lexer
    private let opts: ParserOptions
    private let resolver: EntityResolver
    // 元素栈：每层保存 (qname, 元素开始位置, 引入的命名空间是否为本元素新绑定)。
    // 仅 qname 与 position 需要保留供 EndElement 比对；NsContext 通过 nsStack 单独管理。
    private let elemStack: ArrayStack<(QName, Position)>
    // NsContext 栈顶；每次 StartElement 推新上下文，EndElement 恢复父上下文。
    // 使用独立栈而非依赖 elemStack 中的 NsContext 指针以适配 CDATA / Characters
    // 等位于元素内但不改变 NS 的事件。
    private let nsStack: ArrayStack<NsContext>
    // 待产出事件队列：单个 token 可能诱发多个事件（如 XmlDecl + 空白 Characters）。
    private let pending: ArrayDeque<SaxEvent>
    // 已产出 StartDocument？
    private var emittedStart: Bool
    // 已产出 EndDocument？
    private var emittedEnd: Bool
    // 解析是否已彻底终止（EOF 或致命错误）
    private var finished: Bool
    // 根元素是否已经出现（用于 "单根" 校验）
    private var rootEmitted: Bool
    // 字符级实体展开总量（Billion Laughs 防护）
    private var entityExpansionCharCount: Int64
    // 已读但尚未消费的 token（用于 peek）
    private var pendingToken: ?Token

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
        this.emittedStart = false
        this.emittedEnd = false
        this.finished = false
        this.rootEmitted = false
        this.entityExpansionCharCount = 0
        this.pendingToken = None
    }

    /** 便利构造：直接从字符串（UTF-8）构造 XmlParser。 */
    public static func fromString(s: String, opts!: ParserOptions = ParserOptions()): XmlParser {
        return XmlParser(Lexer.fromString(s, version: opts.version), opts: opts)
    }

    public func next(): Option<SaxEvent> {
        while (true) {
            if (!pending.isEmpty()) {
                return pending.removeFirst()
            }
            if (finished) {
                return None
            }
            try {
                driveOnce()
            } catch (e: XmlException) {
                finished = true
                // 非容错模式：直接上抛（由调用方决定处理）
                if (!opts.recover) {
                    throw e
                }
                // 容错模式（Phase 3c 完整实现）：目前降级为一次性 ParseError + EndDocument
                pending.addLast(SaxEvent.ParseError(e.error))
                pending.addLast(SaxEvent.EndDocument(Position.unknown()))
            }
            // 若 driveOnce 只向字符缓冲区追加内容，pending 可能仍为空——继续循环
            // 直到出现下一个真正可产出的事件，或到达 EOF。
        }
        return None
    }

    /* ---------- 主循环 ---------- */

    private func driveOnce(): Unit {
        // 先确保 StartDocument 已经出现
        if (!emittedStart) {
            produceStartDocumentIfNeeded()
            if (!pending.isEmpty()) {
                return
            }
        }
        // 若根元素已结束且未出 EndDocument，处理尾随事件直到 EOF
        let tok = readToken()
        handleToken(tok)
    }

    private func produceStartDocumentIfNeeded(): Unit {
        // 向前看一个 token：若是 XmlDeclStart，则解析 XML 声明并一起产出 StartDocument；
        // 否则合成默认 StartDocument。
        let first = peekToken()
        match (first) {
            case XmlDeclStart(p) =>
                let _ = readToken() // 消费 XmlDeclStart
                let decl = parseXmlDecl(p)
                pending.addLast(SaxEvent.StartDocument(decl))
                emittedStart = true
            case _ =>
                let pos = match (first) {
                    case Eof(p) => p
                    case t => t.position()
                }
                pending.addLast(SaxEvent.StartDocument(XmlDecl(position: pos)))
                emittedStart = true
        }
    }

    /**
     * 解析 XML 声明的剩余 token，消费到 XmlDeclEnd 为止。
     * 返回完整 `XmlDecl`。
     */
    private func parseXmlDecl(startPos: Position): XmlDecl {
        var version = "1.0"
        var sawVersion = false
        var encoding: ?String = None
        var standalone = Standalone.Unspecified
        var attrSeen = HashSet<String>()
        // 循环解析属性名 / 等号 / 值直到 XmlDeclEnd
        while (true) {
            let tok = readToken()
            match (tok) {
                case XmlDeclEnd(_) => break
                case AttrName(p, name) =>
                    if (attrSeen.contains(name)) {
                        throw XmlException(XmlError.Malformed(p, "duplicate XML declaration attribute '${name}'"))
                    }
                    attrSeen.add(name)
                    consumeExpectedToken({ t: Token =>
                        match (t) {
                            case AttrEq(_) => return true
                            case _ => return false
                        }
                    }, "'=' after XML declaration attribute")
                    let value = readQuotedAttrValueLiteral(p)
                    match (name) {
                        case "version" =>
                            if (value != "1.0" && value != "1.1") {
                                throw XmlException(XmlError.Malformed(p, "unsupported XML version '${value}'"))
                            }
                            // attribute order check: version must come first
                            if (encoding.isSome() || !isStandaloneUnspecified(standalone)) {
                                throw XmlException(XmlError.Malformed(p, "'version' must be the first attribute of XML declaration"))
                            }
                            version = value
                            sawVersion = true
                        case "encoding" =>
                            if (!sawVersion) {
                                throw XmlException(XmlError.Malformed(p, "'encoding' must follow 'version' in XML declaration"))
                            }
                            if (!isStandaloneUnspecified(standalone)) {
                                throw XmlException(XmlError.Malformed(p, "'encoding' must precede 'standalone' in XML declaration"))
                            }
                            if (!isValidEncodingName(value)) {
                                throw XmlException(XmlError.Malformed(p, "invalid encoding name '${value}'"))
                            }
                            encoding = Some(value)
                        case "standalone" =>
                            if (!sawVersion) {
                                throw XmlException(XmlError.Malformed(p, "'standalone' must follow 'version' in XML declaration"))
                            }
                            match (value) {
                                case "yes" => standalone = Standalone.Yes
                                case "no" => standalone = Standalone.No
                                case _ =>
                                    throw XmlException(XmlError.Malformed(p, "'standalone' must be 'yes' or 'no'"))
                            }
                        case _ =>
                            throw XmlException(XmlError.Malformed(p, "unexpected attribute '${name}' in XML declaration"))
                    }
                case t =>
                    throw XmlException(XmlError.Malformed(t.position(), "unexpected token in XML declaration"))
            }
        }
        if (!sawVersion) {
            throw XmlException(XmlError.Malformed(startPos, "XML declaration missing 'version'"))
        }
        return XmlDecl(
            version: version,
            encoding: encoding,
            standalone: standalone,
            position: startPos
        )
    }

    private static func isStandaloneUnspecified(s: Standalone): Bool {
        match (s) {
            case Unspecified => return true
            case _ => return false
        }
    }

    /** 把 AttrValueStart + (Chunk|EntityRef|CharRef)* + AttrValueEnd 序列折叠成字面值字符串。
     *  XML 声明 / 普通属性共用此路径（但 XML 声明值不含实体引用，违反则报错）。 */
    private func readQuotedAttrValueLiteral(attrNamePos: Position): String {
        consumeExpectedToken({ t: Token =>
            match (t) {
                case AttrValueStart(_, _) => return true
                case _ => return false
            }
        }, "opening quote of attribute value")
        let sb = StringBuilder()
        while (true) {
            let t = readToken()
            match (t) {
                case AttrValueEnd(_, _) => break
                case AttrValueChunk(_, s) => sb.append(s)
                case CharRef(_, cp) =>
                    sb.append(Rune(UInt32(cp)))
                    bumpEntityExpansion(1, attrNamePos)
                case EntityRef(p, name) =>
                    let expanded = expandEntityText(name, p)
                    sb.append(expanded)
                case other =>
                    throw XmlException(XmlError.Malformed(other.position(), "unexpected token in attribute value"))
            }
        }
        return sb.toString()
    }

    /** 为预定义 / 用户文本实体取展开字符串，并做 Billion-Laughs 计数。 */
    private func expandEntityText(name: String, pos: Position): String {
        match (resolver.resolveEntity(name)) {
            case Some(Text(s)) =>
                bumpEntityExpansion(Int64(s.size), pos)
                return s
            case Some(External(_, _, _)) =>
                throw XmlException(XmlError.Malformed(pos, "external entity '${name}' not supported in this iteration"))
            case None =>
                throw XmlException(XmlError.Malformed(pos, "undefined entity '${name}'"))
        }
    }

    private func bumpEntityExpansion(n: Int64, pos: Position): Unit {
        entityExpansionCharCount += n
        if (entityExpansionCharCount > opts.maxEntityExpansion) {
            throw XmlException(XmlError.LimitExceeded(pos, "entity expansion total exceeded ${opts.maxEntityExpansion}"))
        }
    }

    /* ---------- 通用 token 处理 ---------- */

    private func handleToken(t: Token): Unit {
        match (t) {
            case Eof(p) =>
                if (!elemStack.isEmpty()) {
                    throw XmlException(XmlError.UnexpectedEof(p, "unexpected EOF inside element"))
                }
                if (!emittedEnd) {
                    pending.addLast(SaxEvent.EndDocument(p))
                    emittedEnd = true
                }
                finished = true
            case DoctypeStart(p, name) =>
                // 读取后续 DoctypeEnd
                let e = readToken()
                match (e) {
                    case DoctypeEnd(_) => ()
                    case other =>
                        throw XmlException(XmlError.Malformed(other.position(), "expected DoctypeEnd"))
                }
                pending.addLast(SaxEvent.Doctype(p, name))
            case Token.Comment(p, s) => pending.addLast(SaxEvent.CommentEvent(p, s))
            case Token.ProcessingInstruction(p, tgt, data) => pending.addLast(SaxEvent.Pi(p, tgt, data))
            case Token.CDataSection(p, s) =>
                if (elemStack.isEmpty()) {
                    throw XmlException(XmlError.Malformed(p, "CDATA section outside of element"))
                }
                pending.addLast(SaxEvent.Cdata(p, s))
            case ElementOpenStart(p, rawName) =>
                handleElementStart(p, rawName)
            case ElementClose(p, rawName) =>
                handleElementEnd(p, rawName)
            case Text(p, s) =>
                handleText(p, s)
            case CharRef(p, cp) =>
                handleText(p, Rune(UInt32(cp)).toString())
                bumpEntityExpansion(1, p)
            case EntityRef(p, name) =>
                handleEntityRef(p, name)
            case XmlDeclStart(p) =>
                throw XmlException(XmlError.Malformed(p, "XML declaration not at start of document"))
            case XmlDeclEnd(p) =>
                throw XmlException(XmlError.Malformed(p, "stray '?>'"))
            case ElementOpenEnd(p) =>
                throw XmlException(XmlError.Malformed(p, "stray '>'"))
            case ElementSelfClose(p) =>
                throw XmlException(XmlError.Malformed(p, "stray '/>'"))
            case AttrName(p, _) =>
                throw XmlException(XmlError.Malformed(p, "stray attribute"))
            case AttrEq(p) =>
                throw XmlException(XmlError.Malformed(p, "stray '='"))
            case AttrValueStart(p, _) =>
                throw XmlException(XmlError.Malformed(p, "stray quote"))
            case AttrValueChunk(p, _) =>
                throw XmlException(XmlError.Malformed(p, "stray chunk"))
            case AttrValueEnd(p, _) =>
                throw XmlException(XmlError.Malformed(p, "stray quote"))
            case DoctypeEnd(p) =>
                throw XmlException(XmlError.Malformed(p, "stray DOCTYPE end"))
        }
    }

    /* ---------- 元素处理 ---------- */

    private func handleElementStart(startPos: Position, rawName: String): Unit {
        // 1) 收集属性
        let rawAttrs = ArrayList<(String, Position, String)>()
        var selfClose = false
        while (true) {
            let t = readToken()
            match (t) {
                case ElementOpenEnd(_) => break
                case ElementSelfClose(_) =>
                    selfClose = true
                    break
                case AttrName(p, aname) =>
                    consumeExpectedToken({ x: Token =>
                        match (x) {
                            case AttrEq(_) => return true
                            case _ => return false
                        }
                    }, "'=' after attribute name")
                    let value = readQuotedAttrValueLiteral(p)
                    rawAttrs.add((aname, p, value))
                case other =>
                    throw XmlException(XmlError.Malformed(other.position(), "unexpected token in start tag"))
            }
        }
        // 2) 深度检查
        if (Int64(elemStack.size) + 1 > opts.maxDepth) {
            throw XmlException(XmlError.LimitExceeded(startPos, "element depth exceeded ${opts.maxDepth}"))
        }
        if (rootEmitted && elemStack.isEmpty()) {
            throw XmlException(XmlError.Malformed(startPos, "multiple root elements"))
        }
        // 3) 构造新 NsContext（先把所有 xmlns 绑定 push 进去），供元素自身名字解析
        let parentNs = nsStack.peek().getOrThrow()
        var newNs = parentNs
        for ((aname, apos, avalue) in rawAttrs) {
            match (nsDeclKind(aname)) {
                case 0 => ()
                case 1 =>
                    // 默认命名空间
                    validateNsValue(avalue, apos)
                    newNs = newNs.push(None<String>, emptyToNone(avalue))
                case 2 =>
                    let pfx = aname[6..] // after "xmlns:"
                    if (pfx == "xmlns") {
                        throw XmlException(XmlError.NamespaceError(apos, "cannot redeclare 'xmlns' prefix"))
                    }
                    if (pfx == "xml") {
                        if (avalue != XML_NAMESPACE_URI) {
                            throw XmlException(XmlError.NamespaceError(apos, "'xml' prefix must bind to ${XML_NAMESPACE_URI}"))
                        }
                        // 允许冗余声明；不再 push
                    } else {
                        if (avalue == XML_NAMESPACE_URI) {
                            throw XmlException(XmlError.NamespaceError(apos, "only 'xml' prefix may bind to XML namespace URI"))
                        }
                        if (avalue == XMLNS_NAMESPACE_URI) {
                            throw XmlException(XmlError.NamespaceError(apos, "no prefix may bind to xmlns namespace URI"))
                        }
                        validateNsValue(avalue, apos)
                        newNs = newNs.push(Some(pfx), emptyToNone(avalue))
                    }
                case _ => ()
            }
        }
        // 4) 解析元素 QName
        let elemQName = resolveQName(rawName, newNs, startPos, isAttribute: false)
        // 5) 解析属性 QName，检查唯一性（扩展名 + 本地名的组合）
        let attrs = ArrayList<Attribute>()
        let seen = HashSet<String>()
        for ((aname, apos, avalue) in rawAttrs) {
            let declKind = nsDeclKind(aname)
            let isNsDecl = declKind != 0
            let attrQName = if (isNsDecl) {
                // xmlns / xmlns:prefix 作为属性本身仍保留原始结构：
                // - xmlns          → QName(local="xmlns", prefix=None, uri=XMLNS_NS)
                // - xmlns:foo      → QName(local="foo",   prefix="xmlns", uri=XMLNS_NS)
                if (declKind == 1) {
                    QName("xmlns", uri: XMLNS_NAMESPACE_URI)
                } else {
                    QName(aname[6..], prefix: "xmlns", uri: XMLNS_NAMESPACE_URI)
                }
            } else {
                resolveQName(aname, newNs, apos, isAttribute: true)
            }
            let key = attrQName.expanded()
            if (seen.contains(key)) {
                throw XmlException(XmlError.Malformed(apos, "duplicate attribute '${aname}'"))
            }
            seen.add(key)
            let attr = internQName(attrQName)
            attrs.add(Attribute(attr, avalue, position: apos, isNamespaceDeclaration: isNsDecl))
        }
        // 6) 产出事件
        let internedElem = internQName(elemQName)
        pending.addLast(SaxEvent.StartElement(startPos, internedElem, attrs.toArray(), newNs))
        if (!rootEmitted) {
            rootEmitted = true
        }
        if (selfClose) {
            pending.addLast(SaxEvent.EndElement(startPos, internedElem))
        } else {
            elemStack.add((internedElem, startPos))
            nsStack.add(newNs)
        }
    }

    private func handleElementEnd(pos: Position, rawName: String): Unit {
        match (elemStack.remove()) {
            case None =>
                throw XmlException(XmlError.Malformed(pos, "end tag '${rawName}' without matching start tag"))
            case Some((openQ, _)) =>
                let _ = nsStack.remove()
                // 以栈顶（pop 之后的新栈顶）的命名空间来解析此结束标签名。
                // 但语义上 libxml2 与 W3C 都要求与开始标签的词法名一致即可。
                // 我们按更严格的"词法名一致"来比对（prefix:local 完全相等）。
                let expected = openQ.lexical()
                if (rawName != expected) {
                    throw XmlException(XmlError.Malformed(pos, "end tag '${rawName}' does not match start tag '${expected}'"))
                }
                pending.addLast(SaxEvent.EndElement(pos, openQ))
        }
    }

    private func handleText(pos: Position, s: String): Unit {
        if (s.size == 0) {
            return
        }
        if (elemStack.isEmpty()) {
            // 根元素外：只允许空白
            if (!isAllXmlWhitespace(s)) {
                throw XmlException(XmlError.Malformed(pos, "non-whitespace text outside root element"))
            }
            // 在文档序言/跋中：keepBlanks 控制是否产出空白（很少用；我们统一跳过）
            return
        }
        if (!opts.keepBlanks && isAllXmlWhitespace(s)) {
            return
        }
        mergeOrEmitCharacters(pos, s)
    }

    private func handleEntityRef(pos: Position, name: String): Unit {
        if (elemStack.isEmpty()) {
            throw XmlException(XmlError.Malformed(pos, "entity reference outside root element"))
        }
        if (!opts.substituteEntities) {
            flushPendingCharacters()
            pending.addLast(SaxEvent.EntityReference(pos, name))
            return
        }
        let text = expandEntityText(name, pos)
        if (text.size != 0) {
            mergeOrEmitCharacters(pos, text)
        }
    }

    /* ---------- Characters 事件合并 ---------- */

    // pending 队列尾部若是 Characters，将新片段追加合并
    private func mergeOrEmitCharacters(pos: Position, s: String): Unit {
        // 只能在真正已进入 pending 的 Characters 上合并。为简化，使用一个单独的
        // "待 flush 缓冲"。
        pendingCharsPos = match (pendingCharsPos) {
            case None => Some(pos)
            case other => other
        }
        pendingCharsBuf.append(s)
    }

    private var pendingCharsPos: ?Position = None
    private let pendingCharsBuf: StringBuilder = StringBuilder()

    private func flushPendingCharacters(): Unit {
        match (pendingCharsPos) {
            case None => return
            case Some(p) =>
                let text = pendingCharsBuf.toString()
                if (text.size > 0) {
                    pending.addLast(SaxEvent.Characters(p, text))
                }
                pendingCharsBuf.reset()
                pendingCharsPos = None
        }
    }

    /* ---------- token 读取 ---------- */

    private func readToken(): Token {
        match (pendingToken) {
            case Some(t) =>
                pendingToken = None
                postReadHook(t)
                return t
            case None => ()
        }
        let t = match (lexer.next()) {
            case Some(x) => x
            case None =>
                return Token.Eof(lastKnownPosition())
        }
        postReadHook(t)
        return t
    }

    /** 读取 token 前先把 pending Characters flush 掉（除了文本连续合并场景）。 */
    private func postReadHook(t: Token): Unit {
        match (t) {
            // 合并连续文本：Text / CharRef / 预定义实体都会先走 handleText / handleEntityRef，
            // 它们自己会把字符 append 到 pendingCharsBuf；只有当遇到"分隔事件"时才 flush。
            case Text(_, _) => ()
            case CharRef(_, _) => ()
            case EntityRef(_, _) => ()
            case _ => flushPendingCharacters()
        }
    }

    private func peekToken(): Token {
        match (pendingToken) {
            case Some(t) => return t
            case None => ()
        }
        let t = match (lexer.next()) {
            case Some(x) => x
            case None => Token.Eof(lastKnownPosition())
        }
        pendingToken = Some(t)
        return t
    }

    private func consumeExpectedToken(pred: (Token) -> Bool, what: String): Unit {
        let t = readToken()
        if (!pred(t)) {
            throw XmlException(XmlError.Malformed(t.position(), "expected ${what}"))
        }
    }

    private func lastKnownPosition(): Position {
        // 没有更好的来源时给 unknown
        return Position.unknown()
    }

    /* ---------- 命名空间 / QName 解析 ---------- */

    /**
     * 0 = 不是 xmlns 声明
     * 1 = 默认命名空间声明 "xmlns"
     * 2 = 前缀命名空间声明 "xmlns:..."
     */
    private static func nsDeclKind(name: String): Int32 {
        if (name == "xmlns") {
            return 1
        }
        if (name.size > 6) {
            // startsWith "xmlns:"
            var ok = true
            let prefix = "xmlns:"
            var i = 0
            for (r in prefix.runes()) {
                let n = name[i]
                if (UInt32(r) != UInt32(n)) {
                    ok = false
                    break
                }
                i += 1
            }
            if (ok) {
                return 2
            }
        }
        return 0
    }

    private static func emptyToNone(s: String): ?String {
        if (s.size == 0) {
            return None
        }
        return Some(s)
    }

    /** 命名空间 URI 值的基本合法性（非空串时走此路径；允许 `None`/空串表示解绑）。 */
    private static func validateNsValue(s: String, pos: Position): Unit {
        // XML Namespaces 要求 URI 只需是 URI-Reference；这里仅拒绝含 NUL 等非 XML 字符
        for (r in s.runes()) {
            if (UInt32(r) == 0u32) {
                throw XmlException(XmlError.NamespaceError(pos, "namespace URI contains NUL"))
            }
        }
    }

    /** 把 "prefix:local" / "local" 解析为 QName，并利用 ns 解析 URI。 */
    private func resolveQName(
        raw: String,
        ns: NsContext,
        pos: Position,
        isAttribute!: Bool
    ): QName {
        // 切分
        var prefix: ?String = None
        var local = raw
        var colonIdx = -1
        var i = 0
        for (r in raw.runes()) {
            if (UInt32(r) == 0x3Au32) { // ':'
                colonIdx = i
                break
            }
            i += 1
        }
        if (colonIdx >= 0) {
            // local & prefix 切分（按 Rune 索引计算字节偏移不可靠——这里用 String 遍历累加字节）
            // 简化：再遍历一次按字节累加
            var byteOff = 0
            var j = 0
            for (r in raw.runes()) {
                if (j == colonIdx) {
                    break
                }
                byteOff += runeByteLen(r)
                j += 1
            }
            let p = raw[..byteOff]
            let l = raw[(byteOff + 1)..]
            if (p.size == 0 || l.size == 0) {
                throw XmlException(XmlError.NamespaceError(pos, "invalid qualified name '${raw}'"))
            }
            // local 不能再含 ':'（NCName 约束）
            for (r in l.runes()) {
                if (UInt32(r) == 0x3Au32) {
                    throw XmlException(XmlError.NamespaceError(pos, "qualified name '${raw}' has multiple colons"))
                }
            }
            prefix = Some(p)
            local = l
        }
        // 解析 URI
        let uri: ?String = match (prefix) {
            case Some(p) =>
                match (ns.resolve(Some(p))) {
                    case Some(u) => Some(u)
                    case None =>
                        throw XmlException(XmlError.NamespaceError(pos, "undefined namespace prefix '${p}'"))
                }
            case None =>
                if (isAttribute) {
                    // W3C Namespaces §6.2：默认命名空间不应用于属性
                    None
                } else {
                    ns.defaultNs()
                }
        }
        return QName(local, prefix: prefix, uri: uri)
    }

    /** 字符的 UTF-8 字节数。 */
    private static func runeByteLen(r: Rune): Int64 {
        let cp = UInt32(r)
        if (cp < 0x80u32) {
            return 1
        }
        if (cp < 0x800u32) {
            return 2
        }
        if (cp < 0x10000u32) {
            return 3
        }
        return 4
    }

    /** 若 options 配置了 NameTable，则对 QName 的 local/prefix 做 intern。 */
    private func internQName(q: QName): QName {
        match (opts.nameTable) {
            case None => return q
            case Some(nt) =>
                let localI = nt.intern(q.localName)
                let prefixI = match (q.prefix) {
                    case Some(p) => Some(nt.intern(p))
                    case None => None<String>
                }
                return QName(localI, prefix: prefixI, uri: q.uri)
        }
    }
}

/* ---------- helpers 暴露在 package 级 ---------- */

func isAllXmlWhitespace(s: String): Bool {
    for (r in s.runes()) {
        let cp = UInt32(r)
        if (cp != 0x20u32 && cp != 0x09u32 && cp != 0x0Au32 && cp != 0x0Du32) {
            return false
        }
    }
    return true
}

/** XML 声明中 encoding 属性值的语法合法性：`[A-Za-z][A-Za-z0-9._-]*`。 */
func isValidEncodingName(s: String): Bool {
    if (s.size == 0) {
        return false
    }
    var first = true
    for (r in s.runes()) {
        let cp = UInt32(r)
        let isAlpha = (cp >= 0x41u32 && cp <= 0x5Au32) || (cp >= 0x61u32 && cp <= 0x7Au32)
        let isDigit = cp >= 0x30u32 && cp <= 0x39u32
        let isSym = cp == 0x2Eu32 /* . */ || cp == 0x5Fu32 /* _ */ || cp == 0x2Du32 /* - */
        if (first) {
            if (!isAlpha) {
                return false
            }
            first = false
        } else {
            if (!(isAlpha || isDigit || isSym)) {
                return false
            }
        }
    }
    return true
}
