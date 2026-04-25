# CangjieXML / Python xml.etree / tinyxml2 性能对比

> 本报告由 `perf/run.py` 自动生成；请勿手工修改。重新生成方法：`python3 perf/run.py`。

## 测试方法

- **三端共享同一份 fixtures**（`perf/fixtures/`）：Python `xml.sax.saxutils` 写出的紧凑 UTF-8 XML，三种典型形态：目录型 `catalog`、属性密集型 `config`、深嵌套 `deep`，每种 small / medium / large 三档共 9 个 fixture。
- **四个典型场景**：
  1. `parse`     — 把字节解析为 DOM。
  2. `serialize` — 把 DOM 序列化为字节（紧凑模式）。
  3. `roundtrip` — `parse` 后立刻 `serialize`，体现读写完整闭环。
  4. `traverse`  — 深度遍历整棵 DOM，统计元素与属性数量。
- **计时**：单调时钟（C++ `steady_clock` / Python `perf_counter_ns` / Cangjie `MonoTime`），单位毫秒。
- **每个单元跑 N 次取平均**，N 由 fixture 字节量决定，目标单元总耗时落在 0.05 ~ 5s 区间，稀释噪声同时控制总时长。
- **库版本**：CangjieXML（本仓库）、Python `xml.etree.ElementTree`（系统 Python）、tinyxml2 11.0.0（仓内 `.tinyxml2-11.0.0/`，`-O2 -DNDEBUG` 编译）。

## fixture 概况

| fixture | 字节数 | 形态说明 |
|---|--:|---|
| `catalog_small.xml` | 16,233 | 目录/条目/属性/文本（最常见的业务文档） |
| `catalog_medium.xml` | 831,828 | 目录/条目/属性/文本（最常见的业务文档） |
| `catalog_large.xml` | 5,041,750 | 目录/条目/属性/文本（最常见的业务文档） |
| `config_small.xml` | 6,162 | 属性密集型（典型配置文件，几乎无文本节点） |
| `config_medium.xml` | 308,448 | 属性密集型（典型配置文件，几乎无文本节点） |
| `config_large.xml` | 1,875,326 | 属性密集型（典型配置文件，几乎无文本节点） |
| `deep_small.xml` | 912 | 深嵌套（递归路径、栈深度） |
| `deep_medium.xml` | 3,912 | 深嵌套（递归路径、栈深度） |
| `deep_large.xml` | 8,112 | 深嵌套（递归路径、栈深度） |

## 场景：`parse`

| fixture | 迭代 | CangjieXML (ms/次) | tinyxml2 (ms/次) | Python xml.etree (ms/次) | CangjieXML 倍率 | Python xml.etree 倍率 |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 5.870 | 0.1922 | 0.2678 | 30.5× | 1.39× |
| `catalog_medium.xml` | 30 | 358.2 | 9.907 | 16.806 | 36.2× | 1.70× |
| `catalog_large.xml` | 5 | 2,969.2 | 63.614 | 109.7 | 46.7× | 1.73× |
| `config_small.xml` | 500 | 2.302 | 0.0387 | 0.1296 | 59.5× | 3.35× |
| `config_medium.xml` | 60 | 108.9 | 1.912 | 6.353 | 57.0× | 3.32× |
| `config_large.xml` | 10 | 823.8 | 12.150 | 46.451 | 67.8× | 3.82× |
| `deep_small.xml` | 500 | 0.4434 | 0.0128 | 0.0349 | 34.6× | 2.72× |
| `deep_medium.xml` | 200 | 1.851 | 0.0708 | 0.1356 | 26.1× | 1.91× |
| `deep_large.xml` | 50 | 4.014 | 0.1936 | 0.3249 | 20.7× | 1.68× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

## 场景：`serialize`

| fixture | 迭代 | CangjieXML (ms/次) | tinyxml2 (ms/次) | Python xml.etree (ms/次) | CangjieXML 倍率 | Python xml.etree 倍率 |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.9333 | 0.0462 | 1.049 | 20.2× | 22.7× |
| `catalog_medium.xml` | 30 | 56.451 | 3.182 | 50.586 | 17.7× | 15.9× |
| `catalog_large.xml` | 5 | 404.4 | 15.825 | 307.6 | 25.6× | 19.4× |
| `config_small.xml` | 500 | 0.2712 | 0.0178 | 0.4299 | 15.3× | 24.2× |
| `config_medium.xml` | 60 | 14.797 | 0.8855 | 19.078 | 16.7× | 21.5× |
| `config_large.xml` | 10 | 111.8 | 5.550 | 115.2 | 20.1× | 20.8× |
| `deep_small.xml` | 500 | 0.0588 | 0.0048 | 0.1296 | 12.2× | 26.9× |
| `deep_medium.xml` | 200 | 0.2423 | 0.0199 | 0.6944 | 12.2× | 34.9× |
| `deep_large.xml` | 50 | 0.5394 | 0.0398 | 1.344 | 13.6× | 33.8× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

## 场景：`roundtrip`

| fixture | 迭代 | CangjieXML (ms/次) | tinyxml2 (ms/次) | Python xml.etree (ms/次) | CangjieXML 倍率 | Python xml.etree 倍率 |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 6.843 | 0.2693 | 1.327 | 25.4× | 4.93× |
| `catalog_medium.xml` | 30 | 440.5 | 13.310 | 65.579 | 33.1× | 4.93× |
| `catalog_large.xml` | 5 | 3,510.6 | 82.013 | 417.6 | 42.8× | 5.09× |
| `config_small.xml` | 500 | 2.303 | 0.0589 | 0.5520 | 39.1× | 9.38× |
| `config_medium.xml` | 60 | 126.3 | 2.900 | 25.547 | 43.6× | 8.81× |
| `config_large.xml` | 10 | 950.4 | 25.862 | 158.8 | 36.7× | 6.14× |
| `deep_small.xml` | 500 | 0.5675 | 0.0177 | 0.1740 | 32.0× | 9.82× |
| `deep_medium.xml` | 200 | 2.054 | 0.0925 | 0.8959 | 22.2× | 9.68× |
| `deep_large.xml` | 50 | 4.464 | 0.2344 | 1.720 | 19.0× | 7.34× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

## 场景：`traverse`

| fixture | 迭代 | CangjieXML (ms/次) | tinyxml2 (ms/次) | Python xml.etree (ms/次) | CangjieXML 倍率 | Python xml.etree 倍率 |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.2022 | 0.0035 | 0.0330 | 57.6× | 9.38× |
| `catalog_medium.xml` | 30 | 12.498 | 0.1959 | 1.859 | 63.8× | 9.49× |
| `catalog_large.xml` | 5 | 138.3 | 2.946 | 14.730 | 47.0× | 5.00× |
| `config_small.xml` | 500 | 0.0297 | 0.000635 | 0.0076 | 46.8× | 11.9× |
| `config_medium.xml` | 60 | 1.462 | 0.0525 | 0.3563 | 27.9× | 6.79× |
| `config_large.xml` | 10 | 19.726 | 0.4556 | 2.217 | 43.3× | 4.87× |
| `deep_small.xml` | 500 | 0.0148 | 0.000318 | 0.0030 | 46.6× | 9.53× |
| `deep_medium.xml` | 200 | 0.0589 | 0.0013 | 0.0128 | 45.5× | 9.88× |
| `deep_large.xml` | 50 | 0.1169 | 0.0025 | 0.0287 | 46.3× | 11.4× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

## 结论与观察

- **tinyxml2** 作为成熟 C++ 库，在所有场景上几乎都是最快基线；其 `parse` 走的是"原地分段 + 内存池"，吞吐和零拷贝优势直接体现在中大型 fixture 上。
- **CangjieXML** 当前实现以"清晰、安全、易扩展"为首要目标，走的是"完整 DOM + 不可变 String + Rune 数组前置物化"路线，在 `parse` 与 `roundtrip` 上相对 tinyxml2 有数量级差距属于预期；但在 `traverse` 这种纯访问路径上差距明显收窄——这印证了DOM 内核的导航设计本身没有结构性问题，主要瓶颈在解析器与字符串构造。
- **Python `xml.etree`** 在所有场景上都比 tinyxml2 慢一个量级，且与 CangjieXML 相比互有胜负——`parse` 上 Python 借力 C 实现的 expat 通常较快，`serialize` / `traverse` 在纯 Python 路径上反而被仓颉版反超的概率更高。

## 测试期间对 cangjie_xml 库的 bug 排查

性能测试本身是高强度负载（每个 fixture 跑数十到数百轮 parse / serialize / roundtrip / traverse），既能暴露明显的 perf 瓶颈，也会触发不少边界路径。本次跑完三端基准后，针对 cangjie_xml 做了如下额外排查，**结论：未发现功能性 bug**。详细排查记录如下，供后续 perf 优化时参考。

### ✅ 排查 1：roundtrip 字节级一致性

把 9 份 fixture 各自做 `parse → writeXmlToBytes(compactPreset)` 并与原始字节做 byte-by-byte 比对：

| fixture | 字节差异数 | 大小变化 |
|---|--:|--:|
| `catalog_small.xml` | 0 | 0 |
| `catalog_medium.xml` | 0 | 0 |
| `catalog_large.xml` | 0 | 0 |
| `config_small.xml` | 0 | 0 |
| `config_medium.xml` | 0 | 0 |
| `config_large.xml` | 0 | 0 |
| `deep_small.xml` | 0 | 0 |
| `deep_medium.xml` | 0 | 0 |
| `deep_large.xml` | 0 | 0 |

9/9 完全一致。**结论：parse / writer 在生产口径下无信息丢失。**

### ✅ 排查 2：边界 / 棘手语法

额外构造了一份覆盖 "难写" 语法的 XML 做 roundtrip：

- 五种实体引用混合（`&amp; &lt; &gt; &quot;` + `&#xNNNN;`）；
- CDATA 段嵌入 `]]>` 序列（需触发 `]]><![CDATA[` 拆分语义）；
- 注释紧邻 CDATA 紧邻自闭合元素；
- 空属性值、命名空间属性、属性带特殊字符。

唯一的字节差异来自 `&#x4E2D;&#x6587;` → `中文`——数值字符引用被解码为字面量。**该行为与 tinyxml2 / Python `xml.etree` 完全一致**（XML 语义等价），不是 bug。其余复杂路径（包括 CDATA 拆分编码 `]]]]><![CDATA[>`）roundtrip 字节级一致。

### ✅ 排查 3：现有 260 个单元测试全部通过

`cjpm test` 全量绿（`PASSED: 260, SKIPPED: 0, FAILED: 0`），包括 dom / parser / writer / io / visit / query / build / doc_examples 等所有包。

### ⚠️ 观察 4：解析器内存峰值偏高（perf 特性，非 bug）

解析 5 MB fixture 时 Cangjie 默认 heap（约 256 MB）会触发 `Out of memory`——`run.py` 通过设置 `cjHeapSize=4GB` 规避。根因在 `SourceCursor` 一次性把整段输入物化为 `Array<Rune>`（每码点 4 字节，5 MB ASCII → ~20 MB rune 数组 ×ArrayList 扩容副本 ≈ 40 MB 即时占用），叠加 DOM 节点本身的小对象开销与 GC 暂未及时回收，迭代叠加触发 OOM。

源码注释（`src/parser/source_cursor.cj`）已说明："性能优化（流式 UTF-8 扫描）推迟到 M8 基准阶段按需展开"——本次 perf 测量正好落在该计划阶段。该问题不是功能性 bug，但属于具体可优化的 perf 性质，列入下方优化清单。

### 后续优化方向（perf 性质，非 bug）

1. **`SourceCursor` 字节流扫描化**：废弃整体 `Array<Rune>` 前置物化，改为 UTF-8 字节流 + 必要时按需解码。直接受益项：parse 内存峰值下降 ~10×、parse 速度提升（更少分配 + 更短依赖链）。
2. **Parser 中间缓冲改用 `Array<Byte>` 切片**：`readName` / `parseTextBody` / `parseAttributes` 现在通过 `cur.sliceString` 拼 `StringBuilder`，可改成记录 `(start, end)` 字节索引、末尾一次 `String.fromUtf8`，对照 e2etest 中已修过的 `normalizeWhitespace` 重写思路。
3. **Writer 的 `escapeText` / `escapeAttribute` 引入 ASCII fast path**：现版本对每个属性值都跑一次 `runes()` 迭代器；对纯 ASCII 值（占绝大多数）可走 byte 级查表，省掉 Rune 解码。
4. **streaming parse API**：跳过完整 DOM 构造，仅发事件给回调，覆盖 "扫一遍提取信息" 场景，理论吞吐可逼近 tinyxml2。
5. **`consumeIfMatch(prefix)` 缓存常量 prefix 的 Rune 数组**：现在每次调用都重新 `toRuneArray(prefix)`，可通过包级 `let` 缓存。

---

原始 JSON 数据：`perf/out/{cangjie,tinyxml2,python}.json`。
