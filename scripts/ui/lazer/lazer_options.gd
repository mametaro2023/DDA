extends "res://scripts/ui/options_panel.gd"
## lazer 風の設定パネル(画面の左から滑り込む縦長のパネル)。設定の項目と、書き換える処理は classic の設定パネル(options_panel.gd)のものをそのまま使い、
## 枠(lazer_frame.gd)・ページの見出し・トグル・スライダーの見た目だけを差し替える。契約も同じ: setup(settings)、signal changed / closed、show_section、refresh_size。

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerFrame = preload("res://scripts/ui/lazer/lazer_frame.gd")

const WIDTH := 940.0
const PAGE_BUILDERS := ["_build_control", "_build_audio", "_build_screen", "_build_songs", "_build_other"]

var _stack: Control


func _ready() -> void:
	var f := LazerFrame.build(self, "設定", "OPTIONS", SECTIONS, WIDTH, func(i: int): _show(i))
	_dim = f.dim
	_panel = f.panel
	_nav = f.nav
	_nav_holder = f.nav_holder
	_nav_ind = f.nav_ind
	f.close.pressed.connect(close_panel)
	_stack = f.stack
	for k in range(SECTIONS.size()):   # ページは、開いたときに作る(5 ページ全部を、開くたびに作ると重い)。作るまでは、場所取りだけ置いておく
		var ph := Control.new()
		ph.visible = false
		ph.set_meta("lazy", true)
		_pages.append(ph)
	UiStyle.close_on_outside_click(self, _panel, close_panel)
	_show(0)
	LazerFrame.open_anim(self, _dim, _panel, _nav)


func _show(i: int) -> void:
	_ensure_page(i)
	super._show(i)


## i 番のページを、まだなら作る(場所取りと入れ替える)。
func _ensure_page(i: int) -> void:
	var ph: Control = _pages[i]
	if not ph.has_meta("lazy"):
		return
	var page: Control = call(PAGE_BUILDERS[i])
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.visible = false   # 表示は _show が決める(切り替えの動きは、非表示から表示へ変わったときに付く)
	_stack.add_child(page)
	_pages[i] = page
	ph.free()


func close_panel() -> void:
	if _closing:
		return
	_closing = true
	LazerFrame.close_anim(self, _dim, _panel, func(): closed.emit())


# --- 部品の差し替え(ページを作る処理は、classic のものをそのまま使う) ---

func _page(title: String, sub: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.add_child(LazerStyle.label(title, 28, LazerStyle.TEXT, true))
	if sub != "":
		v.add_child(LazerStyle.label(sub, 13, LazerStyle.TEXT_DIM))
	var line := ColorRect.new()
	line.color = LazerStyle.PINK
	line.custom_minimum_size = Vector2(56, 3)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(line)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	v.add_child(gap)
	return v


func _toggle_card(title: String, lines: String, _color: Color, on: bool, _right_text: String, on_toggle: Callable) -> PanelContainer:
	return LazerFrame.toggle(self, title, lines, on, on_toggle)


func _slider_row(parent: Control, cap: String, lo: float, hi: float, step: float, value: float, fmt: Callable, _cap_w := 170.0, _slider_w := 380.0, _val_w := 90.0) -> HSlider:
	return LazerFrame.slider_row(parent, cap, lo, hi, step, value, fmt)
