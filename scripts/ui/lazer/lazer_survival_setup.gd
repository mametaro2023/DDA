extends "res://scripts/ui/lazer/lazer_screen.gd"
## サバイバルの準備画面(タイトルの「サバイバル」から開く)。遊び方の要点・開始の Lv(2 / 4 / 6)・MOD・自己ベスト・使える曲の数を出し、
## 「はじめる」で start_requested を出す(main が、1 曲目を選んで始める)。docs/survival_plan.md の §1。
## 曲の一覧は SongBrowser(選曲と同じ。同じ曲は 1 つにまとまる)で作り、曲の統計(Lv)がまだない曲は、裏で用意する(SongBrowser.start_prep)。
## 統計のある譜面の一覧(SurvivalPicker.read_charts)は、別スレッドで少しずつ読む。MOD は選曲の MOD とは別に覚える(settings.survival_mods)。
## 操作: ← → で開始の Lv、Enter ではじめる、Esc でタイトルへ。

signal start_requested(start_level: float, mod_ids: Array, charts: Array)
signal back_requested

const SongBrowser = preload("res://scripts/song_browser.gd")
const SurvivalRun = preload("res://scripts/survival/survival_run.gd")
const SurvivalPicker = preload("res://scripts/survival/survival_picker.gd")
const SurvivalRecords = preload("res://scripts/survival/survival_records.gd")
const Mods = preload("res://scripts/mods.gd")
const Settings = preload("res://scripts/settings.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const AttractBackdrop = preload("res://scripts/attract_backdrop.gd")
const UiSets = preload("res://scripts/ui/ui_sets.gd")

const PANEL_X := 190.0
const PANEL_Y := 66.0
const PANEL_W := 900.0
const PANEL_H := 582.0
const LV_COLORS := [LazerStyle.GREEN, LazerStyle.YELLOW, LazerStyle.RED]

var kind := "survival_setup"
var browser
var _charts: Array = []          # 統計のある譜面の一覧(SurvivalPicker.read_charts)
var _got := {}                   # 統計を読めた曲(path → true)
var _v2 := true                  # いまの一覧が、弾幕 v2 の統計か
var _reading := false
var _dirty := true               # 読んでいない曲があるかもしれない
var _read_t := 0.0
var _gen := 0                    # 読み直しの世代(MOD で弾幕の作り方が変わったら、前の結果は捨てる)
var _start_lv := 4.0
var _mods: Array = []
var _lv_btns: Array = []
var _mods_row: HBoxContainer
var _count_l: Label
var _prep_l: Label
var _start_btn: Button
var _mod_panel: Control
var _options: Control
var _leaving := false


func _ready() -> void:
	settings = Settings.load_all()
	_start_lv = float(settings.get("survival_start", 4.0))
	if not SurvivalRun.START_LEVELS.has(_start_lv):
		_start_lv = 4.0
	_mods = SurvivalRun.clean_mods(settings.get("survival_mods", []))
	_v2 = bool(Mods.params(_mods).gen_v2)
	_build_base()
	_build_toolbar(["ホーム", "サバイバル"])
	_build_panel()
	_build_footer()
	var back := _footer_button("戻る", LazerStyle.PINK, "back", 0, 200, _back)
	back.set_meta("juice_sound", "back")
	_start_btn = _footer_button("はじめる", LazerStyle.GREEN, "play", 1280.0 - 250.0, 250, _start, Color(0.08, 0.18, 0.02))
	_start_btn.emphasized = true
	browser = SongBrowser.new()
	browser.settings = settings
	browser.scan()
	browser.start_prep(_v2)
	_read_more()
	AttractBackdrop.pick_async("", func(r: Dictionary):
		if not r.is_empty() and is_inside_tree() and not _leaving:
			set_background(r.tex))
	UiStyle.pop_in(_panel_node, 0.05, Vector2(0, 24), 0.45)


func _exit_tree() -> void:
	SongBrowser.stop_prep()
	if browser != null:
		browser.close()


# --- 中身 ---

var _panel_node: Control


func _build_panel() -> void:
	var p := Control.new()
	_panel_node = p
	_place(p, PANEL_X, PANEL_Y, PANEL_W, PANEL_H)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.draw.connect(func():
		p.draw_style_box(LazerStyle.box(Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.9), Color(LazerStyle.GREEN.r, LazerStyle.GREEN.g, LazerStyle.GREEN.b, 0.45), 2, 18), Rect2(Vector2.ZERO, p.size)))
	var v := VBoxContainer.new()
	v.position = Vector2(40, 28)
	v.size = Vector2(PANEL_W - 80, PANEL_H - 56)
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	v.add_child(LazerStyle.label("SURVIVAL", 40, LazerStyle.GREEN, true))
	v.add_child(LazerStyle.label("曲をつないで、倒れるまで遊ぶ", 18, LazerStyle.TEXT_DIM))
	var rules := VBoxContainer.new()
	rules.add_theme_constant_override("separation", 3)
	rules.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for line in [
		"・曲は自動で選ばれます。1 曲ごとに目標の Lv が %.1f 上がります" % SurvivalRun.LV_STEP,
		"・ゲージは次の曲へ持ち越し、曲の間に %d%% 回復します" % int(round(SurvivalRun.BETWEEN_HEAL * 100.0)),
		"・曲を終えるごとに、3 つの強化から 1 つを選びます",
		"・スコア = Σ(曲の点 × (Lv / %d)²)。倒れた曲も、そこまでの点が入ります" % int(SurvivalRun.F_REF),
	]:
		rules.add_child(LazerStyle.label(line, 15, LazerStyle.TEXT_DIM))
	v.add_child(rules)
	v.add_child(_gap(6))
	# 開始の Lv
	v.add_child(LazerStyle.label("開始の Lv", 13, LazerStyle.TEXT_MUTE))
	var lv_row := HBoxContainer.new()
	lv_row.add_theme_constant_override("separation", 6)
	v.add_child(lv_row)
	for i in range(SurvivalRun.START_LEVELS.size()):
		var lv: float = SurvivalRun.START_LEVELS[i]
		var b := LazerButton.new("Lv %d から" % int(lv), LV_COLORS[i], "", LazerStyle.ink_on(LV_COLORS[i]))
		b.custom_minimum_size = Vector2(170, 46)
		b.font_size = 17
		b.pressed.connect(func(): _set_level(lv, true))
		lv_row.add_child(b)
		_lv_btns.append(b)
	_restyle_levels()
	v.add_child(_gap(4))
	# MOD
	v.add_child(LazerStyle.label("MOD(選曲の MOD とは別。練習・撃破は付けられません)", 13, LazerStyle.TEXT_MUTE))
	var mod_line := HBoxContainer.new()
	mod_line.add_theme_constant_override("separation", 12)
	v.add_child(mod_line)
	var mb := LazerButton.new("MOD を選ぶ", LazerStyle.PURPLE, "mods", Color(0.1, 0.04, 0.22))
	mb.custom_minimum_size = Vector2(180, 40)
	mb.font_size = 15
	mb.pressed.connect(_open_mods)
	mod_line.add_child(mb)
	_mods_row = HBoxContainer.new()
	_mods_row.add_theme_constant_override("separation", 6)
	_mods_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_mods_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mod_line.add_child(_mods_row)
	_refresh_mods()
	v.add_child(_gap(4))
	# 使える曲の数と、自己ベスト
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 40)
	v.add_child(info)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 2)
	left.custom_minimum_size = Vector2(380, 0)
	info.add_child(left)
	left.add_child(LazerStyle.label("使える曲", 13, LazerStyle.TEXT_MUTE))
	_count_l = LazerStyle.label("調べています…", 20, LazerStyle.TEXT, true)
	left.add_child(_count_l)
	_prep_l = LazerStyle.label("", 13, LazerStyle.TEXT_MUTE)
	left.add_child(_prep_l)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	info.add_child(right)
	right.add_child(LazerStyle.label("自己ベスト", 13, LazerStyle.TEXT_MUTE))
	var best := SurvivalRecords.best()
	if best.is_empty():
		right.add_child(LazerStyle.label("まだありません", 20, LazerStyle.TEXT_DIM, true))
	else:
		right.add_child(LazerStyle.label(UiStyle.fmt(int(round(float(best.total)))), 26, LazerStyle.YELLOW, true))
		right.add_child(LazerStyle.label("%d 曲クリア ・ Lv %.2f まで ・ 開始 Lv %d" % [int(best.cleared), float(best.best_level), int(best.start_level)], 13, LazerStyle.TEXT_DIM))


func _gap(h: float) -> Control:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, h)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


func _set_level(lv: float, sound: bool) -> void:
	if _leaving or is_equal_approx(lv, _start_lv):
		return
	_start_lv = lv
	if sound:
		UiSfx.play("select", 1.0 + 0.1 * SurvivalRun.START_LEVELS.find(lv))
	_restyle_levels()


func _restyle_levels() -> void:
	for i in range(_lv_btns.size()):
		(_lv_btns[i] as LazerButton).emphasized = is_equal_approx(float(SurvivalRun.START_LEVELS[i]), _start_lv)
		_lv_btns[i].modulate.a = 1.0 if _lv_btns[i].emphasized else 0.55


func _refresh_mods() -> void:
	for c in _mods_row.get_children():
		c.queue_free()
	var p := Mods.params(_mods)
	if p.ids.is_empty():
		_mods_row.add_child(LazerStyle.label("なし", 15, LazerStyle.TEXT_MUTE))
		return
	for id in p.ids:
		var m := Mods.find(id)
		var c: Color = m.color
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", LazerStyle.box(Color(c.r, c.g, c.b, 0.22), Color(c.r, c.g, c.b, 0.8), 1, 12, 10, 2))
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(LazerStyle.label(str(m.name), 14, c))
		_mods_row.add_child(chip)


# --- MOD のパネル ---

var _mod_settings := {}


func _open_mods() -> void:
	if _mod_panel != null or _options != null or _leaving:
		return
	_mod_settings = settings.duplicate()
	_mod_settings["mods"] = _mods.duplicate()
	var p = UiSets.current().make_mods()
	p.multi = true   # ひとり用の MOD(撃破)は出さない
	p.setup(_mod_settings, func() -> float: return -1.0)
	p.changed.connect(_on_mods_changed)
	p.closed.connect(func():
		if _mod_panel != null:
			_mod_panel.queue_free()
			_mod_panel = null)
	_mod_panel = p
	add_child(p)


func _on_mods_changed() -> void:
	_mods = SurvivalRun.clean_mods(_mod_settings.get("mods", []))
	settings["survival_mods"] = _mods.duplicate()
	Settings.save_all(settings)
	_refresh_mods()
	var v2 := bool(Mods.params(_mods).gen_v2)
	if v2 != _v2:   # 弾幕の作り方(v1 / v2)が変わった: 統計が別なので、読み直す
		_v2 = v2
		_gen += 1
		_charts = []
		_got = {}
		_reading = false
		_dirty = true
		browser.start_prep(_v2)
	_update_count()


# --- 曲の一覧 ---

func _process(delta: float) -> void:
	super._process(delta)
	if browser == null:
		return
	var r: Dictionary = browser.pump(3000)
	if bool(r.added) or bool(r.prepped):
		_dirty = true
	_read_t += delta
	if _read_t >= 1.0:
		_read_t = 0.0
		if (bool(r.added) or _dirty) and not _reading:
			_read_more()
		browser.start_prep(_v2)   # 曲が増えたときのために、ときどき確かめる(動いていれば何もしない)
		_update_prep()


## 統計をまだ読んでいない曲を、別スレッドで読む。
func _read_more() -> void:
	if _reading:
		return
	var todo: Array = []
	for sg in browser.songs:
		if not _got.has(str(sg.path)):
			todo.append({"path": str(sg.path)})
	_dirty = false
	if todo.is_empty():
		_update_count()
		return
	_reading = true
	var gen := _gen
	var v2 := _v2
	var me: WeakRef = weakref(self)
	WorkerThreadPool.add_task(func():
		var got := {}
		var charts := SurvivalPicker.read_charts(todo, v2, got)
		var target: Object = me.get_ref()
		if target != null:
			target._on_read.call_deferred(gen, charts, got))


func _on_read(gen: int, charts: Array, got: Dictionary) -> void:
	if gen != _gen:
		return
	_reading = false
	_charts.append_array(charts)
	_got.merge(got)
	_update_count()
	_update_prep()


func _update_count() -> void:
	if _count_l == null:
		return
	if _charts.is_empty():
		_count_l.text = "まだありません" if not _reading else "調べています…"
	else:
		_count_l.text = "%d 曲(譜面 %d)" % [SurvivalPicker.song_count(_charts), _charts.size()]
	_start_btn.modulate.a = 1.0 if not _charts.is_empty() else 0.45


func _update_prep() -> void:
	var pp: Dictionary = SongBrowser.prep_progress()
	var op: Dictionary = SongBrowser.osu_progress()
	var parts: Array = []
	if bool(op.running):
		parts.append("osu! の曲を探しています(%d / %d)" % [int(op.done), int(op.total)])
	if bool(pp.running):
		parts.append("曲の難易度を調べています(%d / %d)" % [int(pp.done), int(pp.total)])
	elif browser != null and _got.size() < browser.songs.size() and not _reading:
		parts.append("難易度の分からない曲: %d" % (browser.songs.size() - _got.size()))
	_prep_l.text = "  ".join(parts)


# --- 操作 ---

func _start() -> void:
	if _leaving or _mod_panel != null:
		return
	if _charts.is_empty():
		UiSfx.play("deny")
		return
	_leaving = true
	UiSfx.play("confirm")
	settings["survival_start"] = _start_lv
	settings["survival_mods"] = _mods.duplicate()
	Settings.save_all(settings)
	start_requested.emit(_start_lv, _mods.duplicate(), _charts)


func _back() -> void:
	if _leaving:
		return
	_leaving = true
	back_requested.emit()


## main が設定パネルを開いた・閉じた(ui_set.gd の契約)
func on_overlay(open: bool, panel: Control = null) -> void:
	_options = panel if open else null


func _unhandled_key_input(event: InputEvent) -> void:
	if _mod_panel != null or _options != null or _leaving or not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_LEFT, KEY_RIGHT:
			var i: int = SurvivalRun.START_LEVELS.find(_start_lv)
			i = clampi(i + (-1 if event.keycode == KEY_LEFT else 1), 0, SurvivalRun.START_LEVELS.size() - 1)
			_set_level(float(SurvivalRun.START_LEVELS[i]), true)
		KEY_ENTER, KEY_KP_ENTER:
			_start()
		KEY_ESCAPE:
			UiSfx.play("back")
			_back()
		_:
			return
	get_viewport().set_input_as_handled()
