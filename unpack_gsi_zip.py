#!/usr/bin/env python3
"""基盤地図情報の一括ZIP内にあるメッシュ別ZIPからXML/GMLを展開する。Python 3.10+。"""
import argparse
import io
import json
from pathlib import Path, PurePosixPath
from zipfile import ZipFile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="ダウンロードしたZIP。外側の一括ZIPをそのまま指定可")
    parser.add_argument("--output", type=Path, default=Path("gsi_coastline"))
    args = parser.parse_args()
    if args.output.exists() and any(args.output.iterdir()):
        raise SystemExit("出力先が空ではありません。過去の版と混ぜないよう、別の出力先を指定してください。")
    counters = {"nested_zip_files": 0, "xml_gml_files": 0, "coastline_files": 0}
    pending = []

    def collect(archive, parent=Path(), depth=0):
        if depth > 3:
            raise ValueError("ZIPの入れ子が深すぎます。ダウンロード内容を確認してください。")
        for info in archive.infolist():
            if info.is_dir():
                continue
            # アーカイブ内のパスは使わず、ファイル名だけで出力先を組み立てる。
            name = PurePosixPath(info.filename.replace("\\", "/")).name
            suffix = Path(name).suffix.lower()
            if name.lower().endswith(".zip"):
                # Pythonの版によっては「...zip」のstemが「..」になる。
                # 展開先の親へ移動する名前は、書き出し前に拒否する。
                stem = name[:-4]
                if stem in ("", ".", ".."):
                    raise ValueError(f"安全でないZIPファイル名です: {name}")
                counters["nested_zip_files"] += 1
                with ZipFile(io.BytesIO(archive.read(info))) as nested:
                    collect(nested, parent / stem, depth + 1)
            elif suffix in (".xml", ".gml"):
                pending.append((parent / name, archive.read(info)))
                counters["xml_gml_files"] += 1
                counters["coastline_files"] += "-cstline-" in name.lower()

    with ZipFile(args.source) as archive:
        collect(archive)
    if not counters["coastline_files"]:
        raise SystemExit("Cstlineファイルがありません。「基本項目」の「海岸線」を選んだZIPか確認してください。")
    if len({str(path) for path, _ in pending}) != len(pending):
        raise SystemExit("出力名が重複しています。ZIPの構成を確認してください。")
    for relative, data in pending:
        target = args.output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    print(json.dumps({"output_directory": str(args.output), **counters}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
