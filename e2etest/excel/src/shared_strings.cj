package xlsx_to_csv

import std.collection.*
import std.fs.*
import tinyxml2.dom.*
import tinyxml2.io.*

/**
 * 把 `xl/sharedStrings.xml` 整体装进内存，返回按索引访问的字符串表。
 *
 * ## 结构
 *
 * ```xml
 * <sst count="..." uniqueCount="...">
 *   <si><t>单段文本</t></si>
 *   <si>                                   <!-- rich text: 多段 <r><t>...</t></r> 拼接 -->
 *     <r><rPr>...</rPr><t>前缀</t></r>
 *     <r><rPr>...</rPr><t>后缀</t></r>
 *   </si>
 * </sst>
 * ```
 *
 * 每个 `<si>` 的"显示值"是它**所有后代 `<t>` 文本的拼接**——格式化信息
 * (`<rPr>` 字体 / 颜色)对 CSV 输出没有意义，直接丢弃。
 *
 * 小文件可以直接加载；大文件（本仓库样例的 `sharedStrings.xml` 才 ~47KB，
 * 属于绰绰有余的量级）也一样整体加载，避免引入分段解析的复杂度——这层
 * 复杂度只有百万级 unique strings 的巨型 xlsx 才会出现。
 */
public class SharedStrings {
    private let items: ArrayList<String>

    init(items: ArrayList<String>) {
        this.items = items
    }

    /** 条目总数——用来在上层校验索引越界时给出清晰的错误信息。 */
    public prop count: Int64 {
        get() { items.size }
    }

    /**
     * 取索引为 `i` 的字符串；越界返回空串（与 LibreOffice / Excel 的"悄悄降级"
     * 行为一致——一条损坏引用不应导致整张表导不出）。
     */
    public func get(i: Int64): String {
        if (i < 0 || i >= items.size) {
            return ""
        }
        items[i]
    }
}

/**
 * 解析 `sharedStrings.xml`；文件不存在时返回空表。
 *
 * 并不是所有 xlsx 都有 `sharedStrings.xml`——如果所有单元格都是数字 /
 * 内联字符串，这个文件会被省略。空表语义让上层无须做额外判空。
 */
public func loadSharedStrings(path: String): SharedStrings {
    let items = ArrayList<String>()
    if (!exists(Path(path))) {
        return SharedStrings(items)
    }
    let doc = loadXmlFromFile(path)
    let root = doc.rootElement.getOrThrow()
    for (si in root.childElements(name: Some("si"))) {
        items.add(collectTextInSi(si))
    }
    SharedStrings(items)
}

/**
 * 递归收集 `<si>` 下所有 `<t>` 节点的文本，忽略其它结构（`<rPr>` / `<phoneticPr>`
 * 等装饰），拼成字符串返回。
 *
 * 实现上走最朴素的 DFS；层数不会深，性能够用。专门写死"只关心 `<t>`"而不是
 * 用 `textContent()`，是因为 `<rPr>` / 语音节点里的文本（如注音）不应出现在
 * 主文本流里。
 */
func collectTextInSi(si: XmlElement): String {
    let sb = StringBuilder()
    collectTextNodes(si, sb)
    sb.toString()
}

func collectTextNodes(el: XmlElement, sb: StringBuilder): Unit {
    for (child in el.childNodes()) {
        match (child.kind()) {
            case Element(e) where e.name == "t" =>
                // <t> 本身只有文本子节点——用 textContent 拿整段字符即可，免得再递归一层
                sb.append(e.textContent())
            case Element(e) =>
                collectTextNodes(e, sb)
            case _ => ()
        }
    }
}
