/*
 * parser — XmlParser 元素与属性处理
 *
 * 拆自原 `xml_parser.cj` 的 `handleElementStart` / `handleElementEnd`。按关注点
 * 进一步分解为多个小函数：属性原始收集 / 命名空间绑定 / 属性 QName 解析 / 事件产出，
 * 每个函数 ≤ 30 行，单独圈复杂度显著降低。
 */
package cangjie_xml.parser

import std.collection.*
import cangjie_xml.core.*

/** 由开始标签的 token 流中收集出的原始属性。 */
struct RawAttr {
    let name: String
    let pos: Position
    let value: String

    init(name: String, pos: Position, value: String) {
        this.name = name
        this.pos = pos
        this.value = value
    }
}

extend XmlParser {
    /* ---------- 入口：元素开始 ---------- */

    func handleElementStart(startPos: Position, rawName: String): Unit {
        let rawAttrs = collectRawAttrs()
        checkElementLimits(startPos)
        let newNs = buildNsContextFor(rawAttrs)
        let elemQName = resolveQName(rawName, newNs, startPos, isAttribute: false)
        let attrs = buildAttributes(rawAttrs, newNs)
        emitStart(startPos, elemQName, attrs, newNs, rawAttrs.selfClose)
    }

    /* ---------- 入口：元素结束 ---------- */

    func handleElementEnd(pos: Position, rawName: String): Unit {
        match (elemStack.remove()) {
            case None =>
                throw XmlException(XmlError.Malformed(pos, "end tag '${rawName}' without matching start tag"))
            case Some((openQ, _)) =>
                let _ = nsStack.remove()
                let expected = openQ.lexical()
                if (rawName != expected) {
                    throw XmlException(XmlError.Malformed(pos, "end tag '${rawName}' does not match start tag '${expected}'"))
                }
                pending.addLast(SaxEvent.EndElement(pos, openQ))
        }
    }

    /* ---------- 步骤 1：从 token 流中收集原始属性 ---------- */

    func collectRawAttrs(): RawAttrBatch {
        let batch = RawAttrBatch()
        while (true) {
            let t = readToken()
            match (t) {
                case ElementOpenEnd(_) => return batch
                case ElementSelfClose(_) =>
                    batch.selfClose = true
                    return batch
                case AttrName(p, aname) =>
                    expectEqToken()
                    let value = readQuotedAttrValueLiteral(p)
                    batch.items.add(RawAttr(aname, p, value))
                case other =>
                    throw XmlException(XmlError.Malformed(other.position(), "unexpected token in start tag"))
            }
        }
        return batch
    }

    private func expectEqToken(): Unit {
        consumeExpectedToken({ x: Token =>
            match (x) {
                case AttrEq(_) => return true
                case _ => return false
            }
        }, "'=' after attribute name")
    }

    /* ---------- 步骤 2：深度 / 多根 校验 ---------- */

    private func checkElementLimits(startPos: Position): Unit {
        if (Int64(elemStack.size) + 1 > opts.maxDepth) {
            throw XmlException(XmlError.LimitExceeded(startPos, "element depth exceeded ${opts.maxDepth}"))
        }
        if (rootEmitted && elemStack.isEmpty()) {
            throw XmlException(XmlError.Malformed(startPos, "multiple root elements"))
        }
    }

    /* ---------- 步骤 3：基于父 NsContext + 本元素的 xmlns 属性构造新 NsContext ---------- */

    private func buildNsContextFor(batch: RawAttrBatch): NsContext {
        var ns = nsStack.peek().getOrThrow()
        for (a in batch.items) {
            ns = applyNsDeclIfAny(ns, a)
        }
        return ns
    }

    private func applyNsDeclIfAny(ns: NsContext, a: RawAttr): NsContext {
        match (classifyNsDecl(a.name)) {
            case NotNsDecl => return ns
            case DefaultNs =>
                validateNsValue(a.value, a.pos)
                return ns.push(None<String>, emptyToNone(a.value))
            case PrefixNs =>
                return applyPrefixNsDecl(ns, a)
        }
    }

    private func applyPrefixNsDecl(ns: NsContext, a: RawAttr): NsContext {
        let pfx = a.name[6..] // after "xmlns:"
        if (pfx == "xmlns") {
            throw XmlException(XmlError.NamespaceError(a.pos, "cannot redeclare 'xmlns' prefix"))
        }
        if (pfx == "xml") {
            return handleXmlPrefixRebinding(ns, a)
        }
        rejectReservedNsUri(a.value, a.pos)
        validateNsValue(a.value, a.pos)
        return ns.push(Some(pfx), emptyToNone(a.value))
    }

    private static func handleXmlPrefixRebinding(ns: NsContext, a: RawAttr): NsContext {
        if (a.value != XML_NAMESPACE_URI) {
            throw XmlException(XmlError.NamespaceError(a.pos, "'xml' prefix must bind to ${XML_NAMESPACE_URI}"))
        }
        // 冗余但合法；不再 push
        return ns
    }

    private static func rejectReservedNsUri(value: String, pos: Position): Unit {
        if (value == XML_NAMESPACE_URI) {
            throw XmlException(XmlError.NamespaceError(pos, "only 'xml' prefix may bind to XML namespace URI"))
        }
        if (value == XMLNS_NAMESPACE_URI) {
            throw XmlException(XmlError.NamespaceError(pos, "no prefix may bind to xmlns namespace URI"))
        }
    }

    /* ---------- 步骤 4：属性 QName 解析 + 扩展名唯一性 ---------- */

    private func buildAttributes(batch: RawAttrBatch, ns: NsContext): Array<Attribute> {
        let out = ArrayList<Attribute>()
        let seen = HashSet<String>()
        for (a in batch.items) {
            let q = attrQName(a, ns)
            let key = q.expanded()
            if (seen.contains(key)) {
                throw XmlException(XmlError.Malformed(a.pos, "duplicate attribute '${a.name}'"))
            }
            seen.add(key)
            let interned = maybeInternQName(q, opts.nameTable)
            out.add(Attribute(interned, a.value, position: a.pos, isNamespaceDeclaration: isNsDecl(a.name)))
        }
        return out.toArray()
    }

    private static func isNsDecl(name: String): Bool {
        match (classifyNsDecl(name)) {
            case NotNsDecl => return false
            case _ => return true
        }
    }

    private func attrQName(a: RawAttr, ns: NsContext): QName {
        match (classifyNsDecl(a.name)) {
            case DefaultNs => return QName("xmlns", uri: XMLNS_NAMESPACE_URI)
            case PrefixNs => return QName(a.name[6..], prefix: "xmlns", uri: XMLNS_NAMESPACE_URI)
            case NotNsDecl => return resolveQName(a.name, ns, a.pos, isAttribute: true)
        }
    }

    /* ---------- 步骤 5：产出 StartElement / EndElement 事件并维护栈 ---------- */

    private func emitStart(
        startPos: Position,
        rawElemQName: QName,
        attrs: Array<Attribute>,
        newNs: NsContext,
        selfClose: Bool
    ): Unit {
        let interned = maybeInternQName(rawElemQName, opts.nameTable)
        pending.addLast(SaxEvent.StartElement(startPos, interned, attrs, newNs))
        if (!rootEmitted) {
            rootEmitted = true
        }
        if (selfClose) {
            pending.addLast(SaxEvent.EndElement(startPos, interned))
        } else {
            elemStack.add((interned, startPos))
            nsStack.add(newNs)
        }
    }
}

/** 批量属性 + 自闭合标志。使用可变字段以便收集过程中修改。 */
class RawAttrBatch {
    let items: ArrayList<RawAttr> = ArrayList<RawAttr>()
    var selfClose: Bool = false

    init() {}
}
