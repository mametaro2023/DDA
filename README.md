# Danmaku

osu! の譜面データ(`.osz`)を、弾幕よけゲームに変換して遊ぶアプリです。譜面のヒットオブジェクトから弾幕を発射します(Godot 4)。

> **非公式のファンメイド作品です。** osu! および ppy Pty Ltd とは関係がなく、承認も受けていません。「osu!」は ppy Pty Ltd の商標です。曲・譜面は同梱していません(権利は、それぞれの制作者にあります)。

**ゲージ制**: 弾に当たっている間は継続ダメージを受けます。満タンは 250ms ぶんの被弾で、ゲージ 20% 以下では被ダメージが半分になります(連続して当たり続けると約 300ms でゲージ 0 = ゲームオーバー)。当たっていないときは毎秒 1.5% だけ回復します。MOD「練習」を付けるとゲージが 0 でも続行します(ベーススコア ×0.5)。

## 起動と画面の流れ
`run.bat` をダブルクリック、または `godot --path .`。起動するとまず**タイトル画面**が開きます(画面と操作は [docs/ui.md](docs/ui.md))。
曲(`.osz`)は、プロジェクト直下 / `songs/` / 実行ファイルの隣(と、その `songs/`)/ ユーザーデータ内の `songs/` に置くと一覧に出ます。ウィンドウへのドラッグ&ドロップでも追加できます(osu!standard のみ対応。詳しくは [docs/songs.md](docs/songs.md))。

## ドキュメント
詳しい仕様と実装のメモは、話題ごとに `docs/` に分けてあります。

| ファイル | 内容 |
|---|---|
| [docs/songs.md](docs/songs.md) | 曲の置き場所・osu! の Songs フォルダ・曲がないときの入口(URL・探す)・.osz の取り込み |
| [docs/ui.md](docs/ui.md) | タイトル・選曲・設定・ポーズ・操作・画面の動き・音量・選曲の軽さ |
| [docs/ui_lazer.md](docs/ui_lazer.md) | UI の見た目(クラシック / lazer 風)・上のプレイヤー・プレイリスト |
| [docs/gameplay.md](docs/gameplay.md) | ゲージとダメージ・弾幕の対応・弾と自機の大きさ・危険エリア・スコア・休憩・クリア・ゲームオーバー |
| [docs/difficulty.md](docs/difficulty.md) | 難易度(Lv)の計算・本家★に近づける仕組み・弾速の実験 |
| [docs/mods.md](docs/mods.md) | MOD の一覧と効果・ベーススコア・撃破(ボス) |
| [docs/pattern_v2.md](docs/pattern_v2.md) | 弾幕 v2(モチーフ・弾速・スピナー)・特殊エリア |
| [docs/visuals.md](docs/visuals.md) | HUD・弾・キアイの光・自機の見た目 |
| [docs/replay.md](docs/replay.md) | リプレイ(記録・再生・シーク・一覧・動画出力) |
| [docs/sfx.md](docs/sfx.md) | 効果音と音作りのツール |
| [docs/multiplayer.md](docs/multiplayer.md) | マルチプレイ(つなぎ方・ロビー・同期) |
| [docs/distribution.md](docs/distribution.md) | アプリ内アップデート・配布(ビルド・同梱物) |
| [docs/architecture.md](docs/architecture.md) | コードの構成・処理と描画の分離(判定は 1000 Hz) |
| [docs/testing.md](docs/testing.md) | テスト・確認用の起動(`--smoke*` など)の一覧 |
| [docs/ui_plan.md](docs/ui_plan.md) | lazer 風 UI の計画(当時のメモ) |
| [docs/survival_plan.md](docs/survival_plan.md) | サバイバルモードの計画(実験的。遊び方・数字は変わる) |

## ライセンス
ソースコードは MIT ライセンス(`LICENSE`)。ゲームは Godot Engine(MIT)で作られています(`dist_files/LICENSE-Godot.txt`)。**曲・譜面(.osz)は同梱しておらず、権利はそれぞれの制作者にあります。**
