package cangjie_xml.writer

/**
 * 字符串输出汇聚点。`XmlWriter` 通过 `XmlSink` 与真正的目的地（字符串缓冲区、
 * 文件、流）解耦。
 *
 * - 同一个 Writer 既可驱动 `writeToString`，也可驱动 `saveFile` 等其他目的地；
 * - Sink 只做字节搬运，不做 XML 语法决策。
 */
public interface XmlSink {
    /** 追加一段 UTF-8 字符串到目的地。 */
    func write(text: String): Unit

    /** 把缓冲区内容刷到底层。对纯内存 Sink 可为 no-op。 */
    func flush(): Unit
}

/**
 * 最基础的 Sink：把所有写入累积到一个 `StringBuilder` 中，结束后通过
 * `toString()` 读取。适合 `XmlDocument.writeToString()` 等内存场景。
 *
 * 非线程安全——并发使用需要外部同步。
 */
public class StringXmlSink <: XmlSink {
    private let buffer: StringBuilder

    public init() {
        this.buffer = StringBuilder()
    }

    public init(initialCapacity: Int64) {
        this.buffer = StringBuilder()
        // 预分配提示（当前 StringBuilder 无公开容量 API，保留入参形态以兼容未来）。
        let _ = initialCapacity
    }

    public func write(text: String): Unit {
        buffer.append(text)
    }

    public func flush(): Unit {
        // 字符串 Sink 无需刷盘。
    }

    /** 读取已累积的输出。调用多次结果相同；不会清空缓冲区。 */
    public func toString(): String {
        buffer.toString()
    }
}
