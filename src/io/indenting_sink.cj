/*
 * io — IndentingSink 装饰器
 *
 * 对应 libxml2: xmlsave.c 中 `xmlSaveFormatFile*` 的 indent 逻辑。
 *
 * 该装饰器提供 **命令式** 的缩进控制：序列化器在适当时机调用
 * `increaseIndent()` / `decreaseIndent()` / `writeIndent()`，
 * 装饰器只负责把缩进层次转换为字节（`\n` + N × indentUnit）。
 *
 * 选择不让装饰器自动扫描输出字节插入换行，原因：
 *   - XML pretty-print 的语义取决于是否存在"有效文本子节点"，
 *     字节层面无法准确判断；由上层（未来的 `writer` 包）驱动更稳妥。
 *   - 这样 `IndentingSink` 对非 pretty 输出零开销（不调用 `writeIndent` 即可）。
 */
package cangjie_xml.io

import cangjie_xml.core.*

public class IndentingSink <: IoSink {
    private let inner: IoSink
    private let indentBytes: Array<Byte>
    private let newlineBytes: Array<Byte>
    private var level: Int64
    private let owned: Bool
    private var closed: Bool

    public init(
        inner: IoSink,
        indentUnit!: String = "  ",
        newline!: String = "\n",
        owned!: Bool = true
    ) {
        this.inner = inner
        this.indentBytes = indentUnit.toArray()
        this.newlineBytes = newline.toArray()
        this.level = 0
        this.owned = owned
        this.closed = false
    }

    public func write(bytes: Array<Byte>): Unit {
        if (closed) {
            throw XmlException(XmlError.IoError("write to closed IndentingSink"))
        }
        inner.write(bytes)
    }

    public func flush(): Unit {
        if (!closed) {
            inner.flush()
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
            inner.close()
        }
    }

    /** 进入下一层。 */
    public func increaseIndent(): Unit {
        level += 1
    }

    /** 回到上一层。当前层 = 0 时静默忽略（避免调用顺序错导致的 crash）。 */
    public func decreaseIndent(): Unit {
        if (level > 0) {
            level -= 1
        }
    }

    /** 当前缩进层次。 */
    public func currentLevel(): Int64 {
        return level
    }

    /** 写一个换行 + 当前层次数次 `indentUnit`。 */
    public func writeIndent(): Unit {
        if (closed) {
            throw XmlException(XmlError.IoError("writeIndent on closed IndentingSink"))
        }
        inner.write(newlineBytes)
        // 若无缩进单元（空字符串），直接 return 避免 0 字节 write。
        if (indentBytes.size == 0 || level == 0) {
            return
        }
        // 一次性构造 level × indentUnit 以减少下层 write 次数
        let total = indentBytes.size * level
        let out = Array<Byte>(total, repeat: 0u8)
        for (lv in 0..level) {
            let base = lv * indentBytes.size
            for (j in 0..indentBytes.size) {
                out[base + j] = indentBytes[j]
            }
        }
        inner.write(out)
    }
}
