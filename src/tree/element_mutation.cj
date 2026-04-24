/*
 * tree — Element 变更 API（Phase 4b）
 *
 * 对应 libxml2: `xmlAddChild` / `xmlAddPrevSibling` / `xmlAddNextSibling` /
 * `xmlReplaceNode` / `xmlUnlinkNode` / `xmlSetProp` / `xmlUnsetProp`。
 *
 * 语义对齐 W3C DOM Level 2 `Node.*Child` 家族，但做了 libxml2 / 现代 DOM 的
 * 约定：
 *   - 插入已有父的节点会**自动先 detach**（非抛错）。这对应 DOM 的"move
 *     instead of clone"，与 `document.body.appendChild(foo)` 的浏览器行为一致；
 *   - 拒绝把 `Document` / `DoctypeNode` 作为 Element 的 child（保持树根层次
 *     不变，与 libxml2 拒绝 `XML_DOCUMENT_NODE` 挂到非根位置一致）；
 *   - 拒绝自插入与祖先插入（会造成环）。所有违规抛 `XmlException(Other)`。
 *
 * 身份比较：`ArrayList.indexOf` 需要元素实现 `Equatable`，`Node` 没有统一
 * 的相等语义（Element 按 QName 比较会把"同名双胞胎"误判），所以这里用 `refEq`
 * 做线性扫描，O(n) 在典型 DOM 子节点数下完全可接受，且语义与用户预期一致。
 */
package cangjie_xml.tree

import std.collection.*
import cangjie_xml.core.*

extend Element {
    /* ---------- 子节点：查询 ---------- */

    /**
     * 在直接子节点中按**引用身份**查找 `n` 的索引；未命中返回 `-1`。
     * 不用 `==` 因为 `Node` 无统一相等语义（重复内容的 TextNode 合法共存）。
     */
    public func indexOfChild(n: Node): Int64 {
        var i = 0
        while (i < childrenImpl.size) {
            if (nodeRefEq(childrenImpl[i], n)) {
                return i
            }
            i++
        }
        return -1
    }

    /** 该节点是否为本元素的直接子。 */
    public func hasChild(n: Node): Bool {
        return indexOfChild(n) >= 0
    }

    /* ---------- 子节点：插入 ---------- */

    /**
     * 在末尾追加一个子节点。
     *
     * - `n` 若已有父，会先被 detach；
     * - 不允许 `Document` / `DoctypeNode` 作为 child；
     * - 不允许自插入 / 祖先插入（成环）。
     */
    public func appendChild(n: Node): Unit {
        validateInsertable(n)
        let _ = removeFromParent(n)
        setParent(n, this)
        childrenImpl.add(n)
    }

    /** 在开头插入一个子节点。 */
    public func prependChild(n: Node): Unit {
        validateInsertable(n)
        let _ = removeFromParent(n)
        setParent(n, this)
        childrenImpl.add(n, at: 0)
    }

    /**
     * 在 `reference` 之前插入 `newNode`。
     *
     * - `reference` 必须是本元素的直接子，否则抛 `XmlException`；
     * - `newNode` 与 `reference` 同一引用时视为 no-op。
     */
    public func insertBefore(newNode: Node, reference: Node): Unit {
        if (nodeRefEq(newNode, reference)) {
            return
        }
        let idx = requireChildIndex(reference, "insertBefore")
        validateInsertable(newNode)
        let _ = removeFromParent(newNode)
        // removeFromParent 可能让 reference 索引变化（当 newNode 和 reference 同在
        // 本元素时）；重新查找。
        let idx2 = indexOfChild(reference)
        setParent(newNode, this)
        if (idx2 < 0) {
            // 理论不会发生（reference 不是 newNode 自己，前面已经判过）。
            childrenImpl.add(newNode, at: idx)
        } else {
            childrenImpl.add(newNode, at: idx2)
        }
    }

    /** 在 `reference` 之后插入 `newNode`。 */
    public func insertAfter(newNode: Node, reference: Node): Unit {
        if (nodeRefEq(newNode, reference)) {
            return
        }
        let _ = requireChildIndex(reference, "insertAfter")
        validateInsertable(newNode)
        let _ = removeFromParent(newNode)
        let idx2 = indexOfChild(reference)
        setParent(newNode, this)
        if (idx2 < 0) {
            childrenImpl.add(newNode)
        } else {
            childrenImpl.add(newNode, at: idx2 + 1)
        }
    }

    /* ---------- 子节点：移除 / 替换 ---------- */

    /**
     * 若 `n` 是直接子则移除并返回 true；否则返回 false（不抛）。
     * `n` 被移除后 `parent()` 返回 `None`，可重新挂载。
     */
    public func removeChild(n: Node): Bool {
        let i = indexOfChild(n)
        if (i < 0) {
            return false
        }
        let _ = childrenImpl.remove(at: i)
        clearParent(n)
        return true
    }

    /** 按索引移除子节点并返回之；越界抛 `IndexOutOfBoundsException`。 */
    public func removeChildAt(i: Int64): Node {
        let n = childrenImpl[i]
        let _ = childrenImpl.remove(at: i)
        clearParent(n)
        return n
    }

    /** 清空所有子节点。被移除节点的 `parent` 全部置 `None`。 */
    public func clearChildren(): Unit {
        for (c in childrenImpl) {
            clearParent(c)
        }
        childrenImpl.clear()
    }

    /**
     * 用 `newNode` 替换直接子 `oldNode`。
     *
     * - 若 `newNode === oldNode` 为 no-op；
     * - `oldNode` 必须是本元素直接子，否则抛 `XmlException`；
     * - `newNode` 若已有父会先 detach；
     * - 类型限制同 `appendChild`。
     */
    public func replaceChild(oldNode: Node, newNode: Node): Unit {
        if (nodeRefEq(oldNode, newNode)) {
            return
        }
        let _ = requireChildIndex(oldNode, "replaceChild")
        validateInsertable(newNode)
        let _ = removeFromParent(newNode)
        // newNode 摘除后 old 的索引可能向前挪（当 newNode 是 oldNode 的兄弟时）；
        // 重新定位 old。
        let idx = indexOfChild(oldNode)
        if (idx < 0) {
            // 极端情况：newNode == oldNode 的兄弟被 removeFromParent 挪动时，
            // 这里应该仍能找到 oldNode；找不到则视为 oldNode 同步移除后补追加。
            setParent(newNode, this)
            childrenImpl.add(newNode)
            return
        }
        clearParent(oldNode)
        setParent(newNode, this)
        childrenImpl[idx] = newNode
    }

    /* ---------- 属性：变更 ---------- */

    /**
     * 设置属性。按 `(localName, uri)` 匹配现有属性：命中则替换，未命中则追加。
     * 前缀不参与匹配（符合命名空间语义）。
     */
    public func setAttribute(attr: Attr): Unit {
        var i = 0
        while (i < attributesImpl.size) {
            let existing = attributesImpl[i]
            if (existing.qname.localName == attr.qname.localName && existing.qname.uri == attr.qname.uri) {
                attributesImpl[i] = attr
                return
            }
            i++
        }
        attributesImpl.add(attr)
    }

    /** 便捷重载：按 QName + 字符串值设置；构造 `Attr` 由本方法完成。 */
    public func setAttribute(qname: QName, value: String): Unit {
        setAttribute(Attr(qname, value))
    }

    /**
     * 按 `(localName, uri)` 移除属性。
     * Returns: 是否真的移除了（命中 → true；未命中 → false）。
     */
    public func removeAttribute(localName: String, uri!: ?String = None): Bool {
        var i = 0
        while (i < attributesImpl.size) {
            let a = attributesImpl[i]
            if (a.qname.localName == localName && a.qname.uri == uri) {
                let _ = attributesImpl.remove(at: i)
                return true
            }
            i++
        }
        return false
    }

    /** 清空所有属性（含 xmlns 声明）。 */
    public func clearAttributes(): Unit {
        attributesImpl.clear()
    }

    /* ---------- 内部校验 ---------- */

    /**
     * 校验 `n` 可作为本元素的子节点。违规抛 `XmlException(Other)`。
     *
     * 规则：
     *   1. 不允许 `Document`（文档是根容器，不是节点子）；
     *   2. 不允许 `DoctypeNode`（DOCTYPE 通过 `Document.doctype` 承载，不进子列表）；
     *   3. 不允许 `n` 就是 `this`（自插入 → 直接成环）；
     *   4. 不允许 `n` 是 `this` 的祖先（插入后 `this` 既是 `n` 的子又是父的父）。
     */
    func validateInsertable(n: Node): Unit {
        match (n) {
            case _: Document =>
                throw XmlException(XmlError.Other(Position.unknown(),
                    "Element: cannot insert Document as a child"))
            case _: DoctypeNode =>
                throw XmlException(XmlError.Other(Position.unknown(),
                    "Element: cannot insert DoctypeNode as a child"))
            case e: Element =>
                if (refEq(e, this)) {
                    throw XmlException(XmlError.Other(Position.unknown(),
                        "Element: cannot insert an element into itself"))
                }
                var cur: ?Element = this.parentImpl
                while (true) {
                    match (cur) {
                        case None => break
                        case Some(p) where refEq(p, e) =>
                            throw XmlException(XmlError.Other(Position.unknown(),
                                "Element: insertion would create a cycle"))
                        case Some(p) => cur = p.parentImpl
                    }
                }
            case _ => ()
        }
    }

    /** 封装"reference 必须是本元素直接子"的错误路径。 */
    func requireChildIndex(ref: Node, op: String): Int64 {
        let i = indexOfChild(ref)
        if (i < 0) {
            throw XmlException(XmlError.Other(Position.unknown(),
                "Element.${op}: reference node is not a child of this element"))
        }
        return i
    }
}
