# ローカルでの確認結果（2026-11-17）

## パッケージ作成時の検証記録

以下は受領したパッケージに記載されていた結果です。公開準備時に実データを再取得・再生成したものではありません。

- Python 3.12.14、pyproj 3.8.0。
- unittest 6件成功（CSVの抽出と行番号保持、数値不正の除外、英語ヘッダー拒否、二重ZIPと再展開拒否、GMLの軸順序・線分分離・重複点除去、不明測地系拒否、3D拒否を6テスト内で確認）。
- 実CSVから271行、座標不正除外0行、LIGHT_TYPE欠損22行を再生成。既存の確認済みlights_shimoda.csvとバイト一致。
- 実ZIPを展開し26個の内側ZIP・52 XML・26 Cstline XMLを確認。
- GeoJSONを4,991地物へ再生成。COAST_ID一意4,991、海岸線4,817・その他174、全件LineString、座標の並びを確認。
- Python構文、ローカルMarkdownリンク、公開対象ファイル構成を確認。
- SQLの表名・処理順を静的に確認。Oracle DB接続は行っていないため、公開用初回SQLとCSV出力SQLの実機実行成功は主張しない。

## GitHub公開準備時の追加確認

- Python 3.14.3の仮想環境に`requirements.txt`をインストール。PyPI接続がタイムアウトしたため、端末内のpipキャッシュにあるwheelのRECORDハッシュを照合して使用（pyproj 3.8.0、certifi 2026.10.23）。`python -m pip check`成功。
- `python -m unittest discover -s tests -v`で7件成功。小さな合成入力のみを使用。
- Python 3.11.14では、入れ子ZIPの名前が`...zip`のとき、指定した展開先の親ディレクトリへXMLが書き出される不具合を再現。安全でないZIP名をファイル書き出し前に拒否するよう修正し、回帰テストの修正前の失敗・修正後の成功を確認。通常のZIP展開手順・出力形式は変更していない。
- Python構文、ローカルMarkdownリンク、MANIFESTのファイル一覧・SHA-256を照合。修正ファイルのMANIFESTハッシュを更新。
- 公開対象27ファイルを確認し、認証情報・ウォレット・`.env`・ログ・元CSV/ZIP・生成CSV/GeoJSON・私用ファイルを含めていない。`data/raw`と`data/generated`は`.gitkeep`のみ。仮想環境とアップロード依頼文はコミット対象外。
- README、`sql/`、`legacy/`の内容は変更していない。初回SQLと実行済み追補SQLの区別、および初回SQLのOracle実機通し実行が未確認である旨を保持。LICENSEは追加していない。
- 今回はOracle DB接続・SQL実行・クラウド設定変更・実データのダウンロード／再生成・Spatial Studioの画面操作を行っていない。
