# UI 刷新 設計計画(窓口と契約)

状態: **実装済み(2026-10-03 時点)。下の「実装の結果」を参照。** 以降の §1〜§7 は、実装前の計画(経緯として残している)。
目的: 既存の UI(以下「classic」)を残したまま、osu! lazer 風の別 UI(以下「lazer」)を並べて作れるようにする。
ゲームシステム(`GameSim` / `PatternGen` / `BulletField` / `Boss` / `Mods` / `net.gd` / `mp_game.gd` / `osu/*`)は変えない。

## 実装の結果(計画との違い)

| 計画 | 実装 |
|---|---|
| P1 窓口 | `ui_set.gd` / `classic_ui.gd` / `ui_sets.gd`。画面の `kind`、`on_overlay`、`can_accept_auto_update`、`open_panel`、`is_paused`、`own_settings_button`。`main.gd` のクラス判定は `kind` へ。起動オプション `--ui`、設定 `ui_style` |
| P2a `SongBrowser` | `scripts/song_browser.gd`。classic の選曲画面は、状態への窓口(プロパティ)を介して使う(確認用のコードが読む名前は、そのまま) |
| P2a `AttractBackdrop` | `scripts/attract_backdrop.gd` |
| P2b HUD の切り出し | **やめた**: `GameScreen` の進行は動かさず、HUD の描画部分だけを、サブクラス `lazer/lazer_game.gd`(`extends GameScreen`)が上書きする形にした。classic の `GameScreen` は変更なし(退行のリスクが最小) |
| P2c `LobbyLogic` | **やめた**: `MultiScreen` の背景だけを `_build_backdrop()` として切り出し、`lazer/lazer_multi.gd`(`extends MultiScreen`)が背景・ツールバー・戻るボタン・パネル・ボタンを差し替える。部屋の処理は classic のものを共用 |
| (新規) | `ResultModel`(リザルトの中身)、`RankStamp`(ランクの演出)を切り出し、classic と lazer で共用 |
| (新規) | `UiStyle` の色・フォントを `set_palette` で差し替え可能に(classic の値は不変)。lazer のあいだは、未作成の部品(遊び方・MOD・終了確認・更新)も lazer の配色で描かれる |
| P3 土台 | `lazer/lazer_style.gd`(色・フォント・テーマ)、`lazer_chrome.gd`・`lazer_frame.gd`(ツールバー・フッター・背景・側面パネル・トグル・スライダー)、`lazer_button.gd`(斜めのボタン)、`lazer_icons.gd`(線画のアイコン)、`lazer_logo.gd`(ロゴ) |
| P4 画面 | タイトル・選曲・プレイ(HUD)・リザルト・マルチ(入口とロビー)・設定・遊び方・MOD・確認・更新を lazer 風に。パネルは classic のパネルを継承し、中身の処理はそのままで見た目だけを差し替える(遊び方 = 設定と同じ左の縦長パネル `lazer_howto.gd`、MOD = 下からせり上がる札のシート `lazer_mods.gd`、確認・更新 = 丸いアイコンつきのダイアログ `lazer_dialog.gd` / `lazer_quit.gd` / `lazer_update.gd`)。プレイ中の休憩のカウントダウン・ボスのゲージと WARNING(`lazer_boss_gauge.gd`)・ボーナスタイムも lazer 風 |
| P5 切り替え | 設定の「画面」に、UI の見た目の選択を追加(選ぶと、タイトル・選曲はすぐ作り直される)。既定は classic(**lazer を既定にする時期は未定**) |
| P6 記録・検索・並び替え | `scripts/records.gd`(`user://records.json`)、`SongBrowser` の `view()`(検索・並び替え。記録を使う「ランク」順もある)・`chart_view()`(「難易度」順。曲ではなく譜面ごとに並べる)。lazer 風の選曲に反映(classic の選曲画面には、まだ出していない) |

`UiSet` の契約に `make_howto` / `make_mods` / `make_quit` を追加(`tests/test_ui_contract.gd` が両方の UI セットで確かめる)。マルチ画面の確認パネルは `_make_confirm()` で差し替える。

選曲(lazer): 曲の行は画像の背景 + 難易度の色の札、選んだ曲の下に難易度の一覧が開く。画像と難易度の色は `scripts/song_art.gd`(別スレッドで作って user:// に保存)。曲名は `lazer_marquee.gd` で流す。並び替えは行が滑って入れ替わる。
止まり対策: lazer のフォントに日本語の代替フォントを明示(OS のフォント探しを毎回走らせない)、タイトルの曲は別スレッドで読む(`AttractBackdrop.pick_async`)、遊び方のページは開いたときに作る。測り方は `--prof-ui` と `--hitch`。

main(v0.10.1)の取り込み(2026-10-04): classic の選曲画面は main のもの(osu! の Songs・弾幕 v2・v2 で遊ぼう・戻ったとき真ん中)をそのまま使い、`kind` / `on_overlay` だけを足した(SongBrowser には載せ替えていない)。
lazer の選曲は `SongBrowser` に同じ機能を移した: 曲の一覧の索引(何千曲でも速い)・osu! の Songs の曲を少しずつ足す(`pump`)・弾幕 v2 の弾幕と読み直し(`reload_for_style`)。確認は `--smoke-osu-menu`(classic / lazer の両方)。

未着手・今後の候補: classic の選曲画面への検索・記録の表示 / classic の選曲画面を SongBrowser に載せ替える(今は lazer だけが使う)/ 曲が何千あるときの lazer の行(全部作るので、開くのが重い)。

---

## 0. 前提と、決まっていること

| 項目 | 内容 |
|---|---|
| 範囲 | ゲームシステム以外は、すべて新 UI にする(メニュー、設定、プレイ中の HUD、リザルト、マルチプレイ) |
| 互換性 | ① classic を選べるまま残す ② 設定・記録・曲は共通 ③ 新旧 UI の人が同じ部屋で遊べる(通信は UI に依存しないので、取り決めは変えない) |
| 方向性 | osu! lazer 風(モック済み)。ロゴ・画像は osu! のものを使わず、レイアウトの文法だけ借りる |
| アリーナ | 960×720(4:3)固定。変えられるのは位置・周囲の装飾だけ(§5 の注意を参照) |

---

## 1. 現状の結合点(調査結果)

### 1.1 `main.gd` が画面の「正体」に依存している箇所

`main.gd` は画面を `get_script() == TitleScreen` のようにクラスで判定し、private 変数も直に触る。新クラスを置くと、ここが壊れる。

| 箇所(`scripts/main.gd`) | 内容 | 置き換え先 |
|---|---|---|
| 231, 248 | タイトルか判定 → `show_update()`、`t._overlay`、`t._leaving` を直接見る | `kind` と `can_accept_auto_update()` |
| 295, 1189 | ゲーム・マルチ中か判定(.osz の取り込みを抑える) | `kind` |
| 322 | 選曲か判定 → `refresh_songs()` / `select_path()` | `kind` |
| 386, 391, 581, 593 | 設定ボタンの出し分け。プレイ中の `_paused` を直接見る(F11) | `kind` と `is_paused()` |
| 396 | `OptionsPanel.new()` を直接作る | `UiSet.make_options()` |
| 399-410 | `_current.get("settings")`、`_current._options = p`、`set_process_input(false)` | `on_overlay(open)`(§2.3) |
| `show_*` 各関数(447-560) | `TitleScreen.new()` などを直接作る | `UiSet.make_*()` |
| 674-912(`_shot`)、スモークテスト | `_current._activate(2)`、`g._paused`、`m._page` など private 参照が約 240 箇所 | classic だけで動かす(§4) |

### 1.2 画面クラスに、ロジックが混ざっている箇所

| クラス | 行数 | 混ざっているもの | 扱い |
|---|---|---|---|
| `MenuScreen` | 約 1000 | 曲の走査、別スレッドでの読み込み(`_load_song`)、弾幕の生成・キャッシュ、難易度の再計算、試聴音声、`last_song` の保存 | **`SongBrowser` に切り出す**(§2.4) |
| `TitleScreen` | 約 390 | ランダムな曲の背景と BGM(`_play_random`) | 小さく切り出す(`AttractBackdrop`) |
| `MultiScreen` | 約 720 | 曲の解決(`_resolve_song`)、ダウンロード、開始条件(`_start_blocker`)、退出の確認 | **`LobbyLogic` に切り出す**(§2.4) |
| `GameScreen` | 約 2000 | 進行(クロック・sim・音・入力・ポーズ・リトライ・スキップ)と、HUD の描画・動きが同居 | **HUD だけを外に出す。進行は動かさない**(§2.5) |
| `ResultScreen` | 約 600 | `stats`(辞書)を読むだけ。ロジックは薄い | そのまま新 UI で作れる(辞書の形が契約) |
| `OptionsPanel` ほか | 約 470 | 設定の辞書を直接変更し、`changed(kind)` を出す | 同じ契約で別実装を作る |

### 1.3 すでに「窓口」になっているもの(そのまま使える)

- 画面は signal で `main` と話す(`play_requested`、`back_requested`、`finished` など)。
- 通信層は UI を知らない。`net.gd` の signal(`roster_changed`、`room_changed`、`prepare_game` など)と、`net.players` / `net.room` で読める。`mp_game.gd` は `rows()` / `draw_list()` でデータを返すだけ。
- 結果は辞書(`GameScreen._stats()`)で渡る。体力グラフは `hp_graph.gd`、ランク計算は `GameSim.rank_of`。
- 全ボタン・スライダーへの触り心地は `Juice` が自動で付ける(新 UI も `Button` を使えば自動で効く)。

---

## 2. 目標の構造

```
main.gd(画面の入れ替え・.osz・更新・設定の保存。UI の種類を知らない)
   │
   ├─ UiSet(窓口) ── classic: 既存クラスを返すだけ
   │                └─ lazer  : 新クラスを返す
   │
   ├─ 画面(Title / Menu / Multi / Game(HUD) / Result)  ← 契約(§2.3)を満たす
   ├─ パネル(Options / Mods / HowTo / Quit / Update)    ← 契約(§2.3)を満たす
   │
   └─ ロジック層(UI なし。どちらの UI も使う)
        SongBrowser / LobbyLogic / AttractBackdrop / GameScreen(進行)
        └─ ゲームシステム(変更しない): GameSim, PatternGen, BulletField, Boss, Mods, net, osu/*
```

### 2.1 UI セット(`scripts/ui/ui_set.gd`)

```
extends RefCounted
func id() -> String                       # "classic" | "lazer"
func make_title() -> Control
func make_menu(pick: bool) -> Control
func make_multi() -> Control
func make_game_hud() -> Node              # GameScreen に差し込む HUD(§2.5)
func make_result() -> Control
func make_options() -> Control
func make_mods() -> Control
func make_howto() -> Control
func make_quit() -> Control
func make_update() -> Control
```

- 現在の UI は `Settings` の新キー `ui_style`(既定 `"classic"`)で決める。`UiSets.current()` が返す。
- `Settings.save_all` は `DEFAULTS` のキーだけを書く(`settings.gd` 8 行目付近)ので、**キーを足しても古い版を壊さない**。
- 起動オプション `--ui classic|lazer` で、設定を上書きして撮影・確認ができるようにする。

### 2.2 スタイルの分離

- `UiStyle`(約 370 箇所から参照)は**変更しない**。classic の見た目をそのまま保つ。
- lazer 用に、別のスタイルクラス(色・フォント・部品: ピル、斜めのボタン、ツールバー、フッター、カルーセルの行)を新設する。`UiStyle.animate`(動きの ON/OFF)と、`pop_in` / `tween` / `spring` などの動きの道具は共用してよい(見た目に依存しない)。
- `CursorOverlay`、`ScreenWipe` は水色(`UiStyle.ACCENT`)を使っている。色を差し替えられる口を、フェーズ 3 で足す。

### 2.3 画面・パネルの契約

**全画面共通**

| 項目 | 契約 |
|---|---|
| `kind` | `"title" / "menu" / "multi" / "game" / "result"`。`main` が `show_*` で覚える(`get_script()` 判定をやめる) |
| `settings: Dictionary` | 持っていれば、`main` の設定パネルがこの辞書を直接編集する(今と同じ) |
| `on_settings_changed(kind)` | 任意。設定パネルで値が変わったとき |
| `on_overlay(open: bool)` | **新設**。パネルが開いた・閉じた。画面は入力を止める/戻す(今は `_options` を外から書き込み、`set_process_input` を外から呼んでいる) |

**画面ごと**

| 画面 | signal | 公開メソッド・変数 |
|---|---|---|
| Title | `play_requested`、`multi_requested`、`update_requested`、`settings_requested(section)` | `update_info`、`show_update(info)`、`can_accept_auto_update() -> bool`、`open_panel(panel)` |
| Menu | `play_requested(loader, bm, settings, pre)`、`back_requested`、`settings_requested(section)`、`song_picked(loader, bm, settings, level)` | `pick_mode`、`refresh_songs()`、`select_path(path)` |
| Multi | `back_requested`、`pick_song_requested` | `setup(net, notice)` |
| Game | `finished(stats, music)`、`quit_requested`、`retry_requested` | `setup(loader, bm, settings)`、`setup_multi(net, info, loader, bm, settings)`、`pre`、`is_paused() -> bool` |
| Result | `menu_requested`、`retry_requested` | `setup(stats, net)`、`skip_animation()` |

**パネル**(共通で `signal closed` と `close_panel()`)

| パネル | 追加の契約 |
|---|---|
| Options | `setup(settings)`、`signal changed(kind)`、`show_section(i)`、`refresh_size()` |
| Mods | `setup(settings, level_cb)`、`signal changed`、`refresh_info()` |
| Quit | `setup(title, ok, cancel, body)`、`signal confirmed` |
| Update | `setup(updater)`、`signal cancelled`、`auto_start` |
| HowTo | 契約は共通のみ |

**`stats` 辞書**(Result の入力。classic も lazer も同じものを読む)
`title, level, mean, peak, failed, progress, hits, hit_ms, damage, own_damage, score_gross, score_base, score, score_graze, score_boss_time, graze, mods, mod_ids, damage_factor, practice, bg, hp_log, hp_step, hp_end, hp_t_end, hit_log, breaks, first_fire, last_fire`、撃破時は `boss`、マルチ時は `mp`。形は `GameScreen._stats()`(`game_screen.gd` 859 行目付近)が正。

### 2.4 ロジック層

**`SongBrowser`(`MenuScreen` から切り出す)**
UI を持たない。`RefCounted` + signal。画面は購読して描くだけ。

- 状態: 曲の一覧、選択中の曲・難易度、弾幕(`gens`)と難易度(`ratings`、MOD 適用後)、読み込み中か、試聴用の音声、背景画像。
- 操作: `scan()`、`refresh()`、`add_path()`、`select_song(i)`、`select_diff(i)`、`set_mods(ids)`、`prepare_launch() -> {loader, bm, settings, pre}`。
- signal: `songs_changed`、`song_loading`、`song_loaded(info)`、`song_load_failed(error)`、`diff_changed`、`ratings_changed`、`preview_ready(stream, from)`。
- 移すもの: `_scan`〜`_add_song`、`_select_song` の別スレッド部分、`_load_song`(static)、`_gen_cache*`、`_rate_all`、`_on_song_loaded` の非 UI 部分、「前の難易度に Lv が近いものを選ぶ」「直前の曲・難易度に戻る」の規則。**ほぼそのまま移す(挙動は変えない)**。
- 注意: 画面が閉じられたあとに届く別スレッドの結果は、世代番号(`_job`)と `WeakRef` で捨てている。この仕組みは `SongBrowser` が引き継ぐ。

**`LobbyLogic`(`MultiScreen` から切り出す)**
曲の解決(`_resolve_song`)、ダウンロードの開始・進捗(`SongDownload`)、開始できない理由の判定(`_start_blocker`)、退出の確認の要否。`net` の signal を購読し、画面向けの signal に直す。

**`AttractBackdrop`(`TitleScreen` から)**
ランダムな曲と譜面の選択、背景画像の読み込み、BGM のフェード。タイトルの見た目とは独立。

### 2.5 プレイ中の HUD(いちばん難しい部分)

`GameScreen` は進行と見た目が混ざっている(約 2000 行のうち、HUD に関わるのは約 900 行)。

**方針: 進行(クロック・sim・音声・入力・MP)は `GameScreen` に残し、HUD だけを外へ出す。**
理由: クロック同期、1 ms 刻みの sim、ポーズの悪用防止、マルチの同期は壊れやすく、`tests/` と `--smoke-*` の確認も、`GameScreen` の private を前提にしている。ここを動かさなければ、退行のリスクが大きく減る。

- HUD の部品: 左右のパネル(曲情報・Lv・MOD・GRAZE・DAMAGE)、体力バーとその演出、スコア、READY / GO、ボスのゲージ、休憩のカウントダウン、ボーナスタイム、ループの案内、スキップボタン、ポーズのメニュー、リトライ長押しの輪、マルチの参加者一覧。
- HUD の契約(案):
  - `bind(host)`: `GameScreen` を渡す。HUD は `host.sim`、`host.gen`、`host.bm`、`host.settings`、`host._now` に相当する値を、**読み取り専用**で読む(公開用の getter を `GameScreen` に足す)。
  - `tick(delta)`: 毎フレーム。体力バーの残像・スコアのイージング・火花など、HUD 固有の動きはここで進める。
  - `GameScreen → HUD` の出来事: `on_graze`、`on_hit_started`、`on_death`、`on_outro`、`on_boss_defeated`、`on_item(kind, pos)`、`on_pause_changed(paused)`、`on_resume_wait(on)`、`on_skip_available(on)`、`on_retry_hold(progress)`。
  - `HUD → GameScreen` の操作: `resume()`、`request_retry()`、`request_quit()`、`skip()`(音量は `Volume` を直接触る)。
  - 配置: HUD が `arena_origin() -> Vector2` を返す。`GameScreen` はそれでアリーナの位置と、マウスの対応・カーソルの飛行を決める。
- 手順: ① classic の HUD を、コードの移動だけで `ClassicHud` に切り出す(挙動・見た目は同一) ② 契約が固まったら、`LazerHud` を作る。
- **着手前に小さな調査(スパイク)が必要。** ポーズ(`_set_paused`、`_resume_wait`、`_pause_cd`)は「状態機械(進行側)」と「メニューの見た目(HUD 側)」が絡み合っている。境界は、実際にコードを動かしながら決める。

---

## 3. 段階的な移行

各フェーズの終わりで、**classic が今までどおり動く**ことを確認してから次へ進む。

| # | フェーズ | 内容 | 規模 | 受け入れ基準 |
|---|---|---|---|---|
| P0 | 方向性の決定 | モック済み。§6 の未決事項に答える | - | 未決事項が決まる |
| P1 | 窓口 | `UiSet` と `ClassicUi`、`kind`、`on_overlay`、`can_accept_auto_update` などの契約をそろえ、`main.gd` の判定を置き換える。`ui_style` 設定と `--ui` を足す(lazer はまだ無い) | 小 | classic の見た目・挙動が変わらない(§4 の撮影比較) |
| P2a | `SongBrowser` | `MenuScreen` から選曲ロジックを切り出し、classic を載せ替える。`AttractBackdrop` も | 中 | 選曲まわりの確認が通り、撮影が一致する |
| P2b | `ClassicHud` | `GameScreen` から HUD をコード移動で切り出す(§2.5 の ①)。スパイク込み | 中〜大 | プレイの確認が通り、撮影が一致する |
| P2c | `LobbyLogic` | `MultiScreen` から切り出す | 小〜中 | マルチの確認が通る |
| P3 | lazer の土台 | スタイルクラス、部品(ツールバー、フッター、斜めのボタン、星のピル、カルーセルの行)、背景(画像を暗く)、フォント | 中 | 部品の見本画面で、モックと比べて方向が合っている |
| P4a | 選曲(最初の縦切り) | lazer の選曲を作る。`SongBrowser` を使う | 大 | classic と lazer を設定で切り替えて同じ曲が遊べる |
| P4b | タイトル | | 中 | |
| P4c | リザルト | `stats` を読む。体力グラフは `hp_graph.gd` を再利用 | 中 | |
| P4d | HUD | `LazerHud`(§2.5 の ②) | 大 | 全 MOD(特に撃破・暗闇)と、ポーズ・スキップ・リトライが classic と同じ動き |
| P4e | 設定・MOD・遊び方・終了・更新 | パネル群 | 大 | 設定の保存と反映が同じ |
| P4f | マルチプレイ | 入口とロビー。`LobbyLogic` を使う | 大 | 新旧 UI の組み合わせで部屋に入り、遊べる |
| P6 | 記録・検索・並び替え | 記録の保存(曲・難易度ごと)、選曲の検索と並び替えを `SongBrowser` の上に作り、classic と lazer の両方から使えるようにする | 中 | 保存・読み込み・並び替えのテストが通る |
| P5 | 切り替えと仕上げ | 設定画面に UI の選択を足す。既定は、lazer が classic と同等になるまで classic のまま。README を更新 | 小 | |

規模の目安: 小 = 数百行、中 = 約 1000 行、大 = 1500 行以上。

---

## 4. 検証の方針

「最後は大事なものだけ短く確認する」という方針に合わせ、全部を毎回は回さない。

1. **撮影の比較(P1〜P2 の主な安全網)。** 変更前に、classic の `--shot` を主な画面ぶん撮って保存しておく(title、title の howto/options/quit、menu、menu の MOD 付き・曲なし・読み込み中、game、result)。変更後に同じ撮影をして、画像が一致することを確認する。
2. **契約テスト(新設・小さく)。** 各 `UiSet` から各画面・パネルを作り、契約の signal とメソッドがあるかだけを確認する。classic と lazer の両方に効く。
3. **既存の確認は classic で。** `main.gd` の `--smoke-*` は private を参照するため classic 専用。各フェーズで、関係するものだけを選んで回す(選曲は `--smoke-ui`、プレイは `--smoke-start` / `--smoke-skip`、マルチは `--smoke-mp-ui` / `--smoke-mp` など)。
4. **lazer 用の確認。** 契約越しに書く短いもの(曲を選ぶ → プレイ → リザルト → メニューへ戻る)。
5. **新旧混在のマルチ。** `--smoke-mp` を、ホストが classic、参加者が lazer の組み合わせで 1 回(P4f)。

---

## 5. リスクと対策

| リスク | 対策 |
|---|---|
| `GameScreen` の分離で、クロックやポーズの挙動が壊れる | 進行は動かさず HUD だけを出す(§2.5)。HUD は読み取り専用で参照する。着手前にスパイク |
| `SongBrowser` の別スレッドで、画面が閉じたあとの結果が壊れる | 世代番号と `WeakRef` の仕組みを、そのまま移す。移した直後の撮影・読み込みの確認で見る |
| アリーナの縮小(モックの 90%)が、マウスの対応・カーソルの飛行・自機の HUD 退避に影響する(`ARENA_POS` が `game_screen.gd` に約 20 箇所) | **v1 は拡大率 1.0、位置の変更だけ**。縮小は P4d のあとの実験として、別に判断する |
| 日本語フォント(lazer 風の字体は、日本語を含まないものが多い) | 同梱するフォントを決める(サイズとライセンスを確認)。未決(§6) |
| `Juice` は `Button` / `Slider` にだけ効く | 新 UI の押せる部品は `Button` を土台にする。例外は `set_meta` で指定 |
| 新 UI の素材が `export_presets.cfg` の `include_filter`(今は `assets/sfx/*.sfx` のみ)に入らない | フォントや画像は通常のインポートで入る。生のファイルとして読むものを作る場合だけ、フィルタを足す |
| 古い版のユーザーが、`ui_style` を含む設定を読む | 古い版は `DEFAULTS` にないキーを無視する(`settings.gd`)。問題なし |

---

## 6. 決定事項(2026-10-03 回答)

1. **操作の配置:** README の「戻る = 左上 / 決定 = 右下」には従わない。lazer 式(上のツールバー、下のフッター)にしてよい。
2. **キー案内などの文字:** これまでどおり、操作の説明・キーの案内は「遊び方」の中だけに置き、ほかの画面には出さない。モックの「Enter でプレイ」は採用しない。
3. **点滅・フラッシュ・画面揺れ:** 使わない(新 UI でも守る)。
4. **フォント:** 任せる。方針: 標準フォント + OS のフォールバックを土台にし、あとから同梱を検討する(P3 で判断)。
5. **背景:** 曲の背景画像を暗く表示する。ぼかしは入れない。
6. **記録の保存・選曲の検索と並び替え:** 実装する。UI の刷新とは別の仕事として、`SongBrowser` の上に載せる(P6)。
7. **lazer を既定にする時期:** 未定。当面は classic が既定。
8. **アリーナ:** 縮小しない(拡大率 1.0。位置だけ)。
9. **ロゴ:** 作り込む(自作ロゴ。osu! のロゴは使わない)。2026-10-04: ゲームの名前を「Danmaku」に決定。副題(DANMAKU DODGER)は廃止し、ロゴは「Danmaku」の文字と、弾幕の扇・自機を描いた円盤に作り直した(`lazer_logo.gd`。クラシックのタイトルも「Danmaku」)。

---

## 7. 最初の一歩(P1)でやること

変更はごく小さく、見た目は変えない。

1. `scripts/ui/ui_set.gd` と `scripts/ui/classic_ui.gd`(既存クラスを返すだけ)を作る。
2. `Settings.DEFAULTS` に `"ui_style": "classic"` を足す。
3. `main.gd` の `show_*` を `UiSet` 経由に変え、`get_script() ==` の判定を `kind` に置き換える。
4. 各画面に `kind` と `on_overlay(open)` を足す(`_options` の外部書き込みと `set_process_input` の外部呼び出しをやめる)。`TitleScreen` に `can_accept_auto_update()` を足す。
5. 変更前後の撮影を比較して、一致を確認する。
