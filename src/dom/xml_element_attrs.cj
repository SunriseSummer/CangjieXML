package cangjie_xml.dom

/**
 * `XmlElement` 属性 API。
 *
 * 通过 `extend` 植回 `XmlElement`；底层名称查找走 [XmlElement.findAttr]，
 * 在属性数 ≤ [ATTR_INDEX_THRESHOLD] 时为线性扫描，超阈值后才使用 HashMap。
 */
extend XmlElement {

    /** 查找指定名称的属性值；不存在返回 `None`。 */
    public func attribute(name: String): ?String {
        match (findAttr(name)) {
            case Some(a) => Some(a.value)
            case None => None
        }
    }

    /**
     * 判断属性是否存在；若传入 `value`，则同时比较值。
     *
     * - `hasAttribute("id")`：仅检查属性是否存在。
     * - `hasAttribute("id", value: Some("1"))`：同时要求值等于 `"1"`。
     */
    public func hasAttribute(name: String, value!: ?String = None): Bool {
        match (findAttr(name)) {
            case None => false
            case Some(a) => matchValue(a.value, value)
        }
    }

    /**
     * 新增或覆盖属性。同名属性按"后写覆盖"语义处理，不改变属性插入顺序。
     */
    public func setAttribute(name: String, value: String): Unit {
        match (findAttr(name)) {
            case Some(a) => a.value = value
            case None => addNewAttr(XmlAttribute(name, value))
        }
    }

    /**
     * 仅在不存在同名属性时新增，返回是否成功。供 parser 等"已知 attribute
     * 必须唯一"的高频路径使用：返回 `false` 即重复属性，调用方决定如何报错。
     */
    public func tryAddAttribute(name: String, value: String): Bool {
        match (findAttr(name)) {
            case Some(_) => false
            case None =>
                addNewAttr(XmlAttribute(name, value))
                true
        }
    }

    /**
     * 删除指定名称的属性。
     *
     * - 成功删除返回 `true`；
     * - 属性不存在返回 `false`。
     */
    public func removeAttribute(name: String): Bool {
        let n = attrOrder.size
        var i = 0
        while (i < n) {
            if (attrOrder[i].name == name) {
                attrOrder.remove(at: i)
                dropFromAttrIndex(name)
                return true
            }
            i++
        }
        false
    }

    /** 以插入顺序遍历所有属性。 */
    public func attributes(): Iterable<XmlAttribute> {
        attrOrder
    }

    /** 当前元素的属性数量。 */
    public func attributeCount(): Int64 {
        attrOrder.size
    }

    /**
     * 按插入顺序索引访问属性（0 ≤ i < attributeCount()）。
     *
     * 提供索引访问以便给热路径（writer 序列化、批量诊断）一条不分配迭代器
     * 对象的遍历方式：`for i in 0..el.attributeCount() { el.attributeAt(i) }`。
     * 越界时抛 `IndexOutOfBoundsException`（直接走 ArrayList 的语义）。
     */
    public func attributeAt(i: Int64): XmlAttribute {
        attrOrder[i]
    }
}

/** 把 `hasAttribute` 的可选值比较从 match 中提出，使主路径无嵌套。 */
func matchValue(actual: String, expected: ?String): Bool {
    match (expected) {
        case None => true
        case Some(v) => actual == v
    }
}
