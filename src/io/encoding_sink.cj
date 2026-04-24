/*
 * io — EncodingSink 装饰器
 *
 * 对应 libxml2: xmlOutputBufferWriteEscape / xmlCharEncOutFunc。
 *
 * 把上层写入的 **UTF-8 字节**（仓颉 `String` 的自然表示）转换为目标编码后下写。
 * 构造时可选：
 *   - 写入首个字节前先输出 BOM（UTF-16 / UTF-32 序列化时通常需要）；
 *   - 遇到无法表示的码点时，抛 `XmlException(EncodingError)` 以精确定位。
 *
 * 注意：上层写入必须是合法的 UTF-8。`writer` / `save` 包确保这一点；
 * 若调用方手动构造字节，务必保证有效性——否则转码时会以 `IoError` 抛出。
 */
package cangjie_xml.io

import cangjie_xml.core.*
import cangjie_xml.encoding.*

public class EncodingSink <: IoSink {
    private let inner: IoSink
    private let encoder: Encoder
    private let decoder: Decoder  // 用来把上层的 UTF-8 字节还原成 String
    private let owned: Bool
    private var closed: Bool
    private var bomWritten: Bool
    private let writeBomOnFirstWrite: Bool

    /**
     * `writeBom`: 是否在首次写入前输出目标编码的 BOM。**默认 `false`**：
     * 许多内置编码器（如 `Utf16Encoder`）自带可选 BOM 输出；为避免"双重 BOM"，
     * 本装饰器默认不代劳。调用方应当二选一：
     *   - 使用 `EncodingSink(sink, Utf16Encoder.bigEndian(emitBom: true))`，`writeBom = false`；
     *   - 使用 `EncodingSink(sink, Utf16Encoder.bigEndian(emitBom: false), writeBom: true)`。
     */
    public init(
        inner: IoSink,
        encoder: Encoder,
        writeBom!: Bool = false,
        owned!: Bool = true
    ) {
        this.inner = inner
        this.encoder = encoder
        this.decoder = Utf8Decoder()
        this.owned = owned
        this.closed = false
        this.bomWritten = false
        this.writeBomOnFirstWrite = writeBom
    }

    public func write(bytes: Array<Byte>): Unit {
        if (closed) {
            throw XmlException(XmlError.IoError("write to closed EncodingSink"))
        }
        if (bytes.size == 0) {
            return
        }
        ensureBom()
        // 把上层 UTF-8 还原为 String，再用 encoder 转到目标编码。
        // 支持分片：decoder 会保留"半截序列"到下次调用。
        let r = decoder.decode(bytes, 0, bytes.size, false)
        match (r.status) {
            case Success => ()
            case NeedMoreInput => ()
            case InvalidBytes(off) =>
                throw XmlException(XmlError.IoError(
                    "EncodingSink: upstream produced invalid UTF-8 at byte offset ${off}"
                ))
        }
        if (r.text.isEmpty()) {
            return
        }
        let enc = encoder.encode(r.text)
        match (enc.status) {
            case Success => ()
            case Unmappable(idx, cp) =>
                // 先把成功的部分写下去，再抛
                if (enc.bytes.size > 0) {
                    inner.write(enc.bytes)
                }
                throw encodingError(encoder.name, idx,
                    "code point U+${cp} at logical index ${idx} not representable")
        }
        if (enc.bytes.size > 0) {
            inner.write(enc.bytes)
        }
    }

    public func flush(): Unit {
        if (closed) {
            return
        }
        // 若 decoder 里还有"半截 UTF-8"，此时强制 endOfInput=true 暴露错误。
        let tail = decoder.decode([], 0, 0, true)
        match (tail.status) {
            case Success => ()
            case NeedMoreInput =>
                throw XmlException(XmlError.IoError(
                    "EncodingSink: flush with unfinished UTF-8 pending bytes"
                ))
            case InvalidBytes(_) =>
                throw XmlException(XmlError.IoError(
                    "EncodingSink: flush found invalid UTF-8 in pending bytes"
                ))
        }
        if (!tail.text.isEmpty()) {
            let enc = encoder.encode(tail.text)
            if (enc.bytes.size > 0) {
                inner.write(enc.bytes)
            }
        }
        inner.flush()
    }

    public func isClosed(): Bool {
        return closed
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        try {
            flush()
        } finally {
            closed = true
            if (owned) {
                inner.close()
            }
        }
    }

    private func ensureBom(): Unit {
        if (bomWritten) {
            return
        }
        bomWritten = true
        if (!writeBomOnFirstWrite) {
            return
        }
        // 写入目标编码的 BOM。对 UTF-8 BOM 也支持（虽然 XML 不要求）。
        let bom = bomBytesFor(encoder.name)
        if (bom.size > 0) {
            inner.write(bom)
        }
    }

    private func bomBytesFor(name: String): Array<Byte> {
        match (name) {
            case "utf-8" => return [0xEFu8, 0xBBu8, 0xBFu8]
            case "utf-16le" => return [0xFFu8, 0xFEu8]
            case "utf-16be" => return [0xFEu8, 0xFFu8]
            case "utf-32le" => return [0xFFu8, 0xFEu8, 0x00u8, 0x00u8]
            case "utf-32be" => return [0x00u8, 0x00u8, 0xFEu8, 0xFFu8]
            case _ => return []
        }
    }
}
