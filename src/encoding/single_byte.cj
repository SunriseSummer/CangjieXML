/*
 * encoding — 单字节字符集
 *
 * 对应 libxml2: encoding.c 中 US-ASCII、ISO-8859-1..15 解码。
 *
 * 统一抽象为 `SingleByteDecoder` / `SingleByteEncoder`：
 *  - 低 128（0x00..0x7F）字节一律作 US-ASCII；
 *  - 高 128（0x80..0xFF）字节按具体编码的 128 项 `Array<Int32>` 映射表查表；
 *  - 映射表中 `-1` 表示"未定义"，解码时报 `InvalidBytes`。
 *
 * 每种具体编码都提供静态工厂函数。
 */
package cangjie_xml.encoding

import cangjie_xml.core.*

/** 通用单字节解码器。 */
public class SingleByteDecoder <: Decoder {
    private let nm: String
    // 长度 128：索引 i 对应字节值 0x80 + i 的 Unicode 码点；-1 表示未定义。
    private let highTable: Array<Int32>

    public init(name: String, highTable: Array<Int32>) {
        if (highTable.size != 128) {
            throw IllegalArgumentException("highTable must have length 128")
        }
        this.nm = name
        this.highTable = highTable
    }

    public prop name: String {
        get() {
            return nm
        }
    }

    public override func decode(bytes: Array<Byte>, start: Int64, end: Int64, endOfInput: Bool): DecodeResult {
        let _ = endOfInput // 单字节解码无跨片状态
        let sb = StringBuilder()
        var i = start
        while (i < end) {
            let b = UInt32(bytes[i])
            if (b < 0x80u32) {
                sb.append(Rune(b))
            } else {
                let cp = highTable[Int64(b - 0x80u32)]
                if (cp < 0) {
                    return DecodeResult(sb.toString(), i - start, DecodeStatus.InvalidBytes(i))
                }
                sb.append(Rune(UInt32(cp)))
            }
            i += 1
        }
        return DecodeResult(sb.toString(), end - start, DecodeStatus.Success)
    }
}

/** 通用单字节编码器。 */
public class SingleByteEncoder <: Encoder {
    private let nm: String
    // 反向表：给定高 128 码点区段？太大。采用线性扫 + 小哈希折衷：
    // 存一份 (code point -> byte) 的 ArrayList，顺序由 highTable 决定。
    private let highToByte: Array<Int32> // 长度 128；[i] 是高字节 i 代表的码点（与 Decoder 共享）

    public init(name: String, highTable: Array<Int32>) {
        if (highTable.size != 128) {
            throw IllegalArgumentException("highTable must have length 128")
        }
        this.nm = name
        this.highToByte = highTable
    }

    public prop name: String {
        get() {
            return nm
        }
    }

    public override func encode(text: String): EncodeResult {
        let runes = text.toRuneArray()
        let out = GrowableBuffer()
        for (i in 0..runes.size) {
            let cp = Int32(UInt32(runes[i]))
            if (cp < 0x80) {
                out.writeByte(UInt8(cp))
                continue
            }
            // 线性扫高表查反向映射
            var found = false
            for (k in 0..128) {
                if (highToByte[k] == cp) {
                    out.writeByte(UInt8(0x80u32 + UInt32(k)))
                    found = true
                    break
                }
            }
            if (!found) {
                return EncodeResult(out.toBytes(), EncodeStatus.Unmappable(i, cp))
            }
        }
        return EncodeResult(out.toBytes(), EncodeStatus.Success)
    }
}

/* ---------- 便利工厂 ---------- */

public func asciiDecoder(): SingleByteDecoder {
    return SingleByteDecoder("us-ascii", asciiHighTable())
}

public func asciiEncoder(): SingleByteEncoder {
    return SingleByteEncoder("us-ascii", asciiHighTable())
}

public func iso88591Decoder(): SingleByteDecoder {
    return SingleByteDecoder("iso-8859-1", iso88591HighTable())
}

public func iso88591Encoder(): SingleByteEncoder {
    return SingleByteEncoder("iso-8859-1", iso88591HighTable())
}

public func iso88592Decoder(): SingleByteDecoder {
    return SingleByteDecoder("iso-8859-2", iso88592HighTable())
}

public func iso88592Encoder(): SingleByteEncoder {
    return SingleByteEncoder("iso-8859-2", iso88592HighTable())
}

public func iso88593Decoder(): SingleByteDecoder {
    return SingleByteDecoder("iso-8859-3", iso88593HighTable())
}

public func iso88594Decoder(): SingleByteDecoder {
    return SingleByteDecoder("iso-8859-4", iso88594HighTable())
}

public func iso88595Decoder(): SingleByteDecoder {
    return SingleByteDecoder("iso-8859-5", iso88595HighTable())
}

public func iso88599Decoder(): SingleByteDecoder {
    return SingleByteDecoder("iso-8859-9", iso88599HighTable())
}

public func iso885915Decoder(): SingleByteDecoder {
    return SingleByteDecoder("iso-8859-15", iso885915HighTable())
}

public func iso885915Encoder(): SingleByteEncoder {
    return SingleByteEncoder("iso-8859-15", iso885915HighTable())
}
