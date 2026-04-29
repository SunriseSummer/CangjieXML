# 性能对比：CangjieXML / tinyxml2 / Python xml.etree

> 由 `perf/report.py` 自动生成，请勿手工修改。

## 测试方法

- 形态：目录文档、属性密集型、深嵌套，各 small / medium / large 共 9 份 fixture（`perf/fixtures/`）。
- 场景：`parse` 解析、`serialize` 序列化、`roundtrip` 解析+序列化、`traverse` 深度遍历。
- 计时：单调时钟，毫秒为单位；每单元跑 N 次取均值，N 由 fixture 字节量自适应至 0.05–5 s。
- 库版本：CangjieXML（本仓库，`-O2`）、tinyxml2 11.0.0（`-O2 -DNDEBUG`）、Python `xml.etree.ElementTree`。
- 结果表中 “×” 为相对 `tinyxml2` 的耗时倍率，越小越快；图表条长按各 fixture 内最大值归一化，尾部数值为实际 ms。

## fixture 概况

| fixture | 字节数 | 形态 |
|---|--:|---|
| `catalog_small.xml` | 16,233 | 目录文档（条目 + 属性 + 文本） |
| `catalog_medium.xml` | 831,828 | 目录文档（条目 + 属性 + 文本） |
| `catalog_large.xml` | 5,041,750 | 目录文档（条目 + 属性 + 文本） |
| `config_small.xml` | 6,162 | 配置文件（属性密集，几乎无文本） |
| `config_medium.xml` | 308,448 | 配置文件（属性密集，几乎无文本） |
| `config_large.xml` | 1,875,326 | 配置文件（属性密集，几乎无文本） |
| `deep_small.xml` | 912 | 深嵌套（递归路径、栈深度） |
| `deep_medium.xml` | 3,912 | 深嵌套（递归路径、栈深度） |
| `deep_large.xml` | 8,112 | 深嵌套（递归路径、栈深度） |

## 场景：`parse`

| fixture | N | CangjieXML | tinyxml2 | Python xml.etree | CangjieXML × | Python xml.etree × |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.1969 | 0.1508 | 0.1992 | 1.31× | 1.32× |
| `catalog_medium.xml` | 30 | 7.722 | 8.389 | 12.647 | 0.92× | 1.51× |
| `catalog_large.xml` | 20 | 81.226 | 53.673 | 86.450 | 1.51× | 1.61× |
| `config_small.xml` | 500 | 0.0421 | 0.0298 | 0.0972 | 1.41× | 3.26× |
| `config_medium.xml` | 60 | 2.220 | 1.526 | 4.703 | 1.45× | 3.08× |
| `config_large.xml` | 20 | 15.897 | 9.688 | 36.430 | 1.64× | 3.76× |
| `deep_small.xml` | 500 | 0.0105 | 0.0097 | 0.0267 | 1.08× | 2.74× |
| `deep_medium.xml` | 200 | 0.0414 | 0.0572 | 0.0978 | 0.72× | 1.71× |
| `deep_large.xml` | 50 | 0.0836 | 0.1610 | 0.2488 | 0.52× | 1.55× |

![parse](charts/parse.svg)

## 场景：`serialize`

| fixture | N | CangjieXML | tinyxml2 | Python xml.etree | CangjieXML × | Python xml.etree × |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.1044 | 0.0385 | 0.7778 | 2.71× | 20.2× |
| `catalog_medium.xml` | 30 | 4.809 | 2.661 | 38.671 | 1.81× | 14.5× |
| `catalog_large.xml` | 20 | 29.753 | 13.286 | 235.6 | 2.24× | 17.7× |
| `config_small.xml` | 500 | 0.0259 | 0.0143 | 0.3074 | 1.82× | 21.6× |
| `config_medium.xml` | 60 | 1.575 | 0.6940 | 14.460 | 2.27× | 20.8× |
| `config_large.xml` | 20 | 10.471 | 4.305 | 88.463 | 2.43× | 20.5× |
| `deep_small.xml` | 500 | 0.0063 | 0.0040 | 0.0942 | 1.57× | 23.4× |
| `deep_medium.xml` | 200 | 0.0250 | 0.0159 | 0.5141 | 1.57× | 32.2× |
| `deep_large.xml` | 50 | 0.0489 | 0.0310 | 1.008 | 1.58× | 32.5× |

![serialize](charts/serialize.svg)

## 场景：`roundtrip`

| fixture | N | CangjieXML | tinyxml2 | Python xml.etree | CangjieXML × | Python xml.etree × |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.1995 | 0.2114 | 0.9758 | 0.94× | 4.62× |
| `catalog_medium.xml` | 30 | 14.746 | 11.363 | 49.516 | 1.30× | 4.36× |
| `catalog_large.xml` | 20 | 106.8 | 71.188 | 319.4 | 1.50× | 4.49× |
| `config_small.xml` | 500 | 0.0680 | 0.0454 | 0.4082 | 1.50× | 8.99× |
| `config_medium.xml` | 60 | 4.150 | 2.252 | 19.177 | 1.84× | 8.51× |
| `config_large.xml` | 20 | 27.421 | 21.047 | 119.5 | 1.30× | 5.68× |
| `deep_small.xml` | 500 | 0.0168 | 0.0137 | 0.1235 | 1.22× | 8.99× |
| `deep_medium.xml` | 200 | 0.0695 | 0.0724 | 0.6609 | 0.96× | 9.13× |
| `deep_large.xml` | 50 | 0.1353 | 0.1970 | 1.286 | 0.69× | 6.53× |

![roundtrip](charts/roundtrip.svg)

## 场景：`traverse`

| fixture | N | CangjieXML | tinyxml2 | Python xml.etree | CangjieXML × | Python xml.etree × |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.0116 | 0.0041 | 0.0249 | 2.84× | 6.10× |
| `catalog_medium.xml` | 30 | 0.5690 | 0.2206 | 1.296 | 2.58× | 5.88× |
| `catalog_large.xml` | 20 | 6.324 | 2.511 | 8.088 | 2.52× | 3.22× |
| `config_small.xml` | 500 | 0.0014 | 0.000651 | 0.0051 | 2.18× | 7.84× |
| `config_medium.xml` | 60 | 0.1558 | 0.0408 | 0.2678 | 3.82× | 6.57× |
| `config_large.xml` | 20 | 0.4938 | 0.3178 | 1.611 | 1.55× | 5.07× |
| `deep_small.xml` | 500 | 0.000749 | 0.000310 | 0.0024 | 2.42× | 7.64× |
| `deep_medium.xml` | 200 | 0.0035 | 0.0015 | 0.0102 | 2.27× | 6.63× |
| `deep_large.xml` | 50 | 0.0062 | 0.0028 | 0.0205 | 2.26× | 7.47× |

![traverse](charts/traverse.svg)

---

原始 JSON：`perf/out/{cangjie,tinyxml2,python}.json`。
