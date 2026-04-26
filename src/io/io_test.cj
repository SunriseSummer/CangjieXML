package tinyxml2.io

import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import tinyxml2.dom.*
import tinyxml2.error.*
import tinyxml2.parser.*
import tinyxml2.writer.*
import tinyxml2.build.*
import tinyxml2.query.*

// ======================================================================
// 测试夹具
// ======================================================================

const TMP_ROOT: String = "/tmp/tinyxml2_io_tests"

class TempFile {
    public let path: String
    public init(name: String) {
        if (!exists(Path(TMP_ROOT))) {
            Directory.create(Path(TMP_ROOT), recursive: true)
        }
        this.path = "${TMP_ROOT}/${name}"
        removeIfExists(Path(this.path), recursive: false)
    }
    public func cleanup(): Unit {
        removeIfExists(Path(path), recursive: false)
    }
}

func makeSampleDoc(): XmlDocument {
    XmlDocumentBuilder()
        .declaration()
        .root("catalog") { r =>
            r.element("book") { b =>
                b.attribute("id", "1").text("SICP")
            }
            r.element("book") { b =>
                b.attribute("id", "2").text("TAOCP")
            }
        }
        .build()
}

// ======================================================================
// File round-trip
// ======================================================================

@Test
func testSaveAndLoadRoundTrip(): Unit {
    let tmp = TempFile("round_trip.xml")
    try {
        let doc = makeSampleDoc()
        saveXmlToFile(doc, tmp.path)

        let loaded = loadXmlFromFile(tmp.path)
        let root = loaded.rootElement.getOrThrow()
        @Expect(root.name, "catalog")

        // 用 requiredChildElement + childElementTexts 间接验证双 <book>
        let texts = root.childElementTexts("book")
        @Expect(texts.size, 2)
        @Expect(texts[0], "SICP")
        @Expect(texts[1], "TAOCP")
        let firstBook = root.requiredChildElement("book")
        @Expect(firstBook.attribute("id").getOrThrow(), "1")
    } finally {
        tmp.cleanup()
    }
}

@Test
func testLoadWithOptions(): Unit {
    let tmp = TempFile("with_options.xml")
    try {
        saveXmlToFile(makeSampleDoc(), tmp.path)
        // 使用默认选项加载（preserveAll preset 暂未提供）
        let doc = loadXmlFromFile(tmp.path, XmlParseOptions())
        @Expect(doc.rootElement.getOrThrow().name, "catalog")
    } finally {
        tmp.cleanup()
    }
}

@Test
func testSaveWithCompactOptions(): Unit {
    let tmp = TempFile("compact.xml")
    try {
        let doc = makeSampleDoc()
        saveXmlToFile(doc, tmp.path, XmlWriteOptions.compactPreset())
        let bytes = File.readFrom(Path(tmp.path))
        let text = String.fromUtf8(bytes)
        // 紧凑预设不应含用于美化的换行
        @Expect(text.contains("\n"), false)
        // 仍应可往返解析
        let back = parseXml(text)
        @Expect(back.rootElement.getOrThrow().name, "catalog")
    } finally {
        tmp.cleanup()
    }
}

// ======================================================================
// Bytes round-trip
// ======================================================================

@Test
func testWriteAndParseBytes(): Unit {
    let doc = makeSampleDoc()
    let bytes = writeXmlToBytes(doc)
    @Expect(bytes.size > 0, true)
    let back = parseXmlBytes(bytes)
    @Expect(back.rootElement.getOrThrow().name, "catalog")
    @Expect(back.rootElement.getOrThrow().childElementTexts("book").size, 2)
}

@Test
func testUnicodeContentRoundTrip(): Unit {
    let tmp = TempFile("unicode.xml")
    try {
        let doc = XmlDocumentBuilder()
            .root("doc") { r =>
                r.element("book") { b => b.attribute("lang", "zh").text("排序与查找 🔍 — Gödel") }
            }
            .build()
        saveXmlToFile(doc, tmp.path)
        let loaded = loadXmlFromFile(tmp.path)
        let root = loaded.rootElement.getOrThrow()
        @Expect(root.name, "doc")
        let book = root.requiredChildElement("book")
        @Expect(book.attribute("lang").getOrThrow(), "zh")
        @Expect(book.textContent(), "排序与查找 🔍 — Gödel")
    } finally {
        tmp.cleanup()
    }
}

// ======================================================================
// 错误路径
// ======================================================================

@Test
func testLoadNonexistentFileThrowsFileNotFound(): Unit {
    try {
        loadXmlFromFile("${TMP_ROOT}/does_not_exist_xyz.xml")
        @Fail("expected XmlIoException")
    } catch (e: XmlIoException) {
        match (e.error) {
            case FileNotFound(_) => ()
            case _ => @Fail("expected FileNotFound, got ${e.error}")
        }
    }
}

@Test
func testParseBytesWithInvalidUtf8(): Unit {
    // 0xFF 不是合法 UTF-8 起始字节
    let bytes: Array<Byte> = [0xFFu8, 0xFEu8, 0x00u8]
    try {
        parseXmlBytes(bytes)
        @Fail("expected XmlIoException")
    } catch (e: XmlIoException) {
        match (e.error) {
            case FileReadFailed(src, _) => @Expect(src, "<bytes>")
            case _ => @Fail("expected FileReadFailed, got ${e.error}")
        }
    }
}

@Test
func testSyntaxErrorPropagatesAsParseException(): Unit {
    let tmp = TempFile("bad.xml")
    try {
        File.writeTo(Path(tmp.path), "<open></close>".toArray())
        try {
            loadXmlFromFile(tmp.path)
            @Fail("expected XmlParseException")
        } catch (e: XmlParseException) {
            match (e.error) {
                case MismatchedElement(_, _, _) => ()
                case _ => @Fail("unexpected error: ${e.error}")
            }
        }
    } finally {
        tmp.cleanup()
    }
}

// ======================================================================
// FileXmlSink 流式写
// ======================================================================

@Test
func testFileXmlSinkStreamsIdenticalContent(): Unit {
    let tmp = TempFile("stream.xml")
    try {
        let doc = makeSampleDoc()
        let options = XmlWriteOptions.default_()
        try (sink = FileXmlSink(tmp.path)) {
            let w = XmlWriter(sink, options: options)
            w.writeDocument(doc)
        }
        // 与 StringXmlSink 路径得到的字节完全一致
        let bytesViaStream = File.readFrom(Path(tmp.path))
        let bytesViaString = writeXmlToBytes(doc, options)
        @Expect(String.fromUtf8(bytesViaStream), String.fromUtf8(bytesViaString))
    } finally {
        tmp.cleanup()
    }
}

@Test
func testFileXmlSinkWriteAfterCloseThrows(): Unit {
    let tmp = TempFile("closed.xml")
    try {
        let sink = FileXmlSink(tmp.path)
        sink.write("<r/>")
        sink.close()
        @Expect(sink.isClosed(), true)
        try {
            sink.write("late")
            @Fail("expected XmlIoException on write after close")
        } catch (_: XmlIoException) {
            ()  // 预期
        }
    } finally {
        tmp.cleanup()
    }
}

@Test
func testFileXmlSinkOnUnwritablePathThrows(): Unit {
    // 不存在的目录 → File(Write) 构造应失败并被映射为 XmlIoException
    let bad = "${TMP_ROOT}/no_such_dir/file.xml"
    try {
        let s = FileXmlSink(bad)
        s.close()
        @Fail("expected XmlIoException")
    } catch (_: XmlIoException) {
        ()
    }
}

// ======================================================================
// 端到端联动：build → save → load → query
// ======================================================================

@Test
func testEndToEndBuildSaveLoadQuery(): Unit {
    let tmp = TempFile("e2e.xml")
    try {
        let doc = XmlDocumentBuilder()
            .declaration()
            .root("library") { r =>
                r.element("book") { b =>
                    b.attribute("id", "42").attribute("avail", "true").text("Gödel, Escher, Bach")
                }
            }
            .build()
        saveXmlToFile(doc, tmp.path)

        let back = loadXmlFromFile(tmp.path)
        let book = back.rootElement.getOrThrow().requiredChildElement("book")
        @Expect(book.intAttribute("id").getOrThrow(), 42)
        @Expect(book.boolAttribute("avail").getOrThrow(), true)
        @Expect(book.textContent(), "Gödel, Escher, Bach")
    } finally {
        tmp.cleanup()
    }
}

// ======================================================================
// close 幂等 / 空字节解析 / saveXmlToFile 失败不留半写入文件。
// ======================================================================

@Test
func testFileXmlSinkCloseIsIdempotent(): Unit {
    let tmp = TempFile("close_idempotent.xml")
    try {
        let sink = FileXmlSink(tmp.path)
        sink.write("<r/>")
        sink.close()
        @Expect(sink.isClosed(), true)
        // 第二次 close 不应抛，也不应复活句柄。
        sink.close()
        @Expect(sink.isClosed(), true)
        // 文件内容仍然只有一次写入的结果。
        let content = String.fromUtf8(File.readFrom(Path(tmp.path)))
        @Expect(content, "<r/>")
    } finally {
        tmp.cleanup()
    }
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
    // `saveXmlToFile` 通过"先序列化到内存字节，再一次性写盘"的设计天然
    // 规避了"部分写入"。此测试钉死这条设计：对一份合法 doc，若目标路径
    // 所在目录不存在，我们应当抛 `XmlIoException`，并且不会创建任何副作用。
    let bogusDir = "/nonexistent_tinyxml2_dir_e7a3c/out.xml"
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

// ======================================================================
// 覆盖率补充：XmlIoException.getClassName / FileXmlSink 边界状态
// ======================================================================

@Test
func testXmlIoExceptionGetClassName(): Unit {
    let e = XmlIoException(FileReadFailed("x", "boom"))
    @Expect(e.getClassName(), "XmlIoException")
    // message 透传自 XmlError.toString()
    @Expect(e.message.contains("x"), true)
}

@Test
func testXmlIoExceptionWrapsErrorField(): Unit {
    let e = XmlIoException(FileNotFound("/nope"))
    match (e.error) {
        case FileNotFound(p) => @Expect(p, "/nope")
        case _ => @Fail("expected FileNotFound")
    }
}

@Test
func testFileXmlSinkFlushAfterCloseIsNoOp(): Unit {
    // close 之后再 flush 应为 no-op——不抛、不改状态。
    let tmp = TempFile("flush_after_close.xml")
    try {
        let sink = FileXmlSink(tmp.path)
        sink.write("<x/>")
        sink.close()
        sink.flush()  // 不应抛
        @Expect(sink.isClosed(), true)
    } finally {
        tmp.cleanup()
    }
}

@Test
func testFileXmlSinkExplicitFlushBeforeClose(): Unit {
    // 覆盖 flush() 的"未关闭"分支——主动调用时内容应进磁盘。
    let tmp = TempFile("flush_before_close.xml")
    try {
        let sink = FileXmlSink(tmp.path)
        sink.write("<y/>")
        sink.flush()
        sink.close()
        @Expect(String.fromUtf8(File.readFrom(Path(tmp.path))), "<y/>")
    } finally {
        tmp.cleanup()
    }
}

@Test
func testFileXmlSinkWriteAfterCloseRejected(): Unit {
    // 覆盖 write() 的 `closed` 分支：关闭后再写必须抛 XmlIoException。
    let tmp = TempFile("write_after_close.xml")
    try {
        let sink = FileXmlSink(tmp.path)
        sink.write("<r/>")
        sink.close()
        var threw = false
        try {
            sink.write("<after/>")
        } catch (e: XmlIoException) {
            if (let FileWriteFailed(_, _) <- e.error) { threw = true }
        }
        @Expect(threw, true)
    } finally {
        tmp.cleanup()
    }
}

@Test
func testFileXmlSinkConstructorFailureOnBadPath(): Unit {
    // 目标目录不存在 → 构造期捕获 FSException 映射为 XmlIoException
    var threw = false
    try {
        FileXmlSink("/nonexistent_tinyxml2_dir_9beef/out.xml")
    } catch (e: XmlIoException) {
        if (let FileWriteFailed(_, _) <- e.error) { threw = true }
    }
    @Expect(threw, true)
}

@Test
func testFileXmlSinkStreamsLargeDocument(): Unit {
    // 覆盖 flush() 的正常路径与 BufferedOutputStream 的真实写入分支。
    let tmp = TempFile("large.xml")
    try {
        try (sink = FileXmlSink(tmp.path)) {
            let w = XmlWriter(sink, options: XmlWriteOptions(writeDeclaration: false, compact: true))
            let doc = XmlDocument()
            let r = doc.createElement("root")
            doc.appendChild(r)
            var i = 0
            while (i < 50) {
                let e = doc.createElement("item")
                e.setAttribute("i", i.toString())
                r.appendChild(e)
                i++
            }
            w.writeDocument(doc)
        }
        let content = String.fromUtf8(File.readFrom(Path(tmp.path)))
        @Expect(content.contains("<item i=\"0\"/>"), true)
        @Expect(content.contains("<item i=\"49\"/>"), true)
    } finally {
        tmp.cleanup()
    }
}

@Test
func testParseXmlBytesInvalidUtf8(): Unit {
    // 覆盖 decodeUtf8 的异常分支：0xFF 单字节不是合法 UTF-8 起始序列。
    let bogus: Array<Byte> = [0xFFu8, 0xFEu8, 0x00u8]
    var threw = false
    try {
        parseXmlBytes(bogus)
    } catch (e: XmlIoException) {
        if (let FileReadFailed(source, _) <- e.error) {
            threw = (source == "<bytes>")
        }
    }
    @Expect(threw, true)
}

@Test
func testLoadXmlFromFileInvalidUtf8(): Unit {
    // 文件中含非法 UTF-8 字节——应映射为 XmlIoException(FileReadFailed(path, ...))
    let tmp = TempFile("bad_utf8.xml")
    try {
        let sink = FileXmlSink(tmp.path)
        sink.close()
        // 直接用 std.fs 覆写为非法字节
        File.writeTo(Path(tmp.path), [0xC3u8, 0x28u8])
        var threw = false
        try {
            loadXmlFromFile(tmp.path)
        } catch (e: XmlIoException) {
            if (let FileReadFailed(_, _) <- e.error) { threw = true }
        }
        @Expect(threw, true)
    } finally {
        tmp.cleanup()
    }
}
