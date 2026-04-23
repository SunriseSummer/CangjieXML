package cangjie_xml.dom

/**
 * XML 文档：整棵 DOM 树的根容器。
 *
 * ## 职责
 *
 * - **节点工厂**：M1 阶段所有具体节点类型的构造函数均为包级（`internal`），
 *   用户只能通过 `doc.createXxx()` 创建，借此强制"每个节点都归属一个文档"。
 * - **文档级容器**：持有一条可选的 XML 声明、零或一个根元素，以及任意数量的
 *   顶层注释 / 未知节点（`<!DOCTYPE ...>` 等）。
 * - **文档级元信息**：当前承载 `hasBom` / `writeBom`，未来还可承载字符集等。
 *
 * ## M1 范围
 *
 * M1 只提供手工构造、遍历和查询；`parseString` / `parseBytes` / `loadFile`
 * 等解析入口将在 M3 引入。M2 的 `writeToString` / `saveFile` 会与 Writer 一起上线。
 */
public class XmlDocument <: XmlNode {

    // 所有顶层节点（声明、根元素、注释、未知节点）以链表形式存储，
    // 与 XmlElement 保持一致的结构语义，便于后续 Visit / Writer 统一遍历。
    private var _firstChild: ?XmlNode = None
    private var _lastChild: ?XmlNode = None

    /** 文档是否检测到 / 将写出 UTF-8 BOM。 */
    public var hasBom: Bool = false
    public var writeBom: Bool = false

    /** 创建一个空文档，既无声明也无根元素。 */
    public init() {
        super()
        // XmlDocument 是自己的 document，由 prop override 处理
    }

    public override prop document: XmlDocument {
        get() { this }
    }

    public override func kind(): XmlNodeKind {
        XmlNodeKind.Document(this)
    }

    // ==================================================================
    // 便捷访问
    // ==================================================================

    /** 文档的 XML 声明（若存在）。 */
    public prop declaration: ?XmlDeclaration {
        get() {
            var cur = _firstChild
            while (let Some(n) <- cur) {
                match (n.kind()) {
                    case Declaration(d) => return Some(d)
                    case _ => ()
                }
                cur = n._next
            }
            None
        }
    }

    /** 文档的根元素（若存在）。 */
    public prop rootElement: ?XmlElement {
        get() {
            var cur = _firstChild
            while (let Some(n) <- cur) {
                match (n.kind()) {
                    case Element(e) => return Some(e)
                    case _ => ()
                }
                cur = n._next
            }
            None
        }
    }

    /** 首个顶层节点（任意类型）。 */
    public prop firstChild: ?XmlNode {
        get() { _firstChild }
    }

    /** 末尾顶层节点（任意类型）。 */
    public prop lastChild: ?XmlNode {
        get() { _lastChild }
    }

    /** 按顺序遍历所有顶层节点。 */
    public func childNodes(): Iterable<XmlNode> {
        XmlChildIter(_firstChild)
    }

    // ==================================================================
    // 节点工厂（M1 的核心入口）
    // ==================================================================

    /**
     * 创建一个归属于本文档的元素。新元素未挂接到任何父节点，需调用方
     * 自行 `appendChild` / `prependChild` / `insertChildBefore`。
     */
    public func createElement(name: String): XmlElement {
        XmlElement(this, name)
    }

    /**
     * 创建一个归属于本文档的文本节点。`cdata = true` 时该节点视作 CDATA。
     */
    public func createText(value: String, cdata!: Bool = false): XmlText {
        XmlText(this, value, cdata)
    }

    /** 创建注释节点。 */
    public func createComment(value: String): XmlComment {
        XmlComment(this, value)
    }

    /**
     * 创建 XML 声明节点。`value` 省略时使用默认声明：`xml version="1.0" encoding="UTF-8"`。
     */
    public func createDeclaration(value!: ?String = None): XmlDeclaration {
        let v = value ?? "xml version=\"1.0\" encoding=\"UTF-8\""
        XmlDeclaration(this, v)
    }

    /** 创建未知节点（用于 `<!DOCTYPE ...>` 等）。 */
    public func createUnknown(value: String): XmlUnknown {
        XmlUnknown(this, value)
    }

    // ==================================================================
    // 顶层节点增删
    // ==================================================================

    /**
     * 在顶层末尾追加节点。
     *
     * 约束：
     * - 不允许插入 `XmlDocument`；
     * - 最多一个 `XmlElement`（根元素）；
     * - 最多一个 `XmlDeclaration`，且必须为首个顶层节点；
     * - 节点必须归属本文档。
     */
    public func appendChild(node: XmlNode): Unit {
        _checkTopLevelInsertable(node)
        node.removeSelf()
        _linkAtEnd(node)
    }

    /**
     * 在顶层开头插入节点。其他约束同 `appendChild`。
     */
    public func prependChild(node: XmlNode): Unit {
        _checkTopLevelInsertable(node)
        node.removeSelf()
        match (_firstChild) {
            case None => _linkAtEnd(node)
            case Some(first) =>
                node._prev = None
                node._next = Some(first)
                first._prev = Some(node)
                _firstChild = Some(node)
                node._parentElement = None
                node._document = Some(this)
                node._inDocument = true
        }
    }

    /**
     * 从文档移除顶层节点。成功返回 `true`；若 `node` 不是本文档的直接顶层节点，返回 `false`。
     */
    public func removeChild(node: XmlNode): Bool {
        if (!node._inDocument) {
            return false
        }
        // 检查确实挂在本文档上
        match (node._document) {
            case Some(d) => if (!refEq(d, this)) { return false }
            case None => return false
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
        node._inDocument = false
        true
    }

    /**
     * 清空文档所有顶层节点，重置为初始状态。`hasBom` / `writeBom` 不受影响。
     */
    public func clear(): Unit {
        var cur = _firstChild
        while (let Some(n) <- cur) {
            let nxt = n._next
            n._prev = None
            n._next = None
            n._inDocument = false
            cur = nxt
        }
        _firstChild = None
        _lastChild = None
    }

    // ==================================================================
    // 内部
    // ==================================================================

    private func _linkAtEnd(node: XmlNode): Unit {
        node._parentElement = None
        node._document = Some(this)
        node._inDocument = true
        node._prev = _lastChild
        node._next = None
        match (_lastChild) {
            case Some(l) => l._next = Some(node)
            case None => _firstChild = Some(node)
        }
        _lastChild = Some(node)
    }

    private func _checkTopLevelInsertable(node: XmlNode): Unit {
        match (node.kind()) {
            case Document(_) => throw_("cannot insert XmlDocument into another XmlDocument")
            case Text(_) => throw_("XmlText is not allowed at the document top-level")
            case _ => ()
        }
        // 文档归属一致性：允许节点的 _document 为 None（代表尚未插入过任何文档），
        // 或已经指向本文档；其他情况禁止跨文档插入。
        match (node._document) {
            case None => ()
            case Some(d) =>
                if (!refEq(d, this)) {
                    throw_("cross-document insertion is not allowed")
                }
        }
        // 根元素与声明的唯一性约束
        match (node.kind()) {
            case Element(_) =>
                match (rootElement) {
                    case Some(_) => throw_("XmlDocument already has a root element")
                    case None => ()
                }
            case Declaration(_) =>
                match (declaration) {
                    case Some(_) => throw_("XmlDocument already has an XML declaration")
                    case None => ()
                }
            case _ => ()
        }
    }
}
