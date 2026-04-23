# CangjieXML 开发进度

> 记录 CangjieXML 相对 tinyxml2 **全量功能** 的实现进度，并跟踪每次迭代的增量。

---

## 1. 里程碑看板

| 里程碑 | 名称 | 状态 | 说明 |
|---|---|---|---|
| M0 | 项目脚手架 | ✅ 已完成 | 本次迭代落地 |
| M1 | DOM 内核 | ✅ 已完成 | 本次迭代落地 |
| M2 | Writer | ⏳ 未开始 | 下一迭代候选 |
| M3 | Parser | ⏳ 未开始 | |
| M4 | Query + Builder | ⏳ 未开始 | |
| M5 | Visit | ⏳ 未开始 | |
| M6 | IO + Error + Options 收口 | ⏳ 未开始 | 错误枚举骨架已预落位 |
| M7 | Batch / Concurrency | ⏳ 未开始 | |
| M8 | 回归 / 基准 / 发布 | ⏳ 未开始 | |

---

## 2. 按 tinyxml2 能力域的对照

tinyxml2 v11.0.0 公共 API 能力清单（按 DESIGN.md §3.2 归纳），以及当前 CangjieXML 实现状态：

| # | tinyxml2 能力 | CangjieXML 对应 | 状态 |
|---|---|---|---|
| 1 | DOM：`XMLDocument` / `XMLElement` / `XMLText` / `XMLComment` / `XMLDeclaration` / `XMLUnknown` / `XMLAttribute` | `dom.XmlDocument` / `XmlElement` / `XmlText` / `XmlComment` / `XmlDeclaration` / `XmlUnknown` / `XmlAttribute` | ✅ 已覆盖（M1） |
| 2 | 解析：`Parse(const char*)` / `LoadFile` / 流式 / 字节数组 | `XmlDocument.parseString` / `parseBytes` / `loadFile` | ⏳ M3 |
| 3 | 序列化：`XMLPrinter` / `Print` / 紧凑 vs 格式化 | `writer.XmlWriter` / `XmlDocument.writeToString` / `saveFile` | ⏳ M2 |
| 4 | 类型化属性：`IntAttribute` / `BoolAttribute` / `QueryXxx` | `query.*` 扩展 + `XmlValueCodec<T>` | ⏳ M4 |
| 5 | 访问者：`XMLVisitor` + `Accept` | `visit.XmlVisitor` + `walk()` | ⏳ M5 |
| 6 | 安全导航：`XMLHandle` / `XMLConstHandle` | 以 `Option<T>` + `?.` / `??` 语言原生替代 | ✅ 已用语言特性替代（M1） |
| 7 | 错误报告：错误码 + 行号 + 附加文本 | `error.XmlError` 枚举 + `SourcePos` | 🟡 骨架已落位，行列填值待 M3 |
| 8 | 空白策略：`PRESERVE_WHITESPACE` / `COLLAPSE_WHITESPACE` / `PEDANTIC_WHITESPACE` | `parser.XmlWhitespaceMode` | ⏳ M3 |
| 9 | 工程性保护：最大嵌套深度 | `XmlParseOptions.maxElementDepth`（默认 500） | ⏳ M3 |

图例： ✅ 已完成  🟡 部分完成  ⏳ 未开始

---

## 3. 本次迭代（M0 + M1）详情

### 3.1 增量

- **M0 项目脚手架**
  - `cjpm.toml`（`cjc-version = "1.0.5"`，`output-type = "static"`）
  - `src/lib.cj`、`src/version.cj`、`src/smoke_test.cj`
  - `.gitignore`
- **error 模块（最小骨架）**
  - `SourcePos`：`offset / line / column` 位置结构
  - `XmlError`：完整 14 个错误构造器（M1 本次仅启用 `DomOperationFailed`，其余
    M3 / M4 / M6 将按里程碑激活）
  - `XmlException`：不可预期的 API 误用异常
- **M1 DOM 内核**
  - `XmlNodeKind`：文档 / 元素 / 文本 / 注释 / 声明 / 未知六分支枚举
  - `XmlNode`：`sealed abstract class`，持有 `document` / `parent` / `prev` / `next`
    导航状态、`kind()`、`removeSelf()`、引用相等 `==`
  - `XmlDocument`：节点工厂、顶层节点链表、`rootElement` / `declaration` 便捷访问、
    根元素与声明唯一性约束、文本节点禁止直接置顶层、`clear()` 重置
  - `XmlElement`：属性顺序保留 + 名称索引、属性的新增 / 覆盖 / 删除 / 枚举；
    子节点双向链表、`appendChild` / `prependChild` / `insertChildBefore` /
    `removeChild`；`childNodes()` / `childElements(name:)` /
    `firstChildElement(name:)` 迭代器；`textContent()` / `setTextContent()`；
    环路检测、跨文档插入禁止、节点跨父移动的自动解挂
  - `XmlAttribute` / `XmlText` / `XmlComment` / `XmlDeclaration` / `XmlUnknown`：
    轻量数据类型
- **测试**
  - 20 个 DOM 行为测试 + 1 个根包版本测试 = **21 个 @Test 全绿**
  - 覆盖：节点工厂文档归属、根元素 / 声明唯一性、兄弟导航、跨父移动、
    环路与跨文档拒绝、属性顺序与覆盖、`textContent` 递归拼接、
    `XmlNodeKind` 模式匹配穷举性等

### 3.2 质量门禁

| 门禁 | 状态 |
|---|---|
| `cjpm build` | ✅ 成功 |
| `cjpm test` | ✅ 21/21 通过 |
| 公共 API 文档注释 | ✅ 覆盖全部公共类型 / 方法 |
| 非标准库依赖 | ✅ 零 |

### 3.3 设计偏差说明

| DESIGN 原文 | 实际实现 | 原因 |
|---|---|---|
| `public sealed interface XmlNode` | `sealed abstract class XmlNode` | 避免在 6 个子类里重复实现链表导航状态；sealed + abstract 的封闭性与接口形态等价，模式匹配仍由 `XmlNodeKind` enum 承载，对用户无差别（DESIGN.md 已附加说明） |
| `XmlNode.accept(visitor)` | M1 阶段未提供 | `XmlVisitor` 属于 M5；为避免循环依赖，`accept` 将在 M5 通过扩展函数补回 |

---

## 4. 下一步候选

建议的下一次迭代：**M2 Writer**。理由：

1. Writer 不依赖 Parser，可在 DOM 稳定基础上直接落地；
2. 先建立"DOM → 字符串"的确定性输出，能立即为未来 Parser 的 round-trip
   测试提供黄金基线；
3. 代码量与 50 分钟 / 1 万行预算相容。

Writer 上线后，即可开始 M3（Parser），完成读写闭环。
