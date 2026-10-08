# Danmaku(DDA)— 作業メモ

osu! の譜面(`.osz`)を弾幕よけゲームにする Godot 4.7.2(GDScript)のアプリ。ドキュメント・コメント・コミットメッセージは日本語。

## コンテキストを節約する決まり
- **ドキュメントは全部読まない**。下の表で話題のファイルを選び、`grep -n '^#'` で見出しを見てから、必要な節だけ読む。
- **大きなスクリプトは丸ごと読まない**。`grep -n '^func '` で関数の位置を出してから、`offset` / `limit` で読む。
  - `scripts/main.gd`(約 5,200 行): 本体は前半の約 1,200 行。**後ろの約 4,000 行は確認用の起動(`_smoke_*` / `_shot*` / `_prof*`)**。触る確認の関数だけ読む。
  - `scripts/ui/lazer/lazer_menu.gd`(約 3,000 行)、`scripts/game/game_screen.gd`(約 2,700 行)も同じ。
- **テストの出力は絞る**。失敗は `FAIL: …`(stderr)、最後に `RESULT: OK` / `RESULT: <n> FAILURES`、終了コードも 0 / 1。
  例: `godot --headless --path . --script tests/test_gauge.gd 2>&1 | grep -E 'FAIL|RESULT|ERROR' | tail -n 30`
- `git log` は `--oneline` で見る(コミットメッセージは長い)。

## ドキュメントの地図(`docs/`)
| 話題 | ファイル |
|---|---|
| 曲の置き場所・osu! の Songs フォルダ・URL / 探す・.osz の取り込み | `docs/songs.md` |
| タイトル・選曲・設定・ポーズ・操作・画面の動き・音量 | `docs/ui.md` |
| UI セット(クラシック / lazer 風)・上のプレイヤー・プレイリスト | `docs/ui_lazer.md` |
| ゲージ・ダメージ・弾幕の対応・危険エリア・スコア・休憩・クリア | `docs/gameplay.md` |
| 難易度(Lv)の式・SIZE_EXP / SPEED_EXP・弾速の実験 | `docs/difficulty.md` |
| MOD・撃破(ボス) | `docs/mods.md` |
| 弾幕 v2・特殊エリア | `docs/pattern_v2.md` |
| HUD・弾・キアイ・自機の見た目 | `docs/visuals.md` |
| リプレイ | `docs/replay.md` |
| 効果音・音作りのツール(`tools/`) | `docs/sfx.md` |
| マルチプレイ | `docs/multiplayer.md` |
| アプリ内アップデート・配布・ビルド | `docs/distribution.md` |
| コードの構成・1000 Hz の判定 | `docs/architecture.md` |
| テストと `--smoke*` の全一覧 | `docs/testing.md` |

`README.md` は概要と、この表と同じ索引だけ。**機能を変えたら、README ではなく該当する `docs/*.md` を更新する**(新しいテスト・確認用の起動は `docs/testing.md` にも足す)。

## よく使うコマンド
- 起動: `godot --path .`(`--ui lazer` / `--ui classic` で UI を指定)
- ヘッドレスのテスト: `godot --headless --path . --script tests/<name>.gd`
- 実際の画面での確認: `godot --path . -- [--ui lazer] --smoke-<name>`(ウィンドウが開く。一覧は `docs/testing.md`)

## 慣習
- 版を上げるときは `project.godot`(`config/version`)・`export_presets.cfg`・`build.bat`(zip 名)・`docs/ui.md`(タイトルの版の表示)・`docs/distribution.md`(ベータ版の版)・`dist_files/README.txt` をそろえる。
- `build.bat` / `run.bat` は ASCII のみ・CRLF(`.gitattributes`)。ほかは LF。
- 新しいスクリプトの `.uid` もコミットする。
