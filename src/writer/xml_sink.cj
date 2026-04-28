package fastxml.writer

/**
 * 字符串输出汇聚点。`XmlWriter` 通过 `XmlSink` 与真正的目的地（字符串缓冲区、
 * 文件、流）解耦
 *
 * - 同一个 Writer 既可驱动 `writeToString`，也可驱动 `saveFile` 等其他目的地；
 * - Sink 只做字节搬运，不做 XML 语法决策
 */
public interface XmlSink {
    // 追加一段 UTF-8 字符串到目的地
    func write(text: String): Unit

    // 把缓冲区内容刷到底层。对纯内存 Sink 可为 no-op
    func flush(): Unit
}

/**
 * 最基础的 Sink：把所有写入累积到一个 `StringBuilder` 中，结束后通过
 * `toString()` 读取。适合 `XmlDocument.writeToString()` 等内存场景
 *
 * 非线程安全——并发使用需要外部同步
 */
public class StringXmlSink <: XmlSink {
    /**
     * 包内可见，供 `XmlWriter` 的 fast-path 直接 append 绕过接口分派
     * 仓颉字符串 builder 性能特征（CangjiePerf::string_concat）显示
     * `StringBuilder.append` 单次成本不算低，因此减少接口分派 + 减少 append
     * 次数对热路径收益显著
     */
    let buffer: StringBuilder

    public init() {
        this.buffer = StringBuilder()
    }

    /**
     * 接受容量提示的构造形态，便于上层把"预期输出大小"沿着 sink 链路传下来；
     * 当前 `StringBuilder` 暂无公开容量 API，参数被忽略
     */
    public init(initialCapacity: Int64) {
        this.buffer = StringBuilder()
        let _ = initialCapacity
    }

    public func write(text: String): Unit {
        buffer.append(text)
    }

    public func flush(): Unit {
        // 字符串 Sink 无需刷盘
    }

    // 读取已累积的输出。调用多次结果相同；不会清空缓冲区
    public func toString(): String {
        buffer.toString()
    }
}
