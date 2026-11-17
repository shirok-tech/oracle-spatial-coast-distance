# 実行済み追補SQLの保存版

このフォルダは、ブログ初回検証後の診断・修復・比較・適用に使った03〜06のSQLです。配布時の内容を保持しています。コメントに「実DBでは未実行」と残っているものは当初作成時点の記述で、後日の確認状況は`../docs/validation.md`を参照してください。

**初回セットアップには使いません。初めての方はREADMEの`sql/`の手順を使います。**

| ファイル | 前提・作用 |
|---|---|
| 03_review_diagnostics.sql | 旧COASTLINE・LIGHTS・LIGHT_COAST_METRICSがある環境をSELECTで調査 |
| 04_coastline_repair_candidates.sql | 旧COASTLINEが4,991件、既存距離が271件。候補表作成、LIGHTSの索引等を補完 |
| 05_coastline_recalculate_compare.sql | 04の結果がある環境。比較用表を作成。既存結果は置き換えない |
| 06_adopt_verified_results.sql | 05合格後、既存表を退避して修復・13件除外・距離更新をコミット |

06適用済みの環境で04〜06を再実行しません。初回版と同名の表を使うため、同一スキーマで併用できません。旧初回SQLは不正図形のまま距離計算する経路を避けるため収録していません。
