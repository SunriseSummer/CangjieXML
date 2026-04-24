package cangjie_probe

import std.collection.*
import std.fs.*
import std.sort.*

/**
 * e2e probe 主入口：读取 fixtures 目录、用 cangjie_xml 解析每个 `.xml`、
 * 生成与 Python 端一致的指纹 JSON。
 *
 * 用法：`cangjie_probe <fixtures_dir> <out_path>`
 */
main(args: Array<String>): Int64 {
    if (args.size < 2) {
        println("usage: cangjie_probe <fixtures_dir> <out_path>")
        return 2
    }
    let fixturesDir = args[0]
    let outPath = args[1]

    let files = listXmlFiles(fixturesDir)
    let json = StringBuilder()
    json.append("{\n")
    var first = true
    for (f in files) {
        if (!first) { json.append(",\n") }
        first = false
        writeFileFingerprint(json, fixturesDir, f)
    }
    json.append("\n}\n")

    File.writeTo(Path(outPath), json.toString().toArray())
    println("[cangjie_probe] wrote ${outPath} (${files.size} files)")
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
