#!/usr/bin/env python3
"""基盤地図情報Cstlineの2D折れ線をWGS84 GeoJSONへ変換。Python 3.10+、pyproj。"""
import argparse
import hashlib
import json
import math
import xml.etree.ElementTree as ET
from pathlib import Path
from pyproj import Transformer

# 国土地理院の「日本の測地系」に基づく水平座標の取り扱い。
# JGD2024の緯度経度はJGD2011から引き継がれている。標高変換には使わない。
SOURCE_CRS = {"fguuid:jgd2000.bl": 4612, "fguuid:jgd2011.bl": 6668,
              "fguuid:jgd2024.bl": 6668}


def local(tag):
    return tag.rsplit("}", 1)[-1]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("input_directory", type=Path, help="解凍済みGML/XMLのフォルダ")
    p.add_argument("--output", type=Path, default=Path("coastline_wgs84.geojson"))
    a = p.parse_args()
    files = sorted(f for f in a.input_directory.rglob("*")
                   if f.is_file() and f.suffix.lower() in (".xml", ".gml"))
    features, sources, operations, seen = [], [], {}, {}
    source_features = removed_duplicates = 0
    for file in files:
        raw = file.read_bytes()
        root = ET.fromstring(raw)
        coasts = [e for e in root.iter() if local(e.tag) == "Cstline"]
        if not coasts:
            continue
        sources.append({"file": str(file.relative_to(a.input_directory)),
                        "sha256": hashlib.sha256(raw).hexdigest()})
        for coast in coasts:
            source_features += 1
            coast_type = next((e.text.strip() for e in coast
                               if local(e.tag) == "type" and e.text), "")
            fid = next((e.text.strip() for e in coast if local(e.tag) == "fid" and e.text), None)
            if not fid:
                fid = next((v for k, v in coast.attrib.items() if local(k) == "id"), "")
            locs = [e for e in coast if local(e.tag) == "loc"]
            if len(locs) != 1 or len(locs[0]) != 1:
                raise ValueError(f"未対応のloc形式: {file.name} {fid}")
            geom = locs[0][0]
            if local(geom.tag) not in ("Curve", "LineString"):
                raise ValueError(f"未対応の図形: {file.name} {fid} {local(geom.tag)}")
            srs = geom.get("srsName")
            if srs not in SOURCE_CRS:
                raise ValueError(f"未対応/不明な測地系: {srs} ({file.name})")
            for e in geom.iter():
                if e.get("srsDimension", "2") != "2":
                    raise ValueError("3D座標には対応していません")
                if e.get("srsName", srs) != srs:
                    raise ValueError("図形内の測地系が混在しています")
            transformer = Transformer.from_crs(SOURCE_CRS[srs], 4326,
                                              always_xy=True, allow_ballpark=False)
            if local(geom.tag) == "Curve":
                segments = [e for e in geom if local(e.tag) == "segments"]
                if len(segments) != 1 or not len(segments[0]):
                    raise ValueError(f"segmentsがありません: {fid}")
                parts = list(segments[0])
                if any(local(e.tag) != "LineStringSegment" for e in parts):
                    raise ValueError(f"折れ線以外のsegment: {fid}")
            else:
                parts = [geom]
            coast_parts = []
            for segment in parts:
                lists = [e for e in segment if local(e.tag) == "posList"]
                if len(lists) != 1 or not lists[0].text:
                    raise ValueError(f"posListを確認してください: {fid}")
                values = [float(x) for x in lists[0].text.split()]
                if len(values) < 4 or len(values) % 2:
                    raise ValueError(f"2D座標対ではありません: {fid}")
                coords = []
                for lat, lon in zip(values[0::2], values[1::2]):
                    # 基盤地図情報 .bl の記述順は緯度、経度。
                    if not (math.isfinite(lat) and math.isfinite(lon)
                            and 20 <= lat <= 50 and 120 <= lon <= 155):
                        raise ValueError(f"日本付近の緯度経度ではありません: {fid}")
                    x, y = transformer.transform(lon, lat, errcheck=True)
                    if not (math.isfinite(x) and math.isfinite(y)):
                        raise ValueError(f"変換結果が非有限値です: {fid}")
                    xy = [x, y]
                    if coords and xy == coords[-1]:
                        removed_duplicates += 1
                    else:
                        coords.append(xy)
                if len(coords) < 2:
                    raise ValueError(f"有効な線分になりません: {fid}")
                coast_parts.append(coords)
            if fid and fid in seen:
                if seen[fid] != coast_parts:
                    raise ValueError(f"同じfidに異なる座標があります。版の混在を確認: {fid}")
                continue
            if fid:
                seen[fid] = coast_parts
            operations[srs] = {"horizontal_source_epsg": SOURCE_CRS[srs],
                               "target_epsg": 4326, "description": transformer.description,
                               "operation_accuracy_m": transformer.accuracy}
            for part_no, coords in enumerate(coast_parts, 1):
                features.append({"type": "Feature", "properties": {
                    "COAST_ID": len(features) + 1, "SOURCE_FILE": file.name,
                    "SOURCE_FID": fid, "SOURCE_SRS": srs, "PART_NO": part_no,
                    "COAST_TYPE": coast_type},
                    "geometry": {"type": "LineString", "coordinates": coords}})
    if not features:
        raise ValueError("Cstlineが0件です。海岸線のGML/XMLを解凍して配置してください。")
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps({"type": "FeatureCollection", "features": features},
                                  ensure_ascii=False, allow_nan=False), encoding="utf-8")
    manifest = {"input_files": sources, "source_features": source_features,
                "output_lines": len(features), "removed_consecutive_duplicate_points": removed_duplicates,
                "transformations": operations,
                "note": "2D水平座標のみ。実際の位置精度をoperation_accuracy_mで保証しない。"}
    a.output.with_suffix(".manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"output_lines": len(features), "transformations": operations},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
