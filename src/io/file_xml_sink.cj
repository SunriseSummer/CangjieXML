package cangjie_xml.io

import std.fs.*
import std.io.*
import cangjie_xml.error.*
import cangjie_xml.writer.*

/**
 * 基于 `File` 的流式 `XmlSink`——把每次 `write(text)` 直接以 UTF-8 写入文件
 * （经 `BufferedOutputStream` 缓冲），避免 `saveXmlToFile` 先把整个文档放进
 * `StringBuilder` 的内存峰值。
 *
 * ## 何时使用
 *
 * - 文档足够大（几 MB 以上）；
 * - 上层自己组合 `XmlWriter` 而不走 `saveXmlToFile` 的便捷路径；
 * - 需要把多次写入合并到同一个文件里。
 *
 * ## 资源语义
 *
 * 实现 `XmlSink + Resource`：
 *
 * ```cangjie
 * try (sink = FileXmlSink("/tmp/out.xml")) {
 *     let w = XmlWriter(sink)
 *     w.writeDocument(doc)
 * }
 * ```
 *
 * 退出 `try-with-resource` 时会先 `flush` 再 `close`。整条链失败时文件可能
 * 半写入；若需要"全有或全无"语义，请改用 `saveXmlToFile`。
 */
public class FileXmlSink <: XmlSink & Resource {
    private let path: String
    private let file: File
    private let buffered: BufferedOutputStream<OutputStream>
    private var closed: Bool

    /** 目的文件；若不存在则创建，若存在则截断。 */
    public init(path: String) {
        this.path = path
        try {
            this.file = File(Path(path), Write)
        } catch (e: FSException) {
            throw XmlIoException(FileWriteFailed(path, e.message))
        }
        // BufferedOutputStream 持有 File（File 自身是 OutputStream）
        this.buffered = BufferedOutputStream<OutputStream>(file)
        this.closed = false
    }

    public func write(text: String): Unit {
        if (closed) {
            throw XmlIoException(FileWriteFailed(path, "sink already closed"))
        }
        try {
            buffered.write(text.toArray())
        } catch (e: FSException) {
            throw XmlIoException(FileWriteFailed(path, e.message))
        } catch (e: IOException) {
            throw XmlIoException(FileWriteFailed(path, e.message))
        }
    }

    public func flush(): Unit {
        if (closed) { return }
        try {
            buffered.flush()
        } catch (e: IOException) {
            throw XmlIoException(FileWriteFailed(path, e.message))
        }
    }

    public func isClosed(): Bool {
        closed
    }

    public func close(): Unit {
        if (closed) { return }
        closed = true
        // 先刷缓冲区再关底层句柄；任一步抛异常都要保证 File 被关
        var flushError: ?Exception = None
        try {
            buffered.flush()
        } catch (e: Exception) {
            flushError = e
        }
        file.close()
        match (flushError) {
            case Some(e) => throw XmlIoException(FileWriteFailed(path, e.message))
            case None    => ()
        }
    }
}
