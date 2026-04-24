package cangjie_xml.dom

/**
 * XML 节点种类。
 *
 * 这是模式匹配的入口：在公共 API 中，我们不提供 tinyxml2 的 `ToElement()` / `ToText()`
 * 风格向下转型函数，而是让调用方直接 `match` 本枚举。
 *
 * 每个构造器都携带对应的具体类型实例，因此模式匹配得到的分支变量就是
 * 已经"打开"过的具体类型，无需额外转型。
 *
 * ```cangjie
 * match (node.kind()) {
 *     case Element(e) => println("<${e.name}>")
 *     case Text(t)    => println(t.value)
 *     case _          => ()
 * }
 * ```
 */
public enum XmlNodeKind {
    | Document(XmlDocument)
    | Element(XmlElement)
    | Text(XmlText)
    | Comment(XmlComment)
    | Declaration(XmlDeclaration)
    | Unknown(XmlUnknown)
}
