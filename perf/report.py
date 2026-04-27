#!/usr/bin/env python3
"""
报告生成脚本——读取 `out/{cangjie,tinyxml2,python}.json`，写出 `report.md`。

简化口径：报告只保留简短测试方法说明 + 4 张场景结果表，每张表下方附一张
SVG 直方图（每条 fixture 三库横向对比）。不再附带分析、结论或调优记录。
"""

from __future__ import annotations

import json
from pathlib import Path

PERF_DIR     = Path(__file__).resolve().parent
FIXTURES_DIR = PERF_DIR / "fixtures"
OUT_DIR      = PERF_DIR / "out"
CHARTS_DIR   = PERF_DIR / "charts"
REPORT_PATH  = PERF_DIR / "report.md"

FIXTURE_ORDER = [
    "catalog_small.xml",  "catalog_medium.xml", "catalog_large.xml",
    "config_small.xml",   "config_medium.xml",  "config_large.xml",
    "deep_small.xml",     "deep_medium.xml",    "deep_large.xml",
]

SCENARIOS = ["parse", "serialize", "roundtrip", "traverse"]

# 库 ID（与 JSON `library` 字段一致）→ 表头与图例展示名
LIBS = ["fastxml", "tinyxml2-11.0.0", "python_xml.etree"]
LIB_LABEL = {
    "fastxml":          "CangjieXML",
    "tinyxml2-11.0.0":  "tinyxml2",
    "python_xml.etree": "Python xml.etree",
}
# 直方图配色（色觉友好的三色）
LIB_COLOR = {
    "fastxml":          "#2F7DC1",   # 蓝
    "tinyxml2-11.0.0":  "#7AAE5E",   # 绿
    "python_xml.etree": "#D08C3F",   # 橙
}

FIXTURE_DESC = {
    "catalog": "目录/条目/属性/文本（最常见的业务文档）",
    "config":  "属性密集型（典型配置文件，几乎无文本节点）",
    "deep":    "深嵌套（递归路径、栈深度）",
}


def index_results(payload: dict) -> dict:
    return {(r["scenario"], r["fixture"]): r for r in payload["results"]}


def fmt_avg(ms: float) -> str:
    if ms >= 100:
        return f"{ms:,.1f}"
    if ms >= 1:
        return f"{ms:.3f}"
    if ms >= 0.001:
        return f"{ms:.4f}"
    return f"{ms:.6f}"


def fmt_ratio(value: float, baseline: float) -> str:
    if baseline <= 0 or baseline != baseline:  # nan or 0
        return "—"
    r = value / baseline
    if r >= 100:
        return f"{r:,.0f}×"
    if r >= 10:
        return f"{r:.1f}×"
    return f"{r:.2f}×"


def load_inputs() -> tuple[dict, dict]:
    """返回 (by_lib, plan_iterations_by_fixture)。"""
    by_lib: dict[str, dict] = {}
    for lib_id, fname in [
        ("fastxml",          "cangjie.json"),
        ("tinyxml2-11.0.0",  "tinyxml2.json"),
        ("python_xml.etree", "python.json"),
    ]:
        path = OUT_DIR / fname
        if not path.exists():
            raise SystemExit(
                f"缺少 {path}；请先运行 `python3 perf/bench.py` 产出 JSON。"
            )
        by_lib[lib_id] = json.loads(path.read_text(encoding="utf-8"))

    plan_path = OUT_DIR / "plan.json"
    if not plan_path.exists():
        raise SystemExit(
            f"缺少 {plan_path}；请先运行 `python3 perf/bench.py` 产出 plan。"
        )
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    iters = {p["file"]: p["iterations"] for p in plan}
    return by_lib, iters


# ---------- SVG 直方图 ------------------------------------------------------

def build_svg_chart(scenario: str, indexed: dict[str, dict]) -> str:
    """为单个场景生成 9 fixture × 3 库的横向直方图（SVG）。

    每条 fixture 占一组（3 根横条），条宽按"该 fixture 内最大值"归一化——
    这样小规模与大规模 fixture 的条形可以共用同一坐标系，组内对比一目了然。
    每根条尾标注实际 ms 值。
    """
    n_fix = len(FIXTURE_ORDER)
    n_lib = len(LIBS)

    # 几何常量
    bar_h        = 14
    bar_gap      = 2          # 同组内三条之间的间距
    group_gap    = 14         # 组之间的间距
    left_pad     = 170        # fixture 名所占左侧宽度
    right_pad    = 70         # 数值标注预留宽度
    top_pad      = 36
    bottom_pad   = 30
    plot_w       = 460        # 绘图区横向像素
    title_h      = 18
    legend_h     = 18

    group_h  = n_lib * bar_h + (n_lib - 1) * bar_gap
    plot_h   = n_fix * group_h + (n_fix - 1) * group_gap
    width    = left_pad + plot_w + right_pad
    height   = top_pad + plot_h + bottom_pad

    parts: list[str] = []
    parts.append(
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'viewBox="0 0 {width} {height}" '
        f'role="img" aria-label="{scenario} 场景对比直方图" '
        f'font-family="-apple-system,Segoe UI,Helvetica,Arial,sans-serif" '
        f'font-size="11">'
    )
    # 标题
    parts.append(
        f'<text x="{left_pad}" y="16" font-size="13" font-weight="600">'
        f'场景：{scenario}（条长按 fixture 内最大值归一，尾部为实际 ms/次）'
        f'</text>'
    )
    # 图例
    legend_y = 30
    lx = left_pad
    for lib in LIBS:
        parts.append(
            f'<rect x="{lx}" y="{legend_y - 9}" width="12" height="10" '
            f'fill="{LIB_COLOR[lib]}"/>'
        )
        parts.append(
            f'<text x="{lx + 16}" y="{legend_y}">{LIB_LABEL[lib]}</text>'
        )
        lx += 16 + 8 + 8 * len(LIB_LABEL[lib])  # 粗略宽度

    # 网格底色
    parts.append(
        f'<rect x="{left_pad}" y="{top_pad}" width="{plot_w}" height="{plot_h}" '
        f'fill="#fafafa" stroke="#e0e0e0"/>'
    )

    # 每个 fixture 一组
    for i, fixture in enumerate(FIXTURE_ORDER):
        group_y = top_pad + i * (group_h + group_gap)
        # fixture 名
        parts.append(
            f'<text x="{left_pad - 8}" y="{group_y + group_h / 2 + 4}" '
            f'text-anchor="end" font-family="ui-monospace,Menlo,Consolas,monospace">'
            f'{fixture}</text>'
        )
        # 收集本 fixture 三库 avg
        avgs: dict[str, float] = {}
        for lib in LIBS:
            rec = indexed[lib].get((scenario, fixture))
            avgs[lib] = rec["elapsed_ms_avg"] if rec else float("nan")
        finite = [v for v in avgs.values() if v == v and v > 0]
        max_v = max(finite) if finite else 0.0

        for j, lib in enumerate(LIBS):
            v = avgs[lib]
            by = group_y + j * (bar_h + bar_gap)
            if v != v or max_v <= 0:
                bar_w = 0
                label = "—"
            else:
                bar_w = max(1.5, plot_w * (v / max_v))
                label = fmt_avg(v)
            parts.append(
                f'<rect x="{left_pad}" y="{by}" '
                f'width="{bar_w:.2f}" height="{bar_h}" '
                f'fill="{LIB_COLOR[lib]}"/>'
            )
            parts.append(
                f'<text x="{left_pad + bar_w + 4:.2f}" y="{by + bar_h - 3}" '
                f'fill="#333">{label}</text>'
            )

    parts.append("</svg>")
    return "".join(parts)


# ---------- Markdown 渲染 ---------------------------------------------------

def render_report(by_lib: dict, iters: dict[str, int]) -> str:
    indexed = {lib: index_results(by_lib[lib]) for lib in LIBS}
    lines: list[str] = []
    lines.append("# 性能对比：CangjieXML / tinyxml2 / Python xml.etree")
    lines.append("")
    lines.append("> 由 `perf/report.py` 自动生成，请勿手工修改。")
    lines.append("> 重新生成：先 `python3 perf/bench.py` 跑基准，再 `python3 perf/report.py` 出报告。")
    lines.append("")

    lines.append("## 测试方法")
    lines.append("")
    lines.append("- 三端共享同一组 fixture（`perf/fixtures/`）：紧凑 UTF-8 XML，"
                 "覆盖目录型 / 属性密集型 / 深嵌套三种形态，每种 small / medium / large 三档共 9 份。")
    lines.append("- 四个场景：`parse` 解析为 DOM、`serialize` 序列化为字节、"
                 "`roundtrip` 解析后立即序列化、`traverse` 深度遍历整棵 DOM。")
    lines.append("- 计时：单调时钟（C++ `steady_clock` / Python `perf_counter_ns` / 仓颉 `MonoTime`），"
                 "单位毫秒；每个单元跑 N 次取平均，N 由 fixture 字节量决定，目标单元总耗时落在 0.05 ~ 5s 区间。")
    lines.append("- 库版本：CangjieXML（本仓库，`-O2`）、tinyxml2 11.0.0（`-O2 -DNDEBUG`）、"
                 "Python `xml.etree.ElementTree`（系统 Python）。")
    lines.append("")

    lines.append("## fixture 概况")
    lines.append("")
    lines.append("| fixture | 字节数 | 形态 |")
    lines.append("|---|--:|---|")
    for f in FIXTURE_ORDER:
        kind = f.split("_", 1)[0]
        size = (FIXTURES_DIR / f).stat().st_size
        lines.append(f"| `{f}` | {size:,} | {FIXTURE_DESC[kind]} |")
    lines.append("")

    for scenario in SCENARIOS:
        lines.append(f"## 场景：`{scenario}`")
        lines.append("")
        header_libs = " | ".join(f"{LIB_LABEL[l]} (ms/次)" for l in LIBS)
        ratio_libs  = " | ".join(f"{LIB_LABEL[l]} 倍率"
                                 for l in LIBS if l != "tinyxml2-11.0.0")
        lines.append(f"| fixture | 迭代 | {header_libs} | {ratio_libs} |")
        sep = "|---|--:|" + "--:|" * len(LIBS) + "--:|" * (len(LIBS) - 1)
        lines.append(sep)

        for f in FIXTURE_ORDER:
            avgs: dict[str, float] = {}
            cells_avg: list[str] = []
            for lib in LIBS:
                rec = indexed[lib].get((scenario, f))
                if rec is None:
                    cells_avg.append("—")
                    avgs[lib] = float("nan")
                else:
                    avgs[lib] = rec["elapsed_ms_avg"]
                    cells_avg.append(fmt_avg(rec["elapsed_ms_avg"]))
            base = avgs.get("tinyxml2-11.0.0", float("nan"))
            ratio_cells = [fmt_ratio(avgs.get(l, float("nan")), base)
                           for l in LIBS if l != "tinyxml2-11.0.0"]
            lines.append(
                f"| `{f}` | {iters.get(f, 0)} | "
                + " | ".join(cells_avg)
                + " | " + " | ".join(ratio_cells) + " |"
            )
        lines.append("")
        lines.append("> 倍率列以 `tinyxml2` 为 1×；数值越小越快。")
        lines.append("")
        svg_path = CHARTS_DIR / f"{scenario}.svg"
        svg_path.write_text(build_svg_chart(scenario, indexed), encoding="utf-8")
        # 用相对路径引用，便于 GitHub / 本地预览均能正常渲染。
        rel = svg_path.relative_to(PERF_DIR).as_posix()
        lines.append(f"![{scenario} 场景对比直方图]({rel})")
        lines.append("")

    lines.append("---")
    lines.append("")
    lines.append("原始 JSON：`perf/out/{cangjie,tinyxml2,python}.json`。")
    return "\n".join(lines) + "\n"


def main() -> int:
    by_lib, iters = load_inputs()
    CHARTS_DIR.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(render_report(by_lib, iters), encoding="utf-8")
    print(f"[report] 已写入 {REPORT_PATH}")
    print(f"[report] SVG 图表写入 {CHARTS_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
