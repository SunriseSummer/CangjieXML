# CangjieXML

> **纯仓颉语言实现的 XML 工具链 —— libxml2 的现代化复刻。**

CangjieXML 以 [libxml2 v2.15.3](./.libxml2-2.15.3) 为功能对标，用仓颉（Cangjie）编程语言重新设计并实现一套 **类型安全、内存安全、线程友好、可组合** 的 XML 工具链。仅依赖 `std.*` 与必要的 `stdx.*`，**不使用互操作、其他编程语言及三方库**。

- 设计依据：[`DESIGN.md`](./DESIGN.md) —— 做什么 / 为什么
- 渐进计划：[`ROADMAP.md`](./ROADMAP.md) —— 何时做 / 如何分阶段
- 当前进度：[`progress.md`](./progress.md) —— 相对 libxml2 全量功能的实现情况

---

## 构建与测试

前置：[仓颉 SDK 1.0.5](https://github.com/SunriseSummer/CangjieSDK/releases/download/1.0.5/cangjie-sdk-linux-x64-1.0.5.tar.gz)。安装并 `source <sdk>/envsetup.sh` 之后：

```bash
# 编译全部包
cjpm build

# 运行全部单元测试
cjpm test

# 代码格式化（配合 cangjie-format.toml）
cjfmt -d src/ -c cangjie-format.toml
```

## 项目布局

```
CangjieXML/
├── cjpm.toml              # 顶层模块清单
├── cangjie-format.toml    # 格式化配置
├── DESIGN.md / ROADMAP.md # 设计与计划
├── progress.md            # 相对 libxml2 的进度清单
└── src/
    ├── cangjie_xml.cj     # 顶层门面（后续汇总 public import）
    └── core/              # ✅ Phase 1 基础设施模块
```

> 项目采用单 `cjpm` 模块 + 子目录子包的布局（每个 `src/<name>/` 对应一个 `cangjie_xml.<name>` 子包），相比 `DESIGN.md` 最初构想的"多 workspace"方案更贴合 `cjpm 1.0.5` 的实际能力。后续阶段的各模块（`encoding`、`parser`、`tree` …）将以相同模式陆续引入 `src/` 下。

---

## 已实现模块

### `core` —— 基础设施（Phase 1）

对应 libxml2 的 `chvalid.c` / `xmlstring.c` / `buf.c` / `dict.c` / `error.c` / `uri.c`。由下列源文件构成：

| 文件 | 对应 libxml2 | 核心 API |
| --- | --- | --- |
| `char_valid.cj` | `chvalid.c` | `isXmlChar` / `isNameStartChar` / `isNameChar` / `isXmlWhitespace` / `isPubidChar` / `isValidName` / `isValidNcName` / `isValidXmlString` / `isXml11RestrictedChar` |
| `buffer.cj` | `buf.c` | `GrowableBuffer`、`BoundedBuffer`（带上限的防御性缓冲） |
| `string_util.cj` | `xmlstring.c` | `bytesToString` / `escapeXml` / `normalizeWhitespace` / `normalizeNewlines` |
| `name_table.cj` | `dict.c`、`hash.c` | `NameTable`（非并发 intern 池）、`ConcurrentNameTable`（基于 `ConcurrentHashMap`） |
| `qname.cj` | —（libxml2 中散落于多处） | 不可变 `QName`，比较仅看 `(localName, uri)`，与前缀无关 |
| `error.cj` | `error.c` | `Position`、`Severity`、`XmlError`（分支枚举）、`XmlException`、`ErrorCollector`、`ListErrorCollector`、`SilentErrorCollector` |
| `uri.cj` | `uri.c` | `Uri`（严格 RFC 3986 解析 / 归一化 / 基于 base 的相对参考解析） |

#### 使用示例

```cangjie
import cangjie_xml.core.*

main() {
    // 1. 校验 XML 名字
    println(isValidName("xs:element")) // true

    // 2. 字符转义
    println(escapeXml("a & b < c", forAttribute: false)) // a &amp; b &lt; c
    println(escapeXml("say \"hi\"", forAttribute: true)) // say &quot;hi&quot;

    // 3. URI 解析与相对参考解析（RFC 3986 §5.4 黄金示例）
    let base = Uri.parse("http://a/b/c/d;p?q")
    let ref = Uri.parse("../../g")
    println(ref.resolve(base)) // http://a/g

    // 4. 命名空间限定名
    let q = QName("elem", prefix: Some("p"), uri: Some("urn:demo"))
    println(q.expanded()) // {urn:demo}elem

    // 5. 诊断收集
    let collector = ListErrorCollector()
    collector.report(Severity.Error, XmlError.UriError("bad"))
    println(collector.size()) // 1
}
```

#### 覆盖的 libxml2 等价点

- XML 1.0 / 1.1 字符类与 `NameStartChar` / `NameChar` / `PubidChar` 与 W3C 规范逐区间对齐；
- `Uri.resolve` 通过 RFC 3986 §5.4.1（正常示例 23 条）与 §5.4.2（异常示例 8 条）单元测试；
- `escapeXml` 在"内容"与"属性值"两种模式下输出与 libxml2 `xmlEncodeSpecialChars` / `xmlEncodeEntitiesReentrant` 语义对齐；
- `normalizeNewlines` 覆盖 XML 1.0 行尾归一化与 XML 1.1 NEL/LS 额外归一化；
- `NameTable` 对应 `xmlDict`，提供 intern 语义且不存在 C 版的引用计数陷阱。

---

## 仍未实现

见 [`progress.md`](./progress.md)。按 `ROADMAP.md` 顺序，下一迭代将进入 **Phase 2：编码与 I/O（`encoding` + `io` 包）**。
