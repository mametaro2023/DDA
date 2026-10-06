extends "res://scripts/ui/lazer/lazer_screen.gd"
## サバイバルの曲の間(docs/survival_plan.md の §1)。上から順に:
##   結果の札(曲名・Lv・その曲の点 × f = 加わった点。合計点が数え上がる)→ ゲージの回復(バーが伸びる)
##   → 強化の 3 択(選べる回数ぶん。ゲームは止まっているので、時間の制限はない)→ NEXT の札(次の曲。用意ができたら、少し見せて go_requested)。
## 進行は main が持つ: 3 択が済んだら choices_done を出し、main が次の曲を選んで show_next、用意ができたら set_ready を呼ぶ。
## 1 曲目の前は、結果の札も 3 択もなく、NEXT の札だけ。
## 札は出し直さない(文字だけ変える。ちらつかせない)。演出は必ず最後まで出す。
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

const NEXT_SHOW := 2.2        # NEXT の札を見せる最短の秒(用意ができてから、少なくとも NEXT_READY 秒)
const NEXT_READY := 1.0
const CARD_W := 300.0
const CARD_H := 196.0
const CARD_GAP := 24.0
const CHOICE_Y := 352.0
const GROUP_COLOR := {"def": LazerStyle.BLUE, "bet": LazerStyle.RED, "atk": LazerStyle.PINK}

var kind := "survival_break"
var run                         # SurvivalRun
var last: Dictionary = {}       # 終えた曲の記録(SurvivalRun.song_done の戻り値)。1 曲目の前は空
var gauge_from := 1.0           # 曲が終わったときのゲージ
var _bg_tex: Texture2D
var _music: AudioStreamPlayer

var _total_l: Label
var _total_from := 0.0
var _total_to := 0.0
var _total_t := -1.0
var _gauge_bar: Control
var _gauge_shown := 1.0
var _gauge_l: Label
var _choice_box: Control
var _choice_ids: Array = []
var _choice_cards: Array = []
var _choosing := false          # 札を選べる間
var _choices_left := 0
var _next_card: Control
var _next_title: Label
var _next_sub: Label
var _next_lv: Label
var _next_status: Label
var _next_bar: ColorRect
var _next_t := -1.0             # NEXT の札を出してからの秒(-1 = まだ)
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
	_build_toolbar(["サバイバル", "%d 曲目" % run.next_no()])
	_build_footer()
	var gu := _footer_button("あきらめる", Color(0.3, 0.28, 0.38), "x", 0, 220, _ask_give_up, LazerStyle.TEXT)
	gu.set_meta("juice_sound", "back")
	if _music != null:   # クリアした曲は流れたまま来るので、ゆっくり消す
		add_child(_music)
		var t := _music.create_tween()
		t.tween_property(_music, "volume_db", -40.0, 1.8)
		t.tween_callback(_music.stop)
	_build_header()
	_build_next_card()
	if last.is_empty():
		_after_choices.call_deferred()
		return
	_build_result()
	_build_choice_area()
	var delay := 1.25 if UiStyle.animate else 0.0
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_inside_tree():
		return
	_choices_left = int(run.picks)
	if _choices_left > 0:
		_roll()
	else:
		_after_choices()


func _exit_tree() -> void:
	if _music != null and _music.playing:
		_music.stop()


# --- 見出し ---

func _build_header() -> void:
	var head := LazerStyle.label("SURVIVAL", 14, LazerStyle.GREEN, true)
	head.position = Vector2(0, 54)
	head.size = Vector2(1280, 20)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(head)
	var t := "%d 曲目 クリア" % (run.next_no() - 1) if not last.is_empty() else "1 曲目"
	var title := LazerStyle.label(t, 30, LazerStyle.TEXT, true)
	title.position = Vector2(0, 72)
	title.size = Vector2(1280, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	UiStyle.pop_in(title, 0.0, Vector2(0, -12), 0.4)


# --- 結果の札 ---

func _build_result() -> void:
	var card := Control.new()
	_place(card, 240, 124, 800, 186)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.draw.connect(func():
		card.draw_style_box(LazerStyle.box(Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.9), Color(1, 1, 1, 0.08), 1, 16), Rect2(Vector2.ZERO, card.size)))
	var v := VBoxContainer.new()
	v.position = Vector2(28, 16)
	v.size = Vector2(744, 154)
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var lv := float(last.level)
	row.add_child(LazerStyle.pill("Lv %.2f" % lv, LazerStyle.level_color(lv), 14))
	var name_l := LazerStyle.label(LazerStyle.fit(LazerStyle.font_bold(), str(last.title), 18, 600.0), 18, LazerStyle.TEXT, true)
	row.add_child(name_l)
	var calc := LazerStyle.label("曲の点 %s  ×  f %.2f  =  + %s" % [UiStyle.fmt(int(round(float(last.score)))), float(last.f), UiStyle.fmt(int(round(float(last.points))))], 17, LazerStyle.TEXT_DIM)
	v.add_child(calc)
	var tot_row := HBoxContainer.new()
	tot_row.add_theme_constant_override("separation", 14)
	v.add_child(tot_row)
	var cap := LazerStyle.label("TOTAL", 13, LazerStyle.TEXT_MUTE)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tot_row.add_child(cap)
	_total_to = float(run.total)
	_total_from = _total_to - float(last.points)
	_total_l = LazerStyle.label(UiStyle.fmt(int(round(_total_from))), 40, LazerStyle.YELLOW, true)
	tot_row.add_child(_total_l)
	_total_t = 0.0 if UiStyle.animate else 99.0
	# ゲージ: 曲が終わったときから、曲の間の回復のぶんだけ伸びる
	var g_row := HBoxContainer.new()
	g_row.add_theme_constant_override("separation", 12)
	v.add_child(g_row)
	var gcap := LazerStyle.label("ゲージ", 13, LazerStyle.TEXT_MUTE)
	gcap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g_row.add_child(gcap)
	_gauge_bar = Control.new()
	_gauge_bar.custom_minimum_size = Vector2(460, 18)
	_gauge_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gauge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_bar.draw.connect(_draw_gauge)
	g_row.add_child(_gauge_bar)
	_gauge_l = LazerStyle.label("", 15, LazerStyle.TEXT_DIM, true)
	g_row.add_child(_gauge_l)
	_gauge_shown = gauge_from
	_set_gauge_text()
	UiStyle.tween(self, "_gauge_shown", gauge_from, float(run.gauge), 0.7, 0.75, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	UiStyle.pop_in(card, 0.08, Vector2(0, 18), 0.45)


func _set_gauge_text() -> void:
	if _gauge_l != null:
		_gauge_l.text = "%d%%  →  %d%%" % [int(round(gauge_from * 100.0)), int(round(float(run.gauge) * 100.0))]


func _draw_gauge() -> void:
	var w := _gauge_bar.size.x
	var h := _gauge_bar.size.y
	_gauge_bar.draw_style_box(LazerStyle.box(Color(0.03, 0.025, 0.06, 0.8), Color(1, 1, 1, 0.16), 1, 9), Rect2(0, 0, w, h))
	var gain_w := w * clampf(_gauge_shown, 0.0, 1.0)
	var base_w := w * clampf(gauge_from, 0.0, 1.0)
	if gain_w > base_w + 0.5:   # 回復したぶん(明るく)
		_gauge_bar.draw_style_box(LazerStyle.box(Color(0.55, 1.0, 0.75, 0.85), Color(0, 0, 0, 0), 0, maxi(int(minf(h * 0.5, gain_w * 0.5)), 1)), Rect2(2, 2, gain_w - 4.0, h - 4.0))
	if base_w > 4.0:
		_gauge_bar.draw_style_box(LazerStyle.box(UiStyle.hp_color(gauge_from), Color(0, 0, 0, 0), 0, maxi(int(minf(h * 0.5, base_w * 0.5)), 1)), Rect2(2, 2, base_w - 4.0, h - 4.0))


func _process(delta: float) -> void:
	super._process(delta)
	if _total_t >= 0.0 and _total_l != null:
		_total_t += delta
		var x := clampf((_total_t - 0.45) / 1.0, 0.0, 1.0)
		x = 1.0 - pow(1.0 - x, 3.0)
		_total_l.text = UiStyle.fmt(int(round(lerpf(_total_from, _total_to, x))))
		if x >= 1.0:
			_total_t = -1.0
	if _gauge_bar != null:
		_gauge_bar.queue_redraw()
	if _next_t >= 0.0:
		_next_t += delta
		if _ready_t >= 0.0:
			_ready_t += delta
			var need := maxf(NEXT_SHOW - (_next_t - _ready_t), NEXT_READY)   # 札を出してから NEXT_SHOW 秒、用意ができてから NEXT_READY 秒の、遅いほう
			var k := clampf(_ready_t / need, 0.0, 1.0)
			_next_bar.size.x = 560.0 * k
			if k >= 1.0 and not _went and _confirm == null and _options == null:
				_went = true
				go_requested.emit()


# --- 強化の 3 択 ---

func _build_choice_area() -> void:
	_choice_box = Control.new()
	_place(_choice_box, 0, CHOICE_Y, 1280, CARD_H + 60)
	_choice_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := LazerStyle.label("強化を 1 つ選ぶ(1 / 2 / 3)", 15, LazerStyle.TEXT_DIM, true)
	cap.name = "Caption"
	cap.position = Vector2(0, 0)
	cap.size = Vector2(1280, 22)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choice_box.add_child(cap)


## 3 択を引いて、札を並べる。
func _roll() -> void:
	for c in _choice_cards:
		c.queue_free()
	_choice_cards.clear()
	_choice_ids = run.roll_choices(3)
	if _choice_ids.is_empty():
		_after_choices()
		return
	var cap: Label = _choice_box.get_node("Caption")
	cap.text = "強化を 1 つ選ぶ(1 / 2 / 3)" + ("   あと %d 回" % _choices_left if _choices_left > 1 else "")
	var n := _choice_ids.size()
	var x0 := (1280.0 - (CARD_W * n + CARD_GAP * (n - 1))) * 0.5
	for i in range(n):
		var c := _make_card(str(_choice_ids[i]), i)
		c.position = Vector2(x0 + i * (CARD_W + CARD_GAP), 34)
		c.size = Vector2(CARD_W, CARD_H)
		_choice_box.add_child(c)
		_choice_cards.append(c)
		UiStyle.pop_in(c, 0.05 + 0.06 * i, Vector2(0, 20), 0.4)
	_choosing = true
	UiSfx.play("open")


func _make_card(id: String, i: int) -> Button:
	var u := Upgrades.find(id)
	var col: Color = u.color
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", LazerStyle.box(Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.92), Color(col.r, col.g, col.b, 0.35), 2, 16))
	b.add_theme_stylebox_override("hover", LazerStyle.box(Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 0.95), Color(col.r, col.g, col.b, 0.95), 2, 16))
	b.add_theme_stylebox_override("pressed", LazerStyle.box(Color(col.r * 0.35, col.g * 0.35, col.b * 0.35, 0.95), col, 2, 16))
	b.add_theme_stylebox_override("hover_pressed", b.get_theme_stylebox("pressed"))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func(): _choose(i))
	var v := VBoxContainer.new()
	v.position = Vector2(20, 16)
	v.size = Vector2(CARD_W - 40, CARD_H - 32)
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var icon := LazerIcons.new(str(u.icon), col, 26.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(icon)
	top.add_child(LazerStyle.label(str(u.name), 21, LazerStyle.TEXT, true))
	var key := LazerStyle.label(str(i + 1), 14, LazerStyle.TEXT_MUTE, true)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(key)
	var tag := LazerStyle.label({"def": "守り", "bet": "賭け", "atk": "攻撃"}.get(str(u.group), ""), 12, GROUP_COLOR.get(str(u.group), LazerStyle.TEXT_MUTE), true)
	v.add_child(tag)
	v.add_child(LazerStyle.label(str(u.short), 17, col, true))
	var desc := LazerStyle.label(str(u.desc), 13, LazerStyle.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(CARD_W - 40, 0)
	v.add_child(desc)
	var mx := int(u.max)
	if mx > 1:   # 段の印(いまの段 → 選ぶと 1 つ増える)
		var lvl: int = run.level_of(id)
		var pips := "".join(range(mx).map(func(k): return "●" if k < lvl else ("◉" if k == lvl else "○")))
		v.add_child(LazerStyle.label("%s   %d → %d 段" % [pips, lvl, lvl + 1], 13, col))
	return b


func _choose(i: int) -> void:
	if not _choosing or i < 0 or i >= _choice_ids.size() or _confirm != null:
		return
	_choosing = false
	var id := str(_choice_ids[i])
	run.choose(id)
	_choices_left = int(run.picks)
	UiSfx.play("confirm")
	var card: Control = _choice_cards[i]
	var at := card.get_global_rect().get_center()
	var col: Color = Upgrades.find(id).color
	UiFx.ring(self, at, col, 30.0, 220.0, 0.55, 3.0)
	UiFx.burst(self, at, col, 16, 260.0, 0.55, 3.0)
	for k in range(_choice_cards.size()):
		if k != i:
			UiStyle.tween(_choice_cards[k], "modulate:a", 1.0, 0.0, 0.25)
	card.pivot_offset = card.size * 0.5
	UiStyle.spring(card, "scale", Vector2(1.06, 1.06), Vector2.ONE, 0.4)
	if UiStyle.animate:
		await get_tree().create_timer(0.6).timeout
	if not is_inside_tree():
		return
	if _choices_left > 0:
		_roll()
	else:
		UiStyle.tween(_choice_box, "modulate:a", 1.0, 0.0, 0.25)
		if UiStyle.animate:
			await get_tree().create_timer(0.25).timeout
		_choice_box.visible = false
		_after_choices()


func _after_choices() -> void:
	if not is_inside_tree():
		return
	choices_done.emit()


# --- NEXT の札 ---

func _build_next_card() -> void:
	_next_card = Control.new()
	_place(_next_card, 300, CHOICE_Y + 20, 680, 220)
	_next_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_next_card.visible = false
	_next_card.draw.connect(func():
		_next_card.draw_style_box(LazerStyle.box(Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.92), Color(LazerStyle.GREEN.r, LazerStyle.GREEN.g, LazerStyle.GREEN.b, 0.6), 2, 18), Rect2(Vector2.ZERO, _next_card.size)))
	var v := VBoxContainer.new()
	v.position = Vector2(60, 22)
	v.size = Vector2(560, 180)
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_next_card.add_child(v)
	var nx := LazerStyle.label("NEXT", 15, LazerStyle.GREEN, true)
	v.add_child(nx)
	_next_title = LazerStyle.label("", 28, LazerStyle.TEXT, true)
	v.add_child(_next_title)
	_next_sub = LazerStyle.label("", 16, LazerStyle.TEXT_DIM)
	v.add_child(_next_sub)
	_next_lv = LazerStyle.label("", 18, LazerStyle.TEXT, true)
	v.add_child(_next_lv)
	_next_status = LazerStyle.label("", 13, LazerStyle.TEXT_MUTE)
	v.add_child(_next_status)
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.1)
	track.custom_minimum_size = Vector2(560, 4)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(track)
	_next_bar = ColorRect.new()
	_next_bar.color = LazerStyle.GREEN
	_next_bar.size = Vector2(0, 4)
	_next_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_next_bar)


## 次の曲を出す(main が、選んだら呼ぶ。読めなくて選び直したときも、同じ札の文字だけを変える)。
## info: {title, artist, version, est(見積もりの Lv), extra_mods}
func show_next(info: Dictionary) -> void:
	var first_show := not _next_card.visible
	_next_card.visible = true
	_next_title.text = LazerStyle.fit(LazerStyle.font_bold(), str(info.get("title", "")), 28, 560.0)
	_next_sub.text = LazerStyle.fit(LazerStyle.font(), "%s  ・  [%s]" % [str(info.get("artist", "")), str(info.get("version", ""))], 16, 560.0)
	var est := float(info.get("est", 0.0))
	var extra: Array = info.get("extra_mods", [])
	var lv_text := "Lv %.2f くらい   × %.2f くらい" % [est, SurvivalRun.f_of(est)]
	if not extra.is_empty():
		lv_text += "   (もう一度: %s)" % Mods.names(extra)
	_next_lv.text = lv_text
	_next_lv.add_theme_color_override("font_color", LazerStyle.level_color(est))
	_next_status.text = "用意しています…"
	_ready_t = -1.0
	_next_bar.size.x = 0.0
	if first_show:
		_next_t = 0.0
		UiStyle.pop_in(_next_card, 0.0, Vector2(0, 18), 0.4)
		UiSfx.play("whoosh")


## 次の曲の用意ができた。level: MOD 込みの Lv(測り直したもの)/ tex: 次の曲の背景
func set_ready(level: float, tex: Texture2D) -> void:
	_next_lv.text = "Lv %.2f   × %.2f" % [level, SurvivalRun.f_of(level)]
	_next_lv.add_theme_color_override("font_color", LazerStyle.level_color(level))
	_next_status.text = "まもなく始まります"
	if tex != null:
		set_background(tex)
	_ready_t = 0.0


## 用意できなかった(曲を選び直せないとき)。
func show_error(msg: String) -> void:
	_next_status.text = msg


# --- あきらめる ---

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
		KEY_ESCAPE:
			_ask_give_up()
		_:
			return
	get_viewport().set_input_as_handled()
