package cangjie_xml.visit

import cangjie_xml.dom.*

/**
 * 按 `XmlVisitor` 协议，前序 + 后序派发访问 `node` 及其后代。
 *
 * - `Document` / `Element`：调用 `visitEnter`，若返回 `true` 则递归所有子节点，
 *   结束后调用 `visitExit`；整体返回与 `visitExit` 的返回相同。
 * - 叶子节点：调用 `visit(text|comment|declaration|unknown)`，返回值即为本次
 *   派发的返回值。
 *
 * 返回值约定（与 tinyxml2 对齐）：`accept` 返回 `false` 表示"请在我这里中止
 * 后续遍历"。叶子节点 `visit(...)` 返回 `false` → `accept` 返回 `false`；
 * 容器节点 `visitEnter(...)` 返回 `false` → 跳过子节点，**不**调用
 * `visitExit`，`accept` 本身仍返回 `true`（兄弟仍可继续）；容器节点的任何
 * 子节点 `accept` 返回 `false` → 立刻中止剩余子节点，仍调用 `visitExit`，
 * `accept` 返回 `false`。
 */
public func accept(node: XmlNode, visitor: XmlVisitor): Bool {
    acceptImpl(node, visitor)
}

func acceptImpl(node: XmlNode, visitor: XmlVisitor): Bool {
    match (node.kind()) {
        case Document(d)      => acceptDocument(d, visitor)
        case Element(e)       => acceptElement(e, visitor)
        case Text(t)          => visitor.visit(t)
        case Comment(c)       => visitor.visit(c)
        case Declaration(dcl) => visitor.visit(dcl)
        case Unknown(u)       => visitor.visit(u)
    }
}

func acceptDocument(doc: XmlDocument, visitor: XmlVisitor): Bool {
    if (!visitor.visitEnter(doc)) {
        return true  // 剪枝：不进入子树，也不触发 visitExit
    }
    var keepGoing = true
    for (child in doc.childNodes()) {
        if (!keepGoing) { break }
        if (!acceptImpl(child, visitor)) {
            keepGoing = false
        }
    }
    let exitOk = visitor.visitExit(doc)
    keepGoing && exitOk
}

func acceptElement(el: XmlElement, visitor: XmlVisitor): Bool {
    if (!visitor.visitEnter(el)) {
        return true
    }
    var keepGoing = true
    for (child in el.childNodes()) {
        if (!keepGoing) { break }
        if (!acceptImpl(child, visitor)) {
            keepGoing = false
        }
    }
    let exitOk = visitor.visitExit(el)
    keepGoing && exitOk
}
