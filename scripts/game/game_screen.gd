extends Node2D
## プレイ画面。曲クロックを音声に同期させ、GameSim を毎フレーム進める。

## music: クリアしたとき、鳴っている曲のプレイヤー(呼び出し側が引き継いで、リザルトでも流し続ける)。ゲームオーバーなら null
signal finished(stats: Dictionary, music: AudioStreamPlayer)
signal quit_requested
signal retry_requested

const GameSim = preload("res://scripts/game/game_sim.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
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
const MpGame = preload("res://scripts/net/mp_game.gd")

const ARENA_POS := Vector2(160, 0)
## 体力バーの位置と大きさ(先端の火花の発生位置にも使う)
const HP_X := 188.0
const HP_Y := 28.0
const HP_W := 360.0
const HP_H := 16.0
const HP_SL := 12.0
const LEAD_IN := 1.5
## イントロのスキップ: 最初のノーツの SKIP_LEAD 秒前まで進める。進む幅が SKIP_MIN_GAIN 秒未満なら出さない
const SKIP_LEAD := 1.5
const SKIP_MIN_GAIN := 1.0
## 表示スコアのイージング: 目標値との差を毎秒この割合で詰める ease-out(1/RATE 秒ほどで大半が追いつく)
const SCORE_EASE_RATE := 9.0
const END_DELAY_FAIL := 2.9
## 判定・進行(GameSim)を進める刻み。描画のフレームレートとは独立に、ms 単位(1000 Hz)で当たり判定を行う。
## 1 フレームぶんの経過時間を、この刻みで割って(ceil)、その回数だけ sim を進める(60 fps なら 1 フレームで約 17 回)。
## 1 フレームで進める回数の上限(重い場面で処理が追いつかなくなったときは、刻みを粗くして時刻だけは合わせる)
const SIM_STEP := 0.001
const SIM_MAX_STEPS := 100
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
const KIAI_ARENA_DIM := 0.035     # フィールドの下地の不透明度が、光のピークでこれだけ下がる(僅かに)
const KIAI_BASE := 0.12          # キアイ中は、拍の合間でもこれだけ光っている(光の下限)
const BG_TINT := Color(0.28, 0.28, 0.32)
const ARENA_BG_ALPHA := 0.62
const TAPE_STOP_TIME := 1.7  # ゲームオーバー時に曲が止まるまでの秒数

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
var _score_font: FontVariation
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
var _break_a := 0.0       # 休憩のカウントダウンの表示度(なめらかに出入りする)
var _break_left := 0.0    # 休憩が終わるまでの残り秒
var _break_frac := 0.0    # カウントダウンバーの残り割合(1 → 0)
var _done := false        # リザルトへ渡した後(以降は何もしない)
var _outro_t := -1.0      # クリアのフェードアウトの経過秒(始まるまで -1)
var _bg_nodes: Array = [] # 背景(フェードアウトしない)
var _bg_tex: Texture2D    # 背景の画像(リザルトへ渡して、同じ背景を続ける)
var _sim_t := -LEAD_IN    # 判定側(GameSim)の時刻。_now に追いつくまで SIM_STEP 刻みで進める
var _hit_any := false     # このフレームのどこかのステップで、弾に当たっていたか
var _hit_started := false # このフレームのどこかで、新しい被弾が始まったか
var _sfx_pending: Array = []  # このフレームの発射音(まとめて鳴らす)
var _left_col: Control
var _right_col: Control
var _pause_btns: Array = []
var _pause_sel := 0       # 0..2 = ボタン、3 = 音量、4 = 効果音
var _pause_vol: Array = []   # [スライダー, 値ラベル, 見出しラベル]
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
var _arena_bg: ColorRect  # フィールドの暗い下地
var _kiai_a := 0.0        # キアイ中か(0..1。なめらかに出入りする)
var _beat_glow := 0.0     # 今の光の強さ 0..1(キアイ中、拍の頭で立ち上がって、次の拍へ向けて消える)


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
	settings["mods"] = info.mods.duplicate()
	settings["density_mul"] = float(info.density_mul)


func _ready() -> void:
	_alive += 1
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
	_arena_bg = ColorRect.new()
	_arena_bg.color = Color(0.0, 0.0, 0.02, ARENA_BG_ALPHA)
	_arena_bg.position = ARENA_POS
	_arena_bg.size = PatternGen.ARENA
	add_child(_arena_bg)

	_arena = Node2D.new()
	_arena.position = ARENA_POS
	add_child(_arena)
	_view_under = ArenaView.new()
	_view_under.layer = 0
	_arena.add_child(_view_under)
	field = BulletField.new()
	_arena.add_child(field)
	field.setup_render()
	_view_over = ArenaView.new()
	_view_over.layer = 1
	_arena.add_child(_view_over)

	# 音声
	_audio = AudioStreamPlayer.new()
	Volume.route_music(_audio)   # 音楽バスへ(ホイールなどの「音楽」の音量が効く)
	_audio.stream = loader.load_audio(bm.audio_filename)
	add_child(_audio)
	_sfx = Sfx.new()
	_sfx.volume = int(settings.get("sfx_volume", 70)) / 100.0
	_vol_rev = Volume.rev
	add_child(_sfx)

	# 弾幕生成 + シミュ
	gen = PatternGen.generate(bm, {"density_mul": settings.get("density_mul", 1.0)})
	_mods = Mods.params(settings.get("mods", []))
	gen = Mods.apply(gen, _mods)   # MOD を掛け、その弾幕で難易度(Lv)を測り直す
	_rate = _mods.rate
	_hp_w = HP_W * clampf(_mods.drain_time / GameSim.GAUGE_DRAIN_TIME, 0.3, 1.0)   # 体力が少ない MOD ほどバーが短い(地獄: 150ms ÷ 250ms = 0.6 倍)
	_audio.pitch_scale = _rate
	sim = GameSim.new()
	_end_time = bm.last_time() / 1000.0 / _rate + 2.0   # 再生速度が上がると、曲は短くなる
	# 対戦は、体力が 0 でもゲームオーバーにならない(最後まで続く)。協力は、体力を全員で共有する(ホストが決める)
	sim.setup(field, gen, _end_time, _mods.practice or (net != null and mp_info.mode == "versus"), _mods)
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
	if debug_seek >= 0.0:
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
		_update_hud_fade(0.0, true)
		_update_kiai(0.0, true)
		if sim.failed:
			_begin_death(false)
			_death_t = maxf(debug_death_t, 0.0)
			_apply_death_fx()
		_refresh()
	else:
		_begin_arrival()
	if net != null:
		# 全員が同じ弾幕を作れたかの確認用の要約(ホストと違う人は外される)。開始の合図(go)は、全員の準備が済んでから届く
		net.report_loaded(sim.events.size() * 100003 + sim.bullets_total)


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
		if _can_skip():   # スキップのボタンを押せるように、まだ捕まえない(_update_skip_button が、できなくなったら捕まえる)
			_skip_free = true
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		else:
			var at: Vector2 = ARENA_POS + sim.player_pos
			Input.warp_mouse(get_viewport().get_screen_transform() * at)
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
	_center_label.pivot_offset = Vector2(PatternGen.ARENA.x * 0.5, 30)
	_hud = Node2D.new()
	_hud.draw.connect(_draw_hud)
	add_child(_hud)
	_hp_node = Node2D.new()
	_hp_node.draw.connect(_draw_hp_layer)
	_hud.add_child(_hp_node)
	_sc_node = Node2D.new()
	_sc_node.draw.connect(_draw_score)
	_hud.add_child(_sc_node)
	_build_pause()
	# 始まりの動き: 左右のパネルが外から滑り込み、HP・スコアがフェードインし、READY が弾んで現れる
	UiStyle.pop_in(_left_col, 0.1, Vector2(-26, 0), 0.5)
	UiStyle.pop_in(_right_col, 0.1, Vector2(26, 0), 0.5)
	UiStyle.tween(_hud, "modulate:a", 0.0, 1.0, 0.6, 0.15)
	UiStyle.tween(_center_label, "modulate:a", 0.0, 1.0, 0.4, 0.25)
	_center_label.pivot_offset = Vector2(PatternGen.ARENA.x * 0.5, 30)
	UiStyle.tween(_center_label, "scale", Vector2(1.3, 1.3), Vector2.ONE, 0.55, 0.25, Tween.TRANS_BACK)


## 左パネル(幅 160): 曲情報・Lv(MOD 適用後)・付けた MOD。
func _build_left_panel() -> void:
	var col := VBoxContainer.new()
	_left_col = col
	col.position = Vector2(14, 16)
	col.custom_minimum_size = Vector2(134, 0)
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
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


## 右パネル(幅 160): GRAZE / HIT TIME と、モード表示。
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
	col.add_child(UiStyle.caption("HIT TIME"))
	_hit_l = UiStyle.label("0 ms", 26, UiStyle.TEXT, true)
	col.add_child(_hit_l)


## ポーズ画面(暗転 + 中央パネル。項目: 再開 / リトライ / メニューへ / 音量 / 効果音)。
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
	var panel := PanelContainer.new()
	_pause_panel = panel
	panel.position = Vector2(420, 130)
	panel.size = Vector2(440, 10)
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.LINE, 1, 8, 30, 26))
	_pause_layer.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(UiStyle.label("MENU" if _mp != null else "PAUSED", 28, UiStyle.TEXT, true))   # マルチプレイでは、ゲームは止まらない
	v.add_child(UiStyle.hline())
	_pause_btns.clear()
	var specs := [["再開", "Esc", Callable(self, "_pause_activate").bind(0)],
		["リトライ", "R", Callable(self, "_pause_activate").bind(1)],
		["メニューへ", "Q", Callable(self, "_pause_activate").bind(2)]]
	for i in range(specs.size()):
		var b := Button.new()
		b.text = specs[i][0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(specs[i][2])
		b.mouse_entered.connect(func():
			_pause_sel = i
			_refresh_pause())
		v.add_child(b)
		_pause_btns.append(b)
	if _mp != null:   # マルチプレイ: リトライはなく、「メニューへ」は部屋を出ることになる
		_pause_btns[1].visible = false
		_pause_btns[2].text = "退出"
	v.add_child(UiStyle.hline())
	_pause_vol = _pause_slider_row(v, "音量", func(x: float): _set_master_volume(int(x)))
	_pause_sfx = _pause_slider_row(v, "効果音", func(x: float): _set_sfx_volume(int(x)))


## ポーズ画面の音量スライダー 1 行(見出し + スライダー + 値)。[スライダー, 値ラベル] を返す。
func _pause_slider_row(parent: Control, cap: String, on_change: Callable) -> Array:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var l := UiStyle.label(cap, 15, UiStyle.TEXT)
	l.custom_minimum_size = Vector2(70, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 5
	s.custom_minimum_size = Vector2(210, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(on_change)
	h.add_child(s)
	var val := UiStyle.label("", 15, UiStyle.ACCENT)
	val.custom_minimum_size = Vector2(50, 0)
	h.add_child(val)
	parent.add_child(h)
	return [s, val, l]


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
		return
	delta = minf(delta, 0.05)
	_ui_time += delta
	if not _audio_started:
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
		if _audio.playing:
			_advance_clock(t, delta)
		else:
			_now += delta  # 曲が先に終わっても進行を続ける

	var slow := Input.is_physical_key_pressed(KEY_SHIFT)
	if _mouse_mode:
		slow = slow or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	_step_sim(slow)
	if _mp != null:
		_mp.tick(delta, _now)

	# 効果音は 1 回だけ消費する(シミュレーション停止後に残った分を毎フレーム鳴らさない)
	if not sim.failed:
		for s in _sfx_pending:
			_sfx.play(s)
		if _hit_started:
			_sfx.play("hit")  # 新しい被弾の開始時に 1 回
	_sfx_pending.clear()
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
	_refresh()

	if sim.finished and not sim.failed and not _done:
		# クリア: 背景以外をフェードアウト(画面も曲も止めない。弾は sim が消してある)→ リザルトへ。曲は呼び出し側が引き継ぐ
		if _outro_t < 0.0:
			_begin_outro()
		_outro_t += delta
		if _outro_t < OUTRO_TIME:
			return
		_done = true
		var music := _audio
		if _audio.playing:
			remove_child(_audio)
		else:
			music = null
		var st_clear := _stats()
		if _mp != null:
			_mp.send_final(st_clear)
		finished.emit(st_clear, music)
		return
	if sim.finished and _end_timer < 0.0:
		_end_timer = END_DELAY_FAIL
	if _end_timer >= 0.0:
		_end_timer -= delta
		if _end_timer <= 0.0 and not _done:
			_done = true
			_audio.stop()
			var st_fail := _stats()
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
	_hit_any = false
	if sim.finished:
		_sim_t = _now
		return
	var span := _now - _sim_t
	if span <= 0.0:
		return   # 曲クロックが進んでいない(マウスの移動量は次のフレームへ持ち越す)
	var n := clampi(ceili(span / SIM_STEP), 1, SIM_MAX_STEPS)
	var dt := span / float(n)
	var move := Vector2.ZERO
	var d := Vector2.ZERO
	if _mouse_mode:
		var mult: float = float(settings.get("mouse_sens", 1.0)) * (GameSim.MOUSE_SLOW_FACTOR if slow else 1.0)
		d = _mouse_accum * mult / float(n)
		_mouse_accum = Vector2.ZERO
	else:
		move = _read_move()
	for k in range(n):
		_sim_t += dt
		if _mouse_mode:
			sim.step_relative(_sim_t, dt, d, slow)
		else:
			sim.step(_sim_t, dt, move, slow)
		_hit_any = _hit_any or sim.hit_now
		_hit_started = _hit_started or sim.just_hit
		_sfx_pending.append_array(sim.sfx_queue)
		if sim.finished:
			break
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


## 演出の経過に合わせて、曲の減速・弾のフェード・GAME OVER 表示を更新する。
func _apply_death_fx() -> void:
	var t := _death_t
	_view_over.death_t = t
	# テープストップ: 音量は保ったまま、再生速度(=音程)がなめらかに 0 へ落ちていく
	if _audio.playing:
		var x := clampf(t / TAPE_STOP_TIME, 0.0, 1.0)
		_audio.pitch_scale = maxf(_rate * pow(1.0 - x, 2.0), 0.02)
		_audio.volume_db = linear_to_db(clampf((1.0 - x) / 0.12, 0.001, 1.0))  # 完全に止まる直前だけ消す
		if x >= 1.0:
			_audio.stop()
	# 弾は固まってから消える
	field.modulate.a = clampf(1.0 - (t - 0.5) / 0.9, 0.0, 1.0)
	# GAME OVER 表示
	var a := clampf((t - 0.45) / 0.5, 0.0, 1.0)
	_center_label.text = "GAME OVER"
	_center_label.add_theme_color_override("font_color", Color(1, 0.3, 0.35))
	_center_label.modulate.a = a
	var sc := lerpf(2.2, 1.0, 1.0 - pow(1.0 - a, 3.0))
	_center_label.scale = Vector2(sc, sc)
	_center_label.visible = a > 0.0


func _stats() -> Dictionary:
	var d := {
		"title": bm.display_name(),
		"level": gen.level,
		"mean": gen.rating.mean,
		"peak": gen.rating.peak,
		"failed": sim.failed,
		"progress": 1.0 if not sim.failed else clampf((sim.death_time * _rate - bm.first_time() / 1000.0) / maxf((bm.last_time() - bm.first_time()) / 1000.0, 1.0), 0.0, 1.0),
		"hits": sim.hits,
		"hit_ms": int(round(sim.hit_time * 1000.0)),
		"damage": sim.damage_total,
		"score_gross": sim.score_gross,
		"score_base": sim.score_base,
		"mods": Mods.names(_mods.ids),
		"mod_ids": _mods.ids,
		"damage_factor": sim.damage_factor,
		"score_graze": sim.score_graze,
		"graze": sim.graze,
		"score": sim.score,
		"practice": _mods.practice,
		"bg": _bg_tex,
	}
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
	_hit_l.text = "%d ms" % int(round(sim.hit_time * 1000.0))
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
	var tip := Vector2(HP_X + _hp_w * g + HP_SL * 0.5, HP_Y + HP_H * 0.5)
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
		_hud.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(lw, 0), Vector2(lw, 720), Vector2(0, 720)]), PackedColorArray([c0, c1, c1, c0]))
		_hud.draw_polygon(PackedVector2Array([Vector2(1280 - lw, 0), Vector2(1280, 0), Vector2(1280, 720), Vector2(1280 - lw, 720)]), PackedColorArray([c1, c0, c0, c1]))


## 体力バーの層(自機が近づくと、この層ごと薄くなる)。
func _draw_hp_layer() -> void:
	var g: float = clampf(sim.gauge, 0.0, 1.0) if sim != null else 1.0
	_draw_hp_bar(ThemeDB.fallback_font, HP_X, HP_Y, g)


## スコアの層(自機が近づくと薄くなる)。被ダメージで点が減っている間は、数字が赤くなる。
func _draw_score() -> void:
	var font := ThemeDB.fallback_font
	var right := ARENA_POS.x + PatternGen.ARENA.x - 28.0   # フィールド右端の内側
	var score_text := UiStyle.fmt(int(round(_score_disp)))
	var prog_pct: float = (sim.progress if sim != null else 0.0) * 100.0
	var score_c := Color(1, 1, 1, 0.97).lerp(Color(1.0, 0.27, 0.31, 1.0), _score_red)
	_sc_node.draw_string(font, Vector2(right - 400.0, 24), "SCORE", HORIZONTAL_ALIGNMENT_RIGHT, 400.0, 12, Color(1, 1, 1, 0.55).lerp(Color(1.0, 0.4, 0.42, 0.85), _score_red))
	_sc_node.draw_string(_score_font, Vector2(right - 400.0 + 2.0, 74.0 + 2.0), score_text, HORIZONTAL_ALIGNMENT_RIGHT, 400.0, 48, Color(0, 0, 0, 0.5))
	_sc_node.draw_string(_score_font, Vector2(right - 400.0, 74.0), score_text, HORIZONTAL_ALIGNMENT_RIGHT, 400.0, 48, score_c)
	_sc_node.draw_string(font, Vector2(right - 400.0, 102.0), "%.2f%%" % prog_pct, HORIZONTAL_ALIGNMENT_RIGHT, 400.0, 20, Color(0.62, 0.9, 1.0, 0.9))


## キアイ中の光を更新する。キアイの出入りはなめらかに、光は拍の頭で立ち上がって(約 40ms)次の拍に向けて消えていく。
## 譜面上の時刻(ms)= (曲クロック − オフセット) × 再生速度 × 1000。曲(音)の拍に合わせたいので、オフセットは引いて数える。
func _update_kiai(delta: float, instant := false) -> void:
	var t_ms := (_now - float(settings.get("offset_ms", 0)) / 1000.0) * _rate * 1000.0
	var on: bool = _audio_started and not _dead and not sim.finished and bm.kiai_at(t_ms)
	var target := 1.0 if on else 0.0
	_kiai_a = target if instant else _kiai_a + (target - _kiai_a) * (1.0 - exp(-delta * 4.0))
	var ph: float = bm.beat_phase_at(t_ms)
	var pulse := smoothstep(0.0, 0.08, ph) * exp(-ph * 3.6)
	_beat_glow = _kiai_a * (KIAI_BASE + (1.0 - KIAI_BASE) * pulse)
	_apply_kiai()


func _apply_kiai() -> void:
	var k := 1.0 + KIAI_BG_GAIN * _beat_glow
	if _bg_img != null:
		_bg_img.modulate = Color(BG_TINT.r * k, BG_TINT.g * k, BG_TINT.b * k * 1.06)
	_arena_bg.color.a = ARENA_BG_ALPHA - KIAI_ARENA_DIM * _beat_glow
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
	var hp_rect := Rect2(HP_X - 26.0, HP_Y - 22.0, _hp_w + HP_SL + 52.0, HP_H + 46.0)
	var right := ARENA_POS.x + PatternGen.ARENA.x - 28.0
	var sc_rect := Rect2(right - 300.0, 6.0, 306.0, 124.0)
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


func _draw_hud() -> void:

	var font := ThemeDB.fallback_font
	var ax := ARENA_POS.x

	# --- 体力が低いときの、画面の左右端の赤み(残量に応じてなめらかに強まる。点滅・脈動なし) ---
	_draw_low_vignette()


	# 休憩のカウントダウン(フィールド中央。数字は小数点以下 2 桁、下に残り時間のバー)
	if _break_a > 0.01:
		var cx := ax + PatternGen.ARENA.x * 0.5
		var num := "%.2f" % _break_left
		var nw := _score_font.get_string_size("00.00", HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x   # 桁が変わっても位置がぶれないよう、幅は固定
		var ky := 300.0 - (1.0 - _break_a) * 8.0
		_hud.draw_string(font, Vector2(cx - 100.0, ky - 64.0), "BREAK", HORIZONTAL_ALIGNMENT_CENTER, 200.0, 14, Color(0.62, 0.9, 1.0, 0.8 * _break_a))
		_hud.draw_string(_score_font, Vector2(cx - nw * 0.5 + 2.0, ky + 2.0), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(0, 0, 0, 0.5 * _break_a))
		_hud.draw_string(_score_font, Vector2(cx - nw * 0.5, ky), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(1, 1, 1, 0.95 * _break_a))
		var bw := 280.0
		_hud.draw_rect(Rect2(cx - bw * 0.5, ky + 16.0, bw, 4.0), Color(1, 1, 1, 0.14 * _break_a))
		_hud.draw_rect(Rect2(cx - bw * 0.5, ky + 16.0, bw * _break_frac, 4.0), Color(0.62, 0.9, 1.0, 0.9 * _break_a))

	# 進行バー(フィールド下端。休憩地帯は淡い区間で示す)
	var span := maxf(_end_time, 1.0)
	var pr := clampf(_now / span, 0.0, 1.0)
	var aw: float = PatternGen.ARENA.x
	_hud.draw_rect(Rect2(ax, 716, aw, 4), Color(1, 1, 1, 0.08))
	if sim != null:
		for b in sim.breaks:
			var x0 := clampf(float(b[0]) / span, 0.0, 1.0) * aw
			var x1 := clampf(float(b[1]) / span, 0.0, 1.0) * aw
			_hud.draw_rect(Rect2(ax + x0, 716, maxf(x1 - x0, 1.0), 4), Color(1, 1, 1, 0.22))
	_hud.draw_rect(Rect2(ax, 716, aw * pr, 4), Color(0.5, 0.9, 1.0, 0.9))
	# アリーナ枠
	_hud.draw_rect(Rect2(ARENA_POS, PatternGen.ARENA), Color(1, 1, 1, 0.35).lerp(Color(1.0, 0.35, 0.38, 0.75), clampf(_hit_glow, 0.0, 1.0)), false, 2.0)   # 被弾中は枠がなめらかに赤くなる

func _capture_mouse() -> void:
	# カーソルを隠して移動量だけを受け取る(自機とカーソルがずれない)
	_mouse_accum = Vector2.ZERO
	_mouse_capture_ms = Time.get_ticks_msec()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE:
			if _can_skip():
				_request_skip()
		KEY_ESCAPE:
			if _end_timer < 0.0 and _outro_t < 0.0:
				_set_paused(not _menu_open())
		KEY_UP, KEY_DOWN:
			if _menu_open():
				var d := -1 if event.keycode == KEY_UP else 1
				for _i in range(5):
					_pause_sel = (_pause_sel + d + 5) % 5
					if not (_mp != null and _pause_sel == 1):   # マルチプレイにリトライはない
						break
				UiSfx.play("select", 1.0 + 0.12 * _pause_sel)
				if _pause_sel < _pause_btns.size():   # 選んだボタンが、ぴょこっと弾む
					_pause_btns[_pause_sel].pivot_offset = _pause_btns[_pause_sel].size * 0.5
					UiStyle.spring(_pause_btns[_pause_sel], "scale", Vector2(1.06, 1.06), Vector2.ONE, 0.3)
				_refresh_pause()
		KEY_LEFT, KEY_RIGHT:
			if _menu_open():
				var d := -5 if event.keycode == KEY_LEFT else 5
				if _pause_sel == 4:
					_set_sfx_volume(int(settings.get("sfx_volume", 70)) + d)
				else:
					_set_master_volume(int(settings.get("volume", 80)) + d)
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
	return sim.first_fire_time - SKIP_LEAD


## スキップできるか。最初のノーツの前で、進む幅が SKIP_MIN_GAIN 秒以上あるとき(マルチプレイは、開始の合図のあと)。
func _can_skip() -> bool:
	if sim == null or _skipped or _paused or _mp_menu or _dead or _end_timer >= 0.0 or _outro_t >= 0.0 or debug_seek >= 0.0 or sim.first_fire_time < 0.0:
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
		_debuff_l.text = "デバフ  " + GameSim.zone_name(_debuff_shown)
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
	elif not can and _skip_free:
		_skip_free = false
		Input.warp_mouse(get_viewport().get_screen_transform() * (ARENA_POS + sim.player_pos))
		_capture_mouse()


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
	_paused = p
	_pause_layer.visible = p
	UiSfx.play("open" if p else "close")
	if p:
		_pause_sel = 0
		_refresh_pause()
		_pause_panel.pivot_offset = _pause_panel.size * 0.5
		UiStyle.tween(_pause_layer, "modulate:a", 0.0, 1.0, 0.18)
		UiStyle.spring(_pause_panel, "scale", Vector2(0.9, 0.9), Vector2.ONE, 0.4)
		_pause_enter()
	if _audio_started:
		_audio.stream_paused = p
	if _mouse_mode:
		if p:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		else:
			_capture_mouse()


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
		settings.sfx_volume = Volume.sfx
	for i in range(_pause_btns.size()):
		var sel := (i == _pause_sel)
		_pause_btns[i].add_theme_stylebox_override("normal", UiStyle.box(
			Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.16) if sel else Color(1, 1, 1, 0.05),
			UiStyle.ACCENT if sel else UiStyle.LINE, 1, 4, 16, 8))
	for k in range(2):
		var row: Array = _pause_vol if k == 0 else _pause_sfx
		var value := int(settings.get("volume", 80)) if k == 0 else int(settings.get("sfx_volume", 70))
		row[0].set_value_no_signal(value)
		row[1].text = "%d%%" % value
		row[2].add_theme_color_override("font_color", UiStyle.ACCENT if _pause_sel == 3 + k else UiStyle.TEXT)


func _input(event: InputEvent) -> void:
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
	_center_label.pivot_offset = Vector2(PatternGen.ARENA.x * 0.5, 30)
	UiStyle.spring(_center_label, "scale", Vector2(0.8, 0.8), Vector2(1.15, 1.15), 0.3)
	var t := _center_label.create_tween()
	t.tween_interval(0.12)
	t.tween_property(_center_label, "modulate:a", 0.0, 0.4)
	t.tween_callback(func(): _center_label.visible = false)


## HUD の細かい動き: グレイズの数字が弾む / 被弾中は被弾時間が赤くなる / スキップ案内がなめらかに出入りする。
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
	_break_a = move_toward(_break_a, 1.0 if _update_break_count() else 0.0, delta * 4.0)


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
