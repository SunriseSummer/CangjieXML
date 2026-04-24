package cangjie_xml.query

import cangjie_xml.dom.*

/**
 * Query 扩展的接口契约。
 *
 * ## 为什么需要这个接口
 *
 * cjc 1.0.5 规则：跨包 `extend T <: I { ... }` 的公共方法，调用方只能通过
 * 接口 `I` 声明的签名来访问——未出现在 `I` 中的方法即使写成 `public`，
 * 跨包也不可见。把 Query API 一次性列在 `XmlQueryable` 里是最贴近意图的做法：
 * 即"让用户 `import cangjie_xml.query.*` 后，直接在 `XmlElement` 上使用
 * 完整的查询能力"。
 *
 * ## 使用
 *
 * 用户无需显式引用 `XmlQueryable`。
 */
public interface XmlQueryable {
    func attributeAs<T>(name: String, codec: XmlValueCodec<T>): ?T
    func requiredAttribute(name: String): String
    func requiredAttributeAs<T>(name: String, codec: XmlValueCodec<T>): T
    func intAttribute(name: String): ?Int64
    func int32Attribute(name: String): ?Int32
    func doubleAttribute(name: String): ?Float64
    func boolAttribute(name: String): ?Bool
    func attributeOr<T>(name: String, codec: XmlValueCodec<T>, fallback: T): T

    func childElement(name: String): ?XmlElement
    func requiredChildElement(name: String): XmlElement
    func childElementText(name: String): ?String
    func childElementTextAs<T>(name: String, codec: XmlValueCodec<T>): ?T
    func childElementTexts(name: String): Array<String>
}

