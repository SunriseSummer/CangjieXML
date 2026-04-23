# CangjieXML 渐进开发计划

> 本路线图以 [`DESIGN.md`](./DESIGN.md) 为准绳，目标是在 **不引入实现层混乱** 的前提下，把设计稳定落地为可发布的纯仓颉 XML 库。
>
> 关键词：**小步实现、边界稳定、命名统一、阶段可验收**。

---

## 1. 路线图总览

### 1.1 版本视图

```text
Phase A 基础骨架   : M0
Phase B 核心内核   : M1 ~ M3
Phase C 体验增强   : M4 ~ M5
Phase D 完整工程性 : M6 ~ M7
Phase E 发布收口   : M8
Future RFC         : M9+
```

### 1.2 里程碑总图

```text
M0 脚手架
  ↓
M1 DOM 内核
  ↓
M2 Writer
  ↓
M3 Parser
  ↓
M4 Query + Builder
  ↓
M5 Visit
  ↓
M6 IO + Error + Options 收口
  ↓
M7 Batch / Concurrency 边界
  ↓
M8 回归 / 基准 / 文档 / v1.0 发布
```

### 1.3 路线图原则

1. **先稳定结构，再丰富能力。**
2. **先 Writer，后 Parser。** 这样可以尽早建立字符串黄金测试。
3. **Query / Builder 属于体验层，必须建立在 DOM 稳定之后。**
4. **并发最后进场。** 避免为了并发破坏核心模型的简洁性。
5. **每个里程碑都必须可构建、可测试、可回滚。**

---

## 2. M0 — 项目脚手架

### 目标
建立符合仓颉规范的项目骨架，确认模块命名、目录布局、CI 入口和最小测试链路。

### 交付物
- `cjpm.toml`
- `src/cangjie_xml/lib.cj`
- `src/cangjie_xml/version.cj`
- `tests/smoke_test.cj`
- `README.md` 初版
- `.gitignore`
- CI 初版：`build + test`

### 命名与结构要求
- 采用 `dom / parser / writer / query / build / visit / io / error / internal` 的模块布局。
- 文件名全部采用小写下划线。
- 公共类型统一使用 `Xml` 前缀。

### DoD
- `cjpm build` 成功。
- `cjpm test` 成功。
- 目录骨架与 `DESIGN.md` 保持一致。

### 风险
- SDK 与 CI 环境兼容性。
- `cjpm.toml` 最初模板字段是否满足后续演进需求。

---

## 3. M1 — DOM 内核

### 目标
实现不依赖 Parser 的 DOM 模型，使文档、元素、文本、属性与基本树操作先稳定下来。

### 范围
- `XmlNode`
- `XmlNodeKind`
- `XmlDocument`
- `XmlElement`
- `XmlAttribute`
- `XmlText`
- `XmlComment`
- `XmlDeclaration`
- `XmlUnknown`

### 交付物
- `src/cangjie_xml/dom/` 下全部核心类型
- 基础树操作：追加、前插、移除、兄弟导航、根元素定位
- 属性管理：查找、设置、删除、枚举

### 测试重点
- 子节点与兄弟关系正确。
- 文档与节点的关联正确。
- 属性顺序与覆盖行为正确。
- `XmlNodeKind` 模式匹配穷举性明确。

### DoD
- DOM 相关单元测试全部通过。
- DOM 包覆盖率 ≥ 85%。
- 所有公共类型与方法具备文档注释。

### 设计警戒线
- 不要在这一阶段引入解析或序列化逻辑。
- 不要让 `XmlDocument` 承担批量解析、锁管理等额外职责。

---

## 4. M2 — Writer

### 目标
把 DOM 稳定输出为 XML 文本，为后续 Parser 与回归测试建立黄金基线。

### 范围
- `XmlWriteOptions`
- `XmlWriter`
- 文本 / 属性转义
- 格式化输出与紧凑输出
- `XmlDocument.writeToString()`

### 交付物
- `src/cangjie_xml/writer/xml_write_options.cj`
- `src/cangjie_xml/writer/xml_writer.cj`
- `src/cangjie_xml/internal/text_escape.cj`

### 测试重点
- 空元素、自闭合元素、嵌套元素。
- 注释、声明、CDATA、未知节点输出。
- `compact` 与缩进模式对比。
- 相同 DOM + 相同 options 的输出确定性。

### DoD
- 形成第一批黄金字符串测试。
- `XmlWriter` 相关测试全部通过。
- `XmlWriteOptions` 足以替代 tinyxml2 中全局静态写出配置。

### 设计警戒线
- 核心类型叫 `XmlWriter`，不要让 `XmlPrinter` 反客为主。
- Writer 的配置必须全部显式进入 `XmlWriteOptions`。

---

## 5. M3 — Parser

### 目标
把字符串、字节数组和文件稳定解析为 DOM，形成 v1 核心闭环。

### 范围
- `XmlParseOptions`
- BOM 识别
- 换行规范化
- 按需词法扫描
- 递归下降解析
- `XmlError` 与 `SourcePos` 打通

### 交付物
- `src/cangjie_xml/parser/xml_parse_options.cj`
- `src/cangjie_xml/parser/xml_source.cj`
- `src/cangjie_xml/parser/xml_parser.cj`
- `src/cangjie_xml/internal/slice.cj`
- `src/cangjie_xml/internal/normalized_buffer.cj`
- `src/cangjie_xml/internal/entity_decoder.cj`

### 测试重点
- 元素 / 文本 / CDATA / 注释 / 声明 / 未知节点解析。
- 深度保护（500 / 501）。
- `XmlWhitespaceMode` 三种策略。
- `parse -> write -> parse` 一致性。
- 典型错误路径与定位信息。

### DoD
- 建立 Parser 黄金样例库。
- tinyxml2 关键资源文件可成功迁移并通过 round-trip。
- Parser 包覆盖率 ≥ 80%。

### 设计警戒线
- 保持“首错即止”，不做激进容错恢复。
- `internal` 中的 `Slice` 等结构不进入公共 API。

---

## 6. M4 — Query + Builder

### 目标
在不污染 DOM 核心的前提下，提供仓颉用户真正会高频使用的便利能力。

### 范围
- `extend XmlElement`
- `XmlValueCodec<T>`
- 类型化属性查询
- 子元素快捷查找
- 轻量 Builder DSL

### 交付物
- `src/cangjie_xml/query/xml_element_query_ext.cj`
- `src/cangjie_xml/query/xml_node_iter_ext.cj`
- `src/cangjie_xml/query/xml_find_ext.cj`
- `src/cangjie_xml/build/xml_document_builder.cj`
- `src/cangjie_xml/build/xml_element_builder.cj`

### 测试重点
- `intAttribute` / `boolAttribute` / `doubleAttribute` 等常见扩展。
- `attributeAs(..., using: XxxCodec)` 的通用路径。
- Builder 构造结果与手工 DOM 等价。
- 子节点 / 后代迭代器行为正确。

### DoD
- Query 与 Builder 足够支撑 README 中的主要示例。
- 核心 DOM 类型没有因便利 API 膨胀失控。

### 设计警戒线
- 简写函数只能作为扩展存在，不直接塞进 `dom` 核心。
- `XmlValueCodec` 是体验层协议，不要倒灌进入 Parser 内核。

---

## 7. M5 — Visit

### 目标
提供统一遍历模型，使 Writer、统计、搜索、转换等能力共享一套机制。

### 范围
- `XmlVisitor`
- `XmlWalkControl`
- `walk(node, fn)`
- `accept(visitor)` 完整实现

### 交付物
- `src/cangjie_xml/visit/xml_visitor.cj`
- `src/cangjie_xml/visit/xml_walk.cj`

### 测试重点
- `visitEnter/visitExit` 调用顺序。
- `SkipChildren` / `Stop` 的控制流语义。
- Writer 通过 Visit 驱动输出的可行性。

### DoD
- Visit 能支撑 Writer 和用户自定义遍历。
- 访问控制语义稳定，不产生重复访问或漏访问。

### 设计警戒线
- Visit 是遍历机制，不要演变成查询 DSL。
- Visitor 默认实现应尽量简单、可预测。

---

## 8. M6 — IO + Error + Options 收口

### 目标
把所有输入输出边界、错误表达与配置对象收束为稳定的公共形态。

### 范围
- `loadFile()` / `saveFile()`
- `XmlError` 完整枚举
- `SourcePos`
- `XmlParseOptions` / `XmlWriteOptions` 最终定版
- 长格式错误说明

### 交付物
- `src/cangjie_xml/error/source_pos.cj`
- `src/cangjie_xml/error/xml_error.cj`
- `src/cangjie_xml/io/xml_loader.cj`
- `src/cangjie_xml/io/xml_saver.cj`

### 测试重点
- 文件不存在、读写失败。
- 错误位置信息可读。
- `options` 默认值合理且相互不冲突。

### DoD
- 公共 API 中不再出现模糊的临时配置参数。
- 错误信息足以直接用于 CLI 或日志输出。

### 设计警戒线
- 避免 `XmlError` 失控膨胀为“异常信息垃圾桶”。
- `io` 只做边界适配，不混入语法规则。

---

## 9. M7 — Batch / Concurrency 边界

### 目标
在不破坏核心 DOM 简洁性的前提下，提供多文档批量解析与并发消费能力。

### 范围
- `XmlBatchParser`
- 并发数配置
- 批量结果聚合
- 只读 DOM 并行消费示例

### 交付物
- `src/cangjie_xml/batch/xml_batch_parser.cj`（如决定采用独立包）
- 并发测试与示例

### 测试重点
- 多文档并行解析。
- 错误与成功结果并存时的聚合语义。
- 并发顺序与输出顺序约定是否清晰。

### DoD
- 并发能力是“加法”，而不是对核心模型的侵入式改写。
- 只读共享访问具备清晰文档说明。

### 设计警戒线
- 不在 `XmlDocument` 内部内建锁。
- 不让并发需求倒逼 DOM API 失去朴素性。

---

## 10. M8 — 回归 / 基准 / 文档 / 发布

### 目标
把库从“功能存在”提升到“可以发布”。

### 范围
- tinyxml2 回归迁移
- 性能基准
- README / 示例 / API 文档
- v1.0 发布检查表

### 交付物
- 回归测试集
- 基准测试结果
- 使用指南
- 发布说明

### 测试重点
- tinyxml2 `xmltest.cpp` 中关键行为的迁移对照。
- 大文档解析与写出基线。
- 用户从 README 跟随示例可成功运行。

### DoD
- 回归测试稳定通过。
- 基准数据可复现。
- 文档与实际 API 无漂移。
- 可以打出 `v1.0.0`。

### 设计警戒线
- 文档必须反映真实实现，而不是超前承诺。
- 基准结果用于观察趋势，不为数字而扭曲架构。

---

## 11. 未来 RFC（M9+）

这些能力进入 Future RFC，而不抢占 v1.0 主线：

### RFC-A：流式事件解析
- `XmlEvent`
- pull / iterator 风格解析
- 大文件场景优化

### RFC-B：宏驱动对象绑定
- `@XmlRoot`
- `@XmlAttribute`
- `@XmlElement`
- 面向 POCO / DTO 的双向转换

### RFC-C：XPath 子集
- 基础路径、谓词、位置过滤
- 作为独立查询层，不反向污染 DOM

### RFC-D：内部性能优化
- 节点池
- 名称字符串驻留
- 更激进的延迟物化

这些方向都值得做，但都不应抢占 v1.0 的结构确定性。

---

## 12. 追溯矩阵：设计决策到里程碑

| 设计决策 | 里程碑 |
|---|---|
| 统一模块命名与目录结构 | M0 |
| `XmlNodeKind` + `XmlNode` | M1 |
| `XmlWriter` 取代 `XmlPrinter` 作为核心命名 | M2 |
| `XmlParseOptions` / `XmlWriteOptions` | M2 / M3 / M6 |
| `XmlWhitespaceMode` | M3 |
| `XmlValueCodec` | M4 |
| Query / Builder 作为扩展层 | M4 |
| `XmlVisitor` + `walk()` | M5 |
| `XmlError` + `SourcePos` | M3 / M6 |
| 并发能力从 DOM 中解耦 | M7 |

---

## 13. 每阶段统一质量门禁

所有里程碑统一遵守：

1. `cjpm build`
2. `cjpm test`
3. `cjfmt`
4. `cjlint`
5. 新增公共 API 必须有文档注释
6. 新能力必须附带测试
7. 不引入非标准库依赖

对于本项目而言，**结构一致性本身就是质量门禁的一部分**：

- 新类型命名是否仍然优雅？
- 新能力是否仍然落在正确模块？
- 新便利函数是否污染了核心层？

如果答案是否定的，即使测试通过，也不应合入。

---

## 14. 结语

这份路线图的中心思想不是“尽快堆完功能”，而是：

> **先把骨架做美，再把肌肉长实。**

也就是说：

- M0~M3 保证结构、DOM、Writer、Parser 四根主梁立住；
- M4~M6 再补足日常体验与工程边界；
- M7 最后以“可选能力层”的方式加入并发；
- M8 才进入真正的发布收口。

这样实现出来的 CangjieXML，不只是“能用的 tinyxml2 仓颉版”，而会是一套真正适合仓颉生态长期维护的 XML 基础库。
