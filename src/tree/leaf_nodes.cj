/*
 * tree — 叶子节点：TextNode / CdataSection / CommentNode / PiNode / DoctypeNode
 *
 * 对应 libxml2: `xmlNode` 的 `XML_TEXT_NODE` / `XML_CDATA_SECTION_NODE` /
 * `XML_COMMENT_NODE` / `XML_PI_NODE` / `XML_DTD_NODE`。
 *
 * 所有叶子节点共同特点：
 *   - 只带简单字符数据（+ PI 的 target）；
 *   - 没有子节点；
 *   - `parent` 在 `DocumentBuilder` 构造期由主循环写入，MVP 不提供变更 API。
 */
package cangjie_xml.tree

import cangjie_xml.core.*

/* ---------- TextNode：普通字符数据 ---------- */

public class TextNode <: Node {
    public let data: String
    let pos: Position
    var parentImpl: ?Element = None

    init(data: String, position!: Position = Position.unknown()) {
        this.data = data
        this.pos = position
    }

    public func position(): Position {
        return pos
    }

    public func nodeKind(): NodeKind {
        return NodeKind.TextNodeKind
    }

    public func parent(): ?Element {
        return parentImpl
    }

    public func toString(): String {
        return "Text(${data.size} chars)"
    }
}

/* ---------- CdataSection：CDATA 段 ---------- */

public class CdataSection <: Node {
    public let data: String
    let pos: Position
    var parentImpl: ?Element = None

    init(data: String, position!: Position = Position.unknown()) {
        this.data = data
        this.pos = position
    }

    public func position(): Position {
        return pos
    }

    public func nodeKind(): NodeKind {
        return NodeKind.CdataSectionNode
    }

    public func parent(): ?Element {
        return parentImpl
    }

    public func toString(): String {
        return "Cdata(${data.size} chars)"
    }
}

/* ---------- CommentNode：注释 ---------- */

public class CommentNode <: Node {
    public let data: String
    let pos: Position
    var parentImpl: ?Element = None

    init(data: String, position!: Position = Position.unknown()) {
        this.data = data
        this.pos = position
    }

    public func position(): Position {
        return pos
    }

    public func nodeKind(): NodeKind {
        return NodeKind.CommentNodeKind
    }

    public func parent(): ?Element {
        return parentImpl
    }

    public func toString(): String {
        return "Comment(${data.size} chars)"
    }
}

/* ---------- PiNode：处理指令 ---------- */

public class PiNode <: Node {
    public let target: String
    public let data: String
    let pos: Position
    var parentImpl: ?Element = None

    init(target: String, data: String, position!: Position = Position.unknown()) {
        this.target = target
        this.data = data
        this.pos = position
    }

    public func position(): Position {
        return pos
    }

    public func nodeKind(): NodeKind {
        return NodeKind.ProcessingInstructionNode
    }

    public func parent(): ?Element {
        return parentImpl
    }

    public func toString(): String {
        return "Pi(${target})"
    }
}

/* ---------- DoctypeNode：DOCTYPE 头（仅保留名字，Phase 4a 不含 DTD 子集） ---------- */

public class DoctypeNode <: Node {
    public let name: String
    let pos: Position
    var parentImpl: ?Element = None

    init(name: String, position!: Position = Position.unknown()) {
        this.name = name
        this.pos = position
    }

    public func position(): Position {
        return pos
    }

    public func nodeKind(): NodeKind {
        return NodeKind.DoctypeNodeKind
    }

    public func parent(): ?Element {
        return parentImpl
    }

    public func toString(): String {
        return "Doctype(${name})"
    }
}
