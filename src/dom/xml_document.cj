package fastxml.dom

/**
 * XML 文档：整棵 DOM 树的根容器
 *
 * ## 职责
 *
 * - **节点工厂**：所有具体节点类型的构造函数均为包级（`internal`），
 *   用户只能通过 `doc.createXxx()` 创建，借此强制"每个节点都归属一个文档"
 * - **文档级容器**：持有一条可选的 XML 声明、零或一个根元素，以及任意数量的
 *   顶层注释 / 未知节点（`<!DOCTYPE ...>` 等）
 * - **文档级元信息**：`hasBom` / `writeBom`
 */
public class XmlDocument <: XmlNode {

    // 所有顶层节点（声明、根元素、注释、未知节点）以链表形式存储，
    // 与 XmlElement 保持一致的结构语义，便于后续 Visit / Writer 统一遍历
    private var headChild: ?XmlNode = None
    private var tailChild: ?XmlNode = None
    // 文档是否检测到 / 将写出 UTF-8 BOM
    public var hasBom: Bool = false
    public var writeBom: Bool = false

    // 创建一个空文档，既无声明也无根元素
    public init() {
        super()
        // XmlDocument 是自己的 document，由 prop override 处理
    }

    public override prop document: XmlDocument {
        get() {
            this
        }
    }

    public override func kind(): XmlNodeKind {
        XmlNodeKind.Document(this)
    }

    // ==================================================================
    // 便捷访问
    // ==================================================================

    // 文档的 XML 声明（若存在）
    public prop declaration: ?XmlDeclaration {
        get() {
            var cur = headChild
            while (let Some(n) <- cur) {
                match (n.kind()) {
                    case Declaration(d) => return Some(d)
                    case _ => ()
                }
                cur = n.nextRef
            }
            None
        }
    }

    // 文档的根元素（若存在）
    public prop rootElement: ?XmlElement {
        get() {
            var cur = headChild
            while (let Some(n) <- cur) {
                match (n.kind()) {
                    case Element(e) => return Some(e)
                    case _ => ()
                }
                cur = n.nextRef
            }
            None
        }
    }

    // 首个顶层节点（任意类型）
    public prop firstChild: ?XmlNode {
        get() {
            headChild
        }
    }

    // 末尾顶层节点（任意类型）
    public prop lastChild: ?XmlNode {
        get() {
            tailChild
        }
    }

    // 按顺序遍历所有顶层节点
    public func childNodes(): Iterable<XmlNode> {
        XmlChildIter(headChild)
    }

    // ==================================================================
    // 节点工厂
    // ==================================================================

    /**
     * 创建一个归属于本文档的元素。新元素未挂接到任何父节点，需调用方
     * 自行 `appendChild` / `prependChild` / `insertChildBefore`
     */
    public func createElement(name: String): XmlElement {
        XmlElement(this, name)
    }

    /**
     * 创建一个归属于本文档的文本节点。`cdata = true` 时该节点视作 CDATA
     */
    public func createText(value: String, cdata!: Bool = false): XmlText {
        XmlText(this, value, cdata)
    }

    // 创建注释节点
    public func createComment(value: String): XmlComment {
        XmlComment(this, value)
    }

    /**
     * 创建 XML 声明节点。`value` 省略时使用默认声明：`xml version="1.0" encoding="UTF-8"`
     */
    public func createDeclaration(value!: ?String = None): XmlDeclaration {
        let v = value ?? DEFAULT_DECLARATION_VALUE
        XmlDeclaration(this, v)
    }

    // 创建未知节点（用于 `<!DOCTYPE ...>` 等）
    public func createUnknown(value: String): XmlUnknown {
        XmlUnknown(this, value)
    }

    // ==================================================================
    // 顶层节点增删
    // ==================================================================

    /**
     * 在顶层末尾追加节点
     *
     * 约束：
     * - 不允许插入 `XmlDocument`；
     * - 最多一个 `XmlElement`（根元素）；
     * - 最多一个 `XmlDeclaration`，且必须为首个顶层节点；
     * - 节点必须归属本文档
     */
    public func appendChild(node: XmlNode): Unit {
        checkTopLevelInsertable(node)
        node.removeSelf()
        linkAtEnd(node)
    }

    /**
     * 在顶层开头插入节点。其他约束同 `appendChild`
     */
    public func prependChild(node: XmlNode): Unit {
        checkTopLevelInsertable(node, prepending: true)
        node.removeSelf()
        match (headChild) {
            case None => linkAtEnd(node)
            case Some(first) =>
                node.prevRef = None
                node.nextRef = Some(first)
                first.prevRef = Some(node)
                headChild = Some(node)
                node.parentRef = None
                node.documentRef = Some(this)
                node.inDocFlag = true
        }
    }

    /**
     * 从文档移除顶层节点。成功返回 `true`；若 `node` 不是本文档的直接顶层节点，返回 `false`
     */
    public func removeChild(node: XmlNode): Bool {
        if (!node.inDocFlag) {
            return false
        }
        // 检查确实挂在本文档上
        match (node.documentRef) {
            case Some(d) =>
                if (!refEq(d, this)) {
                    return false
                }
            case None => return false
        }

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
        node.prevRef = None
        node.nextRef = None
        node.inDocFlag = false
        true
    }

    /**
     * 清空文档所有顶层节点，重置为初始状态。`hasBom` / `writeBom` 不受影响
     */
    public func clear(): Unit {
        var cur = headChild
        while (let Some(n) <- cur) {
            let nxt = n.nextRef
            n.prevRef = None
            n.nextRef = None
            n.inDocFlag = false
            cur = nxt
        }
        headChild = None
        tailChild = None
    }

    // ==================================================================
    // 内部
    // ==================================================================

    private func linkAtEnd(node: XmlNode): Unit {
        node.parentRef = None
        node.documentRef = Some(this)
        node.inDocFlag = true
        node.prevRef = tailChild
        node.nextRef = None
        match (tailChild) {
            case Some(l) => l.nextRef = Some(node)
            case None => headChild = Some(node)
        }
        tailChild = Some(node)
    }

    private func checkTopLevelInsertable(node: XmlNode, prepending!: Bool = false): Unit {
        match (node.kind()) {
            case Document(_) => throwDom("cannot insert XmlDocument into another XmlDocument")
            case Text(_) => throwDom("XmlText is not allowed at the document top-level")
            case _ => ()
        }
        // 文档归属一致性：允许节点的 documentRef 为 None（代表尚未插入过任何文档），
        // 或已经指向本文档；其他情况禁止跨文档插入
        match (node.documentRef) {
            case None => ()
            case Some(d) =>
                if (!refEq(d, this)) {
                    throwDom("cross-document insertion is not allowed")
                }
        }
        // 根元素与声明的唯一性约束
        match (node.kind()) {
            case Element(_) => match (rootElement) {
                case Some(_) => throwDom("XmlDocument already has a root element")
                case None => ()
            }
            case Declaration(_) =>
                match (declaration) {
                    case Some(_) => throwDom("XmlDocument already has an XML declaration")
                    case None => ()
                }
                // 位置约束：Declaration 必须是首个顶层节点
                // - `appendChild`：要求文档为空，否则 decl 会落在别的节点之后；
                // - `prependChild`：允许——新 decl 会成为新 head
                if (!prepending && headChild.isSome()) {
                    throwDom(
                        "XmlDeclaration must be the first top-level node; " +
                            "use prependChild or insert the declaration before other nodes")
                }
            case _ =>
                // 反向约束：若首个顶层节点是 Declaration，其他节点不得 prepend
                // 到它之前——否则 Declaration 会不再是首节点，与 XML 规范冲突
                if (prepending && isFirstChildDeclaration()) {
                    throwDom(
                        "cannot prepend a node before the XmlDeclaration; " +
                            "declaration must remain the first top-level node")
                }
        }
    }

    // 是否存在首个顶层节点，且它是 `XmlDeclaration`。供位置约束检查使用
    private func isFirstChildDeclaration(): Bool {
        match (headChild) {
            case None => false
            case Some(h) => match (h.kind()) {
                case Declaration(_) => true
                case _ => false
            }
        }
    }
}
