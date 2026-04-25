package cangjie_xml.writer

/*
 * Writer 的语法片段常量与排版三态枚举。
 *
 * `DEFAULT_XML_DECLARATION_VALUE` 公开导出，供上层在合成默认声明时复用。
 */

public const DEFAULT_XML_DECLARATION_VALUE: String = "xml version=\"1.0\" encoding=\"UTF-8\""

const TAG_OPEN: String = "<"
const TAG_OPEN_SLASH: String = "</"
const TAG_CLOSE: String = ">"
const TAG_SELF_CLOSE: String = "/>"
const PI_OPEN: String = "<?"
const PI_CLOSE: String = "?>"
const COMMENT_OPEN: String = "<!--"
const COMMENT_CLOSE: String = "-->"
const UNKNOWN_OPEN: String = "<!"
const UNKNOWN_CLOSE: String = ">"
const ATTR_EQUALS_QUOTE: String = "=\""
const ATTR_CLOSE_QUOTE: String = "\""
const ATTR_SPACE: String = " "

/** 元素排版三态：自闭合 / 内联 / 块级。 */
enum ElementLayout {
    | SelfClosing
    | Inline
    | Block
}
