/*
 * encoding — UTF-8 解码 / 编码
 *
 * 遵循 RFC 3629：4 字节序列上限 U+10FFFF；拒绝 UTF-16 代理（U+D800..U+DFFF）；
 * 拒绝超长序列（overlong encodings）。与 libxml2 `xmlUTF8ToUTF8` 行为对齐。
 */
package cangjie_xml.encoding

import cangjie_xml.core.*

/** UTF-8 解码器。保留字节级"半截序列"以支持流式分片。 */
public class Utf8Decoder <: Decoder {
    // 未消费的前缀字节（最多 3 个）。
    private let pending: GrowableBuffer

    public init() {
        this.pending = GrowableBuffer()
    }

    public prop name: String {
        get() {
            return "utf-8"
        }
    }

    public override func reset(): Unit {
        pending.clear()
    }

    public override func decode(bytes: Array<Byte>, start: Int64, end: Int64, endOfInput: Bool): DecodeResult {
        // 合并 pending + 输入为一个连续数组（在拼接有 pending 字节时）。
        // 对 no-pending 的热路径直接在 bytes 上零拷贝扫描。
        if (pending.size == 0) {
            return decodeSlice(bytes, start, end, endOfInput, /*extraOffset=*/0)
        }
        let combined = concatPendingWith(bytes, start, end)
        let r = decodeSlice(combined, 0, combined.size, endOfInput, /*extraOffset=*/-pending.size)
        return r
    }

    private func concatPendingWith(bytes: Array<Byte>, start: Int64, end: Int64): Array<Byte> {
        let pendingBytes = pending.toBytes()
        let sliceLen = end - start
        let out = Array<Byte>(pendingBytes.size + sliceLen, repeat: 0u8)
        for (i in 0..pendingBytes.size) {
            out[i] = pendingBytes[i]
        }
        for (i in 0..sliceLen) {
            out[pendingBytes.size + i] = bytes[start + i]
        }
        return out
    }

    /**
     * extraOffset：用于把内部合成数组中的偏移 remap 回调用方原 `bytes` 的偏移；
     * 当 pending 不为空时，合成数组前端是 pending 字节，调用方 bytes 的起点对应
     * 合成偏移 = pending.size；因此 `extraOffset = -pending.size`。
     */
    private func decodeSlice(
        buf: Array<Byte>,
        start: Int64,
        end: Int64,
        endOfInput: Bool,
        extraOffset: Int64
    ): DecodeResult {
        let sb = StringBuilder()
        var i = start
        while (i < end) {
            let b0 = UInt32(buf[i])
            var need: Int64
            var cp: UInt32
            var minCp: UInt32
            if (b0 < 0x80u32) {
                // ASCII 快路径：直接 append Rune
                sb.append(Rune(b0))
                i += 1
                // 清空 pending（已经合并在 buf 中）
                if (pending.size > 0 && i >= pending.size) {
                    pending.clear()
                }
                continue
            } else if (b0 < 0xC2u32) {
                // 0x80..0xC1 永远非法（独立续字节或超长序列前缀）
                return invalidAt(i, extraOffset, sb.toString())
            } else if (b0 < 0xE0u32) {
                need = 2
                cp = b0 & 0x1Fu32
                minCp = 0x80u32
            } else if (b0 < 0xF0u32) {
                need = 3
                cp = b0 & 0x0Fu32
                minCp = 0x800u32
            } else if (b0 < 0xF5u32) {
                need = 4
                cp = b0 & 0x07u32
                minCp = 0x10000u32
            } else {
                // 0xF5..0xFF 永远非法
                return invalidAt(i, extraOffset, sb.toString())
            }
            if (i + need > end) {
                // 半截序列：根据 endOfInput 处理
                if (endOfInput) {
                    return invalidAt(i, extraOffset, sb.toString())
                }
                // 把剩余字节挂到 pending 并返回 NeedMoreInput
                pending.clear()
                for (k in i..end) {
                    pending.writeByte(buf[k])
                }
                let consumedInCaller = i + extraOffset - start
                return DecodeResult(sb.toString(), max0(consumedInCaller), DecodeStatus.NeedMoreInput)
            }
            // 读后续 need-1 个续字节
            var ok = true
            for (k in 1..need) {
                let b = UInt32(buf[i + k])
                if ((b & 0xC0u32) != 0x80u32) {
                    ok = false
                    break
                }
                cp = (cp << 6) | (b & 0x3Fu32)
            }
            if (!ok) {
                return invalidAt(i, extraOffset, sb.toString())
            }
            if (cp < minCp) {
                // overlong encoding
                return invalidAt(i, extraOffset, sb.toString())
            }
            if (cp >= 0xD800u32 && cp <= 0xDFFFu32) {
                // surrogate 码点在 UTF-8 中非法
                return invalidAt(i, extraOffset, sb.toString())
            }
            if (cp > 0x10FFFFu32) {
                return invalidAt(i, extraOffset, sb.toString())
            }
            sb.append(Rune(cp))
            i += need
        }
        pending.clear()
        let consumed = i + extraOffset - start
        return DecodeResult(sb.toString(), max0(consumed), DecodeStatus.Success)
    }

    private func invalidAt(errIdx: Int64, extraOffset: Int64, text: String): DecodeResult {
        // 清空 pending——调用方拿到 InvalidBytes 后应决定中止或丢弃若干字节
        pending.clear()
        let errIdxInCaller = errIdx + extraOffset
        let consumed = max0(errIdxInCaller)
        return DecodeResult(text, consumed, DecodeStatus.InvalidBytes(errIdxInCaller))
    }
}

/** UTF-8 编码器：无状态；把仓颉 `String` 的底层 UTF-8 字节直接复制出来。 */
public class Utf8Encoder <: Encoder {
    public init() {}

    public prop name: String {
        get() {
            return "utf-8"
        }
    }

    public override func encode(text: String): EncodeResult {
        // 仓颉 `String.toArray()` 返回 UTF-8 字节拷贝，本身即完成编码。
        return EncodeResult(text.toArray(), EncodeStatus.Success)
    }
}

func max0(x: Int64): Int64 {
    if (x < 0) {
        return 0
    }
    return x
}
