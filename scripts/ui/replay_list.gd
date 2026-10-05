extends Control
## リプレイの一覧パネル(タイトル画面の上に重ねる)。遊んだプレイが自動で保存されている(新しい KEEP 件まで)ので、ここから選んで見返す。
## 1 行 = 1 プレイ(結果のランク・曲・難易度・MOD・スコア・日時)。「再生」で開く / 「保存」で自動の整理で消えないようにする / 「削除」で消す。
## 操作: ↑↓ で選ぶ / Enter(ダブルクリック)で再生 / S で保存 / Delete で削除 / Esc で閉じる。
## 見た目は UiStyle の配色なので、classic でも lazer 風でも、その UI セットの色になる。

signal closed
signal replay_requested(name: String)

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const SmoothScroll = preload("res://scripts/ui/smooth_scroll.gd")
const Replay = preload("res://scripts/replay.gd")
const SongLibrary = preload("res://scripts/song_library.gd")
const Mods = preload("res://scripts/mods.gd")

const FILTERS := ["すべて", "クリア", "ゲームオーバー", "保存済み"]

var _items: Array = []          # Replay.list() の結果
var _shown: Array = []          # フィルタ後
var _filter := 0
var _sel := 0
var _dim: ColorRect
var _panel: PanelContainer
var _list: VBoxContainer
var _scroll: ScrollContainer
var _smooth: Node
var _cards: Array = []
var _count_l: Label
var _filter_btns: Array = []
var _closing := false
var _del_name := ""             # 「削除」を 1 度押して、確認待ちの行
var _del_timer: SceneTreeTimer
var _have: Dictionary = {}      # md5 → 曲が見つかるか


func _ready() -> void:
	theme = UiStyle.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.7)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.position = Vector2(70, 28)
	_panel.size = Vector2(1140, 664)
	_panel.clip_contents = true   # 中身(フォントの幅が広い UI でも)が、パネルの外へ出ないように
	_panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.LINE, 1, 8, 0, 0))
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	# 見出し + フィルタ + ✕
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	root.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.add_child(UiStyle.label("REPLAYS", 22, UiStyle.TEXT, true))
	titles.add_child(UiStyle.caption("リプレイ"))
	head.add_child(titles)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	var group := ButtonGroup.new()
	for i in range(FILTERS.size()):
		var b := Button.new()
		b.text = FILTERS[i]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.set_pressed_no_signal(i == 0)
		b.pressed.connect(func():
			_filter = i
			_sel = 0
			_rebuild())
		head.add_child(b)
		_filter_btns.append(b)
	root.add_child(UiStyle.hline())

	# 一覧
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_scroll)
	_smooth = SmoothScroll.attach(_scroll, true)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list)

	# 足もと
	root.add_child(UiStyle.hline())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	root.add_child(foot)
	_count_l = UiStyle.label("", 13, UiStyle.TEXT_DIM)
	_count_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_l.clip_text = true   # 長い文で、パネルが広がらないように
	_count_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	foot.add_child(_count_l)
	var open_b := Button.new()
	open_b.text = "保存先のフォルダを開く"
	open_b.focus_mode = Control.FOCUS_NONE
	open_b.pressed.connect(func(): OS.shell_show_in_file_manager(ProjectSettings.globalize_path(Replay.dir)))
	foot.add_child(open_b)
	var close_b := Button.new()
	close_b.text = "閉じる"
	close_b.focus_mode = Control.FOCUS_NONE
	close_b.pressed.connect(close_panel)
	foot.add_child(close_b)

	UiStyle.close_on_outside_click(self, _panel, close_panel)
	_items = Replay.list()
	for m in _items:
		if not _have.has(m.md5):
			_have[m.md5] = not SongLibrary.find_by_md5(str(m.md5)).is_empty()
	_rebuild()
	UiStyle.tween(_dim, "color:a", 0.0, 0.7, 0.22)
	UiStyle.pop_scale(_panel, 0.93, 0.42)


func _matches(m: Dictionary) -> bool:
	match _filter:
		1:
			return not bool(m.failed)
		2:
			return bool(m.failed)
		3:
			return bool(m.keep)
	return true


## 一覧を、いまのフィルタで作り直す。
func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	_cards.clear()
	_shown = _items.filter(_matches)
	_sel = clampi(_sel, 0, maxi(_shown.size() - 1, 0))
	if _shown.is_empty():
		var empty := UiStyle.label("", 15, UiStyle.TEXT_DIM)
		empty.text = "まだリプレイがありません。\n曲を遊ぶと、自動で保存されます(設定で、保存しないこともできます)。" if _items.is_empty() \
			else "この条件のリプレイはありません。"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(0, 160)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_list.add_child(empty)
	for i in range(_shown.size()):
		var card := _make_row(i, _shown[i])
		_list.add_child(card)
		_cards.append(card)
	_restyle()
	var kept := 0
	var bytes := 0
	for m in _items:
		bytes += int(m.size)
		if bool(m.keep):
			kept += 1
	_count_l.text = "%d 件(保存済み %d 件)  ·  自動で残るのは、保存済みを除いて新しい %d 件まで  ·  %.1f MB" % [_items.size(), kept, Replay.KEEP, float(bytes) / 1048576.0]
	for i in range(_filter_btns.size()):
		_filter_btns[i].set_pressed_no_signal(i == _filter)


func _restyle() -> void:
	for i in range(_cards.size()):
		UiStyle.style_card(_cards[i], i == _sel, true, UiStyle.ACCENT)


func _select(i: int, scroll := false) -> void:
	if _shown.is_empty():
		return
	i = clampi(i, 0, _shown.size() - 1)
	if i != _sel:
		UiSfx.play("select")
	_sel = i
	_restyle()
	if scroll and _smooth != null and _sel < _cards.size():
		_smooth.scroll_to_control(_cards[_sel])


## 1 行: [ランク] [曲名 / 作者・難易度 / Lv・MOD(3 段)] [スコア / 被弾 / 日時・長さ] [再生 / 保存・削除]。
## 文字の多い真ん中の段に幅を回し、長いものは「…」で切る(行の幅は広げない)。
func _make_row(i: int, m: Dictionary) -> PanelContainer:
	var have: bool = bool(_have.get(m.md5, false))
	var card := UiStyle.card(84, func(): _select(i), func(): _play(i))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)
	# ランク(失敗は FAIL)
	var failed: bool = bool(m.failed)
	var rank := UiStyle.label("FAIL" if failed else str(m.rank), 28 if not failed else 18, UiStyle.DANGER if failed else UiStyle.rank_color(str(m.rank)), true)
	rank.custom_minimum_size = Vector2(64, 0)
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(rank)
	# 曲名 / 作者・難易度 / Lv・MOD
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 3)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(info)
	var title := UiStyle.label(str(m.title), 17, UiStyle.TEXT if have else UiStyle.TEXT_DIM, true)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.tooltip_text = str(m.title)
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	info.add_child(title)
	var by := UiStyle.label("%s  ·  %s" % [str(m.artist), str(m.diff)], 13, UiStyle.TEXT_DIM)
	by.clip_text = true
	by.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(by)
	var tags_clip := Control.new()   # Lv と MOD のタグ(多いときは、右を切る。行の幅は広げない)
	tags_clip.clip_contents = true
	tags_clip.custom_minimum_size = Vector2(0, 22)
	tags_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(tags_clip)
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 6)
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tags_clip.add_child(tags)
	tags.add_child(UiStyle.label("Lv %.2f" % float(m.level), 13, UiStyle.level_color(float(m.level)), true))
	for id in m.mods:
		var mod = Mods.find(str(id))
		if mod != null and not mod.is_empty():
			var chip := UiStyle.chip(str(mod.tag), mod.color)
			chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			tags.add_child(chip)
	if not have:
		tags.add_child(UiStyle.label("曲が見つかりません", 12, UiStyle.DANGER))
	# スコア / 被弾(失敗はどこまで) / 日時・長さ
	var sc := VBoxContainer.new()
	sc.custom_minimum_size = Vector2(170, 0)
	sc.alignment = BoxContainer.ALIGNMENT_CENTER
	sc.add_theme_constant_override("separation", 2)
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sc)
	var score_l := UiStyle.label(UiStyle.fmt(int(m.score)), 19, UiStyle.TEXT, true)
	score_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sc.add_child(score_l)
	var sub2 := UiStyle.label(("%d%% まで" % int(round(float(m.progress) * 100.0))) if failed else ("被弾 %d 回" % int(m.hits)), 12, UiStyle.TEXT_DIM)
	sub2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sc.add_child(sub2)
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(int(m.time) + bias)
	var secs := int(round(float(m.dur)))
	var date_l := UiStyle.label("%02d/%02d %02d:%02d  ·  %d:%02d" % [d.month, d.day, d.hour, d.minute, secs / 60, secs % 60], 12, UiStyle.TEXT_FAINT)
	date_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sc.add_child(date_l)
	# 操作: 大きな「再生」と、その下に小さな「保存」「削除」
	var act := VBoxContainer.new()
	act.alignment = BoxContainer.ALIGNMENT_CENTER
	act.add_theme_constant_override("separation", 4)
	act.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(act)
	var play := Button.new()
	play.text = "再生"
	play.focus_mode = Control.FOCUS_NONE
	play.custom_minimum_size = Vector2(140, 34)
	play.disabled = not have
	UiStyle.style_primary(play, false, 10, 4)
	play.pressed.connect(func(): _play(i))
	act.add_child(play)
	var small := HBoxContainer.new()
	small.add_theme_constant_override("separation", 4)
	act.add_child(small)
	var keep := Button.new()
	keep.text = "保存済み" if bool(m.keep) else "保存"
	keep.tooltip_text = "保存しておくと、古いリプレイの自動の整理で消えません"
	keep.toggle_mode = true
	keep.set_pressed_no_signal(bool(m.keep))
	keep.focus_mode = Control.FOCUS_NONE
	keep.custom_minimum_size = Vector2(68, 26)
	keep.add_theme_font_size_override("font_size", 12)
	keep.add_theme_stylebox_override("normal", UiStyle.box(Color(1, 1, 1, 0.06), UiStyle.LINE, 1, 4, 6, 2))
	keep.add_theme_stylebox_override("hover", UiStyle.box(Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.28), 1, 4, 6, 2))
	keep.add_theme_stylebox_override("pressed", UiStyle.box(Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.2), UiStyle.ACCENT, 1, 4, 6, 2))
	keep.pressed.connect(func(): _toggle_keep(i))
	small.add_child(keep)
	var del := Button.new()
	var confirming := str(m.name) == _del_name
	del.text = "本当に削除" if confirming else "削除"
	del.focus_mode = Control.FOCUS_NONE
	del.custom_minimum_size = Vector2(68, 26)
	del.add_theme_font_size_override("font_size", 12)
	del.add_theme_stylebox_override("normal", UiStyle.box(Color(1, 1, 1, 0.06), UiStyle.DANGER if confirming else UiStyle.LINE, 1, 4, 6, 2))
	del.add_theme_stylebox_override("hover", UiStyle.box(Color(1, 1, 1, 0.12), UiStyle.DANGER if confirming else Color(1, 1, 1, 0.28), 1, 4, 6, 2))
	if confirming:
		del.add_theme_color_override("font_color", UiStyle.DANGER)
	del.pressed.connect(func(): _delete(i))
	small.add_child(del)
	return card


func _play(i: int) -> void:
	if i < 0 or i >= _shown.size() or _closing:
		return
	if not bool(_have.get(_shown[i].md5, false)):
		UiSfx.play("deny")
		return
	UiSfx.play("confirm")
	replay_requested.emit(str(_shown[i].name))


func _toggle_keep(i: int) -> void:
	if i < 0 or i >= _shown.size():
		return
	var m: Dictionary = _shown[i]
	var on := not bool(m.keep)
	Replay.set_kept(str(m.name), on)
	for it in _items:
		if it.name == m.name:
			it["keep"] = on
	UiSfx.play("confirm" if on else "select")
	_rebuild()


func _delete(i: int) -> void:
	if i < 0 or i >= _shown.size():
		return
	var name := str(_shown[i].name)
	if _del_name != name:   # 1 度目: 確認待ち(2.5 秒で戻る)
		_del_name = name
		UiSfx.play("select")
		_rebuild()
		_del_timer = get_tree().create_timer(2.5)
		_del_timer.timeout.connect(func():
			if _del_name == name:
				_del_name = ""
				_rebuild())
		return
	_del_name = ""
	Replay.remove(name)
	_items = _items.filter(func(m): return m.name != name)
	UiSfx.play("close")
	_rebuild()


func close_panel() -> void:
	if _closing:
		return
	_closing = true
	UiSfx.play("close")
	if not UiStyle.animate:
		closed.emit()
		return
	_panel.pivot_offset = _panel.size * 0.5
	var t := create_tween().set_parallel(true)
	t.tween_property(_dim, "color:a", 0.0, 0.18)
	t.tween_property(_panel, "modulate:a", 0.0, 0.16)
	t.tween_property(_panel, "scale", Vector2(0.96, 0.96), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(func(): closed.emit())


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed) or _closing:
		return
	match event.keycode:
		KEY_ESCAPE:
			if not event.echo:
				close_panel()
		KEY_UP:
			_select(_sel - 1, true)
		KEY_DOWN:
			_select(_sel + 1, true)
		KEY_ENTER, KEY_KP_ENTER:
			if not event.echo:
				_play(_sel)
		KEY_S:
			if not event.echo:
				_toggle_keep(_sel)
		KEY_DELETE:
			if not event.echo:
				_delete(_sel)
		_:
			return
	get_viewport().set_input_as_handled()
