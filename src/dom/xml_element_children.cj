package cangjie_xml.dom

/**
 * `XmlElement` 子节点 API：插入、删除、遍历、导航。
 *
 * `checkInsertable` 拆为若干小辅助（自环检查、节点类型检查、文档归属检查、
 * 祖先环检查），主路径无嵌套；`prependChild` 与 `insertChildBefore` 复用
 * `linkAtEnd` / `linkBefore` 底层挂接逻辑。
 */
extend XmlElement {

    // ==================================================================
    // 插入 / 删除
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
        checkInsertable(node)
        detachFromCurrent(node)
        linkAtEnd(node)
    }

    /** 在开头插入一个子节点。其他约束同 `appendChild`。 */
    public func prependChild(node: XmlNode): Unit {
        checkInsertable(node)
        detachFromCurrent(node)
        match (headChild) {
            case None => linkAtEnd(node)
            case Some(first) => linkBefore(node, first)
        }
    }

    /**
     * 将 `node` 插入到 `reference` 之前。
     *
     * - `reference` 必须是本元素的直接子节点，否则抛出 `XmlException`。
     * - `node` 若在其他位置，会先被自动移除。
     */
    public func insertChildBefore(reference: XmlNode, node: XmlNode): Unit {
        if (!ownsAsChild(reference)) {
            throwDom("insertChildBefore: reference is not a child of this element")
        }
        checkInsertable(node)
        detachFromCurrent(node)
        linkBefore(node, reference)
    }

    /**
     * 从本元素移除指定子节点。
     *
     * - 成功返回 `true`，节点的 `parent` / `prev` / `next` 被清空；
     * - 若 `node` 不是本元素的直接子节点，返回 `false`（不抛异常）。
     */
    public func removeChild(node: XmlNode): Bool {
        if (!ownsAsChild(node)) {
            return false
        }
        unlinkNode(node)
        node.prevRef = None
        node.nextRef = None
        node.parentRef = None
        node.inDocFlag = false
        true
    }

    // ==================================================================
    // 遍历 / 导航
    // ==================================================================

    /** 遍历所有直接子节点（按顺序）。 */
    public func childNodes(): Iterable<XmlNode> {
        XmlChildIter(headChild)
    }

    /**
     * 遍历所有直接 **元素** 子节点；若指定 `name`，仅返回名称匹配的元素。
     */
    public func childElements(name!: ?String = None): Iterable<XmlElement> {
        XmlChildElementIter(headChild, name)
    }

    /** 返回首个匹配的子元素（若指定 `name` 则按名过滤）。 */
    public func firstChildElement(name!: ?String = None): ?XmlElement {
        var cur = headChild
        while (let Some(n) <- cur) {
            if (let Element(e) <- n.kind()) {
                if (elementMatchesName(e, name)) {
                    return Some(e)
                }
            }
            cur = n.nextRef
        }
        None
    }

    /** 首个子节点（任意类型）。 */
    public prop firstChild: ?XmlNode {
        get() { headChild }
    }

    /** 末尾子节点（任意类型）。 */
    public prop lastChild: ?XmlNode {
        get() { tailChild }
    }

    /** 当前元素是否没有任何子节点。 */
    public func isEmpty(): Bool {
        match (headChild) {
            case None => true
            case Some(_) => false
        }
    }

    // ==================================================================
    // 内部：挂接 / 解挂 / 约束检查
    // ==================================================================

    /** 在 `reference` 之前挂入 `node`，假设调用方已完成约束检查与解挂。 */
    private func linkBefore(node: XmlNode, reference: XmlNode): Unit {
        let prev = reference.prevRef
        node.prevRef = prev
        node.nextRef = Some(reference)
        reference.prevRef = Some(node)
        match (prev) {
            case Some(p) => p.nextRef = Some(node)
            case None => headChild = Some(node)
        }
        node.parentRef = Some(this)
        node.documentRef = Some(this.document)
        node.inDocFlag = false
    }

    /** 从双向链表中把 `node` 摘下（调用方负责清空其字段）。 */
    private func unlinkNode(node: XmlNode): Unit {
        let prev = node.prevRef
        let next = node.nextRef
        match (prev) {
            case Some(p) => p.nextRef = next
            case None => headChild = next
        }
        match (next) {
            case Some(n) => n.prevRef = prev
            case None => tailChild = prev
        }
    }

    /** 合法性检查：任何一条约束失败立即抛 `XmlException`。 */
    private func checkInsertable(node: XmlNode): Unit {
        rejectSelfInsertion(node)
        rejectIllegalKindAsChild(node)
        rejectCrossDocument(node)
        rejectAncestorCycle(node)
    }

    private func rejectSelfInsertion(node: XmlNode): Unit {
        if (refEq(node, this)) {
            throwDom("cannot insert an element as its own child")
        }
    }

    private func rejectIllegalKindAsChild(node: XmlNode): Unit {
        match (node.kind()) {
            case Document(_) =>
                throwDom("cannot insert XmlDocument as a child node")
            case Declaration(_) =>
                throwDom("XmlDeclaration must be a direct child of XmlDocument, not XmlElement")
            case _ => ()
        }
    }

    private func rejectCrossDocument(node: XmlNode): Unit {
        if (!refEq(node.document, this.document)) {
            throwDom("cross-document insertion is not allowed; create the child via this.document")
        }
    }

    private func rejectAncestorCycle(node: XmlNode): Unit {
        var anc: ?XmlElement = this.parentRef
        while (let Some(a) <- anc) {
            if (refEq(a, node)) {
                throwDom("cannot insert an ancestor element as a descendant (would create a cycle)")
            }
            anc = a.parentRef
        }
    }
}

/** 辅助：把"可选名称过滤"的比较从 firstChildElement 主路径提出。 */
func elementMatchesName(e: XmlElement, name: ?String): Bool {
    match (name) {
        case None => true
        case Some(nm) => e.name == nm
    }
}
