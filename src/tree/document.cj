/*
 * tree — Document：DOM 根容器
 *
 * 对应 libxml2: `xmlDoc`（`type == XML_DOCUMENT_NODE`）。
 *
 * 结构：
 *   - `xmlDecl`：XML 声明（版本 / 编码 / standalone）。**总是**存在：即便源文档
 *     省略声明，`XmlParser` 也会合成一条默认声明事件，DocumentBuilder 据此构造。
 *   - `doctype`：可选 DOCTYPE 头。
 *   - `root`：唯一的根元素；良构文档必有。
 *   - `prolog` / `epilog`：根元素前 / 后的 Comment / PI 节点序列（空白已过滤）。
 *
 * 对齐 libxml2 `xmlDoc` 的主要字段但做了显式拆分，避免 libxml2 里 `xmlDoc` 和
 * `xmlNode` 共享布局导致的 downcast 陷阱。
 */
package cangjie_xml.tree

import std.collection.*
import cangjie_xml.core.*
import cangjie_xml.parser.*

public class Document <: Node {
    public let xmlDecl: XmlDecl
    public let doctype: ?DoctypeNode
    public let root: Element
    let prologImpl: ArrayList<Node>
    let epilogImpl: ArrayList<Node>

    init(
        xmlDecl: XmlDecl,
        doctype: ?DoctypeNode,
        root: Element,
        prolog: ArrayList<Node>,
        epilog: ArrayList<Node>
    ) {
        this.xmlDecl = xmlDecl
        this.doctype = doctype
        this.root = root
        this.prologImpl = prolog
        this.epilogImpl = epilog
    }

    public func position(): Position {
        return xmlDecl.position
    }

    public func nodeKind(): NodeKind {
        return NodeKind.DocumentNode
    }

    /** 根元素前的 Comment / PI 节点（按源顺序）。只读迭代器视图。 */
    public func prolog(): Iterator<Node> {
        return prologImpl.iterator()
    }

    /** 根元素后的 Comment / PI 节点（按源顺序）。 */
    public func epilog(): Iterator<Node> {
        return epilogImpl.iterator()
    }

    public func toString(): String {
        return "Document(root=${root.qname.lexical()}, prolog=${prologImpl.size}, epilog=${epilogImpl.size})"
    }
}
