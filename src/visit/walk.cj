package fastxml.visit

import fastxml.dom.*

/**
 * 按 `XmlNodeKind` 派发，前序（pre-order）遍历 `node` 及其所有后代
 *
 * ```cangjie
 * walk(doc) { kind =>
 *     match (kind) {
 *         case Element(e) where e.name == "book" => { countBooks++; Continue }
 *         case _ => Continue
 *     }
 * }
 * ```
 *
 * ## 语义
 *
 * - 对每个节点调用 `visit(node.kind())` **一次**（前序）
 * - `Continue`：进入子节点，递归完成后处理兄弟；
 * - `SkipChildren`：不进入子节点，直接处理兄弟；
 * - `Stop`：立即结束整次 `walk`
 *
 * 只有 `Document` 和 `Element` 才有子节点；对叶子节点 (`Text` / `Comment` /
 * `Declaration` / `Unknown`)，`SkipChildren` 与 `Continue` 行为相同
 */
public func walk(node: XmlNode, visit: (XmlNodeKind) -> XmlWalkControl): Unit {
    walkImpl(node, visit)
}

// 内部工作函数，返回"是否继续处理兄弟节点"
func walkImpl(node: XmlNode, visit: (XmlNodeKind) -> XmlWalkControl): Bool {
    // 缓存一次 `kind()`，使后续 visit 与 match 共用同一个值
    let nodeKind = node.kind()
    match (visit(nodeKind)) {
        case Stop => return false
        case SkipChildren => return true
        case Continue => ()
    }
    // 直接走双向链表，避免每次都构造 `childNodes()` 的迭代器对象
    match (nodeKind) {
        case Document(d) =>
            var cursor = d.firstChild
            while (let Some(child) <- cursor) {
                if (!walkImpl(child, visit)) {
                    return false
                }
                cursor = child.nextSibling
            }
        case Element(e) =>
            var cursor = e.firstChild
            while (let Some(child) <- cursor) {
                if (!walkImpl(child, visit)) {
                    return false
                }
                cursor = child.nextSibling
            }
        case _ => () // 叶子
    }
    true
}
