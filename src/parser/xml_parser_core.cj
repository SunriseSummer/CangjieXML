/*
 * parser — XmlParser 主循环 / Token 分派 / Token IO
 *
 * 拆自原 `xml_parser.cj` 的 `next` / `driveOnce` / `handleToken` / `readToken` /
 * `peekToken` / `consumeExpectedToken`。每个函数的圈复杂度都降到 ≤ 6。
 */
package cangjie_xml.parser

import cangjie_xml.core.*

extend XmlParser {
    /* ---------- 顶层：pump（next 的实际实现） ---------- */

    func pump(): Option<SaxEvent> {
        while (true) {
            if (!pending.isEmpty()) {
                return pending.removeFirst()
            }
            if (finished) {
                return None
            }
            pumpOneOrHandleError()
        }
        return None
    }

    /** 驱动一次状态机；异常按 `recover` 模式处理。 */
    private func pumpOneOrHandleError(): Unit {
        try {
            driveOnce()
        } catch (e: XmlException) {
            finished = true
            if (!opts.recover) {
                throw e
            }
            // 容错模式（Phase 3c 完整实现）：目前降级为一次性 ParseError + EndDocument
            pending.addLast(SaxEvent.ParseError(e.error))
            pending.addLast(SaxEvent.EndDocument(Position.unknown()))
        }
    }

    /* ---------- 主循环 ---------- */

    private func driveOnce(): Unit {
        if (!emittedStart) {
            produceStartDocumentIfNeeded()
            if (!pending.isEmpty()) {
                return
            }
        }
        handleToken(readToken())
    }

    private func produceStartDocumentIfNeeded(): Unit {
        let first = peekToken()
        emittedStart = true
        match (first) {
            case XmlDeclStart(p) =>
                let _ = readToken() // 消费 XmlDeclStart
                pending.addLast(SaxEvent.StartDocument(parseXmlDecl(p)))
            case _ =>
                pending.addLast(SaxEvent.StartDocument(XmlDecl(position: first.position(), isSynthetic: true)))
        }
    }

    /* ---------- token 分派 ---------- */

    private func handleToken(t: Token): Unit {
        match (t) {
            case Eof(p) => handleEof(p)
            case DoctypeStart(p, name) => handleDoctype(p, name)
            case Token.Comment(p, s) => pending.addLast(SaxEvent.CommentEvent(p, s))
            case Token.ProcessingInstruction(p, tgt, data) => pending.addLast(SaxEvent.Pi(p, tgt, data))
            case Token.CDataSection(p, s) => handleCData(p, s)
            case ElementOpenStart(p, rawName) => handleElementStart(p, rawName)
            case ElementClose(p, rawName) => handleElementEnd(p, rawName)
            case Text(p, s) => handleText(p, s)
            case CharRef(p, cp) => handleCharRef(p, cp)
            case EntityRef(p, name) => handleEntityRef(p, name)
            case other => throw strayTokenError(other)
        }
    }

    private func handleEof(p: Position): Unit {
        if (!elemStack.isEmpty()) {
            throw XmlException(XmlError.UnexpectedEof(p, "unexpected EOF inside element"))
        }
        if (!emittedEnd) {
            pending.addLast(SaxEvent.EndDocument(p))
            emittedEnd = true
        }
        finished = true
    }

    private func handleDoctype(p: Position, name: String): Unit {
        let e = readToken()
        match (e) {
            case DoctypeEnd(_) => ()
            case other =>
                throw XmlException(XmlError.Malformed(other.position(), "expected DoctypeEnd"))
        }
        pending.addLast(SaxEvent.Doctype(p, name))
    }

    private func handleCData(p: Position, s: String): Unit {
        if (elemStack.isEmpty()) {
            throw XmlException(XmlError.Malformed(p, "CDATA section outside of element"))
        }
        pending.addLast(SaxEvent.Cdata(p, s))
    }

    private func handleCharRef(p: Position, cp: Int32): Unit {
        handleText(p, Rune(UInt32(cp)).toString())
        bumpEntityExpansion(1, p)
    }

    /** 文档流程中孤立出现的"内部"token（语义上不应该在当前上下文出现）统一报错。 */
    private static func strayTokenError(t: Token): XmlException {
        let (p, msg) = strayTokenDiagnostic(t)
        return XmlException(XmlError.Malformed(p, msg))
    }

    private static func strayTokenDiagnostic(t: Token): (Position, String) {
        match (t) {
            case XmlDeclStart(p) => return (p, "XML declaration not at start of document")
            case XmlDeclEnd(p) => return (p, "stray '?>'")
            case ElementOpenEnd(p) => return (p, "stray '>'")
            case ElementSelfClose(p) => return (p, "stray '/>'")
            case AttrName(p, _) => return (p, "stray attribute")
            case AttrEq(p) => return (p, "stray '='")
            case AttrValueStart(p, _) => return (p, "stray quote")
            case AttrValueChunk(p, _) => return (p, "stray chunk")
            case AttrValueEnd(p, _) => return (p, "stray quote")
            case DoctypeEnd(p) => return (p, "stray DOCTYPE end")
            case t2 => return (t2.position(), "unexpected token")
        }
    }

    /* ---------- token 读取 / 预读 ---------- */

    func readToken(): Token {
        let t = takeOrFetchToken()
        postReadHook(t)
        return t
    }

    private func takeOrFetchToken(): Token {
        match (pendingToken) {
            case Some(t) =>
                pendingToken = None
                return t
            case None => ()
        }
        return fetchLexerToken()
    }

    private func fetchLexerToken(): Token {
        match (lexer.next()) {
            case Some(x) => return x
            case None => return Token.Eof(Position.unknown())
        }
    }

    func peekToken(): Token {
        match (pendingToken) {
            case Some(t) => return t
            case None => ()
        }
        let t = fetchLexerToken()
        pendingToken = Some(t)
        return t
    }

    /**
     * 读取 token 后：若 token 本身可能加入字符缓冲（Text/CharRef/EntityRef），
     * 保持缓冲；否则立即 flush，维护"连续字符合并"语义。
     */
    private func postReadHook(t: Token): Unit {
        match (t) {
            case Text(_, _) => ()
            case CharRef(_, _) => ()
            case EntityRef(_, _) => ()
            case _ => flushPendingCharacters()
        }
    }

    func consumeExpectedToken(pred: (Token) -> Bool, what: String): Unit {
        let t = readToken()
        if (!pred(t)) {
            throw XmlException(XmlError.Malformed(t.position(), "expected ${what}"))
        }
    }
}
