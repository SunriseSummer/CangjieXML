package tinyxml2.query

import tinyxml2.dom.*

/**
 * Query 扩展的接口契约。
 *
 * `query` 包通过 `extend XmlElement <: XmlQueryable` 植入下列方法；接口声明
 * 保证了"`import tinyxml2.query.*` 后直接在 `XmlElement` 上调用"的跨包
 * 可见性。用户无需显式引用 `XmlQueryable`。
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

