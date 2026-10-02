extends Control
## MOD パネル(難易度選択の画面に重ねる)。付ける MOD を選ぶ。
## settings(選曲画面の設定の辞書)の mods を直接書き換え、変えたら changed を出す。保存は閉じるときに呼び出し側が行う。
## 下には、MOD 適用後の難易度(Lv。色つき)とベーススコアの倍率だけを出す。切り替えるたびに、数字がなめらかに動き、Lv の色も一緒に変わる。

signal changed
signal closed

const Mods = preload("res://scripts/mods.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const ToggleCard = preload("res://scripts/ui/toggle_card.gd")
const SmoothScroll = preload("res://scripts/ui/smooth_scroll.gd")

const EASE_TIME := 0.5   # 数字が動く時間(秒)

var settings: Dictionary
## 選択中の難易度の、MOD 適用後の Lv を返す Callable(-> float。難易度がなければ負の値)
var level_cb: Callable = Callable()

var _lv_l: Label
var _mul_l: Label
var _lv_shown := -1.0     # いま表示している Lv(負 = まだ何も出していない)
var _mul_shown := 1.0
var _lv_tween: Tween
var _mul_tween: Tween
var _dim: ColorRect
var _panel: PanelContainer
var _closing := false
var _cards := {}          # MOD の id → カード
var _clear_btn: Button


func setup(p_settings: Dictionary, p_level_cb: Callable) -> void:
	settings = p_settings
	level_cb = p_level_cb


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.66)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	var panel := PanelContainer.new()
	_panel = panel
	panel.position = Vector2(240, 36)
	panel.size = Vector2(800, 648)
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.LINE, 1, 8, 28, 24))
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var head := HBoxContainer.new()
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 0)
	title_box.add_child(UiStyle.label("MOD", 24, UiStyle.TEXT, true))
	title_box.add_child(UiStyle.caption("難易度とスコアの修飾"))
	head.add_child(title_box)
	head.add_child(UiStyle.close_button(close_panel))   # 右上の ✕(どのパネルも同じ場所)
	v.add_child(head)
	v.add_child(UiStyle.hline())

	# 6 枚が、スクロールなしで入る高さのカード(compact)。万一増えても合計表示が隠れないよう、カード一覧だけをスクロールにしておく
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 120)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	SmoothScroll.attach(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 9)
	scroll.add_child(list)
	var mods: Array = settings.mods
	for m in Mods.ALL:
		var parts: PackedStringArray = (m.desc as String).split(" / ")
		var effects: Array = []
		for p in parts:
			if not p.begins_with("ベーススコア"):
				effects.append(p)
		var pct := int(round((float(m.get("score_mul", 1.0)) - 1.0) * 100.0))
		var card := ToggleCard.make(self, "%s   %s" % [m.name, m.tag], "  /  ".join(effects), m.color, mods.has(m.id), "ベーススコア %+d%%" % pct,
			func(on: bool): _on_toggled(m.id, on), true)
		_cards[m.id] = card
		list.add_child(card)
	v.add_child(UiStyle.hline())
	# 下の段: 左に「すべて解除」、まん中に合計(視線が行く場所)、右下に「閉じる」(主ボタン)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 24)
	v.add_child(foot)
	_clear_btn = Button.new()
	_clear_btn.text = "すべて解除"
	_clear_btn.focus_mode = Control.FOCUS_NONE
	_clear_btn.custom_minimum_size = Vector2(132, 42)
	_clear_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_clear_btn.pressed.connect(_clear_all)
	foot.add_child(_clear_btn)
	var sp_l := Control.new()
	sp_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp_l)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 60)
	foot.add_child(stats)
	_lv_l = UiStyle.label("--", 44, UiStyle.TEXT_FAINT, true)
	stats.add_child(_stat_block("難易度  LV", _lv_l, 130.0))   # "13.37"(114px)が入る幅
	_mul_l = UiStyle.label("×1.0000", 44, UiStyle.TEXT, true)
	stats.add_child(_stat_block("ベーススコア倍率", _mul_l, 190.0))   # "×1.0000"(165px)が入る幅
	var sp_r := Control.new()
	sp_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp_r)
	var done := Button.new()
	done.text = "閉じる"
	done.focus_mode = Control.FOCUS_NONE
	done.custom_minimum_size = Vector2(132, 42)
	done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiStyle.style_primary(done)
	done.pressed.connect(close_panel)
	foot.add_child(done)
	_sync_clear_btn()
	refresh_info(false)
	UiStyle.close_on_outside_click(self, panel, close_panel)

	# 開く動き: 背景が暗くなり、パネルが下からふわっと上がる
	UiSfx.play("open")
	UiStyle.tween(_dim, "color:a", 0.0, 0.66, 0.22)
	UiStyle.pop_scale(panel, 0.93, 0.42)


func _on_toggled(id: String, on: bool) -> void:
	var mods: Array = settings.mods
	if on and not mods.has(id):
		mods.append(id)
	elif not on:
		mods.erase(id)
	settings.mods = mods
	_sync_clear_btn()
	changed.emit()
	refresh_info()


## 付けている MOD を全部外す。
func _clear_all() -> void:
	var mods: Array = settings.mods
	if mods.is_empty():
		return
	UiSfx.play("off")
	for id in _cards:
		ToggleCard.set_on(_cards[id], false)
	settings.mods = []
	_sync_clear_btn()
	changed.emit()
	refresh_info()


## 「すべて解除」は、何も付けていないときは押せない。
func _sync_clear_btn() -> void:
	if _clear_btn != null:
		_clear_btn.disabled = (settings.mods as Array).is_empty()


## 見出し(小さな文字)と、その下の大きな数字。幅は固定にする(Lv が 10 を超えて桁が増えても、ブロックが横にずれない)。
func _stat_block(cap: String, value: Label, width: float) -> Control:
	var b := VBoxContainer.new()
	b.custom_minimum_size = Vector2(width, 0)
	b.add_theme_constant_override("separation", -2)
	b.add_child(UiStyle.caption(cap))
	b.add_child(value)
	return b


## 合計ベーススコアの倍率と、選択中の難易度の MOD 適用後 Lv を更新する。animate なら、いま出している数字から新しい数字へ動かす。
func refresh_info(animate := true) -> void:
	if _lv_l == null:
		return
	var lv: float = level_cb.call() if level_cb.is_valid() else -1.0
	var mul: float = Mods.params(settings.mods).score_mul
	_ease_lv(lv, animate)
	_ease_mul(mul, animate)


func _show_lv(v: float) -> void:
	_lv_shown = v
	_lv_l.text = "%.2f" % v
	_lv_l.add_theme_color_override("font_color", UiStyle.level_color(v))   # 数字が動くあいだ、色も Lv に合わせて変わる


func _ease_lv(to: float, animate: bool) -> void:
	if _lv_tween != null and _lv_tween.is_valid():
		_lv_tween.kill()
	if to < 0.0:
		_lv_shown = -1.0
		_lv_l.text = "--"
		_lv_l.add_theme_color_override("font_color", UiStyle.TEXT_FAINT)
		return
	if not animate or not UiStyle.animate or _lv_shown < 0.0 or not is_inside_tree():
		_show_lv(to)
		return
	if is_equal_approx(_lv_shown, to):
		return
	_lv_tween = create_tween()
	_lv_tween.tween_method(_show_lv, _lv_shown, to, EASE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pop(_lv_l)


func _show_mul(v: float) -> void:
	_mul_shown = v
	_mul_l.text = "×%.4f" % v


func _ease_mul(to: float, animate: bool) -> void:
	if _mul_tween != null and _mul_tween.is_valid():
		_mul_tween.kill()
	if not animate or not UiStyle.animate or not is_inside_tree():
		_show_mul(to)
		return
	if is_equal_approx(_mul_shown, to):
		return
	_mul_tween = create_tween()
	_mul_tween.tween_method(_show_mul, _mul_shown, to, EASE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pop(_mul_l)


## 数字が変わるとき、ぽんと少し弾む。
func _pop(l: Label) -> void:
	l.pivot_offset = Vector2(l.get_minimum_size().x * 0.5, l.size.y * 0.5)   # 文字の中心(ブロックは固定幅で、文字は左寄せ)
	UiStyle.spring(l, "scale", Vector2(1.08, 1.08), Vector2.ONE, 0.35)


func close_panel() -> void:
	if _closing:
		return
	_closing = true
	UiSfx.play("close")
	if not UiStyle.animate:
		closed.emit()
		return
	# 閉じる動き: パネルが少し縮みながら消え、背景が明るさを戻す
	_panel.pivot_offset = _panel.size * 0.5
	var t := create_tween().set_parallel(true)
	t.tween_property(_dim, "color:a", 0.0, 0.18)
	t.tween_property(_panel, "modulate:a", 0.0, 0.16)
	t.tween_property(_panel, "scale", Vector2(0.96, 0.96), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(func(): closed.emit())


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	get_viewport().set_input_as_handled()   # 開いている間、キー操作は、下の画面へ渡さない
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE or event.keycode == KEY_M:
		close_panel()
