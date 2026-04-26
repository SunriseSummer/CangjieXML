package tinyxml2.dom

import std.collection.*
import tinyxml2.error.*

/**
 * XML 元素节点：`<name attr="...">...</name>`。
 *
 * ## 内部表示
 *
 * - **子节点**：双向链表。XML DOM 典型操作是"在已知节点附近插入 / 删除 /
 *   顺序遍历"，链表让这些操作 O(1)，并天然实现 `previousSibling` /
 *   `nextSibling`。
 * - **属性**：`ArrayList<XmlAttribute>` 保留插入顺序；当属性数超过
 *   `ATTR_INDEX_THRESHOLD` 时，再构建 `HashMap<String, XmlAttribute>`
 *   做 O(1) 名称查找。≤ 阈值时一律线性扫描——典型 XML 元素属性数 < 8，
 *   线性扫描比 HashMap 哈希计算 + 桶寻址更快。同名属性以"后写覆盖"语义
 *   处理（与 XML 规范一致，禁止同一元素出现两个同名属性）。
 *
 * 属性、子节点 API 与子节点迭代器分别落到 `xml_element_attrs.cj` /
 * `xml_element_children.cj` / `xml_element_iters.cj`，本文件只承载类声明、
 * 字段、`kind()`、`textContent` 读写以及供 `extend` 共享的内部工具。
 */
public class XmlElement <: XmlNode {
    public var name: String

    // 字段对包内 extend 可见，命名加 `Child` / `attr` 前缀以避免与公开 API
    // `firstChild` / `attributes()` 同名。
    var headChild: ?XmlNode = None
    var tailChild: ?XmlNode = None

    let attrOrder: ArrayList<XmlAttribute> = ArrayList<XmlAttribute>()
    /** 仅在属性数超过 `ATTR_INDEX_THRESHOLD` 时实例化的名称索引。 */
    var attrIndex: ?HashMap<String, XmlAttribute> = None

    init(doc: XmlDocument, name: String) {
        super(doc)
        this.name = name
    }

    public override func kind(): XmlNodeKind {
        XmlNodeKind.Element(this)
    }

    // ==================================================================
    // 属性容器内部工具
    // ==================================================================

    /**
     * 按名称查找属性：≤ 阈值线性扫描；超阈值后走名称索引。
     */
    func findAttr(name: String): ?XmlAttribute {
        match (attrIndex) {
            case Some(m) => m.get(name)
            case None =>
                let n = attrOrder.size
                var i = 0
                while (i < n) {
                    let a = attrOrder[i]
                    if (a.name == name) {
                        return Some(a)
                    }
                    i++
                }
                None
        }
    }

    /**
     * 追加一个新属性（调用方已确认无同名属性）。
     * 当总数刚跨过阈值时一次性构建 `attrIndex`。
     */
    func addNewAttr(attr: XmlAttribute): Unit {
        attrOrder.add(attr)
        match (attrIndex) {
            case Some(m) => m[attr.name] = attr
            case None =>
                if (attrOrder.size > ATTR_INDEX_THRESHOLD) {
                    let m = HashMap<String, XmlAttribute>()
                    let n = attrOrder.size
                    var i = 0
                    while (i < n) {
                        let a = attrOrder[i]
                        m[a.name] = a
                        i++
                    }
                    attrIndex = Some(m)
                }
        }
    }

    /** 从名称索引（若已建）中移除一条记录；不动 `attrOrder`。 */
    func dropFromAttrIndex(name: String): Unit {
        if (let Some(m) <- attrIndex) {
            m.remove(name)
        }
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
