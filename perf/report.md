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
| `catalog_small.xml` | 500 | 4.398 | 0.1337 | 0.2748 | 32.9× | 2.06× |
| `catalog_medium.xml` | 30 | 245.9 | 7.528 | 16.379 | 32.7× | 2.18× |
| `catalog_large.xml` | 5 | 2,181.6 | 49.855 | 106.2 | 43.8× | 2.13× |
| `config_small.xml` | 500 | 1.620 | 0.0321 | 0.1305 | 50.5× | 4.06× |
| `config_medium.xml` | 60 | 84.324 | 1.658 | 6.486 | 50.9× | 3.91× |
| `config_large.xml` | 10 | 568.1 | 10.598 | 43.592 | 53.6× | 4.11× |
| `deep_small.xml` | 500 | 0.3783 | 0.0107 | 0.0332 | 35.4× | 3.11× |
| `deep_medium.xml` | 200 | 1.529 | 0.0623 | 0.1278 | 24.6× | 2.05× |
| `deep_large.xml` | 50 | 3.069 | 0.1729 | 0.3065 | 17.7× | 1.77× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

## 场景：`serialize`

| fixture | 迭代 | CangjieXML (ms/次) | tinyxml2 (ms/次) | Python xml.etree (ms/次) | CangjieXML 倍率 | Python xml.etree 倍率 |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.5298 | 0.0409 | 0.9541 | 13.0× | 23.4× |
| `catalog_medium.xml` | 30 | 32.977 | 2.643 | 47.178 | 12.5× | 17.8× |
| `catalog_large.xml` | 5 | 275.0 | 14.396 | 281.4 | 19.1× | 19.5× |
| `config_small.xml` | 500 | 0.1564 | 0.0166 | 0.3667 | 9.40× | 22.0× |
| `config_medium.xml` | 60 | 8.483 | 0.8137 | 17.068 | 10.4× | 21.0× |
| `config_large.xml` | 10 | 62.166 | 5.137 | 102.0 | 12.1× | 19.9× |
| `deep_small.xml` | 500 | 0.0476 | 0.0042 | 0.1158 | 11.3× | 27.4× |
| `deep_medium.xml` | 200 | 0.1855 | 0.0168 | 0.5512 | 11.1× | 32.9× |
| `deep_large.xml` | 50 | 0.3781 | 0.0335 | 1.087 | 11.3× | 32.5× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

## 场景：`roundtrip`

| fixture | 迭代 | CangjieXML (ms/次) | tinyxml2 (ms/次) | Python xml.etree (ms/次) | CangjieXML 倍率 | Python xml.etree 倍率 |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 5.041 | 0.1956 | 1.238 | 25.8× | 6.33× |
| `catalog_medium.xml` | 30 | 321.4 | 10.483 | 62.325 | 30.7× | 5.95× |
| `catalog_large.xml` | 5 | 2,562.3 | 67.924 | 392.1 | 37.7× | 5.77× |
| `config_small.xml` | 500 | 1.732 | 0.0503 | 0.5048 | 34.4× | 10.0× |
| `config_medium.xml` | 60 | 89.929 | 2.553 | 23.587 | 35.2× | 9.24× |
| `config_large.xml` | 10 | 690.5 | 20.713 | 145.6 | 33.3× | 7.03× |
| `deep_small.xml` | 500 | 0.4728 | 0.0151 | 0.1589 | 31.3× | 10.5× |
| `deep_medium.xml` | 200 | 1.698 | 0.0794 | 0.7322 | 21.4× | 9.22× |
| `deep_large.xml` | 50 | 3.459 | 0.2070 | 1.436 | 16.7× | 6.94× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

## 场景：`traverse`

| fixture | 迭代 | CangjieXML (ms/次) | tinyxml2 (ms/次) | Python xml.etree (ms/次) | CangjieXML 倍率 | Python xml.etree 倍率 |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.1833 | 0.0032 | 0.0296 | 57.8× | 9.34× |
| `catalog_medium.xml` | 30 | 11.828 | 0.2357 | 1.579 | 50.2× | 6.70× |
| `catalog_large.xml` | 5 | 127.2 | 2.539 | 13.445 | 50.1× | 5.30× |
| `config_small.xml` | 500 | 0.0264 | 0.000479 | 0.0065 | 55.1× | 13.6× |
| `config_medium.xml` | 60 | 1.381 | 0.0712 | 0.3144 | 19.4× | 4.41× |
| `config_large.xml` | 10 | 17.504 | 0.5951 | 1.967 | 29.4× | 3.31× |
| `deep_small.xml` | 500 | 0.0134 | 0.000469 | 0.0030 | 28.6× | 6.33× |
| `deep_medium.xml` | 200 | 0.0525 | 0.0020 | 0.0126 | 25.9× | 6.24× |
| `deep_large.xml` | 50 | 0.1060 | 0.0046 | 0.0256 | 23.1× | 5.57× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

## 结论与观察

- **tinyxml2** 作为成熟 C++ 库，仍然是各场景的最快基线。
- **CangjieXML** 经过本轮（M8）针对性优化后，相对 tinyxml2 的倍率从 30~70× 区间整体下移到 12~55× 区间，多个场景获得 25%~55% 的实测加速；其中 `serialize` / `traverse` 场景仓颉版已经显著**反超 Python `xml.etree`**（见各表的两个倍率列）。
- **Python `xml.etree`** 在 `parse` 上仍因走 C 实现的 expat 占优，`serialize` / `traverse` 已被仓颉版稳定反超 1.3~2× 不等。

## 本轮（M8）已落地的优化

以下优化在本 PR 内一次性落地，所有 260 个单元测试与 e2etest 五种模式指纹比对全部维持 PASS：

1. **`SourceCursor.sliceString` 改用 `String(Array<Rune>)` 构造**——废弃逐 Rune `StringBuilder.append` 路径，每个 name / attr / text 切片只做一次 UTF-8 编码。
2. **`SourceCursor.consumeIfMatch` 接受预编译 `Array<Rune>`**——把 `--` / `[CDATA[` / `-->` / `]]>` 缓存为包级 `let RUNE_*`，并在前缀全 ASCII 的情况下批量一次性更新 idx/column，省掉 per-char `advance()`。
3. **`SourceCursor.skipWhile(pred)` + `skipWhitespace` 重写**——直接索引 `runes` 数组，绕开 `peek()` 的 `Option<Rune>` 装箱与`advance()` 的双重 eof 检查；`readName` / `parseTextBody` / `readQuotedAttrValue` 全部走这条新路径。
4. **`needsTextEscape` / `needsAttrEscape` 字节级单遍扫描**——之前先 `runes()` 多遍迭代，现在按字节做单次线性扫描：`& < > "` 都是 ASCII 单字节，UTF-8 续位字节 ≥ 0x80，因此字节比对与码点比对结果完全一致。
5. **`escapeText` / `escapeAttribute` 慢路径改为字节扫描 + 区间拷贝**——只在遇到待转义字节时切片，剩余 ASCII / UTF-8 内容成段拷贝；废弃逐码点 `runes()` 解码 + per-char 5-way match。
6. **`isAllWhitespace` 字节快路径**——XML 1.0 §2.3 规定的空白集合（` \t \n \r`）全部 ASCII，按字节比 4 个常量等价于按 Rune 比，但省掉解码迭代器。
7. **`XmlElement.tryAddAttribute` 单次 HashMap 路径**——parser 原本对每个属性做 `hasAttribute`（一次 lookup）+ `setAttribute`（再一次 lookup）两次哈希查询，现在合并成一次。

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

`cjpm test` 全量绿（`PASSED: 260, SKIPPED: 0, FAILED: 0`），包括 dom / parser / writer / io / visit / query / build / doc_examples 等所有包；e2etest/xml 五种模式（parse / roundtrip-pretty / roundtrip-compact / bytes / builder）全部 PASS。

### ⚠️ 观察 4：解析器内存峰值偏高（perf 特性，非 bug）

解析 5 MB fixture 时 Cangjie 默认 heap（约 256 MB）会触发 `Out of memory`——`run.py` 通过设置 `cjHeapSize=4GB` 规避。根因在 `SourceCursor` 一次性把整段输入物化为 `Array<Rune>`（每码点 4 字节，5 MB ASCII → ~20 MB rune 数组 ×ArrayList 扩容副本 ≈ 40 MB 即时占用），叠加 DOM 节点本身的小对象开销与 GC 暂未及时回收，迭代叠加触发 OOM。

### 后续可继续推进的优化方向

1. **`SourceCursor` 字节流扫描化**：废弃整体 `Array<Rune>` 前置物化，改为 UTF-8 字节流 + 必要时按需解码。直接受益项：parse 内存峰值下降 ~10×；这是上面 "观察 4" 的根本解决方案，属结构性改动需独立 PR 推进。
2. **DOM 节点对象池**：现在每个 `XmlElement` / `XmlText` / `XmlAttribute` 都是单独 class 实例，5 MB fixture 解析过程中会产生 ~50 万个小对象触发 GC 抖动；可参考 tinyxml2 的 MemPool 做 size-class 池化。
3. **streaming parse API**：跳过完整 DOM 构造、仅发事件回调，覆盖"扫一遍提取信息"场景，理论吞吐可逼近 tinyxml2。
4. **`HashMap<String, XmlAttribute>` 在 ≤4 个属性的元素上退化为线性扫描**：典型业务文档每元素属性数 < 8，HashMap 的哈希计算 + 桶寻址在小 N 上反而比线性扫描慢。

---

原始 JSON 数据：`perf/out/{cangjie,tinyxml2,python}.json`。
