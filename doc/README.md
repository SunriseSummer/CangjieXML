# CangjieXML API 文档

> 本目录为 **CangjieXML** 的完整 API 参考文档。CangjieXML 是一个纯仓颉语言实现的
> XML 库，以 [tinyxml2](https://github.com/leethomason/tinyxml2) 为参照，
> 在保留其"DOM + 基础读写"能力边界的同时，围绕仓颉的 `enum` / 模式匹配 /
> `Option` / 扩展 / 泛型 重建 API。

本文档描述的公共 API 对应仓颉 SDK **1.0.5** 与 CangjieXML `0.1.0`。

---

## 如何使用本文档

- 如果你是新用户，请先阅读 [01 — 总览](./01-overview.md) 与
  [02 — 快速上手](./02-getting-started.md)。
- 如果你在找某个特定子包的 API，直接跳到对应章节。
- 所有**关键**示例代码都位于 `src/doc_examples/doc_examples_test.cj`，随 `cjpm test`
  一并验证——这意味着文档永远不会与实际 API 漂移。极少数"示意性"片段（例如用户可
  自定义的 codec 雏形）出于稳定性考虑不做自动校验，会在章节内明确标注。

---

## 目录

| 章节                                        | 对应子包                  | 内容摘要                             |
| ------------------------------------------- | ------------------------- | ------------------------------------ |
| [01 — 总览](./01-overview.md)                | —                         | 架构、包依赖、设计哲学               |
| [02 — 快速上手](./02-getting-started.md)     | —                         | 环境、构建、第一个程序               |
| [03 — DOM](./03-dom.md)                      | `cangjie_xml.dom`         | 节点模型、文档 / 元素 / 属性         |
| [04 — Parser](./04-parser.md)                | `cangjie_xml.parser`      | 解析入口、选项、错误                 |
| [05 — Writer](./05-writer.md)                | `cangjie_xml.writer`      | 序列化、`XmlWriteOptions`、`XmlSink` |
| [06 — Query](./06-query.md)                  | `cangjie_xml.query`       | 类型化属性 / 子元素查询，codec       |
| [07 — Builder](./07-builder.md)              | `cangjie_xml.build`       | `XmlDocumentBuilder` DSL             |
| [08 — Visit](./08-visit.md)                  | `cangjie_xml.visit`       | `walk` 与 `XmlVisitor`               |
| [09 — IO](./09-io.md)                        | `cangjie_xml.io`          | 文件 / 字节读写、流式 Sink           |
| [10 — 错误模型](./10-errors.md)              | `cangjie_xml.error` 等    | 异常体系与错误分层                   |
| [11 — 示例集](./11-examples.md)              | —                         | 端到端最佳实践与常见模式             |

---

## 命名与引入约定

- **根包**：`cangjie_xml`，仅提供库版本号常量与函数。
- **子包一律按能力划分**：`dom` / `parser` / `writer` / `query` / `build` /
  `visit` / `io` / `error`。
- 典型的"一次引入，全部可用"写法：

```cangjie
import cangjie_xml.dom.*
import cangjie_xml.parser.*
import cangjie_xml.writer.*
import cangjie_xml.query.*
import cangjie_xml.build.*
import cangjie_xml.visit.*
import cangjie_xml.io.*
import cangjie_xml.error.*
```

子包之间的依赖方向是单向的（`dom → writer/parser/query/build/visit/io`），
用户不需要关心具体方向，按需导入即可。

---

## 文档版本与回归保障

- 文档中 **绝大多数** 仓颉代码都在 `src/doc_examples/doc_examples_test.cj` 里被
  当作 `@Test` 跑过一遍——示例构造的 DOM 与断言都是生产代码级别的。
- `cjpm test` 绿灯等价于"文档中的可运行示例全部可编译、可运行、结果符合文档描述"。
- 极少量"示意草图"（例如用户扩展点的雏形）不会进入自动化验证，对应章节会明确指出。
- API 演化时，任何破坏性修改都必须同步更新本目录下对应章节。

如果你在文档里看到"例如……"而示例**没有**被测试文件覆盖，请视为 bug 并提 issue。
