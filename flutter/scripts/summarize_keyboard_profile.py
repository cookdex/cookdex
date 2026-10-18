"""Summarize the last eight keyboard open/close cycles from profile fixtures."""
import json
import math
import statistics
from pathlib import Path

root = Path(__file__).resolve().parents[2] / "artifacts/polish-round2-followup"
report = {}
for phase in ("before", "after"):
    data = json.loads((root / phase / "keyboard-profile.json").read_text(encoding="utf-8-sig"))
    groups = []
    for metric in data["metrics"]:
        if not groups or metric["timeUs"] - groups[-1][-1]["timeUs"] > 500_000:
            groups.append([])
        groups[-1].append(metric)
    groups = groups[-16:]
    if len(groups) != 16:
        raise ValueError(f"{phase}: expected eight complete open/close cycles")
    frames = [frame for frame in data["frames"] if any(
        group[0]["timeUs"] - 20_000 <= frame["startUs"] <= group[-1]["timeUs"] + 100_000
        for group in groups
    )]

    def stats(key):
        values = sorted(frame[key] / 1000 for frame in frames)
        return {
            "p50": round(statistics.median(values), 2),
            "p90": round(values[math.ceil(len(values) * .90) - 1], 2),
            "p95": round(values[math.ceil(len(values) * .95) - 1], 2),
            "max": round(max(values), 2),
        }

    report[phase] = {
        "animationGroups": len(groups),
        "metrics": sum(len(group) for group in groups),
        "frames": len(frames),
        "buildMs": stats("buildUs"),
        "rasterMs": stats("rasterUs"),
        "totalMs": stats("totalUs"),
        "buildOver16ms": sum(frame["buildUs"] > 16_667 for frame in frames),
        "rasterOver16ms": sum(frame["rasterUs"] > 16_667 for frame in frames),
        "groupRanges": [(group[0]["timeUs"], group[-1]["timeUs"]) for group in groups],
    }
(root / "keyboard-timings-summary.json").write_text(json.dumps(report, indent=2), encoding="utf8")
print(json.dumps(report, indent=2))
