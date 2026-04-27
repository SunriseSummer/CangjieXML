# e2etest — 端到端可用性对照

> 用 **Python 生成典型 XML**，分别用 **Python 标准库** 和 **CangjieXML**
> 解析并导出"指纹"，最后 **逐字段 diff**。任何不一致即报错退出。

这是 M8 的"真实世界"验收手段：单元测试证明"每个组件自己不错"，
e2e 对照证明"整条链路跟业界共识一致"。

## 目录结构

```
e2etest/
├── fixtures/
│   ├── generate.py          # 用 xml.etree 生成 10 份典型 XML
│   └── *.xml                # 运行 generate.py 后产生
├── python_probe/
│   └── probe.py             # Python 侧指纹 extractor
├── cangjie_probe/
│   ├── cjpm.toml            # 依赖 tinyxml2（path 依赖）
│   └── src/
│       ├── main.cj          # main：驱动扫描
│       └── fingerprint.cj   # 指纹提取 + 手写 JSON 序列化
├── diff.py                  # 两份指纹的 JSON diff
├── run.py                   # 入口脚本（Python）
├── out/                     # 运行时产出：python.json / cangjie.json
└── README.md
```

## 跑法

```bash
python3 e2etest/xml/run.py
```

脚本会：
1. `python3 fixtures/generate.py` — 生成 10 份 `.xml`
2. `cjpm build`（在 `cangjie_probe/` 下）— 构建仓颉 probe，`cjpm.toml` 已显式配置 `-O2`
3. 分别跑 Python probe 与仓颉 probe → 两份 JSON
4. `diff.py` 对比 → 全绿则 `[PASS] all 10 fixtures produce identical fingerprints`

无需外部 Python 第三方包；脚本只依赖 `python3` 和 `cjc`（`run.py` 会在 `cjpm`
不在 PATH 时自动 source `/opt/cangjie/envsetup.sh`）。

## 指纹（fingerprint）设计

两侧 probe 都把每个 `.xml` 归约成一份 JSON：

```json
{
  "file": "<basename>",
  "declaration_present": true,
  "root": "<root tag>",
  "total_elements": 16,
  "elements": [
    {
      "path": "root[0]/child[0]/leaf[1]",
      "depth": 2,
      "name": "leaf",
      "attrs": { "k": "v", ... },    // 按属性名字典序
      "text": "normalized direct text"
    },
    ...
  ]
}
```

设计原则：

- **`path` 按"同名兄弟序号"生成**——稳定、两端都算得出、肉眼能读。
- **`attrs` 字典序固定**——XML 属性在 DOM 里是有顺序的，但 XML 语义要求
  "顺序不敏感"；做 e2e 时排序后比，避免 `ET` 与 `tinyxml2` 在"保持源码顺序"
  上的细节抖动污染信号。
- **`text` 只取"直接文本"**——即该元素自己名下的文本片段（Python 里是
  `el.text + 各孩子 .tail`；仓颉里是直接 `XmlText` 子节点的 value），
  并做空白规范化：连续空白折叠为单空格，两端 strip。这样既能覆盖
  混合内容（`<p>Hello <b>bold</b> world.</p>`），又不会被"pretty-print 插入
  的换行 / 缩进"扰动。
- **CDATA 归一为普通文本**——Python `xml.etree` 本来就只报告文本；
  `tinyxml2` 的 `XmlText` 无论 `isCdata` 都暴露同一个 `.value`。因此
  CDATA 区段的内容会以"原文"被对比上。

## 覆盖的 fixture

| # | 文件 | 覆盖点 |
|---|---|---|
| 01 | `bookstore.xml` | 典型目录/条目/属性/文本 |
| 02 | `config.xml` | 属性密集型，几乎无文本 |
| 03 | `deep.xml` | 40 层深嵌套（栈 / 递归 / maxElementDepth）|
| 04 | `unicode.xml` | 中文 / 重音 / emoji 属性值 & 文本 |
| 05 | `cdata_and_escapes.xml` | 五个 XML 预定义实体 `&lt; &gt; &amp; &apos; &quot;` |
| 06 | `mixed_content.xml` | `.text` + 子元素 `.tail` 交替的混合内容 |
| 07 | `empty_and_selfclosing.xml` | 空元素 / 自闭合 / 仅属性 |
| 08 | `rss.xml` | RSS 风格多子项 |
| 09 | `bookstore_no_decl.xml` | 无 XML 声明，仅根元素 |
| 10 | `cdata.xml` | 真正的 `<![CDATA[...]]>` 区段 |

## 迭代过程中发现并修复的问题

> e2e 的价值不只是"留个绿灯"，更是"能暴露单测盲区的问题"。
> 在把 fixture 04（Unicode）接上时，我们抓到了一个真实 bug：

**问题**：仓颉 probe 的 `normalizeWhitespace` / `jsonEscape` 原本按**字节**
遍历，并把每个非特殊字节重新构造成 `Rune(UInt32(b))`——这会把 UTF-8 的续
字节当成独立码点，把 `算法导论`（UTF-8 9 字节）转写成 9 个 Latin-1 字符。
**修复**：非特殊字节直接写入 `ArrayList<Byte>`，最后 `String.fromUtf8`
一次性重建。规则：**能不走 `Rune` 就不要走**——`Rune` 是按码点处理的，
任何按字节扫描逻辑都不应反向重建 `Rune`。

这个坑发生在 probe 自己，不是 `tinyxml2` 主库 —— 但它恰好示范了
"写 Unicode 相关代码时必须区分 byte 与 codepoint"的通用教训。
主库自身通过 10/10 指纹一致证明了编码正确。

## 失败排查

- `[FAIL] fixture set mismatch`：两端看到的文件集合不同；通常是
  `generate.py` 没先跑，或 `cangjie_probe` 没扫到 `.xml`。
- `[FAIL] <file> total_elements`：两侧元素数不同——解析本身漏 / 多吃
  了节点；先肉眼看 `out/cangjie.json` 的 `elements` 是否截断。
- `[FAIL] <file> elements[...].text` 带"乱码"：大概率是**编码**而不是
  解析——先核对 probe 的字节/码点处理，再怀疑 `tinyxml2`。
- `[FAIL] <file> elements[...].attrs`：属性值解码（含实体）偏差——
  查 `parser/entity_decoder.cj`。
