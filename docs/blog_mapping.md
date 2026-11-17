# ブログとの対応

ブログ原稿・画像はユーザー側のQiita原稿で管理し、この配布物には含めていません。

| ブログの操作 | 配布ファイル |
|---|---|
| 照明灯CSVの準備 | prepare_lights.py |
| 二重ZIPを展開 | unpack_gsi_zip.py |
| 海岸線GMLの変換 | convert_gsi_coastline.py |
| SPATIAL_AUTHORの有効化 | sql/00_spatial_user.sql |
| 初回のDB作成〜色分け用ビュー | sql/01〜04 |
| 最終件数・区分確認／次回CSV | sql/05〜06 |
| レビュー時に実行した03〜06 | legacy/に同名で保存 |

記事中の旧`01_setup.sql`・`02_coast_distance.sql`と、今回の初回版SQLは番号だけで対応付けないでください。記事のSQLとファイルのCREATEを二重実行しません。

記事の配布ファイル説明は「このリポジトリのREADMEに従い、初回実行はsql/01〜04、既存環境の追補履歴はlegacy/を参照」としてください。今回の配布版ではLIGHTS_RAW／COASTLINE_RAWへの改名は不要です。
