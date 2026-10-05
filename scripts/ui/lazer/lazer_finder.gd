extends Control
## lazer 風の選曲画面の「探す」タブ: osu! の曲を探して(osu.direct。beatmap_search.gd)、そのままダウンロードする。
## 上に検索欄・並び順(人気 / 新着 / お気に入り)・絞り込み(ランク済み / Loved / すべて)、下に曲のカードを 2 列で並べる(下までスクロールすると続きを読む)。
## 検索欄が空のときは、並び順どおりの一覧(初めは ranked の人気順 = おすすめ)。
## カードの右のボタン: 取得 → 待機中 / 45% → 遊ぶ(入っている曲。押すと「ソロ」へ戻ってその曲を選ぶ)/ 再試行。ダウンロードと同意の確認は main が行う。

signal download_requested(set_id: int, label: String)
signal play_requested(path: String)
signal closed

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerButton = preload("res://scripts/ui/lazer/lazer_button.gd")
const LazerChrome = preload("res://scripts/ui/lazer/lazer_chrome.gd")
const LazerIcons = preload("res://scripts/ui/lazer/lazer_icons.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const SmoothScroll = preload("res://scripts/ui/smooth_scroll.gd")
const BeatmapSearch = preload("res://scripts/beatmap_search.gd")

const TOP := LazerChrome.TOOLBAR_H
const CARD_W := 598.0
const CARD_H := 92.0
const GAP := 12
const MARGIN := 36.0
const BTN_W := 104.0
const DEBOUNCE := 0.45        # 入力が止まってから検索するまでの秒数
const MORE_AHEAD := 400.0     # 下端までこれだけ近づいたら、続きを読む(px)

## 曲の ID → ダウンロードの状態(main の fetch_states と同じ辞書)
var states: Dictionary = {}
## 入っている曲のパス(なければ空)を返す: func(item: Dictionary) -> String
var owned_cb: Callable

var search: BeatmapSearch
var _query: LineEdit
var _sort := "plays"
var _status := "ranked"
var _sort_btns := {}
var _status_btns := {}
var _scroll: ScrollContainer
var _grid: GridContainer
var _note: Label
var _retry: LazerButton
var _cards := {}              # set_id → カード
var _items: Array = []
var _req := -1
var _more := false
var _loading := false
var _debounce := -1.0


func _ready() -> void:
	position = Vector2(0, TOP)
	size = Vector2(LazerChrome.SIZE_PX.x, LazerChrome.SIZE_PX.y - TOP)
	mouse_filter = Control.MOUSE_FILTER_STOP   # 下の選曲画面には、クリックを通さない
	var bg := ColorRect.new()
	bg.color = Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 1.0)   # 下の選曲画面は見せない(文字が透けると読みにくい)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	search = BeatmapSearch.new()
	add_child(search)
	search.results.connect(_on_results)
	search.failed.connect(_on_failed)
	search.cover_ready.connect(func(id: int, _t: Texture2D):
		var c = _cards.get(id)
		if c != null and is_instance_valid(c):
			c.queue_redraw())
	_build_bar()
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(MARGIN, 64)
	_scroll.size = Vector2(size.x - MARGIN * 2.0 + 14.0, size.y - 64 - LazerChrome.FOOTER_H - 4)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	SmoothScroll.attach(_scroll, true)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", GAP)
	_grid.add_theme_constant_override("v_separation", 10)
	_scroll.add_child(_grid)
	_note = LazerStyle.label("", 17, LazerStyle.TEXT_MUTE)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.position = Vector2(0, 250)
	_note.size = Vector2(size.x, 30)
	add_child(_note)
	_retry = LazerButton.new("もう一度", LazerStyle.PANEL, "retry", LazerStyle.TEXT)
	_retry.font_size = 15
	_retry.position = Vector2(size.x * 0.5 - 80.0, 292)
	_retry.size = Vector2(160, 42)
	_retry.visible = false
	_retry.pressed.connect(func(): _run(false))
	add_child(_retry)
	var footer := LazerChrome.build_footer(self)
	footer.position.y -= TOP
	var back := LazerChrome.footer_button(footer, "戻る", LazerStyle.PINK, "back", 0, 168, func(): closed.emit())
	back.set_meta("juice_sound", "back")
	if UiStyle.animate:
		modulate.a = 0.0
		UiStyle.tween(self, "modulate:a", 0.0, 1.0, 0.18)
	_run(false)


func _build_bar() -> void:
	_query = LineEdit.new()
	_query.placeholder_text = "osu! の曲を検索…"
	_query.clear_button_enabled = true
	_query.max_length = 80
	_query.focus_mode = Control.FOCUS_CLICK
	_query.position = Vector2(MARGIN, 14)
	_query.size = Vector2(440, 38)
	for st in [["normal", Color(1, 1, 1, 0.08), LazerStyle.LINE], ["focus", Color(1, 1, 1, 0.12), LazerStyle.PINK]]:
		_query.add_theme_stylebox_override(st[0], LazerStyle.box(st[1], st[2], 1, 10, 14, 8))
	_query.text_changed.connect(func(_t: String): _debounce = DEBOUNCE)
	_query.text_submitted.connect(func(_t: String):
		_debounce = -1.0
		_query.release_focus()
		_run(false))
	add_child(_query)
	var x := MARGIN + 440.0 + 22.0
	for s in [["plays", "人気"], ["new", "新着"], ["favs", "お気に入り"]]:
		x = _chip(x, str(s[1]), _sort_btns, str(s[0]), func(id: String): _sort = id) + 6.0
	x += 16.0
	for s in [["ranked", "ランク済み"], ["loved", "Loved"], ["all", "すべて"]]:
		x = _chip(x, str(s[1]), _status_btns, str(s[0]), func(id: String): _status = id) + 6.0
	_sync_chips()


## 並び順・絞り込みの札(押すと、すぐ探し直す)。返り値は右端の x。
func _chip(x: float, text: String, group: Dictionary, id: String, pick: Callable) -> float:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.position = Vector2(x, 17)
	b.size = Vector2(maxf(64.0, LazerStyle.font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 30.0), 32)
	b.pressed.connect(func():
		pick.call(id)
		_sync_chips()
		_run(false))
	add_child(b)
	group[id] = b
	return x + b.size.x


func _sync_chips() -> void:
	for grp in [[_sort_btns, _sort], [_status_btns, _status]]:
		for id in grp[0]:
			var b: Button = grp[0][id]
			var on: bool = id == grp[1]
			var sb := LazerStyle.box(LazerStyle.PINK if on else Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 0, 999, 12, 4)
			for st in ["normal", "hover", "pressed", "hover_pressed"]:
				b.add_theme_stylebox_override(st, sb)
			var ink := Color(0.16, 0.05, 0.10) if on else LazerStyle.TEXT_DIM
			for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
				b.add_theme_color_override(c, ink)


## 探す(more = true なら、いまの一覧の続き)。
func _run(more: bool) -> void:
	if more and (_loading or not _more):
		return
	if not more:
		search.drop_pending_covers()
		for c in _grid.get_children():
			_grid.remove_child(c)
			c.queue_free()
		_cards.clear()
		_items.clear()
		_scroll.scroll_vertical = 0
	_loading = true
	_more = false
	_set_note("読み込み中…" if not more else "")
	_retry.visible = false
	_req = search.search(_query.text, _sort, _status, _items.size())


func _on_results(req: int, items: Array, more: bool) -> void:
	if req != _req:
		return
	_loading = false
	_more = more
	for it in items:
		if _cards.has(int(it.id)):
			continue
		_items.append(it)
		var c := _make_card(it)
		_grid.add_child(c)
		_cards[int(it.id)] = c
	_set_note("" if not _items.is_empty() else "見つかりませんでした")


func _on_failed(req: int, msg: String) -> void:
	if req != _req:
		return
	_loading = false
	if _items.is_empty():
		_set_note(msg + "(osu.direct)")
		_retry.visible = true
	else:
		_more = true   # 続きを読めなかった: 次にスクロールしたとき、もう一度試す


func _set_note(t: String) -> void:
	_note.text = t
	_note.visible = t != ""


func _process(delta: float) -> void:
	if _debounce >= 0.0:
		_debounce -= delta
		if _debounce < 0.0:
			_run(false)
	if _more and not _loading and _scroll != null:
		var bar := _scroll.get_v_scroll_bar()
		if bar.max_value - bar.page - _scroll.scroll_vertical < MORE_AHEAD:
			_run(true)


## Esc: 入力中なら入力を終える。そうでなければ閉じる。
func handle_escape() -> void:
	if _query.has_focus():
		_query.release_focus()
	else:
		closed.emit()


## ダウンロードの状態が変わった(main → 選曲画面 → ここ)。
func refresh_state(set_id: int) -> void:
	var c = _cards.get(set_id)
	if c != null and is_instance_valid(c):
		_sync_button(c)


# --- カード ---

func _make_card(it: Dictionary) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(CARD_W, CARD_H)
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.set_meta("item", it)
	c.draw.connect(func(): _draw_card(c))
	c.mouse_entered.connect(func(): c.set_meta("hover", true); c.queue_redraw())
	c.mouse_exited.connect(func(): c.set_meta("hover", false); c.queue_redraw())
	var b := LazerButton.new("", LazerStyle.PINK, "download")
	b.font_size = 15
	b.slant = 10.0
	b.position = Vector2(CARD_W - BTN_W - 12.0, (CARD_H - 40.0) * 0.5)
	b.size = Vector2(BTN_W, 40)
	b.pressed.connect(func(): _on_button(c))
	c.add_child(b)
	c.set_meta("btn", b)
	_sync_button(c)
	return c


func _owned_path(it: Dictionary) -> String:
	var s: Dictionary = states.get(int(it.id), {})
	if str(s.get("state", "")) == "done":
		return str(s.get("path", ""))
	return str(owned_cb.call(it)) if owned_cb.is_valid() else ""


func _sync_button(c: Control) -> void:
	var it: Dictionary = c.get_meta("item")
	var b: LazerButton = c.get_meta("btn")
	var s: Dictionary = states.get(int(it.id), {})
	var st := str(s.get("state", ""))
	var look := ["取得", LazerStyle.PINK, "download", Color(0.16, 0.05, 0.10), false]
	if st == "queued":
		look = ["待機中", LazerStyle.PANEL, "clock", LazerStyle.TEXT_DIM, true]
	elif st == "downloading":
		look = ["%d%%" % roundi(float(s.get("frac", 0.0)) * 100.0), LazerStyle.PANEL, "download", LazerStyle.TEXT, true]
	elif _owned_path(it) != "":
		look = ["遊ぶ", LazerStyle.GREEN, "play", Color(0.08, 0.16, 0.02), false]
	elif st == "failed":
		look = ["再試行", LazerStyle.RED, "retry", Color(0.16, 0.03, 0.07), false]
	b.caption = look[0]
	b.color = look[1]
	b.icon_kind = look[2]
	b.ink = look[3]
	b.disabled = look[4]
	b.tooltip_text = str(s.get("error", "")) if st == "failed" else ""
	b.queue_redraw()


func _on_button(c: Control) -> void:
	var it: Dictionary = c.get_meta("item")
	var path := _owned_path(it)
	if path != "":
		play_requested.emit(path)
		return
	download_requested.emit(int(it.id), "%s - %s" % [it.artist, it.title])


func _draw_card(c: Control) -> void:
	var it: Dictionary = c.get_meta("item")
	var hover: bool = c.get_meta("hover", false)
	var w := c.size.x
	var h := c.size.y
	c.draw_style_box(LazerStyle.box(Color(1, 1, 1, 0.10 if hover else 0.06), LazerStyle.PINK if hover else LazerStyle.LINE, 1, 10), Rect2(0, 0, w, h))
	var tex := search.cover(int(it.id), str(it.cover))
	var cr := Rect2(8, 8, h - 16, h - 16)
	if tex != null:
		c.draw_texture_rect(tex, cr, false)
	else:
		c.draw_rect(cr, LazerStyle.title_color(str(it.title)).darkened(0.55))
	var f := LazerStyle.font()
	var fb := LazerStyle.font_bold()
	var x := cr.end.x + 14.0
	var tw := w - x - BTN_W - 28.0
	c.draw_string(fb, Vector2(x, 28), LazerStyle.fit(fb, str(it.title), 17, tw), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, LazerStyle.TEXT)
	c.draw_string(f, Vector2(x, 48), LazerStyle.fit(f, "%s  ·  %s" % [it.artist, it.creator], 13, tw), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, LazerStyle.TEXT_DIM)
	# 下の段: 難易度の色の点(易しい順)・★の幅・長さ・プレイ回数
	var stars: Array = it.stars
	var dx := x
	for k in range(mini(stars.size(), 12)):
		c.draw_circle(Vector2(dx + 5.0, 70.0), 5.0, LazerStyle.star_color(float(stars[k])))
		dx += 13.0
	if stars.size() > 12:
		c.draw_string(f, Vector2(dx, 75), "+%d" % (stars.size() - 12), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LazerStyle.TEXT_MUTE)
		dx += 26.0
	var lo := float(stars[0])
	var hi := float(stars[stars.size() - 1])
	var meta := "★%.1f" % lo if is_equal_approx(lo, hi) or stars.size() == 1 else "★%.1f–%.1f" % [lo, hi]
	meta += "   %d:%02d" % [int(it.length) / 60, int(it.length) % 60]
	if int(it.plays) > 0:
		meta += "   ▶ %s" % _short(int(it.plays))
	c.draw_string(f, Vector2(dx + 8.0, 75), LazerStyle.fit(f, meta, 13, x + tw - dx - 8.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, LazerStyle.TEXT_MUTE)


static func _short(n: int) -> String:
	if n >= 1000000:
		return "%.1fM" % (n / 1000000.0)
	if n >= 1000:
		return "%.1fK" % (n / 1000.0)
	return str(n)
