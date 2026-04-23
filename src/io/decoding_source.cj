/*
 * io — DecodingSource 辅助
 *
 * 对应 libxml2: xmlParserInputBuffer + 字符编码切换。
 *
 * 把字节级 `IoSource` 提升为字符级读取：
 *   - 构造时可传入显式 `Decoder`；否则根据 BOM + `encodingHint` 自动选择；
 *   - 负责跳过 BOM（若存在）；
 *   - 提供 `readAllAsString()` / `readChunk()` 便利 API；
 *   - 保留流式状态，支持分片读取。
 */
package cangjie_xml.io

import cangjie_xml.core.*
import cangjie_xml.encoding.*

public class DecodingSource <: Resource {
    /** 读缓冲大小：解码前一次性读入的字节数。4 KiB 取自常见 I/O 页面大小。 */
    public static const READ_BUFFER_SIZE: Int64 = 4096
    /** BOM 探测所需最大字节数：UTF-32 BOM 即 4 字节。 */
    public static const BOM_PROBE_SIZE: Int64 = 4

    private let source: IoSource
    private let decoder: Decoder
    private let ownedSource: Bool
    private var closed: Bool
    // 字节读缓冲：解码前的原始字节
    private let readBuf: Array<Byte>
    // 当 BOM 被消费后，剩余"先行字节"（探测阶段读入但尚未喂给解码器）
    private var prefix: Array<Byte>
    private var prefixPos: Int64
    // 流是否已读到 EOF
    private var eof: Bool

    /** 检测到的编码规范名（可能与 `encodingHint` 不同——BOM 优先）。 */
    public let detectedEncoding: String
    /** 若探测到 BOM，这里记录其种类；否则 `None`。 */
    public let bom: ?BomKind

    public init(
        source: IoSource,
        registry!: EncodingRegistry = EncodingRegistry.defaultRegistry(),
        explicitEncoding!: ?String = None,
        ownedSource!: Bool = true
    ) {
        this.source = source
        this.ownedSource = ownedSource
        this.closed = false
        this.readBuf = Array<Byte>(READ_BUFFER_SIZE, repeat: 0u8)
        this.eof = false

        // 第一步：先读最多 BOM_PROBE_SIZE 字节用于 BOM / 启发式探测
        let probe = Array<Byte>(BOM_PROBE_SIZE, repeat: 0u8)
        var probeLen = 0
        while (probeLen < BOM_PROBE_SIZE) {
            let n = source.read(probe[probeLen..])
            if (n <= 0) {
                this.eof = true
                break
            }
            probeLen += n
        }
        let probeSlice = Array<Byte>(probeLen, repeat: 0u8)
        for (i in 0..probeLen) {
            probeSlice[i] = probe[i]
        }
        let (detected, skipBom) = chooseEncoding(probeSlice, explicitEncoding, source.encodingHint)
        this.detectedEncoding = detected
        this.bom = if (skipBom) {
            detectBomAt(probeSlice, 0)
        } else {
            None
        }
        // 若有 BOM，跳过其字节
        let skip = match (this.bom) {
            case Some(k) => k.length()
            case None => 0
        }
        let remain = probeLen - skip
        if (remain > 0) {
            this.prefix = Array<Byte>(remain, repeat: 0u8)
            for (i in 0..remain) {
                this.prefix[i] = probeSlice[skip + i]
            }
        } else {
            this.prefix = []
        }
        this.prefixPos = 0

        // 实例化解码器
        match (registry.newDecoder(detected)) {
            case Some(d) => this.decoder = d
            case None =>
                throw XmlException(XmlError.EncodingError(
                    Position.unknown(),
                    "unknown encoding: ${detected}"
                ))
        }
    }

    /**
     * 解码器选择优先级：
     *   1. 显式指定（`explicitEncoding`）——无条件采用，不跳 BOM（除非 BOM 与之一致时由调用方再处理）；
     *   2. 探测到 BOM ——以 BOM 指示为准，跳过 BOM 字节；
     *   3. 源的 `encodingHint` —— HTTP / 外部声明；
     *   4. 最终回落到 UTF-8（W3C XML 默认值）。
     */
    private static func chooseEncoding(
        probe: Array<Byte>,
        explicit: ?String,
        hint: ?String
    ): (String, Bool) {
        match (explicit) {
            case Some(name) => return (name, false)
            case None => ()
        }
        match (detectBomAt(probe, 0)) {
            case Some(k) => return (k.encodingName(), true)
            case None => ()
        }
        match (hint) {
            case Some(name) => return (name, false)
            case None => return ("utf-8", false)
        }
    }

    /**
     * 读取下一批解码后的字符。返回空字符串表示本次无字符产出；
     * 当 `isEof()` 为 true 且无 pending 数据时，所有后续调用都返回 `""`。
     * 出错时抛 `XmlException(EncodingError)`。
     */
    public func readChunk(): String {
        if (closed) {
            return ""
        }
        // 先把 prefix（BOM 探测残留）喂进去
        if (prefixPos < prefix.size) {
            let r = decoder.decode(prefix, prefixPos, prefix.size, eof)
            match (r.status) {
                case Success =>
                    prefixPos = prefix.size
                    return r.text
                case NeedMoreInput =>
                    prefixPos = prefix.size
                    return r.text
                case InvalidBytes(off) =>
                    throw XmlException(XmlError.EncodingError(
                        Position(source: source.baseUri, line: 0, column: 0, byteOffset: off),
                        "invalid ${detectedEncoding} byte at offset ${off}"
                    ))
            }
        }
        if (eof) {
            return ""
        }
        let n = source.read(readBuf)
        if (n <= 0) {
            eof = true
            // 最后一次调用以通知解码器：EOF
            let r = decoder.decode([], 0, 0, true)
            match (r.status) {
                case Success => return r.text
                case NeedMoreInput =>
                    throw XmlException(XmlError.EncodingError(
                        Position.unknown(),
                        "unexpected end of input in ${detectedEncoding}"
                    ))
                case InvalidBytes(off) =>
                    throw XmlException(XmlError.EncodingError(
                        Position(source: source.baseUri, line: 0, column: 0, byteOffset: off),
                        "invalid ${detectedEncoding} byte at offset ${off}"
                    ))
            }
        }
        let r = decoder.decode(readBuf, 0, n, false)
        match (r.status) {
            case Success | NeedMoreInput => return r.text
            case InvalidBytes(off) =>
                throw XmlException(XmlError.EncodingError(
                    Position(source: source.baseUri, line: 0, column: 0, byteOffset: off),
                    "invalid ${detectedEncoding} byte at offset ${off}"
                ))
        }
    }

    /** 读完全部输入，返回解码后的完整字符串。 */
    public func readAllAsString(): String {
        let sb = StringBuilder()
        while (true) {
            let piece = readChunk()
            if (piece.isEmpty() && eof && prefixPos >= prefix.size) {
                break
            }
            sb.append(piece)
        }
        return sb.toString()
    }

    public func isEof(): Bool {
        return eof && prefixPos >= prefix.size
    }

    public func isClosed(): Bool {
        return closed
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        if (ownedSource) {
            source.close()
        }
    }
}
