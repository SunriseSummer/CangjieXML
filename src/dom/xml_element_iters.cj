package tinyxml2.dom

/**
 * `XmlElement` 子节点迭代器：服务于 `childNodes()` / `childElements()`。
 */

/** 遍历任意类型的直接子节点。 */
class XmlChildIter <: Iterable<XmlNode> {
    private var first: ?XmlNode

    init(first: ?XmlNode) {
        this.first = first
    }

    public func iterator(): Iterator<XmlNode> {
        XmlChildIterator(first)
    }
}

class XmlChildIterator <: Iterator<XmlNode> {
    private var cur: ?XmlNode

    init(first: ?XmlNode) {
        this.cur = first
    }

    public func next(): ?XmlNode {
        match (cur) {
            case None => None
            case Some(n) =>
                cur = n.nextRef
                Some(n)
        }
    }
}

/** 仅遍历元素类型的直接子节点；若 `name` 非空，则按名过滤。 */
class XmlChildElementIter <: Iterable<XmlElement> {
    private var first: ?XmlNode
    private var name: ?String

    init(first: ?XmlNode, name: ?String) {
        this.first = first
        this.name = name
    }

    public func iterator(): Iterator<XmlElement> {
        XmlChildElementIterator(first, name)
    }
}

class XmlChildElementIterator <: Iterator<XmlElement> {
    private var cur: ?XmlNode
    private let name: ?String

    init(first: ?XmlNode, name: ?String) {
        this.cur = first
        this.name = name
    }

    public func next(): ?XmlElement {
        while (let Some(n) <- cur) {
            let nxt = n.nextRef
            cur = nxt
            if (let Element(e) <- n.kind()) {
                if (matchesName(e)) {
                    return Some(e)
                }
            }
        }
        None
    }

    private func matchesName(e: XmlElement): Bool {
        match (name) {
            case None => true
            case Some(nm) => e.name == nm
        }
    }
}
