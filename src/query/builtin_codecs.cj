package tinyxml2.query

import std.convert.*
import std.collection.*

/**
 * 内置 `XmlValueCodec` 实现——覆盖 XML 文档中最常见的几个标量类型。
 *
 * 每个 codec 都是"行为无状态"的单例，通过 public 字段暴露，避免用户每次
 * 调用都构造新对象。
 *
 * ## 约定
 *
 * - 所有 codec 在 `tryParse` 失败时一律返回 `None`，不抛异常；
 * - `format` 对所有输入都是全值域定义（永不抛异常）；
 * - `BoolCodec` 接受 `"true"` / `"false"` / `"1"` / `"0"`（忽略大小写），
 *   与 tinyxml2 行为对齐；`format` 只输出 `"true"` / `"false"`；
 * - 数值 codec 对含前后空白的输入会先 `trim` 再解析——XML 文本常带空白。
 */

/** `Int64` 编解码。失败返回 `None`（包括溢出）。 */
public class Int64Codec <: XmlValueCodec<Int64> {
    public func tryParse(text: String): ?Int64 {
        let trimmed = trimAscii(text)
        if (trimmed.isEmpty()) { return None }
        try {
            Some(Int64.parse(trimmed))
        } catch (_: Exception) {
            None
        }
    }

    public func format(value: Int64): String {
        value.toString()
    }
}

/** `Int32` 编解码。 */
public class Int32Codec <: XmlValueCodec<Int32> {
    public func tryParse(text: String): ?Int32 {
        let trimmed = trimAscii(text)
        if (trimmed.isEmpty()) { return None }
        try {
            Some(Int32.parse(trimmed))
        } catch (_: Exception) {
            None
        }
    }

    public func format(value: Int32): String {
        value.toString()
    }
}

/** `Float64` 编解码。 */
public class Float64Codec <: XmlValueCodec<Float64> {
    public func tryParse(text: String): ?Float64 {
        let trimmed = trimAscii(text)
        if (trimmed.isEmpty()) { return None }
        try {
            Some(Float64.parse(trimmed))
        } catch (_: Exception) {
            None
        }
    }

    public func format(value: Float64): String {
        value.toString()
    }
}

/** `Bool` 编解码。接受 `"true"/"false"/"1"/"0"`（忽略大小写）。 */
public class BoolCodec <: XmlValueCodec<Bool> {
    public func tryParse(text: String): ?Bool {
        let t = lowerAscii(trimAscii(text))
        match (t) {
            case "true"  => Some(true)
            case "1"     => Some(true)
            case "false" => Some(false)
            case "0"     => Some(false)
            case _       => None
        }
    }

    public func format(value: Bool): String {
        if (value) { "true" } else { "false" }
    }
}

/** `String` 透传 codec——便于统一 Builder / Query 的泛型签名。 */
public class StringCodec <: XmlValueCodec<String> {
    public func tryParse(text: String): ?String {
        Some(text)
    }

    public func format(value: String): String {
        value
    }
}

// ----------------------------------------------------------------------
// 单例访问点：避免每次调用都构造新对象
// ----------------------------------------------------------------------

public let INT64_CODEC: Int64Codec = Int64Codec()
public let INT32_CODEC: Int32Codec = Int32Codec()
public let FLOAT64_CODEC: Float64Codec = Float64Codec()
public let BOOL_CODEC: BoolCodec = BoolCodec()
public let STRING_CODEC: StringCodec = StringCodec()

// ----------------------------------------------------------------------
// 内部字符串工具（保持 codec 自给自足，不依赖 internal 包）
// ----------------------------------------------------------------------

func trimAscii(s: String): String {
    let rr = toRuneList(s)
    var start = 0
    var end = rr.size
    while (start < end && isAsciiWhitespace(rr[start])) { start++ }
    while (end > start && isAsciiWhitespace(rr[end - 1])) { end-- }
    if (start == 0 && end == rr.size) { return s }
    let sb = StringBuilder()
    var i = start
    while (i < end) {
        sb.append(rr[i])
        i++
    }
    sb.toString()
}

func lowerAscii(s: String): String {
    let sb = StringBuilder()
    for (r in s.runes()) {
        if (r >= r'A' && r <= r'Z') {
            sb.append(Rune(UInt32(r) + UInt32(r'a') - UInt32(r'A')))
        } else {
            sb.append(r)
        }
    }
    sb.toString()
}

func isAsciiWhitespace(r: Rune): Bool {
    r == r' ' || r == r'\t' || r == r'\n' || r == r'\r'
}

func toRuneList(s: String): Array<Rune> {
    let list = ArrayList<Rune>()
    for (r in s.runes()) { list.add(r) }
    list.toArray()
}
