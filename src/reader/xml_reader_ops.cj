/*
 * reader — XmlReader：前进状态机 + 查询实现（extend）
 *
 * 负责 `read()` / `skip()` / 字段派生。主类受 Cangjie 限制通过包级 `readerXxx`
 * 函数转发。
 */
package cangjie_xml.reader

import cangjie_xml.core.*
import cangjie_xml.parser.*

extend XmlReader {
    /* ---------- 抛错 + 取下一事件 ---------- */

    func fail(e: XmlError): Nothing {
        state = ReaderState.Error
        throw XmlException(e)
    }

    func pullEvent(): ?SaxEvent {
        if (let Some(p) <- peeked) {
            peeked = None
            return Some(p)
        }
        try {
            return parser.next()
        } catch (e: XmlException) {
            state = ReaderState.Error
            throw e
        }
    }

    func peekEvent(): ?SaxEvent {
        if (let Some(_) <- peeked) {
            return peeked
        }
        try {
            peeked = parser.next()
        } catch (e: XmlException) {
            state = ReaderState.Error
            throw e
        }
        return peeked
    }

    /* ---------- read() ---------- */

    func runRead(): Bool {
        match (state) {
            case Closed => return false
            case Error => return false
            case EndOfFile => return false
            case _ => ()
        }

        // 结算上一次的 Element 深度：
        //   - 离开 StartElement 时，若非空元素，深度已在读入时 +1；空元素则需 -1 还原
        //     （因为我们要跳过它的 EndElement，但深度只计"当前"，不计历史）；
        //     我们选择在进入下一 read 时处理。
        //   - 离开 EndElement 时，深度在这里 -1，以让下一层节点 depth 正确。
        adjustDepthAfterCursor()

        // 清属性游标
        attrCursor = -1
        emptyElement = false

        let nxt = pullEvent()
        match (nxt) {
            case None =>
                current = None
                state = ReaderState.EndOfFile
                return false
            case Some(ev) =>
                match (ev) {
                    case ParseError(err) =>
                        current = Some(ev)
                        fail(err)
                    case StartElement(pos, _, _, _) =>
                        current = Some(ev)
                        depthVal += 1
                        // 检测空元素：下一事件若是同位置元素的 EndElement，则 emptyElement = true
                        // 但同位置难以严谨判定（自闭合的 EndElement 其 pos 就是自闭合 `/>` 处的位置）。
                        // 采用结构化判定：**下一事件是 EndElement 且其 QName 与此 StartElement 一致**，
                        // 且中间未出现其它子节点 —— 因为 parser 本身对自闭合 `<a/>` 直接发两条事件，
                        // 所以简单判"下一事件是 EndElement"就够了。
                        _ = pos
                        match (peekEvent()) {
                            case Some(EndElement(_, _)) =>
                                emptyElement = true
                            case _ => ()
                        }
                        state = ReaderState.Interactive
                        return true
                    case EndElement(_, _) =>
                        current = Some(ev)
                        state = ReaderState.Interactive
                        // depth 在 adjustDepthAfterCursor 中处理
                        return true
                    case EndDocument(_) =>
                        current = Some(ev)
                        state = ReaderState.Interactive
                        return true
                    case _ =>
                        current = Some(ev)
                        state = ReaderState.Interactive
                        return true
                }
        }
    }

    /**
     * 在 read() 真正拿下一个事件之前，根据当前 cursor 做深度调整：
     *   - 若当前光标是 EndElement，则现在要离开它，depth -= 1；
     *   - 若当前光标是 Element 且是空元素，parser 会给我们发配对的 EndElement；
     *     我们不想把它作为单独节点暴露，所以提前 pull 掉，并且让深度 -1。
     */
    func adjustDepthAfterCursor(): Unit {
        match (current) {
            case Some(EndElement(_, _)) =>
                depthVal -= 1
            case Some(StartElement(_, _, _, _)) where emptyElement =>
                // 消费掉配对 EndElement
                _ = pullEvent()
                depthVal -= 1
            case _ => ()
        }
    }

    /* ---------- skip() ---------- */

    func runSkip(): Bool {
        match (state) {
            case Closed | Error | EndOfFile => return false
            case _ => ()
        }
        match (current) {
            case Some(StartElement(_, qn, _, _)) where emptyElement =>
                // 空元素：skip 等价 read 一次
                return runRead()
            case Some(StartElement(_, qn, _, _)) =>
                // 结算当前元素深度进入，目标：读到本元素配对的 EndElement 为止
                let targetDepth = depthVal
                // 先前进一步
                if (!runRead()) {
                    return false
                }
                // 一直读直到离开这个元素：EndElement 且 depth == targetDepth
                while (true) {
                    match (current) {
                        case Some(EndElement(_, endQn)) where depthVal == targetDepth =>
                            _ = endQn
                            _ = qn
                            return true
                        case None => return false
                        case _ => ()
                    }
                    if (!runRead()) {
                        return false
                    }
                }
                return true
            case _ =>
                return runRead()
        }
    }

    /* ---------- 名字 / 值派生 ---------- */

    func currentAttr(): ?Attribute {
        match (current) {
            case Some(StartElement(_, _, attrs, _)) where attrCursor >= 0 && attrCursor < attrs.size =>
                return Some(attrs[attrCursor])
            case _ => return None
        }
    }

    func runLocalName(): String {
        if (let Some(a) <- currentAttr()) {
            return a.qname.localName
        }
        match (current) {
            case Some(StartElement(_, n, _, _)) => return n.localName
            case Some(EndElement(_, n)) => return n.localName
            case Some(Pi(_, t, _)) => return t
            case Some(Doctype(_, n)) => return n
            case Some(EntityReference(_, n)) => return n
            case Some(StartDocument(_)) => return "xml"
            case _ => return ""
        }
    }

    func runPrefix(): String {
        if (let Some(a) <- currentAttr()) {
            return optStr(a.qname.prefix)
        }
        match (current) {
            case Some(StartElement(_, n, _, _)) => return optStr(n.prefix)
            case Some(EndElement(_, n)) => return optStr(n.prefix)
            case _ => return ""
        }
    }

    func runNamespaceUri(): String {
        if (let Some(a) <- currentAttr()) {
            return optStr(a.qname.uri)
        }
        match (current) {
            case Some(StartElement(_, n, _, _)) => return optStr(n.uri)
            case Some(EndElement(_, n)) => return optStr(n.uri)
            case _ => return ""
        }
    }

    func runName(): String {
        if (let Some(a) <- currentAttr()) {
            return a.qname.lexical()
        }
        match (current) {
            case Some(StartElement(_, n, _, _)) => return n.lexical()
            case Some(EndElement(_, n)) => return n.lexical()
            case Some(Pi(_, t, _)) => return t
            case Some(Doctype(_, n)) => return n
            case Some(EntityReference(_, n)) => return n
            case Some(StartDocument(_)) => return "xml"
            case _ => return ""
        }
    }

    func runValue(): String {
        if (let Some(a) <- currentAttr()) {
            return a.value
        }
        match (current) {
            case Some(Characters(_, s)) => return s
            case Some(Cdata(_, s)) => return s
            case Some(CommentEvent(_, s)) => return s
            case Some(Pi(_, _, d)) => return d
            case Some(EntityReference(_, n)) => return n
            case Some(StartDocument(d)) => return d.version
            case _ => return ""
        }
    }
}

/* ---------- 小工具 ---------- */

func optStr(o: ?String): String {
    match (o) {
        case Some(s) => return s
        case None => return ""
    }
}
