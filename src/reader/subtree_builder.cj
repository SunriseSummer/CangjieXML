/*
 * reader — 子树重建：从 SaxEvent 窗口构造一个独立的 Element 树
 *
 * 本文件为 Phase 4c+ 新增。`XmlReader.readOuterXml` / `readInnerXml` 需要把
 * 已在事件流里走过的某个元素（含其子孙）还原成可序列化的结构化数据；
 * `readSubtree` 虽不物化到 DOM，但也需要先把事件"封装"成一个可重放的源。
 *
 * 设计要点：
 *   - **SubtreeBuilder**：轻量版 `DocumentBuilder`，只消化从某一层 StartElement
 *     起到**其配对 EndElement 止**的事件序列。不处理 StartDocument / EndDocument
 *     （因为调用方在"元素范围内"调用，这两个事件不会出现）。
 *   - 对 `ParseError` 仍透传为 `XmlException` —— `XmlReader` 已经在 state=Error
 *     前提下调用本模块，但防御性起见这里也不吞。
 *   - 产出的 `Element` 带完整子孙，`DocumentSerializer.elementToString` 可直接
 *     消费。本 Builder 不复用 `tree.DocumentBuilder` 是为了：
 *       (1) DocumentBuilder 要求以 StartDocument/EndDocument 为边界；
 *       (2) 我们需要一个"匹配初始深度"的终止条件，在 DocumentBuilder 里不暴露。
 *
 * 不变量：
 *   - `collectSubtreeEvents` 调用方必须已经**收过**配对的 StartElement —— 调用方
 *     传入的第一个事件来自 pullEvent，后续的 pull 也由 Builder 完成；
 *   - 结束条件是 `depth == 0` 时看到 EndElement。
 */
package cangjie_xml.reader

import std.collection.*
import cangjie_xml.core.*
import cangjie_xml.parser.*
import cangjie_xml.tree.*

/**
 * 把一个 StartElement + 其后的所有子事件 + 配对 EndElement，构造为一棵
 * 独立的 `Element` 子树。
 *
 * 参数：
 *   - `start`：触发调用时刚刚从事件流里取出的 `StartElement`。
 *   - `pull`：持续取下一事件的 callback。由 XmlReader 提供，内部是 `pullEvent`。
 *
 * 终止：直到 pull 到一个 `EndElement` 且当前深度为 0。返回的 Element 的 parent
 * 为 `None`；其全部子孙结构完整。
 */
func buildElementFromEvents(start: SaxEvent, pull: () -> ?SaxEvent): Element {
    let root = newElementFrom(start)
    // 用显式栈代替递归，防极深嵌套爆栈。初始深度 = 0，栈顶即 root。
    let stack: ArrayStack<Element> = ArrayStack<Element>()
    stack.add(root)
    while (!stack.isEmpty()) {
        let ev = pull()
        match (ev) {
            case None =>
                // 事件流在子树结束前断流 —— 语义错误，但我们依然返回已构造的部分。
                // XmlReader 层会上报 parse error，这里不再抛。
                return root
            case Some(e) =>
                dispatch(e, stack)
                if (stack.isEmpty()) {
                    return root
                }
        }
    }
    return root
}

/** 收集一窗子树事件到 ArrayList —— 给 `readSubtree` 做独立 reader 用。
 *  返回的事件列表包含 `start` 本身 + 所有后续子事件 + 配对 EndElement。 */
func collectSubtreeEvents(start: SaxEvent, pull: () -> ?SaxEvent): ArrayList<SaxEvent> {
    let out = ArrayList<SaxEvent>()
    out.add(start)
    var depth: Int64 = 1
    while (depth > 0) {
        let ev = pull()
        match (ev) {
            case None => return out
            case Some(e) =>
                out.add(e)
                match (e) {
                    case StartElement(_, _, _, _) => depth += 1
                    case EndElement(_, _) => depth -= 1
                    case _ => ()
                }
        }
    }
    return out
}

/* ---------- 分派：把单个事件挂到栈顶元素 ---------- */

func dispatch(e: SaxEvent, stack: ArrayStack<Element>): Unit {
    match (e) {
        case StartElement(_, _, _, _) =>
            let child = newElementFrom(e)
            attachChild(stack, child)
            stack.add(child)
        case EndElement(_, _) =>
            let _ = stack.remove()
        case Characters(p, s) => attachLeaf(stack, TextNode(s, position: p))
        case Cdata(p, s) => attachLeaf(stack, CdataSection(s, position: p))
        case CommentEvent(p, s) => attachLeaf(stack, CommentNode(s, position: p))
        case Pi(p, t, d) => attachLeaf(stack, PiNode(t, d, position: p))
        case EntityReference(p, n) =>
            // 与 DocumentBuilder 一致：降级为 `&name;` 文本。
            attachLeaf(stack, TextNode("&${n};", position: p))
        case ParseError(err) => throw XmlException(err)
        case StartDocument(_) | EndDocument(_) | Doctype(_, _) =>
            // 子树里不应出现；忽略保守处理。
            ()
    }
}

func newElementFrom(ev: SaxEvent): Element {
    match (ev) {
        case StartElement(p, q, attrs, ns) =>
            let el = Element(q, ns, position: p)
            for (a in attrs) {
                el.setAttribute(Attr.fromSaxAttribute(a))
            }
            return el
        case _ =>
            // 编程错误：只能传 StartElement。
            throw XmlException(XmlError.Other(Position.unknown(),
                "SubtreeBuilder: newElementFrom requires StartElement"))
    }
}

func attachChild(stack: ArrayStack<Element>, child: Element): Unit {
    match (stack.peek()) {
        case Some(p) => p.appendChild(child)
        case None => ()
    }
}

func attachLeaf(stack: ArrayStack<Element>, n: Node): Unit {
    match (stack.peek()) {
        case Some(p) => p.appendChild(n)
        case None => ()
    }
}
