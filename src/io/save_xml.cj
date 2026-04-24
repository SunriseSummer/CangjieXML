package cangjie_xml.io

import std.fs.*
import cangjie_xml.dom.*
import cangjie_xml.error.*
import cangjie_xml.writer.*

/**
 * 把 `XmlDocument` 序列化后写入目标文件。
 *
 * ## 实现选择：字符串暂存 vs 流式写盘
 *
 * 当前选择**字符串暂存再一次性写盘**——`XmlDocument.writeToString(options)`
 * → `File.writeTo(path, bytes)`。原因：
 * 1. 让"不破坏原文件"的语义尽量自然：若序列化过程中抛异常，我们根本没打开文件。
 * 2. 实现简单、路径短；大文档场景的流式替代放在 `FileXmlSink`（见同包）里按需选用。
 * 3. 与 `writeToBytes` 共享同一条字节路径，避免两条独立实现漂移。
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
 * 序列化 `XmlDocument` 为 UTF-8 字节。适合写入 HTTP 响应、BLOB、内存管道等。
 */
public func writeXmlToBytes(doc: XmlDocument): Array<Byte> {
    writeXmlToBytes(doc, XmlWriteOptions.default_())
}

public func writeXmlToBytes(doc: XmlDocument, options: XmlWriteOptions): Array<Byte> {
    let sink = StringXmlSink()
    let w = XmlWriter(sink, options: options)
    w.writeDocument(doc)
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
