/*
 * tree — 节点 detach：从父节点中摘除自身
 *
 * 所有可挂到 `Element` 下的节点（`Element` 自身 + 叶子节点）都提供 `detach()`。
 * 语义等同 W3C DOM `Node.remove()` / libxml2 `xmlUnlinkNode`：
 *   - 若当前节点无父（根元素、已摘除节点），`detach()` 为无操作；
 *   - 否则从父元素的 children 中移除自身并清空 `parentImpl`；
 *   - 返回调用者自身，便于链式编程。
 *
 * `Document` 是整棵树的根容器，不实现 `detach()`（它没有 parent 概念）。
 * `DoctypeNode` 虽然在 `Document.doctype` 独占一席，但当前 MVP 并不把它挂到
 * Element 之下；保留 `parentImpl` 字段是为了未来 DTD 内部子集建模。
 *
 * 实现策略：
 *   - 通过 `extend` 给每个具体类新增一个 `detach()` 公开方法；
 *   - 内部复用包级 `removeFromParent(node)` 帮助函数，保持单一真相源；
 *   - `removeFromParent` 使用 `refEq` 做身份比较 —— Element 子列表里可能
 *     存在两个数据相等但不同一的 TextNode（例如并列两段相同文字），只能按
 *     引用身份定位被移除者。
 */
package cangjie_xml.tree

/* ---------- 包级工具：按引用身份从父元素中移除一个子节点 ---------- */

/**
 * 按**引用身份**比较两个 Node。`refEq` 要求 `Class-Object`，而 `Node` 是
 * sealed interface；通过类型模式把两侧落到具体 class（所有 Node 分支都是
 * class），然后比较 Object 引用。不在同一分支 → 必然非同一对象。
 */
func nodeRefEq(a: Node, b: Node): Bool {
    match (a) {
        case ea: Element => match (b) {
            case eb: Element => return refEq(ea, eb)
            case _ => return false
        }
        case ta: TextNode => match (b) {
            case tb: TextNode => return refEq(ta, tb)
            case _ => return false
        }
        case ca: CdataSection => match (b) {
            case cb: CdataSection => return refEq(ca, cb)
            case _ => return false
        }
        case cma: CommentNode => match (b) {
            case cmb: CommentNode => return refEq(cma, cmb)
            case _ => return false
        }
        case pia: PiNode => match (b) {
            case pib: PiNode => return refEq(pia, pib)
            case _ => return false
        }
        case dta: DoctypeNode => match (b) {
            case dtb: DoctypeNode => return refEq(dta, dtb)
            case _ => return false
        }
        case da: Document => match (b) {
            case db: Document => return refEq(da, db)
            case _ => return false
        }
        case _ => return false
    }
}

/**
 * 若 `n` 有父，则从父元素的 children 列表里移除 `n` 并清空其 `parentImpl`。
 * 已孤立节点调用为 no-op。不抛异常。
 *
 * Returns: 是否真的发生了移除（有父 → true；无父 → false）。
 */
func removeFromParent(n: Node): Bool {
    let parent = parentOf(n) ?? return false
    var i = 0
    let list = parent.childrenImpl
    while (i < list.size) {
        if (nodeRefEq(list[i], n)) {
            let _ = list.remove(at: i)
            clearParent(n)
            return true
        }
        i++
    }
    // 结构不自洽：`n.parent == parent` 但 `parent.children` 不含 `n`。
    // 仍然清掉 parent 指针以便调用方恢复使用。
    clearParent(n)
    return false
}

/** 查找一个节点当前的父 Element（仅对可挂载节点类型有效）。 */
func parentOf(n: Node): ?Element {
    match (n) {
        case e: Element => return e.parentImpl
        case t: TextNode => return t.parentImpl
        case c: CdataSection => return c.parentImpl
        case cm: CommentNode => return cm.parentImpl
        case pi: PiNode => return pi.parentImpl
        case dt: DoctypeNode => return dt.parentImpl
        case _ => return None
    }
}

/** 清空一个节点的 parent 指针。Document 无 parent，忽略。 */
func clearParent(n: Node): Unit {
    match (n) {
        case e: Element => e.parentImpl = None
        case t: TextNode => t.parentImpl = None
        case c: CdataSection => c.parentImpl = None
        case cm: CommentNode => cm.parentImpl = None
        case pi: PiNode => pi.parentImpl = None
        case dt: DoctypeNode => dt.parentImpl = None
        case _ => ()
    }
}

/** 设置一个节点的 parent 指针。仅对可挂载节点类型有效，Document 忽略。 */
func setParent(n: Node, parent: Element): Unit {
    match (n) {
        case e: Element => e.parentImpl = Some(parent)
        case t: TextNode => t.parentImpl = Some(parent)
        case c: CdataSection => c.parentImpl = Some(parent)
        case cm: CommentNode => cm.parentImpl = Some(parent)
        case pi: PiNode => pi.parentImpl = Some(parent)
        case dt: DoctypeNode => dt.parentImpl = Some(parent)
        case _ => ()
    }
}

/* ---------- 各节点类型的 detach() 便捷方法 ---------- */

extend Element {
    /**
     * 从当前父元素中摘除自身。根元素 / 已孤立元素为 no-op。
     *
     * 摘除后可继续把自身重新挂到任何 Element（同树或跨树）。不破坏子树结构。
     */
    public func detach(): Unit {
        let _ = removeFromParent(this)
    }
}

extend TextNode {
    public func detach(): Unit {
        let _ = removeFromParent(this)
    }
}

extend CdataSection {
    public func detach(): Unit {
        let _ = removeFromParent(this)
    }
}

extend CommentNode {
    public func detach(): Unit {
        let _ = removeFromParent(this)
    }
}

extend PiNode {
    public func detach(): Unit {
        let _ = removeFromParent(this)
    }
}
