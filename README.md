# Oracle Spatialで道路照明灯の海岸距離を可視化する

静岡県の道路照明灯オープンデータから下田市の271設備を抽出し、国土地理院の海岸線と組み合わせて、Oracle Spatialで海岸距離を計算します。Autonomous AI Lakehouse組み込みのSpatial Studioで色分け・属性表示する、ブログ第1回の実行用コードです。

**初めて実行する方は、このREADMEの初回手順を使ってください。** `legacy/`はブログ検証中に使った追補SQLで、初回手順と混ぜません。すでに06の適用が済んだ環境では、作成・修復SQLを再実行する必要はありません。`sql/05_verify_results.sql`と`sql/06_export_results.sql`は、その環境でも利用できる読み取り用SQLです。

## 確認済みの範囲

- 利用者のOracle AI Database 26ai（23.26.4.1.0）で、追補SQL 04・05・06の実行結果が確認されています。
- 公開用の`sql/01`〜`04`は、その処理を「修復してから距離計算」の順に再構成したものです。**この初回版一式はOracle実機での通し実行が未確認です。** 公開時点では検証用コードとして扱ってください。
- Pythonは実際のCSV・海岸線ZIPで再実行して確認しています。詳細は[検証状況](docs/validation.md)を参照してください。
- DBへの接続情報・ウォレット・実行ログ・元データ・生成済みCSV/GeoJSONは含めていません。各提供元から取得し、ローカルで生成します。

## ファイル

| ファイル | 用途 |
|---|---|
| `prepare_lights.py` | 日本語列名の元CSVを抽出し、IDと英語列名を付与 |
| `unpack_gsi_zip.py` | 国土地理院の二重ZIPを展開 |
| `convert_gsi_coastline.py` | Cstlineの2D折れ線をWGS84 GeoJSONへ変換 |
| `requirements.txt` | Python依存ライブラリ |
| `sql/00_spatial_user.sql` | 既存のSPATIAL_USERに対するADMIN用の権限設定 |
| `sql/01_setup.sql` | 取り込み済みの表から、LIGHTSとCOASTLINE_SOURCEを作成 |
| `sql/02_repair_candidates.sql` | 許容値0.05で検証し、修復候補を保存 |
| `sql/03_calculate_and_verify.sql` | 有効線で距離を計算し、短線の除外影響と距離を照合 |
| `sql/04_publish_results.sql` | 検証後に計算表と表示用ビューを作成。Webへの公開操作は行わない |
| `sql/05_verify_results.sql` | 最終状態の件数・区分・索引をSELECTで確認 |
| `sql/06_export_results.sql` | SQLclから次回用のCSVを出力 |
| `legacy/03`〜`06` | 実際の検証過程で使用した追補SQLの保存版 |
| `docs/` | データ出典、地図設定、検証結果、ブログとの対応 |
| `tests/` | Pythonの小さな入力と異常系の確認 |

## 1. 前提とデータの入手

- Python 3.10以降、SQLclまたはSQL*Plus。
- 作成済みのAutonomous AI Lakehouseと組み込みSpatial Studio。SQLとGUIは同じDB・`SPATIAL_USER`に接続します。
- SQLcl/SQL*Plusは接続済みの専用セッションから実行します。認証情報はファイルへ保存しません。
- SDO_NNの対応条件は[公式資料](https://docs.oracle.com/en/database/oracle/oracle-database/26/spatl/sdo_nn.html)を確認してください。Autonomous環境ではOracle JVM有効化の前提が記載されています。自動で設定変更するコードはありません。

データのダウンロード先・26メッシュの一覧・対象版は[data_sources.md](docs/data_sources.md)に記載しています。

1. 元の日本語ヘッダーの照明灯CSVを`data/raw/lighting_source.csv`として置きます。Excelで加工した英語ヘッダーのCSVは入力しません。
2. 海岸線の一括ZIPを`data/raw/gsi_coastline.zip`として置きます。
3. 最新データで件数が変わる場合があります。本セットのSQLは271設備・4,991入力線の検証を再現するため、異なる件数では停止します。件数や除外IDのガードを機械的に外さず、変更後のデータを再評価します。

## 2. CSVとGeoJSONを生成する

リポジトリ直下で実行します（macOS/Linuxの例）。

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python prepare_lights.py data/raw/lighting_source.csv --output data/generated/lights_shimoda.csv
python unpack_gsi_zip.py data/raw/gsi_coastline.zip --output data/generated/gsi_coastline
python convert_gsi_coastline.py data/generated/gsi_coastline --output data/generated/coastline_wgs84.geojson
```

確認値はCSV 271行、GeoJSON 4,991地物です。`.audit.json`と`.manifest.json`も保存してください。ZIP展開先が空でなければ停止するため、再展開時は新しいフォルダを指定します。CSV・GeoJSONの出力は同名ファイルを置き換えるため、過去の出力は別名で保存します。

`ASSET_ID`は`SZ20231004-000001`形式です。元CSVの行番号から生成するため、同じスナップショット内でのみ固定キーとして使います。元CSVを並べ替えて再生成したり、別年度のCSVと同一設備をIDだけで結合したりしないでください。

## 3. ユーザー設定とSpatial Studioへの取り込み

1. ADMINでDatabase ActionsのDatabase Usersから`SPATIAL_USER`を作成し、DATA表領域のクォータとWeb Accessを設定します。パスワードはGUIで入力します。
2. ADMINのSQLセッションで`@sql/00_spatial_user.sql`を実行します。既存のデフォルトロールを保ってSPATIAL_AUTHORを追加します。
3. `SPATIAL_USER`として再接続します。

```sql
SELECT GRANTED_ROLE, DEFAULT_ROLE FROM USER_ROLE_PRIVS WHERE GRANTED_ROLE='SPATIAL_AUTHOR';
SELECT ROLE FROM SESSION_ROLES WHERE ROLE='SPATIAL_AUTHOR';
```

`YES`と、セッションの`SPATIAL_AUTHOR`を確認します。

4. Spatial Studioで`Create dataset` → `Local file` → ファイル選択 → `Create` → プレビュー確認 → `Submit`と進めます。

| ファイル | 取り込み先の表名 | データセットキー |
|---|---|---|
| `lights_shimoda.csv` | `LIGHTS_SHIMODA` | `ASSET_ID` |
| `coastline_wgs84.geojson` | `COASTLINE_WGS84` | `COAST_ID` |

接続はログイン先の既定接続（今回の画面名は`DEFAULT_CONNECTION`、資料では`MY_DEFAULT_CONNECTION`）。CSVはUTF-8、LATITUDE/LONGITUDEは数値、ASSET_IDは文字列にします。キーが未認識なら`Use as Key` → `Validate key` → `Apply`。照明灯は`Create Latitude/Longitude Index`で緯度LATITUDE・経度LONGITUDEを設定します。

海岸線の空間列が`GEOM`であることを確認してください。別名の場合はSQLの参照列も合わせます。`COASTLINE_WGS84`は原データの保存用として保持します。

## 4. 初回SQLの実行

**修復前のCOASTLINEや距離表が既にある環境では実行しません。** 今回の新規作成SQLは既存表を自動削除・上書きしません。

SQLcl/SQL*Plusをリポジトリ直下から起動し、`SPATIAL_USER`として接続して、1ファイルずつ実行します。

```sql
@sql/01_setup.sql
@sql/02_repair_candidates.sql
@sql/03_calculate_and_verify.sql
@sql/04_publish_results.sql
@sql/05_verify_results.sql
```

| 段階 | 確認する結果 |
|---|---|
| 01 | LIGHTS 271件、COASTLINE_SOURCE 4,991件 |
| 02 | UNCHANGED_VALID 4,520件、REPAIRED_VALID 458件、残り13件 |
| 03 | 有効線4,978件、距離271件、除外影響3,523組が合格、`VERIFICATION_PASSED` |
| 04 | COASTLINE、LIGHT_COAST_METRICS、V_LIGHTS_COASTの作成完了 |
| 05 | 海岸線4,978件・不正0件、距離271件・欠損0件、区分36/46/57/132件 |

エラーが出たら止まり、ログを確認します。DDLは暗黙コミットされるため、ROLLBACKで作成済み表は消えません。同じファイルをそのまま再実行しないでください。GUIのDatabase ActionsではSQLcl用のSET/SPOOL等を除き、SQL/PLSQL単位で手動実行します。エラー後に自動継続しない点を守ります。

### 修復と除外の扱い

- 許容値内の連続頂点で13356が返った線に対して、3頂点以上なら重複頂点除去を試し、再検証します。
- 2頂点の線12件と、修復後にも有効線にならなかった1件は別に保持します。
- 残る13件について、元の頂点から線の広がりの保守的上限を計算し、全271設備で除外影響を確認します。不正な線を点へ置換して距離計算に混ぜません。
- 13件の除外が妥当だったのは今回の設備・取得範囲に対してです。設備を増やす・移動する場合は再検証します。
- 原形状のCOASTLINE_SOURCE、候補表、検証表を残します。最終計算用COASTLINEは検証後に作成します。

## 5. 色分けとクリック時の属性表示

[Spatial Studio設定手順](docs/spatial_studio.md)に詳細があります。

- `V_LIGHTS_COAST`をデータセット化し、キーをASSET_ID、空間列をGEOMにします。
- プロジェクトに追加したうえで地図へ追加し、元のLIGHTS_SHIMODAレイヤーは非表示にします。
- `Settings` → `Style` → Render style=`Symbol` → Color=`Column with color codes` → Column=`MAP_COLOR`。
- `Configure`を`Interaction`へ変更し、`Show info window`をONにして表示列を追加します。
- 背景を`MapTiler Bright`へ変更し、表示を確認して`Save`します。
- 修復後の海岸線を重ねる場合は`COASTLINE`（キーCOAST_ID）を別途データセット化します。

## 6. 次回用CSVとローカルテスト

```sql
@sql/06_export_results.sql
```

SQLclの出力先は`data/generated/lights_with_coast_distance.csv`です。再実行は同名CSVを置き換えます。SQL*PlusまたはDatabase Actionsの場合は、同ファイル中のSELECTの結果をCSVとして保存します。

```bash
python -m unittest discover -s tests -v
```

## 結果の意味と再利用

距離は、取得した海岸線の線形状までの楕円体上の最短距離です。種別「その他」もCstlineの一部として含みます。道路移動距離・塩害判定・現地測量値を意味しません。照明灯CSVの測地系は提供元情報だけでは確定できず、WGS84とみなす試行条件です。取得範囲の拡大比較は未実施です。

補助コードはOracle・静岡県・国土地理院の公式配布物ではありません。第三者データの利用条件は各提供元の規約に従ってください。本セットにはコードの再配布ライセンスを指定していません。公開者が採用するライセンスを決めた場合にLICENSEを追加してください。
