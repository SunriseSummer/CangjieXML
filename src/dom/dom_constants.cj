package fastxml.dom

// 属性数量超过该阈值后，`XmlElement` 才会构建 `HashMap` 名称索引；小元素继续线性扫描更划算
const ATTR_INDEX_THRESHOLD: Int64 = 8
public const DEFAULT_DECLARATION_VALUE: String = "xml version=\"1.0\" encoding=\"UTF-8\""
