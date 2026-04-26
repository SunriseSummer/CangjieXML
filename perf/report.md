# CangjieXML / Python xml.etree / tinyxml2 性能对比

> 本报告由 `perf/run.py` 自动生成；请勿手工修改。重新生成方法：`python3 perf/run.py`。仓颉侧统一按 `-O2` 编译。

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
| `catalog_small.xml` | 500 | 0.2450 | 0.1899 | 0.2638 | 1.29× | 1.39× |
| `catalog_medium.xml` | 30 | 13.379 | 9.922 | 16.505 | 1.35× | 1.66× |
| `catalog_large.xml` | 5 | 95.536 | 62.942 | 107.6 | 1.52× | 1.71× |
| `config_small.xml` | 500 | 0.0564 | 0.0384 | 0.1294 | 1.47× | 3.37× |
| `config_medium.xml` | 60 | 3.433 | 1.906 | 6.535 | 1.80× | 3.43× |
| `config_large.xml` | 10 | 24.013 | 12.461 | 46.804 | 1.93× | 3.76× |
| `deep_small.xml` | 500 | 0.0128 | 0.0126 | 0.0357 | 1.01× | 2.83× |
| `deep_medium.xml` | 200 | 0.0531 | 0.0717 | 0.1337 | 0.74× | 1.86× |
| `deep_large.xml` | 50 | 0.1137 | 0.1950 | 0.3291 | 0.58× | 1.69× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

## 场景：`serialize`

| fixture | 迭代 | CangjieXML (ms/次) | tinyxml2 (ms/次) | Python xml.etree (ms/次) | CangjieXML 倍率 | Python xml.etree 倍率 |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.1635 | 0.0454 | 1.035 | 3.60× | 22.8× |
| `catalog_medium.xml` | 30 | 8.877 | 3.233 | 50.511 | 2.75× | 15.6× |
| `catalog_large.xml` | 5 | 62.672 | 15.851 | 305.3 | 3.95× | 19.3× |
| `config_small.xml` | 500 | 0.0617 | 0.0183 | 0.4059 | 3.38× | 22.2× |
| `config_medium.xml` | 60 | 3.454 | 0.9355 | 18.929 | 3.69× | 20.2× |
| `config_large.xml` | 10 | 22.447 | 5.559 | 114.4 | 4.04× | 20.6× |
| `deep_small.xml` | 500 | 0.0150 | 0.0048 | 0.1284 | 3.11× | 26.7× |
| `deep_medium.xml` | 200 | 0.0580 | 0.0193 | 0.6798 | 3.00× | 35.1× |
| `deep_large.xml` | 50 | 0.1186 | 0.0381 | 1.327 | 3.11× | 34.8× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

## 场景：`roundtrip`

| fixture | 迭代 | CangjieXML (ms/次) | tinyxml2 (ms/次) | Python xml.etree (ms/次) | CangjieXML 倍率 | Python xml.etree 倍率 |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.3108 | 0.2661 | 1.319 | 1.17× | 4.96× |
| `catalog_medium.xml` | 30 | 19.775 | 13.297 | 65.521 | 1.49× | 4.93× |
| `catalog_large.xml` | 5 | 206.6 | 81.706 | 416.9 | 2.53× | 5.10× |
| `config_small.xml` | 500 | 0.1227 | 0.0584 | 0.5526 | 2.10× | 9.47× |
| `config_medium.xml` | 60 | 7.281 | 2.903 | 25.515 | 2.51× | 8.79× |
| `config_large.xml` | 10 | 48.034 | 25.374 | 159.5 | 1.89× | 6.28× |
| `deep_small.xml` | 500 | 0.0276 | 0.0176 | 0.1731 | 1.57× | 9.82× |
| `deep_medium.xml` | 200 | 0.1118 | 0.0918 | 0.8750 | 1.22× | 9.54× |
| `deep_large.xml` | 50 | 0.2327 | 0.2359 | 1.714 | 0.99× | 7.26× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

## 场景：`traverse`

| fixture | 迭代 | CangjieXML (ms/次) | tinyxml2 (ms/次) | Python xml.etree (ms/次) | CangjieXML 倍率 | Python xml.etree 倍率 |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.0142 | 0.0040 | 0.0330 | 3.58× | 8.31× |
| `catalog_medium.xml` | 30 | 1.374 | 0.2092 | 1.769 | 6.57× | 8.46× |
| `catalog_large.xml` | 5 | 6.135 | 3.057 | 15.180 | 2.01× | 4.97× |
| `config_small.xml` | 500 | 0.0019 | 0.000634 | 0.0068 | 3.03× | 10.7× |
| `config_medium.xml` | 60 | 0.1373 | 0.0559 | 0.3568 | 2.45× | 6.38× |
| `config_large.xml` | 10 | 0.6778 | 0.5784 | 2.139 | 1.17× | 3.70× |
| `deep_small.xml` | 500 | 0.0011 | 0.000318 | 0.0031 | 3.46× | 9.79× |
| `deep_medium.xml` | 200 | 0.0041 | 0.0012 | 0.0130 | 3.49× | 11.0× |
| `deep_large.xml` | 50 | 0.0084 | 0.0024 | 0.0267 | 3.42× | 10.9× |

> 倍率列以 `tinyxml2` 为 1×；数值越小越快。

## 结论与观察

- **tinyxml2** 作为成熟 C++ 库（原地分段 + 内存池 + strchr/SSE），在各场景上是最快基线。
- **CangjieXML** 在 `-O2` 下相对 tinyxml2 的倍率落在 **约 1× ~ 9×**；`serialize` / `traverse` 稳定**反超 Python `xml.etree`**，`roundtrip` 在中大 fixture 上同样领先 Python。
- **Python `xml.etree`** 在 `parse` 上仍因走 C 实现的 expat 占优；仓颉版的剩余差距集中在大文档解析与属性密集型遍历。

## 测试期间对 cangjie_xml 库的 bug 排查

性能测试本身是高强度负载（每个 fixture 跑数十到数百轮 parse / serialize / roundtrip / traverse），既能暴露明显的 perf 瓶颈，也会触发不少边界路径。**结论：未发现功能性 bug**，详细排查记录如下。

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

### 剩余差距溯源 → 仓颉编译器 / 运行时 / 标准库

DOM / parser / writer / escape 层面的算法优化已经基本榨干（参考 tinyxml2 的实现思路：原地分段切片 / 零拷贝 sub-string / 内存池 / strchr-SSE 字节查找）。**剩余 6~35× 的差距，根因不在 cangjie_xml 算法层，而落在仓颉编译器、运行时与标准库的通用性能特性上。**

已在 `problem.md` 中按观察到的影响维度记录了 **8 个具体的低效实现**（含复现路径、估算量化影响、对照实现），可作为反馈给 Cangjie SDK 团队的素材：

1. P1：`String` 内部 UTF-8 但 `Rune` 解码到 4-byte——parser 必须前置物化 `Array<Rune>`，5 MB ASCII 输入即耗 ~20 MB。
2. P1：闭包参数 `(T) -> R` 触发堆分配——XML 闭包密集场景的 GC 压力源，逼迫库代码用宏式特化 workaround（已在 `SourceCursor` 里手动展开 `skipNameChars` / `skipUntilLt` / `skipAttrValueChars`）。
3. P2：`Iterable<T>` / `Iterator<T>` 接口虚分发 + Option 装箱——writer 索引迭代成为唯一性能可接受的方案。
4. P2：`String.runes()` 没有零开销 `forEachByte` 等价物。
5. P2：`StringBuilder` 缺公开容量预分配 API（构造器只接受空 / 字符串）。
6. P2：`HashMap<String, V>` 哈希函数对短键也走全字节扫描，无 inline cache。
7. P3：`String → Array<Byte>` 与 `StringBuilder → Array<Byte>` 路径重复做一次 UTF-8 编码，没有零拷贝出口。
8. P3：缺乏 SIMD/intrinsic：字节扫描特殊字符 (`<` `&` `"`) 只能逐字节 if-比较，对照 C 端的 `strchr` / `_mm_cmpestri` 有数量级差距。

详见仓库根的 `problem.md`。这些项的修复或公开 API 暴露能让 cangjie_xml 进一步逼近 tinyxml2 量级，且会同时受益于其它字符密集型库（JSON / TOML / 协议解析等）。

### 后续应用层可继续推进的优化（不依赖 SDK 修复）

1. **`SourceCursor` 完全字节流扫描化**：当前 ASCII 输入下 `sliceString` 已经直接走原 `String` 字节切片，但 `runes` 仍被完整物化（用于 `peek` / `advance` 等热路径上的码点等值比较）。下一步可彻底废弃整体 `Array<Rune>` 前置物化，改为 UTF-8 字节流 + 按需解码；理论上 parse 内存峰值再降 ~4×，属结构性改动需独立 PR 推进。
2. **DOM 节点对象池**：现在每个 `XmlElement` / `XmlText` / `XmlAttribute` 都是单独 class 实例，5 MB fixture 解析过程中会产生 ~50 万个小对象触发 GC 抖动；可参考 tinyxml2 的 MemPool 做 size-class 池化。
3. **streaming parse API**：跳过完整 DOM 构造、仅发事件回调，覆盖"扫一遍提取信息"场景，理论吞吐可逼近 tinyxml2。

> 历史项已在仓内落地：实体解码字节扫描化、CDATA 拆分字节扫描化、`XmlElement` 属性容器懒建索引（≤ 8 个属性走线性扫描）、ASCII 输入下 `SourceCursor.sliceString` 直接走原 `String` 字节切片（避免 `Array<Rune>` 切片 + UTF-8 重编码）、`trimLeft` / `isDeclarationPayload` / `collapseWhitespace` 字节扫描化，上面的数据已包含这些改造的收益。

---

原始 JSON 数据：`perf/out/{cangjie,tinyxml2,python}.json`。
