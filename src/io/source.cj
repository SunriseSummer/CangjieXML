/*
 * io — 输入源抽象与适配器
 *
 * 对应 libxml2: xmlIO.c 的 xmlParserInputBuffer / xmlInputReadCallback。
 *
 * 与 C 版的差异：
 *   - 用 `interface` 代替函数指针组，便于 `extend` 与组合；
 *   - 继承仓颉 `Resource`，获得 `try-with-resource` 自动关闭；
 *   - `baseUri` / `encodingHint` 作为元数据显式暴露，parser 阶段可直接查询；
 *   - 不内嵌 HTTP / FTP；网络资源走 `StreamSource` 包裹 `stdx.net` 流即可。
 */
package cangjie_xml.io

import std.io.*
import std.fs.*
import cangjie_xml.core.*

/**
 * 字节输入源：XML 解析器从这里按字节流消费源文档。
 *
 * 语义：
 *   - `read(buffer)` 与 `std.io.InputStream.read` 相同：返回实际读取字节数；0 = EOF。
 *     约定返回值 `>= 0`，底层发生 I/O 错误应抛 `XmlException(IoError(...))`。
 *   - `baseUri`：可选，用于相对参考解析（对应 libxml2 `xmlParserInputBufferURL`）。
 *   - `encodingHint`：可选，外部提供的编码提示（例如 HTTP `charset` 头、XML 目录表）。
 *     解析器仍会以 BOM + `<?xml encoding=?>` 声明为准，hint 仅在二者都缺失时生效。
 *   - `close()` 幂等；多次调用不应抛异常。
 */
public interface IoSource <: Resource {
    func read(buffer: Array<Byte>): Int64
    prop baseUri: ?String
    prop encodingHint: ?String
}

/* ---------- MemorySource：字节数组源 ---------- */

/** 零拷贝字节数组输入源。 */
public class MemorySource <: IoSource {
    private let bytes: Array<Byte>
    private var pos: Int64
    private var closed: Bool
    private let uri: ?String
    private let hint: ?String

    public init(bytes: Array<Byte>, baseUri!: ?String = None, encodingHint!: ?String = None) {
        this.bytes = bytes
        this.pos = 0
        this.closed = false
        this.uri = baseUri
        this.hint = encodingHint
    }

    public prop baseUri: ?String {
        get() {
            return uri
        }
    }

    public prop encodingHint: ?String {
        get() {
            return hint
        }
    }

    public func read(buffer: Array<Byte>): Int64 {
        if (closed) {
            return 0
        }
        let remaining = bytes.size - pos
        if (remaining <= 0) {
            return 0
        }
        let n = if (buffer.size < remaining) {
            buffer.size
        } else {
            remaining
        }
        for (i in 0..n) {
            buffer[i] = bytes[pos + i]
        }
        pos += n
        return n
    }

    public func isClosed(): Bool {
        return closed
    }

    public func close(): Unit {
        closed = true
    }
}

/* ---------- StringSource：把 String 当字节源（UTF-8）---------- */

/**
 * 以 UTF-8 字节序列暴露一个 `String`。便于在内存中喂解析器而不关心编码协商。
 * 自动把 `encodingHint` 置为 `"utf-8"`。
 */
public class StringSource <: IoSource {
    private let inner: MemorySource

    public init(text: String, baseUri!: ?String = None) {
        this.inner = MemorySource(text.toArray(), baseUri: baseUri, encodingHint: Some("utf-8"))
    }

    public prop baseUri: ?String {
        get() {
            return inner.baseUri
        }
    }

    public prop encodingHint: ?String {
        get() {
            return inner.encodingHint
        }
    }

    public func read(buffer: Array<Byte>): Int64 {
        return inner.read(buffer)
    }

    public func isClosed(): Bool {
        return inner.isClosed()
    }

    public func close(): Unit {
        inner.close()
    }
}

/* ---------- StreamSource：包装任意 std.io.InputStream ---------- */

/**
 * 将 `std.io.InputStream` 适配为 `IoSource`。
 *
 * 注意：`InputStream` 自身不带 `close` 语义；`owned = true` 且 `stream` 也实现
 * `Resource` 时，本类的 `close()` 会级联关闭；否则只标记本地关闭位。
 */
public class StreamSource <: IoSource {
    private let stream: InputStream
    private let owned: Bool
    private var closed: Bool
    private let uri: ?String
    private let hint: ?String

    public init(
        stream: InputStream,
        owned!: Bool = false,
        baseUri!: ?String = None,
        encodingHint!: ?String = None
    ) {
        this.stream = stream
        this.owned = owned
        this.closed = false
        this.uri = baseUri
        this.hint = encodingHint
    }

    public prop baseUri: ?String {
        get() {
            return uri
        }
    }

    public prop encodingHint: ?String {
        get() {
            return hint
        }
    }

    public func read(buffer: Array<Byte>): Int64 {
        if (closed) {
            return 0
        }
        try {
            return stream.read(buffer)
        } catch (e: Exception) {
            throw XmlException(XmlError.IoError(e.message))
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

/* ---------- FileSource：打开磁盘文件 ---------- */

/**
 * 打开磁盘文件作为 `IoSource`，`baseUri` 默认填入路径字符串。
 * 构造失败会抛 `XmlException(IoError)` 而非底层 `FSException`，便于上层统一处理。
 */
public class FileSource <: IoSource {
    private let file: File
    private var closed: Bool
    private let uri: ?String
    private let hint: ?String

    public init(path: String, encodingHint!: ?String = None) {
        try {
            this.file = File(path, OpenMode.Read)
        } catch (e: Exception) {
            throw XmlException(XmlError.IoError("cannot open ${path}: ${e.message}"))
        }
        this.closed = false
        this.uri = Some(path)
        this.hint = encodingHint
    }

    public prop baseUri: ?String {
        get() {
            return uri
        }
    }

    public prop encodingHint: ?String {
        get() {
            return hint
        }
    }

    public func read(buffer: Array<Byte>): Int64 {
        if (closed) {
            return 0
        }
        try {
            return file.read(buffer)
        } catch (e: Exception) {
            throw XmlException(XmlError.IoError("read failed: ${e.message}"))
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
        } catch (_: Exception) {
            // 关闭失败不再抛：遵循 libxml2 传统（日志级别错误）。
        }
    }
}

/* ---------- 便利函数：读尽 ---------- */

/** `readAll` 的一次性读缓冲区大小；与 DecodingSource 的主读缓冲一致（4 KiB 页面）。 */
const READ_ALL_BUFFER_SIZE: Int64 = 4096

/** 把 `IoSource` 读尽为字节数组。用于小文档 / 测试。 */
public func readAll(source: IoSource): Array<Byte> {
    let acc = GrowableBuffer()
    let buf = Array<Byte>(READ_ALL_BUFFER_SIZE, repeat: 0u8)
    while (true) {
        let n = source.read(buf)
        if (n <= 0) {
            break
        }
        for (i in 0..n) {
            acc.writeByte(buf[i])
        }
    }
    return acc.toBytes()
}
