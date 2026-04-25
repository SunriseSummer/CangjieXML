# 01 — 总览

CangjieXML 是一个**纯仓颉语言实现**的 XML 处理库。它以 tinyxml2 为参照，
采用 DOM 模型与基础读写组合的能力边界，零 C/C++ 依赖，全部 API 与仓颉的
语言特性（`enum`、模式匹配、`Option<T>`、`extend`、泛型）天然贴合。

---

## 设计目标

| 维度       | 设计选择                                                         |
| ---------- | ---------------------------------------------------------------- |
| **能力边界** | DOM 内核 + 手工 Builder + 解析器 + 序列化器 + IO                |
| **错误模型** | `XmlError` 枚举 + 分层异常（`XmlException` / `XmlParseException` / `XmlIoException`） |
| **配置模型** | 不可变 `struct`（`XmlParseOptions` / `XmlWriteOptions`），无全局开关 |
| **遍历模型** | 函数式 `walk` + 经典 `XmlVisitor`，两种范式并存                   |
| **确定性**   | 相同 DOM + 相同 `XmlWriteOptions` → 逐字节一致输出                |
| **工程红线** | 单文件 ≤ 300 行、无下划线前缀、低圈复杂度、常量化              |

---

## 包结构

```
cangjie_xml/                 # 根包，仅含版本号
├── dom/                     # DOM 节点模型（M1）
├── parser/                  # 递归下降解析器（M3）
├── writer/                  # 序列化器、XmlSink、XmlWriteOptions（M2）
├── query/                   # 类型化属性 / 子元素查询、codec（M4）
├── build/                   # Builder DSL（M4）
├── visit/                   # walk / XmlVisitor（M5）
├── io/                      # 文件 / 字节 IO（M6）
├── error/                   # 错误类型（贯穿全期）
└── internal/                # 内部工具（转义、字符分类），不对外开放
```

### 依赖方向

```
error  ←── dom
dom    ←── writer
dom    ←── parser  ──→ error
dom    ←── query   ──→ error
dom    ←── build   ──→ query
dom    ←── visit
writer ←── io      ──→ parser  ──→ error
```

依赖关系严格单向，无循环。任何扩展（`extend`）都从子包向 `dom` 单向植入新方法，
DOM 包自身保持极小且稳定。

---

## 与 tinyxml2 的对应关系

| tinyxml2                         | CangjieXML                         | 迁移原因                            |
| -------------------------------- | ---------------------------------- | ----------------------------------- |
| `XMLDocument` / `XMLElement` …    | `XmlDocument` / `XmlElement` …     | 直接对应                            |
| `XMLHandle`                      | `Option<T>` + `?.` / `??`          | 语言特性天然覆盖                    |
| `ToElement()` / `ToText()`       | `match (node.kind())`              | 模式匹配取代运行时转型              |
| `QueryIntAttribute(...)` 等      | `intAttribute(...)` / `XmlValueCodec<T>` | 类型化扩展 + 用户可扩展 codec |
| `MemPool` / `StrPair`            | （不提供）                         | GC 语言不需要手工内存池             |
| 全局静态写出开关                 | `XmlWriteOptions`（struct）        | 显式配置、线程安全                  |
| `XMLPrinter`                     | `XmlWriter` + `XmlSink`            | Writer 与 Sink 解耦                 |
| `XMLVisitor`                     | `XmlVisitor` + `walk` 双范式       | 同时提供现代函数式 API              |

---

## 核心不变量（API 契约）

以下不变量构成所有子包共同的前提，用户可以把它们视为"免费"的正确性：

1. **每个节点都属于某个 `XmlDocument`**
   - 节点只能通过 `doc.createXxx(...)` 创建；所有 `XmlNode.document` 返回非空。
2. **跨文档插入被禁止**
   - 跨文档 `appendChild` 立即抛 `XmlException`。
3. **根元素与声明的唯一性**
   - 每个文档至多一个 `XmlElement` 根，至多一条 `XmlDeclaration`，且声明必须是
     首个顶层节点。
4. **DOM 树无环**
   - 把节点插到自己祖先下会抛 `XmlException`；插入已在其他父节点下的节点会
     自动先解挂（DOM 移动语义）。
5. **确定性序列化**
   - 相同 DOM + 相同 `XmlWriteOptions` → 逐字节一致的输出，天然适配 diff /
     缓存 / 签名。
6. **错误分层不互相嵌套**
   - `XmlIoException` 只负责 IO 边界；落盘之后的语法错误原样以
     `XmlParseException` 抛出。

详细 API 见后续各章。
