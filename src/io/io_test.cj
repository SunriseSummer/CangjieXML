package cangjie_xml.io

import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import cangjie_xml.dom.*
import cangjie_xml.error.*
import cangjie_xml.parser.*
import cangjie_xml.writer.*
import cangjie_xml.build.*
import cangjie_xml.query.*

// ======================================================================
// 测试夹具
// ======================================================================

const TMP_ROOT: String = "/tmp/cangjie_xml_io_tests"

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
