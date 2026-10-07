extends "res://scripts/ui/lazer/lazer_screen.gd"
## サバイバルの曲の間(docs/survival_plan.md の §1)。3 つの場面が、同じ画面の中で順に入れ替わる:
##   結果   … 上の帯「STAGE n CLEAR」(光が走る)。札の中で、曲の点が数え上がる → 倍率が弾んで出る → 加わった点が数え上がる
##            → その点が合計点へ飛んで、合計点が数え上がる。並行して、ゲージが回復のぶんだけ伸びる(先端で光が弾ける)。
##            クリック・Enter・Space で、演出を飛ばして最後の状態にする。
##   3 択   … 強化の札が、めくれるように順に現れる。カーソルを乗せると浮き上がって光る。選ぶと札が光って弾け、
##            小さな光になって下の「強化」の列へ飛び込み、列の印が弾む。選べる回数が残っていれば、次の 3 択。
##   NEXT  … 結果と 3 択が上へ抜け、帯が「STAGE n」に変わる。次の曲名が右から滑り込み、難易度・Lv・倍率の札、
##            これまでの曲の Lv の道のり(次の曲は脈打つ輪)、用意の進み具合のバーが出る。用意ができたら背景が次の曲の絵に
##            変わってゆっくり寄り、バーが満ちたら go_requested。
## 進行は main が持つ: 3 択が済んだら choices_done を出し、main が次の曲を選んで show_next、用意ができたら set_ready を呼ぶ。
## 1 曲目の前は、結果も 3 択もなく、NEXT だけ。
## 文字は出し直さない(中身だけ変える。ちらつかせない)。演出は必ず最後まで出す(飛ばしたときは、最後の状態にそろえる)。
## 操作: 1 / 2 / 3 で強化を選ぶ。Esc で「あきらめる」の確認。

signal choices_done
signal go_requested
signal give_up_requested

const Upgrades = preload("res://scripts/survival/upgrades.gd")
const SurvivalRun = preload("res://scripts/survival/survival_run.gd")
const Mods = preload("res://scripts/mods.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const UiFx = preload("res://scripts/ui/ui_fx.gd")
const Settings = preload("res://scripts/settings.gd")

const NEXT_SHOW := 2.4        # NEXT を見せる最短の秒(用意ができてから、少なくとも NEXT_READY 秒)
const NEXT_READY := 1.1
const CARD_W := 292.0
const CARD_H := 206.0
const CARD_GAP := 26.0
const CHOICE_Y := 360.0
const STRIP_Y := 606.0
## 結果の演出の時刻(秒。画面を開いてから)
const T_SCORE := [0.35, 0.95]     # 曲の点が数え上がる
const T_MUL := 1.0                # 倍率が弾んで出る
const T_POINTS := [1.15, 1.55]    # 加わった点が数え上がる
const T_FLY := 1.6                # 加わった点が、合計点へ飛ぶ
const T_TOTAL := [1.85, 2.35]     # 合計点が数え上がる
const T_GAUGE := [0.9, 1.6]       # ゲージが回復のぶん伸びる
const INTRO_END := 2.45           # 結果の演出が終わる(3 択が出る)

var kind := "survival_break"
var run                         # SurvivalRun
var last: Dictionary = {}       # 終えた曲の記録(SurvivalRun.song_done の戻り値)。1 曲目の前は空
var gauge_from := 1.0           # 曲が終わったときのゲージ(いまの上限に対する割合)
var _bg_tex: Texture2D
var _music: AudioStreamPlayer

# 上の帯
var _banner: Control
var _banner_main: Label
var _banner_sub: Label
var _sweep := -1.0              # 帯を走る光の位置(0..1。-1 = 走っていない)

# 結果
var _result: Control
var _score_l: Label
var _mul_box: Control
var _points_l: Label
var _total_l: Label
var _gauge_bar: Control
var _gauge_to := 1.0
var _gauge_shown := 1.0
var _heal_pill: Control
var _xp_bar: Control            # 経験値のバー(レベルをまたいで伸びる)
var _xp_lv_l: Label
var _xp_from := 0.0
var _xp_to := 0.0
var _xp_shown := 0.0
var _xp_level := 0
var _t := 0.0
var _intro := false             # 結果の演出中
var _fired := {}                # 一度だけの演出(名前 → true)
var _quiet := false             # 演出を飛ばしている(粒・音を出さない)
var _tick_t := 0.0              # 数え上げの音の間引き

# 3 択
var _choice_box: Control
var _choice_cap: Label
var _choice_ids: Array = []
var _choice_cards: Array = []
var _choosing := false
var _choices_left := 0
var _strip: HBoxContainer       # 下の「強化」の列
var _strip_slots := {}          # 強化の id → 印
var _strip_none: Label          # 強化がまだないときの「なし」

# NEXT
var _next_box: Control
var _next_cap: Label
var _next_title: Label
var _next_sub: Label
var _next_pills: HBoxContainer
var _next_lv_l: Label
var _next_mul_l: Label
var _next_extra: Control
var _ladder: Control
var _next_status: Label
var _prog: Control
var _prog_k := 0.0
var _anim_t := 0.0              # 脈打つ・回る動きの時計
var _next_level := 0.0          # 次の曲の Lv(見積もり → 測り直したもの)
var _next_t := -1.0             # NEXT を出してからの秒(-1 = まだ)
var _ready_t := -1.0            # 用意ができてからの秒(-1 = まだ)
var _went := false
var _confirm: Control
var _options: Control
var _leaving := false


## run: いまのサバイバル / p_last: 終えた曲の記録(1 曲目の前は空)/ hp_end: 曲が終わったときのゲージ / bg: 背景 / music: 鳴り続けている曲(クリア。フェードアウトさせる)
func setup(p_run, p_last: Dictionary, hp_end: float, bg: Texture2D, music: AudioStreamPlayer = null) -> void:
	run = p_run
	last = p_last
	gauge_from = hp_end
	_bg_tex = bg
	_music = music


func _ready() -> void:
	settings = Settings.load_all()
	_build_base()
	if _bg_tex != null:
		set_background(_bg_tex, true)
	_build_toolbar(["サバイバル", "STAGE %d" % run.next_no()])
	_build_footer()
	var gu := _footer_button("あきらめる", Color(0.3, 0.28, 0.38), "x", 0, 220, _ask_give_up, LazerStyle.TEXT)
	gu.set_meta("juice_sound", "back")
	if _music != null:   # クリアした曲は流れたまま来るので、ゆっくり消す
		add_child(_music)
		var t := _music.create_tween()
		t.tween_property(_music, "volume_db", -40.0, 1.8)
		t.tween_callback(_music.stop)
	_build_banner()
	_build_strip()
	_build_next()
	if last.is_empty():
		_set_banner("STAGE 1", "SURVIVAL  START")
		_after_choices.call_deferred()
		return
	_set_banner("STAGE %d  CLEAR" % (run.next_no() - 1), "SURVIVAL")
	_build_result()
	_build_choice_area()
	_intro = true
	_t = 0.0
	if not UiStyle.animate:
		_skip_intro()


func _exit_tree() -> void:
	if _music != null and _music.playing:
		_music.stop()


func _process(delta: float) -> void:
	super._process(delta)
	_anim_t += delta
	if _sweep >= 0.0:
		_sweep += delta / 0.9
		if _sweep > 1.0:
			_sweep = -1.0
		_banner.queue_redraw()
	if _intro:
		_t += delta
		_tick_intro(delta)
	if _next_t >= 0.0:
		_tick_next(delta)


# --- 上の帯 ---

func _build_banner() -> void:
	_banner = Control.new()
	_place(_banner, 0, 50, 1280, 66)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.draw.connect(_draw_banner)
	_banner_sub = LazerStyle.label("", 13, LazerStyle.GREEN, true)
	_banner_sub.position = Vector2(0, 6)
	_banner_sub.size = Vector2(1280, 18)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_sub)
	_banner_main = LazerStyle.label("", 32, LazerStyle.TEXT, true)
	_banner_main.position = Vector2(0, 22)
	_banner_main.size = Vector2(1280, 40)
	_banner_main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_main.pivot_offset = Vector2(640, 20)
	_banner_main.add_theme_color_override("font_outline_color", Color(LazerStyle.GREEN.r, LazerStyle.GREEN.g, LazerStyle.GREEN.b, 0.22))
	_banner_main.add_theme_constant_override("outline_size", 10)
	_banner.add_child(_banner_main)


## 帯の文字を変え、光を走らせる(文字は弾んで入る)。
func _set_banner(main_text: String, sub_text: String) -> void:
	_banner_main.text = main_text
	_banner_sub.text = sub_text
	_sweep = 0.0
	if UiStyle.animate:
		UiStyle.spring(_banner_main, "scale", Vector2(1.18, 1.18), Vector2.ONE, 0.5)
		UiStyle.tween(_banner_main, "modulate:a", 0.0, 1.0, 0.25)


func _draw_banner() -> void:
	var w := _banner.size.x
	var h := _banner.size.y
	# 中央が濃く、左右へ消える帯
	var steps := 24
	for i in range(steps):
		var x0 := w * float(i) / steps
		var c := 1.0 - absf((float(i) + 0.5) / steps - 0.5) * 2.0
		_banner.draw_rect(Rect2(x0, 0, w / steps + 1.0, h), Color(0.02, 0.015, 0.05, 0.62 * pow(c, 0.7)))
	var g := LazerStyle.GREEN
	_banner.draw_rect(Rect2(w * 0.2, 0, w * 0.6, 1), Color(g.r, g.g, g.b, 0.35))
	_banner.draw_rect(Rect2(w * 0.2, h - 1, w * 0.6, 1), Color(g.r, g.g, g.b, 0.35))
	if _sweep >= 0.0:   # 走る光(左から右へ。なめらかに出て消える)
		var x := lerpf(-160.0, w + 160.0, 1.0 - pow(1.0 - _sweep, 2.0))
		var a := sin(_sweep * PI)
		for k in range(10):
			var d := float(k) * 12.0
			_banner.draw_rect(Rect2(x - d, 0, 12, h), Color(1, 1, 1, 0.07 * a * (1.0 - k / 10.0)))


# --- 結果 ---

func _build_result() -> void:
	_result = Control.new()
	_place(_result, 190, 126, 900, 226)
	_result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result.draw.connect(func():
		var sb := LazerStyle.box(Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.9), Color(1, 1, 1, 0.08), 1, 18)
		_result.draw_style_box(sb, Rect2(Vector2.ZERO, _result.size)))
	# 1 行目: Lv・曲名
	var row := HBoxContainer.new()
	row.position = Vector2(26, 16)
	row.size = Vector2(848, 26)
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result.add_child(row)
	var lv := float(last.level)
	row.add_child(LazerStyle.pill("Lv %.2f" % lv, LazerStyle.level_color(lv), 14))
	row.add_child(LazerStyle.label(LazerStyle.fit(LazerStyle.font_bold(), str(last.title), 17, 720.0), 17, LazerStyle.TEXT, true))   # title は「アーティスト - 曲名 [難易度]」
	# 2 行目: 曲の点 × 倍率 = 加わった点(左)と、合計点(右)
	var sc := _block(26, 54, 210, "曲の点", LazerStyle.TEXT)
	_score_l = sc[1]
	_op(244, 64, "×")
	var mb := _block(272, 54, 120, "倍率", LazerStyle.level_color(lv))
	_mul_box = mb[0]
	(mb[1] as Label).text = "× %.2f" % float(last.f)
	_op(400, 64, "=")
	var pb := _block(428, 54, 200, "加わった点", LazerStyle.GREEN)
	_points_l = pb[1]
	_points_l.text = "+ 0"
	var tc := LazerStyle.label("TOTAL", 13, LazerStyle.TEXT_MUTE, true)
	tc.position = Vector2(650, 52)
	tc.size = Vector2(224, 18)
	tc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_result.add_child(tc)
	_total_l = LazerStyle.label(UiStyle.fmt(int(round(float(run.total) - float(last.points)))), 44, LazerStyle.YELLOW, true)
	_total_l.position = Vector2(574, 66)
	_total_l.size = Vector2(300, 56)
	_total_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_total_l.pivot_offset = Vector2(230, 28)
	_total_l.add_theme_color_override("font_outline_color", Color(LazerStyle.YELLOW.r, LazerStyle.YELLOW.g, LazerStyle.YELLOW.b, 0.18))
	_total_l.add_theme_constant_override("outline_size", 14)
	_result.add_child(_total_l)
	# 3 行目: ゲージ(回復のぶんだけ伸びる)
	var gc := LazerStyle.label("ゲージ", 13, LazerStyle.TEXT_MUTE)
	gc.position = Vector2(26, 148)
	_result.add_child(gc)
	_gauge_bar = Control.new()
	_gauge_bar.position = Vector2(84, 148)
	_gauge_bar.size = Vector2(560, 20)
	_gauge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_bar.draw.connect(_draw_gauge)
	_result.add_child(_gauge_bar)
	_gauge_to = float(run.gauge_frac())
	_gauge_shown = gauge_from
	var heal := float(run.between_heal())
	_heal_pill = LazerStyle.pill("+%d%% 回復" % int(round(heal * 100.0)), LazerStyle.GREEN, 13)
	_heal_pill.position = Vector2(660, 146)
	_heal_pill.modulate.a = 0.0
	_result.add_child(_heal_pill)
	# 4 行目: 経験値(倒した数・取った経験値。バーはレベルをまたいで伸び、上がるたびにレベルの数字が弾む)
	var xc := LazerStyle.label("経験値", 13, LazerStyle.TEXT_MUTE)
	xc.position = Vector2(26, 186)
	_result.add_child(xc)
	_xp_to = float(run.xp)
	_xp_from = _xp_to - float(last.get("xp_got", 0.0))
	_xp_shown = _xp_from
	_xp_level = SurvivalRun.level_for_xp(_xp_from)
	_xp_bar = Control.new()
	_xp_bar.position = Vector2(84, 190)
	_xp_bar.size = Vector2(460, 12)
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_bar.draw.connect(_draw_xp)
	_result.add_child(_xp_bar)
	_xp_lv_l = LazerStyle.label("LEVEL %d" % _xp_level, 15, LazerStyle.GREEN, true)
	_xp_lv_l.position = Vector2(556, 182)
	_xp_lv_l.size = Vector2(90, 22)
	_xp_lv_l.pivot_offset = Vector2(40, 11)
	_result.add_child(_xp_lv_l)
	var ki := LazerStyle.label("撃破 %d / %d 体 ・ 経験値 + %d" % [int(last.get("kills", 0)), int(last.get("spawned", 0)), int(round(float(last.get("xp_got", 0.0))))], 13, LazerStyle.TEXT_DIM)
	ki.position = Vector2(650, 184)
	ki.size = Vector2(224, 20)
	ki.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_result.add_child(ki)
	UiStyle.pop_in(_result, 0.1, Vector2(0, 22), 0.45)


## 数字の箱(見出し + 値)。[箱, 値の Label] を返す。
func _block(x: float, y: float, w: float, cap: String, col: Color) -> Array:
	var p := PanelContainer.new()
	p.position = Vector2(x, y)
	p.custom_minimum_size = Vector2(w, 74)
	p.size = Vector2(w, 74)
	p.add_theme_stylebox_override("panel", LazerStyle.box(Color(1, 1, 1, 0.04), Color(col.r, col.g, col.b, 0.22), 1, 12, 14, 8))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.pivot_offset = Vector2(w * 0.5, 37)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	v.add_child(LazerStyle.label(cap, 12, LazerStyle.TEXT_MUTE))
	var l := LazerStyle.label("0", 26, col, true)
	v.add_child(l)
	_result.add_child(p)
	return [p, l]


func _op(x: float, y: float, text: String) -> void:
	var l := LazerStyle.label(text, 26, LazerStyle.TEXT_MUTE, true)
	l.position = Vector2(x, y)
	_result.add_child(l)


func _draw_gauge() -> void:
	var w := _gauge_bar.size.x
	var h := _gauge_bar.size.y
	_gauge_bar.draw_style_box(LazerStyle.box(Color(0.03, 0.025, 0.06, 0.85), Color(1, 1, 1, 0.16), 1, 10), Rect2(0, 0, w, h))
	var base_w := (w - 4.0) * clampf(gauge_from, 0.0, 1.0)
	var now_w := (w - 4.0) * clampf(_gauge_shown, 0.0, 1.0)
	if now_w > base_w + 0.5:   # 回復したぶん(明るい緑。先端に光)
		_gauge_bar.draw_style_box(LazerStyle.box(Color(0.55, 1.0, 0.72, 0.9), Color(0, 0, 0, 0), 0, maxi(int(minf(h * 0.5 - 2.0, now_w * 0.5)), 1)), Rect2(2, 2, now_w, h - 4.0))
		_gauge_bar.draw_circle(Vector2(2.0 + now_w, h * 0.5), 9.0, Color(0.7, 1.0, 0.8, 0.25))
	if base_w > 3.0:
		_gauge_bar.draw_style_box(LazerStyle.box(UiStyle.hp_color(gauge_from), Color(0, 0, 0, 0), 0, maxi(int(minf(h * 0.5 - 2.0, base_w * 0.5)), 1)), Rect2(2, 2, base_w, h - 4.0))
	# 被ダメージ半減の境目(初期の体力の 30%)
	var lx := 2.0 + (w - 4.0) * clampf(SurvivalRun.LOW_LINE / float(run.max_gauge()), 0.0, 1.0)
	_gauge_bar.draw_colored_polygon(PackedVector2Array([Vector2(lx - 4.0, -7.0), Vector2(lx + 4.0, -7.0), Vector2(lx, -1.0)]), Color(1, 1, 1, 0.5))


func _draw_xp() -> void:
	var pr := SurvivalRun.xp_progress(_xp_shown)
	var w := _xp_bar.size.x
	var h := _xp_bar.size.y
	var k := clampf(float(pr.into) / maxf(float(pr.need), 0.001), 0.0, 1.0)
	var g := LazerStyle.GREEN
	_xp_bar.draw_style_box(LazerStyle.box(Color(0.03, 0.025, 0.06, 0.85), Color(1, 1, 1, 0.14), 1, 6), Rect2(0, 0, w, h))
	if k > 0.0:
		_xp_bar.draw_style_box(LazerStyle.box(g, Color(0, 0, 0, 0), 0, 5), Rect2(2, 2, maxf((w - 4.0) * k, h - 4.0), h - 4.0))


func _ease(t0: float, t1: float) -> float:
	var x := clampf((_t - t0) / maxf(t1 - t0, 0.001), 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


## 結果の演出を、時刻 _t に合わせて進める。
func _tick_intro(delta: float) -> void:
	var song_score := float(last.score)
	var points := float(last.points)
	var total_to := float(run.total)
	var total_from := total_to - points
	var counting := false
	if _t >= T_SCORE[0]:
		var k := _ease(T_SCORE[0], T_SCORE[1])
		_score_l.text = UiStyle.fmt(int(round(song_score * k)))
		counting = counting or k < 1.0
	if _t >= T_MUL and _once("mul"):
		_fx_ring(_mul_box, LazerStyle.level_color(float(last.level)))
		UiStyle.spring(_mul_box, "scale", Vector2(1.25, 1.25), Vector2.ONE, 0.45)
		_sound("confirm", 1.2)
	if _t >= T_POINTS[0]:
		var k2 := _ease(T_POINTS[0], T_POINTS[1])
		_points_l.text = "+ " + UiStyle.fmt(int(round(points * k2)))
		counting = counting or k2 < 1.0
	if _t >= T_FLY and _once("fly"):
		_fly_points()
	if _t >= T_TOTAL[0]:
		var k3 := _ease(T_TOTAL[0], T_TOTAL[1])
		_total_l.text = UiStyle.fmt(int(round(lerpf(total_from, total_to, k3))))
		counting = counting or k3 < 1.0
	if _t >= T_TOTAL[1] and _once("total"):
		UiStyle.spring(_total_l, "scale", Vector2(1.12, 1.12), Vector2.ONE, 0.45)
		if not _quiet:
			UiFx.burst(self, _total_l.get_global_rect().get_center() + Vector2(60, 0), LazerStyle.YELLOW, 16, 240.0, 0.6, 3.0)
		_sound("stamp", 1.0)
	if _t >= T_GAUGE[0]:
		_gauge_shown = lerpf(gauge_from, _gauge_to, _ease(T_GAUGE[0], T_GAUGE[1]))
		_gauge_bar.queue_redraw()
		if _once("heal"):
			UiStyle.tween(_heal_pill, "modulate:a", 0.0, 1.0, 0.25)
			UiStyle.pop_in(_heal_pill, 0.0, Vector2(-14, 0), 0.3)
	if _t >= T_GAUGE[0]:   # 経験値: ゲージと同じ間に伸びる
		_xp_shown = lerpf(_xp_from, _xp_to, _ease(T_GAUGE[0], T_GAUGE[1] + 0.3))
		_xp_bar.queue_redraw()
		var lv := SurvivalRun.level_for_xp(_xp_shown)
		if lv > _xp_level:
			_xp_level = lv
			_xp_lv_l.text = "LEVEL %d" % lv
			UiStyle.spring(_xp_lv_l, "scale", Vector2(1.4, 1.4), Vector2.ONE, 0.45)
			_fx_ring(_xp_lv_l, LazerStyle.GREEN)
			_sound("on", 1.2 + 0.1 * lv)
	if _t >= T_GAUGE[1] and _once("heal_end") and _gauge_to > gauge_from + 0.005 and not _quiet:
		var tip := _gauge_bar.global_position + Vector2(2.0 + (_gauge_bar.size.x - 4.0) * _gauge_to, _gauge_bar.size.y * 0.5)
		UiFx.burst(self, tip, Color(0.6, 1.0, 0.75), 10, 150.0, 0.5, 2.5)
	_tick_t -= delta
	if counting and _tick_t <= 0.0:
		_tick_t = 0.055
		_sound("count", 1.0 + 0.4 * clampf(_t / INTRO_END, 0.0, 1.0), 0.6)
	if _t >= INTRO_END:
		_intro = false
		_start_choices()


func _once(key: String) -> bool:
	if _fired.has(key):
		return false
	_fired[key] = true
	return true


func _sound(name_s: String, pitch := 1.0, gain := 1.0) -> void:
	if not _quiet:
		UiSfx.play(name_s, pitch, gain)


func _fx_ring(c: Control, col: Color) -> void:
	if not _quiet:
		var at := c.get_global_rect().get_center()
		UiFx.ring(self, at, col, 24.0, 110.0, 0.5, 2.5)


## 加わった点が、光る文字になって合計点へ飛ぶ。
func _fly_points() -> void:
	if _quiet or not UiStyle.animate:
		return
	var l := LazerStyle.label(_points_l.text, 24, LazerStyle.GREEN, true)
	l.add_theme_color_override("font_outline_color", Color(LazerStyle.GREEN.r, LazerStyle.GREEN.g, LazerStyle.GREEN.b, 0.3))
	l.add_theme_constant_override("outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	var from := _points_l.global_position
	var to := _total_l.global_position + Vector2(_total_l.size.x - 200.0, 6.0)
	l.position = from
	var t := l.create_tween().set_parallel(true)
	t.tween_property(l, "position", to, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_property(l, "modulate:a", 0.0, 0.12).set_delay(0.2)
	t.chain().tween_callback(l.queue_free)
	_sound("whoosh", 1.3, 0.7)


## 演出を飛ばして、最後の状態にする。
func _skip_intro() -> void:
	if not _intro:
		return
	_quiet = true
	_t = INTRO_END
	_tick_intro(0.0)
	_quiet = false


# --- 3 択 ---

func _build_choice_area() -> void:
	_choice_box = Control.new()
	_place(_choice_box, 0, CHOICE_Y, 1280, CARD_H + 44)
	_choice_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_cap = LazerStyle.label("", 15, LazerStyle.TEXT_DIM, true)
	_choice_cap.position = Vector2(0, 0)
	_choice_cap.size = Vector2(1280, 22)
	_choice_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choice_cap.modulate.a = 0.0
	_choice_box.add_child(_choice_cap)


func _start_choices() -> void:
	_choices_left = int(run.picks)
	if _choices_left > 0:
		_roll()
		return
	# レベルが上がらなかった: 強化はない(一言出して、NEXT へ)
	_choice_cap.text = "レベルは上がらなかった(強化なし)"
	UiStyle.tween(_choice_cap, "modulate:a", 0.0, 1.0, 0.25)
	if UiStyle.animate:
		await get_tree().create_timer(1.1).timeout
	_after_choices()


## 3 択を引いて、札を並べる(めくれるように、順に現れる)。
func _roll() -> void:
	for c in _choice_cards:
		c.queue_free()
	_choice_cards.clear()
	_choice_ids = run.roll_choices(3)
	if _choice_ids.is_empty():
		_after_choices()
		return
	_choice_cap.text = "LEVEL UP!   強化を 1 つ選ぶ" + ("   (あと %d 回)" % _choices_left if _choices_left > 1 else "")
	UiStyle.tween(_choice_cap, "modulate:a", _choice_cap.modulate.a, 1.0, 0.25)
	var n := _choice_ids.size()
	var x0 := (1280.0 - (CARD_W * n + CARD_GAP * (n - 1))) * 0.5
	for i in range(n):
		var id := str(_choice_ids[i])
		var c := ChoiceCard.new(Upgrades.find(id), run.level_of(id), i)
		c.position = Vector2(x0 + i * (CARD_W + CARD_GAP), 30)
		c.size = Vector2(CARD_W, CARD_H)
		c.pivot_offset = Vector2(CARD_W * 0.5, CARD_H * 0.5)
		c.picked.connect(func(): _choose(i))
		_choice_box.add_child(c)
		_choice_cards.append(c)
		if UiStyle.animate:   # めくれるように現れる(横に縮んだところから開き、少し上がる)
			c.scale = Vector2(0.05, 0.9)
			c.modulate.a = 0.0
			var d := 0.06 + 0.09 * i
			var t := c.create_tween().set_parallel(true)
			t.tween_property(c, "scale", Vector2.ONE, 0.42).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t.tween_property(c, "modulate:a", 1.0, 0.18).set_delay(d)
			t.tween_property(c, "position:y", 30.0, 0.42).from(52.0).set_delay(d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_choosing = true
	UiSfx.play("open")


func _choose(i: int) -> void:
	if not _choosing or i < 0 or i >= _choice_ids.size() or _confirm != null:
		return
	_choosing = false
	var id := str(_choice_ids[i])
	run.choose(id)
	_choices_left = int(run.picks)
	var u := Upgrades.find(id)
	var col: Color = u.color
	var card: ChoiceCard = _choice_cards[i]
	for c in _choice_cards:
		(c as ChoiceCard).enabled = false
	card.flash = 1.0
	UiSfx.play("confirm")
	var at := card.get_global_rect().get_center()
	UiFx.ring(self, at, col, 40.0, 240.0, 0.6, 3.0)
	UiFx.burst(self, at, col, 20, 300.0, 0.6, 3.0)
	UiStyle.spring(card, "scale", Vector2(1.08, 1.08), Vector2.ONE, 0.4)
	for k in range(_choice_cards.size()):   # 選ばなかった札は、下へ沈んで消える
		if k != i:
			var o: Control = _choice_cards[k]
			UiStyle.tween(o, "modulate:a", 1.0, 0.0, 0.28)
			UiStyle.tween(o, "position:y", o.position.y, o.position.y + 36.0, 0.3, 0.0, Tween.TRANS_CUBIC, Tween.EASE_IN)
	var slot := _refresh_strip(id)
	if UiStyle.animate:
		await get_tree().create_timer(0.42).timeout
		if not is_inside_tree():
			return
		# 選んだ札は縮んで消え、光が下の「強化」の列へ飛び込む
		UiStyle.tween(card, "modulate:a", 1.0, 0.0, 0.25)
		UiStyle.tween(card, "scale", card.scale, Vector2(0.7, 0.7), 0.25, 0.0, Tween.TRANS_CUBIC, Tween.EASE_IN)
		await _fly_to_slot(at, slot, col)
		if not is_inside_tree():
			return
	else:
		slot.modulate.a = 1.0
	if _choices_left > 0:
		_roll()
	else:
		_after_choices()


## 光の玉を from から、列の印 slot へ飛ばす。着いたら印が弾む。
func _fly_to_slot(from: Vector2, slot: Control, col: Color) -> void:
	await get_tree().process_frame   # 列の並びが決まるのを待つ
	var to := slot.get_global_rect().get_center()
	var orb := Control.new()
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orb.size = Vector2(1, 1)
	orb.draw.connect(func():
		orb.draw_circle(Vector2.ZERO, 16.0, Color(col.r, col.g, col.b, 0.25))
		orb.draw_circle(Vector2.ZERO, 8.0, col.lerp(Color.WHITE, 0.4)))
	add_child(orb)
	orb.position = from
	var mid := (from + to) * 0.5 + Vector2(0, -90)
	var tw := orb.create_tween()
	tw.tween_method(func(k: float):
		var a := from.lerp(mid, k)
		var b := mid.lerp(to, k)
		orb.position = a.lerp(b, k), 0.0, 1.0, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	UiSfx.play("whoosh", 1.2, 0.7)
	await tw.finished
	orb.queue_free()
	if not is_inside_tree():
		return
	slot.modulate.a = 1.0
	slot.pivot_offset = slot.size * 0.5
	UiStyle.spring(slot, "scale", Vector2(1.35, 1.35), Vector2.ONE, 0.45)
	UiFx.ring(self, to, col, 10.0, 60.0, 0.4, 2.0)
	UiSfx.play("on", 1.1)


# --- 下の「強化」の列 ---

func _build_strip() -> void:
	var cap := LazerStyle.label("強化", 12, LazerStyle.TEXT_MUTE, true)
	cap.position = Vector2(250, STRIP_Y + 14)
	add_child(cap)
	_strip = HBoxContainer.new()
	_strip.position = Vector2(290, STRIP_Y + 6)
	_strip.size = Vector2(900, 36)
	_strip.add_theme_constant_override("separation", 8)
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)
	_strip_none = LazerStyle.label("なし", 13, LazerStyle.TEXT_MUTE)
	_strip_none.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_strip.add_child(_strip_none)
	_refresh_strip("")


## 列を、いまの強化に合わせる。new_id: いま選んだ強化(その印は見えない状態で置き、光が着いたら出す)。戻り値: その印。
func _refresh_strip(new_id: String) -> Control:
	var want: Array = []   # [id, 文字]
	for u in Upgrades.ALL:
		var id := str(u.id)
		match id:
			"guard":
				if int(run.guard) > 0:
					want.append([id, "×%d" % int(run.guard)])
			"bet":
				if bool(run.bet_next):
					want.append([id, "次の曲"])
			_:
				if run.level_of(id) > 0:
					want.append([id, "%d / %d" % [run.level_of(id), int(u.max)]])
	var keep := {}
	for w in want:
		keep[w[0]] = true
	for id in _strip_slots.keys():
		if not keep.has(id):
			(_strip_slots[id] as Control).queue_free()
			_strip_slots.erase(id)
	var out: Control = null
	for w in want:
		var id: String = w[0]
		var slot: Control = _strip_slots.get(id)
		if slot == null:
			slot = _make_slot(id)
			_strip.add_child(slot)
			_strip_slots[id] = slot
			if id == new_id:
				slot.modulate.a = 0.0
		(slot.get_meta("label") as Label).text = str(w[1])
		_strip.move_child(slot, -1)
		if id == new_id:
			out = slot
	_strip_none.visible = want.is_empty()
	if out == null and _strip_slots.has(new_id):
		out = _strip_slots[new_id]
	return out if out != null else _strip


func _make_slot(id: String) -> Control:
	var u := Upgrades.find(id)
	var col: Color = u.color
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", LazerStyle.box(Color(col.r * 0.2, col.g * 0.2, col.b * 0.2, 0.85), Color(col.r, col.g, col.b, 0.6), 1, 14, 10, 4))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var ic := LazerIcons.new(str(u.icon), col, 16.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	h.add_child(LazerStyle.label(str(u.name), 13, LazerStyle.TEXT, true))
	var l := LazerStyle.label("", 13, col, true)
	h.add_child(l)
	p.set_meta("label", l)
	return p


func _after_choices() -> void:
	if not is_inside_tree():
		return
	if _result != null and UiStyle.animate:   # 結果と 3 択は、上へ抜けて消える
		for c in [_result, _choice_box]:
			UiStyle.tween(c, "modulate:a", 1.0, 0.0, 0.3)
			UiStyle.tween(c, "position:y", c.position.y, c.position.y - 30.0, 0.32, 0.0, Tween.TRANS_CUBIC, Tween.EASE_IN)
		await get_tree().create_timer(0.3).timeout
		if not is_inside_tree():
			return
	if _result != null:
		_result.visible = false
		_choice_box.visible = false
	choices_done.emit()


# --- NEXT ---

func _build_next() -> void:
	_next_box = Control.new()
	_place(_next_box, 0, 124, 1280, 470)
	_next_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_next_box.visible = false
	_next_box.draw.connect(func():   # 曲名の下の、左右へ消える帯
		var w := _next_box.size.x
		for i in range(24):
			var c := 1.0 - absf((float(i) + 0.5) / 24.0 - 0.5) * 2.0
			_next_box.draw_rect(Rect2(w * i / 24.0, 36, w / 24.0 + 1.0, 196), Color(0.02, 0.015, 0.05, 0.55 * pow(c, 0.8))))
	_next_cap = LazerStyle.label("NEXT", 16, LazerStyle.GREEN, true)
	_next_cap.position = Vector2(0, 46)
	_next_cap.size = Vector2(1280, 20)
	_next_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_next_box.add_child(_next_cap)
	_next_title = LazerStyle.label("", 46, LazerStyle.TEXT, true)
	_next_title.position = Vector2(80, 70)
	_next_title.size = Vector2(1120, 60)
	_next_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_next_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	_next_title.add_theme_constant_override("outline_size", 8)
	_next_box.add_child(_next_title)
	_next_sub = LazerStyle.label("", 20, LazerStyle.TEXT_DIM)
	_next_sub.position = Vector2(80, 132)
	_next_sub.size = Vector2(1120, 28)
	_next_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_next_box.add_child(_next_sub)
	_next_pills = HBoxContainer.new()
	_next_pills.position = Vector2(0, 172)
	_next_pills.size = Vector2(1280, 40)
	_next_pills.alignment = BoxContainer.ALIGNMENT_CENTER
	_next_pills.add_theme_constant_override("separation", 10)
	_next_pills.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_next_box.add_child(_next_pills)
	var lvp := _big_pill("Lv", LazerStyle.TEXT)
	_next_lv_l = lvp[1]
	_next_pills.add_child(lvp[0])
	var mp := _big_pill("倍率", LazerStyle.YELLOW)
	_next_mul_l = mp[1]
	_next_pills.add_child(mp[0])
	# これまでの曲の Lv の道のり
	_ladder = Control.new()
	_ladder.position = Vector2(240, 262)
	_ladder.size = Vector2(800, 92)
	_ladder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ladder.draw.connect(_draw_ladder)
	_next_box.add_child(_ladder)
	# 用意の進み具合
	_next_status = LazerStyle.label("", 14, LazerStyle.TEXT_MUTE)
	_next_status.position = Vector2(0, 376)
	_next_status.size = Vector2(1280, 20)
	_next_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_next_box.add_child(_next_status)
	_prog = Control.new()
	_prog.position = Vector2(390, 404)
	_prog.size = Vector2(500, 6)
	_prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prog.draw.connect(_draw_prog)
	_next_box.add_child(_prog)


## 大きめの札(見出し + 値)。[札, 値の Label]
func _big_pill(cap: String, col: Color) -> Array:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", LazerStyle.box(Color(0.04, 0.035, 0.08, 0.85), Color(col.r, col.g, col.b, 0.5), 1, 16, 16, 5))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var c := LazerStyle.label(cap, 13, LazerStyle.TEXT_MUTE)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(c)
	var l := LazerStyle.label("", 20, col, true)
	h.add_child(l)
	return [p, l]


## 次の曲を出す(main が、選んだら呼ぶ。読めなくて選び直したときも、同じ場所の文字だけを変える)。
## info: {title, artist, version, est(見積もりの Lv), extra_mods}
func show_next(info: Dictionary) -> void:
	var first_show := not _next_box.visible
	_next_box.visible = true
	_next_title.text = LazerStyle.fit(LazerStyle.font_bold(), str(info.get("title", "")), 46, 1100.0)
	_next_sub.text = LazerStyle.fit(LazerStyle.font(), "%s   ・   %s" % [str(info.get("artist", "")), str(info.get("version", ""))], 20, 1100.0)
	_next_level = float(info.get("est", 0.0))
	_show_level(_next_level, true)
	if _next_extra != null:
		_next_extra.queue_free()
		_next_extra = null
	var extra: Array = info.get("extra_mods", [])
	if not extra.is_empty():
		_next_extra = LazerStyle.pill("もう一度: %s" % Mods.names(extra), Color(0.82, 0.6, 1.0), 14)
		_next_extra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_next_pills.add_child(_next_extra)
	_next_status.text = "用意しています…"
	_ready_t = -1.0
	_prog_k = 0.0
	_ladder.queue_redraw()
	if first_show:
		_next_t = 0.0
		if not last.is_empty():
			_set_banner("STAGE %d" % run.next_no(), "SURVIVAL")
		if UiStyle.animate:
			_next_box.modulate.a = 0.0
			UiStyle.tween(_next_box, "modulate:a", 0.0, 1.0, 0.3)
			UiStyle.pop_in(_next_cap, 0.0, Vector2(0, -10), 0.35)
			UiStyle.pop_in(_next_title, 0.05, Vector2(70, 0), 0.5)
			UiStyle.pop_in(_next_sub, 0.12, Vector2(70, 0), 0.5)
			UiStyle.pop_in(_next_pills, 0.2, Vector2(0, 14), 0.4)
			UiStyle.pop_in(_ladder, 0.28, Vector2(0, 14), 0.45)
		UiSfx.play("whoosh")


## Lv と倍率の札の文字。est = true なら「くらい」(見積もり)。
func _show_level(lv: float, est: bool) -> void:
	_next_lv_l.text = "%.2f%s" % [lv, " くらい" if est else ""]
	_next_lv_l.add_theme_color_override("font_color", LazerStyle.level_color(lv))
	_next_mul_l.text = "× %.2f%s" % [SurvivalRun.f_of(lv), " くらい" if est else ""]


## 次の曲の用意ができた。level: MOD 込みの Lv(測り直したもの)/ tex: 次の曲の背景
func set_ready(level: float, tex: Texture2D) -> void:
	var from := _next_level
	_next_level = level
	if UiStyle.animate:   # 見積もりから、測り直した値へ、数字がなめらかに動く
		UiStyle.tween_value(self, from, level, 0.45, func(v: float): _show_level(v, false))
	else:
		_show_level(level, false)
	_ladder.queue_redraw()
	_next_status.text = "まもなく始まります"
	if tex != null:
		set_background(tex)
	if UiStyle.animate:   # 背景が、ゆっくり寄っていく(開始前画面と同じ動き)
		var dur := NEXT_SHOW + 0.6
		UiStyle.tween(_bg_holder, "scale", Vector2.ONE, Vector2.ONE * (1.0 + LazerStyle.LAUNCH_ZOOM_SPEED * dur), dur, 0.0, Tween.TRANS_LINEAR)
	_ready_t = 0.0


## 用意できなかった(曲を選び直せないとき)。
func show_error(msg: String) -> void:
	_next_status.text = msg


func _tick_next(delta: float) -> void:
	_next_t += delta
	_ladder.queue_redraw()
	if _ready_t >= 0.0:
		_ready_t += delta
		var need := maxf(NEXT_SHOW - (_next_t - _ready_t), NEXT_READY)   # NEXT を出してから NEXT_SHOW 秒、用意ができてから NEXT_READY 秒の、遅いほう
		_prog_k = clampf(_ready_t / need, 0.0, 1.0)
		if _prog_k >= 1.0 and not _went and _confirm == null and _options == null:
			_went = true
			UiFx.ring(self, _next_title.get_global_rect().get_center(), LazerStyle.GREEN, 40.0, 420.0, 0.6, 3.0)
			UiSfx.play("confirm", 1.1)
			go_requested.emit()
	_prog.queue_redraw()


func _draw_prog() -> void:
	var w := _prog.size.x
	var h := _prog.size.y
	_prog.draw_style_box(LazerStyle.box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 0, 3), Rect2(0, 0, w, h))
	var g := LazerStyle.GREEN
	if _ready_t < 0.0:   # 用意の途中: 光の帯が左右に行き来する
		var x := (0.5 + 0.5 * sin(_anim_t * 3.2)) * (w - 90.0)
		_prog.draw_style_box(LazerStyle.box(Color(g.r, g.g, g.b, 0.55), Color(0, 0, 0, 0), 0, 3), Rect2(x, 0, 90.0, h))
		return
	if _prog_k > 0.0:
		_prog.draw_style_box(LazerStyle.box(g, Color(0, 0, 0, 0), 0, 3), Rect2(0, 0, maxf(w * _prog_k, h), h))
		_prog.draw_circle(Vector2(w * _prog_k, h * 0.5), 7.0, Color(g.r, g.g, g.b, 0.3))


## これまでの曲の Lv の道のり: 線の上に、遊んだ曲(最大 6 曲)の点と、次の曲の点(脈打つ輪)。点の高さは Lv。
func _draw_ladder() -> void:
	var songs: Array = run.songs
	var shown: Array = songs.slice(maxi(songs.size() - 6, 0))
	var n := shown.size() + 1
	var w := _ladder.size.x
	var h := _ladder.size.y
	var step := minf(120.0, w / maxf(float(n), 1.0))
	var x0 := w * 0.5 - step * (n - 1) * 0.5
	var lvs: Array = shown.map(func(e): return float(e.level))
	lvs.append(_next_level)
	var lo := 99.0
	var hi := 0.0
	for v in lvs:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var span := maxf(hi - lo, 0.6)
	var pts: Array = []
	for i in range(n):
		var y := h - 30.0 - (float(lvs[i]) - lo) / span * (h - 54.0)
		pts.append(Vector2(x0 + step * i, y))
	for i in range(n - 1):   # 点をつなぐ線(次の曲へは点線)
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		if i == n - 2:
			_ladder.draw_dashed_line(a, b, Color(1, 1, 1, 0.35), 2.0, 6.0)
		else:
			_ladder.draw_line(a, b, Color(1, 1, 1, 0.28), 2.0, true)
	var font := LazerStyle.font_bold()
	var no0: int = songs.size() - shown.size() + 1
	for i in range(n):
		var p: Vector2 = pts[i]
		var lv := float(lvs[i])
		var col := LazerStyle.level_color(lv)
		var is_next := i == n - 1
		if is_next:   # 次の曲: 脈打つ輪
			var k := 0.5 + 0.5 * sin(_anim_t * 4.0)
			_ladder.draw_circle(p, 16.0 + 4.0 * k, Color(col.r, col.g, col.b, 0.12 + 0.08 * k))
			_ladder.draw_arc(p, 12.0, 0.0, TAU, 40, col, 2.5, true)
			_ladder.draw_circle(p, 5.0, col)
		else:
			_ladder.draw_circle(p, 8.0, col)
			_ladder.draw_polyline(PackedVector2Array([p + Vector2(-3.5, 0), p + Vector2(-1, 2.5), p + Vector2(3.5, -2.5)]), Color(0.05, 0.04, 0.08), 1.8, true)
		var no_text := "NEXT" if is_next else str(no0 + i)
		_ladder.draw_string(font, p + Vector2(-40, -18), no_text, HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color(1, 1, 1, 0.9 if is_next else 0.5))
		_ladder.draw_string(font, p + Vector2(-40, 26), "%.2f" % lv, HORIZONTAL_ALIGNMENT_CENTER, 80, 13, col if is_next else Color(col.r, col.g, col.b, 0.75))


# --- あきらめる・入力 ---

func _ask_give_up() -> void:
	if _confirm != null or _went or _leaving:
		return
	var q = load("res://scripts/ui/ui_sets.gd").current().make_quit()
	q.setup("サバイバルを終わりますか？", "終わる", "続ける", "ここまでの点で記録します")
	q.confirmed.connect(func():
		_leaving = true
		give_up_requested.emit())
	q.closed.connect(func():
		if _confirm != null:
			_confirm.queue_free()
			_confirm = null)
	_confirm = q
	add_child(q)


func on_overlay(open: bool, panel: Control = null) -> void:
	_options = panel if open else null


func _unhandled_input(event: InputEvent) -> void:
	if _intro and _confirm == null and _options == null and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_skip_intro()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if _confirm != null or _options != null or _leaving or not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1, KEY_KP_1:
			_choose(0)
		KEY_2, KEY_KP_2:
			_choose(1)
		KEY_3, KEY_KP_3:
			_choose(2)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if not _intro:
				return
			_skip_intro()
		KEY_ESCAPE:
			_ask_give_up()
		_:
			return
	get_viewport().set_input_as_handled()


# --- 強化の札 ---

## 強化の札 1 枚。上に種類の色の線、左上に絵の入った円、名前・種類・要点・説明、下に段の印。
## カーソルを乗せると浮き上がって、種類の色で光る(押すと picked)。レアな強化は、上の縁を金色の光が流れる。
class ChoiceCard extends Control:
	signal picked

	const LS = preload("res://scripts/ui/lazer/lazer_style.gd")
	const LI = preload("res://scripts/ui/lazer/lazer_icons.gd")
	const US = preload("res://scripts/ui/ui_sfx.gd")
	const GROUP_NAME := {"def": "守り", "bet": "賭け", "atk": "攻撃"}

	var u: Dictionary
	var lvl := 0
	var idx := 0
	var col := Color.WHITE
	var enabled := true
	var flash := 0.0      # 選んだときの白い光(1 → 0)
	var _hover := 0.0     # 浮き上がりの度合い(0..1。なめらかに追従)
	var _hover_to := 0.0
	var _t := 0.0
	var _content: Control

	func _init(p_u: Dictionary, p_lvl: int, p_idx: int) -> void:
		u = p_u
		lvl = p_lvl
		idx = p_idx
		col = u.color
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func():
			if enabled:
				_hover_to = 1.0
				US.play("hover"))
		mouse_exited.connect(func(): _hover_to = 0.0)

	func _ready() -> void:
		_content = Control.new()
		_content.size = size
		_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_content)
		var name_l := LS.label(str(u.name), 21, LS.TEXT, true)
		name_l.position = Vector2(84, 22)
		_content.add_child(name_l)
		var g := str(u.group)
		var tag := LS.label(str(GROUP_NAME.get(g, "")) + ("  ・  レア" if bool(u.get("rare", false)) else ""), 12, col, true)
		tag.position = Vector2(84, 52)
		_content.add_child(tag)
		var key := LS.label(str(idx + 1), 14, LS.TEXT_MUTE, true)
		key.position = Vector2(size.x - 34, 16)
		_content.add_child(key)
		var short := LS.label(str(u.short), 17, col.lerp(Color.WHITE, 0.15), true)
		short.position = Vector2(20, 88)
		short.size = Vector2(size.x - 40, 24)
		_content.add_child(short)
		var desc := LS.label(str(u.desc), 13, LS.TEXT_DIM)
		desc.position = Vector2(20, 116)
		desc.custom_minimum_size = Vector2(size.x - 40, 0)   # 折り返す幅(大きさだけでは、文字の幅に広がってしまう)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(desc)
		var mx := int(u.max)
		if mx > 1:
			var lt := LS.label("%d → %d 段" % [lvl, lvl + 1], 12, col, true)
			lt.position = Vector2(size.x - 92, size.y - 32)
			lt.size = Vector2(72, 18)
			lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_content.add_child(lt)

	func _gui_input(event: InputEvent) -> void:
		if enabled and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			picked.emit()

	func _process(delta: float) -> void:
		_t += delta
		var to := _hover_to if enabled else 0.0
		_hover += (to - _hover) * (1.0 - exp(-delta * 12.0))
		flash = maxf(flash - delta * 2.2, 0.0)
		if _content != null:
			_content.position.y = -8.0 * _hover
		queue_redraw()

	func _draw() -> void:
		var oy := -8.0 * _hover
		var r := Rect2(0, oy, size.x, size.y)
		var sb := LS.box(Color(0.05 + col.r * 0.06 * _hover, 0.045 + col.g * 0.06 * _hover, 0.08 + col.b * 0.06 * _hover, 0.94),
			Color(col.r, col.g, col.b, 0.35 + 0.6 * _hover), 2, 16)
		sb.shadow_color = Color(col.r, col.g, col.b, 0.32 * _hover)
		sb.shadow_size = int(18.0 * _hover)
		draw_style_box(sb, r)
		draw_rect(Rect2(18, oy + 1, size.x - 36, 3), Color(col.r, col.g, col.b, 0.85))   # 上の色の線
		if bool(u.get("rare", false)):   # レア: 上の縁を、金色の光がゆっくり流れる
			var x := fmod(_t * 0.5, 1.4) / 1.4 * (size.x + 120.0) - 60.0
			for k in range(6):
				draw_rect(Rect2(clampf(x - k * 10.0, 18.0, size.x - 18.0), oy + 1, 10, 3), Color(1, 1, 1, 0.5 * (1.0 - k / 6.0)))
		var c := Vector2(46, oy + 46)   # 絵の入った円
		draw_circle(c, 27.0, Color(col.r, col.g, col.b, 0.14 + 0.08 * _hover))
		draw_arc(c, 27.0, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.75), 2.0, true)
		LI.draw_icon(self, str(u.icon), c, 14.0, col, 2.2)
		var mx := int(u.max)
		if mx > 1:   # 段の印: 済んだ段 / 選ぶと増える段(ゆっくり明滅しない、明るい枠)/ まだの段
			for k in range(mx):
				var pr := Rect2(20 + k * 34, oy + size.y - 28, 28, 8)
				if k < lvl:
					draw_style_box(LS.box(col, Color(0, 0, 0, 0), 0, 4), pr)
				elif k == lvl:
					draw_style_box(LS.box(Color(col.r, col.g, col.b, 0.35 + 0.35 * _hover), col.lerp(Color.WHITE, 0.4), 1, 4), pr)
				else:
					draw_style_box(LS.box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.22), 1, 4), pr)
		if flash > 0.0:
			draw_style_box(LS.box(Color(1, 1, 1, 0.55 * flash), Color(0, 0, 0, 0), 0, 16), r)
