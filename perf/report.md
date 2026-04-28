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
| `catalog_small.xml` | 500 | 0.2101 | 0.1515 | 0.1823 | 1.39× | 1.20× |
| `catalog_medium.xml` | 30 | 7.773 | 8.359 | 12.473 | 0.93× | 1.49× |
| `catalog_large.xml` | 5 | 81.791 | 55.557 | 84.759 | 1.47× | 1.53× |
| `config_small.xml` | 500 | 0.0436 | 0.0313 | 0.0948 | 1.39× | 3.03× |
| `config_medium.xml` | 60 | 2.247 | 1.512 | 4.650 | 1.49× | 3.08× |
| `config_large.xml` | 10 | 20.313 | 10.024 | 34.690 | 2.03× | 3.46× |
| `deep_small.xml` | 500 | 0.0114 | 0.0103 | 0.0251 | 1.11× | 2.44× |
| `deep_medium.xml` | 200 | 0.0407 | 0.0594 | 0.0950 | 0.69× | 1.60× |
| `deep_large.xml` | 50 | 0.0824 | 0.1654 | 0.2426 | 0.50× | 1.47× |

![parse](charts/parse.svg)

## 场景：`serialize`

| fixture | N | CangjieXML | tinyxml2 | Python xml.etree | CangjieXML × | Python xml.etree × |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.1437 | 0.0375 | 0.7841 | 3.83× | 20.9× |
| `catalog_medium.xml` | 30 | 6.955 | 2.679 | 38.995 | 2.60× | 14.6× |
| `catalog_large.xml` | 5 | 59.071 | 14.376 | 237.7 | 4.11× | 16.5× |
| `config_small.xml` | 500 | 0.0465 | 0.0142 | 0.3063 | 3.28× | 21.6× |
| `config_medium.xml` | 60 | 2.794 | 0.6909 | 14.429 | 4.04× | 20.9× |
| `config_large.xml` | 10 | 20.552 | 4.331 | 87.732 | 4.75× | 20.3× |
| `deep_small.xml` | 500 | 0.0114 | 0.0039 | 0.0954 | 2.90× | 24.2× |
| `deep_medium.xml` | 200 | 0.0442 | 0.0155 | 0.5200 | 2.85× | 33.6× |
| `deep_large.xml` | 50 | 0.0883 | 0.0320 | 1.029 | 2.76× | 32.2× |

![serialize](charts/serialize.svg)

## 场景：`roundtrip`

| fixture | N | CangjieXML | tinyxml2 | Python xml.etree | CangjieXML × | Python xml.etree × |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.2514 | 0.2135 | 0.9771 | 1.18× | 4.58× |
| `catalog_medium.xml` | 30 | 17.042 | 11.418 | 50.167 | 1.49× | 4.39× |
| `catalog_large.xml` | 5 | 135.5 | 73.793 | 324.3 | 1.84× | 4.39× |
| `config_small.xml` | 500 | 0.0950 | 0.0468 | 0.4049 | 2.03× | 8.66× |
| `config_medium.xml` | 60 | 5.980 | 2.241 | 19.111 | 2.67× | 8.53× |
| `config_large.xml` | 10 | 34.140 | 21.557 | 120.5 | 1.58× | 5.59× |
| `deep_small.xml` | 500 | 0.0216 | 0.0144 | 0.1236 | 1.50× | 8.60× |
| `deep_medium.xml` | 200 | 0.0850 | 0.0753 | 0.6705 | 1.13× | 8.90× |
| `deep_large.xml` | 50 | 0.1803 | 0.1961 | 1.311 | 0.92× | 6.68× |

![roundtrip](charts/roundtrip.svg)

## 场景：`traverse`

| fixture | N | CangjieXML | tinyxml2 | Python xml.etree | CangjieXML × | Python xml.etree × |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.0187 | 0.0034 | 0.0248 | 5.43× | 7.20× |
| `catalog_medium.xml` | 30 | 0.5887 | 0.2234 | 1.279 | 2.64× | 5.72× |
| `catalog_large.xml` | 5 | 5.127 | 3.282 | 11.852 | 1.56× | 3.61× |
| `config_small.xml` | 500 | 0.0016 | 0.000653 | 0.0050 | 2.41× | 7.65× |
| `config_medium.xml` | 60 | 0.0791 | 0.0409 | 0.2712 | 1.93× | 6.63× |
| `config_large.xml` | 10 | 3.969 | 0.4021 | 1.607 | 9.87× | 4.00× |
| `deep_small.xml` | 500 | 0.000800 | 0.000377 | 0.0024 | 2.12× | 6.29× |
| `deep_medium.xml` | 200 | 0.0034 | 0.0013 | 0.0100 | 2.69× | 7.83× |
| `deep_large.xml` | 50 | 0.0072 | 0.0029 | 0.0208 | 2.46× | 7.15× |

![traverse](charts/traverse.svg)

---

原始 JSON：`perf/out/{cangjie,tinyxml2,python}.json`。
