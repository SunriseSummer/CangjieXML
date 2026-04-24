/*
 * encoding — 编码器抽象基类
 *
 * 对应 libxml2: xmlCharEncodingOutputFunc。
 */
package cangjie_xml.encoding

/**
 * 字符集编码器：把仓颉 `String`（逻辑上 UTF-8）转为目标编码的字节流。
 *
 * 与 `Decoder` 不同，编码器通常是 **无状态的**：仓颉 `String` 不可变且
 * 已按完整码点切分，不会跨调用传递"半个码点"。因此默认接口只暴露
 * 一次性 `encode(text)`；必要时由具体子类补充流式重载。
 */
public abstract class Encoder {
    /** IANA 规范编码名。 */
    public prop name: String

    /** 该编码是否写 BOM（`Utf16Le` / `Utf16Be` / `Utf32Le` / `Utf32Be` 默认写；`Utf8` 默认不写）。 */
    public open prop writesBom: Bool {
        get() {
            return false
        }
    }

    /**
     * 编码整段文本。若存在目标编码不可表达的码点，返回 `EncodeResult`
     * 并将 `status` 设为 `Unmappable`；`bytes` 里只含错误发生前已成功编码的部分。
     */
    public func encode(text: String): EncodeResult

    /** 便利封装：出错时直接抛异常。 */
    public func encodeAll(text: String): Array<Byte> {
        let r = encode(text)
        match (r.status) {
            case Success => return r.bytes
            case Unmappable(idx, cp) =>
                throw encodingError(
                    name,
                    Int64(idx),
                    "code point U+${cp} at position ${idx} not representable"
                )
        }
    }
}
