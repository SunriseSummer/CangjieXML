/*
 * encoding — 解/编码结果类型
 *
 * 对应 libxml2: encoding.c 的 xmlCharEncError、xmlCharEncOutFunc 返回约定。
 *
 * 将 C 版的 int 返回值（负数表错误、正数表消耗字节数）拆为独立的
 * `DecodeStatus`（分支枚举）+ `bytesConsumed`（显式 Int64），
 * 让调用方用 match 表达式穷尽处理。
 */
package cangjie_xml.encoding

import cangjie_xml.core.*

/** 一次 `Decoder.decode` 调用的结果状态。 */
public enum DecodeStatus <: ToString {
    /** 成功；`bytesConsumed == end - start`。 */
    | Success
    /**
     * 输入末尾残留了不完整的多字节序列，且 `endOfInput = false`。
     * 调用方应当 append 更多字节后再次调用；`bytesConsumed` 指示本次消费到哪里。
     */
    | NeedMoreInput
    /**
     * 在给定偏移处遇到非法字节序列（`byteOffset` 以输入数组下标为准）。
     * `bytesConsumed` 为错误字节之前已成功解码的字节数。
     */
    | InvalidBytes(Int64)

    public func toString(): String {
        match (this) {
            case Success => return "Success"
            case NeedMoreInput => return "NeedMoreInput"
            case InvalidBytes(off) => return "InvalidBytes@${off}"
        }
    }
}

/** 解码结果 = 已产出文本 + 已消费字节数 + 状态。 */
public struct DecodeResult {
    public let text: String
    public let bytesConsumed: Int64
    public let status: DecodeStatus

    public init(text: String, bytesConsumed: Int64, status: DecodeStatus) {
        this.text = text
        this.bytesConsumed = bytesConsumed
        this.status = status
    }
}

/** 一次 `Encoder.encode` 调用的结果状态。 */
public enum EncodeStatus <: ToString {
    /** 全部输入已编码。 */
    | Success
    /**
     * 输入中的某个码点无法在目标编码中表示（例如把中文送入 US-ASCII）。
     * 携带该码点在输入 `String.toRuneArray()` 中的索引以及码点值本身。
     */
    | Unmappable(Int64, Int32)

    public func toString(): String {
        match (this) {
            case Success => return "Success"
            case Unmappable(idx, cp) => return "Unmappable@${idx}:U+${cp}"
        }
    }
}

/** 编码结果 = 已产出字节 + 状态。 */
public struct EncodeResult {
    public let bytes: Array<Byte>
    public let status: EncodeStatus

    public init(bytes: Array<Byte>, status: EncodeStatus) {
        this.bytes = bytes
        this.status = status
    }
}

/** 常见的 BOM（字节序标记）种类。 */
public enum BomKind <: ToString & Equatable<BomKind> {
    | Utf8      // EF BB BF
    | Utf16Le   // FF FE
    | Utf16Be   // FE FF
    | Utf32Le   // FF FE 00 00
    | Utf32Be   // 00 00 FE FF

    /** 该 BOM 的规范字节长度。 */
    public func length(): Int64 {
        match (this) {
            case Utf8 => return 3
            case Utf16Le => return 2
            case Utf16Be => return 2
            case Utf32Le => return 4
            case Utf32Be => return 4
        }
    }

    /** 该 BOM 对应的 IANA 编码名（全小写、连字符规范形）。 */
    public func encodingName(): String {
        match (this) {
            case Utf8 => return "utf-8"
            case Utf16Le => return "utf-16le"
            case Utf16Be => return "utf-16be"
            case Utf32Le => return "utf-32le"
            case Utf32Be => return "utf-32be"
        }
    }

    public operator func ==(that: BomKind): Bool {
        return this.encodingName() == that.encodingName()
    }

    public operator func !=(that: BomKind): Bool {
        return !(this == that)
    }

    public func toString(): String {
        return encodingName()
    }
}

/** 把错误字节偏移包装成一个便于诊断的 `XmlException`。 */
public func encodingError(encodingName: String, byteOffset: Int64, msg: String): XmlException {
    let pos = Position(source: None, line: 0, column: 0, byteOffset: byteOffset)
    return XmlException(XmlError.EncodingError(pos, "${encodingName}: ${msg}"))
}
