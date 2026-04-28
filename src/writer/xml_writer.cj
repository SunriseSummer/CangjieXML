package fastxml.writer

import fastxml.dom.*
import fastxml.internal.*

/**
 * XML 写出器：把 DOM 子树序列化为 XML 文本并写入指定 `XmlSink`。
 *
 * 所有行为由 `XmlWriteOptions` 控制，不存在全局静态开关——相同 DOM + 相同
 * options 必然产生相同输出（确定性契约）。
 *
 * ## 排版决策
 *
 * | 子节点 | 排版 |
 * |---|---|
 * | 无 | 自闭合 `<e/>` |
 * | 含文本 / CDATA | 全内联（保留空白语义） |
 * | 其它 | 块级缩进 |
 */
public class XmlWriter {
    let sink: XmlSink
    let opts: XmlWriteOptions
    var depth: Int64 = 0
    var atLineStart: Bool = true

    /*
     * Fast path: 当 sink 是 `StringXmlSink` 时，直接拿到其 `StringBuilder`，
     * 绕过 `XmlSink.write` 的接口分派。CangjiePerf 显示 `string_concat`
     * (StringBuilder) 不是仓颉强项；减少接口分派可在热路径上显著降低
     * 单次 append 的固定开销。
     */
    private let directBuf: ?StringBuilder

    public init(sink: XmlSink, options!: XmlWriteOptions = XmlWriteOptions.default_()) {
        this.sink = sink
        this.opts = options
        this.directBuf = match (sink) {
            case s: StringXmlSink => Some(s.buffer)
            case _ => None
        }
    }

    /** 唯一的字节出口；fast-path 直写 builder，否则走 sink 接口。 */
    private func emit(text: String): Unit {
        match (directBuf) {
            case Some(b) => b.append(text)
            case None => sink.write(text)
        }
    }

    public func writeDocument(doc: XmlDocument): Unit {
        writeBomIfNeeded(doc)
        writeDeclarationIfNeeded(doc)
        writeTopLevelBody(doc)
        sink.flush()
    }

    public func writeElement(el: XmlElement): Unit {
        writeNodeDispatch(el)
        sink.flush()
    }

    public func writeNode(node: XmlNode): Unit {
        match (node.kind()) {
            case Document(d) => writeDocument(d)
            case _ => writeNodeDispatch(node)
        }
    }

    private func writeNodeDispatch(node: XmlNode): Unit {
        match (node.kind()) {
            case Document(_) => ()
            case Element(e) => writeElementBlock(e)
            case Text(t) => writeTextNode(t)
            case Comment(c) => writeCommentNode(c)
            case Declaration(d) => writeDeclarationNode(d)
            case Unknown(u) => writeUnknownNode(u)
        }
    }

    private func writeBomIfNeeded(doc: XmlDocument): Unit {
        if (opts.writeBom || doc.writeBom) {
            emit(UTF8_BOM_STRING)
        }
    }

    private func writeDeclarationIfNeeded(doc: XmlDocument): Unit {
        if (!opts.writeDeclaration) {
            return
        }
        match (doc.declaration) {
            case Some(d) => writeDeclarationNode(d)
            case None => writeDefaultDeclaration()
        }
    }

    private func writeTopLevelBody(doc: XmlDocument): Unit {
        var cur = doc.firstChild
        while (let Some(n) <- cur) {
            if (!isDeclaration(n)) {
                writeNodeDispatch(n)
            }
            cur = n.nextSibling
        }
    }

    private static func isDeclaration(n: XmlNode): Bool {
        match (n.kind()) {
            case Declaration(_) => true
            case _ => false
        }
    }

    private func writeDeclarationNode(d: XmlDeclaration): Unit {
        indentIfNeeded()
        writePiRaw(d.value)
        maybeNewline()
    }

    private func writeCommentNode(c: XmlComment): Unit {
        indentIfNeeded()
        writeCommentRaw(c.value)
        maybeNewline()
    }

    private func writeUnknownNode(u: XmlUnknown): Unit {
        indentIfNeeded()
        writeUnknownRaw(u.value)
        maybeNewline()
    }

    private func writeTextNode(t: XmlText): Unit {
        // 文本节点的缩进策略由上层元素决定；此处只负责内容本身。
        if (t.isCdata) {
            emit(escapeCdata(t.value))
        } else {
            emit(escapeText(t.value))
        }
    }

    private func writeDefaultDeclaration(): Unit {
        indentIfNeeded()
        writePiRaw(DEFAULT_XML_DECLARATION_VALUE)
        maybeNewline()
    }

    /** 块级模式写出元素；排版决策由 `chooseLayout` 给出，主流程分三态处理。 */
    private func writeElementBlock(el: XmlElement): Unit {
        indentIfNeeded()
        writeOpenTagWithAttrs(el)

        match (chooseLayout(el)) {
            case SelfClosing => finishSelfClosing()
            case Inline => finishAsInline(el)
            case Block => finishAsBlock(el)
        }
    }

    private func finishSelfClosing(): Unit {
        emit(TAG_SELF_CLOSE)
        maybeNewline()
    }

    private func finishAsInline(el: XmlElement): Unit {
        emit(TAG_CLOSE)
        // 直接走链表，避免每次都构造迭代器对象。
        var cur = el.firstChild
        while (let Some(child) <- cur) {
            writeNodeInline(child)
            cur = child.nextSibling
        }
        writeCloseTag(el.name)
        maybeNewline()
    }

    private func finishAsBlock(el: XmlElement): Unit {
        emit(TAG_CLOSE)
        maybeNewline()
        depth++
        var cur = el.firstChild
        while (let Some(child) <- cur) {
            writeNodeDispatch(child)
            cur = child.nextSibling
        }
        depth--
        indentIfNeeded()
        writeCloseTag(el.name)
        maybeNewline()
    }

    private func writeOpenTagWithAttrs(el: XmlElement): Unit {
        emit(TAG_OPEN)
        emit(el.name)
        // 索引迭代避免为每个属性构造一个 `ArrayList.Iterator` 对象。
        let attributeCount = el.attributeCount()
        var attributeIndex = 0
        while (attributeIndex < attributeCount) {
            let attribute = el.attributeAt(attributeIndex)
            emit(ATTR_SPACE)
            emit(attribute.name)
            emit(ATTR_EQUALS_QUOTE)
            emit(escapeAttribute(attribute.value))
            emit(ATTR_CLOSE_QUOTE)
            attributeIndex++
        }
    }

    private func writeCloseTag(name: String): Unit {
        emit(TAG_OPEN_SLASH)
        emit(name)
        emit(TAG_CLOSE)
    }

    private func writeNodeInline(node: XmlNode): Unit {
        match (node.kind()) {
            case Document(_) => ()
            case Element(e) => writeElementInline(e)
            case Text(t) => writeTextNode(t)
            case Comment(c) => writeCommentRaw(c.value)
            case Declaration(d) => writePiRaw(d.value)
            case Unknown(u) => writeUnknownRaw(u.value)
        }
    }

    private func writeElementInline(el: XmlElement): Unit {
        writeOpenTagWithAttrs(el)
        match (el.firstChild) {
            case None =>
                emit(TAG_SELF_CLOSE)
                return
            case Some(_) => ()
        }
        emit(TAG_CLOSE)
        var cur = el.firstChild
        while (let Some(child) <- cur) {
            writeNodeInline(child)
            cur = child.nextSibling
        }
        writeCloseTag(el.name)
    }

    private func writePiRaw(value: String): Unit {
        emit(PI_OPEN)
        emit(value)
        emit(PI_CLOSE)
    }

    private func writeCommentRaw(value: String): Unit {
        emit(COMMENT_OPEN)
        emit(value)
        emit(COMMENT_CLOSE)
    }

    private func writeUnknownRaw(value: String): Unit {
        // PI 形态（`?...?`）原样输出，bang markup 包 `<!...>`。
        if (value.startsWith("?")) {
            emit(TAG_OPEN);
            emit(value);
            emit(TAG_CLOSE)
        } else {
            emit(UNKNOWN_OPEN);
            emit(value);
            emit(UNKNOWN_CLOSE)
        }
    }

    private func chooseLayout(el: XmlElement): ElementLayout {
        match (el.firstChild) {
            case None => SelfClosing
            case Some(_) =>
                // 紧凑模式无缩进 / 换行语义，非空元素一律按 inline 写出，
                // 避免为每个元素再扫描子链表判断是否含文本节点。
                if (opts.compact || hasTextChild(el)) {
                    Inline
                } else {
                    Block
                }
        }
    }

    private static func hasTextChild(el: XmlElement): Bool {
        var cur = el.firstChild
        while (let Some(n) <- cur) {
            if (let Text(_) <- n.kind()) {
                return true
            }
            cur = n.nextSibling
        }
        false
    }

    private func indentIfNeeded(): Unit {
        if (opts.compact || !atLineStart) {
            return
        }
        var i = 0
        while (i < depth) {
            emit(opts.indent)
            i++
        }
        atLineStart = false
    }

    private func maybeNewline(): Unit {
        if (opts.compact) {
            return
        }
        emit(opts.lineEnd)
        atLineStart = true
    }
}
