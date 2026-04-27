package xlsx_to_csv

import std.collection.*
import fastxml.dom.*
import fastxml.io.*

/**
 * `sheetN.xml` 的内存模型：二维 grid，按**原表格布局**保留行号 / 列号。
 *
 * - `rows` 按行号 1 起升序存储；表格中"空行"也会出现为一个空 `Row`
 *   ——这样后续生成 CSV 时就能保持与原表相同的行数。
 * - 每个 `Row` 又按列号 1 起存储；缺失列在 CSV 阶段以空串补齐。
 */
public class Sheet {
    public let rows: ArrayList<Row>
    public let maxColumn: Int64

    init(rows: ArrayList<Row>, maxColumn: Int64) {
        this.rows = rows
        this.maxColumn = maxColumn
    }
}

/** 单个 `<row>` 的内存表示。 */
public class Row {
    public let index: Int64                          // 1 起的行号
    public let cells: ArrayList<Cell>                // 按列号升序

    init(index: Int64, cells: ArrayList<Cell>) {
        this.index = index
        this.cells = cells
    }
}

/** 单元格的最终**展示值**——已经过共享字符串 / 内联字符串的解析，可直接下发 CSV。 */
public class Cell {
    public let column: Int64
    public let value: String

    init(column: Int64, value: String) {
        this.column = column
        this.value = value
    }
}

/**
 * 解析一个 sheet 文件。
 *
 * `sst` 来自 workbook 级 shared strings 表；无 shared strings 时上层可以传
 * 一个空表（`loadSharedStrings` 在文件缺失时本就返回空表）。
 *
 * ## OOXML 单元格类型简表
 *
 * `<c>` 的 `t` 属性决定值的来源：
 *
 * | t         | 含义                 | 取值来源                                 |
 * |-----------|----------------------|------------------------------------------|
 * | (缺省)    | 数值                 | `<v>数字</v>`                            |
 * | `n`       | 数值（显式）         | `<v>数字</v>`                            |
 * | `s`       | 共享字符串           | `<v>索引</v>` → `sst.get(索引)`          |
 * | `str`     | 公式的结果字符串     | `<v>字符串</v>`                          |
 * | `inlineStr`| 行内字符串           | `<is>` 下收集所有 `<t>` 文本            |
 * | `b`       | 布尔                 | `<v>0</v>` / `<v>1</v>` → "FALSE"/"TRUE" |
 * | `e`       | 错误                 | `<v>#REF!</v>` 等错误码原样              |
 * | `d`       | 日期（ISO-8601）     | `<v>2012-07-02</v>`                      |
 *
 * 本项目不做数字格式化（如 `styles.xml` 里的日期序列号 → "2012/7/2"）——那
 * 是 Excel 渲染层的事，xlsx 原始值本身已经是字符串 / 数字，按源值下发能让
 * CSV 忠实反映 xlsx 数据层。
 */
public func loadSheet(path: String, sst: SharedStrings): Sheet {
    let doc = loadXmlFromFile(path)
    let root = doc.rootElement.getOrThrow()

    let rows = ArrayList<Row>()
    var maxCol: Int64 = 0

    // `<dimension ref="A1:M87"/>`：OOXML 写入端给出的"整表外包盒"。用它做 maxCol
    // 的下限能把"只有样式、没有值"的尾列也保留到 CSV 里，更忠实还原原表布局。
    match (root.firstChildElement(name: Some("dimension"))) {
        case None => ()
        case Some(dim) =>
            match (maxColFromDimensionRef(dim.attribute("ref") ?? "")) {
                case None => ()
                case Some(c) => maxCol = c
            }
    }

    // <worksheet><sheetData><row r="1">...</row>...</sheetData></worksheet>
    match (root.firstChildElement(name: Some("sheetData"))) {
        case None => ()                              // 空 sheet
        case Some(sheetData) =>
            for (rowEl in sheetData.childElements(name: Some("row"))) {
                let r = parseRow(rowEl, sst)
                if (r.cells.size > 0) {
                    let last = r.cells[r.cells.size - 1].column
                    if (last > maxCol) { maxCol = last }
                }
                rows.add(r)
            }
    }
    Sheet(rows, maxCol)
}

/**
 * 从 `<dimension ref="...">` 的取值里抽出最大列号。
 *
 * 合法形式：
 *
 * - `A1` （单格）→ 最大列 = 1
 * - `A1:M87` （矩形范围）→ 最大列 = 13
 *
 * 非法 / 空串返回 `None`，上层回退到"按数据单元计算"。
 */
func maxColFromDimensionRef(ref: String): ?Int64 {
    if (ref.size == 0) { return None }
    // 取 `:` 右侧（没有冒号就用整串）
    let parts = ref.split(":")
    let rhs = parts[parts.size - 1]
    match (parseCellRef(rhs)) {
        case None => None
        case Some((c, _)) => Some(c)
    }
}

/** 解析单个 `<row>` 元素。 */
func parseRow(rowEl: XmlElement, sst: SharedStrings): Row {
    let idx = parseRowIndex(rowEl)
    let cells = ArrayList<Cell>()
    for (cEl in rowEl.childElements(name: Some("c"))) {
        match (parseCell(cEl, sst)) {
            case None => ()
            case Some(c) => cells.add(c)
        }
    }
    Row(idx, cells)
}

/**
 * 尝试从 `<row r="...">` 里读行号；没有 `r` 属性时退化为**按出现顺序** +1
 * ——OOXML 规范允许省略（被视为"紧跟上一行"），这里不算错误。
 *
 * 为了简单起见，我们只在有 `r` 时严格解析；没有时回退到 0 并由上层用
 * 出现顺序补齐不在本函数职责内；当前所有 WPS / Excel 主流导出都写 `r`，
 * 遇到省略的样本再加增强。
 */
func parseRowIndex(rowEl: XmlElement): Int64 {
    match (rowEl.attribute("r")) {
        case None => 0
        case Some(s) =>
            var n: Int64 = 0
            for (b in s.toArray()) {
                if (b >= b'0' && b <= b'9') {
                    n = n * 10 + Int64(b - b'0')
                } else {
                    return 0
                }
            }
            n
    }
}

/**
 * 解析单个 `<c>` 元素。
 *
 * 空单元格（无 `<v>` 也无 `<is>`）返回 `None`——CSV 阶段会自动按列号用空串
 * 补位，把这些全空单元格留在 grid 里没有额外意义。
 */
func parseCell(cEl: XmlElement, sst: SharedStrings): ?Cell {
    let refAttr = cEl.attribute("r") ?? ""
    let col = match (parseCellRef(refAttr)) {
        case Some((c, _)) => c
        case None =>
            // 未带 r 属性（极少见，某些轻量导出工具有此行为）。
            // 本项目不支持该退化路径——告诉上层跳过；交给空列补位。
            return None
    }

    let ty = cEl.attribute("t") ?? "n"
    let raw = readCellRawValue(cEl, ty)
    match (raw) {
        case None => None
        case Some(s) =>
            let finalValue = decodeCellValue(ty, s, sst)
            Some(Cell(col, finalValue))
    }
}

/**
 * 读取 `<c>` 的"原始值"——对大多数类型就是 `<v>` 的文本内容；对 `inlineStr`
 * 是 `<is>` 下所有 `<t>` 拼接。找不到任何值时返回 `None`。
 */
func readCellRawValue(cEl: XmlElement, ty: String): ?String {
    if (ty == "inlineStr") {
        match (cEl.firstChildElement(name: Some("is"))) {
            case None => return None
            case Some(isEl) =>
                let sb = StringBuilder()
                collectTextNodes(isEl, sb)
                return Some(sb.toString())
        }
    }
    match (cEl.firstChildElement(name: Some("v"))) {
        case None => None
        case Some(v) => Some(v.textContent())
    }
}

/** 按单元格类型把 `<v>` 原值翻译成可写入 CSV 的最终字符串。 */
func decodeCellValue(ty: String, raw: String, sst: SharedStrings): String {
    if (ty == "s") {
        return sst.get(parseNonNegativeInt(raw))
    }
    if (ty == "b") {
        return if (raw == "1") { "TRUE" } else { "FALSE" }
    }
    // n / str / e / d / inlineStr 以及未知类型：按字面字符串输出
    raw
}

/**
 * 宽松的非负整数解析——用于把 `<v>` 里的共享字符串索引变成 `Int64`。
 *
 * 故意不抛异常：如果内容不是数字，返回 0 会命中 `sst.get(0)`——要么是合理
 * 的第一条字符串，要么是空串（空表时）。CSV 不会因此爆炸，这正是"尽量多
 * 输出已知数据"的哲学。
 */
func parseNonNegativeInt(s: String): Int64 {
    var n: Int64 = 0
    for (b in s.toArray()) {
        if (b >= b'0' && b <= b'9') {
            n = n * 10 + Int64(b - b'0')
        } else {
            return 0
        }
    }
    n
}
