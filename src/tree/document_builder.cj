/*
 * tree — DocumentBuilder：SAX 事件流 → DOM 树
 *
 * 对应 libxml2: `SAX2.c` 中 `xmlSAX2StartDocument` / `xmlSAX2StartElementNs`
 * / `xmlSAX2Characters` 等一组回调的聚合行为。libxml2 以"回调闭包 + 全局
 * parser 状态"实现，CangjieXML 改为**拉式**：调用方传入 `Iterator<SaxEvent>`，
 * Builder 驱动迭代器到 `EndDocument` 并返回完整 `Document`。
 *
 * 不变式：
 *   1. 迭代器必须产出良构事件（已由 `XmlParser` 保证，除非 `recover=true`）；
 *   2. 若迭代途中遇到 `ParseError`：立即抛 `XmlException` 包装其内部 `XmlError`。
 *      Phase 4b 再考虑"带错误节点的部分 DOM"；
 *   3. 构造结束时 `elemStack` 必须为空，否则 `XmlParser` 本应抛 `UnexpectedEof`，
 *      这里视作内部错误用 `Malformed` 报出（防御式）。
 *
 * 与 `XmlParser` 配合的便捷入口：`DocumentBuilder.parseString` / `parse` 一步到位。
 */
package cangjie_xml.tree

import std.collection.*
import cangjie_xml.core.*
import cangjie_xml.parser.*

public class DocumentBuilder {
    var xmlDecl: ?XmlDecl = None
    var doctypeNode: ?DoctypeNode = None
    var rootElem: ?Element = None
    let prologBuf: ArrayList<Node> = ArrayList<Node>()
    let epilogBuf: ArrayList<Node> = ArrayList<Node>()
    // 元素栈：栈顶为当前开放元素。
    let elemStack: ArrayStack<Element> = ArrayStack<Element>()
    var finished: Bool = false

    public init() {}

    /* ---------- 顶层入口 ---------- */

    /** 便利入口：从字符串直接构造 Document。 */
    public static func parseString(s: String, opts!: ParserOptions = ParserOptions()): Document {
        return DocumentBuilder().build(XmlParser.fromString(s, opts: opts))
    }

    /** 通用入口：消费一个 SaxEvent 迭代器（通常来自 `XmlParser`）。 */
    public func build(events: Iterator<SaxEvent>): Document {
        for (e in events) {
            consume(e)
            if (finished) {
                break
            }
        }
        return finalize()
    }

    /* ---------- 单事件分派 ---------- */

    func consume(e: SaxEvent): Unit {
        match (e) {
            case StartDocument(d) => xmlDecl = Some(d)
            case EndDocument(_) => finished = true
            case StartElement(p, q, attrs, ns) => onStartElement(p, q, attrs, ns)
            case EndElement(_, _) => onEndElement()
            case Characters(p, s) => addLeaf(TextNode(s, position: p))
            case Cdata(p, s) => addLeaf(CdataSection(s, position: p))
            case CommentEvent(p, s) => addLeaf(CommentNode(s, position: p))
            case Pi(p, t, d) => addLeaf(PiNode(t, d, position: p))
            case Doctype(p, n) => onDoctype(p, n)
            case EntityReference(p, n) => onEntityReference(p, n)
            case ParseError(err) => throw XmlException(err)
        }
    }

    func onStartElement(p: Position, q: QName, attrs: Array<Attribute>, ns: NsContext): Unit {
        let el = Element(q, ns, position: p)
        for (a in attrs) {
            el.attributesImpl.add(Attr.fromSaxAttribute(a))
        }
        if (elemStack.isEmpty()) {
            // 根元素
            rootElem = Some(el)
        } else {
            let parent = elemStack.peek().getOrThrow()
            el.parentImpl = Some(parent)
            parent.childrenImpl.add(el)
        }
        elemStack.add(el)
    }

    func onEndElement(): Unit {
        if (elemStack.isEmpty()) {
            throw XmlException(XmlError.Malformed(Position.unknown(), "DocumentBuilder: EndElement without matching StartElement"))
        }
        let _ = elemStack.remove()
    }

    func onDoctype(p: Position, name: String): Unit {
        let dt = DoctypeNode(name, position: p)
        doctypeNode = Some(dt)
        // DOCTYPE 出现在 prolog 里；但 `Document.doctype` 独立字段承载，这里不入 prologBuf。
    }

    func onEntityReference(p: Position, name: String): Unit {
        // substituteEntities = false 时会见到；MVP 暂不建模 EntityRef 节点，
        // 降级为一段文本字面量 `&name;`，保持 DOM 完整但不损失源信息。
        let literal = "&${name};"
        addLeaf(TextNode(literal, position: p))
    }

    /* ---------- 叶子节点挂载 ---------- */

    func addLeaf(n: Node): Unit {
        if (elemStack.isEmpty()) {
            // 根元素尚未出现 → prolog；已 pop 完 → epilog。
            if (rootElem.isNone()) {
                prologBuf.add(n)
            } else {
                epilogBuf.add(n)
            }
            return
        }
        let parent = elemStack.peek().getOrThrow()
        setLeafParent(n, parent)
        parent.childrenImpl.add(n)
    }

    /**
     * 同包内访问叶子节点的 `parentImpl` 字段。为避免在每个叶子类上都重复类型模式，
     * 封装为 package-private 函数。
     */
    func setLeafParent(n: Node, parent: Element): Unit {
        match (n) {
            case t: TextNode => t.parentImpl = Some(parent)
            case c: CdataSection => c.parentImpl = Some(parent)
            case cm: CommentNode => cm.parentImpl = Some(parent)
            case pi: PiNode => pi.parentImpl = Some(parent)
            case e: Element => e.parentImpl = Some(parent)
            case _ => ()
        }
    }

    /* ---------- 构造结束 ---------- */

    func finalize(): Document {
        if (!elemStack.isEmpty()) {
            throw XmlException(XmlError.UnexpectedEof(Position.unknown(), "DocumentBuilder: ${elemStack.size} element(s) not closed"))
        }
        let decl = match (xmlDecl) {
            case Some(d) => d
            case None => XmlDecl(position: Position.unknown())
        }
        let root = match (rootElem) {
            case Some(r) => r
            case None => throw XmlException(XmlError.Malformed(Position.unknown(), "DocumentBuilder: no root element"))
        }
        return Document(decl, doctypeNode, root, prologBuf, epilogBuf)
    }
}
