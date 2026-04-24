/*
 * encoding — 解码器抽象基类
 *
 * 对应 libxml2: xmlCharEncodingInputFunc 的角色，但提供面向对象的封装。
 */
package cangjie_xml.encoding

/**
 * 字符集解码器：把源编码字节流转为 UTF-8 的仓颉 `String`。
 *
 * 设计要点：
 *  - 解码器保留内部状态（例如 UTF-8 中的半字节序列、UTF-16 的高位代理）；
 *  - `decode(bytes, start, end, endOfInput)` 支持增量调用；
 *  - `reset()` 清空状态，用于跨文档复用解码器实例；
 *  - `decodeAll(bytes)` 是无状态一次性解码的便利封装，失败时抛异常。
 */
public abstract class Decoder {
    /** IANA 规范编码名（全小写、连字符形式，如 `utf-8`、`iso-8859-1`）。 */
    public prop name: String

    /**
     * 解码 `bytes[start..end]` 的字节切片。若 `endOfInput` 为 true，解码器
     * 不允许残留未消费字节；否则可把"半个序列"挂在内部状态里等下次调用。
     */
    public func decode(bytes: Array<Byte>, start: Int64, end: Int64, endOfInput: Bool): DecodeResult

    /** 清空解码器内部状态。默认空实现；有状态的子类自行重写。 */
    public open func reset(): Unit {}

    /** 一次性解码完整字节数组。失败抛出 `XmlException(EncodingError)`。 */
    public func decodeAll(bytes: Array<Byte>): String {
        reset()
        let r = decode(bytes, 0, bytes.size, true)
        match (r.status) {
            case Success => return r.text
            case InvalidBytes(off) => throw encodingError(name, off, "invalid byte sequence")
            case NeedMoreInput => throw encodingError(name, r.bytesConsumed, "unexpected end of input")
        }
    }
}
