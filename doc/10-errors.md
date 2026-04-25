# 10 — 错误模型

包：`cangjie_xml.error`（以及各子包内的专属异常）

CangjieXML 对错误采取**分层 + 枚举**的设计：用枚举携带语义信息，用异常类型
区分错误边界（程序员错误、解析错误、IO 错误），避免 tinyxml2 那种"一个整数错
码贯穿到底"的信息密度不足。

---

## 核心类型

### `XmlError`：统一错误枚举

```cangjie
public enum XmlError <: ToString {
    // DOM
    | DomOperationFailed(String)

    // IO（M6）
    | FileNotFound(String)
    | FileReadFailed(String, String)      // path, cause
    | FileWriteFailed(String, String)     // path, cause

    // 解析（M3）
    | EmptyDocument
    | MismatchedElement(String, String, SourcePos)   // open, close, at
    | InvalidAttribute(String, SourcePos, String)    // name, at, reason
    | InvalidText(SourcePos, String)
    | InvalidComment(SourcePos, String)
    | InvalidDeclaration(SourcePos, String)
    | InvalidUnknownNode(SourcePos, String)
    | InvalidEncoding(SourcePos, String)
    | ElementDepthExceeded(Int64, SourcePos)         // limit, at

    // Query（M4）
    | ValueDecodeFailed(String, String, SourcePos)   // targetType, text, at
}
```

`XmlError` 实现 `ToString`，直接 `println(err)` 即可得到可读的一行摘要。

### `SourcePos`

```cangjie
public struct SourcePos <: ToString {
    public let offset: Int64    // Rune 偏移（不含 BOM）
    public let line: Int64      // 1 起
    public let column: Int64    // 1 起

    public static func zero(): SourcePos    // (0, 1, 1)
}
```

`SourcePos.zero()` 用作 DOM 手工构造 / 未记录位置场景的哨兵值。

---

## 异常体系

```text
Exception
├─ XmlException            — 程序员错误（违反 API 契约 / DOM 不变量）
├─ XmlParseException       — 解析错误（包装 XmlError）
└─ XmlIoException          — IO 错误（包装 XmlError）
```

### `XmlException`

```cangjie
public class XmlException <: Exception {
    public init(message: String)
    public override func getClassName(): String { "XmlException" }
}
```

由 DOM 抛出。含义："你用错了 API，请改代码而不是 `catch`。"

典型触发：

- 插入重复根元素 / 重复 XML 声明；
- 顶层插入裸 `XmlText`；
- 把元素作为自己的祖先 / 后代；
- 跨文档插入；
- `requiredAttribute` / `requiredChildElement` 缺失。

### `XmlParseException`

```cangjie
public class XmlParseException <: Exception {
    public let error: XmlError
    public init(error: XmlError)
    public override func getClassName(): String { "XmlParseException" }
}
```

由 Parser 抛出。含义："语法错误，请看 `error` / `SourcePos` 决定如何处理。"

### `XmlIoException`

```cangjie
public class XmlIoException <: Exception {
    public let error: XmlError
    public init(error: XmlError)
    public override func getClassName(): String { "XmlIoException" }
}
```

由 IO 抛出。含义："读写文件遇到问题（找不到文件、权限、非法 UTF-8 等）。"

---

## 分层不互相嵌套

- **`loadXmlFromFile`** 读到字节后内部调 `parseXml`——语法错误**原样**以
  `XmlParseException` 抛出，不会被 `XmlIoException` 包装。
- **`saveXmlToFile`** 写盘前先序列化；序列化相关异常原样抛出，只有真正的
  文件系统错误才被映射成 `XmlIoException`。

这种分层让调用方可以按**语义**而不是按**路径**决定 `catch` 策略：

```cangjie
try {
    let doc = loadXmlFromFile(path)
    // ...
} catch (e: XmlIoException) {
    // 只可能是 FileNotFound / FileReadFailed
} catch (e: XmlParseException) {
    // 只可能是语法错误
}
```

---

## 为什么用"枚举 + 异常"，而不是 `Result<T, E>`

仓颉的异常机制与模式匹配已足够胜任错误处理；全程 `Result<T, E>` 会让每层
解析函数的签名都显式返回 Result，噪音巨大。折中做法：

- **底层**（codec、解析器内部）：尽可能用 `Option<T>` 表达可预期的"缺失/失败"。
- **API 边界**（`parseString` / `loadXmlFromFile`）：抛 `XmlParseException` /
  `XmlIoException`，让调用方一点捕获即可。
- **程序员错误**（DOM 不变量）：抛 `XmlException`，用户**不**应捕获。

---

## 典型处理模板

```cangjie
import cangjie_xml.dom.*
import cangjie_xml.io.*
import cangjie_xml.parser.*
import cangjie_xml.error.*

func load(path: String): ?XmlDocument {
    try {
        Some(loadXmlFromFile(path))
    } catch (e: XmlIoException) {
        match (e.error) {
            case FileNotFound(_)         => None
            case FileReadFailed(_, _)    => None
            case _                       => None
        }
    } catch (e: XmlParseException) {
        match (e.error) {
            case MismatchedElement(o, c, at) =>
                println("xml mismatch: <${o}> vs </${c}> @ ${at}")
            case InvalidAttribute(n, at, r) =>
                println("bad attribute ${n} @ ${at}: ${r}")
            case _ =>
                println("parse failed: ${e.error}")
        }
        None
    }
}
```
