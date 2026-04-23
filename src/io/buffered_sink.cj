/*
 * io — BufferedSink 装饰器
 *
 * 对应 libxml2: xmlOutputBufferWrite 自带的内部缓冲。
 * 仓颉把它外置为一层显式装饰器，便于测试与替换。
 */
package cangjie_xml.io

import cangjie_xml.core.*

/**
 * 带固定容量缓冲的 Sink 装饰器：
 *   - 小 writes 先累积到 buf，达阈值时一次性 flush 到下层；
 *   - 大 writes（长度 ≥ buf 容量）旁路 buf 直接下写；
 *   - `flush()` 冲刷缓冲后调用下层 `flush()`；
 *   - `close()` 会先 flush 缓冲再（可选）关闭下层（`owned = true` 时）。
 */
public class BufferedSink <: IoSink {
    private let inner: IoSink
    private let buf: Array<Byte>
    private var pos: Int64
    private let owned: Bool
    private var closed: Bool

    public static const DEFAULT_CAPACITY: Int64 = 4096

    public init(inner: IoSink, capacity!: Int64 = DEFAULT_CAPACITY, owned!: Bool = true) {
        if (capacity < 16) {
            throw IllegalArgumentException("BufferedSink capacity must be >= 16")
        }
        this.inner = inner
        this.buf = Array<Byte>(capacity, repeat: 0u8)
        this.pos = 0
        this.owned = owned
        this.closed = false
    }

    public func write(bytes: Array<Byte>): Unit {
        if (closed) {
            throw XmlException(XmlError.IoError("write to closed BufferedSink"))
        }
        let n = bytes.size
        if (n == 0) {
            return
        }
        // 大块：先冲刷缓冲，再旁路直写
        if (n >= buf.size) {
            flushBufferOnly()
            inner.write(bytes)
            return
        }
        // 若当前剩余空间不足，先冲刷
        if (pos + n > buf.size) {
            flushBufferOnly()
        }
        for (i in 0..n) {
            buf[pos + i] = bytes[i]
        }
        pos += n
    }

    public func flush(): Unit {
        if (closed) {
            return
        }
        flushBufferOnly()
        inner.flush()
    }

    public func isClosed(): Bool {
        return closed
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        // 先刷缓冲，再酌情关闭下层。即使刷失败也要标记 closed，避免重复刷。
        try {
            flushBufferOnly()
        } finally {
            closed = true
            if (owned) {
                inner.close()
            }
        }
    }

    /** 当前缓冲内已填字节数；测试用。 */
    public func bufferedSize(): Int64 {
        return pos
    }

    private func flushBufferOnly(): Unit {
        if (pos == 0) {
            return
        }
        // 拷贝已填部分并下写
        let slice = Array<Byte>(pos, repeat: 0u8)
        for (i in 0..pos) {
            slice[i] = buf[i]
        }
        pos = 0
        inner.write(slice)
    }
}
