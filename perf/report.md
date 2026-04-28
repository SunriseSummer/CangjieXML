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
| `catalog_small.xml` | 500 | 0.2120 | 0.1365 | 0.2747 | 1.55× | 2.01× |
| `catalog_medium.xml` | 30 | 10.703 | 7.895 | 16.490 | 1.36× | 2.09× |
| `catalog_large.xml` | 20 | 109.7 | 52.047 | 109.1 | 2.11× | 2.10× |
| `config_small.xml` | 500 | 0.0545 | 0.0321 | 0.1285 | 1.70× | 4.00× |
| `config_medium.xml` | 60 | 2.780 | 1.681 | 6.460 | 1.65× | 3.84× |
| `config_large.xml` | 20 | 21.525 | 10.723 | 44.202 | 2.01× | 4.12× |
| `deep_small.xml` | 500 | 0.0141 | 0.0108 | 0.0340 | 1.31× | 3.15× |
| `deep_medium.xml` | 200 | 0.0543 | 0.0624 | 0.1275 | 0.87× | 2.04× |
| `deep_large.xml` | 50 | 0.1092 | 0.1726 | 0.3090 | 0.63× | 1.79× |

![parse](charts/parse.svg)

## 场景：`serialize`

| fixture | N | CangjieXML | tinyxml2 | Python xml.etree | CangjieXML × | Python xml.etree × |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.1124 | 0.0407 | 0.9461 | 2.76× | 23.2× |
| `catalog_medium.xml` | 30 | 5.961 | 2.679 | 46.208 | 2.23× | 17.2× |
| `catalog_large.xml` | 20 | 41.968 | 14.081 | 278.1 | 2.98× | 19.7× |
| `config_small.xml` | 500 | 0.0328 | 0.0163 | 0.3694 | 2.01× | 22.6× |
| `config_medium.xml` | 60 | 1.970 | 0.8145 | 17.024 | 2.42× | 20.9× |
| `config_large.xml` | 20 | 13.204 | 5.109 | 102.4 | 2.58× | 20.0× |
| `deep_small.xml` | 500 | 0.0081 | 0.0042 | 0.1172 | 1.91× | 27.6× |
| `deep_medium.xml` | 200 | 0.0304 | 0.0166 | 0.5567 | 1.83× | 33.6× |
| `deep_large.xml` | 50 | 0.0608 | 0.0330 | 1.097 | 1.84× | 33.2× |

![serialize](charts/serialize.svg)

## 场景：`roundtrip`

| fixture | N | CangjieXML | tinyxml2 | Python xml.etree | CangjieXML × | Python xml.etree × |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.2544 | 0.2006 | 1.232 | 1.27× | 6.14× |
| `catalog_medium.xml` | 30 | 17.464 | 10.637 | 61.597 | 1.64× | 5.79× |
| `catalog_large.xml` | 20 | 144.3 | 70.968 | 386.8 | 2.03× | 5.45× |
| `config_small.xml` | 500 | 0.0879 | 0.0503 | 0.5028 | 1.75× | 10.00× |
| `config_medium.xml` | 60 | 5.122 | 2.585 | 23.511 | 1.98× | 9.10× |
| `config_large.xml` | 20 | 33.193 | 21.276 | 145.4 | 1.56× | 6.83× |
| `deep_small.xml` | 500 | 0.0224 | 0.0154 | 0.1594 | 1.45× | 10.3× |
| `deep_medium.xml` | 200 | 0.0849 | 0.0795 | 0.7380 | 1.07× | 9.28× |
| `deep_large.xml` | 50 | 0.1981 | 0.2060 | 1.481 | 0.96× | 7.19× |

![roundtrip](charts/roundtrip.svg)

## 场景：`traverse`

| fixture | N | CangjieXML | tinyxml2 | Python xml.etree | CangjieXML × | Python xml.etree × |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.0156 | 0.0032 | 0.0299 | 4.94× | 9.49× |
| `catalog_medium.xml` | 30 | 0.7473 | 0.2745 | 1.571 | 2.72× | 5.73× |
| `catalog_large.xml` | 20 | 12.415 | 2.283 | 9.905 | 5.44× | 4.34× |
| `config_small.xml` | 500 | 0.0016 | 0.000478 | 0.0062 | 3.35× | 13.0× |
| `config_medium.xml` | 60 | 0.1421 | 0.0842 | 0.3140 | 1.69× | 3.73× |
| `config_large.xml` | 20 | 0.7849 | 0.5948 | 1.969 | 1.32× | 3.31× |
| `deep_small.xml` | 500 | 0.0012 | 0.000478 | 0.0030 | 2.45× | 6.36× |
| `deep_medium.xml` | 200 | 0.0048 | 0.0020 | 0.0124 | 2.37× | 6.07× |
| `deep_large.xml` | 50 | 0.0102 | 0.0047 | 0.0251 | 2.19× | 5.37× |

![traverse](charts/traverse.svg)

---

原始 JSON：`perf/out/{cangjie,tinyxml2,python}.json`。
