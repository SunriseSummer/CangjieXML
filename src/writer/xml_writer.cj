package cangjie_xml.writer

import cangjie_xml.dom.*
import cangjie_xml.internal.*

/**
 * XML 写出器：把 DOM 子树序列化为 XML 文本并写入指定 `XmlSink`。
 *
 * 所有行为由 `XmlWriteOptions` 控制，不存在全局静态开关——相同 DOM + 相同
 * options 必然产生相同输出（确定性契约，见 DESIGN §13.2）。
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

    public init(sink: XmlSink, options!: XmlWriteOptions = XmlWriteOptions.default_()) {
        this.sink = sink
        this.opts = options
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
            sink.write(UTF8_BOM_STRING)
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
            sink.write(escapeCdata(t.value))
        } else {
            sink.write(escapeText(t.value))
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
        sink.write(TAG_SELF_CLOSE)
        maybeNewline()
    }

    private func finishAsInline(el: XmlElement): Unit {
        sink.write(TAG_CLOSE)
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
        sink.write(TAG_CLOSE)
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
        sink.write(TAG_OPEN)
        sink.write(el.name)
        // 索引迭代避免为每个属性构造一个 `ArrayList.Iterator` 对象。
        let n = el.attributeCount()
        var i = 0
        while (i < n) {
            let a = el.attributeAt(i)
            sink.write(ATTR_SPACE)
            sink.write(a.name)
            sink.write(ATTR_EQUALS_QUOTE)
            sink.write(escapeAttribute(a.value))
            sink.write(ATTR_CLOSE_QUOTE)
            i++
        }
    }

    private func writeCloseTag(name: String): Unit {
        sink.write(TAG_OPEN_SLASH)
        sink.write(name)
        sink.write(TAG_CLOSE)
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
                sink.write(TAG_SELF_CLOSE)
                return
            case Some(_) => ()
        }
        sink.write(TAG_CLOSE)
        var cur = el.firstChild
        while (let Some(child) <- cur) {
            writeNodeInline(child)
            cur = child.nextSibling
        }
        writeCloseTag(el.name)
    }

    private func writePiRaw(value: String): Unit {
        sink.write(PI_OPEN)
        sink.write(value)
        sink.write(PI_CLOSE)
    }

    private func writeCommentRaw(value: String): Unit {
        sink.write(COMMENT_OPEN)
        sink.write(value)
        sink.write(COMMENT_CLOSE)
    }

    private func writeUnknownRaw(value: String): Unit {
        // PI 形态（`?...?`）原样输出，bang markup 包 `<!...>`。
        if (value.startsWith("?")) {
            sink.write(TAG_OPEN);
            sink.write(value);
            sink.write(TAG_CLOSE)
        } else {
            sink.write(UNKNOWN_OPEN);
            sink.write(value);
            sink.write(UNKNOWN_CLOSE)
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
            sink.write(opts.indent)
            i++
        }
        atLineStart = false
    }

    private func maybeNewline(): Unit {
        if (opts.compact) {
            return
        }
        sink.write(opts.lineEnd)
        atLineStart = true
    }
}
