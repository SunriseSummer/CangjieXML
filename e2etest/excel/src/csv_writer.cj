package xlsx_to_csv

import std.collection.*
import std.fs.*

/**
 * 把 `Sheet` 写成 RFC 4180 兼容的 CSV 文件。
 *
 * ## 契约
 *
 * - 输出文件总是 UTF-8；为了让多数 Windows / Mac 的 Excel 正确识别中文，
 *   默认在文件开头写 **UTF-8 BOM**（`EF BB BF`）。可以通过 `writeBom=false`
 *   关闭。
 * - 行分隔固定 `\r\n`——这是 RFC 4180 硬性要求；`\n` 在某些 Excel 版本里会
 *   被解读为"CSV 内字段换行"。
 * - 字段包含 `,` / `"` / CR / LF 时整体用 `"..."` 包裹，内部 `"` 转 `""`。
 * - **保留原表格布局**：从 1 行开始连续输出到最大行号；中间缺失行以全空列
 *   行填充。每行至少 `maxColumn` 列；更少的缺失列同样用空串补齐。
 */
public struct CsvWriteOptions {
    public let writeBom: Bool
    public let delimiter: Rune               // 支持未来切换为 `;`（欧洲 locale）

    public init(writeBom!: Bool = true, delimiter!: Rune = r',') {
        this.writeBom = writeBom
        this.delimiter = delimiter
    }

    public static func default_(): CsvWriteOptions { CsvWriteOptions() }
}

/** 把 `Sheet` 序列化为字节串——便于上层选择落盘路径或直接打印。 */
public func sheetToCsvBytes(sheet: Sheet, options: CsvWriteOptions): Array<Byte> {
    let sb = StringBuilder()
    if (options.writeBom) {
        // UTF-8 BOM：先用代码点 U+FEFF 追加进字符串，随后 toUtf8 自动展开为 EF BB BF
        sb.append("\u{FEFF}")
    }

    let maxCol = sheet.maxColumn
    var expected: Int64 = 1
    for (row in sheet.rows) {
        // 保留原表格布局：中间缺失的行号也要占位
        while (expected < row.index) {
            writeEmptyRow(sb, maxCol, options.delimiter)
            expected++
        }
        writeRow(sb, row, maxCol, options.delimiter)
        expected++
    }

    sb.toString().toArray()
}

/** 直接落盘；调用方需确保父目录已存在。 */
public func writeSheetToCsv(sheet: Sheet, path: String, options: CsvWriteOptions): Unit {
    File.writeTo(Path(path), sheetToCsvBytes(sheet, options))
}

/** 写一整行。至少输出 `maxCol` 列，缺失列以空串补位。 */
func writeRow(sb: StringBuilder, row: Row, maxCol: Int64, delim: Rune): Unit {
    var col: Int64 = 1
    var i: Int64 = 0
    var first = true
    while (col <= maxCol) {
        if (!first) { sb.append(delim) }
        first = false
        if (i < row.cells.size && row.cells[i].column == col) {
            appendCsvField(sb, row.cells[i].value, delim)
            i++
        }
        // 若当前单元格的 column > col，说明这列是空——无需写任何内容
        col++
    }
    sb.append("\r\n")
}

/** 写一整行空占位行（仅行终止符 + `maxCol - 1` 个分隔符）。 */
func writeEmptyRow(sb: StringBuilder, maxCol: Int64, delim: Rune): Unit {
    var col: Int64 = 1
    while (col < maxCol) {
        sb.append(delim)
        col++
    }
    sb.append("\r\n")
}

/**
 * CSV 字段级转义。
 *
 * 需要引用的场景（RFC 4180 §2.6 / §2.7）：
 *
 * - 字段含分隔符；
 * - 字段含双引号；
 * - 字段含 CR 或 LF。
 *
 * 未命中则直接写原值——"快路径"省掉一次新字符串分配。
 */
func appendCsvField(sb: StringBuilder, value: String, delim: Rune): Unit {
    if (!needsQuote(value, delim)) {
        sb.append(value)
        return
    }
    sb.append(r'"')
    for (r in value.runes()) {
        if (r == r'"') {
            sb.append("\"\"")
        } else {
            sb.append(r)
        }
    }
    sb.append(r'"')
}

func needsQuote(value: String, delim: Rune): Bool {
    for (r in value.runes()) {
        if (r == delim || r == r'"' || r == r'\r' || r == r'\n') {
            return true
        }
    }
    false
}
