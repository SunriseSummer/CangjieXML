package xlsx_to_csv

import std.collection.*
import fastxml.dom.*
import fastxml.io.*

/**
 * 从 workbook 里读取 sheet 列表（名称 + 实际路径），顺序严格按 `<sheets>` 子
 * 元素在 `xl/workbook.xml` 中出现的先后
 *
 * 形状：
 *
 * ```xml
 * <sheet name="封面"       sheetId="35" r:id="rId1"/>
 * <sheet name="钢管材料清单" sheetId="41" r:id="rId2"/>
 * ```
 *
 * 再结合 `xl/_rels/workbook.xml.rels` 里 `Id -> Target` 的映射，就能把 sheet
 * 名对应到 `xl/worksheets/sheetN.xml`
 */
public struct SheetEntry {
    public let name: String
    public let sheetPath: String        // 已规范化的绝对 xml 内部路径，例如 "xl/worksheets/sheet1.xml"

    public init(name: String, sheetPath: String) {
        this.name = name
        this.sheetPath = sheetPath
    }
}

/**
 * 读取 workbook 下所有 sheet（按 `<sheets>` 出现顺序）
 *
 * `unzipRoot` 是解压 xlsx 的根目录，函数内部负责拼 `xl/workbook.xml` 与
 * `xl/_rels/workbook.xml.rels` 两个路径
 */
public func loadSheetList(unzipRoot: String): ArrayList<SheetEntry> {
    let workbookXml = "${unzipRoot}/xl/workbook.xml"
    let relsXml = "${unzipRoot}/xl/_rels/workbook.xml.rels"

    let relMap = loadRelationshipMap(relsXml)

    let doc = loadXmlFromFile(workbookXml)
    let root = doc.rootElement.getOrThrow()
    let entries = ArrayList<SheetEntry>()

    // <workbook><sheets><sheet .../></sheets></workbook>
    let sheetsEl = root.firstChildElement(name: Some("sheets"))
    match (sheetsEl) {
        case None => throw Exception("workbook.xml has no <sheets> element")
        case Some(s) =>
            for (sheet in s.childElements(name: Some("sheet"))) {
                let name = sheet.attribute("name") ?? ""
                let rid = sheet.attribute("r:id") ?? ""
                let target = relMap.get(rid) ?? ""
                if (target == "") {
                    throw Exception(
                        "sheet '${name}' has unresolved r:id='${rid}' in workbook relationships")
                }
                entries.add(SheetEntry(name, normalizeRelTarget(target)))
            }
    }
    entries
}

/**
 * 读取 `xl/_rels/workbook.xml.rels` 并构造 `Id -> Target` 映射
 *
 * relationships 文件的形状：
 *
 * ```xml
 * <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
 *   <Relationship Id="rId1" Type="..." Target="worksheets/sheet1.xml"/>
 *   ...
 * </Relationships>
 * ```
 */
func loadRelationshipMap(path: String): HashMap<String, String> {
    let map = HashMap<String, String>()
    let doc = loadXmlFromFile(path)
    let root = doc.rootElement.getOrThrow()
    for (rel in root.childElements(name: Some("Relationship"))) {
        let id = rel.attribute("Id") ?? ""
        let target = rel.attribute("Target") ?? ""
        if (id != "" && target != "") {
            map.add(id, target)
        }
    }
    map
}

/**
 * 把 rels 里 `Target` 字段（相对 `xl/` 根的路径）归一成"相对 xlsx 顶层根"的
 * 路径——我们在 `unzipRoot` 下按"顶层根"寻址
 *
 * 规则：
 *
 * - 以 `/` 开头 → 已是绝对内部路径，去掉前导 `/`；
 * - 否则视为相对 `xl/`（workbook.xml 所在目录），补上前缀
 *
 * 不再做 `..` 展开——OOXML 文档里不会出现跨目录回退，简单判定足矣
 */
func normalizeRelTarget(target: String): String {
    if (target.startsWith("/")) {
        // `split("/", removeEmpty: false)` 会把前导 `/` 产出一个空段，丢掉它
        // 再用 `/` 重新拼回；String 没有稳定的 `[start..]` 字节切片，这是最干
        // 净的便携写法
        let parts = target.split("/", removeEmpty: false)
        let sb = StringBuilder()
        var first = true
        var idx = 0
        for (p in parts) {
            if (idx == 0) { idx++; continue }         // 跳过前导 `/` 产生的空段
            if (!first) { sb.append("/") }
            first = false
            sb.append(p)
            idx++
        }
        return sb.toString()
    }
    "xl/${target}"
}
