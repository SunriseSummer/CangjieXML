# 04 — Parser

包：`fastxml.parser`

递归下降解析器。输入为仓颉 `String`，输出为 `XmlDocument`。所有结构性错误都
通过 `XmlParseException`（携带 `XmlError` 与 `SourcePos`）抛出。

---

## 公共入口

### 顶层函数（推荐跨包使用）

```cangjie
public func parseXml(xml: String): XmlDocument
public func parseXml(xml: String, options: XmlParseOptions): XmlDocument
```

### 静态方法形式（`XmlDocument.parseString`）

```cangjie
// 通过 extend 注册到 XmlDocument 上
public static func parseString(xml: String): XmlDocument
public static func parseString(xml: String, options: XmlParseOptions): XmlDocument
```

两者等价。受 cjc 1.0.5 的扩展可见性限制，**跨包调用推荐使用 `parseXml(...)`**；
同包内或非跨包场景下 `XmlDocument.parseString(...)` 更贴近 tinyxml2 的直觉。

---

## `XmlParseOptions`

```cangjie
public struct XmlParseOptions {
    public let whitespace: XmlWhitespaceMode
    public let maxElementDepth: Int64
    public let acceptBom: Bool

    public init(
        whitespace!: XmlWhitespaceMode = Preserve,
        maxElementDepth!: Int64 = DEFAULT_MAX_ELEMENT_DEPTH,
        acceptBom!: Bool = true
    )

    public static func default_(): XmlParseOptions
}
```

| 字段              | 默认值                   | 含义                                                      |
| ----------------- | ------------------------ | --------------------------------------------------------- |
| `whitespace`      | `Preserve`               | 空白处理策略                                              |
| `maxElementDepth` | `500`                    | 元素最大嵌套深度，超限抛 `ElementDepthExceeded`            |
| `acceptBom`       | `true`                   | `true` 接受并剥离 UTF-8 BOM；`false` 遇到 BOM 抛错        |

**`XmlWhitespaceMode`**：

```cangjie
public enum XmlWhitespaceMode <: ToString {
    | Preserve   // 保留原文本空白
    | Collapse   // 折叠连续空白为单个空格，且删除纯空白文本节点
}
```

`Collapse` 模式对应 tinyxml2 的 `COLLAPSE_WHITESPACE`；常见于"只关心语义值"
的应用场景。

**常量**：

```cangjie
public const DEFAULT_MAX_ELEMENT_DEPTH: Int64 = 500
```

---

## 解析覆盖范围

| 语法                              | 支持                               |
| --------------------------------- | ---------------------------------- |
| XML 声明 `<?xml ... ?>`            | ✅ 保留为 `XmlDeclaration`         |
| 注释 `<!-- ... -->`                | ✅ 保留为 `XmlComment`             |
| CDATA 段 `<![CDATA[ ... ]]>`       | ✅ 保留为 `XmlText(isCdata=true)`  |
| `<!DOCTYPE ...>` 等 `<!...>`       | ✅ 保留为 `XmlUnknown`             |
| 元素开 / 闭 / 自闭合               | ✅                                 |
| 属性（单引号 / 双引号）            | ✅                                 |
| 内建实体 `&amp; &lt; &gt; &quot; &apos;` | ✅                           |
| 数字实体 `&#NN; &#xNN;`            | ✅                                 |
| 根元素唯一性 / 嵌套深度检查        | ✅                                 |

---

## 错误模型

解析错误统一抛 **`XmlParseException`**，其 `error: XmlError` 字段使用如下
构造器之一：

- `EmptyDocument` — 输入全空白或没有根元素
- `MismatchedElement(open, close, at)` — 起止标签不匹配
- `InvalidAttribute(name, at, reason)` — 属性值非法
- `InvalidText(at, reason)` — 文本非法（含期望字符缺失）
- `InvalidComment(at, reason)` — 注释非法
- `InvalidDeclaration(at, reason)` — XML 声明非法
- `InvalidUnknownNode(at, reason)` — `<!...>` 结构非法
- `InvalidEncoding(at, reason)` — 编码非法
- `ElementDepthExceeded(limit, at)` — 嵌套深度超限

所有带位置信息的构造器都携带 `SourcePos`（行 / 列 / 偏移，见
[10 — 错误模型](./10-errors.md)）。

### 典型处理模式

```cangjie
import fastxml.dom.*
import fastxml.parser.*
import fastxml.error.*

try {
    let doc = parseXml("<r>  a\n  b  </r>",
        XmlParseOptions(whitespace: Collapse))
    println(doc.rootElement.getOrThrow().textContent())
    // "a b"
} catch (e: XmlParseException) {
    // 分枝处理
    match (e.error) {
        case MismatchedElement(o, c, at) =>
            println("mismatch <${o}> vs </${c}> at ${at}")
        case _ =>
            println("parse failed: ${e.error}")
    }
}
```

---

## `SourcePos`

```cangjie
public struct SourcePos <: ToString {
    public let offset: Int64   // 从文档起始（忽略 BOM）算起的 Rune 索引
    public let line: Int64     // 1 起
    public let column: Int64   // 1 起
}
```

> Parser 产出的 `offset` 以 **Rune（码点）** 为单位，与 `line` / `column` 的计数
> 保持一致；不是字节偏移。

---

## 小例：受控的空白折叠

```cangjie
let opts = XmlParseOptions(whitespace: Collapse)
let doc = parseXml("<r>  a\n  b  </r>", opts)
// 根元素文本变为 "a b"
```

## 小例：对高深度的保护

```cangjie
// 生成一棵 600 层的 <a><a>...<a/>...</a></a>，默认上限 500
// 超限时抛 XmlParseException(error = ElementDepthExceeded(500, at))
```
