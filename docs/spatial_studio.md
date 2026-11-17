# Spatial Studioの表示設定

## 表示用ビューを登録する

1. `Datasets` → `Create dataset` → `Database table/view`。
2. 取り込み時と同じ既定接続から`V_LIGHTS_COAST`を選択。
3. `No key column was found`なら`Go to Dataset Columns` → `ASSET_ID`の`Use as Key` → `Validate key` → `Apply`。空間列は`GEOM`。
4. プロジェクトの`Add dataset`で追加し、さらに地図へ追加。データ一覧への追加だけでは地図レイヤーになりません。
5. `LIGHTS_SHIMODA`は非表示にし、重なった元の点で色が隠れないようにします。
6. 海岸線は修復済みの`COASTLINE`を別データセットとして追加できます。元の`COASTLINE_WGS84`は取り込み時の原形状です。

## 距離区分の色

地図のLayersにある`V_LIGHTS_COAST`のメニュー → `Settings`で設定します。

| 項目 | 設定 |
|---|---|
| Configure | Style |
| Render style | Symbol |
| Symbol | Single symbol（丸など） |
| Color | Column with color codes |
| Column | MAP_COLOR |

**ColorがSingle colorのままではColumnは表示されません。** Colorの右側の▼から方式を変更します。色見本をクリックする操作ではありません。列名の末尾にaは付きません。

| COAST_DISTANCE_BAND | MAP_COLOR |
|---|---|
| 01: 100m未満 | #D60 |
| 02: 100m以上500m未満 | #DA0 |
| 03: 500m以上1km未満 | #099 |
| 04: 1km以上 | #47A |
| 未計算 | #999 |

距離は丸めずに区分へ割り当てます。色コード指定では凡例が`Colored by MAP_COLOR`になるため、記事には上の表を併記します。これらは表示用区分であり、塩害・劣化の判定基準ではありません。

## クリック時に管理番号・距離を表示する

1. 同じレイヤーのSettingsで、`Configure`を`Style`から`Interaction`へ変更。
2. `Allow selection`と`Show info window`をON。
3. Available Columnsから以下の列を選び、上矢印でColumns to showへ追加。
4. 地図の色付きの点をクリックして表示を確認し、`Save`。

表示列：ASSET_ID、MANAGEMENT_NO、LOCATION_TEXT、LIGHT_TYPE、COAST_DISTANCE_M、COAST_DISTANCE_BAND。

マウスを乗せただけで表示するTooltipとは別設定です。小さい点をクリックしにくい場合は拡大するかSelection toleranceを調整します。

## 背景地図と保存

`Background` → Basemap → `MapTiler Bright`へ切り替えます。今回の画面では、粗い背景地図から切り替えると道路・護岸との対応が確認しやすくなりました。見た目の一致だけでメートル単位の精度を保証せず、背景に合わせて座標を手動補正しません。

Save後、SQLで値を更新した場合はプロジェクトを開き直し、ビューを再読込して確認します。

参考：
- https://docs.oracle.com/en/database/oracle/spatial-studio/26.1/spstu/styling-map-layer.html
- https://docs.oracle.com/en/database/oracle/spatial-studio/26.1/spstu/adding-interactions-map-visualization.html
