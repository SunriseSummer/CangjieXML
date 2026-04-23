/*
 * io — 输出汇抽象与适配器
 *
 * 对应 libxml2: xmlIO.c 的 xmlOutputBuffer / xmlOutputWriteCallback。
 */
package cangjie_xml.io

import std.io.*
import std.fs.*
import cangjie_xml.core.*

/**
 * 字节输出汇：序列化器把 UTF-8（或经 `EncodingSink` 转码后的）字节写到这里。
 *
 * 语义：
 *   - `write(bytes)` 必须全部写完（部分写由实现自行重试或抛 `IoError`）；
 *   - `flush()` 冲刷任意内置缓冲；
 *   - `close()` 级联关闭内层资源，幂等。
 */
public interface IoSink <: Resource {
    func write(bytes: Array<Byte>): Unit
    func flush(): Unit
}

/* ---------- MemorySink：写入内存数组 ---------- */

/** 把写入累积到内存；`toBytes()` 取快照。 */
public class MemorySink <: IoSink {
    private let buf: GrowableBuffer
    private var closed: Bool

    public init() {
        this.buf = GrowableBuffer()
        this.closed = false
    }

    public func write(bytes: Array<Byte>): Unit {
        if (closed) {
            throw XmlException(XmlError.IoError("write to closed MemorySink"))
        }
        for (i in 0..bytes.size) {
            buf.writeByte(bytes[i])
        }
    }

    public func flush(): Unit {}

    public func isClosed(): Bool {
        return closed
    }

    public func close(): Unit {
        closed = true
    }

    /** 快照当前累积字节；可在 `close()` 之后继续调用。 */
    public func toBytes(): Array<Byte> {
        return buf.toBytes()
    }

    /** 已写字节数。 */
    public func size(): Int64 {
        return buf.size
    }
}

/* ---------- StreamSink：包装 std.io.OutputStream ---------- */

/** 将任意 `std.io.OutputStream` 适配为 `IoSink`。 */
public class StreamSink <: IoSink {
    private let stream: OutputStream
    private let owned: Bool
    private var closed: Bool

    public init(stream: OutputStream, owned!: Bool = false) {
        this.stream = stream
        this.owned = owned
        this.closed = false
    }

    public func write(bytes: Array<Byte>): Unit {
        if (closed) {
            throw XmlException(XmlError.IoError("write to closed StreamSink"))
        }
        try {
            stream.write(bytes)
        } catch (e: Exception) {
            throw XmlException(XmlError.IoError("write failed: ${e.message}"))
        }
    }

    public func flush(): Unit {
        if (closed) {
            return
        }
        try {
            stream.flush()
        } catch (e: Exception) {
            throw XmlException(XmlError.IoError("flush failed: ${e.message}"))
        }
    }

    public func isClosed(): Bool {
        return closed
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        if (owned) {
            match (stream) {
                case r: Resource => r.close()
                case _ => ()
            }
        }
    }
}

/* ---------- FileSink：写出文件 ---------- */

/** 以 `OpenMode.Write`（截断）或 `OpenMode.Append` 打开磁盘文件。 */
public class FileSink <: IoSink {
    private let file: File
    private var closed: Bool

    public init(path: String, append!: Bool = false) {
        let mode = if (append) {
            OpenMode.Append
        } else {
            OpenMode.Write
        }
        try {
            this.file = File(path, mode)
        } catch (e: Exception) {
            throw XmlException(XmlError.IoError("cannot open ${path} for write: ${e.message}"))
        }
        this.closed = false
    }

    public func write(bytes: Array<Byte>): Unit {
        if (closed) {
            throw XmlException(XmlError.IoError("write to closed FileSink"))
        }
        try {
            file.write(bytes)
        } catch (e: Exception) {
            throw XmlException(XmlError.IoError("write failed: ${e.message}"))
        }
    }

    public func flush(): Unit {
        if (closed) {
            return
        }
        try {
            file.flush()
        } catch (e: Exception) {
            throw XmlException(XmlError.IoError("flush failed: ${e.message}"))
        }
    }

    public func isClosed(): Bool {
        return closed
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        closed = true
        try {
            file.close()
        } catch (_: Exception) {}
    }
}
