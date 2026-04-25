package cangjie_xml.dom

/**
 * XML 属性：挂在 `XmlElement` 上的名称/值对。
 *
 * ## 与 tinyxml2 的差异
 *
 * - tinyxml2 的 `XMLAttribute` 是链式结构且持有指向下一个属性的指针；
 *   我们把这类链表维护封到 `XmlElement` 内部，公共类型只保留干净的数据含义。
 * - 不是 `XmlNode` 的子类型——XML 规范中属性并非节点树成员。
 * - 属性值一律以原始 `String` 形态保存；类型化访问（`intAttribute` 等）由
 *   Query 层提供。
 */
public class XmlAttribute {
    /**
     * 属性名不可就地修改——若可修改，`XmlElement.attrIndex` 的 key 将与新名
     * 失同步。改名请走 `removeAttribute(oldName)` + `setAttribute(newName, value)`。
     */
    public let name: String
    public var value: String

    public init(name: String, value: String) {
        this.name = name
        this.value = value
    }
}
