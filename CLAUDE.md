# Danmaku(DDA)— 作業メモ

osu! の譜面(`.osz`)を弾幕よけゲームにする Godot 4.7.2(GDScript)のアプリ。ドキュメント・コメント・コミットメッセージは日本語。

## コンテキストを節約する決まり
- **ドキュメントは全部読まない**。下の表で話題のファイルを選び、`grep -n '^#'` で見出しを見てから、必要な節だけ読む。
- **大きなスクリプトは丸ごと読まない**。`grep -n '^func '` で関数の位置を出してから、`offset` / `limit` で読む。
  - `scripts/main.gd`(約 1,200 行): 画面遷移の本体。**確認用の起動(`_smoke_*` / `_shot*` / `_prof*`、約 4,300 行)は `scripts/main_dev.gd`**(`main.gd` を継承。`main.tscn` が付けるのは、こちら)。確認の関数は `_dev_start` の引数の分岐から呼ばれる。触る確認の関数だけ読む。新しい確認は `main_dev.gd` に足し、`_dev_start` に分岐を足す。
  - `scripts/ui/lazer/lazer_menu.gd`(約 3,000 行)、`scripts/game/game_screen.gd`(約 2,700 行)も同じ。
- **テストの出力は絞る**。失敗は `FAIL: …`(stderr)、最後に `RESULT: OK` / `RESULT: <n> FAILURES`、終了コードも 0 / 1。
  例: `godot --headless --path . --script tests/test_gauge.gd 2>&1 | grep -E 'FAIL|RESULT|ERROR' | tail -n 30`
- `git log` は `--oneline` で見る(コミットメッセージは長い)。
- **Godot の起動ログは、必ず絞る**。`--shot` / `--smoke*` の起動は、終了時に RID リークなどの長いエラーを出す。`2>&1 | grep -E 'SCRIPT ERROR|ERROR|saved|FAIL|RESULT' | head -n 20` のようにする(`SCRIPT ERROR` の前後の呼び出し順が要るときだけ `-A 6`)。
- **画面の確認の画像**は、必要なときだけ撮る。細部が要らなければ縮小する(Read は画像をそのまま読むので重い)。読み取れる文字だけなら、画像でなく `--smoke*` の出力で確かめる。
- **広い調べもの**(「どこで使っているか」を何十ファイルも探す・全体の洗い出し)は、結論だけ返る別のエージェントに任せる。小さな調べは grep で足りる。
- 長い 1 行(`docs/*.md` の説明文など)を grep すると、その 1 行が全部出る。`grep -n … | cut -c1-200` で切る。

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
| サバイバルモードの計画(**実験的**。遊び方・数字は変わる) | `docs/survival_plan.md`(約 26KB) |
| lazer 風 UI の計画(当時のメモ。今の仕様は `docs/ui_lazer.md` / `docs/ui.md`) | `docs/ui_plan.md`(約 25KB) |

`docs/ui.md`(約 30KB)・`docs/gameplay.md`・`docs/pattern_v2.md` は大きい。見出しを引いてから読む。計画書(`*_plan.md`)は、その機能を作り直すときだけ読む。

`README.md` は概要と、この表と同じ索引だけ。**機能を変えたら、README ではなく該当する `docs/*.md` を更新する**(新しいテスト・確認用の起動は `docs/testing.md` にも足す)。

## よく使うコマンド
**この PC(Windows)では `godot` は PATH にない。** WinGet の実行ファイルを呼ぶ(bash から):
```bash
G="$LOCALAPPDATA/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe"
```
(`run.bat` は、ウィンドウ版の `Godot_v4.7.2-stable_win64.exe` を使う。ログを読むときはコンソール版。)以下の `godot` は、この `"$G"` のこと。
- 起動: `godot --path .`(`--ui lazer` / `--ui classic` で UI を指定)
- ヘッドレスのテスト: `godot --headless --path . --script tests/<name>.gd`
- 実際の画面での確認: `godot --path . -- [--ui lazer] --smoke-<name>`(ウィンドウが開く。一覧は `docs/testing.md`)
- **ウィンドウの出る確認は、サブモニターで動かす**(メインでは作業の邪魔になる)。**Godot の引数 `--screen 0` を、`--path` の前に付ける**: `"$G" --screen 0 --path . -- --smoke-title`(この PC は、サブ = 画面 0・メイン = 画面 1)。付けなくても、アプリが起動直後にサブへ移すが、最初の一瞬はメインに出る。`-- --screen <番号>` で、移す先を変えられる。
- **確認用の起動は、音量 0**(写しの dev_settings.cfg だけ 0 にする。使う人の設定は変わらない)。音を確かめるときは `-- --sound`。
- 画面写真: `godot --path . -- --ui lazer --shot menu out.png [finder]`。**`--` を忘れない**(忘れると、確認ではなく普通のアプリが起動し、写真は撮れず、設定も触る)。
- `python` は使えない(Windows のストアの空の入口で、終了コード 49 になる)。補助の処理は bash か GDScript で書く。

## 確認用の起動と設定
- `--smoke*` / `--shot*` / `--prof*` の起動と、`Settings` を使うテストは、**本物の `settings.cfg` ではなく、その写し `user://dev_settings.cfg` を読み書きする**(`Settings.use_dev_file()`)。途中で止めても、使う人の設定は壊れない。新しい確認・テストが設定を書き換えるときは、これを呼ぶ。
- ユーザーデータは `%APPDATA%\Godot\app_userdata\Danmaku\`(ワークツリーでも共通)。設定・曲の索引・osu! の Songs の指定は、全ワークツリーで共有される。
- `.osz`(曲)は git に入れない。**git のワークツリーで動かすと、元のリポジトリの直下と `songs/` も探す**(`SongLibrary.main_checkout_root`)ので、新しいワークツリーでも曲が空にならない。

## 慣習
- 版を上げるときは `project.godot`(`config/version`)・`export_presets.cfg`・`build.bat`(zip 名)・`docs/ui.md`(タイトルの版の表示)・`docs/distribution.md`(ベータ版の版)・`dist_files/README.txt` をそろえる。
- `build.bat` / `run.bat` は ASCII のみ・CRLF(`.gitattributes`)。ほかは LF。
- 新しいスクリプトの `.uid` もコミットする。
