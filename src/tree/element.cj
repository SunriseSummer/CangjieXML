/*
 * tree — Element：具名元素节点
 *
 * 对应 libxml2: `xmlNode`（当 `type == XML_ELEMENT_NODE`）。
 *
 * 设计要点：
 *   - 引用语义（`class`）。`parent` 作为 `var`，由 `DocumentBuilder` 在构造 DOM
 *     时写入一次；MVP 阶段不支持后续外部修改。
 *   - `children` / `attributes` 在 DOM 构造期间由 Builder 向内追加，构造完成后
 *     对外只提供只读视图（Cangjie 无 `ReadOnly<T>` 原语，我们通过私有字段 +
 *     访问器函数实现；直接暴露 `ArrayList` 会让调用方误以为可变）。
 *   - `ns` 字段保留 `StartElement` 事件携带的 `NsContext` 快照，便于下游（例如
 *     XPath、Canonical XML）查询作用域内绑定；libxml2 的做法是挂 `xmlNs *` 链
 *     表到元素节点，语义等价但数据结构更原始。
 */
package cangjie_xml.tree

import std.collection.*
import cangjie_xml.core.*
import cangjie_xml.parser.*

public class Element <: Node {
    public let qname: QName
    let childrenImpl: ArrayList<Node>
    let attributesImpl: ArrayList<Attr>
    /** 该元素开启标签处生效的命名空间上下文（含祖先继承部分）。 */
    public let ns: NsContext
    let pos: Position
    var parentImpl: ?Element = None

    init(qname: QName, ns: NsContext, position!: Position = Position.unknown()) {
        this.qname = qname
        this.ns = ns
        this.pos = position
        this.childrenImpl = ArrayList<Node>()
        this.attributesImpl = ArrayList<Attr>()
    }

    public func position(): Position {
        return pos
    }

    public func nodeKind(): NodeKind {
        return NodeKind.ElementNode
    }

    /** 父元素；根元素返回 `None`（其父是 `Document`，不属于 `Element` 类型）。 */
    public func parent(): ?Element {
        return parentImpl
    }

    /** 子节点只读视图。返回底层 `ArrayList` 的迭代器，不暴露写 API。 */
    public func children(): Iterator<Node> {
        return childrenImpl.iterator()
    }

    /** 子节点数。 */
    public func childCount(): Int64 {
        return childrenImpl.size
    }

    /** 按索引访问子节点；越界抛 `IndexOutOfBoundsException`（`ArrayList` 语义）。 */
    public func childAt(i: Int64): Node {
        return childrenImpl[i]
    }

    /** 属性只读视图。 */
    public func attributes(): Iterator<Attr> {
        return attributesImpl.iterator()
    }

    public func attributeCount(): Int64 {
        return attributesImpl.size
    }

    /**
     * 按扩展名查找首个匹配属性（`(localName, uri)` 同时相等，忽略前缀）。
     * 未命中返回 `None`。
     */
    public func findAttribute(localName: String, uri!: ?String = None): ?Attr {
        for (a in attributesImpl) {
            if (a.qname.localName == localName && a.qname.uri == uri) {
                return Some(a)
            }
        }
        return None
    }

    /**
     * 按扩展名查找所有直接子元素。惰性迭代，不分配数组。
     * `uri = None` 匹配"无命名空间"（与 libxml2 `xmlGetNoNsProp` 对应）。
     */
    public func findChildren(localName: String, uri!: ?String = None): Iterator<Element> {
        return ElementChildrenFilter(childrenImpl, localName, uri)
    }

    /**
     * 聚合所有直接 Text/CDATA 子节点的字符内容。对应 W3C DOM `Node.textContent`
     * 的**浅**版本 —— 不递归子元素。需要递归聚合可调用 `allText()`。
     */
    public func directText(): String {
        let sb = StringBuilder()
        for (c in childrenImpl) {
            match (c) {
                case t: TextNode => sb.append(t.data)
                case c2: CdataSection => sb.append(c2.data)
                case _ => ()
            }
        }
        return sb.toString()
    }

    /** 递归聚合所有后代的 Text / CDATA 字符。对应 W3C DOM `Node.textContent`。 */
    public func allText(): String {
        let sb = StringBuilder()
        appendAllTextTo(sb)
        return sb.toString()
    }

    func appendAllTextTo(sb: StringBuilder): Unit {
        for (c in childrenImpl) {
            match (c) {
                case t: TextNode => sb.append(t.data)
                case c2: CdataSection => sb.append(c2.data)
                case e: Element => e.appendAllTextTo(sb)
                case _ => ()
            }
        }
    }

    public func toString(): String {
        return "Element(${qname.lexical()}, ${childrenImpl.size} children, ${attributesImpl.size} attrs)"
    }
}

/** `findChildren` 的惰性迭代器。对子节点做 `filter + isInstance<Element>`。 */
class ElementChildrenFilter <: Iterator<Element> {
    let src: Iterator<Node>
    let localName: String
    let uri: ?String

    init(children: ArrayList<Node>, localName: String, uri: ?String) {
        this.src = children.iterator()
        this.localName = localName
        this.uri = uri
    }

    public func next(): ?Element {
        while (true) {
            match (src.next()) {
                case None => return None
                case Some(n) =>
                    match (n) {
                        case e: Element where e.qname.localName == localName && e.qname.uri == uri =>
                            return Some(e)
                        case _ => ()
                    }
            }
        }
        return None
    }
}
