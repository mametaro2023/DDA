extends Control
## リザルト画面。左に大きなランク(ゲームオーバーなら到達度)、右にスコア(カウントアップ)と内訳・成績。

signal menu_requested
signal retry_requested

const Mods = preload("res://scripts/mods.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Ambient = preload("res://scripts/ui/ambient.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")

## スコア表示の ease-out(1/RATE 秒ほどで大半が追いつく。プレイ画面の表示と同じ考え方)
const COUNT_RATE := 3.5

var stats: Dictionary

var _score_l: Label
var _t := 0.0                    # 開いてからの経過秒(スコアのカウントアップの開始を遅らせる)
var _counters: Array = []         # 数字のカウントアップ: [Label, 目標値, 接尾辞]
var _score_target := 0.0
var _score_disp := 0.0


func setup(p_stats: Dictionary) -> void:
	stats = p_stats


func _ready() -> void:
	theme = UiStyle.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiStyle.backdrop(self)
	# 曲の背景画像(プレイ画面と同じ暗さ。クリアのフェードアウトのあと、同じ背景のまま結果が現れる)
	var bg_tex = stats.get("bg")
	if bg_tex is Texture2D:
		var tr := TextureRect.new()
		tr.texture = bg_tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.modulate = Color(0.28, 0.28, 0.32)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
	var amb := Ambient.new()
	amb.strength = 0.8
	add_child(amb)

	var failed: bool = stats.failed
	# クリアしたときだけスコアが残る。ランクは、ノーミスなら SS、それ以外は達成率(スコア ÷ ベーススコア)で S〜F
	var score: int = int(round(stats.score))   # プレイ中の表示(四捨五入)と同じにする。切り捨てだと 1 ずれる
	var rank := GameSim.rank_of(failed, int(stats.hits), float(stats.score), float(stats.get("score_base", 1000000.0)))
	var accent := UiStyle.DANGER if failed else UiStyle.rank_color(rank)

	# --- 左: ランク / 到達度 ---
	var left := Control.new()
	left.position = Vector2(90, 110)
	left.size = Vector2(420, 480)
	add_child(left)
	var lp := PanelContainer.new()
	lp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lp.add_theme_stylebox_override("panel", UiStyle.box(Color(accent.r, accent.g, accent.b, 0.05), Color(accent.r, accent.g, accent.b, 0.35), 1, 8))
	left.add_child(lp)
	var lv := VBoxContainer.new()
	lv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	lv.add_theme_constant_override("separation", 0)
	left.add_child(lv)
	lv.add_child(_centered(UiStyle.label("GAME OVER" if failed else "CLEAR", 26, accent, true)))
	lv.add_child(_gap(6))
	var big: Label
	if failed:
		big = UiStyle.label("%d%%" % int(round(stats.progress * 100.0)), 140, accent, true)
		lv.add_child(_centered(big))
		lv.add_child(_centered(UiStyle.label("到達", 18, UiStyle.TEXT_DIM)))
		_counters.append([big, int(round(stats.progress * 100.0)), "%", 0.3, 0.9])
	else:
		big = UiStyle.label(rank, 220, accent, true)
		lv.add_child(_centered(big))
		lv.add_child(_centered(UiStyle.label("RANK", 16, UiStyle.TEXT_DIM)))

	# 左パネルは左から滑り込み、ランク文字は弾んで現れる
	UiStyle.pop_in(left, 0.05, Vector2(-40, 0), 0.5)
	if not failed:
		big.pivot_offset = big.get_minimum_size() * 0.5
		UiStyle.tween(big, "scale", Vector2(0.4, 0.4), Vector2.ONE, 0.6, 0.4, Tween.TRANS_BACK)
		UiStyle.tween(big, "modulate:a", 0.0, 1.0, 0.3, 0.4)

	# --- 右: 曲名 / スコア / 内訳 / 成績 ---
	var right := VBoxContainer.new()
	right.position = Vector2(560, 100)
	right.size = Vector2(640, 500)
	right.add_theme_constant_override("separation", 10)
	add_child(right)
	var t := UiStyle.label(stats.title, 18, UiStyle.TEXT_DIM)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	right.add_child(t)
	# Lv・MOD のチップ
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.add_child(UiStyle.chip("Lv %.2f" % stats.level, UiStyle.level_color(stats.level)))
	for id in stats.get("mod_ids", []):
		var m := Mods.find(id)
		if not m.is_empty():
			chips.add_child(UiStyle.chip(m.name, m.color))
	right.add_child(chips)
	right.add_child(_gap(6))

	right.add_child(UiStyle.caption("SCORE"))
	if failed:
		right.add_child(UiStyle.label("---", 72, UiStyle.TEXT_FAINT, true))
	else:
		_score_target = float(score)
		_score_l = UiStyle.label("0", 72, UiStyle.TEXT, true)
		right.add_child(_score_l)
		right.add_child(_gap(4))
		right.add_child(UiStyle.hline())
		right.add_child(_row("ベーススコア", UiStyle.fmt(int(round(stats.get("score_base", 1000000.0)))), _mod_note()))
		right.add_child(_row("グレイズボーナス", "+ " + UiStyle.fmt(int(stats.score_graze)), ""))
		right.add_child(_row("被ダメージ係数", "× %.3f" % stats.damage_factor, ""))
		right.add_child(UiStyle.hline())
	right.add_child(_gap(6))

	# 成績(3 つ並べる)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 40)
	grid.add_child(_stat("GRAZE", int(stats.graze), "", 0.7))
	grid.add_child(_stat("被弾", int(stats.hits), " 回", 0.8))
	grid.add_child(_stat("被弾時間", int(stats.hit_ms), " ms", 0.9))
	right.add_child(grid)

	# 下部のボタン(Enter / R のキーでも同じ操作ができる)
	var hint := HBoxContainer.new()
	hint.add_theme_constant_override("separation", 12)
	hint.position = Vector2(560, 626)
	for spec in [["メニューへ", menu_requested], ["リトライ", retry_requested]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 40)
		var sig: Signal = spec[1]
		b.pressed.connect(func(): sig.emit())
		hint.add_child(b)
	add_child(hint)

	# 右の列は右から滑り込み、中身が上から順に現れ、数字が数え上がる
	UiStyle.pop_in(right, 0.1, Vector2(40, 0), 0.5)
	var j := 0
	for c in right.get_children():
		UiStyle.tween(c, "modulate:a", 0.0, 1.0, 0.35, 0.2 + 0.07 * j)
		j += 1
	UiStyle.tween(hint, "modulate:a", 0.0, 1.0, 0.5, 1.2)
	for c in _counters:
		var lab: Label = c[0]
		var suffix: String = c[2]
		var set_text := func(v: float): lab.text = str(int(round(v))) + suffix
		UiStyle.tween_value(lab, 0.0, float(c[1]), float(c[4]), set_text, float(c[3]))


func _process(delta: float) -> void:
	_t += delta
	if _score_l == null or (UiStyle.animate and _t < 0.55):   # 右の列が現れてから数え始める
		return
	_score_disp += (_score_target - _score_disp) * (1.0 - exp(-delta * COUNT_RATE))
	if absf(_score_target - _score_disp) < 0.5:
		_score_disp = _score_target
	_score_l.text = UiStyle.fmt(int(round(_score_disp)))


## MOD によるベーススコアの倍率の注記(なければ空)。
func _mod_note() -> String:
	var base: float = stats.get("score_base", 1000000.0)
	if absf(base - 1000000.0) < 1.0:
		return ""
	return "MOD  ×%.4f" % (base / 1000000.0)


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _centered(c: Control) -> Control:
	var w := CenterContainer.new()
	w.add_child(c)
	return w


## 内訳の 1 行: 見出し(と注記)を左、値を右に。
func _row(name: String, value: String, note: String) -> Control:
	var h := HBoxContainer.new()
	var l := UiStyle.label(name, 16, UiStyle.TEXT_DIM)
	l.custom_minimum_size = Vector2(190, 0)
	h.add_child(l)
	var n := UiStyle.label(note, 12, UiStyle.TEXT_FAINT)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	var v := UiStyle.label(value, 18, UiStyle.TEXT, true)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.custom_minimum_size = Vector2(190, 0)
	h.add_child(v)
	return h


func _stat(cap: String, value: int, suffix: String, delay: float) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.add_child(UiStyle.caption(cap))
	var l := UiStyle.label(str(value) + suffix, 26, UiStyle.TEXT, true)
	v.add_child(l)
	_counters.append([l, value, suffix, delay, 0.9])
	return v


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE:
				menu_requested.emit()
			KEY_R:
				retry_requested.emit()
