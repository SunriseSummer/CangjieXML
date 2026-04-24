/*
 * XmlParser 单元测试：共享辅助函数。
 *
 * 实际测试按主题拆分到同包的多个文件：
 *   - `xml_parser_test.cj`            — 文档骨架 / XML 声明
 *   - `xml_parser_attrs_test.cj`      — 属性聚合 / 重复 / 实体展开
 *   - `xml_parser_ns_test.cj`         — 命名空间绑定 / xml / xmlns 硬约束
 *   - `xml_parser_text_test.cj`       — Characters / CDATA / Comment / PI / DOCTYPE
 *   - `xml_parser_options_test.cj`    — ParserOptions 各开关
 *   - `xml_parser_edge_test.cj`       — 边界 & QName 扩展名冲突
 */
package cangjie_xml.parser

import std.collection.*

/** 把 `XmlParser` 的整个事件流收集为列表（到 EndDocument / ParseError 截止）。 */
func events(s: String, opts!: ParserOptions = ParserOptions()): ArrayList<SaxEvent> {
    let p = XmlParser.fromString(s, opts: opts)
    let acc = ArrayList<SaxEvent>()
    while (true) {
        match (p.next()) {
            case Some(e) =>
                acc.add(e)
                match (e) {
                    case EndDocument(_) => return acc
                    case ParseError(_) => return acc
                    case _ => ()
                }
            case None => return acc
        }
    }
    return acc
}

/** 事件种类的短字符串名，便于 `@Expect` 比对。 */
func kind(e: SaxEvent): String {
    match (e) {
        case StartDocument(_) => return "StartDocument"
        case EndDocument(_) => return "EndDocument"
        case StartElement(_, _, _, _) => return "StartElement"
        case EndElement(_, _) => return "EndElement"
        case Characters(_, _) => return "Characters"
        case Cdata(_, _) => return "Cdata"
        case CommentEvent(_, _) => return "CommentEvent"
        case Pi(_, _, _) => return "Pi"
        case Doctype(_, _) => return "Doctype"
        case EntityReference(_, _) => return "EntityReference"
        case ParseError(_) => return "ParseError"
    }
}
