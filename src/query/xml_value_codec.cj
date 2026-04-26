package tinyxml2.query

/**
 * 双向编解码协议：把任意 `T` ←→ `String` 的映射抽出来，让 Query 与 Build
 * 两侧都能复用同一套规则。
 *
 * `query` 包内置 `Int64Codec` / `Int32Codec` / `Float64Codec` / `BoolCodec` /
 * `StringCodec`；用户自定义类型实现本接口后，就能在 Query（`attributeAs<T>`）
 * 与 Build（`attributeAs<T>`）中获得与内建类型完全一致的使用体验。
 *
 * `tryParse` 返回 `?T`：失败时是否抛 `XmlException`、带多少上下文，应由
 * 调用点决定，而不是由最底层的 codec 拼错误信息。需要"必须成功"的语义时
 * 走 `requiredAttributeAs<T>`。
 */
public interface XmlValueCodec<T> {
    /** 尝试把文本解析为 `T`；失败返回 `None`。实现方不应抛异常。 */
    func tryParse(text: String): ?T

    /** 把值格式化为 XML 属性 / 文本中合法的字符串（仅数值/布尔语义，不负责 XML 转义）。 */
    func format(value: T): String
}
