package cangjie_xml.visit

import cangjie_xml.dom.*

/**
 * 按 `XmlVisitor` 协议，前序 + 后序派发访问 `node` 及其后代。
 *
 * ## 语义摘要
 *
 * - `Document`：调用 `visitEnter(document)`；若返回 `true`，递归所有子节点；
 *   结束后调用 `visitExit(document)`；整体返回与 `visitExit` 的返回相同。
 * - `Element`：同上（`visitEnter/Exit(element)`）。
 * - 叶子节点：调用 `visit(text|comment|declaration|unknown)`，返回值即为本次
 *   派发的返回值。
 *
 * ## 返回值
 *
 * 对齐 tinyxml2：`accept` 返回 `false` 表示"请在我这里中止后续遍历"。具体而言：
 *
 * - 叶子节点 `visit(...)` 返回 `false` → `accept` 返回 `false`；
 * - 容器节点 `visitEnter(...)` 返回 `false` → 跳过子节点，**不**调用 `visitExit`，
 *   `accept` 本身返回 `true`（对兄弟一层仍可继续）；
 * - 容器节点的任何子节点 `accept` 返回 `false` → 立刻中止剩余子节点的处理，
 *   仍然调用 `visitExit`，`accept` 返回 `false`。
 *
 * 这一组约定既贴合 tinyxml2 用户的直觉，又保持 `visitExit` 的 RAII-风格对称性。
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
