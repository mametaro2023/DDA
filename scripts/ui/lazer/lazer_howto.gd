extends "res://scripts/ui/howto_panel.gd"
## lazer 風の遊び方パネル。説明の中身(ページ)とキー操作(Esc / Tab / ↑↓)は classic(howto_panel.gd)のものをそのまま使い、
## 枠を設定パネルと同じ「左から滑り込む縦長のパネル」(lazer_frame.gd)に、見出し・段落・行の見た目を lazer 風に差し替える。

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerFrame = preload("res://scripts/ui/lazer/lazer_frame.gd")
const SmoothScroll = preload("res://scripts/ui/smooth_scroll.gd")

const WIDTH := 940.0

var _nav_holder: Control
var _nav_ind: Panel
var _nav_tween: Tween
var _stack: Control


func _ready() -> void:
	var f := LazerFrame.build(self, "遊び方", "HOW TO PLAY", SECTIONS, WIDTH, func(i: int): _show(i))
	_dim = f.dim
	_panel = f.panel
	_nav = f.nav
	_nav_holder = f.nav_holder
	_nav_ind = f.nav_ind
	f.close.pressed.connect(close_panel)
	_stack = f.stack
	for k in range(SECTIONS.size()):   # 中身は、開いたページから作る(長い文章の組版は重いので、開くときに全部は作らない)
		var holder := Control.new()
		holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.visible = false
		_stack.add_child(holder)
		_pages.append(holder)
	UiStyle.close_on_outside_click(self, _panel, close_panel)
	_show(0)
	LazerFrame.open_anim(self, _dim, _panel, _nav)


func _show(i: int) -> void:
	var prev := _cur
	_ensure_page(i)
	super._show(i)
	if _nav_ind == null:
		return
	if prev < 0 or not _nav_holder.is_inside_tree() or _nav[_cur].size == Vector2.ZERO:   # 最初は、並びが決まってから置く
		await get_tree().process_frame
		if not is_instance_valid(_nav_ind) or _cur < 0:
			return
		_place_nav_indicator(false)
		_nav_ind.visible = true
		UiStyle.tween(_nav_ind, "modulate:a", 0.0, 1.0, 0.3, 0.1)
		return
	_place_nav_indicator(true)


## i 番のページの中身を、まだなら作る。
func _ensure_page(i: int) -> void:
	var holder: Control = _pages[i]
	if holder.get_child_count() > 0:
		return
	var page: Control = call(PAGE_BUILDERS[i])
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(page)


## 選んでいる項目の下へ、ピンクの枠を滑らせる(設定パネルと同じ動き)。
func _place_nav_indicator(animated: bool) -> void:
	var b: Control = _nav[_cur]
	var to := b.global_position - _nav_holder.global_position
	_nav_ind.size = b.size
	if _nav_tween != null and _nav_tween.is_valid():
		_nav_tween.kill()
	if not animated or not UiStyle.animate:
		_nav_ind.position = to
		return
	_nav_tween = _nav_ind.create_tween()
	_nav_tween.tween_property(_nav_ind, "position", to, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close_panel() -> void:
	if _closing:
		return
	_closing = true
	LazerFrame.close_anim(self, _dim, _panel, func(): closed.emit())


# --- 部品の差し替え(ページの中身は classic のものをそのまま使う) ---

func _section(title: String) -> Array:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	SmoothScroll.attach(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 12)
	scroll.add_child(v)
	v.add_child(LazerStyle.label(title, 28, LazerStyle.TEXT, true))
	var line := ColorRect.new()
	line.color = LazerStyle.PINK
	line.custom_minimum_size = Vector2(56, 3)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(line)
	return [scroll, v]


func _para(v: VBoxContainer, text: String, color := UiStyle.TEXT_DIM, size := 15) -> void:
	var l := LazerStyle.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_constant_override("line_spacing", 3)
	v.add_child(l)


## 小見出し: 左にピンクの縦の線。
func _head(v: VBoxContainer, text: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	v.add_child(gap)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var bar := ColorRect.new()
	bar.color = LazerStyle.PINK
	bar.custom_minimum_size = Vector2(4, 0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)
	h.add_child(LazerStyle.label(text, 18, LazerStyle.TEXT, true))
	v.add_child(h)


## 「キー … 内容」の 1 行: 左にうす札の見出し、右に説明。
func _row(v: VBoxContainer, key: String, text: String, key_color := Color(0, 0, 0, 0)) -> void:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", LazerStyle.box(Color(1, 1, 1, 0.035), Color(0, 0, 0, 0), 0, 10, 14, 9))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	row.add_child(h)
	var k := LazerStyle.label(key, 15, key_color if key_color.a > 0.0 else LazerStyle.PINK, true)
	k.custom_minimum_size = Vector2(180, 0)
	k.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN   # 説明が何行でも、見出しは 1 行目の高さに
	h.add_child(k)
	var t := LazerStyle.label(text, 15, LazerStyle.TEXT_DIM)
	t.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	v.add_child(row)
