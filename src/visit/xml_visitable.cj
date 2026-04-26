package tinyxml2.visit

import tinyxml2.dom.*

/**
 * `accept` / `walk` 作为 `XmlNode` 方法的接口契约。
 *
 * `import tinyxml2.visit.*` 后即可写：
 *
 * ```cangjie
 * doc.accept(MyVisitor())
 * doc.walk { k => Continue }
 * ```
 *
 * 顶层函数 `accept(node, visitor)` / `walk(node, fn)` 也保留。
 */
public interface XmlVisitable {
    func accept(visitor: XmlVisitor): Bool
    func walk(visit: (XmlNodeKind) -> XmlWalkControl): Unit
}

extend XmlNode <: XmlVisitable {
    public func accept(visitor: XmlVisitor): Bool {
        acceptImpl(this, visitor)
    }

    public func walk(visit: (XmlNodeKind) -> XmlWalkControl): Unit {
        walkImpl(this, visit)
    }
}
