#!/usr/bin/env python3
"""
便捷入口：先跑基准（bench.py）再生成报告（report.py）。

如果只想重新出报告而不重跑基准，直接执行 `python3 perf/report.py` 即可。
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

PERF_DIR = Path(__file__).resolve().parent


def main() -> int:
    for script in ("bench.py", "report.py"):
        rc = subprocess.run([sys.executable, str(PERF_DIR / script)]).returncode
        if rc != 0:
            return rc
    return 0


if __name__ == "__main__":
    sys.exit(main())
