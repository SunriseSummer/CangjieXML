package cangjie_probe

import std.collection.*
import std.fs.*
import std.sort.*

/**
 * e2e probe 主入口：读取 fixtures 目录、按 `--mode` 以对应流水线在仓颉侧处理每个
 * `.xml`、生成与 Python 端一致的指纹 JSON
 *
 * ## 模式
 *
 * - `parse`（默认）：读文件 → `loadXmlFromFile` → 指纹。覆盖 Parser + IO
 * - `roundtrip-pretty`：读 → parse → 以默认（pretty）选项 write → 再 parse → 指纹
 *   覆盖 Writer 默认排版 + 与 Parser 的往返一致性。写出的缩进 / 换行不应改变
 *   指纹，因为 `normalizeWhitespace` 会吞掉"仅空白"的 direct text
 * - `roundtrip-compact`：读 → parse → 以 compact 选项 write → 再 parse → 指纹
 *   额外覆盖 compact 模式下空元素 / 文本 inline 的写出路径
 * - `builder`：不读 fixture 文件——而是用 `XmlDocumentBuilder` 在仓颉侧**构造**
 *   与 `01_bookstore.xml` 等价的文档 → write → 再 parse → 指纹
 *   与 Python 对 `01_bookstore.xml` 的指纹严格一致才能通过。覆盖 Builder + DOM
 *
 * - `bytes`：把每个 fixture 读为字节 → `parseXmlBytes` → 走 `writeXmlToBytes` 再
 *   `parseXmlBytes` → 指纹。覆盖 `io.parseXmlBytes` + `io.writeXmlToBytes` 的
 *   字节级往返路径（与 `parse` 模式互补——后者走 `loadXmlFromFile`）
 *
 * 用法：`cangjie_probe <mode> <fixtures_dir> <out_path>`
 */
main(args: Array<String>): Int64 {
    if (args.size < 3) {
        println("usage: cangjie_probe <mode> <fixtures_dir> <out_path>")
        println("  modes: parse | roundtrip-pretty | roundtrip-compact | builder | bytes")
        return 2
    }
    let mode = args[0]
    let fixturesDir = args[1]
    let outPath = args[2]

    let json = match (mode) {
        case "parse"              => renderAllFixtures(fixturesDir, ModeParse)
        case "roundtrip-pretty"   => renderAllFixtures(fixturesDir, ModeRoundTripPretty)
        case "roundtrip-compact"  => renderAllFixtures(fixturesDir, ModeRoundTripCompact)
        case "bytes"              => renderAllFixtures(fixturesDir, ModeBytesRoundTrip)
        case "builder"            => renderBuilderFixtures()
        case _ =>
            println("error: unknown mode '${mode}'")
            return 2
    }

    File.writeTo(Path(outPath), json.toArray())
    println("[cangjie_probe:${mode}] wrote ${outPath}")
    0
}

/** 按文件名字典序列出 fixtures 目录里的所有 `.xml`。 */
func listXmlFiles(dir: String): ArrayList<String> {
    let infos = Directory.readFrom(Path(dir))
    let names = ArrayList<String>()
    for (info in infos) {
        let name = info.name
        if (name.endsWith(".xml")) {
            names.add(name)
        }
    }
    sort<String>(names)
    names
}

/** 遍历所有 fixture，按指定模式生成合并 JSON 对象。 */
func renderAllFixtures(dir: String, mode: ProbeMode): String {
    let files = listXmlFiles(dir)
    let json = StringBuilder()
    json.append("{\n")
    var first = true
    for (f in files) {
        if (!first) { json.append(",\n") }
        first = false
        writeFileFingerprint(json, dir, f, mode)
    }
    json.append("\n}\n")
    json.toString()
}

