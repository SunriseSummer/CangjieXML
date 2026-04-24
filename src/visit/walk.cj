package cangjie_xml.visit

import cangjie_xml.dom.*

/**
 * 按 `XmlNodeKind` 派发，前序（pre-order）遍历 `node` 及其所有后代。
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
 * - 对每个节点调用 `visit(node.kind())` **一次**（前序）。
 * - `Continue`：进入子节点，递归完成后处理兄弟；
 * - `SkipChildren`：不进入子节点，直接处理兄弟；
 * - `Stop`：立即结束整次 `walk`。
 *
 * 只有 `Document` 和 `Element` 才有子节点；对叶子节点 (`Text` / `Comment` /
 * `Declaration` / `Unknown`)，`SkipChildren` 与 `Continue` 行为相同。
 *
 * ## 为什么是顶层函数而不是 `XmlNode.walk(...)`
 *
 * 遍历逻辑属于"用法"层，而非 DOM 核心数据结构的一部分。放在 `visit` 包里
 * 既避免 `dom` 包膨胀，也让用户更易按需引入/替换为其他遍历策略。
 * 为了让 `node.accept(v)` 之类的 OO 写法依然可用，我们额外通过
 * `XmlVisitable` 扩展接口把 `accept` 提供在 DOM 节点上。
 */
public func walk(node: XmlNode, visit: (XmlNodeKind) -> XmlWalkControl): Unit {
    walkImpl(node, visit)
}

/** 内部工作函数，返回"是否继续处理兄弟节点"。 */
func walkImpl(node: XmlNode, visit: (XmlNodeKind) -> XmlWalkControl): Bool {
    match (visit(node.kind())) {
        case Stop         => return false
        case SkipChildren => return true
        case Continue     => ()
    }
    // 进入子节点
    match (node.kind()) {
        case Document(d) =>
            for (child in d.childNodes()) {
                if (!walkImpl(child, visit)) { return false }
            }
        case Element(e) =>
            for (child in e.childNodes()) {
                if (!walkImpl(child, visit)) { return false }
            }
        case _ => ()  // 叶子
    }
    true
}
