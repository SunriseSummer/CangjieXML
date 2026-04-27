# 06 — Query

包：`fastxml.query`

为 `XmlElement` 补齐**类型化查询**能力——属性 / 子元素的读取带自动解码，
缺失 / 解析失败有清晰的 `Option` 语义与必填语义分层。

引入：`import fastxml.query.*`。用户**无需**显式引用 `XmlQueryable` 接口，
方法已通过 `extend` 挂在 `XmlElement` 上。

---

## 属性查询

| 方法                                                      | 语义                                        |
| --------------------------------------------------------- | ------------------------------------------- |
| `attributeAs<T>(name, codec): ?T`                          | 读取并解码；缺失 / 解析失败都是 `None`      |
| `attributeOr<T>(name, codec, fallback): T`                 | 缺失 / 解析失败时返回 `fallback`            |
| `requiredAttribute(name): String`                          | 必填字符串；缺失抛 `XmlException`          |
| `requiredAttributeAs<T>(name, codec): T`                   | 必填并解码；缺失或解析失败抛 `XmlException` |
| `intAttribute(name): ?Int64`                               | `attributeAs<Int64>(name, INT64_CODEC)` 的短写 |
| `int32Attribute(name): ?Int32`                             | 同上，用 `INT32_CODEC`                     |
| `doubleAttribute(name): ?Float64`                          | 同上，用 `FLOAT64_CODEC`                   |
| `boolAttribute(name): ?Bool`                               | 同上，用 `BOOL_CODEC`                      |

### 示例

```cangjie
let doc = XmlDocument()
let e = doc.createElement("book")
e.setAttribute("id", "42")
e.setAttribute("avail", "true")
doc.appendChild(e)

e.intAttribute("id")                 // Some(42)
e.boolAttribute("avail")             // Some(true)
e.doubleAttribute("missing")         // None

e.attributeOr<Int64>("copies", INT64_CODEC, 0)  // 0

// 必填语义：缺失抛 XmlException
try {
    e.requiredAttribute("missing")
} catch (ex: XmlException) { /* 由调用方决定处理方式 */ }
```

---

## 子元素查询

| 方法                                                 | 语义                                      |
| ---------------------------------------------------- | ----------------------------------------- |
| `childElement(name): ?XmlElement`                     | `firstChildElement(name: Some(name))` 短写 |
| `requiredChildElement(name): XmlElement`              | 必填；缺失抛 `XmlException`              |
| `childElementText(name): ?String`                     | 读取指定子元素的 `textContent()`         |
| `childElementTextAs<T>(name, codec): ?T`              | 同上 + 解码；缺失 / 解析失败返回 `None` |
| `childElementTexts(name): Array<String>`              | 按 `name` 过滤后所有子元素的文本集合    |

### 示例

```cangjie
let doc = parseXml(
    "<store><name>SICP</name><price>42.5</price></store>")
let root = doc.rootElement.getOrThrow()

root.childElementText("name").getOrThrow()                         // "SICP"
root.childElementTextAs<Float64>("price", FLOAT64_CODEC)           // Some(42.5)
root.requiredChildElement("name").textContent()                    // "SICP"
```

---

## `XmlValueCodec<T>`：可扩展的编解码协议

```cangjie
public interface XmlValueCodec<T> {
    func tryParse(text: String): ?T
    func format(value: T): String
}
```

- `tryParse` 失败返回 `None`，**不**抛异常；
- `format` 对所有输入都是全值域定义；
- 可由用户为任意类型实现。

### 为什么不是 `Result<T, XmlError>`

`Option<T>` 的"缺失/失败"两义对 XML 语义层已经足够。失败时是否抛异常、带多少
上下文，由调用点决定（`attributeAs` → `None`；`requiredAttributeAs` → 抛异常）。

---

## 内置 codec

```cangjie
public class Int64Codec   <: XmlValueCodec<Int64>
public class Int32Codec   <: XmlValueCodec<Int32>
public class Float64Codec <: XmlValueCodec<Float64>
public class BoolCodec    <: XmlValueCodec<Bool>
public class StringCodec  <: XmlValueCodec<String>

// 单例实例——避免每次调用都构造新对象
public let INT64_CODEC:   Int64Codec
public let INT32_CODEC:   Int32Codec
public let FLOAT64_CODEC: Float64Codec
public let BOOL_CODEC:    BoolCodec
public let STRING_CODEC:  StringCodec
```

### 解析约定

| codec           | 接受输入                                          | 备注                    |
| --------------- | ------------------------------------------------- | ----------------------- |
| `Int64Codec`    | 十进制整数；允许前后 ASCII 空白                  | 溢出返回 `None`         |
| `Int32Codec`    | 同上                                              | —                       |
| `Float64Codec`  | 浮点数；允许前后空白                             | —                       |
| `BoolCodec`     | `"true"` / `"false"` / `"1"` / `"0"`（忽略大小写） | 与 tinyxml2 对齐；`format` 只出 `"true"` / `"false"` |
| `StringCodec`   | 原样透传                                          | 便于统一泛型签名         |

### 自定义 codec

下面是扩展 `XmlValueCodec<T>` 的示意草图，并未进入 `doc_examples_test.cj`
的自动化断言范围；生产实现需根据自身格式约定完整处理 radix / 大小写 / 溢出 /
前后空白等边界。

```cangjie
public class HexInt64Codec <: XmlValueCodec<Int64> {
    public func tryParse(text: String): ?Int64 {
        // 伪代码：用户按自己的进制 / trim / 大小写策略实现
        None
    }
    public func format(value: Int64): String {
        // 伪代码：按 16 进制格式化即可
        value.toString()
    }
}
```

用户自定义 codec 后，`attributeAs<T>` / `requiredAttributeAs<T>` /
`attributeOr<T>` / `childElementTextAs<T>` 以及 Builder 的 `attributeAs<T>`
都获得与内建类型**完全一致**的使用体验。

---

## 必填 vs 可选的心智模型

| 形态                                            | 返回                | 错误                                |
| ----------------------------------------------- | ------------------- | ----------------------------------- |
| `attribute(name)`                                | `?String`            | —                                   |
| `attributeAs<T>(name, codec)`                    | `?T`                 | —                                   |
| `attributeOr<T>(name, codec, fallback)`          | `T`                  | —（用 fallback 兜底）               |
| `requiredAttribute(name)`                        | `String`             | 缺失 → `XmlException`                |
| `requiredAttributeAs<T>(name, codec)`            | `T`                  | 缺失或解析失败 → `XmlException`      |

子元素端同构：`childElement` / `childElementText` / `requiredChildElement` 等。
