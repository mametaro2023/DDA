extends Node2D
## プレイ画面。曲クロックを音声に同期させ、GameSim を毎フレーム進める。

## music: クリアしたとき、鳴っている曲のプレイヤー(呼び出し側が引き継いで、リザルトでも流し続ける)。ゲームオーバーなら null
signal finished(stats: Dictionary, music: AudioStreamPlayer)
signal quit_requested
signal retry_requested
## リプレイ画面から、動画出力を頼む(main が、別のプロセスで書き出す)。opts: {w, h, fps, trail_mode, trail_sec}(空なら、書き出し中の中止)
signal replay_export_requested(data: Dictionary, opts: Dictionary)
## 動画出力の子プロセス: リプレイを最後まで流した(main が、続けてリザルト画面を撮る)。stats: リプレイの結果(背景つき)、music: 鳴り続けている曲(クリア。なければ null)
signal replay_export_finished(stats: Dictionary, music: AudioStreamPlayer)

const GameSim = preload("res://scripts/game/game_sim.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const PatternGenV2 = preload("res://scripts/game/pattern_gen_v2.gd")
const BulletField = preload("res://scripts/game/bullet_field.gd")
const ArenaView = preload("res://scripts/game/arena_view.gd")
const Settings = preload("res://scripts/settings.gd")
const Sfx = preload("res://scripts/game/sfx.gd")
const Mods = preload("res://scripts/mods.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Volume = preload("res://scripts/volume.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const UiFx = preload("res://scripts/ui/ui_fx.gd")
const CursorOverlay = preload("res://scripts/ui/cursor_overlay.gd")
const BossGauge = preload("res://scripts/ui/boss_gauge.gd")
const Boss = preload("res://scripts/game/boss.gd")
const MpGame = preload("res://scripts/net/mp_game.gd")
const SpeedStudy = preload("res://scripts/speed_study.gd")
const Replay = preload("res://scripts/replay.gd")
const Records = preload("res://scripts/records.gd")
const ReplayBar = preload("res://scripts/game/replay_bar.gd")
const ReplayDense = preload("res://scripts/replay_dense.gd")

const ARENA_POS := Vector2(160, 0)
## 体力バーの位置と大きさ(先端の火花の発生位置にも使う)
const HP_X := 188.0
const HP_Y := 28.0
## 撃破 MOD: 体力バーは左下へ(上部はボスのゲージ)。スコアは、ボスのゲージの下へずらす
const HP_Y_BOSS := 684.0
const SCORE_DY_BOSS := 52.0
## 撃破 MOD: ボーナスタイム(各周の最後のノーツのあと)の間に、曲をテープの早送りのように次の周の頭へ進める。
## 速さ(と音程)は sin の形で 1 → FF_PEAK → 1 倍に上がって下がり、いちばん速いところ(半分)で曲の位置を飛ばす(早送りの音にまぎれる)。
## 残り半分で進む分を見込んで飛ばすので、終わりに、ちょうど次の周の始まり(最初のノーツの GameSim.LOOP_LEAD 秒前)に着く。
const FF_PEAK := 6.0
const HP_W := 360.0
const HP_H := 16.0
const HP_SL := 12.0
const LEAD_IN := 1.5
## イントロのスキップ: 最初のノーツの SKIP_LEAD 秒前まで進める。進む幅が SKIP_MIN_GAIN 秒未満なら出さない
const SKIP_LEAD := 1.5
const SKIP_MIN_GAIN := 1.0
## 表示スコアのイージング: 目標値との差を毎秒この割合で詰める ease-out(1/RATE 秒ほどで大半が追いつく)
const SCORE_EASE_RATE := 9.0
## ゲームオーバーから結果画面へ移るまでの秒数(曲のテープストップ 1.7 秒・弾が消えるのを待ってから)
const END_DELAY_FAIL := 2.0
## プレイ中に R をこの秒数だけ押し続けると、すぐにリトライ(ひとりのときだけ)
const RETRY_HOLD := 0.6
## 休憩のカウントダウンの輪の半径
const BREAK_R := 62.0
## 判定・進行(GameSim)を進める刻み。描画のフレームレートとは独立に、ms 単位(1000 Hz)で当たり判定を行う。
## 1 フレームぶんの経過時間を、この刻みで割って(ceil)、その回数だけ sim を進める(60 fps なら 1 フレームで約 17 回)。
## 1 フレームで進める回数の上限(重い場面で処理が追いつかなくなったときは、刻みを粗くして時刻だけは合わせる)
const SIM_STEP := 0.001
const SIM_MAX_STEPS := 100
## 弾が多いとき、判定の刻みを広げる。1 ステップの処理は弾の数に比例して重く(4000 発で約 1.5ms)、1ms 刻みでは、1 フレームに十数回回すと間に合わずフレームが落ちる。
## 刻みは、弾 500 発までは SIM_STEP(1ms)で、増えるにつれて広げ、2000 発以上で SIM_STEP_MAX(4ms)。弾は 1 ステップで 1px も進まず(最大 250px/s × 4ms)、
## 自機の移動は線分で判定し、発射は遅れたぶんだけ進めて出すので、判定は変わらない(被弾の時間・グレイズの数は、刻みによらずほぼ同じ)。
const SIM_STEP_MAX := 0.004
## 曲クロックの補正: 音声とのずれを 1 秒あたりこの割合で詰める(小さいほど滑らか)。ずれが CLOCK_RESYNC 秒を超えたら直接合わせる
const CLOCK_PULL := 4.0
const CLOCK_RESYNC := 0.1
## クリア時、背景以外がフェードアウトする時間(この間も曲は流れ続ける)。そのあとリザルトへ
const OUTRO_TIME := 0.6
## 暗闇 MOD: 自機からこの距離までは弾が全部見え、DARK_FADE_R に向けてなめらかに薄れて、それより遠い弾は見えない(px)
const DARK_FULL_R := 60.0
const DARK_FADE_R := 150.0
## 低速にしている間は、可視範囲がさらにこの倍率まで狭まる(なめらかに出入りする)
const DARK_SLOW_SCALE := 0.55
## 自機が体力バー・スコアに近づいたときの透過: 自機の縁から HUD_FADE_DIST px 以内で薄れ始め、重なると不透明度 HUD_FADE_MIN まで下がる
const HUD_FADE_DIST := 90.0
const HUD_FADE_MIN := 0.14
## キアイ中の拍に合わせた光(背景の明るさ・下地の暗さ・弾の周りのハロー)。少しだけ光らせる。
const KIAI_BG_GAIN := 0.14        # 背景の画像の明るさが、光のピークで 1 + この値 倍まで上がる(僅かに)
const KIAI_SOFT := 0.3            # 目に優しい表示: 拍の光の振れ幅(拍ごとの明暗)を、この割合に抑える
const SOFT_BG_ALPHA := 0.76       # 目に優しい表示: フィールドの下地の不透明度(背景の絵を、より暗く沈める)
const KIAI_ARENA_DIM := 0.035     # フィールドの下地の不透明度が、光のピークでこれだけ下がる(僅かに)
const KIAI_BASE := 0.12          # キアイ中は、拍の合間でもこれだけ光っている(光の下限)
const BG_TINT := Color(0.28, 0.28, 0.32)
const ARENA_BG_ALPHA := 0.62
const TAPE_STOP_TIME := 1.7  # ゲームオーバー時に曲が止まるまでの秒数

## 画面の種類(main が、いま何の画面かを知るのに使う。ui_set.gd の契約)
var kind := "game"
var loader
var bm
var settings: Dictionary
## デバッグ: 指定秒まで進めて固定(音声なし)。スクリーンショット用。
var debug_seek := -1.0
## デバッグ: ゲームオーバー演出の経過秒を固定する(seek 中に死んだ場合のみ)。
var debug_death_t := -1.0

## マルチプレイ(setup_multi で設定。ひとりのときは null / 空)
var net
var mp_info: Dictionary = {}
var _mp
var _vol_rev := 0              # Volume.rev の見た目(変わったら効果音の音量を反映し直す)
var _mp_menu := false          # マルチプレイ中のメニュー(ゲームは止めずに重ねるだけ)
var _mp_box: VBoxContainer     # 左パネルの参加者一覧
var _mp_ids: Array = []
var _mp_rows: Dictionary = {}
## 開発用: 設定すると、キー入力の代わりに移動方向(Vector2)をこの関数から得る(ボット)
var debug_move := Callable()

var sim
var field
var gen: Dictionary

## リプレイ(scripts/replay.gd)。ひとり用のプレイは入力を記録して、終わりに保存する。replay_data が空でなければ、プレイではなく再生(setup_replay)。
var replay_data: Dictionary = {}
var replay_export := false     # 動画出力の子プロセス: 操作パネルなしで、先頭から 1 倍速で最後まで流して終わる(固定のフレーム時間で動く)
var replay_trail_mode := 1     # 再生: 自機の軌道 0 = 切 / 1 = 出す(過去 replay_trail_sec 秒)
var replay_trail_sec := 3.0
var _rec                       # Replay.Recorder(プレイ中の記録係。再生・マルチプレイ・開発用の確認では null)
var _rp                        # Replay.Player(再生の係。プレイでは null)
var _rt := 0.0                 # 再生の時計(いまの時刻 = シムを進める先)
var _rp_playing := true
var _rp_speed := 1.0
var _rp_bar
var _rp_ended_t := -1.0        # 再生が最後に着いてからの秒(動画出力は、少し余韻を撮って終わる)
var _rp_audio_key := ""        # 再生の音を合わせ直す目印(止める・倍速を変える・飛ぶと変わる)
var _rp_error := ""
var _rp_progress_t := 0.0
var _rp_fp := 0                # 弾幕の指紋(組み立てた直後の値。記録と再生で同じかを確かめる)
var _rp_scrub_resume := false  # 体力グラフのドラッグ中は止めて、離したら続ける
var _rp_hits := PackedFloat32Array()   # 被弾した時刻(「前の・次の被弾」へ飛ぶ)
var _rp_verified := false      # 最後まで流して、記録の結果と合っているかを確かめた
var _rp_state_l: Label         # 左のパネルの「再生中 / 停止中」
var _rp_dense                  # 追加のキーフレームを、裏で作る係(飛ぶときの待ちを減らす。replay_dense.gd)
var _view_l := 0.0             # 画面の左右の端(この画面の座標。再生で画面を縮めても、背景・赤みは画面いっぱいに出す)
var _view_r := 1280.0
var _view_b := 720.0
var _rp_stage_k := -1.0
var replay_seek_budget_ms := 10.0   # 飛ぶときの計算を、1 フレームに使ってよい時間(これを超えるぶんは、次のフレームへ)
var _rp_seek_to := -1.0          # 飛んでいる途中の目標(-1 = 飛んでいない)
var _rp_seek_from := 0.0
var _rp_seek_t0 := 0
var _mods: Dictionary   # 付けた MOD の効果(Mods.params)
var _rate := 1.0        # 譜面の再生速度(MOD)

var _arena: Node2D
var _audio: AudioStreamPlayer
var _sfx
var _view_under
var _view_over
var _now := -LEAD_IN
var _audio_started := false
var _paused := false
var _end_timer := -1.0
var _end_time := 0.0
var _mouse_mode := false
## いま木の中にあるプレイ画面の数(リトライでは、新しい画面が先に作られ、古い画面があとで消える)
static var _alive := 0
var _mouse_accum := Vector2.ZERO  # 未処理のカーソル移動量(相対)
var _guiding := false             # 開始の演出中: カーソルが自機の位置へ飛んでいる間(マウスの移動は自機に効かせない)
var _skip_btn: Button            # イントロのスキップのボタン(スキップできる間だけ出る)
var _skip_free := false           # スキップのボタンを押せるように、マウスを捕まえていない間
var _skipped := false             # スキップした(もう出さない)
var _debuff_l: Label              # 危険エリアのデバフの名前(左のパネル。盤面・自機には文字を出さない)
var _debuff_shown := ""
var _arrived := false             # 自機が現れて、操作が渡ったか
var _mouse_capture_ms := 0
var _dead := false
var _hit_glow := 0.0  # 被弾中の赤み(なめらかに減衰。点滅させない)
var _fx_regen := 0.0       # 体力バー先端の演出: 回復中の度合い(0..1。なめらかに出入り)
var _fx_break := 0.0       # 同: 休憩地帯で回復が止まっている度合い(0..1)
var _hp_flow := 0.0        # バーの上を流れる光の位置(回復中は速く、休憩中は止まる)
var _hp_ripple := 0.0      # 休憩中の先端の波紋の位相(0..1)
var _hp_spawn := 0.0       # 火花の発生の端数
var _hp_sparks: Array = [] # 先端から出る火花 {p, v, life, max, col, size}
var _hp_rng := RandomNumberGenerator.new()
var _low_vis := 0.0       # 体力が低いときの、画面の左右端の赤み(0..1。目標へなめらかに追従する)
var _gauge_ghost := 1.0  # 体力バーの残像(被弾で減った分がゆっくり縮む)
var _score_disp := 0.0   # 画面に表示しているスコア(sim.score へイージングで追従)
var _score_font: Font
var _death_t := 0.0
var _graze_l: Label
var _hit_l: Label
var _ui_time := 0.0        # プレイ画面が動いた時間(操作ヘルプを薄く消すのに使う)
var _center_label: Label
var _pause_layer: Control
var _pause_panel: PanelContainer
var _graze_pop := 0.0     # グレイズが増えたときの数字の弾み(1 → 0 へ減衰)
var _last_graze := 0
var _dark_scale := 1.0     # 暗闇 MOD の可視範囲の倍率(低速で DARK_SLOW_SCALE へ、なめらかに追従)
## 撃破 MOD: 右パネルのボスの欄(HP の割合・バー・攻撃力)と、前のフレームで見た状態(変わったときに音・演出を出す)
var _boss_gauge             # 上部のボスのゲージ(BossGauge)
var _weapon_ls: Dictionary = {}   # 右パネルの強化の段階(power / rate / wide → Label)
var _weapon_seen := ""
var _pick_seen := 0         # boss.pick_events をどこまで演出したか
var _boss_down_seen := false
var _hp_x := HP_X           # 体力バーの位置(撃破 MOD では左下)
var _hp_y := HP_Y
var _score_dy := 0.0        # スコアを下へずらす量(撃破 MOD)
var _loop_k := 0           # 撃破 MOD: 曲の再生がいま何周目か(曲クロック = 再生位置 ÷ rate + 周 × sim.loop_len)
var _ff_t := -1.0           # 撃破 MOD: 早送り(ボーナスタイム)の経過秒(-1 = 早送りしていない)
var _ff_jumped := false
var _break_a := 0.0       # 休憩のカウントダウンの表示度(なめらかに出入りする)
var _break_left := 0.0    # 休憩が終わるまでの残り秒
var _break_frac := 0.0    # カウントダウンの輪の残り割合(1 → 0)
var _break_sec := -1      # いま出している残り秒(整数。-1 = 数えていない)
var _break_pop := 0.0     # 数字が変わったときの弾み(1 → 0)
var _break_in := 0.0      # 輪が現れるときの伸び(0 → 1)
var _done := false        # リザルトへ渡した後(以降は何もしない)
var _outro_t := -1.0      # クリアのフェードアウトの経過秒(始まるまで -1)
var _bg_nodes: Array = [] # 背景(フェードアウトしない)
var _bg_tex: Texture2D    # 背景の画像(リザルトへ渡して、同じ背景を続ける)
var _sim_t := -LEAD_IN    # 判定側(GameSim)の時刻。_now に追いつくまで SIM_STEP 刻みで進める
var prof_on := false       # 開発用(--prof-frames): このフレームの処理時間の内訳を prof に残す
var prof := {}
var _prof_steps := 0
var _hit_any := false     # このフレームのどこかのステップで、弾に当たっていたか
var _hit_started := false # このフレームのどこかで、新しい被弾が始まったか
var _study_cond := ""   # 弾速の実験の条件(scripts/speed_study.gd)。実験しないときは空
var _sfx_pending: Array = []  # このフレームの発射音(まとめて鳴らす)
var _sfx_pending_pan: Array = []  # 同じ順の、左右の位置
var _left_col: Control
var _right_col: Control
var _pause_btns: Array = []
## ポーズで止めた弾を、じっくり観察してから再開する(連続ポーズ)悪用を防ぐ:
##   ポーズ中はアリーナを覆って、弾・自機を見せない / 「再開」のあとは、自機だけを見せて待ち(動かせない)、クリックか移動キーなどの操作で、
##   弾が RESUME_VEIL 秒かけて現れて動き出す / 動き出してから PAUSE_COOLDOWN 秒は、またポーズできない
const PAUSE_COOLDOWN := 2.0
const RESUME_VEIL := 0.35
const RESUME_KEYS := [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_A, KEY_D, KEY_W, KEY_S]
const PAUSE_ROWS := 6       # 再開 / リトライ / メニューへ / 全体音量 / 音楽 / 効果音
var _pause_cover: ColorRect   # ポーズ中、アリーナ(弾・自機)を覆う
var _resume_wait := false     # 「再開」のあと、使う人の操作を待っている(自機だけを見せている。ゲームは止まったまま)
var _resume_hint: Label       # 再開の待ちの案内(「クリックで再開」など)
var _retry_hold := 0.0        # R を押し続けている秒数(RETRY_HOLD でリトライ)
var _retry_armed := false     # R を一度離したか(ポーズ・結果画面の R でリトライした押しっぱなしで、また始まらないように)
var _retry_ui: Control        # R 長押しの進み具合の輪
var _wait_t := 0.0
var _wait_lock := 0.0         # 待ちに入った直後は、操作を受けない(再開ボタンのダブルクリックで、すぐ始まらないように)
var _pause_cd := 0.0          # 再開してから、またポーズできるようになるまでの残り秒
var _pause_sel := 0       # 0..2 = ボタン、3 = 全体音量、4 = 音楽、5 = 効果音
var _pause_vol: Array = []   # [スライダー, 値ラベル, 見出しラベル, 行の枠]
var _pause_music: Array = []
var _pause_sfx: Array = []
var _hud: Node2D
var _hp_node: Node2D      # 体力バーの描画層(自機が近づくと薄くなる)
var _sc_node: Node2D      # スコアの描画層(同上)
var _hp_a := 1.0          # 体力バーの不透明度(自機が近いほど下がる。なめらかに追従)
var _sc_a := 1.0          # スコアの不透明度(同上)
var _score_red := 0.0     # スコアが被ダメージで減っている間の赤み(0..1。なめらかに出入り)
var _hp_stripe := 0.0     # 体力バーの斜めの縞の位置(0..縞の周期)
var _hp_w := HP_W         # 体力バーの長さ。ゲージ満タンぶんの被弾時間が短い MOD(地獄)では、その割合だけ短くなる
var _bg_img: TextureRect  # 背景の画像(キアイ中の拍で少し明るくなる)
var _soft := false         # 目に優しい表示(設定 eye_comfort)
var _arena_bg: ColorRect  # フィールドの暗い下地
var _kiai_a := 0.0        # キアイ中か(0..1。なめらかに出入りする)
var _beat_glow := 0.0     # 今の光の強さ 0..1(キアイ中、拍の頭で立ち上がって、次の拍へ向けて消える)


## 選曲で作っておいたもの {gen: 弾幕(MOD 適用前), audio: 曲全体の音声}。ないものは、ここで作る・読む
var pre: Dictionary = {}


## ポーズ中か(main が、F11 の全画面を受け付けるかの判断に使う)
func is_paused() -> bool:
	return _paused


## ウィンドウのフォーカスが外れたら(別のウィンドウへ切り替えた・最小化した)、自動でポーズにする。
## ひとり用だけ(マルチプレイは止められない)。終わりの演出・ゲームオーバー・すでにポーズ中は何もしない。開発用の自動操作(--smoke / --prof / --shot)も対象外。
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT:
		return
	if not replay_data.is_empty():   # 再生: 別のウィンドウへ移ったら、止める(動画の書き出しの子プロセスは、止めない)
		if _rp != null and not replay_export and _rp_playing and not _dev_run():
			_replay_set_playing(false)
		return
	if _mp != null or _menu_open() or _dead or _end_timer >= 0.0 or _outro_t >= 0.0 or not is_inside_tree() or not replay_data.is_empty():
		return
	if prof_on or debug_move.is_valid() or debug_seek >= 0.0 or (_dev_run() and not focus_pause_in_dev):
		return
	_set_paused(true)


## 開発用の起動引数(--smoke… / --prof… / --shot)で動いているか。自動操作の最中は、フォーカスが外れてもポーズにしない。
## 開発用の起動引数で動いていても、フォーカス外れのポーズを試す(--smoke-focus だけが true にする)
static var focus_pause_in_dev := false


static func _dev_run() -> bool:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--smoke") or str(a).begins_with("--prof") or str(a).begins_with("--shot"):
			return true
	return false


func setup(p_loader, p_bm, p_settings: Dictionary) -> void:
	loader = p_loader
	bm = p_bm
	settings = p_settings


## マルチプレイで始める。net: 通信層(net.gd)、info: 部屋の設定(mode, mods, density_mul, players)。MOD・弾密度は、部屋のものを使う(全員で同じ弾幕にする)。
func setup_multi(p_net, info: Dictionary, p_loader, p_bm, p_settings: Dictionary) -> void:
	net = p_net
	mp_info = info
	loader = p_loader
	bm = p_bm
	settings = p_settings.duplicate()
	settings["mods"] = Mods.multi_ok(info.mods)   # 撃破はひとり用(部屋に入っていても外す)
	settings["density_mul"] = float(info.density_mul)


## リプレイを再生する。p_settings: いまの設定(音量など)。MOD・弾の密度は、記録のものを使う(同じ弾幕にする)。
func setup_replay(p_loader, p_bm, p_settings: Dictionary, data: Dictionary) -> void:
	loader = p_loader
	bm = p_bm
	replay_data = data
	settings = p_settings.duplicate()
	settings["mods"] = (data.settings as Dictionary).get("mods", [])
	settings["density_mul"] = float((data.settings as Dictionary).get("density_mul", 1.0))
	settings["control"] = "keyboard"   # 再生では、マウスを捕まえない(操作パネルを使うため)
	settings["speed_study"] = false


func _ready() -> void:
	_alive += 1
	get_window().focus_entered.connect(_on_window_focus_in)   # 別のウィンドウから戻ったとき、マウスの捕まえを掛け直す
	_mouse_mode = settings.get("control", "mouse") == "mouse"
	# 背景(譜面の画像を暗く)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.06)
	bg.size = Vector2(1280, 720)
	add_child(bg)
	_bg_nodes.append(bg)
	var tex: Texture2D = loader.load_image(bm.background) if bm.background != "" else null
	_bg_tex = tex
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.size = Vector2(1280, 720)
		tr.modulate = BG_TINT
		add_child(tr)
		_bg_nodes.append(tr)
		_bg_img = tr
	_soft = bool(settings.get("eye_comfort", true))
	_arena_bg = ColorRect.new()
	_arena_bg.color = Color(0.0, 0.0, 0.02, SOFT_BG_ALPHA if _soft else ARENA_BG_ALPHA)
	_arena_bg.position = ARENA_POS
	_arena_bg.size = PatternGen.ARENA
	add_child(_arena_bg)

	_arena = Node2D.new()
	_arena.position = ARENA_POS
	add_child(_arena)
	_view_under = ArenaView.new()
	_view_under.layer = 0
	_view_under.soft = _soft
	_arena.add_child(_view_under)
	field = BulletField.new()
	_arena.add_child(field)
	field.setup_render()
	field.soft = 1.0 if _soft else 0.0
	_view_over = ArenaView.new()
	_view_over.layer = 1
	_view_over.soft = _soft
	_arena.add_child(_view_over)

	# 音声
	_audio = AudioStreamPlayer.new()
	Volume.route_music(_audio)   # 音楽バスへ(ホイールなどの「音楽」の音量が効く)
	_audio.stream = pre.audio if pre.has("audio") else loader.load_audio(bm.audio_filename)
	add_child(_audio)
	_sfx = Sfx.new()
	_sfx.volume = int(settings.get("sfx_volume", 70)) / 100.0
	_vol_rev = Volume.rev
	add_child(_sfx)

	# 弾幕生成 + シミュ
	# 弾幕: 選曲のときに作ったもの(MOD 適用前)があれば、それを使う(作り直すと、曲によっては 0.3 秒ほど止まる)
	# 弾速の実験(設定で参加したとき・ひとりで・弾幕に効く MOD なし): 条件に合わせて、弾速・目標の難易度を変えて作る(プレイ中は条件を出さない)
	if not replay_data.is_empty():
		_study_cond = str(replay_data.get("cond", ""))   # 再生: 記録したときの条件で、同じ弾幕を作る
	elif SpeedStudy.eligible(settings, net != null):
		_study_cond = SpeedStudy.choose(SpeedStudy.map_key(bm), SpeedStudy.read_rows())
	# 対戦は、体力が 0 でもゲームオーバーにならない(最後まで続く)。協力は、体力を全員で共有する(ホストが決める)
	var built := Replay.build_game(field, bm, settings, _study_cond, pre, net != null and mp_info.mode == "versus")
	gen = built.gen
	_mods = built.mods
	_rate = built.rate
	_end_time = built.end_time
	sim = built.sim
	_hp_w = HP_W * clampf(_mods.drain_time / GameSim.GAUGE_DRAIN_TIME, 0.3, 1.2)   # 体力が少ない MOD ほどバーが短い(地獄: 150ms ÷ 250ms = 0.6 倍)
	_audio.pitch_scale = _rate
	if sim.boss != null:
		_hp_y = HP_Y_BOSS
		_score_dy = SCORE_DY_BOSS
	_view_under.sim = sim
	_view_over.sim = sim
	if net != null:
		if mp_info.mode == "coop":
			sim.setup_coop(mp_info.players.size(), net.is_host())
		_mp = MpGame.new()
		_mp.setup(net, mp_info, sim)
		_view_under.own_color = _mp.my_color()
		_view_over.own_color = _mp.my_color()
		net.game_message.connect(_mp.handle)
		net.go.connect(_mp.on_go)
		_mp.skip_cb = func(elapsed: float): _skip_intro(elapsed)   # 全員がスキップを押したら、いっせいに飛ばす

	_build_hud()
	_build_skip_button()
	if replay_data.is_empty() and _mp == null and debug_seek < 0.0 and Replay.enabled and bool(settings.get("replay_save", true)) and (Replay.force_record or (not debug_move.is_valid() and not _dev_run())):
		_rec = Replay.Recorder.new()   # ひとり用のプレイは入力を記録する(終わりに保存。scripts/replay.gd。開発用の自動操作は保存しない)
		_rec.begin(sim, field, -LEAD_IN)
		_rp_fp = Replay.fingerprint_of(sim)
	if not replay_data.is_empty():
		_init_replay()
	elif debug_seek >= 0.0:
		_now = 0.0
		var dt := 1.0 / 60.0
		while _now < debug_seek and not sim.finished:
			sim.step(_now, dt, Vector2.ZERO, false)
			_now += dt
		_audio_started = true
		_center_label.visible = false
		_gauge_ghost = sim.gauge
		_low_vis = _low_target()
		_score_disp = sim.score
		_break_a = 1.0 if _update_break_count() else 0.0
		_break_in = _break_a
		_break_sec = int(ceil(_break_left)) if _break_a > 0.0 else -1
		_update_hud_fade(0.0, true)
		_update_kiai(0.0, true)
		if sim.failed:
			_begin_death(false)
			_death_t = maxf(debug_death_t, 0.0)
			_apply_death_fx()
		_refresh()
	else:
		_begin_arrival()
	_prewarm_text()
	if net != null:
		# 全員が同じ弾幕を作れたかの確認用の要約(ホストと違う人は外される)。開始の合図(go)は、全員の準備が済んでから届く
		net.report_loaded(sim.events.size() * 100003 + sim.bullets_total)


## プレイの途中で初めて出る文字(エリアの名前)の字形を、始まる前に作っておく。
## 日本語の字形は、初めて使うときに作られ、1 回で数 ms かかる(エリアに入った瞬間に、フレームが落ちていた)。
func _prewarm_text() -> void:
	if _debuff_l == null:
		return
	var font := _debuff_l.get_theme_font("font")
	var size := _debuff_l.get_theme_font_size("font_size")
	for type in ["slow", "fragile", "poison", "big", "heal", "precise", "bonus", "warp", "haste", "flow"]:
		font.get_string_size("%s  %s" % [GameSim.zone_family_name(type), GameSim.zone_name(type)], HORIZONTAL_ALIGNMENT_LEFT, -1, size)


## 自機の現れ具合(ArenaView の ship_in)を、2 つの描画層にそろえて設定する。
func _set_ship_in(v: float) -> void:
	_view_under.ship_in = v
	_view_over.ship_in = v
	_view_under.queue_redraw()
	_view_over.queue_redraw()


## ゲーム開始の「間」: メニューで見ていたカーソルが、自機の開始位置へ弧を描いて飛び、着いた瞬間に自機になる。
## 自機が見えない間はマウスを捕まえず(移動は効かない)、着いたら OS のポインタも自機の位置へ移してから捕まえる
## (ポーズでカーソルが戻るとき、自機のあった場所から出る)。キーボード操作・動きなしのときは、少し待って自機が現れる。
func _begin_arrival() -> void:
	if not UiStyle.animate:
		if _mouse_mode:
			_capture_mouse()
		return
	_set_ship_in(0.0)
	if _mouse_mode:
		_guiding = true
		var to: Vector2 = ARENA_POS + sim.player_pos
		if CursorOverlay.fly_to(to, 0.6, Callable(self, "_arrive")):
			return
	get_tree().create_timer(0.35).timeout.connect(_arrive)


func _arrive() -> void:
	if _arrived or not is_inside_tree():
		return
	_arrived = true
	_guiding = false
	CursorOverlay.cancel_fly()
	if _mouse_mode and not _menu_open():
		Input.warp_mouse(get_viewport().get_screen_transform() * (ARENA_POS + sim.player_pos))
		if _can_skip():   # スキップのボタンを押せるように、まだ捕まえない(自機がマウスの位置へ動き、カーソルの代わりになる。_update_skip_button が、できなくなったら捕まえる)
			_skip_free = true
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		else:
			_capture_mouse()
	# 自機が、その場で弾んで現れる(輪が広がり、小さな音)
	if UiStyle.animate and not _dead:
		var t := create_tween()
		t.tween_method(_set_ship_in, 0.0, 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		UiFx.ring(_arena, sim.player_pos, Color(0.32, 0.8, 1.0, 0.9), 10.0, 70.0, 0.55, 2.5)
		UiSfx.play("select", 1.6)
	else:
		_set_ship_in(1.0)


func _exit_tree() -> void:
	_alive -= 1
	if _rp_dense != null:
		_rp_dense.stop()   # 裏のスレッドを止めて、終わるのを待つ
	if _alive <= 0:   # リトライで次のプレイ画面がすでに始まっているときは、触らない(マウスの捕まえを外してしまい、自機と独自カーソルが両方出る)
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN   # OS のカーソルは、どの画面でも隠したまま(アプリ独自のカーソルを出す。cursor_overlay.gd)
	if net != null and _mp != null:
		if net.game_message.is_connected(_mp.handle):
			net.game_message.disconnect(_mp.handle)
		if net.go.is_connected(_mp.on_go):
			net.go.disconnect(_mp.on_go)


func _build_hud() -> void:
	_score_font = UiStyle.bold()
	_build_left_panel()
	_build_right_panel()
	_center_label = _label("READY", ARENA_POS + Vector2(0, 300), 40, PatternGen.ARENA.x)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.pivot_offset = _center_label.size * 0.5   # ラベルの真ん中を軸に弾む
	_hud = Node2D.new()
	_hud.draw.connect(_draw_hud)
	add_child(_hud)
	_hp_node = Node2D.new()
	_hp_node.draw.connect(_draw_hp_layer)
	_hud.add_child(_hp_node)
	_sc_node = Node2D.new()
	_sc_node.draw.connect(_draw_score)
	_hud.add_child(_sc_node)
	if sim.boss != null:
		_build_boss_gauge()
	_build_pause()
	# 始まりの動き: 左右のパネルが外から滑り込み、HP・スコアがフェードインし、READY が弾んで現れる
	UiStyle.pop_in(_left_col, 0.1, Vector2(-26, 0), 0.5)
	UiStyle.pop_in(_right_col, 0.1, Vector2(26, 0), 0.5)
	UiStyle.tween(_hud, "modulate:a", 0.0, 1.0, 0.6, 0.15)
	UiStyle.tween(_center_label, "modulate:a", 0.0, 1.0, 0.4, 0.25)
	_center_label.pivot_offset = _center_label.size * 0.5   # ラベルの真ん中を軸に弾む
	UiStyle.tween(_center_label, "scale", Vector2(1.3, 1.3), Vector2.ONE, 0.55, 0.25, Tween.TRANS_BACK)


## 再生: いつの・どんな結果のプレイか(左のパネルに出す)。戻り値: {when, result, failed}
func _replay_info() -> Dictionary:
	var st: Dictionary = replay_data.get("stats", {})
	var failed := bool(st.get("failed", false))
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60   # 保存は UTC の秒なので、この PC の時刻へ
	var d := Time.get_datetime_dict_from_unix_time(int(replay_data.get("time", 0)) + bias)
	var res := "GAME OVER" if failed else "CLEAR  %s" % GameSim.rank_of(false, int(st.get("hits", 0)), float(st.get("score", 0.0)), float(st.get("score_base", 1000000.0)))
	return {"when": "%04d/%02d/%02d %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute], "result": res, "failed": failed}


## 左パネル(幅 160): 曲情報・Lv(MOD 適用後)・付けた MOD。
func _build_left_panel() -> void:
	var col := VBoxContainer.new()
	_left_col = col
	col.position = Vector2(14, 16)
	col.custom_minimum_size = Vector2(134, 0)
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	if not replay_data.is_empty() and not replay_export:   # 再生: 「リプレイ」であることと、いつの・どんな結果のプレイかを、いちばん上に出す(動画には入れない)
		var info := _replay_info()
		var chip := UiStyle.chip("REPLAY", UiStyle.ACCENT)
		chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		col.add_child(chip)
		col.add_child(UiStyle.label(info.when, 11, UiStyle.TEXT_FAINT))
		col.add_child(UiStyle.label(info.result, 12, Color(1.0, 0.45, 0.48) if info.failed else UiStyle.TEXT_DIM, true))
		_rp_state_l = UiStyle.label("", 12, UiStyle.ACCENT, true)   # 再生中 / 停止中(速さも)
		col.add_child(_rp_state_l)
		var gap0 := Control.new()
		gap0.custom_minimum_size = Vector2(0, 6)
		col.add_child(gap0)
	for spec in [[bm.artist, 12, UiStyle.TEXT_DIM, false], [bm.title, 16, UiStyle.TEXT, true], [bm.version, 13, UiStyle.ACCENT, false]]:
		var l := UiStyle.label(spec[0], spec[1], spec[2], spec[3])
		l.custom_minimum_size = Vector2(134, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		col.add_child(l)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	col.add_child(gap)
	col.add_child(UiStyle.caption("LV"))
	col.add_child(UiStyle.label("%.2f" % gen.level, 34, UiStyle.level_color(gen.level), true))
	if absf(gen.level - gen.base_level) >= 0.005:
		col.add_child(UiStyle.label("MODなし  %.2f" % gen.base_level, 12, UiStyle.TEXT_FAINT))
	if not _mods.ids.is_empty():
		var gap2 := Control.new()
		gap2.custom_minimum_size = Vector2(0, 10)
		col.add_child(gap2)
		for id in _mods.ids:
			var m := Mods.find(id)
			var chip := UiStyle.chip(m.tag, m.color)
			chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			col.add_child(chip)
	_debuff_l = UiStyle.label("", 15, UiStyle.TEXT, true)   # 危険エリアに入っている間だけ、デバフの名前を出す
	_debuff_l.visible = false
	col.add_child(_debuff_l)
	if _mp != null:   # マルチプレイ: 参加者の一覧(対戦はスコア順)
		var gap3 := Control.new()
		gap3.custom_minimum_size = Vector2(0, 14)
		col.add_child(gap3)
		col.add_child(UiStyle.caption("VERSUS" if _mp.mode == "versus" else "CO-OP"))
		_mp_box = VBoxContainer.new()
		_mp_box.add_theme_constant_override("separation", 5)
		_mp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(_mp_box)


## 右パネル(幅 160): GRAZE / DAMAGE(ダメージ量。ゲージ満タン = 100%)と、モード表示。
func _build_right_panel() -> void:
	var col := VBoxContainer.new()
	_right_col = col
	col.position = Vector2(1138, 18)
	col.custom_minimum_size = Vector2(130, 0)
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	col.add_child(UiStyle.caption("GRAZE"))
	_graze_l = UiStyle.label("0", 26, UiStyle.TEXT, true)
	col.add_child(_graze_l)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	col.add_child(gap)
	col.add_child(UiStyle.caption("DAMAGE"))
	_hit_l = UiStyle.label("0%", 26, UiStyle.TEXT, true)
	col.add_child(_hit_l)
	if sim.boss != null:   # 撃破 MOD: 自機の弾の強化(アイテムで上がる段階)
		var gap2 := Control.new()
		gap2.custom_minimum_size = Vector2(0, 12)
		col.add_child(gap2)
		col.add_child(UiStyle.caption("WEAPON"))
		for k in ["power", "rate", "wide"]:
			var l := UiStyle.label("", 15, UiStyle.TEXT_DIM, true)
			col.add_child(l)
			_weapon_ls[k] = l
		_update_weapon_labels()


## ポーズ画面(暗転 + 中央パネル)。項目は 6 行: 再開 / リトライ / メニューへ / 全体音量 / 音楽 / 効果音(設定・音量メーターと同じ名前と並び)。
## マウスを乗せた行が選択になり、枠で示す。キーでも、↑↓ で全部の行を選べる(← → は選んだ音量の行だけを動かす)。
func _build_pause() -> void:
	_pause_layer = Control.new()
	_pause_layer.size = Vector2(1280, 720)
	_pause_layer.theme = UiStyle.make_theme()
	_pause_layer.visible = false
	add_child(_pause_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.size = Vector2(1280, 720)
	_pause_layer.add_child(dim)
	_pause_cover = ColorRect.new()   # 止めた弾を観察できないよう、ポーズ中のアリーナは見せない(マルチプレイのメニューは、ゲームが進むので覆わない)
	_pause_cover.color = Color(UiStyle.BG.r, UiStyle.BG.g, UiStyle.BG.b, 1.0)
	_pause_cover.position = ARENA_POS
	_pause_cover.size = PatternGen.ARENA
	_pause_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_cover.visible = _mp == null
	_pause_layer.add_child(_pause_cover)
	var panel := PanelContainer.new()
	_pause_panel = panel
	panel.position = Vector2(400, 112)
	panel.size = Vector2(480, 10)
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.LINE, 1, 8, 30, 26))
	_pause_layer.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(UiStyle.label("MENU" if _mp != null else "PAUSED", 28, UiStyle.TEXT, true))   # マルチプレイでは、ゲームは止まらない
	v.add_child(UiStyle.hline())
	_pause_btns.clear()
	var btn_box := VBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 8)
	v.add_child(btn_box)
	var specs := [["再開", Callable(self, "_pause_activate").bind(0)],
		["リトライ", Callable(self, "_pause_activate").bind(1)],
		["メニューへ", Callable(self, "_pause_activate").bind(2)]]
	for i in range(specs.size()):
		var b := Button.new()
		b.text = specs[i][0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 44)
		b.pressed.connect(specs[i][1])
		b.mouse_entered.connect(func():
			_pause_sel = i
			_refresh_pause())
		btn_box.add_child(b)
		_pause_btns.append(b)
	if _mp != null:   # マルチプレイ: リトライはなく、「メニューへ」は部屋を出ることになる
		_pause_btns[1].visible = false
		_pause_btns[2].text = "退出"
	v.add_child(UiStyle.hline())
	var row_box := VBoxContainer.new()
	row_box.add_theme_constant_override("separation", 6)
	v.add_child(row_box)
	_pause_vol = _pause_slider_row(row_box, 3, "全体音量", func(x: float): _set_master_volume(int(x)))
	_pause_music = _pause_slider_row(row_box, 4, "音楽", func(x: float): _set_music_volume(int(x)))
	_pause_sfx = _pause_slider_row(row_box, 5, "効果音", func(x: float): _set_sfx_volume(int(x)))


## ポーズ画面の音量スライダー 1 行(見出し + スライダー + 値。選択中は枠で示す)。idx はその行の _pause_sel の番号。
## [スライダー, 値ラベル, 見出しラベル, 行の枠] を返す。
func _pause_slider_row(parent: Control, idx: int, cap: String, on_change: Callable) -> Array:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 40)
	row.mouse_filter = Control.MOUSE_FILTER_PASS   # 子(スライダー)の上でも、行に入ったことが分かる
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)
	var l := UiStyle.label(cap, 15, UiStyle.TEXT)
	l.custom_minimum_size = Vector2(88, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 5
	s.custom_minimum_size = Vector2(170, 0)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(on_change)
	h.add_child(s)
	var val := UiStyle.label("", 15, UiStyle.ACCENT)
	val.custom_minimum_size = Vector2(50, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	var select_row := func():
		if _pause_sel != idx:
			_pause_sel = idx
			_refresh_pause()
	row.mouse_entered.connect(select_row)
	s.mouse_entered.connect(select_row)
	parent.add_child(row)
	return [s, val, l, row]


func _label(text: String, pos: Vector2, font_size: int, width: float) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = Vector2(width, 10)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	return l


func _process(delta: float) -> void:
	if Volume.rev != _vol_rev and _sfx != null:   # ホイールなどで効果音の音量が変わった
		_vol_rev = Volume.rev
		_sfx.volume = Volume.sfx / 100.0
	if debug_seek >= 0.0 or _done:
		return
	if _paused:
		if _resume_wait:
			_tick_resume_wait(delta)
		return
	delta = minf(delta, 0.05)
	if _rp == null and _should_capture() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and get_window().has_focus():
		_capture_mouse()   # 捕まえているはずなのに外れている(何かの拍子に戻ってしまった): 掛け直す。これがないと、自機が動かないまま
	_pause_cd = maxf(_pause_cd - delta, 0.0)
	_ui_time += delta
	if _rp == null and _update_retry_hold(delta):
		return
	if not replay_data.is_empty():
		if _rp != null:
			_replay_tick(delta)
	elif _dead:
		# ゲームオーバー: ゲームの時間も、テープストップ(曲の減速)と同じ割合で遅くなって止まる。
		# 弾はそのまま進み続けて(当たり判定はなし)、曲と一緒に減速して止まる。予兆・危険エリアなどの動きも同じ
		var dt_game := delta * _tape_speed()
		_now += dt_game
		field.update(dt_game, Vector2(-1.0e6, -1.0e6), 0.0, false)
	elif not _audio_started:
		if _mp != null:   # マルチプレイ: 開始の合図まで待ち、合図のあとは全員で共通の時計で READY を数える(同じ瞬間に曲が始まる)
			_now = maxf(-LEAD_IN + (net.shared_time() - _mp.start_shared), -LEAD_IN) if _mp.started else -LEAD_IN
		else:
			_now += delta
		if _now >= 0.0:
			_audio.play(_now * _rate if _now > 0.1 else 0.0)   # 遅れて始まった人は、途中から
			_audio_started = true
			_arrive()   # 演出が間に合っていなくても、曲が始まるまでに操作を渡す
			_fade_out_center()
	else:
		# 再生位置は曲の秒数(再生速度の倍で進む)。÷rate で、ゲーム内の時刻(実時間と同じ進み方)にする
		var t: float = _audio.get_playback_position() / _rate + AudioServer.get_time_since_last_mix() \
			- AudioServer.get_output_latency() + settings.get("offset_ms", 0) / 1000.0
		if _ff_t >= 0.0:   # 撃破: ボーナスタイムの早送り中は、曲クロックを実時間で進める
			_tick_ff(delta)
		else:
			t += float(_loop_k) * sim.loop_len   # 撃破: 2 周目以降は、周の分を足す
			if _audio.playing:
				_advance_clock(t, delta)
			else:
				_now += delta  # 曲が先に終わっても進行を続ける
			if sim.loop_len > 0.0 and not _dead and not sim.finished and _now >= float(_loop_k) * sim.loop_len + sim.loop_end:
				_begin_ff()

	var slow := Input.is_physical_key_pressed(KEY_SHIFT)
	if _mouse_mode:
		slow = slow or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var p0 := Time.get_ticks_usec() if prof_on else 0
	_step_sim(slow)
	if prof_on:
		prof = {"sim": Time.get_ticks_usec() - p0, "steps": _prof_steps, "n": field.count, "now": _now, "warp": field.warp.size(), "ts": field._ts_active, "halo": field.halo, "zone": sim.zone_area_type}
	if _mp != null:
		_mp.tick(delta, _now)

	# 効果音は 1 回だけ消費する(シミュレーション停止後に残った分を毎フレーム鳴らさない)
	if not sim.failed:
		for i in range(_sfx_pending.size()):
			_sfx.play(_sfx_pending[i], 1.0, float(_sfx_pending_pan[i]) if i < _sfx_pending_pan.size() else 0.0)
		if _hit_started:
			_sfx.play("hit", 1.0, sim.player_pos.x / PatternGen.ARENA.x * 2.0 - 1.0)  # 新しい被弾の開始時に 1 回。自機の横の位置で左右に振る(触れている間は、下の touch_damage がジジジと鳴らし続ける)
		if _hit_any:
			_sfx.touch_damage(1.0 - sim.gauge)
	_sfx_pending.clear()
	_sfx_pending_pan.clear()
	_hit_started = false
	_hit_glow = 1.0 if _hit_any else _hit_glow * exp(-delta * 5.0)
	_gauge_ghost = maxf(sim.gauge, _gauge_ghost - delta * 0.5)
	_ease_score(delta)
	_animate_hud(delta)
	_update_skip_button()
	_update_debuff_label()
	_view_over.hit_glow = _hit_glow
	_view_under.hit_glow = _hit_glow
	if sim.failed and not _dead:
		_begin_death(true)
	if _dead:
		_death_t += delta
		_apply_death_fx()
	var p1 := Time.get_ticks_usec() if prof_on else 0
	_refresh()
	if prof_on:
		prof["refresh"] = Time.get_ticks_usec() - p1
		prof["proc"] = Time.get_ticks_usec() - p0

	if _rp == null and sim.finished and not sim.failed and not _done:
		# クリア: 背景以外をフェードアウト(画面も曲も止めない。弾は sim が消してある)→ リザルトへ。曲は呼び出し側が引き継ぐ
		if _outro_t < 0.0:
			_begin_outro()
		_outro_t += delta
		if _outro_t < OUTRO_TIME:
			return
		_done = true
		_end_ff()   # 早送りの途中なら、ふつうの速さに戻して渡す
		var music := _audio
		if _audio.playing:
			remove_child(_audio)
		else:
			music = null
		var st_clear := _stats()
		_record_study(st_clear)
		_save_replay(st_clear)
		if _mp != null:
			_mp.send_final(st_clear)
		finished.emit(st_clear, music)
		return
	if _rp == null and sim.finished and _end_timer < 0.0:
		_end_timer = END_DELAY_FAIL
	if _end_timer >= 0.0:
		_end_timer -= delta
		if _end_timer <= 0.0 and not _done:
			_done = true
			_audio.stop()
			var st_fail := _stats()
			_record_study(st_fail)
			_save_replay(st_fail)
			if _mp != null:
				_mp.send_final(st_fail)
			finished.emit(st_fail, null)


## 曲クロック(_now)を進める。音声クロック t は、ミキサーのかたまり単位で更新されるため、そのまま使うと
## フレームごとの増分がばらつく(止まって次に跳ぶ)= 弾の移動距離がフレームごとに違って、カクついて見える。
## そこで _now は描画のフレーム時間 delta で滑らかに進め、音声とのずれ(err)だけを CLOCK_PULL の割合でゆっくり寄せる。
## ずれが CLOCK_RESYNC を超えたら(シーク・音声の遅れなど)、音声の時刻へ直接合わせる。時刻は戻らない。
func _advance_clock(t: float, delta: float) -> void:
	var err := t - _now
	if err > CLOCK_RESYNC:
		_now = t
	else:
		_now += maxf(delta + err * clampf(delta * CLOCK_PULL, 0.0, 1.0), 0.0)


## クリアのフェードアウトを始める: 背景(暗い画像)を残して、アリーナ・自機・HUD・左右のパネルをなめらかに消す。
func _begin_outro() -> void:
	_outro_t = 0.0
	for c in get_children():
		if c is CanvasItem and not _bg_nodes.has(c) and c != _pause_layer:
			UiStyle.tween(c, "modulate:a", c.modulate.a, 0.0, OUTRO_TIME, 0.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT)


## 判定・進行(GameSim)を、曲クロック(_now)に追いつくまで SIM_STEP(1 ms)刻みで進める。描画のフレームレートとは独立。
## 入力は、キーボードなら押している方向を各ステップで、マウスならこのフレームの移動量を各ステップに等分して渡す。
## このフレームのどこかで起きた被弾・発射音は、まとめて記録する(描画側が 1 度だけ使う)。
func _step_sim(slow: bool) -> void:
	if not replay_data.is_empty():
		return   # 再生: シムは、記録を流す係(_replay_tick)が進める
	_hit_any = false
	if sim.finished:
		_sim_t = _now
		return
	var span := _now - _sim_t
	if span <= 0.0:
		return   # 曲クロックが進んでいない(マウスの移動量は次のフレームへ持ち越す)
	var step := clampf(float(field.count) * 0.000002, SIM_STEP, SIM_STEP_MAX)
	var n := clampi(ceili(span / step), 1, SIM_MAX_STEPS)
	_prof_steps = n
	var dt := span / float(n)
	var move := Vector2.ZERO
	var d := Vector2.ZERO
	if _ship_is_cursor():   # スキップできる間: 自機がカーソルの代わり(マウスの位置へ、そのまま動く)
		d = (get_viewport().get_mouse_position() - ARENA_POS - sim.player_pos) / float(n)
		_mouse_accum = Vector2.ZERO
	elif _mouse_mode:
		var mult: float = float(settings.get("mouse_sens", 1.0)) * (GameSim.MOUSE_SLOW_FACTOR if slow else 1.0)
		d = _mouse_accum * mult / float(n)
		_mouse_accum = Vector2.ZERO
	else:
		move = _read_move()
	var t0 := _sim_t
	for k in range(n):
		_sim_t += dt
		if _mouse_mode:
			sim.step_relative(_sim_t, dt, d, slow)
		else:
			sim.step(_sim_t, dt, move, slow)
		_hit_any = _hit_any or sim.hit_now
		_hit_started = _hit_started or sim.just_hit
		_sfx_pending.append_array(sim.sfx_queue)
		_sfx_pending_pan.append_array(sim.sfx_pan)
		if sim.finished:
			break
	if _rec != null:
		_rec.add(t0, span, n, d if _mouse_mode else move, slow, _mouse_mode, sim, field)   # 同じ入力・同じ刻みで、あとで再生できるように
	if not sim.finished:
		_sim_t = _now


## ゲームオーバー演出の開始。
func _begin_death(with_sound: bool) -> void:
	_dead = true
	_death_t = 0.0
	if with_sound:
		_sfx.play("explosion")  # ゲームオーバー時はこの爆発音だけ
	if _mouse_mode:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_view_over.dead = true
	_view_under.dead = true   # 機体(弾の下の層)も描かなくする
	_view_over.death_pos = sim.death_pos
	var add := CanvasItemMaterial.new()   # 爆散演出は加算合成で光らせる(自機は描かないので、この層全体を加算にしてよい)
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_view_over.material = add


## ゲームオーバーのテープストップの速さ(1 = ふつう → 0 = 止まった)。曲の再生速度と、ゲームの時間の進み方の両方に使う。
func _tape_speed() -> float:
	return pow(1.0 - clampf(_death_t / TAPE_STOP_TIME, 0.0, 1.0), 2.0)


## 演出の経過に合わせて、曲の減速・弾のフェード・GAME OVER 表示を更新する。
func _apply_death_fx() -> void:
	var t := _death_t
	_view_over.death_t = t
	# テープストップ: 音量は保ったまま、再生速度(=音程)がなめらかに 0 へ落ちていく
	if _audio.playing:
		var x := clampf(t / TAPE_STOP_TIME, 0.0, 1.0)
		_audio.pitch_scale = maxf(_rate * _tape_speed(), 0.02)
		_audio.volume_db = linear_to_db(clampf((1.0 - x) / 0.12, 0.001, 1.0))  # 完全に止まる直前だけ消す
		if x >= 1.0:
			_audio.stop()
	# 弾は(曲と一緒に減速して)止まってから消える
	field.modulate.a = clampf(1.0 - (t - 1.0) / 0.8, 0.0, 1.0)
	# GAME OVER 表示
	var a := clampf((t - 0.45) / 0.5, 0.0, 1.0)
	_center_label.text = "GAME OVER"
	_center_label.add_theme_color_override("font_color", Color(1, 0.3, 0.35))
	_center_label.modulate.a = a
	var sc := lerpf(2.2, 1.0, 1.0 - pow(1.0 - a, 3.0))
	_center_label.scale = Vector2(sc, sc)
	_center_label.visible = a > 0.0


## 弾速の実験の記録を 1 行書き足す(実験しているプレイだけ)。被弾は、最初の発射から、最後の発射(ゲームオーバーならその時刻)までの時間あたりで比べる。
func _record_study(st: Dictionary) -> void:
	if _study_cond == "":
		return
	var first_t := -1.0
	var last_t := 0.0
	for e in gen.events:
		if not e.shots.is_empty():
			if first_t < 0.0:
				first_t = float(e.t)
			last_t = float(e.t)
	var end_t := minf(sim.death_time, last_t) if sim.failed else last_t
	var sc: Dictionary = SpeedStudy.CONDITIONS[_study_cond]
	SpeedStudy.record({
		"time": Time.get_datetime_string_from_system(), "app": str(ProjectSettings.get_setting("application/config/version", "")),
		"map": SpeedStudy.map_key(bm), "stars": float(gen.stars), "cond": _study_cond,
		"speed_mul": float(sc.speed_mul), "density_mul": float(sc.density_mul), "speed": float(gen.speed), "size": float(gen.size),
		"level": float(gen.level), "mean": float(gen.rating.mean), "control": str(settings.get("control", "")),
		"practice": 1 if _mods.practice else 0, "failed": 1 if sim.failed else 0, "progress": float(st.progress),
		"played_s": maxf(end_t - maxf(first_t, 0.0), 0.0), "hits": int(sim.hits), "hit_ms": int(st.hit_ms), "graze": int(sim.graze), "score": float(sim.score),
	})


func _stats() -> Dictionary:
	var d := {
		"title": bm.display_name(),
		"md5": bm.md5,   # 記録(records.gd)を、譜面の難易度ごとに残すための識別子
		"version": bm.version,
		"level": gen.level,
		"mean": gen.rating.mean,
		"peak": gen.rating.peak,
		"failed": sim.failed,
		"progress": 1.0 if not sim.failed else clampf((sim.death_time * _rate - bm.first_time() / 1000.0) / maxf((bm.last_time() - bm.first_time()) / 1000.0, 1.0), 0.0, 1.0),
		"hits": sim.hits,
		"hit_ms": int(round(sim.hit_time * 1000.0)),
		"damage": sim.damage_total,
		"own_damage": sim.own_damage,
		"score_gross": sim.score_gross,
		"score_base": sim.score_base,
		"mods": Mods.names(_mods.ids),
		"mod_ids": _mods.ids,
		"damage_factor": sim.damage_factor,
		"score_graze": sim.score_graze,
		"score_boss_time": sim.score_boss_time,
		"graze": sim.graze,
		"score": sim.score,
		"practice": _mods.practice,
		"bg": _bg_tex,
		# 結果画面の体力グラフ用
		"hp_log": sim.gauge_log,
		"hp_step": GameSim.GAUGE_LOG_STEP,
		"hp_end": sim.gauge,
		"hp_t_end": sim.log_end_t,
		"hit_log": sim.hit_log,
		"breaks": sim.breaks,
		"first_fire": sim.first_fire_time,
		"last_fire": sim.log_end_t if sim.boss != null else sim.last_fire_time,   # 撃破は曲が繰り返すので、戦いの終わりまで
	}
	if sim.boss != null:   # 撃破 MOD: 結果画面に、倒せたか・倒すまでの時間(最初の発射から。実時間)・残りの HP・周回数を出す
		d["boss"] = {"defeated": sim.boss.defeated, "defeat_t": maxf(float(sim.boss.defeat_t) - maxf(sim.first_fire_time, 0.0), 0.0),
			"hp_left": float(sim.boss.hp) / maxf(float(sim.boss.max_hp), 1.0), "loops": sim.loop_index(_now) + 1}
	if _mp != null:   # マルチプレイ: 結果画面が、参加者の成績を並べるのに使う
		d["mp"] = {"mode": _mp.mode, "my_id": _mp.my_id, "players": _mp.roster.duplicate(true)}
	return d


func _read_move() -> Vector2:
	if debug_move.is_valid():
		return debug_move.call()
	if _mp_menu:
		return Vector2.ZERO
	var m := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):
		m.x -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
		m.x += 1.0
	if Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W):
		m.y -= 1.0
	if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S):
		m.y += 1.0
	return m


func _refresh() -> void:
	if _mp != null:
		var rl: Array = _mp.draw_list()
		_view_under.remotes = rl
		_view_over.remotes = rl
	_view_under.now = _now
	_view_under.sync_sliders()
	_view_over.now = _now
	_view_under.queue_redraw()
	_view_over.queue_redraw()
	if _mods.dark:   # 暗闇: 自機の周囲の弾だけが見える(描画だけ。判定は変わらない)
		field.vis_center = sim.player_pos
		field.vis_r0 = DARK_FULL_R * _dark_scale
		field.vis_r1 = DARK_FADE_R * _dark_scale
	field.sync_render()
	_graze_l.text = str(sim.graze)
	_hit_l.text = "%d%%" % int(round(sim.damage_total * 100.0))   # ダメージ量(回復は引かない。協力ではチーム全体)
	_hud.queue_redraw()
	_hp_node.queue_redraw()
	_sc_node.queue_redraw()


## 体力バー: 斜めに切った細身のバー。外枠(暗いケース)+ 溝 + 塗り。塗りは上が明るく下が暗い 2 段のグラデーション(左が暗く右が明るい)、
## 上面の光沢、斜めの縞(流れる)、流れる光の帯、下に落ちる色のにじみ。減った分は白い残像がゆっくり縮む。
## 20%(被ダメージ半減の境目)の小さな三角。残量が減るほど青緑 → 琥珀 → 赤へ連続的に変わり、枠も赤みを帯びる。
## 先端は状態で動きが変わる:
##   回復中   … 縞と光が速く流れ、先端が明るく、火の粉が立ちのぼる
##   通常     … 縞と光がゆっくり流れ、先端は控えめ
##   被弾中   … 先端から赤い火花が散る
##   休憩中(回復が止まっている)… 縞と光が止まり、バーが冷たい色に沈み、先端に静かな波紋が広がる
func _draw_hp_bar(font: Font, bx: float, y: float, g: float) -> void:
	var cv := _hp_node
	var bw := _hp_w
	var h := HP_H
	var sl := HP_SL
	var gc := UiStyle.hp_color(g).lerp(Color(0.68, 0.78, 0.95), 0.5 * _fx_break)   # 休憩中は冷たい色に沈む
	var ghost: float = clampf(_gauge_ghost, 0.0, 1.0)
	var calm := 1.0 - _fx_break
	var fw := bw * g

	# 見出しと、左の飾り(斜めの 3 本線。残量の色)
	cv.draw_string(font, Vector2(bx + sl + 2.0, y - 9.0), "HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.6))
	for k in range(3):
		var cx := bx - 10.0 - 7.0 * k
		cv.draw_colored_polygon(PackedVector2Array([Vector2(cx + sl * 0.8 + 3.0, y + 1.0), Vector2(cx + sl * 0.8 + 6.0, y + 1.0), Vector2(cx + 6.0, y + h - 1.0), Vector2(cx + 3.0, y + h - 1.0)]),
			Color(gc.r, gc.g, gc.b, 0.8 - 0.25 * k))
	# 外枠(暗いケース)と溝。溝には細い斜線の模様
	cv.draw_colored_polygon(_slant(bx - 3.0, y - 3.0, bw + 6.0, h + 6.0, sl), Color(0.02, 0.03, 0.07, 0.72))
	cv.draw_colored_polygon(_slant(bx, y, bw, h, sl), Color(0, 0, 0, 0.5))
	var hx := 6.0
	while hx < bw:
		cv.draw_line(Vector2(bx + hx + sl, y + 1.0), Vector2(bx + hx, y + h - 1.0), Color(1, 1, 1, 0.05), 1.0)
		hx += 9.0
	# 残像(減った分の白。右へ向かって薄くなる)
	if ghost > g:
		var gp := _slant(bx, y, bw * ghost, h, sl)
		var g_l := Color(1, 1, 1, 0.42)
		var g_r := Color(1, 1, 1, 0.16)
		cv.draw_polygon(gp, PackedColorArray([g_l, g_r, g_r, g_l]))
	if g > 0.005:
		# 下ににじむ色(バーの底から落ちる光)
		cv.draw_polygon(PackedVector2Array([Vector2(bx, y + h), Vector2(bx + fw, y + h), Vector2(bx + fw, y + h + 9.0), Vector2(bx, y + h + 9.0)]),
			PackedColorArray([Color(gc.r, gc.g, gc.b, 0.20 * calm), Color(gc.r, gc.g, gc.b, 0.20 * calm), Color(gc.r, gc.g, gc.b, 0.0), Color(gc.r, gc.g, gc.b, 0.0)]))
		# 本体: 上の段(明るい)と下の段(暗い)。どちらも左が暗く右が明るい
		var c_l := Color(gc.r * 0.42, gc.g * 0.42, gc.b * 0.42, 1.0)
		var c_r := Color(gc.r, gc.g, gc.b, 1.0)
		var t_l := c_l.lerp(Color.WHITE, 0.16)
		var t_r := c_r.lerp(Color.WHITE, 0.34)
		var b_l := Color(c_l.r * 0.72, c_l.g * 0.72, c_l.b * 0.72, 1.0)
		var b_r := Color(c_r.r * 0.7, c_r.g * 0.7, c_r.b * 0.7, 1.0)
		cv.draw_polygon(_slant_band(bx, y, fw, h, sl, 0.0, 0.5), PackedColorArray([t_l, t_r, c_r, c_l]))
		cv.draw_polygon(_slant_band(bx, y, fw, h, sl, 0.5, 1.0), PackedColorArray([c_l, c_r, b_r, b_l]))
		# 斜めの縞(バーの傾きと平行。回復中は速く流れ、休憩中は止まる)
		var stripe_a := (0.09 + 0.09 * _fx_regen) * calm
		if stripe_a > 0.01:
			var u := _hp_stripe - 20.0
			while u < fw:
				var a := maxf(u, 0.0)
				var b := minf(u + 7.0, fw)
				if b - a > 0.5:
					cv.draw_colored_polygon(PackedVector2Array([Vector2(bx + a + sl, y), Vector2(bx + b + sl, y), Vector2(bx + b, y + h), Vector2(bx + a, y + h)]), Color(1, 1, 1, stripe_a))
				u += 20.0
		# 上面の光沢(上 40% に白がのって、下へ向かって消える)
		cv.draw_polygon(_slant_band(bx, y, fw, h, sl, 0.0, 0.4), PackedColorArray([Color(1, 1, 1, 0.34), Color(1, 1, 1, 0.34), Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.04)]))
		# 流れる光(斜めの帯)。回復中は明るく速く、休憩中は止まって見えなくなる
		var band_a := (0.14 + 0.26 * _fx_regen) * calm
		if band_a > 0.01:
			var cx2 := _hp_flow - 40.0
			for side in range(2):   # 左半分は透明 → 明るい、右半分は明るい → 透明
				var x0 := clampf(cx2 + (-18.0 if side == 0 else 0.0), 0.0, fw)
				var x1 := clampf(cx2 + (0.0 if side == 0 else 18.0), 0.0, fw)
				if x1 - x0 < 0.5:
					continue
				var c_lo := Color(1, 1, 1, 0.0 if side == 0 else band_a)
				var c_hi := Color(1, 1, 1, band_a if side == 0 else 0.0)
				cv.draw_polygon(PackedVector2Array([Vector2(bx + x0 + sl, y), Vector2(bx + x1 + sl, y), Vector2(bx + x1, y + h), Vector2(bx + x0, y + h)]),
					PackedColorArray([c_lo, c_hi, c_hi, c_lo]))
	# 縁取り(低いほど赤みを帯びる)。内側の細い線 + 外枠の淡い線
	var edge := Color(1, 1, 1, 0.36).lerp(Color(1.0, 0.35, 0.38, 0.9), _low_vis)
	var o := _slant(bx, y, bw, h, sl)
	o.append(o[0])
	cv.draw_polyline(o, edge, 1.0, true)
	var o2 := _slant(bx - 3.0, y - 3.0, bw + 6.0, h + 6.0, sl)
	o2.append(o2[0])
	cv.draw_polyline(o2, Color(edge.r, edge.g, edge.b, edge.a * 0.42), 1.0, true)
	if g > 0.005:
		_draw_hp_tip(bx + fw, y, h, sl, gc)
	# 20% の目印(これ以下は被ダメージ半減。半減のない MOD では出さない)
	if sim == null or sim.low_protect:
		var tx := bx + bw * GameSim.GAUGE_LOW_THRESHOLD + sl
		cv.draw_colored_polygon(PackedVector2Array([Vector2(tx - 4.0, y - 10.0), Vector2(tx + 4.0, y - 10.0), Vector2(tx, y - 4.0)]), Color(1, 1, 1, 0.6))


## 斜めの四角の一部分(高さの f0〜f1 の割合の帯。0 = 上、1 = 下)。頂点は 左上 → 右上 → 右下 → 左下。
func _slant_band(x: float, y: float, w: float, h: float, sl: float, f0: float, f1: float) -> PackedVector2Array:
	var y0 := y + h * f0
	var y1 := y + h * f1
	var o0 := sl * (1.0 - f0)
	var o1 := sl * (1.0 - f1)
	return PackedVector2Array([Vector2(x + o0, y0), Vector2(x + o0 + w, y0), Vector2(x + o1 + w, y1), Vector2(x + o1, y1)])


## 体力バーの先端(xe = 塗りの右端)。先端の線・光・波紋・火花を、状態に応じた動きで描く。
func _draw_hp_tip(xe: float, y: float, h: float, sl: float, gc: Color) -> void:
	var tip := Vector2(xe + sl * 0.5, y + h * 0.5)
	var hit := clampf(_hit_glow, 0.0, 1.0)
	# 先端の光: 回復中は大きく明るく、被弾中は赤く、休憩中は消える
	var glow_a := (0.10 + 0.12 * _fx_regen + 0.08 * hit) * (1.0 - _fx_break)
	var glow_c := gc.lerp(Color(1.0, 0.3, 0.3), hit)
	var r := 8.0 + 5.0 * _fx_regen + 3.0 * hit
	_hp_node.draw_circle(tip, r * 1.5, Color(glow_c.r, glow_c.g, glow_c.b, glow_a * 0.5))
	_hp_node.draw_circle(tip, r, Color(glow_c.r, glow_c.g, glow_c.b, glow_a))
	_hp_node.draw_circle(tip, r * 0.42, Color(1, 1, 1, 0.5 * (1.0 - _fx_break) * (0.4 + 0.6 * _fx_regen)))
	# 先端の線
	var line_c := Color(1, 1, 1, 0.9).lerp(Color(1.0, 0.45, 0.45, 0.95), hit).lerp(Color(0.72, 0.82, 1.0, 0.6), _fx_break)
	_hp_node.draw_line(Vector2(xe + sl + 1.0, y - 2.0), Vector2(xe + 1.0, y + h + 2.0), line_c, lerpf(2.0, 1.4, _fx_break), true)
	# 休憩中: 先端に、静かな波紋がゆっくり広がる(出入りはなめらか)
	if _fx_break > 0.02:
		var p := _hp_ripple
		var e := 1.0 - pow(1.0 - p, 2.0)
		_hp_node.draw_arc(tip, 3.0 + 15.0 * e, 0.0, TAU, 32, Color(0.75, 0.86, 1.0, sin(PI * p) * 0.5 * _fx_break), 1.3, true)
	# 火花
	for s in _hp_sparks:
		var k: float = s.life / s.max
		var col: Color = s.col
		_hp_node.draw_line(s.p, s.p - s.v * 0.04, Color(col.r, col.g, col.b, k * 0.6), 1.3, true)
		_hp_node.draw_circle(s.p, s.size * (0.4 + 0.6 * k), Color(col.r, col.g, col.b, k))


## 体力バー先端の演出の更新(毎フレーム)。状態のなめらかな切り替え、流れる光、波紋、火花の発生と移動。
func _update_hp_fx(delta: float) -> void:
	var g: float = clampf(sim.gauge, 0.0, 1.0)
	var resting: bool = sim.in_break(_now)
	var regen: bool = (not _hit_any) and (not resting) and g < 0.999
	_fx_regen += ((1.0 if regen else 0.0) - _fx_regen) * (1.0 - exp(-delta * 6.0))
	_fx_break += ((1.0 if resting else 0.0) - _fx_break) * (1.0 - exp(-delta * 5.0))
	# 光の流れる速さ: 通常はゆっくり、回復中は速く、休憩中は止まる
	_hp_flow = fmod(_hp_flow + lerpf(45.0, 175.0, _fx_regen) * (1.0 - _fx_break) * delta, _hp_w + 80.0)
	_hp_stripe = fmod(_hp_stripe + lerpf(12.0, 55.0, _fx_regen) * (1.0 - _fx_break) * delta, 20.0)
	_hp_ripple = fmod(_hp_ripple + delta / 1.9, 1.0)
	# 火花の発生
	var tip := Vector2(_hp_x + _hp_w * g + HP_SL * 0.5, _hp_y + HP_H * 0.5)
	var col := UiStyle.hp_color(g).lerp(Color.WHITE, 0.45)
	var rate := 0.0
	if _hit_any:
		rate = 55.0
	elif regen:
		rate = 34.0
	elif not resting and g > 0.0:
		rate = 3.0
	_hp_spawn += rate * delta
	while _hp_spawn >= 1.0 and _hp_sparks.size() < 90:
		_hp_spawn -= 1.0
		if _hit_any:
			# 被弾: 赤い火花が四方へ散る
			var ang := _hp_rng.randf_range(-PI * 0.85, PI * 0.85)
			var life := _hp_rng.randf_range(0.28, 0.55)
			_hp_sparks.append({"p": tip, "v": Vector2.from_angle(ang) * _hp_rng.randf_range(60.0, 170.0), "life": life, "max": life,
				"col": Color(1.0, _hp_rng.randf_range(0.3, 0.6), 0.3), "size": _hp_rng.randf_range(1.4, 2.4)})
		else:
			# 回復・通常: 火の粉が上へ立ちのぼる(回復中のほうが多く、勢いがある)
			var life := _hp_rng.randf_range(0.5, 0.95)
			_hp_sparks.append({"p": tip + Vector2(_hp_rng.randf_range(-3.0, 3.0), _hp_rng.randf_range(-3.0, 3.0)),
				"v": Vector2(_hp_rng.randf_range(6.0, 38.0), _hp_rng.randf_range(-62.0, -20.0)), "life": life, "max": life,
				"col": col, "size": _hp_rng.randf_range(1.3, 2.1)})
	_hp_spawn = minf(_hp_spawn, 1.0)
	# 火花の移動(だんだん減速して消える)
	var i := _hp_sparks.size() - 1
	while i >= 0:
		var s: Dictionary = _hp_sparks[i]
		s.life -= delta
		if s.life <= 0.0:
			_hp_sparks.remove_at(i)
		else:
			s.p += s.v * delta
			s.v *= maxf(1.0 - 2.4 * delta, 0.0)
		i -= 1


## 斜めに切った細長い四角(左上 → 右上 → 右下 → 左下)。上辺が右に sl だけ張り出す。
func _slant(x: float, y: float, w: float, h: float, sl: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x + sl, y), Vector2(x + sl + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])


## 体力が低いときの、画面の左右端の赤み。端が濃く、内側へなめらかに薄れる。
func _draw_low_vignette() -> void:
	var v := clampf(_low_vis + 0.12 * _hit_glow * _low_vis, 0.0, 1.0)
	if v < 0.01:
		return
	var edge := Color(1.0, 0.1, 0.16)
	var w := 130.0 + 60.0 * v
	for layer in range(2):   # 2 枚重ねて、端は濃く内側は素早く薄れる(指数に近い減衰)
		var lw := w * (1.0 if layer == 0 else 0.42)
		var a := (0.36 if layer == 0 else 0.34) * v
		var c0 := Color(edge.r, edge.g, edge.b, a)
		var c1 := Color(edge.r, edge.g, edge.b, 0.0)
		_hud.draw_polygon(PackedVector2Array([Vector2(_view_l, 0), Vector2(_view_l + lw, 0), Vector2(_view_l + lw, _view_b), Vector2(_view_l, _view_b)]), PackedColorArray([c0, c1, c1, c0]))
		_hud.draw_polygon(PackedVector2Array([Vector2(_view_r - lw, 0), Vector2(_view_r, 0), Vector2(_view_r, _view_b), Vector2(_view_r - lw, _view_b)]), PackedColorArray([c1, c0, c0, c1]))


## 体力バーの層(自機が近づくと、この層ごと薄くなる)。
func _draw_hp_layer() -> void:
	var g: float = clampf(sim.gauge, 0.0, 1.0) if sim != null else 1.0
	_draw_hp_bar(ThemeDB.fallback_font, _hp_x, _hp_y, g)


## スコアの層(自機が近づくと薄くなる)。被ダメージで点が減っている間は、数字が赤くなる。
func _draw_score() -> void:
	var font := ThemeDB.fallback_font
	var right := ARENA_POS.x + PatternGen.ARENA.x - 28.0   # フィールド右端の内側
	var score_text := UiStyle.fmt(int(round(_score_disp)))
	var prog_pct: float = (sim.progress if sim != null else 0.0) * 100.0
	var dy := _score_dy
	var score_c := Color(1, 1, 1, 0.97).lerp(Color(1.0, 0.27, 0.31, 1.0), _score_red)
	_sc_node.draw_string(font, Vector2(right - 400.0, 24 + dy), "SCORE", HORIZONTAL_ALIGNMENT_RIGHT, 400.0, 12, Color(1, 1, 1, 0.55).lerp(Color(1.0, 0.4, 0.42, 0.85), _score_red))
	_sc_node.draw_string(_score_font, Vector2(right - 400.0 + 2.0, 74.0 + 2.0 + dy), score_text, HORIZONTAL_ALIGNMENT_RIGHT, 400.0, 48, Color(0, 0, 0, 0.5))
	_sc_node.draw_string(_score_font, Vector2(right - 400.0, 74.0 + dy), score_text, HORIZONTAL_ALIGNMENT_RIGHT, 400.0, 48, score_c)
	# 進行率(撃破 MOD では曲が繰り返すので、代わりに何周目か)
	var sub := ("LOOP %d" % (sim.loop_index(_now) + 1)) if sim.loop_len > 0.0 else "%.2f%%" % prog_pct
	_sc_node.draw_string(font, Vector2(right - 400.0, 102.0 + dy), sub, HORIZONTAL_ALIGNMENT_RIGHT, 400.0, 20, Color(0.62, 0.9, 1.0, 0.9))


## キアイ中の光を更新する。キアイの出入りはなめらかに、光は拍の頭で立ち上がって(約 40ms)次の拍に向けて消えていく。
## 譜面上の時刻(ms)= (曲クロック − オフセット) × 再生速度 × 1000。曲(音)の拍に合わせたいので、オフセットは引いて数える。
func _update_kiai(delta: float, instant := false) -> void:
	var t_ms := (_now - float(settings.get("offset_ms", 0)) / 1000.0) * _rate * 1000.0
	var on: bool = _audio_started and not _dead and not sim.finished and bm.kiai_at(t_ms)
	var target := 1.0 if on else 0.0
	_kiai_a = target if instant else _kiai_a + (target - _kiai_a) * (1.0 - exp(-delta * 4.0))
	var ph: float = bm.beat_phase_at(t_ms)
	var pulse := smoothstep(0.0, 0.08, ph) * exp(-ph * 3.6)
	if _soft:   # 目に優しい表示: 拍ごとの明暗を小さくする(光の下限と、振れ幅を KIAI_SOFT 倍に)
		pulse *= KIAI_SOFT
	_beat_glow = _kiai_a * (KIAI_BASE + (1.0 - KIAI_BASE) * pulse)
	_apply_kiai()


func _apply_kiai() -> void:
	var k := 1.0 + KIAI_BG_GAIN * _beat_glow
	if _bg_img != null:
		_bg_img.modulate = Color(BG_TINT.r * k, BG_TINT.g * k, BG_TINT.b * k * 1.06)
	_arena_bg.color.a = (SOFT_BG_ALPHA if _soft else ARENA_BG_ALPHA) - KIAI_ARENA_DIM * _beat_glow
	field.halo = _beat_glow


## 点 p と矩形 r の距離(中にあれば 0)。
func _dist_to_rect(p: Vector2, r: Rect2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return sqrt(dx * dx + dy * dy)


## 自機が体力バーやスコアに重なりそうになったら、それらを薄くして自機と弾を見やすくする(なめらかに出入り)。
## 自機の縁から HUD_FADE_DIST px 以内に入ると薄れ始め、重なると HUD_FADE_MIN まで下がる。
func _update_hud_fade(delta: float, instant := false) -> void:
	var pp: Vector2 = ARENA_POS + sim.player_pos
	var pr: float = 14.0 * sim.player_scale
	var hp_rect := Rect2(_hp_x - 26.0, _hp_y - 22.0, _hp_w + HP_SL + 52.0, HP_H + 46.0)
	var right := ARENA_POS.x + PatternGen.ARENA.x - 28.0
	var sc_rect := Rect2(right - 300.0, 6.0 + _score_dy, 306.0, 124.0)
	var k := 1.0 if instant else 1.0 - exp(-delta * 12.0)
	for spec in [[hp_rect, 0], [sc_rect, 1]]:
		var d := maxf(_dist_to_rect(pp, spec[0]) - pr, 0.0)
		var target := lerpf(HUD_FADE_MIN, 1.0, smoothstep(0.0, HUD_FADE_DIST, d))
		if spec[1] == 0:
			_hp_a += (target - _hp_a) * k
		else:
			_sc_a += (target - _sc_a) * k
	_hp_node.modulate.a = _hp_a
	_sc_node.modulate.a = _sc_a
	if _boss_gauge != null:   # ボスのゲージも、自機が近づくと薄くなる
		var gd := maxf(_dist_to_rect(pp, Rect2(BossGauge.X - 10.0, 0.0, BossGauge.W + 40.0, 64.0)) - pr, 0.0)
		var gt := lerpf(0.3, 1.0, smoothstep(0.0, HUD_FADE_DIST, gd))
		_boss_gauge.modulate.a += (gt - _boss_gauge.modulate.a) * k


func _draw_hud() -> void:

	var ax := ARENA_POS.x

	# --- 体力が低いときの、画面の左右端の赤み(残量に応じてなめらかに強まる。点滅・脈動なし) ---
	_draw_low_vignette()


	# 休憩のカウントダウン(フィールド中央の輪と、残り秒)
	if _break_a > 0.01:
		_draw_break_count()

	# 進行バー(フィールド下端。休憩地帯は淡い区間で示す)
	# 撃破 MOD では曲が繰り返すので、いまの周の中の位置を出す(時刻は 1 周目に戻して数える)
	var span := maxf(_end_time, 1.0)
	var shift := 0.0
	if sim != null and sim.loop_len > 0.0:
		span = sim.loop_end + Boss.BONUS_TIME
		shift = float(sim.loop_index(_now)) * sim.loop_len
	var pr := clampf((_now - shift) / span, 0.0, 1.0)
	var aw: float = PatternGen.ARENA.x
	_hud.draw_rect(Rect2(ax, 716, aw, 4), Color(1, 1, 1, 0.08))
	if sim != null:
		for b in sim.breaks:
			var x0 := clampf((float(b[0]) - shift) / span, 0.0, 1.0)
			var x1 := clampf((float(b[1]) - shift) / span, 0.0, 1.0)
			if x1 - x0 > 0.0:
				_hud.draw_rect(Rect2(ax + x0 * aw, 716, maxf((x1 - x0) * aw, 1.0), 4), Color(1, 1, 1, 0.22))
	_hud.draw_rect(Rect2(ax, 716, aw * pr, 4), Color(0.5, 0.9, 1.0, 0.9))
	_draw_bonus_hud()
	# アリーナ枠
	_hud.draw_rect(Rect2(ARENA_POS, PatternGen.ARENA), Color(1, 1, 1, 0.35).lerp(Color(1.0, 0.35, 0.38, 0.75), clampf(_hit_glow, 0.0, 1.0)), false, 2.0)   # 被弾中は枠がなめらかに赤くなる

## いま、マウスを捕まえて(相対移動で)自機を動かしている状態のはずか(ポーズ・演出中・ゲームオーバー・スキップのボタンを押せる間は、違う)。
func _should_capture() -> bool:
	return _mouse_mode and _arrived and not _guiding and not _menu_open() and not _dead and not _skip_free and not _done


## ウィンドウのフォーカスが戻った(Alt+Tab・別のウィンドウをクリックしたあと)。
## 捕まえているはずなら、いったん外してから掛け直す(Input.mouse_mode は、同じ値を入れても何も起きないので、外すところから)。
## 外れたあとの「捕まえたまま」では、マウスの移動量が届かず、自機が動かなくなることがあるため。
func _on_window_focus_in() -> void:
	if _should_capture():
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		_capture_mouse()


func _capture_mouse() -> void:
	# カーソルを隠して移動量だけを受け取る(自機とカーソルがずれない)
	_mouse_accum = Vector2.ZERO
	_mouse_capture_ms = Time.get_ticks_msec()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_key_input(event: InputEvent) -> void:
	if not replay_data.is_empty():
		if event is InputEventKey and event.pressed:
			_replay_key(event)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if _resume_wait:   # 再開の待ち: Esc でポーズへ戻る / 移動キー・Space・Enter で、動き出す
		if event.keycode == KEY_ESCAPE:
			_set_paused(true)
		elif _wait_lock <= 0.0 and RESUME_KEYS.has(event.keycode):
			_finish_resume()
		return
	match event.keycode:
		KEY_SPACE:
			if _can_skip():
				_request_skip()
		KEY_ESCAPE:
			if _end_timer < 0.0 and _outro_t < 0.0:
				if _mp == null and not _paused and _pause_cd > 0.0:
					UiSfx.play("deny")   # 再開したばかり: まだポーズできない
				else:
					_set_paused(not _menu_open())
		KEY_UP, KEY_DOWN:
			if _menu_open():
				var d := -1 if event.keycode == KEY_UP else 1
				for _i in range(PAUSE_ROWS):
					_pause_sel = (_pause_sel + d + PAUSE_ROWS) % PAUSE_ROWS
					if not (_mp != null and _pause_sel == 1):   # マルチプレイにリトライはない
						break
				UiSfx.play("select", 1.0 + 0.1 * _pause_sel)
				if _pause_sel < _pause_btns.size():   # 選んだボタンが、ぴょこっと弾む
					_pause_btns[_pause_sel].pivot_offset = _pause_btns[_pause_sel].size * 0.5
					UiStyle.spring(_pause_btns[_pause_sel], "scale", Vector2(1.06, 1.06), Vector2.ONE, 0.3)
				_refresh_pause()
		KEY_LEFT, KEY_RIGHT:
			if _menu_open() and _pause_sel >= 3:   # 選んでいる音量の行だけを動かす(ボタンの行では、何も起きない)
				var d := -5 if event.keycode == KEY_LEFT else 5
				match _pause_sel:
					3:
						_set_master_volume(int(settings.get("volume", 80)) + d)
					4:
						_set_music_volume(int(settings.get("music_volume", 100)) + d)
					_:
						_set_sfx_volume(int(settings.get("sfx_volume", 70)) + d)
		KEY_ENTER, KEY_KP_ENTER:
			if _menu_open() and _pause_sel < 3:
				_pause_activate(_pause_sel)
		KEY_R:
			if _menu_open() and _mp == null:
				_audio.stop()
				retry_requested.emit()
		KEY_Q:
			if _menu_open():
				_audio.stop()
				quit_requested.emit()


## イントロ(最初のノーツまでの何もない区間)を飛ばした先の曲時間。最初のノーツの SKIP_LEAD 秒前。
func _skip_target() -> float:
	if sim.boss != null:   # 撃破: ボスの登場(WARNING)が見えるところまで
		return sim.boss.appear_t - 1.4
	return sim.first_fire_time - SKIP_LEAD


## スキップできるか。最初のノーツの前で、進む幅が SKIP_MIN_GAIN 秒以上あるとき(マルチプレイは、開始の合図のあと)。
func _can_skip() -> bool:
	if sim == null or _skipped or _paused or _mp_menu or _dead or _end_timer >= 0.0 or _outro_t >= 0.0 or debug_seek >= 0.0 or sim.first_fire_time < 0.0 or not replay_data.is_empty():
		return false
	if _mp != null and not _mp.started:
		return false
	return _skip_target() - maxf(_now, 0.0) >= SKIP_MIN_GAIN


## スキップを押した(Space・ボタン)。ひとりなら、すぐ飛ばす。マルチプレイは、全員が押すまで待つ。
func _request_skip() -> void:
	if _mp == null:
		_skip_intro()
	else:
		_mp.request_skip()


## 曲(と曲クロック)を最初のノーツの直前まで進める。READY 中に押した場合は、そこから再生を始める。
## extra: マルチプレイで、全員が押してから経った秒(その分だけ先へ進める)。
func _skip_intro(extra := 0.0) -> void:
	if _skipped:
		return
	_skipped = true
	var target := _skip_target() + extra
	var pos := maxf(target - float(settings.get("offset_ms", 0)) / 1000.0, 0.0) * _rate   # 曲クロック = 再生位置 ÷ rate + オフセット
	if _audio_started:
		_audio.seek(pos)
	else:
		_audio.play(pos)
		_audio_started = true
		_arrive()
		_fade_out_center()
	_now = target
	_sim_t = target   # 判定側も一気に進める(イントロには弾がない)
	UiSfx.play("select", 1.3)
	_refresh()


# --- スキップのボタン ---

## 左のパネルに、いま受けているデバフの名前(危険エリアの中にいる間)。
func _update_debuff_label() -> void:
	if _debuff_l == null or sim.zone_debuff == _debuff_shown:
		return
	_debuff_shown = sim.zone_debuff
	_debuff_l.visible = _debuff_shown != ""
	if _debuff_shown != "":
		_debuff_l.text = "%s  %s" % [GameSim.zone_family_name(_debuff_shown), GameSim.zone_name(_debuff_shown)]
		_debuff_l.add_theme_color_override("font_color", GameSim.zone_color(_debuff_shown))


func _build_skip_button() -> void:
	_skip_btn = Button.new()
	_skip_btn.focus_mode = Control.FOCUS_NONE
	_skip_btn.position = ARENA_POS + Vector2(PatternGen.ARENA.x * 0.5 - 130.0, 640.0)
	_skip_btn.size = Vector2(260, 46)
	_skip_btn.visible = false
	_skip_btn.add_theme_font_size_override("font_size", 18)
	_skip_btn.add_theme_stylebox_override("normal", UiStyle.box(Color(0.03, 0.035, 0.06, 0.85), Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.8), 2, 6, 14, 8))
	_skip_btn.add_theme_stylebox_override("hover", UiStyle.box(Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.22), UiStyle.ACCENT, 2, 6, 14, 8))
	_skip_btn.add_theme_stylebox_override("pressed", UiStyle.box(Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.4), UiStyle.ACCENT, 2, 6, 14, 8))
	_skip_btn.pressed.connect(func(): if _can_skip(): _request_skip())
	add_child(_skip_btn)
	move_child(_skip_btn, _arena.get_index())   # アリーナ(自機)より奥: 自機をボタンに重ねても、自機が文字に隠れない


## ボタンの表示と、マウスの扱いを合わせる。スキップできる間は、マウスを捕まえず(カーソルが見えて、ボタンを押せる)、
## できなくなったら(飛ばした・間に合わなくなった)自機の位置へ戻して捕まえる。
func _update_skip_button() -> void:
	if _skip_btn == null:
		return
	var can := _can_skip()
	if _skip_btn.visible != can:
		_skip_btn.visible = can
	if can:
		var voted: bool = _mp != null and _mp.skip_mine
		var cnt := ""
		if _mp != null:
			cnt = "  %d/%d" % [_mp.skip_n, _mp.skip_total]
		_skip_btn.text = ("スキップ待ち" if voted else "スキップ") + cnt + "   [Space]"
		_skip_btn.add_theme_stylebox_override("normal", UiStyle.box(Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.35) if voted else Color(0.03, 0.035, 0.06, 0.85),
			Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.8), 2, 6, 14, 8))
	if not _mouse_mode or not _arrived or _menu_open() or _dead:
		return
	if can and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_skip_free = true
		_mouse_accum = Vector2.ZERO
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		Input.warp_mouse(get_viewport().get_screen_transform() * (ARENA_POS + sim.player_pos))   # 自機がマウスの位置へ跳ばないように
	elif not can and _skip_free:
		_skip_free = false
		Input.warp_mouse(get_viewport().get_screen_transform() * (ARENA_POS + sim.player_pos))
		_capture_mouse()
	if _ship_is_cursor():   # 自機が動ける範囲の中では、独自カーソルを出さない(自機とカーソルが 2 つ並ばない)。小型化で範囲の外にあるボタンへは、自機が届かないので、外ではカーソルを出す
		var m: float = GameSim.PLAYER_MARGIN * sim.player_scale
		CursorOverlay.hide_in(Rect2(ARENA_POS + sim.move_rect.position + Vector2(m, m), sim.move_rect.size - Vector2(m, m) * 2.0))


## スキップのボタンを押せる間(マウスを捕まえていない): 自機がマウスの位置へそのまま動き、カーソルの代わりになる。
## 自機をボタンへ重ねてクリックすれば押せる。スキップできなくなったら、その位置のままマウスを捕まえる(自機は跳ばない)。
func _ship_is_cursor() -> bool:
	return _mouse_mode and _skip_free and _arrived and not _menu_open() and not _dead \
		and Input.mouse_mode == Input.MOUSE_MODE_HIDDEN


func _set_paused(p: bool) -> void:
	if _mp != null:   # マルチプレイ: 他の人がいるので、ゲームは止めない。メニューを重ねるだけ(自機は動かさない)
		_mp_menu = p
		_pause_layer.visible = p
		UiSfx.play("open" if p else "close")
		if p:
			_pause_sel = 0
			_refresh_pause()
			_pause_panel.pivot_offset = _pause_panel.size * 0.5
			UiStyle.tween(_pause_layer, "modulate:a", 0.0, 1.0, 0.18)
			_pause_enter()
		if _mouse_mode:
			if p:
				Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
			else:
				_capture_mouse()
		return
	if not p:   # ポーズから戻る: すぐには動かさず、自機だけを見せて、使う人の操作を待つ
		_begin_resume_wait()
		return
	_paused = true
	_resume_wait = false
	_show_resume_hint(false)
	_set_ship_only(false)
	_pause_layer.visible = true
	UiSfx.play("open")
	field.visible = false   # 弾の描画そのものを止める(アリーナの外にはみ出した弾も、見えないように)
	field.modulate.a = 1.0
	_pause_sel = 0
	_refresh_pause()
	_pause_panel.pivot_offset = _pause_panel.size * 0.5
	UiStyle.tween(_pause_layer, "modulate:a", 0.0, 1.0, 0.18)
	UiStyle.spring(_pause_panel, "scale", Vector2(0.9, 0.9), Vector2.ONE, 0.4)
	_pause_enter()
	if _audio_started:
		_audio.stream_paused = true
	if _mouse_mode:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


## 「再開」を押したあと: アリーナには自機(と、その周りの輪)だけを見せ、ゲームは止めたまま、使う人の操作を待つ。
## 弾は見せない(止めた弾を観察できないように)。マウスは、自機がカーソルになるよう捕まえておく(動かしても、自機はまだ動かない)。
func _begin_resume_wait() -> void:
	UiSfx.play("close")
	_resume_wait = true
	_wait_t = 0.0
	_wait_lock = 0.3
	_pause_layer.visible = false
	_set_ship_only(true)
	if _skip_btn != null:
		_skip_btn.visible = false   # 待ちの間、Space は「動き出す」操作になるので、スキップの案内は隠す(動き出したら、また出る)
	_show_resume_hint(true)
	if _mouse_mode:
		_capture_mouse()


## 再開の待ちの案内(どうすれば動き出すか)。自機のすぐ下(下の端に近いときは上)に、短く出す。
func _show_resume_hint(on: bool) -> void:
	if _resume_hint == null:
		if not on:
			return
		_resume_hint = UiStyle.label("", 18, UiStyle.TEXT, true)
		_resume_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_resume_hint.size = Vector2(320, 26)
		_resume_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_resume_hint.add_theme_constant_override("outline_size", 5)
		add_child(_resume_hint)
	_resume_hint.visible = on
	if not on:
		return
	_resume_hint.text = "クリックで再開" if _mouse_mode else "移動キー・Space で再開"
	var below: bool = sim.player_pos.y < PatternGen.ARENA.y - 110.0
	_resume_hint.position = ARENA_POS + sim.player_pos + Vector2(-160.0, 66.0 if below else -92.0)
	UiStyle.tween(_resume_hint, "modulate:a", 0.0, 1.0, 0.25)


func _tick_resume_wait(delta: float) -> void:
	_wait_t += delta
	_wait_lock = maxf(_wait_lock - delta, 0.0)
	_view_over.wait_t = _wait_t
	_view_over.queue_redraw()


## 操作された: ゲームが進み始め、弾が RESUME_VEIL 秒かけて現れる。そこから PAUSE_COOLDOWN 秒は、またポーズできない。
func _finish_resume() -> void:
	_resume_wait = false
	_show_resume_hint(false)
	_paused = false
	_set_ship_only(false)
	_pause_cd = PAUSE_COOLDOWN
	field.visible = true
	field.modulate.a = 0.0
	UiStyle.tween(field, "modulate:a", 0.0, 1.0, RESUME_VEIL, 0.0, Tween.TRANS_QUAD, Tween.EASE_IN)
	if _audio_started:
		_audio.stream_paused = false
	if _mouse_mode:
		_capture_mouse()


## 自機だけを描く状態にする(再開の待ち)/ 元に戻す。
func _set_ship_only(on: bool) -> void:
	_view_under.ship_only = on
	_view_over.ship_only = on
	_view_under.sync_sliders()
	_view_under.queue_redraw()
	_view_over.queue_redraw()


## ポーズを開いたとき、ボタンが上から順に弾んで現れる。
func _pause_enter() -> void:
	var k := 0
	for b in _pause_btns:
		if b.visible:
			UiStyle.pop_scale(b, 0.9, 0.32, 0.06 + 0.05 * k)
			k += 1


## ポーズ(マルチプレイでは、ゲームを止めないメニュー)が開いているか。
func _menu_open() -> bool:
	return _paused or _mp_menu


## R の長押しでリトライ(プレイ中・ゲームオーバーの演出中。ひとりのときだけ)。押している間は、アリーナの上に進み具合の輪を出す。
## リトライしたら true(このフレームの処理をやめる)。
func _update_retry_hold(delta: float) -> bool:
	var held := Input.is_physical_key_pressed(KEY_R)
	if not held:
		_retry_armed = true
	if held and _retry_armed and _mp == null and not _menu_open():
		_retry_hold += delta
	else:
		_retry_hold = maxf(_retry_hold - delta * 4.0, 0.0)   # 離したら、すばやく戻る
	if _retry_hold > 0.0 or (_retry_ui != null and _retry_ui.modulate.a > 0.0):
		_update_retry_ui()
	if _retry_hold < RETRY_HOLD:
		return false
	_done = true
	UiSfx.play("confirm")
	_audio.stop()
	retry_requested.emit()
	return true


func _update_retry_ui() -> void:
	if _retry_ui == null:
		_retry_ui = Control.new()
		_retry_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_retry_ui.position = ARENA_POS + Vector2(PatternGen.ARENA.x * 0.5 - 60.0, 84.0)
		_retry_ui.size = Vector2(120, 96)
		_retry_ui.draw.connect(_draw_retry_ui)
		add_child(_retry_ui)
	_retry_ui.modulate.a = clampf(_retry_hold / 0.12, 0.0, 1.0)
	_retry_ui.queue_redraw()


## R 長押しの輪: 暗い円の上に、押している長さだけ時計回りに伸びる輪と「リトライ」。
func _draw_retry_ui() -> void:
	var c := Vector2(60, 32)
	var k := clampf(_retry_hold / RETRY_HOLD, 0.0, 1.0)
	var a := UiStyle.ACCENT
	_retry_ui.draw_circle(c, 29.0, Color(0, 0, 0, 0.55))
	_retry_ui.draw_arc(c, 24.0, 0.0, TAU, 48, Color(1, 1, 1, 0.15), 4.0, true)
	if k > 0.0:
		_retry_ui.draw_arc(c, 24.0, -PI * 0.5, -PI * 0.5 + TAU * k, 48, a, 4.5, true)
	var font := UiStyle.bold()
	_retry_ui.draw_string(font, c + Vector2(-30, 7), "R", HORIZONTAL_ALIGNMENT_CENTER, 60.0, 20, Color(1, 1, 1, 0.95))
	_retry_ui.draw_string_outline(font, Vector2(0, 84), "リトライ", HORIZONTAL_ALIGNMENT_CENTER, 120.0, 15, 5, Color(0, 0, 0, 0.8))
	_retry_ui.draw_string(font, Vector2(0, 84), "リトライ", HORIZONTAL_ALIGNMENT_CENTER, 120.0, 15, Color(a.r, a.g, a.b, 0.95))


## ポーズ画面の項目の実行(0 = 再開、1 = リトライ、2 = メニューへ)。
func _pause_activate(i: int) -> void:
	match i:
		0:
			_set_paused(false)
		1:
			if _mp != null:
				return
			_audio.stop()
			retry_requested.emit()
		2:
			_audio.stop()
			quit_requested.emit()


func _set_master_volume(v: int) -> void:
	settings.volume = clampi(v, 0, 100)
	Settings.apply_volume(settings.volume)
	Settings.save_all(settings)
	_refresh_pause()


func _set_music_volume(v: int) -> void:
	settings.music_volume = clampi(v, 0, 100)
	Volume.set_music(settings.music_volume)
	Settings.save_all(settings)
	_refresh_pause()


func _set_sfx_volume(v: int) -> void:
	settings.sfx_volume = clampi(v, 0, 100)
	Volume.set_sfx(settings.sfx_volume)
	_vol_rev = Volume.rev
	_sfx.volume = settings.sfx_volume / 100.0
	_sfx.play("pop")
	Settings.save_all(settings)
	_refresh_pause()


## ポーズ画面の表示を、今の設定・選択に合わせる。
func _refresh_pause() -> void:
	if Volume.loaded:   # ホイールで変えた値も出す
		settings.volume = Volume.master
		settings.music_volume = Volume.music
		settings.sfx_volume = Volume.sfx
	for i in range(_pause_btns.size()):   # 選択中の行は、アクセント色の枠(ボタンも、音量の行も同じ見た目)
		_pause_btns[i].add_theme_stylebox_override("normal", _pause_row_style(i == _pause_sel, 16.0, 8.0))
	var rows := [_pause_vol, _pause_music, _pause_sfx]
	var keys := ["volume", "music_volume", "sfx_volume"]
	var defaults := [80, 100, 70]
	for k in range(rows.size()):
		var row: Array = rows[k]
		var value := int(settings.get(keys[k], defaults[k]))
		row[0].set_value_no_signal(value)
		row[1].text = "%d%%" % value
		row[2].add_theme_color_override("font_color", UiStyle.ACCENT if _pause_sel == 3 + k else UiStyle.TEXT)
		(row[3] as PanelContainer).add_theme_stylebox_override("panel", _pause_row_style(_pause_sel == 3 + k, 14.0, 4.0))


func _pause_row_style(selected: bool, mh: float, mv: float) -> StyleBoxFlat:
	return UiStyle.box(
		Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.16) if selected else Color(1, 1, 1, 0.05),
		UiStyle.ACCENT if selected else UiStyle.LINE, 1, 4, mh, mv)


func _input(event: InputEvent) -> void:
	if _resume_wait and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _wait_lock <= 0.0:
		_finish_resume()   # 再開の待ち: クリックで動き出す
		get_viewport().set_input_as_handled()
		return
	if _mouse_mode and not _guiding and not _paused and not _mp_menu and not _dead and (_mp == null or _mp.started) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event is InputEventMouseMotion:
		# モード切替直後の初期イベント(カーソルの中央移動)は無視する
		if Time.get_ticks_msec() - _mouse_capture_ms > 200:
			_mouse_accum += event.relative


## 体力が低いときの赤みの目標(0..1)。35% 以下から出はじめ、0 に近づくほど強くなる(なめらかな曲線)。
func _low_target() -> float:
	var x := clampf((0.35 - sim.gauge) / 0.35, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## READY をなめらかに消す。
func _fade_out_center() -> void:
	if not UiStyle.animate:
		_center_label.visible = false
		return
	# 曲が始まる瞬間に READY が「GO」に変わり、少し膨らみながら消える
	_center_label.text = "GO"
	_center_label.modulate.a = 1.0
	_center_label.pivot_offset = _center_label.size * 0.5   # ラベルの真ん中を軸に弾む
	UiStyle.spring(_center_label, "scale", Vector2(0.8, 0.8), Vector2(1.15, 1.15), 0.3)
	var t := _center_label.create_tween()
	t.tween_interval(0.12)
	t.tween_property(_center_label, "modulate:a", 0.0, 0.4)
	t.tween_callback(func(): _center_label.visible = false)


## HUD の細かい動き: グレイズの数字が弾む / 被弾中はダメージ量が赤くなる / スキップ案内がなめらかに出入りする。
func _animate_hud(delta: float) -> void:
	_update_hp_fx(delta)
	_update_mp_rows(delta)
	_low_vis += (_low_target() - _low_vis) * (1.0 - exp(-delta * 4.0))   # 赤みは、残量の変化にゆっくり追従する
	if sim.graze > _last_graze:
		_graze_pop = 1.0
		_last_graze = sim.graze
	_graze_pop = maxf(_graze_pop - delta * 5.0, 0.0)
	var s := 1.0 + 0.16 * _graze_pop * _graze_pop
	_graze_l.pivot_offset = Vector2(0.0, _graze_l.size.y * 0.5)
	_graze_l.scale = Vector2(s, s)
	_hit_l.add_theme_color_override("font_color", UiStyle.TEXT.lerp(UiStyle.DANGER, clampf(_hit_glow, 0.0, 1.0)))
	_update_hud_fade(delta)
	_update_kiai(delta)
	_dark_scale += ((DARK_SLOW_SCALE if sim.slow else 1.0) - _dark_scale) * (1.0 - exp(-delta * 9.0))
	_tick_break_count(delta)
	_update_boss_hud(delta)


## 撃破 MOD: ボスのゲージ・右パネルの強化を更新し、アイテムを取った・倒したときに音と演出を出す。
func _update_boss_hud(delta: float) -> void:
	var b = sim.boss
	if b == null:
		return
	if _boss_gauge != null:
		_boss_gauge.tick(delta, _now)
	_update_weapon_labels()
	while _pick_seen < b.pick_events.size():
		var ev: Dictionary = b.pick_events[_pick_seen]
		_pick_seen += 1
		if not _dead:
			_item_fx(str(ev.kind), ev.p)
	if b.defeated and not _boss_down_seen:
		_boss_down_seen = true
		_sfx.play("boom", 1.0, clampf(b.defeat_pos.x / PatternGen.ARENA.x * 2.0 - 1.0, -1.0, 1.0))   # explosion はゲームオーバーの音なので使わない
		UiSfx.play("stamp", 0.9)
		if not _dead:   # 中央に「BOSS DEFEATED」(このあとクリア)
			_center_label.text = "BOSS DEFEATED"
			_center_label.add_theme_color_override("font_color", UiStyle.GOLD)
			_center_label.visible = true
			_center_label.modulate.a = 1.0
			_center_label.pivot_offset = _center_label.size * 0.5
			UiStyle.spring(_center_label, "scale", Vector2(1.4, 1.4), Vector2.ONE, 0.35)


## 撃破 MOD: 上部のボスのゲージを作る(WARNING の重い音・節目の音をつなぐ)。
func _build_boss_gauge() -> void:
	_boss_gauge = BossGauge.new()
	_boss_gauge.boss = sim.boss
	_boss_gauge.warned.connect(func():
		_sfx.play("boom")
		UiSfx.play("whoosh", 0.7))
	_boss_gauge.phase_crossed.connect(func(): UiSfx.play("whoosh", 1.25))
	_hud.add_child(_boss_gauge)


## アイテムを取ったときの音と演出(種類の色の輪・粒と、効果の名前が自機の上に浮かぶ)。ボムは盤面いっぱいに輪が広がる。
func _item_fx(kind: String, at: Vector2) -> void:
	var spec: Dictionary = Boss.ITEMS[kind]
	var c: Color = spec.color
	UiSfx.play("confirm", {"power": 1.2, "rate": 1.35, "wide": 1.1, "heal": 1.5, "bomb": 0.8}.get(kind, 1.2))
	UiFx.ring(_arena, sim.player_pos, Color(c.r, c.g, c.b, 0.9), 8.0, 50.0, 0.4, 2.5)
	UiFx.burst(_arena, at, c, 10, 140.0, 0.45, 2.5)
	if kind == "bomb":
		_sfx.play("boom", 1.0, clampf(sim.player_pos.x / PatternGen.ARENA.x * 2.0 - 1.0, -1.0, 1.0))
		UiFx.ring(_arena, sim.player_pos, Color(1.0, 0.85, 0.45, 0.85), 20.0, 1100.0, 0.7, 6.0)
		UiFx.ring(_arena, sim.player_pos, Color(1.0, 1.0, 1.0, 0.6), 10.0, 800.0, 0.55, 3.0)
	elif kind == "heal":
		UiFx.ring(_arena, sim.player_pos, Color(c.r, c.g, c.b, 0.7), 34.0, 8.0, 0.5, 3.0)
	if not UiStyle.animate:
		return
	var lv: int = sim.boss.level_of(kind)
	var mx: int = spec.max
	var text: String = spec.name
	if mx > 0:
		text += "  MAX" if lv >= mx else "  Lv%d" % lv
	var l := UiStyle.label(text, 15, c.lerp(Color.WHITE, 0.35), true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(200, 22)
	l.position = sim.player_pos - Vector2(100, 48)
	_arena.add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 34.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)


## 右パネルの強化の段階(変わったときだけ書き換える)。
func _update_weapon_labels() -> void:
	var b = sim.boss
	if b == null or _weapon_ls.is_empty():
		return
	var key := "%d_%d_%d" % [b.power, b.rate_lv, b.wide_lv]
	if key == _weapon_seen:
		return
	_weapon_seen = key
	var rows := {"power": "攻撃  ×%.2f" % b.power_mul, "rate": "連射  ×%.2f" % (1.0 + Boss.RATE_STEP * b.rate_lv), "wide": "ワイド  %d 列" % Boss.WIDE_OFFSETS[b.wide_lv].size()}
	for k in rows:
		var l: Label = _weapon_ls[k]
		var lv: int = b.level_of(k)
		l.text = rows[k] + ("  MAX" if lv >= int(Boss.ITEMS[k].max) else "")
		var c: Color = Boss.ITEMS[k].color
		l.add_theme_color_override("font_color", c.lerp(Color.WHITE, 0.3) if lv > 0 else UiStyle.TEXT_DIM)


## 撃破 MOD: ボーナスタイムの早送りを始める(曲の音程と速さが上がっていく)。
func _begin_ff() -> void:
	_ff_t = 0.0
	_ff_jumped = false
	UiSfx.play("whoosh", 1.3)


## 撃破 MOD: 早送りを 1 フレーム進める。曲クロックは実時間で進め、曲の速さ(音程)を 1 → FF_PEAK → 1 倍に動かし、
## 半分のところで曲の位置を、終わりにちょうど次の周の始まりに着くところへ飛ばす。終わったら次の周へ。
func _tick_ff(delta: float) -> void:
	var dur: float = Boss.BONUS_TIME
	_ff_t += delta
	_now += delta
	var u := clampf(_ff_t / dur, 0.0, 1.0)
	var f := 1.0 + (FF_PEAK - 1.0) * sin(PI * u)
	if not _dead:
		_audio.pitch_scale = _rate * f
		_audio.volume_db = linear_to_db(1.0 - 0.3 * sin(PI * u))   # 速いところで少しだけ下げる
	var land: float = sim.loop_from * _rate   # 着く先(曲の秒)
	if not _ff_jumped and _ff_t >= dur * 0.5 and not _dead:
		_ff_jumped = true
		# 残りで進む曲の秒 = rate × ∫[u·dur, dur] (1 + (FF_PEAK − 1) sin(πτ/dur)) dτ = rate × (dur(1 − u) + (FF_PEAK − 1) dur/π (1 + cos πu))
		var rest := _rate * (dur * (1.0 - u) + (FF_PEAK - 1.0) * dur / PI * (1.0 + cos(PI * u)))
		var to := maxf(land - rest, 0.0)
		if _audio.playing:
			_audio.seek(to)
		else:
			_audio.play(to)
	if _ff_t >= dur:
		_ff_t = -1.0
		_loop_k += 1
		_now = maxf(_now, float(_loop_k) * sim.loop_len + sim.loop_from)
		_end_ff()
		if not _dead:
			UiSfx.play("whoosh", 0.8)
			_show_loop_banner()


## 早送りの後始末: ふつうの速さ・音量に戻し、曲の位置が次の周の始まりからずれていれば合わせる(早送りの途中で呼ばれたときも)。
func _end_ff() -> void:
	if sim.loop_len <= 0.0:
		return
	var mid := _ff_t >= 0.0
	_ff_t = -1.0
	if _dead:
		return
	_audio.pitch_scale = _rate
	_audio.volume_db = 0.0
	if mid:   # 途中(クリアなど): 次の周の始まりへ
		_audio.seek(sim.loop_from * _rate)
		return
	var want: float = sim.loop_from * _rate
	if absf(_audio.get_playback_position() - want) > 0.05:
		_audio.seek(want)


## 撃破 MOD: 次の周に入ったとき、中央に「LOOP n」が弾んで出て、消える。
func _show_loop_banner() -> void:
	if sim.boss == null or sim.boss.defeated or not UiStyle.animate:
		return
	_center_label.text = "LOOP %d" % (_loop_k + 1)
	_center_label.add_theme_color_override("font_color", Color(0.62, 0.9, 1.0))
	_center_label.visible = true
	_center_label.modulate.a = 1.0
	_center_label.pivot_offset = _center_label.size * 0.5
	UiStyle.spring(_center_label, "scale", Vector2(1.35, 1.35), Vector2.ONE, 0.35)
	var t := _center_label.create_tween()
	t.tween_interval(0.5)
	t.tween_property(_center_label, "modulate:a", 0.0, 0.4)
	t.tween_callback(func():
		if not _dead and not (sim.boss != null and sim.boss.defeated):
			_center_label.visible = false)


## 撃破 MOD: ボーナスタイムの表示。上部(ボスのゲージの下)に「BONUS TIME」と早送りの印・残りのバー、フィールドには、左へ流れる早送りの光の筋。
func _draw_bonus_hud() -> void:
	if sim == null or sim.boss == null or sim.boss.defeated or _dead:
		return
	var left: float = sim.bonus_left(_now)
	if left < 0.0:
		return
	var dur: float = Boss.BONUS_TIME
	var u := 1.0 - left / dur
	var env := smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.85, 1.0, u))
	var sp := sin(PI * u)   # 早送りの速さ(曲と同じ形)
	var ax := ARENA_POS.x
	var aw: float = PatternGen.ARENA.x
	# 早送りの光の筋(フィールド全体。速いところほど長く、明るい)
	for i in range(18):
		var hy := fmod(float(i) * 97.3 + 13.0, 700.0) + 10.0
		var spd := 900.0 + 700.0 * fmod(float(i) * 0.618, 1.0)
		var x := ax + aw - fposmod(_now * spd * (0.4 + sp) + float(i) * 211.0, aw + 300.0) + 150.0
		var ln := (60.0 + 260.0 * sp) * (0.6 + 0.4 * fmod(float(i) * 0.37, 1.0))
		var x0 := clampf(x, ax, ax + aw)
		var x1 := clampf(x + ln, ax, ax + aw)
		if x1 - x0 > 1.0:
			_hud.draw_line(Vector2(x0, hy), Vector2(x1, hy), Color(0.75, 0.9, 1.0, 0.10 * env * (0.4 + sp)), 2.0)
	# 「BONUS TIME」と早送りの印、残りのバー
	var cx := ax + aw * 0.5
	var y := 104.0
	var font := _score_font
	var gold := Color(1.0, 0.86, 0.4, env)
	_hud.draw_string(font, Vector2(cx - 200.0, y), "BONUS TIME", HORIZONTAL_ALIGNMENT_CENTER, 400.0, 30, gold)
	for k in range(2):   # ▶▶(早送りの印。速いほど右へ流れる)
		var ox := cx + 118.0 + 16.0 * k + 6.0 * sp
		_hud.draw_colored_polygon(PackedVector2Array([Vector2(ox, y - 22.0), Vector2(ox + 13.0, y - 13.0), Vector2(ox, y - 4.0)]), gold)
	var bw := 260.0
	_hud.draw_rect(Rect2(cx - bw * 0.5, y + 10.0, bw, 4.0), Color(1, 1, 1, 0.15 * env))
	_hud.draw_rect(Rect2(cx - bw * 0.5, y + 10.0, bw * (left / dur), 4.0), gold)


## 休憩のカウントダウンの動き: 出入り(なめらか)・輪が伸びて現れる・秒が変わるたびの弾み。
## 残り 3 秒からは、1 秒ごとに輪が広がる(音はなし)。終わると、輪が外へ広がって消える(動き出す合図)。
func _tick_break_count(delta: float) -> void:
	var counting := _update_break_count()
	_break_a = move_toward(_break_a, 1.0 if counting else 0.0, delta * 4.0)
	_break_pop = maxf(_break_pop - delta * 3.5, 0.0)
	if counting:
		_break_in = minf(_break_in + delta / 0.5, 1.0) if UiStyle.animate else 1.0
		var sec := int(ceil(_break_left - 0.0001))
		if sec != _break_sec:
			if _break_sec >= 0:
				_break_pop = 1.0
				if sec >= 1 and sec <= 3:
					UiFx.ring(_hud, _break_center(), Color(UiStyle.GOLD.r, UiStyle.GOLD.g, UiStyle.GOLD.b, 0.7), BREAK_R, BREAK_R + 46.0, 0.6, 3.0)
			_break_sec = sec
	elif _break_sec >= 0:
		if _break_left < 0.25:   # 休憩が終わった(途中で消えたのではない): 表示はすぐ消して、輪が外へ広がって消える
			_break_a = 0.0
			UiFx.ring(_hud, _break_center(), Color(UiStyle.GOLD.r, UiStyle.GOLD.g, UiStyle.GOLD.b, 0.9), BREAK_R, BREAK_R + 120.0, 0.55, 4.0)
			UiFx.ring(_hud, _break_center(), Color(1, 1, 1, 0.5), BREAK_R * 0.6, BREAK_R + 60.0, 0.45, 2.0)
		_break_sec = -1
		_break_in = 0.0


func _break_center() -> Vector2:
	return ARENA_POS + Vector2(PatternGen.ARENA.x * 0.5, 330.0)


## 休憩のカウントダウン: 暗い円の上に、残り時間の輪(真上から時計回りに減る)と、残り秒(整数)。下に BREAK。
## 残り 3 秒からは、輪と数字が金色になる。数字は変わるたびに少し弾む。
func _draw_break_count() -> void:
	var c := _break_center()
	var a := _break_a
	var warm := smoothstep(3.4, 2.9, _break_left)   # 残り 3 秒で、なめらかに金色へ
	var cool := Color(0.62, 0.9, 1.0)
	var col := cool.lerp(UiStyle.GOLD, warm)
	var grow := 1.0 - pow(1.0 - _break_in, 3.0)   # 現れるとき、輪が 0 から今の残りまで伸びる
	var frac := _break_frac * grow
	_hud.draw_circle(c, BREAK_R + 16.0, Color(0, 0, 0, 0.3 * a))
	_hud.draw_arc(c, BREAK_R, 0.0, TAU, 72, Color(1, 1, 1, 0.1 * a), 6.0, true)
	if frac > 0.002:
		var end := -PI * 0.5 + TAU * frac
		_hud.draw_arc(c, BREAK_R, -PI * 0.5, end, 72, Color(col.r, col.g, col.b, 0.92 * a), 6.0, true)
		_hud.draw_circle(c + Vector2.from_angle(end) * BREAK_R, 5.0, Color(1, 1, 1, 0.9 * a))   # 輪の先端
	# 残り秒: 変わるたびに少し大きく現れて、戻る
	var p := _break_pop * _break_pop
	var sc := 1.0 + 0.22 * p
	var txt := str(maxi(_break_sec, 0))
	var fs := 54
	_hud.draw_set_transform(c, 0.0, Vector2(sc, sc))
	var base := Vector2(-80.0, fs * 0.36)
	_hud.draw_string(_score_font, base + Vector2(2, 2), txt, HORIZONTAL_ALIGNMENT_CENTER, 160.0, fs, Color(0, 0, 0, 0.45 * a))
	_hud.draw_string(_score_font, base, txt, HORIZONTAL_ALIGNMENT_CENTER, 160.0, fs, Color(1, 1, 1, 0.96 * a).lerp(Color(col.r, col.g, col.b, a), 0.25 + 0.5 * p))
	_hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_hud.draw_string(_score_font, c + Vector2(-80.0, BREAK_R + 40.0), "BREAK", HORIZONTAL_ALIGNMENT_CENTER, 160.0, 14, Color(cool.r, cool.g, cool.b, 0.75 * a))


## 休憩のカウントダウン(弾を一掃してから休憩が終わるまで)の残りを更新する。表示すべきなら true。
func _update_break_count() -> bool:
	var counting: bool = sim.break_clear_t >= 0.0 and sim.in_break(_now) and not sim.finished
	if counting:
		_break_left = maxf(sim.break_end_t - _now, 0.0)
		_break_frac = clampf(_break_left / maxf(sim.break_end_t - sim.break_clear_t, 0.001), 0.0, 1.0)
	return counting


## スコア表示のイージング。sim.score(弾が発射されるたびに増える)へ、減速しながら滑らかに追従する。
## 差が大きいほど速く、近づくほどゆっくりになる(指数的な ease-out)。数字がカクカク跳ばずにカウントアップする。
func _ease_score(delta: float) -> void:
	var target: float = sim.score
	_score_disp += (target - _score_disp) * (1.0 - exp(-delta * SCORE_EASE_RATE))
	if absf(target - _score_disp) < 0.5:
		_score_disp = target
	# 被ダメージで点が減っている間(表示が目標より上にある間)は、数字が赤くなる
	var falling := target < _score_disp - 0.5
	_score_red += ((1.0 if falling else 0.0) - _score_red) * (1.0 - exp(-delta * (16.0 if falling else 5.0)))


## 左パネルの参加者一覧(マルチプレイ)を更新する。顔ぶれ・並びが変わったときだけ作り直し、スコアは毎回更新する。
## 対戦は名前の下にスコア(高い順)、協力は名前だけ(スコアはチームで 1 つ)。
func _update_mp_rows(delta: float) -> void:
	if _mp == null or _mp_box == null:
		return
	var rows: Array = _mp.rows(delta)
	var ids: Array = rows.map(func(r): return r.id)
	if ids != _mp_ids:
		_mp_ids = ids
		for c in _mp_box.get_children():
			c.queue_free()
			_mp_box.remove_child(c)
		_mp_rows.clear()
		for r in rows:
			var row := VBoxContainer.new()
			row.add_theme_constant_override("separation", -1)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var top := HBoxContainer.new()
			top.add_theme_constant_override("separation", 6)
			top.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var dot := Control.new()
			dot.custom_minimum_size = Vector2(9, 9)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var dc: Color = r.color
			dot.draw.connect(func(): dot.draw_circle(Vector2(4.5, 4.5), 4.0, dc))
			top.add_child(dot)
			var nl := UiStyle.label(r.name, 12, UiStyle.TEXT if r.me else UiStyle.TEXT_DIM, r.me)
			nl.custom_minimum_size = Vector2(110, 0)
			nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			top.add_child(nl)
			row.add_child(top)
			var sl: Label = null
			if _mp.mode == "versus":
				sl = UiStyle.label("", 14, UiStyle.TEXT if r.me else UiStyle.TEXT_DIM, true)
				var line := HBoxContainer.new()
				line.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var pad := Control.new()
				pad.custom_minimum_size = Vector2(15, 0)
				line.add_child(pad)
				line.add_child(sl)
				row.add_child(line)
			_mp_box.add_child(row)
			_mp_rows[r.id] = sl
	for r in rows:
		var sl2: Label = _mp_rows.get(r.id)
		if sl2 != null:
			sl2.text = UiStyle.fmt(int(round(r.score)))


# --- リプレイ ---

## 終わったプレイの記録を保存して、結果の stats["replay"] にファイル名を入れる(裏のスレッドで書く)。ひとり用のプレイだけ。
func _save_replay(st: Dictionary) -> void:
	if _rec == null:
		return
	var rec = _rec
	_rec = null
	var meta := {"md5": bm.md5, "title": bm.title, "artist": bm.artist, "version": bm.version,
		"settings": {"mods": _mods.ids.duplicate(), "density_mul": float(settings.get("density_mul", 1.0))},
		"cond": _study_cond, "fp": _rp_fp}
	Replay.prune(Records.replay_names(), 1)
	var name := Replay.save_async(Replay.make_data(rec, meta, st))
	if name != "":
		st["replay"] = name


## 再生の準備: 弾幕の指紋を確かめ、再生の係と操作パネルを作る。
func _init_replay() -> void:
	_rp_fp = Replay.fingerprint_of(sim)
	_audio_started = true   # READY の待ちはない
	_arrived = true
	_set_ship_in(1.0)
	_center_label.visible = false
	if _rp_fp != int(replay_data.get("fp", -1)) or (replay_data.get("frames") as PackedFloat64Array).size() < Replay.STRIDE:
		var made := str(replay_data.get("app", "?"))
		var now_v := str(ProjectSettings.get_setting("application/config/version", "?"))
		_rp_error = "このバージョンでは再生できません\n(弾幕が記録と違います。記録: v%s / いま: v%s)" % [made, now_v]
		_center_label.text = _rp_error
		_center_label.visible = true
		_center_label.add_theme_font_size_override("font_size", 22)
		_center_label.size.y = 90.0
		get_tree().create_timer(3.5).timeout.connect(func(): quit_requested.emit())
		return
	_rp = Replay.Player.new(sim, field, replay_data.frames, replay_data.keys)
	_rt = _rp.start_time()
	_now = _rt
	_sim_t = _rt
	_rp_hits = (replay_data.get("stats", {}) as Dictionary).get("hit_log", PackedFloat32Array())
	_view_under.trail_pts = replay_data.get("trail", PackedVector2Array())   # 軌道は、下の層(弾の下)にだけ描く
	_view_under.trail_ts = replay_data.get("trail_t", PackedFloat64Array())
	_view_under.hit_ts = _rp_hits
	_replay_apply_trail()
	if replay_export:
		CursorOverlay.hide_in(Rect2(0, 0, 1280, 720))
		return
	_rp_dense = ReplayDense.new()   # まだ見ていない秒へ飛ぶときの待ちを減らす: 裏で別のシムを流して、0.5 秒おきの状態を作っておく
	_rp.cache = _rp_dense
	_rp_dense.start(bm, settings, _study_cond, false, replay_data.frames, replay_data.keys, sim, field)
	_rp_bar = ReplayBar.new()
	add_child(_rp_bar)
	_rp_bar.setup(replay_data, _rp.end_time())
	_rp_bar.play_pressed.connect(func(): _replay_set_playing(not _rp_playing, true))
	_rp_bar.restart_pressed.connect(func():
		_replay_seek(_rp.start_time())
		_replay_set_playing(true)
		_osd("最初から"))
	_rp_bar.end_pressed.connect(func():
		_replay_seek(_rp.end_time())
		_osd("最後へ"))
	_rp_bar.seek_requested.connect(_replay_seek)
	_rp_bar.scrub_started.connect(func():
		_rp_scrub_resume = _rp_playing
		if _rp_playing:
			_replay_set_playing(false))
	_rp_bar.scrub_ended.connect(func():
		if _rp_scrub_resume and not _rp.at_end():
			_replay_set_playing(true)
		_rp_scrub_resume = false)
	_rp_bar.skip_requested.connect(func(d: float): _replay_skip(d))
	_rp_bar.hit_jump_requested.connect(_replay_jump_hit)
	_rp_bar.speed_selected.connect(func(s: float): _replay_set_speed(s, false))
	_rp_bar.trail_toggled.connect(_replay_toggle_trail)
	_rp_bar.export_requested.connect(_replay_request_export)
	_rp_bar.close_pressed.connect(_replay_close)
	_replay_layout(1.0)
	_replay_sync_bar()


## 再生: 画面の大きさ。k = 0 で元の大きさ、1 で、操作パネルのぶん縮める。背景・赤みは、画面いっぱいに保つ。
func _replay_layout(k: float) -> void:
	_rp_stage_k = k
	var s := lerpf(1.0, ReplayBar.DOCK_SCALE, k)
	scale = Vector2(s, s)
	position = Vector2(640.0 * (1.0 - s), 0.0)
	_view_l = -position.x / s
	_view_r = (1280.0 - position.x) / s
	_view_b = 720.0 / s
	for n in _bg_nodes:
		n.position = Vector2(_view_l, 0.0)
		n.size = Vector2(_view_r - _view_l, _view_b)
	_hud.queue_redraw()


func _osd(text: String) -> void:
	if _rp_bar != null:
		_rp_bar.osd(text)


## 1 フレームぶん: 再生の時計を進め、記録を流してシムを進め、音を合わせる(プレイ中の「曲クロック → _step_sim」の代わり)。
func _replay_tick(delta: float) -> void:
	if _rp_bar != null:
		var k: float = _rp_bar.stage_ease()
		if not is_equal_approx(k, _rp_stage_k):
			_replay_layout(k)
	if _rp_seek_to >= 0.0:   # 飛んでいる最中: 続きを計算するだけ(再生は、終わってから)
		_replay_seek_tick()
		return
	if _dead:   # ゲームオーバーの演出(曲のテープストップと同じ割合で、弾の時間も遅くなって止まる)
		var dt_game := delta * _tape_speed()
		_now += dt_game
		field.update(dt_game, Vector2(-1.0e6, -1.0e6), 0.0, false)
		_hit_any = false
		if replay_export:
			_replay_export_tick(delta)
		_replay_sync_bar()
		return
	_hit_any = false
	_hit_started = false
	if _rp_playing and not _rp.at_end():
		var step_t := delta * _rp_speed
		if _audio.playing and not replay_export:   # 曲が鳴っているあいだは、時計を、音のほうへゆっくり寄せる(プレイ中の _advance_clock と同じ。映像と曲がずれていかない)
			var err: float = _replay_audio_time() - (_rt + step_t)
			if absf(err) < CLOCK_RESYNC * 3.0 * maxf(_rp_speed, 1.0):
				step_t = maxf(step_t + err * clampf(delta * CLOCK_PULL, 0.0, 1.0), 0.0)
		var target := minf(_rt + step_t, _rp.end_time())
		var done: bool = _rp.advance_to(target, true, 0.0 if replay_export else 9.0)
		_rt = target if done else _rp.t   # 倍速で間に合わないときは、時計をシムに合わせて遅らせる
		_rp.cache_here()   # 通ったところも、飛ぶときの出発点として覚える
		_hit_any = _rp.hit_any
		_hit_started = _rp.hit_started
		if absf(_rp_speed - 1.0) < 0.01:   # 効果音は、ふつうの速さのときだけ
			_sfx_pending = _rp.sfx
			_sfx_pending_pan = _rp.sfx_pan
	if _rp_playing and not _rp.at_end() and _rp.next_start() > _rt + 0.05:   # 記録のない区間(スキップしたイントロ): 時計を、次の記録まで飛ばす
		_rt = _rp.next_start()
	_now = _rt
	if _rp.at_end():
		_replay_verify()
		if _rp_playing and not sim.failed and not replay_export:
			_replay_set_playing(false)
	if replay_export:
		_replay_export_tick(delta)
	_replay_audio()
	_replay_sync_bar()


## 曲の位置から求めた、いまのゲームの時刻(撃破 MOD の周の分も足す)。
func _replay_audio_time() -> float:
	var loop_off: float = float(sim.loop_index(_rt)) * sim.loop_len if sim.loop_len > 0.0 else 0.0
	return _audio.get_playback_position() / _rate + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency() \
		+ float(settings.get("offset_ms", 0)) / 1000.0 + loop_off


## 動画出力の子プロセス: 最後に着いたら、少し余韻を撮って(クリアは HUD がフェードし、ゲームオーバーは演出のぶん)、リザルトへ(main が撮る)。
func _replay_export_tick(delta: float) -> void:
	CursorOverlay.hide_in(Rect2(0, 0, 1280, 720))
	_rp_progress_t += delta
	if _rp_progress_t >= 0.5:
		_rp_progress_t = 0.0
		Replay.write_progress(0.9 * clampf((_rt - _rp.start_time()) / maxf(_rp.end_time() - _rp.start_time(), 0.001), 0.0, 1.0))   # 残りの 1 割はリザルト
	if not _rp.at_end() or _rp_ended_t < -1.5:
		return
	_rp_ended_t = maxf(_rp_ended_t, 0.0) + delta
	if not sim.failed and _outro_t < 0.0 and _rp_ended_t >= 1.0:
		_begin_outro()   # クリア: プレイのときと同じく、背景を残して HUD・アリーナが消えていく
	var tail := (END_DELAY_FAIL + 0.6) if sim.failed else 1.0 + OUTRO_TIME
	if _rp_ended_t >= tail:
		_rp_ended_t = -2.0   # 1 度だけ
		var st: Dictionary = (replay_data.get("stats", {}) as Dictionary).duplicate()
		st["bg"] = _bg_tex
		st["video"] = true   # リザルトは、ボタンなしで見せる
		var music: AudioStreamPlayer = null
		if not sim.failed and _audio.playing:   # クリア: 鳴っている曲を、そのままリザルトへ(プレイのときと同じ)
			music = _audio
			remove_child(_audio)
		replay_export_finished.emit(st, music)


## 再生の音: どの速さでも曲を鳴らす(速さに合わせて音程も変わる)。止めた・飛んでいる・最後まで流したときは止める。
## 曲の長さを過ぎたところでは鳴らさない(鳴らし直すと、曲の頭から鳴ってしまう)。
func _replay_audio() -> void:
	var song_t: float = _rt - (float(sim.loop_index(_rt)) * sim.loop_len if sim.loop_len > 0.0 else 0.0)   # 撃破: 周ごとに、曲は頭へ戻る
	var song_len: float = _audio.stream.get_length() / _rate if _audio.stream != null else 1.0e9
	if replay_export and _rp.at_end() and not sim.failed:
		return   # 動画のクリア: 曲は、そのままリザルトまで鳴らし続ける
	var want: bool = _rp_playing and _rt >= 0.0 and not _rp.at_end() and not _dead and song_t < song_len - 0.05
	if not want:
		if _audio.playing:
			_audio.stop()
		return
	_audio.pitch_scale = _rate * _rp_speed
	_audio.volume_db = 0.0
	if not _audio.playing:
		_audio.play(maxf(song_t, 0.0) * _rate)
	elif not replay_export:   # 動画では、固定のフレーム時間で曲も進むので、合わせ直さない
		var pos := _audio.get_playback_position() / _rate
		if absf(pos - song_t) > 0.25 * maxf(_rp_speed, 1.0):
			_audio.seek(maxf(song_t, 0.0) * _rate)


## 最後まで流した(飛んだ)ときに、結果が記録と合っているかを確かめる。ずれていたら、注意を出す(版の違いで、動きが変わったとき)。
func _replay_verify() -> void:
	if _rp_verified or _rp_bar == null:
		return
	_rp_verified = true
	if not Replay.verify(sim, replay_data.get("stats", {})):
		_rp_bar.set_warning("再現にずれがあります(この版で、判定や弾の動きが変わったかもしれません)。見えているものは、記録と少し違う可能性があります")


func _replay_set_playing(on: bool, announce := false) -> void:
	if _rp == null:
		return
	if on and _rp.at_end() and not _dead:
		_replay_seek(_rp.start_time())   # 最後で再生を押したら、最初から
	_rp_playing = on
	if not on and _audio.playing:
		_audio.stop()
	if announce:
		_osd("再生" if on else "停止")
	_replay_sync_bar()


## 速さを変える(0.25〜8 倍の好きな値)。曲は止めずに、次のフレームで音の速さを合わせる(スライダーを動かしても途切れない)。
func _replay_set_speed(s: float, announce := true) -> void:
	_rp_speed = clampf(s, ReplayBar.SPEED_MIN, ReplayBar.SPEED_MAX)
	if announce:
		_osd("%.2fx" % _rp_speed)
	_replay_sync_bar()


## 秒数だけ、いまの位置から動く(OSD つき)。
func _replay_skip(d: float) -> void:
	_replay_seek(_rt + d)
	_osd("%+d秒" % int(d))


## 前の・次の被弾の少し前へ飛ぶ(死因・避けそこねの確認)。
func _replay_jump_hit(dir: int) -> void:
	const LEAD := 1.5   # 被弾のこれだけ前から見せる(避けそこねた前後が分かるように)
	var cur := _rt
	var idx := -1
	if dir > 0:
		for i in range(_rp_hits.size()):
			if float(_rp_hits[i]) - LEAD > cur + 0.05:
				idx = i
				break
	else:
		for i in range(_rp_hits.size() - 1, -1, -1):
			if float(_rp_hits[i]) - LEAD < cur - 0.3:
				idx = i
				break
	if idx < 0:
		_osd("これより後の被弾はありません" if dir > 0 else "これより前の被弾はありません")
		return
	_replay_seek(maxf(float(_rp_hits[idx]) - LEAD, _rp.start_time()))
	_osd("被弾 %d / %d" % [idx + 1, _rp_hits.size()])


## 時刻 t へ飛ぶ(前へも後ろへも)。直前のキーフレームへ戻して、そこから目標までを、数フレームに分けて計算する(1 フレームに replay_seek_budget_ms ミリ秒まで。
## 画面は止まらず、時間がかかるときは「読み込み中」を出す)。新しく飛ぶように頼まれたら、そちらに切り替える。
func _replay_seek(t: float) -> void:
	if _rp == null:
		return
	if _dead:
		_replay_undo_death()
	if _rp_seek_to < 0.0:
		_rp_seek_t0 = Time.get_ticks_usec()
		_rp_seek_from = _rp.t
	_rp.seek_begin(t)
	_rt = clampf(t, _rp.start_time(), _rp.end_time())   # 記録のない区間(スキップしたイントロ)へ飛んだときは、その手前の状態のまま、時計だけ進む
	_now = _rt
	_rp_seek_to = _rt
	_rp_seek_from = minf(_rp_seek_from, _rp.t)
	_hit_any = false
	_hit_started = false
	if _audio.playing:
		_audio.stop()
	_replay_seek_step(3.0)   # 近いときは、ここで終わる(待ちは出ない)
	_replay_sync_bar()


## 飛ぶ途中の計算を、budget_ms ミリ秒ぶん進める(0 なら最後まで)。終わったら true。
func _replay_seek_step(budget_ms: float) -> bool:
	if _rp_seek_to < 0.0:
		return true
	if not _rp.advance_to(_rp_seek_to, false, budget_ms):
		return false
	_rp_seek_to = -1.0
	_replay_snap_hud()
	if sim.failed:
		_begin_death(false)   # 最後まで飛んだ: ゲームオーバーの演出をもう一度
	if _rp.at_end():
		_replay_verify()
	_refresh()
	if _rp_bar != null:
		_rp_bar.set_loading(false, 1.0)
		_rp_bar.set_seek_cost(float(Time.get_ticks_usec() - _rp_seek_t0) / 1000.0)
	return true


## 飛ぶのを、その場で最後まで済ませる(確認用)。
func _replay_seek_now(t: float) -> void:
	_replay_seek(t)
	_replay_seek_step(0.0)
	_replay_sync_bar()


## 飛んでいる最中の 1 フレーム: 計算を進めて、途中の状態を見せ、時間がかかっていれば「読み込み中」を出す。
func _replay_seek_tick() -> void:
	if not _replay_seek_step(replay_seek_budget_ms):
		var span := maxf(_rp_seek_to - _rp_seek_from, 0.001)
		if _rp_bar != null and float(Time.get_ticks_usec() - _rp_seek_t0) > 70000.0:   # 70 ms を超えたら出す(一瞬で済む飛びでは、出さない)
			_rp_bar.set_loading(true, clampf((_rp.t - _rp_seek_from) / span, 0.0, 1.0))
		_refresh()
	_replay_sync_bar()


## 飛んだあとに、なめらかに追従する表示(体力バーの残像・スコア・赤み・休憩・ボス)を、その場で合わせる。
func _replay_snap_hud() -> void:
	_gauge_ghost = sim.gauge
	_low_vis = _low_target()
	_score_disp = sim.score
	_last_graze = sim.graze
	_hit_glow = 0.0
	_break_a = 1.0 if _update_break_count() else 0.0
	_break_in = _break_a
	_break_sec = int(ceil(_break_left)) if _break_a > 0.0 else -1
	_update_hud_fade(0.0, true)
	_update_kiai(0.0, true)
	if sim.boss != null:
		_pick_seen = sim.boss.pick_events.size()
		_boss_down_seen = sim.boss.defeated
		_update_weapon_labels()
	_hp_sparks.clear()


## ゲームオーバーの演出を元に戻す(前へ飛ぶとき)。
func _replay_undo_death() -> void:
	_dead = false
	_death_t = 0.0
	_view_over.dead = false
	_view_under.dead = false
	_view_over.death_t = 0.0
	_view_over.material = null
	field.modulate.a = 1.0
	_center_label.visible = false
	_center_label.scale = Vector2.ONE
	_audio.stop()
	_audio.pitch_scale = _rate
	_audio.volume_db = 0.0
	_rp.force_restore = true   # 演出で弾を進めたので、キーフレームから戻す


# --- 動画出力 ---

func _replay_request_export(opts: Dictionary) -> void:
	var o := opts.duplicate()
	if not o.is_empty():
		o["trail_mode"] = replay_trail_mode
		o["trail_sec"] = replay_trail_sec
	replay_export_requested.emit(replay_data, o)


# --- 軌道(過去 3 秒。出す / 出さない だけ) ---

func _replay_toggle_trail() -> void:
	replay_trail_mode = 0 if replay_trail_mode > 0 else 1
	_replay_apply_trail()
	_osd("軌道: 表示" if replay_trail_mode > 0 else "軌道: 非表示")


func _replay_apply_trail() -> void:
	_view_under.trail_mode = 1 if replay_trail_mode > 0 else 0
	_view_under.trail_sec = replay_trail_sec
	_view_over.trail_mode = 0
	_replay_sync_bar()


func _replay_close() -> void:
	_audio.stop()
	quit_requested.emit()


## 動画の書き出しの状態を、操作パネルに出す(main が、子プロセスの進み具合を見て呼ぶ)。
func set_export_status(text: String) -> void:
	if _rp_bar != null:
		_rp_bar.set_export_status(text)


## 書き出しが終わった(path: できたファイル。空なら失敗)。
func set_export_done(path: String, text: String) -> void:
	if _rp_bar != null:
		_rp_bar.set_export_done(path, text)


func _replay_sync_bar() -> void:
	if _rp_state_l != null:
		var txt := "停止中" if not _rp_playing else ("再生中" if is_equal_approx(_rp_speed, 1.0) else "再生中  %.2fx" % _rp_speed)
		if txt != _rp_state_l.text:
			_rp_state_l.text = txt
			_rp_state_l.modulate.a = 0.6 if not _rp_playing else 1.0
	if _rp_bar != null:
		_rp_bar.set_state(_rp_playing, _rp_speed, _rt, replay_trail_mode > 0)


## 再生のキー操作(一覧は ReplayBar.HELP_LINES)。
func _replay_key(event: InputEventKey) -> void:
	if _rp == null:
		if event.keycode == KEY_ESCAPE:
			quit_requested.emit()
		return
	var step := 1.0 if event.shift_pressed else (15.0 if event.ctrl_pressed else 5.0)
	match event.keycode:
		KEY_SPACE:
			if not event.echo:
				_replay_set_playing(not _rp_playing, true)
		KEY_ESCAPE:
			if not _rp_bar.dismiss_popups():
				_replay_close()
		KEY_LEFT:
			_replay_skip(-step)
		KEY_RIGHT:
			_replay_skip(step)
		KEY_HOME:
			_replay_seek(_rp.start_time())
			_osd("最初へ")
		KEY_END:
			_replay_seek(_rp.end_time())
			_osd("最後へ")
		KEY_PAGEUP:
			_replay_jump_hit(-1)
		KEY_PAGEDOWN:
			_replay_jump_hit(1)
		KEY_COMMA:
			_replay_set_playing(false)
			_replay_seek(_rp.prev_frame_time())
		KEY_PERIOD:
			_replay_set_playing(false)
			if _rp_seek_to < 0.0 and _rp.step_frame():
				_rt = _rp.t
				_now = _rt
				_hit_any = _rp.hit_any
				_replay_sync_bar()
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:   # 区切りのよい速さ(0.25 / 0.5 / 1 / 2 / 4 / 8)へ
			var up := event.keycode == KEY_BRACKETRIGHT
			var next := _rp_speed
			var speeds: Array = ReplayBar.SPEEDS
			for i in range(speeds.size()):
				var s: float = speeds[i if up else speeds.size() - 1 - i]
				if (up and s > _rp_speed + 0.001) or (not up and s < _rp_speed - 0.001):
					next = s
					break
			_replay_set_speed(next)
		KEY_H:
			_rp_bar.pinned_hidden = not _rp_bar.pinned_hidden   # 操作パネルを隠す・出す(プレイ画面が、元の大きさへ戻る)
		KEY_T:
			_replay_toggle_trail()
		KEY_F1, KEY_SLASH, KEY_QUESTION:
			_rp_bar.toggle_help()


## 再生中、プレイ画面をクリックすると、再生 / 停止(操作パネルの上のクリックは、ここへ来ない)。
func _unhandled_input(event: InputEvent) -> void:
	if _rp == null or _rp_bar == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _rp_bar.dismiss_popups():
			return
		_replay_set_playing(not _rp_playing, true)
