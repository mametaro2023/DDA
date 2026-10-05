extends Control
## プレイリストのパネル(上のプレイヤーの「≡」を押すと、main が開く。どの画面でも開ける)。
## 左に、プレイリストの一覧(新しく作る)。右に、選んだプレイリストの曲(押すと、その曲から流す・▲▼で並べ替え・✕で外す)、
## 再生・シャッフル・リピート・名前の変更・削除、曲の追加(ライブラリから探して足す / いま流れている曲を足す)。
## 実際に曲を流すのは、いまの画面(タイトル・選曲。NowPlaying.play_cb)。流せない画面では、編集だけできる。
## 契約は確認パネル(lazer_quit.gd)と同じ: signal closed。Esc・✕・パネルの外で閉じる。

signal closed

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerIcons = preload("res://scripts/ui/lazer/lazer_icons.gd")
const NowPlaying = preload("res://scripts/ui/lazer/now_playing.gd")
const Playlist = preload("res://scripts/playlist.gd")
const SongLibrary = preload("res://scripts/song_library.gd")

const PANEL_POS := Vector2(566, 46)
const PANEL_SIZE := Vector2(700, 468)
const LEFT_W := 190.0
const ROW_H := 44.0
const PICK_MAX := 300   # 曲を探す一覧に出す最大の数(多いときは、検索で絞る)

## 曲を探す一覧の元(ライブラリの全曲)。開くたびに作り直さないよう、覚えておく
static var _lib: Array = []
static var _lib_time := -100000
const LIB_TTL_MS := 60000

var _panel: PanelContainer
var _left_box: VBoxContainer
var _right: VBoxContainer
var _status: Label
var _picking := false          # 曲を探す表示
var _renaming := false
var _search := ""
var _rows: Array = []          # 曲の行(現在の曲の印を付け替えるため)
var _list_rows: Array = []
var _rev := -1
var _state_rev := -1
var _lib_loading := false
var _closing := false
var _pick_list: VBoxContainer
var _pick_note: Label
var _can_play_shown := false
var _tsc: ScrollContainer     # 曲の一覧のスクロール(作り直しても、位置を保つため)
## 曲を探す一覧を集める別スレッドの結果(スレッドが、パネルを閉じたあとに終わってもよいように、パネルとは別に持つ)
static var _lib_mutex := Mutex.new()
static var _lib_result: Array = []
static var _lib_done := false


# --- 行(自分で描く) ---

class ListRow extends Control:
	signal chosen
	var idx := 0
	func _init(i: int) -> void:
		idx = i
		custom_minimum_size = Vector2(0, 40)
		mouse_filter = Control.MOUSE_FILTER_STOP
	var _hov := false
	func _ready() -> void:
		mouse_entered.connect(func():
			_hov = true
			queue_redraw())
		mouse_exited.connect(func():
			_hov = false
			queue_redraw())
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			chosen.emit()
			accept_event()
	func _draw() -> void:
		var l: Dictionary = Playlist.lists[idx]
		var sel: bool = Playlist.selected == idx
		if sel:
			draw_rect(Rect2(Vector2.ZERO, size), Color(LazerStyle.PINK.r, LazerStyle.PINK.g, LazerStyle.PINK.b, 0.16))
			draw_rect(Rect2(0, 0, 3, size.y), LazerStyle.PINK)
		elif _hov:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.06))
		var playing: bool = Playlist.playing == idx and Playlist.is_active()
		var x := 14.0
		if playing:
			LazerIcons.draw_icon(self, "play", Vector2(18, size.y * 0.5), 6.0, LazerStyle.PINK)
			x = 32.0
		var count := str((l.tracks as Array).size())
		var cw: float = LazerStyle.font().get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(LazerStyle.font(), Vector2(size.x - cw - 12.0, size.y * 0.5 + 5.0), count, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, LazerStyle.TEXT_MUTE)
		var nm: String = LazerStyle.fit(LazerStyle.font_bold() if sel else LazerStyle.font(), str(l.name), 15, size.x - x - cw - 24.0)
		var ink := LazerStyle.PINK if playing else (LazerStyle.TEXT if sel else LazerStyle.TEXT_DIM)
		draw_string(LazerStyle.font_bold() if sel else LazerStyle.font(), Vector2(x, size.y * 0.5 + 5.5), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ink)


## 曲の行。tracks モード = 流す・並べ替え・外す。pick モード = 押すと足す。
class SongRow extends Control:
	signal chosen
	signal up
	signal down
	signal remove
	var path := ""
	var title := ""
	var artist := ""
	var number := 0
	var pick_mode := false
	var hover_zone := -1   # 0 = ▲ 1 = ▼ 2 = ✕
	func _init(p: String, t: String, a: String, n: int, pick: bool) -> void:
		path = p
		title = t
		artist = a
		number = n
		pick_mode = pick
		custom_minimum_size = Vector2(0, 46)
		mouse_filter = Control.MOUSE_FILTER_STOP
	var _hov := false
	func _ready() -> void:
		mouse_entered.connect(func():
			_hov = true
			queue_redraw())
		mouse_exited.connect(func():
			_hov = false
			hover_zone = -1
			queue_redraw())
	func _zone_at(x: float) -> int:
		if pick_mode or not _hov:
			return -1
		for k in range(3):
			if absf(x - (size.x - 22.0 - 26.0 * (2 - k))) <= 11.0:
				return k
		return -1
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion:
			var z := _zone_at(ev.position.x)
			if z != hover_zone:
				hover_zone = z
				queue_redraw()
		elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			match _zone_at(ev.position.x):
				0:
					up.emit()
				1:
					down.emit()
				2:
					remove.emit()
				_:
					chosen.emit()
			accept_event()
	func _draw() -> void:
		var cur := false
		var added := false
		if pick_mode:
			added = Playlist.index_of(Playlist.selected, path) >= 0
		else:
			cur = Playlist.is_active() and Playlist.playing == Playlist.selected and Playlist.current_index() == number - 1
		if cur:
			draw_rect(Rect2(Vector2.ZERO, size), Color(LazerStyle.PINK.r, LazerStyle.PINK.g, LazerStyle.PINK.b, 0.14))
			draw_rect(Rect2(0, 0, 3, size.y), LazerStyle.PINK)
		elif _hov:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.06))
		var f := LazerStyle.font()
		var fb := LazerStyle.font_bold()
		var tx := 16.0
		if not pick_mode:
			if cur:
				LazerIcons.draw_icon(self, "play", Vector2(20, size.y * 0.5), 6.0, LazerStyle.PINK)
			else:
				draw_string(f, Vector2(8, size.y * 0.5 + 5.0), str(number), HORIZONTAL_ALIGNMENT_CENTER, 24.0, 13, LazerStyle.TEXT_MUTE)
			tx = 40.0
		var right_pad := 14.0 if pick_mode else 96.0
		if pick_mode:
			right_pad = 60.0
		var maxw := size.x - tx - right_pad
		draw_string(fb, Vector2(tx, 20.0), LazerStyle.fit(fb, title, 15, maxw), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, LazerStyle.PINK if cur else LazerStyle.TEXT)
		draw_string(f, Vector2(tx, 38.0), LazerStyle.fit(f, artist, 12, maxw), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LazerStyle.TEXT_MUTE)
		if pick_mode:
			if added:
				LazerIcons.draw_icon(self, "check", Vector2(size.x - 28.0, size.y * 0.5), 8.0, LazerStyle.GREEN, 2.0)
			else:
				LazerIcons.draw_icon(self, "plus", Vector2(size.x - 28.0, size.y * 0.5), 8.0, LazerStyle.TEXT if _hov else LazerStyle.TEXT_MUTE, 1.8)
		elif _hov:
			for k in range(3):
				var cx := size.x - 22.0 - 26.0 * (2 - k)
				if k == hover_zone:
					draw_circle(Vector2(cx, size.y * 0.5), 11.0, Color(1, 1, 1, 0.14))
				LazerIcons.draw_icon(self, ["up", "down", "x"][k], Vector2(cx, size.y * 0.5), 6.5, LazerStyle.TEXT if k == hover_zone else LazerStyle.TEXT_DIM, 1.6)


# --- 組み立て ---

func _ready() -> void:
	Playlist.ensure_loaded()
	theme = LazerStyle.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel = PanelContainer.new()
	_panel.position = PANEL_POS
	_panel.custom_minimum_size = PANEL_SIZE
	_panel.size = PANEL_SIZE
	var sb := LazerStyle.box(Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.985), Color(1, 1, 1, 0.10), 1, 14, 0, 0)
	sb.border_color = Color(LazerStyle.PINK.r, LazerStyle.PINK.g, LazerStyle.PINK.b, 0.5)
	sb.border_width_top = 3
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 18
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	_panel.add_child(root)
	# 見出し
	var head := HBoxContainer.new()
	head.custom_minimum_size = Vector2(0, 46)
	head.add_theme_constant_override("separation", 10)
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_left", 18)
	hm.add_theme_constant_override("margin_right", 10)
	hm.add_child(head)
	root.add_child(hm)
	var t := LazerStyle.label("プレイリスト", 18, LazerStyle.TEXT, true)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)
	_status = LazerStyle.label("", 13, LazerStyle.TEXT_MUTE)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_status)
	head.add_child(_icon_button("x", "閉じる", _close))
	var line := ColorRect.new()
	line.color = LazerStyle.LINE
	line.custom_minimum_size = Vector2(0, 1)
	root.add_child(line)
	# 本体
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(LEFT_W, 0)
	left.add_theme_constant_override("separation", 0)
	body.add_child(left)
	var lsc := ScrollContainer.new()
	lsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(lsc)
	_left_box = VBoxContainer.new()
	_left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_box.add_theme_constant_override("separation", 0)
	lsc.add_child(_left_box)
	var new_btn := _text_button("新しいプレイリスト", "plus", _new_list)
	var nm := MarginContainer.new()
	nm.add_theme_constant_override("margin_left", 10)
	nm.add_theme_constant_override("margin_right", 10)
	nm.add_theme_constant_override("margin_top", 8)
	nm.add_theme_constant_override("margin_bottom", 10)
	nm.add_child(new_btn)
	left.add_child(nm)
	var vline := ColorRect.new()
	vline.color = LazerStyle.LINE
	vline.custom_minimum_size = Vector2(1, 0)
	body.add_child(vline)
	var rm := MarginContainer.new()
	rm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rm.add_theme_constant_override("margin_left", 14)
	rm.add_theme_constant_override("margin_right", 12)
	rm.add_theme_constant_override("margin_top", 10)
	rm.add_theme_constant_override("margin_bottom", 10)
	body.add_child(rm)
	_right = VBoxContainer.new()
	_right.add_theme_constant_override("separation", 8)
	rm.add_child(_right)
	UiStyle.close_on_outside_click(self, _panel, _close)
	_build_left()
	_build_right()
	_update_status()
	if UiStyle.animate:   # 開く: 少し下がりながら現れる(点滅なし)
		_panel.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_panel, "modulate:a", 1.0, 0.16)
		tw.tween_property(_panel, "position:y", PANEL_POS.y, 0.22).from(PANEL_POS.y - 8.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	UiSfx.play("open")


func _process(_delta: float) -> void:
	if Playlist.rev != _rev:   # 曲・プレイリストが増減した・名前が変わった(曲を探している間は、右は作り直さない = 検索・位置を保つ)
		_rev = Playlist.rev
		_build_left()
		if not _picking:
			_build_right()
		_update_status()
	if _lib_loading and _take_library():
		_fill_picker()
	if Playlist.state_rev != _state_rev or NowPlaying.can_play_playlist() != _can_play_shown:   # 流している曲が変わった
		_state_rev = Playlist.state_rev
		for r in _list_rows:
			if is_instance_valid(r):
				(r as Control).queue_redraw()
		for r in _rows:
			if is_instance_valid(r):
				(r as Control).queue_redraw()
		_update_status()


func _update_status() -> void:
	_can_play_shown = NowPlaying.can_play_playlist()
	if Playlist.is_active():
		_status.text = "再生中: %s" % str(Playlist.lists[Playlist.playing].name)
		_status.add_theme_color_override("font_color", LazerStyle.PINK)
	elif not _can_play_shown:
		_status.text = "この画面では再生できません(タイトル・選曲で再生できます)"
		_status.add_theme_color_override("font_color", LazerStyle.TEXT_MUTE)
	else:
		_status.text = ""


func _icon_button(icon: String, tip: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(34, 34)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", LazerStyle.box(Color(1, 1, 1, 0.10), Color(0, 0, 0, 0), 0, 17))
	b.add_child(LazerIcons.new(icon, LazerStyle.TEXT_DIM, 16.0))
	b.get_child(0).position = Vector2(9, 9)
	b.pressed.connect(on_press)
	return b


func _text_button(caption: String, icon: String, on_press: Callable, accent := false) -> Button:
	var b := Button.new()
	b.text = ("    " if icon != "" else "") + caption
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	var bg := Color(LazerStyle.PINK.r, LazerStyle.PINK.g, LazerStyle.PINK.b, 0.9) if accent else Color(1, 1, 1, 0.07)
	var bgh := LazerStyle.PINK.lightened(0.15) if accent else Color(1, 1, 1, 0.14)
	b.add_theme_stylebox_override("normal", LazerStyle.box(bg, Color(1, 1, 1, 0.0 if accent else 0.10), 1, 8, 14, 8))
	b.add_theme_stylebox_override("hover", LazerStyle.box(bgh, Color(1, 1, 1, 0.0 if accent else 0.10), 1, 8, 14, 8))
	b.add_theme_stylebox_override("pressed", LazerStyle.box(bgh.darkened(0.1), Color(1, 1, 1, 0.1), 1, 8, 14, 8))
	b.add_theme_stylebox_override("disabled", LazerStyle.box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.06), 1, 8, 14, 8))
	if accent:
		b.add_theme_color_override("font_color", Color(0.16, 0.03, 0.07))
		b.add_theme_color_override("font_hover_color", Color(0.16, 0.03, 0.07))
		b.add_theme_color_override("font_pressed_color", Color(0.16, 0.03, 0.07))
	if icon != "":
		var ic := LazerIcons.new(icon, Color(0.16, 0.03, 0.07) if accent else LazerStyle.TEXT_DIM, 14.0)
		b.add_child(ic)
		ic.position = Vector2(12, 11)
	b.pressed.connect(func():
		UiSfx.play("click")
		on_press.call())
	return b


## 左: プレイリストの一覧
func _build_left() -> void:
	_list_rows.clear()
	for c in _left_box.get_children():
		c.queue_free()
	for i in range(Playlist.lists.size()):
		var r := ListRow.new(i)
		r.chosen.connect(func():
			if Playlist.selected != i or _picking:
				UiSfx.play("select", 1.1)
			Playlist.selected = i
			_picking = false
			_renaming = false
			Playlist.save()
			for x in _list_rows:
				(x as Control).queue_redraw()
			_build_right())
		_left_box.add_child(r)
		_list_rows.append(r)


## 右: 選んだプレイリスト(曲の一覧 / 曲を探す)
func _build_right() -> void:
	_rows.clear()
	var keep := _tsc.scroll_vertical if _tsc != null and is_instance_valid(_tsc) and not _picking else 0
	_tsc = null
	for c in _right.get_children():
		c.queue_free()
	if Playlist.lists.is_empty():
		var hint := LazerStyle.label("プレイリストがありません。\n左下の「新しいプレイリスト」から作れます。", 15, LazerStyle.TEXT_MUTE)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_right.add_child(hint)
		return
	if _picking:
		_build_picker()
		return
	var li: int = clampi(Playlist.selected, 0, Playlist.lists.size() - 1)
	var l: Dictionary = Playlist.lists[li]
	# 名前の行
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 6)
	_right.add_child(nrow)
	if _renaming:
		var ed := LineEdit.new()
		ed.text = str(l.name)
		ed.max_length = Playlist.MAX_NAME
		ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ed.custom_minimum_size = Vector2(0, 36)
		ed.add_theme_font_size_override("font_size", 16)
		var commit := func(save: bool):
			if not _renaming:
				return
			_renaming = false
			if save:
				Playlist.rename(li, ed.text)
			else:
				_build_right()
		ed.text_submitted.connect(func(_t: String): commit.call(true))
		ed.focus_exited.connect(func(): commit.call(true))
		ed.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
				commit.call(false)
				accept_event())
		nrow.add_child(ed)
		ed.grab_focus.call_deferred()
		ed.select_all.call_deferred()
	else:
		var nl := LazerStyle.label(str(l.name), 19, LazerStyle.TEXT, true)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.clip_text = true
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nrow.add_child(nl)
		nrow.add_child(_icon_button("pencil", "名前を変える", func():
			_renaming = true
			_build_right()))
		nrow.add_child(_icon_button("trash", "プレイリストを消す", _delete_list.bind(li)))
	# 操作の行
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	_right.add_child(crow)
	var tracks: Array = l.tracks
	var play := _text_button("再生", "play", _play_list.bind(li, -1), true)
	play.disabled = tracks.is_empty()
	crow.add_child(play)
	var sh := _toggle_button("shuffle", "シャッフル", Playlist.shuffle, func():
		Playlist.toggle_shuffle())
	crow.add_child(sh)
	var rp := _toggle_button("repeat", "リピート " + Playlist.repeat_label(), Playlist.repeat != Playlist.REPEAT_OFF, func():
		Playlist.cycle_repeat())
	crow.add_child(rp)
	if Playlist.is_active():
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		crow.add_child(spacer)
		crow.add_child(_text_button("流しを解除", "", func():
			Playlist.stop()
			_update_status()))
	# 曲の一覧
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_right.add_child(sc)
	_tsc = sc
	if keep > 0:   # 曲を動かした・消したあとも、見ていた位置を保つ
		sc.set_deferred("scroll_vertical", keep)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 0)
	sc.add_child(box)
	if tracks.is_empty():
		var e := LazerStyle.label("曲がありません。下の「曲を追加」から足せます。", 14, LazerStyle.TEXT_MUTE)
		e.custom_minimum_size = Vector2(0, 60)
		e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(e)
	for t in range(tracks.size()):
		var tr: Dictionary = tracks[t]
		var r := SongRow.new(str(tr.path), str(tr.title), str(tr.artist), t + 1, false)
		r.chosen.connect(_play_list.bind(li, t))
		r.up.connect(func():
			UiSfx.play("click")
			Playlist.move_track(li, t, -1))
		r.down.connect(func():
			UiSfx.play("click")
			Playlist.move_track(li, t, 1))
		r.remove.connect(func():
			UiSfx.play("click", 0.9)
			Playlist.remove_track(li, t))
		box.add_child(r)
		_rows.append(r)
	# 追加の行
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 8)
	_right.add_child(arow)
	arow.add_child(_text_button("曲を追加", "plus", func():
		_picking = true
		_search = ""
		_build_right()))
	var cur_btn := _text_button("流れている曲を追加", "note", func():
		if Playlist.add(li, NowPlaying.path, NowPlaying.title, NowPlaying.artist):
			UiSfx.play("select", 1.3)
		else:
			UiSfx.play("deny"))
	cur_btn.disabled = not NowPlaying.is_set() or NowPlaying.path == ""
	arow.add_child(cur_btn)


func _toggle_button(icon: String, caption: String, on: bool, on_press: Callable) -> Button:
	var b := _text_button(caption, icon, on_press)
	if on:
		b.add_theme_stylebox_override("normal", LazerStyle.box(Color(LazerStyle.PINK.r, LazerStyle.PINK.g, LazerStyle.PINK.b, 0.22), LazerStyle.PINK, 1, 8, 14, 8))
		b.add_theme_stylebox_override("hover", LazerStyle.box(Color(LazerStyle.PINK.r, LazerStyle.PINK.g, LazerStyle.PINK.b, 0.34), LazerStyle.PINK, 1, 8, 14, 8))
		b.add_theme_color_override("font_color", LazerStyle.PINK)
		b.add_theme_color_override("font_hover_color", LazerStyle.PINK)
		(b.get_child(0) as LazerIcons).col = LazerStyle.PINK
	return b


## 曲を探す表示
func _build_picker() -> void:
	var li: int = clampi(Playlist.selected, 0, Playlist.lists.size() - 1)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	_right.add_child(top)
	var ed := LineEdit.new()
	ed.placeholder_text = "曲名・アーティストで探す"
	ed.text = _search
	ed.clear_button_enabled = true
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ed.custom_minimum_size = Vector2(0, 36)
	ed.text_changed.connect(func(s: String):
		_search = s
		_fill_picker())
	top.add_child(ed)
	top.add_child(_text_button("完了", "", func():
		_picking = false
		_build_right()))
	_pick_note = LazerStyle.label("", 12, LazerStyle.TEXT_MUTE)
	_right.add_child(_pick_note)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_right.add_child(sc)
	_pick_list = VBoxContainer.new()
	_pick_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pick_list.add_theme_constant_override("separation", 0)
	sc.add_child(_pick_list)
	if Time.get_ticks_msec() - _lib_time > LIB_TTL_MS or _lib.is_empty():
		_load_library()
	else:
		_fill_picker()
	ed.grab_focus.call_deferred()


## ライブラリの全曲({path, title, artist})を、別スレッドで集める(索引にあれば軽い)。
func _load_library() -> void:
	if _lib_loading:
		return
	_lib_loading = true
	_pick_note.text = "曲を読み込んでいます…"
	_lib_mutex.lock()
	_lib_done = false
	_lib_mutex.unlock()
	var paths := SongLibrary.find_all()
	WorkerThreadPool.add_task(func():
		var out: Array = []
		for p in paths:
			var info := SongLibrary.info(str(p))
			if bool(info.get("ok", false)):
				out.append({"path": str(p), "title": str(info.title), "artist": str(info.artist)})
		out.sort_custom(func(a, b): return str(a.title).naturalnocasecmp_to(str(b.title)) < 0)
		_lib_mutex.lock()
		_lib_result = out
		_lib_done = true
		_lib_mutex.unlock())


## 集め終わっていたら、受け取る(true)。
func _take_library() -> bool:
	_lib_mutex.lock()
	var done := _lib_done
	if done:
		_lib = _lib_result
		_lib_done = false
	_lib_mutex.unlock()
	if done:
		_lib_loading = false
		_lib_time = Time.get_ticks_msec()
	return done


func _fill_picker() -> void:
	if _pick_list == null or not is_instance_valid(_pick_list):
		return
	_rows.clear()
	for c in _pick_list.get_children():
		c.queue_free()
	var q := _search.strip_edges().to_lower()
	var shown := 0
	var total := 0
	for s in _lib:
		if q != "" and not (str(s.title).to_lower().contains(q) or str(s.artist).to_lower().contains(q)):
			continue
		total += 1
		if shown >= PICK_MAX:
			continue
		var r := SongRow.new(str(s.path), str(s.title), str(s.artist), 0, true)
		r.chosen.connect(func():
			if Playlist.add(Playlist.selected, str(s.path), str(s.title), str(s.artist)):
				UiSfx.play("select", 1.3)
			else:
				UiSfx.play("deny")
			r.queue_redraw())
		_pick_list.add_child(r)
		_rows.append(r)
		shown += 1
	if _lib_loading:
		_pick_note.text = "曲を読み込んでいます…"
	elif total == 0:
		_pick_note.text = "見つかりません" if _lib.size() > 0 else "曲がありません"
	elif total > shown:
		_pick_note.text = "%d 曲のうち、先頭の %d 曲を表示(検索で絞れます)" % [total, shown]
	else:
		_pick_note.text = "%d 曲(押すと、プレイリストに足します)" % total


# --- 操作 ---

func _new_list() -> void:
	var i := Playlist.create("")
	if i < 0:
		UiSfx.play("deny")
		return
	UiSfx.play("select", 1.2)
	_picking = false
	_renaming = true   # 作ったら、すぐ名前を付けられる


func _delete_list(i: int) -> void:
	UiSfx.play("click", 0.9)
	_renaming = false
	Playlist.delete(i)


## プレイリスト li の t 番目から流す(t < 0: 流している最中ならその曲・そうでなければ最初)。
func _play_list(li: int, t: int) -> void:
	if not NowPlaying.can_play_playlist():
		UiSfx.play("deny")
		_status.text = "この画面では再生できません(タイトル・選曲で再生できます)"
		return
	var start := t
	if start < 0:
		start = Playlist.current_index() if Playlist.is_active() and Playlist.playing == li else 0
	UiSfx.play("click")
	if not NowPlaying.play_playlist(li, maxi(start, 0)):
		UiSfx.play("deny")
	_update_status()


func _close() -> void:
	if _closing:
		return
	_closing = true
	Playlist.save()
	UiSfx.play("close")
	if UiStyle.animate and is_inside_tree():
		var tw := create_tween()
		tw.tween_property(_panel, "modulate:a", 0.0, 0.12)
		tw.tween_callback(func(): closed.emit())
	else:
		closed.emit()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _renaming or _picking:
			get_viewport().set_input_as_handled()
			if _renaming:
				_renaming = false
				_build_right()
			else:
				_picking = false
				_build_right()
		else:
			_close()
			get_viewport().set_input_as_handled()
