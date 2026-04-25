package cangjie_xml.query

import std.collection.*
import cangjie_xml.dom.*
import cangjie_xml.error.*

/**
 * `XmlElement` 的查询便利扩展——属性访问、必填语义、子元素按名字定位。
 *
 * 通过 `<: XmlQueryable` 满足跨包扩展可见性要求，让 `import
 * cangjie_xml.query.*` 后即可直接在 `XmlElement` 上使用本节方法。
 */
extend XmlElement <: XmlQueryable {

    // ------------------------------------------------------------------
    // 属性查询
    // ------------------------------------------------------------------

    /** 读取 `name` 属性并用 `codec` 解析，失败返回 `None`。 */
    public func attributeAs<T>(name: String, codec: XmlValueCodec<T>): ?T {
        match (attribute(name)) {
            case Some(s) => codec.tryParse(s)
            case None    => None
        }
    }

    /** 读取必填属性；缺失抛 `XmlException`。 */
    public func requiredAttribute(name: String): String {
        match (attribute(name)) {
            case Some(s) => s
            case None => throw XmlException(
                "required attribute '${name}' is missing on element <${this.name}>")
        }
    }

    /** 读取必填属性并解析；缺失或解析失败均抛 `XmlException`。 */
    public func requiredAttributeAs<T>(name: String, codec: XmlValueCodec<T>): T {
        let text = requiredAttribute(name)
        match (codec.tryParse(text)) {
            case Some(v) => v
            case None => throw XmlException(
                "required attribute '${name}' on element <${this.name}> has value " +
                "'${text}' that cannot be parsed as the requested type")
        }
    }

    public func intAttribute(name: String): ?Int64 {
        attributeAs<Int64>(name, INT64_CODEC)
    }

    public func int32Attribute(name: String): ?Int32 {
        attributeAs<Int32>(name, INT32_CODEC)
    }

    public func doubleAttribute(name: String): ?Float64 {
        attributeAs<Float64>(name, FLOAT64_CODEC)
    }

    public func boolAttribute(name: String): ?Bool {
        attributeAs<Bool>(name, BOOL_CODEC)
    }

    /**
     * 读取属性并解码，缺失 / 解析失败时返回默认值。
     *
     * 针对"可选配置项 + 兜底默认"这个高频场景，比"先 attributeAs 再 ??" 更顺手。
     */
    public func attributeOr<T>(name: String, codec: XmlValueCodec<T>, fallback: T): T {
        match (attributeAs<T>(name, codec)) {
            case Some(v) => v
            case None    => fallback
        }
    }

    // ------------------------------------------------------------------
    // 子元素 / 文本查询
    // ------------------------------------------------------------------

    /** `firstChildElement(name: Some(name))` 的短写。 */
    public func childElement(name: String): ?XmlElement {
        firstChildElement(name: Some(name))
    }

    /** 必填子元素；缺失抛 `XmlException`。 */
    public func requiredChildElement(name: String): XmlElement {
        match (childElement(name)) {
            case Some(e) => e
            case None => throw XmlException(
                "required child element <${name}> is missing under <${this.name}>")
        }
    }

    /** 读取 `name` 子元素的文本内容；若子元素不存在返回 `None`。 */
    public func childElementText(name: String): ?String {
        match (childElement(name)) {
            case Some(e) => Some(e.textContent())
            case None    => None
        }
    }

    /** 读取 `name` 子元素的文本并用 `codec` 解析；缺失或解析失败返回 `None`。 */
    public func childElementTextAs<T>(name: String, codec: XmlValueCodec<T>): ?T {
        match (childElementText(name)) {
            case Some(s) => codec.tryParse(s)
            case None    => None
        }
    }

    /** 枚举所有按 `name` 匹配的子元素的文本内容。 */
    public func childElementTexts(name: String): Array<String> {
        let list = ArrayList<String>()
        for (e in childElements(name: Some(name))) {
            list.add(e.textContent())
        }
        list.toArray()
    }
}
