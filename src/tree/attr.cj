/*
 * tree — Attr：元素属性
 *
 * 对应 libxml2: `xmlAttr`（`tree.h`）；libxml2 继承 `xmlNode` 布局，CangjieXML
 * 把 `Attr` 独立出来不作为 Node，理由见 `node.cj`。
 *
 * 设计要点：
 *   - 不可变值语义：Attr 是 `class`（为了与其它 Node 共享引用语义一致），但
 *     所有字段 `let`。需要修改属性值应构造新实例并重新挂到 Element.attributes。
 *   - `isNamespaceDeclaration`：与 `SaxEvent` 中同名字段语义一致，标记该属性
 *     原本是 `xmlns` / `xmlns:prefix` 声明。序列化时下游可据此决定是否作为
 *     独立命名空间节点输出。
 */
package cangjie_xml.tree

import cangjie_xml.core.*
import cangjie_xml.parser.*

public class Attr <: ToString {
    public let qname: QName
    public let value: String
    public let position: Position
    public let isNamespaceDeclaration: Bool

    public init(
        qname: QName,
        value: String,
        position!: Position = Position.unknown(),
        isNamespaceDeclaration!: Bool = false
    ) {
        this.qname = qname
        this.value = value
        this.position = position
        this.isNamespaceDeclaration = isNamespaceDeclaration
    }

    /** 从 SAX 层的 `Attribute` 值类型构造等价的 `Attr`。 */
    public static func fromSaxAttribute(a: Attribute): Attr {
        return Attr(
            a.qname,
            a.value,
            position: a.position,
            isNamespaceDeclaration: a.isNamespaceDeclaration
        )
    }

    public func toString(): String {
        return "${qname.lexical()}=\"${value}\""
    }
}
