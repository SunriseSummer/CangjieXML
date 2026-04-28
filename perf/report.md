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
| `catalog_small.xml` | 500 | 0.2424 | 0.1899 | 0.2665 | 1.28× | 1.40× |
| `catalog_medium.xml` | 30 | 12.564 | 9.900 | 16.535 | 1.27× | 1.67× |
| `catalog_large.xml` | 5 | 93.433 | 63.032 | 108.6 | 1.48× | 1.72× |
| `config_small.xml` | 500 | 0.0561 | 0.0385 | 0.1303 | 1.46× | 3.39× |
| `config_medium.xml` | 60 | 3.465 | 1.912 | 6.657 | 1.81× | 3.48× |
| `config_large.xml` | 10 | 25.623 | 12.401 | 47.390 | 2.07× | 3.82× |
| `deep_small.xml` | 500 | 0.0134 | 0.0128 | 0.0357 | 1.05× | 2.80× |
| `deep_medium.xml` | 200 | 0.0506 | 0.0709 | 0.1359 | 0.71× | 1.92× |
| `deep_large.xml` | 50 | 0.1058 | 0.1945 | 0.3216 | 0.54× | 1.65× |

![parse](charts/parse.svg)

## 场景：`serialize`

| fixture | N | CangjieXML | tinyxml2 | Python xml.etree | CangjieXML × | Python xml.etree × |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.1682 | 0.0464 | 1.045 | 3.62× | 22.5× |
| `catalog_medium.xml` | 30 | 9.071 | 3.186 | 51.114 | 2.85× | 16.0× |
| `catalog_large.xml` | 5 | 61.791 | 15.990 | 306.9 | 3.86× | 19.2× |
| `config_small.xml` | 500 | 0.0614 | 0.0184 | 0.4115 | 3.34× | 22.4× |
| `config_medium.xml` | 60 | 3.476 | 0.9005 | 19.124 | 3.86× | 21.2× |
| `config_large.xml` | 10 | 21.284 | 5.577 | 115.9 | 3.82× | 20.8× |
| `deep_small.xml` | 500 | 0.0201 | 0.0048 | 0.1302 | 4.17× | 26.9× |
| `deep_medium.xml` | 200 | 0.0580 | 0.0197 | 0.6898 | 2.94× | 35.0× |
| `deep_large.xml` | 50 | 0.1168 | 0.0388 | 1.338 | 3.01× | 34.5× |

![serialize](charts/serialize.svg)

## 场景：`roundtrip`

| fixture | N | CangjieXML | tinyxml2 | Python xml.etree | CangjieXML × | Python xml.etree × |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.3114 | 0.2601 | 1.348 | 1.20× | 5.18× |
| `catalog_medium.xml` | 30 | 20.236 | 13.328 | 65.018 | 1.52× | 4.88× |
| `catalog_large.xml` | 5 | 190.6 | 81.341 | 417.1 | 2.34× | 5.13× |
| `config_small.xml` | 500 | 0.1191 | 0.0591 | 0.5588 | 2.02× | 9.46× |
| `config_medium.xml` | 60 | 7.082 | 2.921 | 25.619 | 2.42× | 8.77× |
| `config_large.xml` | 10 | 47.957 | 25.019 | 158.8 | 1.92× | 6.35× |
| `deep_small.xml` | 500 | 0.0280 | 0.0176 | 0.1773 | 1.59× | 10.1× |
| `deep_medium.xml` | 200 | 0.1094 | 0.0917 | 0.8904 | 1.19× | 9.71× |
| `deep_large.xml` | 50 | 0.2213 | 0.2345 | 1.717 | 0.94× | 7.32× |

![roundtrip](charts/roundtrip.svg)

## 场景：`traverse`

| fixture | N | CangjieXML | tinyxml2 | Python xml.etree | CangjieXML × | Python xml.etree × |
|---|--:|--:|--:|--:|--:|--:|
| `catalog_small.xml` | 500 | 0.0141 | 0.0037 | 0.0334 | 3.83× | 9.04× |
| `catalog_medium.xml` | 30 | 1.724 | 0.1879 | 1.786 | 9.17× | 9.50× |
| `catalog_large.xml` | 5 | 20.669 | 2.840 | 14.762 | 7.28× | 5.20× |
| `config_small.xml` | 500 | 0.0020 | 0.000645 | 0.0067 | 3.12× | 10.4× |
| `config_medium.xml` | 60 | 0.1523 | 0.0499 | 0.3599 | 3.05× | 7.21× |
| `config_large.xml` | 10 | 0.6646 | 0.4330 | 2.134 | 1.53× | 4.93× |
| `deep_small.xml` | 500 | 0.0011 | 0.000313 | 0.0032 | 3.54× | 10.2× |
| `deep_medium.xml` | 200 | 0.0043 | 0.0012 | 0.0127 | 3.45× | 10.2× |
| `deep_large.xml` | 50 | 0.0080 | 0.0024 | 0.0260 | 3.30× | 10.8× |

![traverse](charts/traverse.svg)

---

原始 JSON：`perf/out/{cangjie,tinyxml2,python}.json`。
