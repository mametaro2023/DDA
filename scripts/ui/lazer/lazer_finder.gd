extends Control
## lazer 風の選曲画面の「探す」タブ: osu! の曲を探して(osu.direct。beatmap_search.gd)、そのままダウンロードする。
## 上に検索欄・並び順(人気 / 新着 / お気に入り)・絞り込み(ランク済み / Loved / すべて)、下に曲のカードを 2 列で並べる(下までスクロールすると続きを読む)。
## 検索欄が空のときは、並び順どおりの一覧(初めは ranked の人気順 = おすすめ)。
## カードの右のボタン: 取得 → 待機中 / 45% → 遊ぶ(入っている曲。押すと「ソロ」へ戻ってその曲を選ぶ)/ 再試行。ダウンロードと同意の確認は main が行う。

signal download_requested(set_id: int, label: String)
signal play_requested(path: String)
signal closed
## 試聴が流れ始めた(true)・止まった(false)。選曲画面が、自分の曲を小さくするのに使う
signal preview_changed(on: bool)

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerButton = preload("res://scripts/ui/lazer/lazer_button.gd")
const LazerChrome = preload("res://scripts/ui/lazer/lazer_chrome.gd")
const LazerIcons = preload("res://scripts/ui/lazer/lazer_icons.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const SmoothScroll = preload("res://scripts/ui/smooth_scroll.gd")
const BeatmapSearch = preload("res://scripts/beatmap_search.gd")
const UiFx = preload("res://scripts/ui/ui_fx.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const Volume = preload("res://scripts/volume.gd")

const TOP := LazerChrome.TOOLBAR_H
const CARD_W := 598.0
const CARD_H := 92.0
const GAP := 12
const MARGIN := 36.0
const BTN_W := 104.0
const DEBOUNCE := 0.45        # 入力が止まってから検索するまでの秒数
const MORE_AHEAD := 400.0     # 下端までこれだけ近づいたら、続きを読む(px)
const PREVIEW_DB := -6.0       # 試聴の音量(音楽の音量とは別に、音楽バスの音量が効く)
const PREVIEW_FADE := 0.14    # 試聴の入り・切れのフェード(秒)
const SKEL_ROWS := 6          # 読み込み中の仮カードの行数

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
var _skel: Control             # 読み込み中の仮カード(光の帯が流れる)
var _skel_tw: Tween
var _pv_player: AudioStreamPlayer
var _pv_id := 0               # 試聴を押した曲(0 = なし)
var _pv_state := ""           # "loading" | "playing"
var _pv_tw: Tween
var _ducked := false
var _dl_cards := {}           # ダウンロード中の曲(set_id → true)。進捗の棒をなめらかに動かす


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
			if UiStyle.animate:   # ジャケットは、取れたらふわっと現れる
				c.set_meta("cover_a", 0.0)
				UiStyle.tween_value(c, 0.0, 1.0, 0.3, func(v: float):
					if is_instance_valid(c):
						c.set_meta("cover_a", v)
						c.queue_redraw())
			c.queue_redraw())
	search.preview_ready.connect(_on_preview_ready)
	search.preview_failed.connect(_on_preview_failed)
	_pv_player = AudioStreamPlayer.new()
	Volume.route_music(_pv_player)   # 音楽バスへ(「音楽」の音量が効く)
	_pv_player.finished.connect(func(): if _pv_state == "playing": _stop_preview())
	add_child(_pv_player)
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
	_skel = Control.new()
	_skel.position = _scroll.position
	_skel.size = _scroll.size
	_skel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skel.visible = false
	_skel.draw.connect(_draw_skeleton)
	add_child(_skel)
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
		_stop_preview()
		_dl_cards.clear()
		search.drop_pending_covers()
		for c in _grid.get_children():
			_grid.remove_child(c)
			c.queue_free()
		_cards.clear()
		_items.clear()
		_scroll.scroll_vertical = 0
	_loading = true
	_more = false
	_set_note("")
	_retry.visible = false
	if not more:
		_show_skeleton(true)
	_req = search.search(_query.text, _sort, _status, _items.size())


func _on_results(req: int, items: Array, more: bool) -> void:
	if req != _req:
		return
	_loading = false
	_more = more
	_show_skeleton(false)
	var k := 0
	for it in items:
		if _cards.has(int(it.id)):
			continue
		_items.append(it)
		var c := _make_card(it)
		_grid.add_child(c)
		_cards[int(it.id)] = c
		if UiStyle.animate:   # カードが、順に少し弾んで現れる(最初の数枚だけ時間差。あとは続けて)
			var delay := minf(k * 0.035, 0.42)
			c.modulate.a = 0.0
			c.scale = Vector2(0.94, 0.94)
			UiStyle.tween(c, "modulate:a", 0.0, 1.0, 0.25, delay)
			UiStyle.spring(c, "scale", Vector2(0.94, 0.94), Vector2.ONE, 0.45, delay)
		k += 1
	_set_note("" if not _items.is_empty() else "見つかりませんでした")


func _on_failed(req: int, msg: String) -> void:
	if req != _req:
		return
	_loading = false
	_show_skeleton(false)
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
	if _skel.visible:
		_skel.queue_redraw()
	if _pv_id != 0:   # 試聴中のカードは、回る輪・棒・進みを毎フレーム描き直す
		var pc = _cards.get(_pv_id)
		if pc != null and is_instance_valid(pc):
			pc.queue_redraw()
	for id in _dl_cards.keys():   # ダウンロードの棒は、目標へなめらかに近づく
		var dc = _cards.get(id)
		if dc == null or not is_instance_valid(dc):
			_dl_cards.erase(id)
			continue
		var cur := float(dc.get_meta("dl_a", 0.0))
		var to := float(dc.get_meta("dl_to", 0.0))
		if not UiStyle.animate:
			cur = to
		else:
			cur = move_toward(cur, to, maxf(absf(to - cur), 0.02) * minf(1.0, delta * 10.0))
		dc.set_meta("dl_a", cur)
		dc.queue_redraw()
		if is_equal_approx(cur, to) and str(dc.get_meta("st", "")) != "downloading":
			_dl_cards.erase(id)


func _exit_tree() -> void:
	_set_duck(false)


## Esc: 入力中なら入力を終える。そうでなければ閉じる。
func handle_escape() -> void:
	if _query.has_focus():
		_query.release_focus()
	else:
		closed.emit()


## ダウンロードの状態が変わった(main → 選曲画面 → ここ)。
func refresh_state(set_id: int) -> void:
	var c = _cards.get(set_id)
	if c == null or not is_instance_valid(c):
		return
	var s: Dictionary = states.get(set_id, {})
	var st := str(s.get("state", ""))
	var prev := str(c.get_meta("st", ""))
	c.set_meta("st", st)
	if st == "downloading" or st == "queued":
		c.set_meta("dl_to", float(s.get("frac", 0.0)))
		_dl_cards[set_id] = true
	elif st == "done" and prev != "done":   # 取れた: ボタンが緑の「遊ぶ」になり、輪と粒が広がる
		c.set_meta("dl_to", 1.0)
		_dl_cards[set_id] = true
		var b: Control = c.get_meta("btn")
		var at := b.get_global_rect().get_center() - global_position
		UiFx.ring(self, at, LazerStyle.GREEN, 16.0, 90.0, 0.55, 2.5)
		UiFx.burst(self, at, LazerStyle.GREEN, 12, 190.0, 0.55, 3.0)
	_sync_button(c)


# --- カード ---

func _make_card(it: Dictionary) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(CARD_W, CARD_H)
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.set_meta("item", it)
	c.draw.connect(func(): _draw_card(c))
	c.pivot_offset = c.custom_minimum_size * 0.5
	c.set_meta("st", str((states.get(int(it.id), {}) as Dictionary).get("state", "")))
	c.mouse_entered.connect(func(): c.set_meta("hover", true); c.queue_redraw())
	c.mouse_exited.connect(func():
		c.set_meta("hover", false)
		c.queue_redraw())
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND   # 押すと試聴(右のボタンの上は、ボタンの矢印)
	c.gui_input.connect(func(ev: InputEvent): _card_input(c, ev))
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
	var cr := _cover_rect()
	var ca := float(c.get_meta("cover_a", 1.0))
	if tex == null or ca < 1.0:
		c.draw_rect(cr, LazerStyle.title_color(str(it.title)).darkened(0.55))
	if tex != null:
		c.draw_texture_rect(tex, cr, false, Color(1, 1, 1, ca))
	_draw_preview_overlay(c, it, cr)
	if str(c.get_meta("st", "")) == "downloading":   # ダウンロードの進み(カードの下端の棒)
		var bx := cr.end.x + 14.0
		var bw := w - bx - 12.0
		c.draw_rect(Rect2(bx, h - 7.0, bw, 3.0), Color(1, 1, 1, 0.08))
		c.draw_rect(Rect2(bx, h - 7.0, bw * clampf(float(c.get_meta("dl_a", 0.0)), 0.0, 1.0), 3.0), LazerStyle.PINK)
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


# --- 試聴(ジャケットを押すと流れる) ---

static func _cover_rect() -> Rect2:
	return Rect2(8, 8, CARD_H - 16.0, CARD_H - 16.0)


func _card_input(c: Control, ev: InputEvent) -> void:
	# 右のボタンの上は、ボタンが受ける(ここには届かない)。それ以外のカードのどこを押しても、試聴
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			c.set_meta("press_at", ev.position)
		elif c.has_meta("press_at"):
			var moved := (c.get_meta("press_at") as Vector2).distance_to(ev.position)
			c.remove_meta("press_at")
			if moved < 6.0:   # ドラッグ(一覧のスクロール)ではなく、押した
				toggle_preview(int((c.get_meta("item") as Dictionary).id))
				c.accept_event()


## その曲の試聴を流す。いま流している曲なら止める。
func toggle_preview(set_id: int) -> void:
	if _pv_id == set_id:
		_stop_preview()
		return
	_stop_preview(true)
	_pv_id = set_id
	_pv_state = "loading"
	UiSfx.play("select")
	_redraw_card(set_id)
	search.fetch_preview(set_id)


func _on_preview_ready(set_id: int, stream: AudioStream) -> void:
	if set_id != _pv_id:
		return
	_pv_state = "playing"
	_set_duck(true)
	if _pv_tw != null:
		_pv_tw.kill()
	_pv_player.stream = stream
	_pv_player.volume_db = -40.0 if UiStyle.animate else PREVIEW_DB
	_pv_player.play()
	if UiStyle.animate:
		_pv_tw = _pv_player.create_tween()
		_pv_tw.tween_property(_pv_player, "volume_db", PREVIEW_DB, PREVIEW_FADE * 2.0)
	_redraw_card(set_id)


func _on_preview_failed(set_id: int) -> void:
	if set_id != _pv_id:
		return
	_pv_id = 0
	_pv_state = ""
	_set_duck(false)
	var c = _cards.get(set_id)
	if c != null and is_instance_valid(c):
		c.set_meta("pv_msg", true)   # 「プレビューなし」を、しばらくカードに出す
		c.queue_redraw()
		get_tree().create_timer(2.5).timeout.connect(func():
			if is_instance_valid(c):
				c.set_meta("pv_msg", false)
				c.queue_redraw())


## 試聴を止める(小さくして止める)。switching = true: すぐ別の曲の試聴を始めるので、選曲画面の曲は小さいままにする。
func _stop_preview(switching := false) -> void:
	if _pv_id == 0:
		return
	var old := _pv_id
	var was_playing := _pv_state == "playing"
	search.cancel_preview()
	_pv_id = 0
	_pv_state = ""
	if was_playing:
		if _pv_tw != null:
			_pv_tw.kill()
		if UiStyle.animate and is_inside_tree():
			_pv_tw = _pv_player.create_tween()
			_pv_tw.tween_property(_pv_player, "volume_db", -40.0, PREVIEW_FADE)
			_pv_tw.tween_callback(_pv_player.stop)
		else:
			_pv_player.stop()
	if not switching:
		_set_duck(false)
	_redraw_card(old)


## 閉じる前に呼ぶ: 試聴を、フェードして止める。
func stop_preview() -> void:
	_stop_preview()


func _set_duck(on: bool) -> void:
	if on != _ducked:
		_ducked = on
		preview_changed.emit(on)


func _redraw_card(set_id: int) -> void:
	var c = _cards.get(set_id)
	if c != null and is_instance_valid(c):
		c.queue_redraw()


## ジャケットの上: マウスを乗せると ▶、読み込み中は回る輪、流れている間は ❚❚・棒(イコライザー風)・進みの線
func _draw_preview_overlay(c: Control, it: Dictionary, cr: Rect2) -> void:
	var active := int(it.id) == _pv_id
	var over := bool(c.get_meta("hover", false))   # カードにマウスを乗せている(右のボタンの上は含まない)
	var ctr := cr.get_center()
	var t := Time.get_ticks_msec() / 1000.0
	if active or over:
		c.draw_rect(cr, Color(0, 0, 0, 0.5 if active else 0.38))
		if active and _pv_state == "loading":
			c.draw_arc(ctr, 13.0, t * 5.0, t * 5.0 + PI * 1.3, 24, Color(1, 1, 1, 0.9), 2.5, true)
		elif active:
			c.draw_rect(Rect2(ctr.x - 8.0, ctr.y - 9.0, 5.0, 18.0), Color.WHITE)
			c.draw_rect(Rect2(ctr.x + 3.0, ctr.y - 9.0, 5.0, 18.0), Color.WHITE)
		else:
			c.draw_colored_polygon(PackedVector2Array([ctr + Vector2(-6, -10), ctr + Vector2(10, 0), ctr + Vector2(-6, 10)]), Color.WHITE)
	if active and _pv_state == "playing":
		for k in range(4):   # 棒は、音そのものではなく、ゆるやかに伸び縮みする飾り
			var hh := 5.0 + 9.0 * (0.5 + 0.5 * sin(t * (4.1 + k * 1.3) + k * 1.7))
			c.draw_rect(Rect2(cr.position.x + 6.0 + k * 7.0, cr.end.y - 8.0 - hh, 4.0, hh), Color(LazerStyle.PINK.r, LazerStyle.PINK.g, LazerStyle.PINK.b, 0.95))
		var plen := _pv_player.stream.get_length() if _pv_player.stream != null else 0.0
		if plen > 0.0:
			var frac := clampf(_pv_player.get_playback_position() / plen, 0.0, 1.0)
			c.draw_rect(Rect2(cr.position.x, cr.end.y - 3.0, cr.size.x, 3.0), Color(0, 0, 0, 0.5))
			c.draw_rect(Rect2(cr.position.x, cr.end.y - 3.0, cr.size.x * frac, 3.0), LazerStyle.PINK)
	if bool(c.get_meta("pv_msg", false)):
		c.draw_rect(cr, Color(0, 0, 0, 0.6))
		c.draw_string(LazerStyle.font(), Vector2(cr.position.x, ctr.y + 5.0), "なし", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 13, LazerStyle.TEXT_DIM)


# --- 読み込み中の仮カード ---

func _show_skeleton(on: bool) -> void:
	if _skel_tw != null:
		_skel_tw.kill()
	if on:
		_skel.modulate.a = 1.0
		_skel.visible = true
	elif _skel.visible:
		if UiStyle.animate and is_inside_tree():
			_skel_tw = _skel.create_tween()
			_skel_tw.tween_property(_skel, "modulate:a", 0.0, 0.18)
			_skel_tw.tween_callback(func(): _skel.visible = false)
		else:
			_skel.visible = false


func _draw_skeleton() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for r in range(SKEL_ROWS):
		for col in range(2):
			var o := Vector2(col * (CARD_W + GAP), r * (CARD_H + 10.0))
			_skel.draw_style_box(LazerStyle.box(Color(1, 1, 1, 0.04), LazerStyle.LINE, 1, 10), Rect2(o, Vector2(CARD_W, CARD_H)))
			_skel.draw_rect(Rect2(o + Vector2(8, 8), Vector2(CARD_H - 16, CARD_H - 16)), Color(1, 1, 1, 0.05))
			var x := o.x + CARD_H + 6.0
			_skel.draw_rect(Rect2(x, o.y + 16.0, 260.0 - col * 40.0 + (r % 3) * 30.0, 14.0), Color(1, 1, 1, 0.06))
			_skel.draw_rect(Rect2(x, o.y + 38.0, 180.0 + (r % 2) * 60.0, 10.0), Color(1, 1, 1, 0.045))
			_skel.draw_rect(Rect2(x, o.y + 62.0, 120.0, 10.0), Color(1, 1, 1, 0.04))
			# 光の帯が、左から右へ流れる(行ごとに少しずれて、波のように)
			var u := fposmod(t * 0.7 - r * 0.10 - col * 0.05, 1.7) - 0.35
			var bx := o.x + u * (CARD_W + 80.0)
			var band := PackedVector2Array([Vector2(bx + 40.0, o.y), Vector2(bx + 110.0, o.y), Vector2(bx + 70.0, o.y + CARD_H), Vector2(bx, o.y + CARD_H)])
			var card := PackedVector2Array([o, o + Vector2(CARD_W, 0), o + Vector2(CARD_W, CARD_H), o + Vector2(0, CARD_H)])
			for part in Geometry2D.intersect_polygons(card, band):
				if _area(part) > 4.0:   # 端にかかって潰れた形は、描かない(三角形に分けられない)
					_skel.draw_colored_polygon(part, Color(1, 1, 1, 0.06))


static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(p.size()):
		var q := p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return absf(a) * 0.5
