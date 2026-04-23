package cangjie_xml.query

/**
 * 双向编解码协议：把任意 `T` ←→ `String` 的映射抽出来，
 * 让 Query 与 Build 两侧都能复用同一套规则。
 *
 * ## 与 tinyxml2 的对照
 *
 * tinyxml2 把 `QueryIntAttribute` / `QueryBoolAttribute` / … 直接写进
 * `XMLElement`。那样做的后果：类型集合被 "内建支持" 的几种写死，用户自定义
 * 类型没有对等地位。
 *
 * CangjieXML 把这块下沉到 `XmlValueCodec<T>`：
 *
 * - `query` 包内置 `Int64Codec` / `Int32Codec` / `Float64Codec` / `BoolCodec` / `StringCodec`；
 * - 用户自定义类型实现本接口后，就能在 Query（`attributeAs<T>`）与 Build
 *   （`attributeAs<T>`）中获得与内建类型**完全一致**的使用体验。
 *
 * ## 为什么返回 `?T` 而不是 `Result<T, XmlError>`
 *
 * - 仓颉语言内置 `Option<T>`，其"缺失/失败"两义对 XML 语义层已经足够；
 * - 失败时是否抛 `XmlException`、带多少上下文，应由**调用点**决定，
 *   而不是由最底层的 codec 去强行拼错误信息。
 * - 保留逃生口：想要"必须成功"的语义时，在 `requiredAttributeAs<T>`
 *   中统一抛 `XmlException`。
 */
public interface XmlValueCodec<T> {
    /** 尝试把文本解析为 `T`；失败返回 `None`。实现方不应抛异常。 */
    func tryParse(text: String): ?T

    /** 把值格式化为 XML 属性 / 文本中合法的字符串（仅数值/布尔语义，不负责 XML 转义）。 */
    func format(value: T): String
}
