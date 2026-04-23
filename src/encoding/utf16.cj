/*
 * encoding — UTF-16 LE / BE 解码 + 编码
 *
 * 遵循 RFC 2781。代理对（D800..DFFF）必须严格成对出现，否则报错。
 */
package cangjie_xml.encoding

import cangjie_xml.core.*

/** UTF-16 字节序。 */
enum Utf16Order {
    | Le
    | Be
}

/** UTF-16 解码器。跨分片时最多缓存 3 字节（1 字节尾巴 + 完整高位代理）。 */
public class Utf16Decoder <: Decoder {
    private let order: Utf16Order
    private let nm: String
    private let pending: GrowableBuffer
    // 等待低位代理：Some(cp) 表示上一轮读到的高位代理值
    private var pendingHighSurrogate: ?UInt32

    init(order: Utf16Order, name: String) {
        this.order = order
        this.nm = name
        this.pending = GrowableBuffer()
        this.pendingHighSurrogate = None
    }

    public static func littleEndian(): Utf16Decoder {
        return Utf16Decoder(Utf16Order.Le, "utf-16le")
    }

    public static func bigEndian(): Utf16Decoder {
        return Utf16Decoder(Utf16Order.Be, "utf-16be")
    }

    public prop name: String {
        get() {
            return nm
        }
    }

    public override func reset(): Unit {
        pending.clear()
        pendingHighSurrogate = None
    }

    public override func decode(bytes: Array<Byte>, start: Int64, end: Int64, endOfInput: Bool): DecodeResult {
        let sb = StringBuilder()
        var bytesConsumed = 0

        // 合并可能残留的 1 字节 pending + 调用方输入
        let pendingBytes = pending.toBytes()
        pending.clear()
        let prefixSize = pendingBytes.size

        var i: Int64 = 0
        let totalLen = prefixSize + (end - start)

        // 提供一个 "逻辑字节" 取值函数
        func byteAt(idx: Int64): Byte {
            if (idx < prefixSize) {
                return pendingBytes[idx]
            }
            return bytes[start + (idx - prefixSize)]
        }

        while (i + 1 < totalLen) {
            let b0 = UInt32(byteAt(i))
            let b1 = UInt32(byteAt(i + 1))
            let unit: UInt32 = match (order) {
                case Le => b0 | (b1 << 8)
                case Be => (b0 << 8) | b1
            }
            // 处理代理对
            if (unit >= 0xD800u32 && unit <= 0xDBFFu32) {
                // 高位代理
                match (pendingHighSurrogate) {
                    case Some(_) =>
                        // 连续两个高位代理 → 非法
                        let errIdx = callerIndexOf(i, prefixSize, start)
                        pendingHighSurrogate = None
                        return DecodeResult(sb.toString(), callerConsumedBefore(i, prefixSize),
                            DecodeStatus.InvalidBytes(errIdx))
                    case None => pendingHighSurrogate = Some(unit)
                }
                i += 2
                continue
            }
            if (unit >= 0xDC00u32 && unit <= 0xDFFFu32) {
                // 低位代理：必须紧随高位代理
                match (pendingHighSurrogate) {
                    case Some(high) =>
                        let cp: UInt32 = 0x10000u32 + ((high - 0xD800u32) << 10) + (unit - 0xDC00u32)
                        sb.append(Rune(cp))
                        pendingHighSurrogate = None
                    case None =>
                        // 孤立低位代理 → 非法
                        let errIdx = callerIndexOf(i, prefixSize, start)
                        return DecodeResult(sb.toString(), callerConsumedBefore(i, prefixSize),
                            DecodeStatus.InvalidBytes(errIdx))
                }
                i += 2
                continue
            }
            // BMP 码点
            match (pendingHighSurrogate) {
                case Some(_) =>
                    // 前面的高位代理没有低位跟随 → 非法
                    let errIdx = callerIndexOf(i, prefixSize, start)
                    pendingHighSurrogate = None
                    return DecodeResult(sb.toString(), callerConsumedBefore(i, prefixSize),
                        DecodeStatus.InvalidBytes(errIdx))
                case None => ()
            }
            sb.append(Rune(unit))
            i += 2
        }

        bytesConsumed = callerConsumedBefore(i, prefixSize)

        // 处理尾巴字节（单个字节未成对）
        if (i < totalLen) {
            if (endOfInput) {
                // 奇数字节数 → 非法
                let errIdx = callerIndexOf(i, prefixSize, start)
                return DecodeResult(sb.toString(), bytesConsumed, DecodeStatus.InvalidBytes(errIdx))
            }
            // 挂 1 字节到 pending
            pending.writeByte(byteAt(i))
        }

        // 若 endOfInput 且仍挂着高位代理 → 非法
        match (pendingHighSurrogate) {
            case Some(_) =>
                if (endOfInput) {
                    pendingHighSurrogate = None
                    return DecodeResult(sb.toString(), bytesConsumed,
                        DecodeStatus.InvalidBytes(bytesConsumed))
                }
                // 否则留作状态（已自然保留）
                return DecodeResult(sb.toString(), bytesConsumed, DecodeStatus.NeedMoreInput)
            case None => ()
        }

        if (pending.size > 0) {
            return DecodeResult(sb.toString(), bytesConsumed, DecodeStatus.NeedMoreInput)
        }
        return DecodeResult(sb.toString(), bytesConsumed, DecodeStatus.Success)
    }

    /** 把"逻辑位置 i"换算成调用方 `bytes` 数组中的绝对下标（可能 < 0 代表落在 pending 区）。 */
    private func callerIndexOf(i: Int64, prefixSize: Int64, start: Int64): Int64 {
        if (i < prefixSize) {
            return start - (prefixSize - i)
        }
        return start + (i - prefixSize)
    }

    /** 把"逻辑位置 i"换算成调用方在本次调用消费的字节数（从 start 算起，不小于 0）。 */
    private func callerConsumedBefore(i: Int64, prefixSize: Int64): Int64 {
        let raw = i - prefixSize
        if (raw < 0) {
            return 0
        }
        return raw
    }
}

/** UTF-16 编码器，内置支持 BOM 输出。 */
public class Utf16Encoder <: Encoder {
    private let order: Utf16Order
    private let nm: String
    private let emitBom: Bool

    init(order: Utf16Order, name: String, emitBom: Bool) {
        this.order = order
        this.nm = name
        this.emitBom = emitBom
    }

    public static func littleEndian(emitBom!: Bool = true): Utf16Encoder {
        return Utf16Encoder(Utf16Order.Le, "utf-16le", emitBom)
    }

    public static func bigEndian(emitBom!: Bool = true): Utf16Encoder {
        return Utf16Encoder(Utf16Order.Be, "utf-16be", emitBom)
    }

    public prop name: String {
        get() {
            return nm
        }
    }

    public override prop writesBom: Bool {
        get() {
            return emitBom
        }
    }

    public override func encode(text: String): EncodeResult {
        let buf = GrowableBuffer()
        if (emitBom) {
            writeUnit(buf, 0xFEFFu32)
        }
        let runes = text.toRuneArray()
        for (i in 0..runes.size) {
            let cp = UInt32(runes[i])
            if (cp <= 0xFFFFu32) {
                if (cp >= 0xD800u32 && cp <= 0xDFFFu32) {
                    // 理论上 Rune 不应为代理；保守处理。
                    return EncodeResult(buf.toBytes(), EncodeStatus.Unmappable(i, Int32(cp)))
                }
                writeUnit(buf, cp)
            } else if (cp <= 0x10FFFFu32) {
                let v = cp - 0x10000u32
                let high: UInt32 = 0xD800u32 + (v >> 10)
                let low: UInt32 = 0xDC00u32 + (v & 0x3FFu32)
                writeUnit(buf, high)
                writeUnit(buf, low)
            } else {
                return EncodeResult(buf.toBytes(), EncodeStatus.Unmappable(i, Int32(cp)))
            }
        }
        return EncodeResult(buf.toBytes(), EncodeStatus.Success)
    }

    private func writeUnit(buf: GrowableBuffer, unit: UInt32): Unit {
        let lo = UInt8(unit & 0xFFu32)
        let hi = UInt8((unit >> 8) & 0xFFu32)
        match (order) {
            case Le =>
                buf.writeByte(lo)
                buf.writeByte(hi)
            case Be =>
                buf.writeByte(hi)
                buf.writeByte(lo)
        }
    }
}
