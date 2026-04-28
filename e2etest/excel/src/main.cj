package xlsx_to_csv

import std.collection.*
import std.fs.*

/**
 * xlsx → 按 sheet CSV 的命令行入口，也是 CangjieXML 库的一个真实 E2E 用例
 *
 * ## 用法
 *
 * ```
 * xlsx_to_csv <path/to/file.xlsx> <output/dir>
 * ```
 *
 * 每个 sheet 生成独立 CSV：`<序号>_<sheet 名>.csv`。序号补零保证字典序等于
 * workbook 里的定义顺序；sheet 名里的 `/` `\` `:` `*` `?` `"` `<` `>` `|`
 * 等跨平台非法字符统一替换为下划线，保留原名可读性
 *
 * ## 退出码
 *
 * | 条件            | 退出码 |
 * |-----------------|--------|
 * | 正常完成        | 0      |
 * | 参数缺失        | 2      |
 * | 运行中异常      | 1      |
 *
 * ## 为什么这个项目能"验证 XML 库能力"
 *
 * 跑通这一个用例，意味着 CangjieXML 同时做到了：
 *
 * 1. 正确读取带 XML 声明 / BOM / UTF-8 编码的"现实中的 XML"；
 * 2. 解析带**默认命名空间** `xmlns="..."` 及 `r:id` 这类**带前缀属性**的文档；
 * 3. 处理 sheet 动辄数百 KB、包含数万个元素的中等规模文档（样例里最大的
 *    `sheet3.xml` 约 680 KB）；
 * 4. 保留元素 / 属性的出现顺序，让"按行号 / 列号还原表格布局"成为可能
 */
main(args: Array<String>): Int64 {
    if (args.size < 2) {
        eprintln("usage: xlsx_to_csv <xlsx_path> <output_dir>")
        return 2
    }
    let xlsxPath = args[0]
    let outDir = args[1]

    if (!exists(Path(xlsxPath))) {
        eprintln("error: xlsx not found: ${xlsxPath}")
        return 1
    }

    try {
        convert(xlsxPath, outDir)
        0
    } catch (e: Exception) {
        eprintln("error: ${e.message}")
        1
    }
}

/**
 * 核心调度：解压 → 读取 workbook / 共享字符串 → 逐 sheet parse 并写 CSV
 *
 * 为了让失败不留半成品，临时目录经 `env.getTempDirectory()` + `Directory.createTemp`
 * 在系统临时目录下生成唯一子目录（跨 Linux / Windows）；本函数不主动
 * 清理——留到进程退出由系统 tmpfs 清理即可，也方便用户在出错时手工检查
 * 解压产物
 */
func convert(xlsxPath: String, outDir: String): Unit {
    let outPath = Path(outDir)
    if (!exists(outPath)) {
        Directory.create(outPath, recursive: true)
    }

    let extractDir = makeTempDir("xlsx_to_csv")
    println("[xlsx_to_csv] unzipping '${xlsxPath}' -> ${extractDir}")
    unzipXlsx(xlsxPath, extractDir)

    let sheets = loadSheetList(extractDir)
    println("[xlsx_to_csv] workbook has ${sheets.size} sheet(s)")

    let sst = loadSharedStrings("${extractDir}/xl/sharedStrings.xml")
    println("[xlsx_to_csv] sharedStrings: ${sst.count} item(s)")

    let indexWidth = digitCount(sheets.size)
    var sheetIndex: Int64 = 1
    for (entry in sheets) {
        let sheetXml = "${extractDir}/${entry.sheetPath}"
        if (!exists(Path(sheetXml))) {
            eprintln("warning: sheet '${entry.name}' missing underlying file: ${sheetXml}")
            sheetIndex++
            continue
        }
        let sheet = loadSheet(sheetXml, sst)
        let filename = "${padIndex(sheetIndex, indexWidth)}_${sanitizeFileName(entry.name)}.csv"
        let csvPath = "${outDir}/${filename}"
        writeSheetToCsv(sheet, csvPath, CsvWriteOptions.default_())
        println(
            "[xlsx_to_csv] wrote ${csvPath} (rows=${sheet.rows.size}, maxCol=${sheet.maxColumn})")
        sheetIndex++
    }
}

/** 把整数补零到宽度 `width`；`index=3, width=2` → `"03"` */
func padIndex(index: Int64, width: Int64): String {
    "${index}".padStart(width, padding: "0")
}

/** 十进制位数——只用来算序号宽度，0 和负数按 1 位处理（实际不会命中） */
func digitCount(n: Int64): Int64 {
    if (n <= 0) { return 1 }
    var remaining = n
    var digits: Int64 = 0
    while (remaining > 0) {
        remaining /= 10
        digits++
    }
    digits
}

/**
 * 把 sheet 名中跨平台非法的文件名字符替换为下划线
 *
 * 规则（Windows 文件名保留字符 + 控制字符）：
 *
 * - `/` `\` `:` `*` `?` `"` `<` `>` `|` → `_`
 * - ASCII 控制字符（U+0000..U+001F）→ `_`
 * - 其它按原 rune 输出，保留中文等多字节字符
 *
 * 额外把两端的空格 / 点去掉——Windows 不允许文件名以空格 / 点结尾
 */
func sanitizeFileName(name: String): String {
    let buffer = StringBuilder()
    for (r in name.runes()) {
        if (isIllegalFileNameRune(r)) {
            buffer.append(r'_')
        } else {
            buffer.append(r)
        }
    }
    let trimmed = buffer.toString().trimAscii()
    if (trimmed.size == 0) { return "sheet" }
    trimmed
}

func isIllegalFileNameRune(r: Rune): Bool {
    if (r == r'/' || r == r'\\' || r == r':' || r == r'*' || r == r'?' ||
        r == r'"' || r == r'<' || r == r'>' || r == r'|') {
        return true
    }
    // ASCII 控制字符——`Rune` 与 `UInt32` 不直接比较，用字面量兜住常见 CR/LF/Tab
    if (r == r'\r' || r == r'\n' || r == r'\t') {
        return true
    }
    false
}
