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
| `catalog_small.xml` | 500 | 0.1916 | 0.1509 | 0.1826 | 1.27× | 1.21× |
| `catalog_medium.xml` | 30 | 12.064 | 8.545 | 12.409 | 1.41× | 1.45× |
| `catalog_large.xml` | 20 | 82.147 | 57.237 | 85.959 | 1.44× | 1.50× |
| `config_small.xml` | 500 | 0.0422 | 0.0299 | 0.0951 | 1.41× | 3.19× |
| `config_medium.xml` | 60 | 2.203 | 1.554 | 4.581 | 1.42× | 2.95× |
| `config_large.xml` | 20 | 15.765 | 10.376 | 35.389 | 1.52× | 3.41× |
| `deep_small.xml` | 500 | 0.0184 | 0.0100 | 0.0250 | 1.85× | 2.51× |
| `deep_medium.xml` | 200 | 0.0711 | 0.0581 | 0.0972 | 1.22× | 1.67× |
| `deep_large.xml` | 50 | 0.1392 | 0.1603 | 0.2465 | 0.87× | 1.54× |

![parse](charts/parse.svg)

## 场景：`serialize`

| fixture | N | CangjieXML | tinyxml2 | Python xml.etree | CangjieXML × | Python xml.etree × |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.1032 | 0.0369 | 0.7913 | 2.80× | 21.5× |
| `catalog_medium.xml` | 30 | 5.089 | 2.713 | 39.534 | 1.88× | 14.6× |
| `catalog_large.xml` | 20 | 32.896 | 13.555 | 237.5 | 2.43× | 17.5× |
| `config_small.xml` | 500 | 0.0255 | 0.0146 | 0.3036 | 1.75× | 20.8× |
| `config_medium.xml` | 60 | 1.688 | 0.6966 | 14.496 | 2.42× | 20.8× |
| `config_large.xml` | 20 | 10.458 | 4.425 | 87.422 | 2.36× | 19.8× |
| `deep_small.xml` | 500 | 0.0079 | 0.0038 | 0.0950 | 2.10× | 25.1× |
| `deep_medium.xml` | 200 | 0.0339 | 0.0153 | 0.5246 | 2.22× | 34.3× |
| `deep_large.xml` | 50 | 0.0662 | 0.0304 | 1.022 | 2.18× | 33.6× |

![serialize](charts/serialize.svg)

## 场景：`roundtrip`

| fixture | N | CangjieXML | tinyxml2 | Python xml.etree | CangjieXML × | Python xml.etree × |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.2033 | 0.2182 | 0.9834 | 0.93× | 4.51× |
| `catalog_medium.xml` | 30 | 13.497 | 11.659 | 49.943 | 1.16× | 4.28× |
| `catalog_large.xml` | 20 | 116.5 | 75.412 | 321.3 | 1.54× | 4.26× |
| `config_small.xml` | 500 | 0.0686 | 0.0457 | 0.4292 | 1.50× | 9.38× |
| `config_medium.xml` | 60 | 4.340 | 2.281 | 18.865 | 1.90× | 8.27× |
| `config_large.xml` | 20 | 31.230 | 22.816 | 119.4 | 1.37× | 5.23× |
| `deep_small.xml` | 500 | 0.0207 | 0.0136 | 0.1228 | 1.52× | 9.01× |
| `deep_medium.xml` | 200 | 0.1039 | 0.0731 | 0.6678 | 1.42× | 9.13× |
| `deep_large.xml` | 50 | 0.2068 | 0.1916 | 1.299 | 1.08× | 6.78× |

![roundtrip](charts/roundtrip.svg)

## 场景：`traverse`

| fixture | N | CangjieXML | tinyxml2 | Python xml.etree | CangjieXML × | Python xml.etree × |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.0117 | 0.0045 | 0.0255 | 2.62× | 5.70× |
| `catalog_medium.xml` | 30 | 0.5534 | 0.2283 | 1.306 | 2.42× | 5.72× |
| `catalog_large.xml` | 20 | 7.786 | 2.852 | 8.594 | 2.73× | 3.01× |
| `config_small.xml` | 500 | 0.0014 | 0.000638 | 0.0052 | 2.17× | 8.20× |
| `config_medium.xml` | 60 | 0.0739 | 0.0422 | 0.2742 | 1.75× | 6.49× |
| `config_large.xml` | 20 | 2.676 | 0.3315 | 1.564 | 8.07× | 4.72× |
| `deep_small.xml` | 500 | 0.0013 | 0.000317 | 0.0024 | 4.08× | 7.58× |
| `deep_medium.xml` | 200 | 0.0050 | 0.0012 | 0.0100 | 4.03× | 8.04× |
| `deep_large.xml` | 50 | 0.0098 | 0.0025 | 0.0206 | 3.88× | 8.17× |

![traverse](charts/traverse.svg)

---

原始 JSON：`perf/out/{cangjie,tinyxml2,python}.json`。
