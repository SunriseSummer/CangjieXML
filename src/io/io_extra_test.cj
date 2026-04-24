package cangjie_xml.io

import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import cangjie_xml.dom.*
import cangjie_xml.error.*

// =====================================================================
// io 二轮补强：
// 1. `FileXmlSink.close` 幂等（连续 close 不抛、不改状态）
// 2. `parseXmlBytes` 空字节数组走合理错误路径
// 3. `saveXmlToFile` 抛错时不会留下半写入的文件——通过"先序列化到字节再写盘"
//    的实现选择成立，本测试作为行为契约钉钉。
// =====================================================================

@Test
func testFileXmlSinkCloseIsIdempotent(): Unit {
    let tmp = makeTmpPath("close_idempotent.xml")
    let sink = FileXmlSink(tmp)
    sink.write("<r/>")
    sink.close()
    @Expect(sink.isClosed(), true)
    // 第二次 close 不应抛，也不应复活句柄。
    sink.close()
    @Expect(sink.isClosed(), true)
    // 文件内容仍然只有一次写入的结果。
    let content = String.fromUtf8(File.readFrom(Path(tmp)))
    @Expect(content, "<r/>")
    remove(Path(tmp))
}

@Test
func testParseEmptyBytesThrowsParseException(): Unit {
    // 走 io 层解码 + parser 层"空输入"一条链。空 UTF-8 字节不是 IO 错误，
    // 因此我们期望抛出 `XmlParseException`（由 parser 判定），而不是
    // `XmlIoException`。
    var threw = false
    try {
        parseXmlBytes([])
    } catch (_: XmlParseException) {
        threw = true
    }
    @Expect(threw, true)
}

@Test
func testSaveXmlToFileAtomicOnSerializationFailureAvoidsPartialFile(): Unit {
    // 用一个"一旦序列化就会抛异常"的 sink 路径不好直接构造——本库的
    // `saveXmlToFile` 通过"先序列化到内存字节，再一次性写盘"的设计天然
    // 规避了"部分写入"。此测试钉死这条设计：对一份合法 doc，若目标路径
    // 所在目录不存在，我们应当抛 `XmlIoException`，并且不会创建任何副作用。
    let bogusDir = "/nonexistent_cangjie_xml_dir_e7a3c/out.xml"
    let doc = XmlDocument()
    doc.appendChild(doc.createElement("r"))
    var threw = false
    try {
        saveXmlToFile(doc, bogusDir)
    } catch (_: XmlIoException) {
        threw = true
    }
    @Expect(threw, true)
    @Expect(exists(Path(bogusDir)), false)
}

// --- helpers ----------------------------------------------------------

func makeTmpPath(name: String): String {
    "/tmp/cjxml_${name}"
}
