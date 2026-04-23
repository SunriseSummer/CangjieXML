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
 * ## 元素名
 *
 * M1 阶段不强制校验元素名合法性（例如 `XML` 前缀、空格、非法字符等）——
 * 那是 Parser 在 M3 的职责。对手工构造使用者，我们默认"你知道自己在写什么"。
 *
 * ## 线程约束
 *
 * DOM 模型本身不持有锁。并发场景下，多个 writer 或读写混合访问同一 `XmlElement`
 * 须由外部同步。M7 引入的 `batch` 层仅支持只读共享。
 */
public class XmlElement <: XmlNode {
    public var name: String

    private var _firstChild: ?XmlNode = None
    private var _lastChild: ?XmlNode = None

    private let _attrOrder: ArrayList<XmlAttribute> = ArrayList<XmlAttribute>()
    private let _attrIndex: HashMap<String, XmlAttribute> = HashMap<String, XmlAttribute>()

    init(doc: XmlDocument, name: String) {
        super(doc)
        this.name = name
    }

    public override func kind(): XmlNodeKind {
        XmlNodeKind.Element(this)
    }

    // ==================================================================
    // 属性 API
    // ==================================================================

    /**
     * 查找指定名称的属性值；不存在返回 `None`。
     */
    public func attribute(name: String): ?String {
        match (_attrIndex.get(name)) {
            case Some(a) => Some(a.value)
            case None => None
        }
    }

    /**
     * 判断属性是否存在；若传入 `value`，则同时比较值。
     *
     * - `hasAttribute("id")`：仅检查属性是否存在。
     * - `hasAttribute("id", value: Some("1"))`：同时要求值等于 `"1"`。
     */
    public func hasAttribute(name: String, value!: ?String = None): Bool {
        match (_attrIndex.get(name)) {
            case None => false
            case Some(a) =>
                match (value) {
                    case None => true
                    case Some(v) => a.value == v
                }
        }
    }

    /**
     * 新增或覆盖属性。同名属性按"后写覆盖"语义处理，不改变属性插入顺序。
     */
    public func setAttribute(name: String, value: String): Unit {
        match (_attrIndex.get(name)) {
            case Some(a) => a.value = value
            case None =>
                let attr = XmlAttribute(name, value)
                _attrOrder.add(attr)
                _attrIndex[name] = attr
        }
    }

    /**
     * 删除指定名称的属性。
     *
     * - 成功删除返回 `true`；
     * - 属性不存在返回 `false`。
     */
    public func removeAttribute(name: String): Bool {
        match (_attrIndex.remove(name)) {
            case None => false
            case Some(_) =>
                // 同步从顺序数组中移除
                var i = 0
                while (i < _attrOrder.size) {
                    if (_attrOrder[i].name == name) {
                        _attrOrder.remove(at: i)
                        break
                    }
                    i++
                }
                true
        }
    }

    /**
     * 以插入顺序遍历所有属性。
     */
    public func attributes(): Iterable<XmlAttribute> {
        _attrOrder
    }

    /**
     * 当前元素的属性数量。
     */
    public func attributeCount(): Int64 {
        _attrOrder.size
    }

    // ==================================================================
    // 子节点 API
    // ==================================================================

    /**
     * 在末尾追加一个子节点。
     *
     * - 若节点已挂在其他父节点下，会先自动从原父节点移除（DOM 移动语义）；
     * - 节点必须与本元素属于同一 `XmlDocument`；
     * - 不允许将 `XmlDocument` / `XmlDeclaration` 作为元素的子节点——前者
     *   不可嵌入、后者只能位于文档级。违反时抛出 `XmlException`。
     */
    public func appendChild(node: XmlNode): Unit {
        _checkInsertable(node)
        _detachFromCurrent(node)
        _linkAtEnd(node)
    }

    /**
     * 在开头插入一个子节点。其他约束同 `appendChild`。
     */
    public func prependChild(node: XmlNode): Unit {
        _checkInsertable(node)
        _detachFromCurrent(node)
        match (_firstChild) {
            case None => _linkAtEnd(node)
            case Some(first) =>
                node._prev = None
                node._next = Some(first)
                first._prev = Some(node)
                _firstChild = Some(node)
                node._parentElement = Some(this)
                node._document = Some(this.document)
                node._inDocument = false
        }
    }

    /**
     * 将 `node` 插入到 `reference` 之前。
     *
     * - `reference` 必须是本元素的直接子节点，否则抛出 `XmlException`。
     * - `node` 若在其他位置，会先被自动移除。
     */
    public func insertChildBefore(reference: XmlNode, node: XmlNode): Unit {
        if (!_ownsAsChild(reference)) {
            throw_("insertChildBefore: reference is not a child of this element")
        }
        _checkInsertable(node)
        _detachFromCurrent(node)

        let prev = reference._prev
        node._prev = prev
        node._next = Some(reference)
        reference._prev = Some(node)
        match (prev) {
            case Some(p) => p._next = Some(node)
            case None => _firstChild = Some(node)
        }
        node._parentElement = Some(this)
        node._document = Some(this.document)
        node._inDocument = false
    }

    /**
     * 从本元素移除指定子节点。
     *
     * - 成功返回 `true`，节点的 `parent` / `prev` / `next` 被清空；
     * - 若 `node` 不是本元素的直接子节点，返回 `false`（不抛异常）。
     */
    public func removeChild(node: XmlNode): Bool {
        if (!_ownsAsChild(node)) {
            return false
        }
        let prev = node._prev
        let next = node._next
        match (prev) {
            case Some(p) => p._next = next
            case None => _firstChild = next
        }
        match (next) {
            case Some(n) => n._prev = prev
            case None => _lastChild = prev
        }
        node._prev = None
        node._next = None
        node._parentElement = None
        node._inDocument = false
        true
    }

    /**
     * 遍历所有直接子节点（按顺序）。
     */
    public func childNodes(): Iterable<XmlNode> {
        XmlChildIter(_firstChild)
    }

    /**
     * 遍历所有直接 **元素** 子节点；若指定 `name`，仅返回名称匹配的元素。
     */
    public func childElements(name!: ?String = None): Iterable<XmlElement> {
        XmlChildElementIter(_firstChild, name)
    }

    /**
     * 返回首个匹配的子元素（若指定 `name` 则按名过滤）。
     */
    public func firstChildElement(name!: ?String = None): ?XmlElement {
        var cur = _firstChild
        while (let Some(n) <- cur) {
            if (let Element(e) <- n.kind()) {
                match (name) {
                    case None => return Some(e)
                    case Some(nm) => if (e.name == nm) { return Some(e) }
                }
            }
            cur = n._next
        }
        None
    }

    /**
     * 首个子节点（任意类型）。
     */
    public prop firstChild: ?XmlNode {
        get() { _firstChild }
    }

    /**
     * 末尾子节点（任意类型）。
     */
    public prop lastChild: ?XmlNode {
        get() { _lastChild }
    }

    /**
     * 当前元素是否没有任何子节点。
     */
    public func isEmpty(): Bool {
        match (_firstChild) {
            case None => true
            case Some(_) => false
        }
    }

    // ==================================================================
    // 文本 API
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
        _collectTextContent(this, sb)
        sb.toString()
    }

    /**
     * 覆盖元素文本内容为单一文本子节点。
     *
     * 行为：
     * 1. 删除所有现有子节点；
     * 2. 追加一个新的非 CDATA `XmlText`（`value = value`）；
     *
     * 若仅需设置 CDATA，请改用 `XmlDocument.createText(value, cdata: true)` + `appendChild`。
     */
    public func setTextContent(value: String): Unit {
        // 清空所有子节点
        var cur = _firstChild
        while (let Some(n) <- cur) {
            let nxt = n._next
            n._prev = None
            n._next = None
            n._parentElement = None
            cur = nxt
        }
        _firstChild = None
        _lastChild = None

        let t = document.createText(value)
        _linkAtEnd(t)
    }

    // ==================================================================
    // 内部工具
    // ==================================================================

    func _linkAtEnd(node: XmlNode): Unit {
        node._parentElement = Some(this)
        node._document = Some(this.document)
        node._inDocument = false
        node._prev = _lastChild
        node._next = None
        match (_lastChild) {
            case Some(l) => l._next = Some(node)
            case None => _firstChild = Some(node)
        }
        _lastChild = Some(node)
    }

    private func _checkInsertable(node: XmlNode): Unit {
        if (refEq(node, this)) {
            throw_("cannot insert an element as its own child")
        }
        match (node.kind()) {
            case Document(_) => throw_("cannot insert XmlDocument as a child node")
            case Declaration(_) => throw_("XmlDeclaration must be a direct child of XmlDocument, not XmlElement")
            case _ => ()
        }
        // 文档归属一致性
        if (!refEq(node.document, this.document)) {
            throw_("cross-document insertion is not allowed; create the child via this.document")
        }
        // 不能把祖先作为子节点（避免成环）
        var anc: ?XmlElement = this._parentElement
        while (let Some(a) <- anc) {
            if (refEq(a, node)) {
                throw_("cannot insert an ancestor element as a descendant (would create a cycle)")
            }
            anc = a._parentElement
        }
    }

    private func _detachFromCurrent(node: XmlNode): Unit {
        node.removeSelf()
    }

    private func _ownsAsChild(node: XmlNode): Bool {
        match (node._parentElement) {
            case None => false
            case Some(p) => refEq(p, this)
        }
    }

    private static func _collectTextContent(el: XmlElement, sb: StringBuilder): Unit {
        var cur = el._firstChild
        while (let Some(n) <- cur) {
            match (n.kind()) {
                case Text(t) => sb.append(t.value)
                case Element(child) => _collectTextContent(child, sb)
                case _ => ()
            }
            cur = n._next
        }
    }
}

/** 便捷抛异常工具（避免到处写 `throw XmlException(...)`）。 */
func throw_(msg: String): Nothing {
    throw XmlException(msg)
}

// ======================================================================
// 迭代器：childNodes() / childElements()
// ======================================================================

class XmlChildIter <: Iterable<XmlNode> {
    private var first: ?XmlNode

    init(first: ?XmlNode) {
        this.first = first
    }

    public func iterator(): Iterator<XmlNode> {
        XmlChildIterator(first)
    }
}

class XmlChildIterator <: Iterator<XmlNode> {
    private var cur: ?XmlNode

    init(first: ?XmlNode) {
        this.cur = first
    }

    public func next(): ?XmlNode {
        match (cur) {
            case None => None
            case Some(n) =>
                cur = n._next
                Some(n)
        }
    }
}

class XmlChildElementIter <: Iterable<XmlElement> {
    private var first: ?XmlNode
    private var name: ?String

    init(first: ?XmlNode, name: ?String) {
        this.first = first
        this.name = name
    }

    public func iterator(): Iterator<XmlElement> {
        XmlChildElementIterator(first, name)
    }
}

class XmlChildElementIterator <: Iterator<XmlElement> {
    private var cur: ?XmlNode
    private let name: ?String

    init(first: ?XmlNode, name: ?String) {
        this.cur = first
        this.name = name
    }

    public func next(): ?XmlElement {
        while (let Some(n) <- cur) {
            let nxt = n._next
            match (n.kind()) {
                case Element(e) =>
                    cur = nxt
                    match (name) {
                        case None => return Some(e)
                        case Some(nm) => if (e.name == nm) { return Some(e) }
                    }
                case _ =>
                    cur = nxt
            }
        }
        None
    }
}
