package cangjie_xml.dom

import std.collection.*
import cangjie_xml.error.*

/**
 * XML 元素节点：`<name attr="...">...</name>`。
 *
 * ## 内部表示
 *
 * - **子节点**：双向链表。选择链表而非 `ArrayList<XmlNode>` 的理由见
 *   DESIGN.md §7.1——XML DOM 典型操作是"在已知节点附近插入 / 删除 /
 *   顺序遍历"，链表能让这些操作 O(1)，且 `previousSibling` / `nextSibling`
 *   实现天然。
 * - **属性**：`ArrayList<XmlAttribute>` 保留插入顺序，`HashMap<String, XmlAttribute>`
 *   提供 O(1) 名称查找。同名属性以"后写覆盖"语义处理（与 XML 规范一致，
 *   不允许同一元素出现两个同名属性）。
 *
 * ## 文件拆分
 *
 * 为保持单文件不超过 300 行（工程红线），属性 API 与子节点 API 分别放入：
 *
 * - `xml_element_attrs.cj`
 * - `xml_element_children.cj`
 * - `xml_element_iters.cj`（迭代器实现）
 *
 * 本文件仅承载类声明、字段、基础构造与 `kind()`，以及 `textContent` 读写与
 * 少量供 `extend` 共享的内部工具。
 */
public class XmlElement <: XmlNode {
    public var name: String

    // 字段改为包内可见（不加 private），以便同包内的 extend 文件访问。
    // 命名上以 `Child` / `attr` 前缀去歧义，避免与 `firstChild` / `attributes()`
    // 这些公共 API 冲突。
    var headChild: ?XmlNode = None
    var tailChild: ?XmlNode = None

    let attrOrder: ArrayList<XmlAttribute> = ArrayList<XmlAttribute>()
    let attrIndex: HashMap<String, XmlAttribute> = HashMap<String, XmlAttribute>()

    init(doc: XmlDocument, name: String) {
        super(doc)
        this.name = name
    }

    public override func kind(): XmlNodeKind {
        XmlNodeKind.Element(this)
    }

    // ==================================================================
    // 文本内容 API
    // ==================================================================

    /**
     * 读取元素的"文本内容"：按 DOM 直觉拼接所有后代 `XmlText` 节点的值。
     *
     * - 与 W3C DOM 的 `textContent` 语义一致：跨层级递归拼接；
     * - 不包含注释、声明、未知节点等非文本内容；
     * - CDATA 与普通文本一视同仁，只取其 `value`。
     */
    public func textContent(): String {
        let sb = StringBuilder()
        collectTextContent(this, sb)
        sb.toString()
    }

    /**
     * 覆盖元素文本内容为单一文本子节点。
     *
     * 行为：
     * 1. 删除所有现有子节点；
     * 2. 追加一个新的非 CDATA `XmlText`（`value = value`）。
     *
     * 若仅需设置 CDATA，请改用 `XmlDocument.createText(value, cdata: true)` + `appendChild`。
     */
    public func setTextContent(value: String): Unit {
        clearAllChildren()
        let t = document.createText(value)
        linkAtEnd(t)
    }

    // ==================================================================
    // 供 extend 文件共享的内部工具
    // ==================================================================

    /** 在尾部挂入节点，维护双向链表与归属字段。 */
    func linkAtEnd(node: XmlNode): Unit {
        node.parentRef = Some(this)
        node.documentRef = Some(this.document)
        node.inDocFlag = false
        node.prevRef = tailChild
        node.nextRef = None
        match (tailChild) {
            case Some(l) => l.nextRef = Some(node)
            case None => headChild = Some(node)
        }
        tailChild = Some(node)
    }

    /** 将节点从现有父节点中解挂（若有）。 */
    func detachFromCurrent(node: XmlNode): Unit {
        node.removeSelf()
    }

    /** `node` 是否为本元素的直接子节点。 */
    func ownsAsChild(node: XmlNode): Bool {
        match (node.parentRef) {
            case None => false
            case Some(p) => refEq(p, this)
        }
    }

    /** 清空所有子节点（仅供 setTextContent 复用，避免重复逻辑）。 */
    private func clearAllChildren(): Unit {
        var cur = headChild
        while (let Some(n) <- cur) {
            let nxt = n.nextRef
            n.prevRef = None
            n.nextRef = None
            n.parentRef = None
            n.inDocFlag = false
            cur = nxt
        }
        headChild = None
        tailChild = None
    }

    private static func collectTextContent(el: XmlElement, sb: StringBuilder): Unit {
        var cur = el.headChild
        while (let Some(n) <- cur) {
            match (n.kind()) {
                case Text(t) => sb.append(t.value)
                case Element(child) => collectTextContent(child, sb)
                case _ => ()
            }
            cur = n.nextRef
        }
    }
}

/** 便捷抛异常工具（避免到处写 `throw XmlException(...)`）。 */
func throwDom(msg: String): Nothing {
    throw XmlException(msg)
}
