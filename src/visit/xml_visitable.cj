package cangjie_xml.visit

import cangjie_xml.dom.*

/**
 * `accept` / `walk` 作为 `XmlNode` 方法的接口契约。
 *
 * cjc 1.0.5 的跨包 `extend T <: I { ... }` 只会暴露 `I` 中声明的方法——这里
 * 把两个入口都列出来，让用户 `import cangjie_xml.visit.*` 之后可以写：
 *
 * ```cangjie
 * doc.accept(MyVisitor())
 * doc.walk { k => Continue }
 * ```
 *
 * 顶层函数 `accept(node, visitor)` / `walk(node, fn)` 也保留，便于不喜欢
 * 方法风格的场景使用。
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
