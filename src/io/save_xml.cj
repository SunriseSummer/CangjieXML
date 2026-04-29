package fastxml.io

import std.fs.*
import fastxml.dom.*
import fastxml.error.*
import fastxml.writer.*

/**
 * 把 `XmlDocument` 序列化后写入目标文件
 *
 * 实现策略：先在内存把整个文档序列化为字节，再一次性写盘——序列化失败时
 * 不打开文件，自然获得"不破坏原文件"语义。大文档场景的流式替代见同包内
 * `FileXmlSink`
 *
 * ## 错误映射
 *
 * | 触发情形 | 抛出 |
 * |---|---|
 * | 写入过程出现 `FSException`（无权限、磁盘满…） | `XmlIoException(FileWriteFailed(path, cause))` |
 * | 其它异常（包括 Writer 层面的） | 不吞掉，原样抛出 |
 */
public func saveXmlToFile(doc: XmlDocument, path: String): Unit {
    saveXmlToFile(doc, path, XmlWriteOptions.default_())
}

public func saveXmlToFile(doc: XmlDocument, path: String, options: XmlWriteOptions): Unit {
    let bytes = writeXmlToBytes(doc, options)
    writeAllBytes(path, bytes)
}

/**
 * 序列化 `XmlDocument` 为 UTF-8 字节。适合写入 HTTP 响应、BLOB、内存管道等
 */
public func writeXmlToBytes(doc: XmlDocument): Array<Byte> {
    writeXmlToBytes(doc, XmlWriteOptions.default_())
}

public func writeXmlToBytes(doc: XmlDocument, options: XmlWriteOptions): Array<Byte> {
    let sink = StringXmlSink()
    let writer = XmlWriter(sink, options: options)
    writer.writeDocument(doc)
    sink.toString().toArray()
}

// ======================================================================
// 内部工具
// ======================================================================

func writeAllBytes(path: String, bytes: Array<Byte>): Unit {
    try {
        File.writeTo(Path(path), bytes)
    } catch (e: FSException) {
        throw XmlIoException(FileWriteFailed(path, e.message))
    }
}
