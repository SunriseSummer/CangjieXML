/*
 * encoding — UTF-32 LE / BE 解码
 *
 * UCS-4 每个码点正好 4 字节；LE 与 BE 仅字节序不同。
 * 解码器拒绝 > U+10FFFF、拒绝代理对码点。
 */
package cangjie_xml.encoding

import cangjie_xml.core.*

enum Utf32Order {
    | Le
    | Be
}

public class Utf32Decoder <: Decoder {
    private let order: Utf32Order
    private let nm: String
    private let pending: GrowableBuffer

    init(order: Utf32Order, name: String) {
        this.order = order
        this.nm = name
        this.pending = GrowableBuffer()
    }

    public static func littleEndian(): Utf32Decoder {
        return Utf32Decoder(Utf32Order.Le, "utf-32le")
    }

    public static func bigEndian(): Utf32Decoder {
        return Utf32Decoder(Utf32Order.Be, "utf-32be")
    }

    public prop name: String {
        get() {
            return nm
        }
    }

    public override func reset(): Unit {
        pending.clear()
    }

    public override func decode(bytes: Array<Byte>, start: Int64, end: Int64, endOfInput: Bool): DecodeResult {
        let sb = StringBuilder()
        let pendingBytes = pending.toBytes()
        pending.clear()
        let prefixSize = pendingBytes.size
        let totalLen = prefixSize + (end - start)

        func byteAt(idx: Int64): Byte {
            if (idx < prefixSize) {
                return pendingBytes[idx]
            }
            return bytes[start + (idx - prefixSize)]
        }

        var i: Int64 = 0
        while (i + 4 <= totalLen) {
            let b0 = UInt32(byteAt(i))
            let b1 = UInt32(byteAt(i + 1))
            let b2 = UInt32(byteAt(i + 2))
            let b3 = UInt32(byteAt(i + 3))
            let cp: UInt32 = match (order) {
                case Le => b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
                case Be => (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
            }
            if (cp > 0x10FFFFu32 || (cp >= 0xD800u32 && cp <= 0xDFFFu32)) {
                let raw = i - prefixSize
                let errIdx = if (raw < 0) {
                    start - (prefixSize - i)
                } else {
                    start + raw
                }
                let consumed = if (raw < 0) {
                    0
                } else {
                    raw
                }
                return DecodeResult(sb.toString(), consumed, DecodeStatus.InvalidBytes(errIdx))
            }
            sb.append(Rune(cp))
            i += 4
        }

        let raw = i - prefixSize
        let consumed = if (raw < 0) {
            0
        } else {
            raw
        }

        if (i < totalLen) {
            if (endOfInput) {
                let errIdx = if (raw < 0) {
                    start - (prefixSize - i)
                } else {
                    start + raw
                }
                return DecodeResult(sb.toString(), consumed, DecodeStatus.InvalidBytes(errIdx))
            }
            for (k in i..totalLen) {
                pending.writeByte(byteAt(k))
            }
            return DecodeResult(sb.toString(), consumed, DecodeStatus.NeedMoreInput)
        }
        return DecodeResult(sb.toString(), consumed, DecodeStatus.Success)
    }
}
