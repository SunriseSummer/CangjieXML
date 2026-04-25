package cangjie_xml.dom

/**
 * XML DOM 的统一节点基类。
 *
 * - **共享导航状态**：`prev` / `next` / `parent` / `document` 四条引用对所有
 *   具体节点完全一致，集中放到抽象基类避免子类重复实现链表维护。
 * - **封闭性**：`sealed` 保证外部不可派生，`abstract` 保证不可实例化。
 * - **模式匹配**：公共入口仍为 `kind(): XmlNodeKind`，由 enum 承载，与基类形态无关。
 *
 * ## 所有权模型
 *
 * - 每个节点都"属于"一个 `XmlDocument`（`document` 属性不可为空）。
 * - 父节点只能是 `XmlElement`；直接挂在 `XmlDocument` 下的节点（声明、根元素、
 *   顶层注释等），其 `parent` 为 `None`，但 `document` 仍指向所属文档。
 * - 兄弟关系通过节点内部的双向链表维护。
 */
sealed abstract class XmlNode {
    // ------------------------------------------------------------------
    // 内部导航状态（包内可见，仅供 XmlElement / XmlDocument 维护链表使用）
    // ------------------------------------------------------------------
    // `documentRef` 允许在 XmlDocument 构造早期为 None，
    // 所有其他具体节点类型构造时必须传入非空文档。
    var documentRef: ?XmlDocument = None
    var parentRef: ?XmlElement = None
    var prevRef: ?XmlNode = None
    var nextRef: ?XmlNode = None
    // 对 Document 的直接子节点，inDocFlag=true 表示它直接挂在文档下；
    // 对挂在 Element 下的节点，inDocFlag=false。
    var inDocFlag: Bool = false

    init() {}

    init(document: XmlDocument) {
        this.documentRef = Some(document)
    }

    /**
     * 节点所属的 `XmlDocument`。
     *
     * 对 `XmlDocument` 自身而言，返回自己。
     */
    public open prop document: XmlDocument {
        get() {
            match (documentRef) {
                case Some(d) => d
                case None => throw Exception("XmlNode has no owning XmlDocument (internal invariant violated)")
            }
        }
    }

    /**
     * 父元素（若本节点位于某个 `XmlElement` 下）。
     *
     * 对根元素、顶层声明/注释、以及尚未插入到树中的节点，返回 `None`。
     */
    public prop parent: ?XmlElement {
        get() { parentRef }
    }

    /**
     * 前一个兄弟节点；若本节点为首个子节点，返回 `None`。
     */
    public prop previousSibling: ?XmlNode {
        get() { prevRef }
    }

    /**
     * 后一个兄弟节点；若本节点为末尾子节点，返回 `None`。
     */
    public prop nextSibling: ?XmlNode {
        get() { nextRef }
    }

    /**
     * 返回当前节点的 `XmlNodeKind`，用于模式匹配。
     *
     * 由具体子类实现。
     */
    public func kind(): XmlNodeKind

    /**
     * 从父节点（或所属文档）移除自己。
     *
     * - 若节点当前不在任何父节点 / 文档中，返回 `false`。
     * - 成功移除后，节点的 `parent` / `previousSibling` / `nextSibling`
     *   会被重置为 `None`，但 `document` 属性保持不变，允许后续重新插入
     *   到同一文档的其他位置。
     */
    public func removeSelf(): Bool {
        if (let Some(parentEl) <- parentRef) {
            return parentEl.removeChild(this)
        }
        if (inDocFlag) {
            match (documentRef) {
                case Some(d) => return d.removeChild(this)
                case None => return false
            }
        }
        false
    }

    /**
     * 判断两个 XmlNode 是否引用同一个对象（身份比较）。
     *
     * XML DOM 中节点是可变、带身份的实体；以身份相等为默认更符合直觉。
     */
    public operator func ==(other: XmlNode): Bool {
        refEq(this, other)
    }

    public operator func !=(other: XmlNode): Bool {
        !refEq(this, other)
    }
}
