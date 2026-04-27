# 05 — Writer

包：`fastxml.writer`

把 `XmlDocument` / `XmlElement` 序列化为 XML 文本。无全局静态状态——所有
行为由一份 `XmlWriteOptions` 完全决定。

---

## 公共入口

### 便捷方法（`extend` 注入到 DOM）

```cangjie
// 植入到 XmlDocument
public interface XmlWritable {
    func writeToString(): String
    func writeToString(options: XmlWriteOptions): String
}

extend XmlDocument <: XmlWritable { ... }
extend XmlElement  <: XmlWritable { ... }
```

- `XmlDocument.writeToString(options?)` — 完整文档（含 BOM / 声明决策）。
- `XmlElement.writeToString(options?)` — 纯子树，不含 BOM / 声明。

### 底层 API

```cangjie
public class XmlWriter {
    public init(sink: XmlSink, options!: XmlWriteOptions = XmlWriteOptions.default_())

    public func writeDocument(doc: XmlDocument): Unit
    public func writeElement(el: XmlElement): Unit
    public func writeNode(node: XmlNode): Unit
}
```

典型用法：

```cangjie
let sink = StringXmlSink()
let w = XmlWriter(sink, options: XmlWriteOptions.compactPreset())
w.writeDocument(doc)
let xml = sink.toString()
```

---

## `XmlWriteOptions`

**不可变** `struct`，所有字段构造时一次性生效：

```cangjie
public struct XmlWriteOptions {
    public let compact: Bool            // 默认 false
    public let indent: String           // 默认 "    "（4 空格）
    public let lineEnd: String          // 默认 "\n"
    public let writeDeclaration: Bool   // 默认 true
    public let writeBom: Bool           // 默认 false
    public let boolTrueText: String     // 默认 "true"
    public let boolFalseText: String    // 默认 "false"

    public init(
        compact!: Bool = false,
        indent!: String = "    ",
        lineEnd!: String = "\n",
        writeDeclaration!: Bool = true,
        writeBom!: Bool = false,
        boolTrueText!: String = "true",
        boolFalseText!: String = "false"
    )

    public static func default_(): XmlWriteOptions       // 美化 + 输出声明 + 无 BOM
    public static func compactPreset(): XmlWriteOptions  // 紧凑单行；保留声明
}
```

- `compact = true` 时：无缩进、无换行；`indent` / `lineEnd` 被忽略。
- `writeDeclaration = false`：完全不输出任何 `<?xml ... ?>`；
- `writeDeclaration = true`：**若文档已有声明则原样输出**；否则合成默认
  `<?xml version="1.0" encoding="UTF-8"?>`。
- `writeBom = true` 或 `document.writeBom = true` 都会使开头写出 UTF-8 BOM。
- `boolTrueText` / `boolFalseText` 保留给 Query / Builder 层使用，不影响 Writer 本身。

---

## 排版规则

| 元素内容                    | 输出                                                      |
| --------------------------- | --------------------------------------------------------- |
| 无子节点                    | `<e/>`                                                    |
| 含文本的混合内容            | **全内联**：`<e>a<b/>c</e>`（保留空白语义）              |
| 仅元素 / 注释 / 未知子节点  | **块级**：每个子节点独占一行，按 `indent` 缩进          |

例子（美化模式）：

```xml
<!-- 无子节点 -->
<e/>

<!-- 含文本：全内联 -->
<e>hello</e>
<e>a<b/>c</e>

<!-- 纯元素：块级 -->
<catalog>
    <book/>
    <book/>
</catalog>
```

---

## 转义矩阵

| 上下文       | 转义目标                             |
| ------------ | ------------------------------------ |
| 文本节点     | `&` / `<` / `>`                      |
| 属性值       | `&` / `<` / `>` / `"`                |
| CDATA        | 不转义；若含 `]]>` 自动按规范拆段   |

**快路径**：输入若不含任何需转义字符，直接返回原字符串，零分配。

### 示例

```cangjie
let doc = XmlDocument()
let e = doc.createElement("e")
e.setAttribute("x", "a&b<c>d\"e")
doc.appendChild(e)
doc.writeToString(XmlWriteOptions(writeDeclaration: false))
// <e x="a&amp;b&lt;c&gt;d&quot;e"/>

let d2 = XmlDocument()
let e2 = d2.createElement("e")
d2.appendChild(e2)
e2.setTextContent("a<b>c&d\"e")
d2.writeToString(XmlWriteOptions(writeDeclaration: false))
// <e>a&lt;b&gt;c&amp;d"e</e>         // 注意文本节点不转义 `"`
```

---

## 确定性契约

> **相同 DOM + 相同 `XmlWriteOptions` → 逐字节一致的输出。**

这是 Writer 的公开承诺，使 diff、缓存失效、签名校验等外围工程成为可能。

---

## `XmlSink`：扩展点

```cangjie
public interface XmlSink {
    func write(text: String): Unit
    func flush(): Unit
}

public class StringXmlSink <: XmlSink {
    public init()
    public init(initialCapacity: Int64)
    public func write(text: String): Unit
    public func flush(): Unit
    public func toString(): String    // 读取累积的输出
}
```

- `StringXmlSink`：最基础的内存 Sink。
- **大文档 / 流式写盘**：见 `fastxml.io.FileXmlSink`（[09 — IO](./09-io.md)）。
- 自定义 Sink：实现 `XmlSink`，接入网络流、压缩、管道等任意目的地。

---

## 导出常量

```cangjie
public const DEFAULT_XML_DECLARATION_VALUE: String = "xml version=\"1.0\" encoding=\"UTF-8\""
```

Writer 合成默认声明时使用。与 DOM 包中的 `DEFAULT_DECLARATION_VALUE` 取值相同，
两者独立以避免反向依赖。

---

## 小例：紧凑 vs 美化

```cangjie
let doc = XmlDocument()
doc.appendChild(doc.createDeclaration())
let r = doc.createElement("catalog")
doc.appendChild(r)
let b = doc.createElement("book")
b.setAttribute("id", "1")
b.setTextContent("SICP")
r.appendChild(b)

// 默认：美化
println(doc.writeToString())
// <?xml version="1.0" encoding="UTF-8"?>
// <catalog>
//     <book id="1">SICP</book>
// </catalog>

// 紧凑
println(doc.writeToString(XmlWriteOptions.compactPreset()))
// <?xml version="1.0" encoding="UTF-8"?><catalog><book id="1">SICP</book></catalog>

// 压制声明 + 自定义缩进
println(doc.writeToString(
    XmlWriteOptions(writeDeclaration: false, indent: "  ")))
// <catalog>
//   <book id="1">SICP</book>
// </catalog>
```
