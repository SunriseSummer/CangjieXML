package tinyxml2.dom

/**
 * XML 节点种类。
 *
 * 公共 API 不提供 tinyxml2 风格的 `ToElement()` / `ToText()` 向下转型函数，
 * 调用方应直接 `match (node.kind())` 走不同分支。每个构造器携带对应的具体
 * 类型实例，匹配得到的分支变量已是"打开"过的具体类型，无需再次转型。
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
