#!/usr/bin/env python3
"""静岡県道路照明灯CSVから、下田市の検証用CSVを作成する。Python 3.10+。"""
import argparse
import collections
import csv
import hashlib
import io
import json
import math
from pathlib import Path

FIELDS = {
    "事務所名": "OFFICE_NAME", "路線名": "ROUTE_NAME",
    "設置位置": "LOCATION_TEXT", "管理番号": "MANAGEMENT_NO",
    "照明灯種別": "LIGHT_TYPE", "緯度": "LATITUDE", "経度": "LONGITUDE",
}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("source", type=Path)
    p.add_argument("--output", type=Path, default=Path("lights_shimoda.csv"))
    p.add_argument("--contains", default="下田市", help="設置位置の文字列フィルタ。行政界判定ではない")
    p.add_argument("--snapshot", default="20231004", help="元CSVの版。再取得時はファイル名と照合")
    a = p.parse_args()
    data = a.source.read_bytes()
    for encoding in ("utf-8-sig", "cp932"):
        try:
            text = data.decode(encoding)
            break
        except UnicodeDecodeError:
            continue
    else:
        raise SystemExit("UTF-8/CP932で読み込めません。文字コードを確認してください。")
    reader = csv.DictReader(io.StringIO(text))
    if not set(FIELDS).issubset(reader.fieldnames or []):
        raise SystemExit(f"必要な列がありません: {reader.fieldnames}")
    result, rejected = [], []
    source_count = selected_count = 0
    for row_number, row in enumerate(reader, 1):
        source_count += 1
        if a.contains not in (row.get("設置位置") or ""):
            continue
        selected_count += 1
        output = {v: (row.get(k) or "").strip() for k, v in FIELDS.items()}
        try:
            lat, lon = float(output["LATITUDE"]), float(output["LONGITUDE"])
            if not (math.isfinite(lat) and math.isfinite(lon)
                    and 34 <= lat <= 36 and 137 <= lon <= 140):
                raise ValueError("静岡県周辺の概略範囲外")
        except ValueError as e:
            rejected.append({"SOURCE_ROW": row_number, "REASON": str(e), **output})
            continue
        output.update(ASSET_ID=f"SZ{a.snapshot}-{row_number:06d}",
                      SOURCE_ROW=row_number, LATITUDE=lat, LONGITUDE=lon)
        result.append(output)
    if not result:
        raise SystemExit("対象データが0件です。フィルタと座標を確認してください。")
    a.output.parent.mkdir(parents=True, exist_ok=True)
    with a.output.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["ASSET_ID", "SOURCE_ROW", *FIELDS.values()])
        w.writeheader()
        w.writerows(result)
    ids = collections.Counter(r["MANAGEMENT_NO"] for r in result if r["MANAGEMENT_NO"])
    summary = {
        "source_file": a.source.name, "source_sha256": hashlib.sha256(data).hexdigest(),
        "encoding": encoding, "source_rows": source_count,
        "location_contains": a.contains, "selected_rows": selected_count,
        "output_rows": len(result), "rejected_rows": len(rejected),
        "missing_management_no": sum(not r["MANAGEMENT_NO"] for r in result),
        "duplicate_management_no_rows": sum(n - 1 for n in ids.values()),
        "missing_light_type": sum(not r["LIGHT_TYPE"] for r in result),
        "latitude_range": [min(r["LATITUDE"] for r in result), max(r["LATITUDE"] for r in result)],
        "longitude_range": [min(r["LONGITUDE"] for r in result), max(r["LONGITUDE"] for r in result)],
        "rejected": rejected,
    }
    a.output.with_suffix(".audit.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
