extends Control
## マルチプレイの画面。入口(部屋を作る / 招待コードで入る)→ ロビー(参加者・モード・曲・開始)。
## 状態はすべて通信層(net.gd)が持ち、この画面はそれを描いて、操作を net に伝えるだけ。ゲームが始まると main が画面を切り替える。
##
## 操作: Esc で戻る(ロビーでは部屋を出る)。マウスでも全部できる。

signal back_requested        # 入口から、タイトルへ
signal pick_song_requested   # ホスト: 曲・MOD の選択画面へ

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const Settings = preload("res://scripts/settings.gd")
const Mods = preload("res://scripts/mods.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Volume = preload("res://scripts/volume.gd")
const Ambient = preload("res://scripts/ui/ambient.gd")
const SongLibrary = preload("res://scripts/song_library.gd")
const MpGame = preload("res://scripts/net/mp_game.gd")
const SongDownload = preload("res://scripts/song_download.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const UiFx = preload("res://scripts/ui/ui_fx.gd")

const BG_TINT := Color(0.3, 0.3, 0.36)
const MODES := [["versus", "対戦"], ["coop", "協力"]]

var net
var notice := ""
var settings: Dictionary = {}

var _page := ""
var _content: Control
var _bg_holder: Control
var _bg: TextureRect
var _audio: AudioStreamPlayer
var _name_edit: LineEdit
var _code_edit: LineEdit
var _status: Label
var _busy := false
var _t := 0.0
var _resolve_t := 0.0
var _ping_labels: Dictionary = {}
var _preview_md5 := ""
var _dl: Node                       # 曲のダウンロード(必要になったときに作る)
var _dl_frac := 0.0
var _dl_text := ""
var _dl_error := ""
var _dl_bar: ProgressBar
var _dl_label: Label
var _ambient: Node2D
var _par := Vector2.ZERO
var _lobby_built := false         # ロビーを作ったことがあるか(最初だけ入場の動き。作り直しのたびには動かさない)
var _known_ids: Dictionary = {}  # 見えている参加者(新しく入った人・出た人で、音を鳴らす)


func setup(p_net, p_notice := "") -> void:
	net = p_net
	notice = p_notice


func _ready() -> void:
	settings = Settings.load_all()
	if str(settings.player_name) == "":
		settings.player_name = "PLAYER%03d" % (randi() % 1000)
		Settings.save_all(settings)
	theme = UiStyle.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiStyle.backdrop(self)
	_bg_holder = Control.new()
	_bg_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_holder)
	_bg = TextureRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.modulate = Color(BG_TINT.r, BG_TINT.g, BG_TINT.b, 0.0)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_holder.add_child(_bg)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.025, 0.05, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_ambient = Ambient.new()
	add_child(_ambient)
	_audio = AudioStreamPlayer.new()
	Volume.route_music(_audio)   # 音楽バスへ(ホイールなどの「音楽」の音量が効く)
	_audio.volume_db = -6.0
	add_child(_audio)
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)

	net.joined.connect(_on_joined)
	net.join_failed.connect(_on_join_failed)
	net.left.connect(_on_left)
	net.roster_changed.connect(_on_state_changed)
	net.room_changed.connect(_on_state_changed)
	net.code_changed.connect(_on_state_changed)
	if net.is_active():
		_show_lobby()
	else:
		_show_entry()


func _exit_tree() -> void:
	if net == null:
		return
	for pair in [[net.joined, _on_joined], [net.join_failed, _on_join_failed], [net.left, _on_left],
			[net.roster_changed, _on_state_changed], [net.room_changed, _on_state_changed], [net.code_changed, _on_state_changed]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])


func _clear_content() -> void:
	for c in _content.get_children():
		c.queue_free()
		_content.remove_child(c)
	_ping_labels.clear()
	_name_edit = null
	_code_edit = null
	_status = null


func _place(c: Control, x: float, y: float, w: float, h: float) -> Control:
	c.position = Vector2(x, y)
	c.size = Vector2(w, h)
	_content.add_child(c)
	return c


func _header(back_text: String, on_back: Callable) -> void:
	_place(UiStyle.label("MULTIPLAYER", 30, UiStyle.ACCENT, true), 36, 20, 400, 40)
	_place(UiStyle.caption("ONLINE / LAN"), 38, 62, 300, 16)
	var back := Button.new()
	back.text = back_text
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(on_back)
	_place(back, 1044, 24, 124, 34)   # 右上の「設定」(main のボタン)と並べる


func _panel(x: float, y: float, w: float, h: float, alpha := 0.04) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.box(Color(1, 1, 1, alpha), UiStyle.LINE, 1, 8, 22, 18))
	_place(p, x, y, w, h)
	return p


func _button(text: String, on_press: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if primary:
		b.add_theme_stylebox_override("normal", UiStyle.box(Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.9), Color(0, 0, 0, 0), 0, 4, 16, 8))
		b.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.ACCENT, Color(0, 0, 0, 0), 0, 4, 16, 8))
		b.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.ACCENT, Color(0, 0, 0, 0), 0, 4, 16, 8))
		b.add_theme_stylebox_override("disabled", UiStyle.box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 4, 16, 8))
		for k in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(k, Color(0.02, 0.06, 0.1))
		b.add_theme_color_override("font_disabled_color", UiStyle.TEXT_FAINT)
		b.add_theme_font_override("font", UiStyle.bold())
	b.pressed.connect(on_press)
	return b


# --- 入口 ---

func _show_entry(msg := "") -> void:
	_page = "entry"
	_lobby_built = false
	_known_ids.clear()
	_busy = false
	_clear_content()
	if msg != "":
		notice = msg
	_header("◀  タイトル", func(): back_requested.emit())
	# 名前
	_place(UiStyle.caption("NAME"), 152, 122, 200, 16)
	_name_edit = LineEdit.new()
	_name_edit.text = str(settings.player_name)
	_name_edit.max_length = 12
	_name_edit.text_changed.connect(func(t: String):
		settings.player_name = t.strip_edges()
		Settings.save_all(settings))
	_place(_name_edit, 152, 142, 260, 36)
	# 部屋を作る
	var left := _panel(152, 220, 460, 250)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 12)
	left.add_child(lv)
	lv.add_child(UiStyle.label("部屋を作る", 28, UiStyle.TEXT, true))
	lv.add_child(UiStyle.caption("CREATE ROOM"))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(sp)
	var create := _button("部屋を作る", _on_create, true)
	create.custom_minimum_size = Vector2(0, 44)
	lv.add_child(create)
	# 部屋に入る
	var right := _panel(668, 220, 460, 250)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 12)
	right.add_child(rv)
	rv.add_child(UiStyle.label("部屋に入る", 28, UiStyle.TEXT, true))
	rv.add_child(UiStyle.caption("JOIN ROOM"))
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "招待コード または IP アドレス"
	_code_edit.max_length = 40
	_code_edit.custom_minimum_size = Vector2(0, 40)
	_code_edit.text_submitted.connect(func(_t): _on_join())
	rv.add_child(_code_edit)
	var sp2 := Control.new()
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(sp2)
	var join := _button("参加する", _on_join, true)
	join.custom_minimum_size = Vector2(0, 44)
	rv.add_child(join)
	_status = UiStyle.label(notice, 13, UiStyle.DANGER)
	_place(_status, 152, 490, 976, 22)
	notice = ""
	UiStyle.pop_in(left, 0.05, Vector2(-30, 0), 0.5)
	UiStyle.pop_in(right, 0.12, Vector2(30, 0), 0.5)


func _set_status(text: String, color := UiStyle.DANGER) -> void:
	if _status != null:
		_status.text = text
		_status.add_theme_color_override("font_color", color)


func _on_create() -> void:
	if _busy:
		return
	if not net.host_room("versus", str(settings.player_name)):
		_set_status("部屋を作れませんでした(ポートが使えません)")
		return
	_show_lobby()


func _on_join() -> void:
	if _busy or _code_edit == null:
		return
	if _code_edit.text.strip_edges() == "":
		_set_status("招待コードを入力してください")
		return
	_busy = true
	_set_status("接続しています…", UiStyle.TEXT_DIM)
	net.join(_code_edit.text, str(settings.player_name))


func _on_joined() -> void:
	_busy = false
	_show_lobby()


func _on_join_failed(reason: String) -> void:
	_busy = false
	_set_status(reason)


func _on_left(reason: String) -> void:
	_show_entry(reason)


func _on_state_changed() -> void:
	if _page == "lobby":
		if not net.is_active():
			return
		_resolve_song()
		_refresh_lobby()


# --- ロビー ---

func _show_lobby() -> void:
	_page = "lobby"
	_lobby_built = false   # 開いたときは、入場の動きをつける
	_known_ids.clear()
	_resolve_song()
	_refresh_lobby()


## 部屋の曲を、この端末が持っているか探す(参加者)。見つけたら net に伝える(曲を持っている印になる)。
func _resolve_song() -> void:
	if net.is_host() or not net.is_active():
		return
	var song: Dictionary = net.room.get("song", {})
	if song.is_empty():
		return
	var md5 := str(song.get("md5", ""))
	var have: bool = net.song_bm != null and net.song_bm.md5 == md5
	if have:
		return
	var found := SongLibrary.find_by_md5(md5)
	if not found.is_empty():
		var l = OszLoader.new()
		if l.open(found.path):
			for bm in l.difficulties:
				if bm.md5 == md5:
					net.report_song(true, l, bm)
					return
	if net.players.has(net.my_id) and net.players[net.my_id].has_song:
		net.report_song(false)


func _refresh_lobby() -> void:
	_clear_content()
	var is_host: bool = net.is_host()
	var room: Dictionary = net.room
	_header("退出", _leave)
	# --- 左: 招待コード / 参加者 ---
	if is_host:
		var cp := _panel(36, 92, 600, 128)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		cp.add_child(cv)
		cv.add_child(UiStyle.caption("INVITE CODE"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		cv.add_child(row)
		var code_l := UiStyle.label(net.code if net.code != "" else "…", 34, UiStyle.ACCENT if net.code != "" else UiStyle.TEXT_FAINT, true)
		code_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(code_l)
		var copy := _button("コピー", func(): DisplayServer.clipboard_set(net.code))
		copy.disabled = net.code == ""
		row.add_child(copy)
		var note := UiStyle.label(net.code_note, 12, UiStyle.TEXT_DIM)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(540, 0)
		cv.add_child(note)
	else:
		var hp := _panel(36, 92, 600, 128)
		var hv := VBoxContainer.new()
		hv.add_theme_constant_override("separation", 6)
		hp.add_child(hv)
		hv.add_child(UiStyle.caption("ROOM"))
		var hname := ""
		for id in net.players:
			if net.players[id].slot == 0:
				hname = str(net.players[id].name)
		hv.add_child(UiStyle.label("%s の部屋" % hname, 30, UiStyle.TEXT, true))
		hv.add_child(UiStyle.label("遅延 %s ms" % ("%.0f" % net.ping_ms if net.ping_ms >= 0.0 else "-"), 12, UiStyle.TEXT_DIM))
	var pp := _panel(36, 240, 600, 360)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 8)
	pp.add_child(pv)
	pv.add_child(UiStyle.caption("PLAYERS  %d / %d" % [net.players.size(), net.MAX_PLAYERS]))
	var ids: Array = net.players.keys()
	ids.sort_custom(func(a, b): return net.players[a].slot < net.players[b].slot)
	var joined: Array = []
	for id in ids:
		var row_c := _player_row(id, is_host)
		pv.add_child(row_c)
		if _lobby_built and not _known_ids.has(id):   # 新しく入ってきた人は、弾んで現れる
			joined.append(row_c)
	var left_n := 0
	for id in _known_ids:
		if not net.players.has(id):
			left_n += 1
	if _lobby_built:
		if not joined.is_empty():
			UiSfx.play("on", 1.25)
			for rc in joined:
				UiStyle.pop_scale(rc, 0.85, 0.4)
		elif left_n > 0:
			UiSfx.play("off", 0.9)
	_known_ids.clear()
	for id in ids:
		_known_ids[id] = true
	# --- 右: モード / 曲 ---
	_place(UiStyle.caption("MODE"), 668, 94, 200, 16)
	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", 8)
	for m in MODES:
		var on: bool = room.mode == m[0]
		var b := Button.new()
		b.text = m[1]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 44)
		var mode_id: String = m[0]
		if on:
			b.add_theme_stylebox_override("normal", UiStyle.box(Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.18), UiStyle.ACCENT, 1, 4, 16, 8))
			b.add_theme_stylebox_override("hover", UiStyle.box(Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.24), UiStyle.ACCENT, 1, 4, 16, 8))
			b.add_theme_stylebox_override("disabled", UiStyle.box(Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.18), UiStyle.ACCENT, 1, 4, 16, 8))
			b.add_theme_color_override("font_color", UiStyle.ACCENT)
			b.add_theme_color_override("font_disabled_color", UiStyle.ACCENT)
		else:
			b.add_theme_stylebox_override("disabled", UiStyle.box(Color(1, 1, 1, 0.03), UiStyle.LINE, 1, 4, 16, 8))
			b.add_theme_color_override("font_disabled_color", UiStyle.TEXT_FAINT)
		b.disabled = not is_host
		b.pressed.connect(func(): net.set_mode(mode_id))
		seg.add_child(b)
	_place(seg, 668, 116, 320, 44)
	_place(UiStyle.caption("SONG"), 668, 184, 200, 16)
	var sp := _panel(668, 206, 580, 10)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 8)
	sp.add_child(sv)
	var song: Dictionary = room.get("song", {})
	if song.is_empty():
		sv.add_child(UiStyle.label("曲が選ばれていません", 18, UiStyle.TEXT_DIM))
	else:
		var t := UiStyle.label(str(song.title), 24, UiStyle.TEXT, true)
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		t.custom_minimum_size = Vector2(536, 0)
		sv.add_child(t)
		sv.add_child(UiStyle.label(str(song.artist), 15, UiStyle.TEXT_DIM))
		var chips := HBoxContainer.new()
		chips.add_theme_constant_override("separation", 8)
		chips.add_child(UiStyle.label(str(song.version), 16, UiStyle.ACCENT, true))
		chips.add_child(UiStyle.chip("Lv %.2f" % float(song.level), UiStyle.level_color(float(song.level))))
		sv.add_child(chips)
		sv.add_child(UiStyle.hline())
		var mods := HBoxContainer.new()
		mods.add_theme_constant_override("separation", 8)
		var ids2: Array = Mods.params(room.mods).ids
		if ids2.is_empty():
			mods.add_child(UiStyle.label("MOD なし", 13, UiStyle.TEXT_FAINT))
		for mid in ids2:
			var md := Mods.find(mid)
			mods.add_child(UiStyle.chip(md.name, md.color))
		sv.add_child(mods)
		if not is_host and not (net.players.has(net.my_id) and net.players[net.my_id].has_song):
			_build_missing(sv, song)
	if is_host:
		var pick := _button("曲・MOD を選ぶ" if song.is_empty() else "曲・MOD を変更", func(): pick_song_requested.emit())
		pick.custom_minimum_size = Vector2(0, 40)
		sv.add_child(pick)
	# --- 下: 開始 ---
	if is_host:
		var reason := _start_blocker()
		var start := _button("ゲーム開始", _on_start, true)
		start.disabled = reason != ""
		_place(start, 1088, 626, 160, 44)
		_status = UiStyle.label(reason, 13, UiStyle.TEXT_DIM)
		_place(_status, 668, 638, 400, 20)
	_update_bg()
	if not _lobby_built:   # 最初だけ、パネルが左右から滑り込む
		_lobby_built = true
		var k := 0
		for c in _content.get_children():
			if c is PanelContainer:
				UiStyle.pop_in(c, 0.04 + 0.06 * k, Vector2(-26, 0) if c.position.x < 640.0 else Vector2(26, 0), 0.45)
				k += 1


## 部屋の曲を持っていないとき(参加者): ダウンロードして取り込むボタン。ダウンロード中は進み具合。
## 補助として、osu! の譜面ページ(ブラウザで開く)と、曲フォルダを開くボタンも出す。
func _build_missing(sv: VBoxContainer, song: Dictionary) -> void:
	sv.add_child(UiStyle.label("この曲を持っていません", 15, UiStyle.DANGER, true))
	var set_id := int(song.get("set_id", 0))
	var downloading: bool = _dl != null and _dl.busy
	if set_id > 0 and not downloading:
		var dl := _button("ダウンロードして取り込む", func(): _start_download(song), true)
		dl.custom_minimum_size = Vector2(0, 40)
		sv.add_child(dl)
	if downloading:
		_dl_bar = ProgressBar.new()
		_dl_bar.min_value = 0.0
		_dl_bar.max_value = 1.0
		_dl_bar.value = _dl_frac
		_dl_bar.show_percentage = false
		_dl_bar.custom_minimum_size = Vector2(0, 10)
		_dl_bar.add_theme_stylebox_override("background", UiStyle.box(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, 3))
		_dl_bar.add_theme_stylebox_override("fill", UiStyle.box(UiStyle.ACCENT, Color(0, 0, 0, 0), 0, 3))
		sv.add_child(_dl_bar)
		_dl_label = UiStyle.label(_dl_text, 13, UiStyle.TEXT_DIM)
		sv.add_child(_dl_label)
	elif _dl_error != "":
		var err := UiStyle.label(_dl_error, 12, UiStyle.DANGER)
		err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		err.custom_minimum_size = Vector2(536, 0)
		sv.add_child(err)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var url := osu_url(set_id, int(song.get("map_id", 0)))
	if url != "":   # osu! の公式のページ(自分で入れたいとき)
		row.add_child(_button("ブラウザで開く", func(): OS.shell_open(url)))
	row.add_child(_button("曲フォルダを開く", _open_songs_dir))
	sv.add_child(row)


func _start_download(song: Dictionary) -> void:
	if _dl == null:
		_dl = SongDownload.new()
		add_child(_dl)
		_dl.progress.connect(_on_dl_progress)
		_dl.finished.connect(_on_dl_finished)
	_dl_error = ""
	_dl_frac = 0.0
	_dl_text = "接続しています…"
	_dl.start(int(song.get("set_id", 0)), str(song.get("md5", "")), "%d %s - %s" % [int(song.get("set_id", 0)), str(song.get("artist", "")), str(song.get("title", ""))])
	_refresh_lobby()


func _on_dl_progress(frac: float, text: String) -> void:
	_dl_frac = frac
	_dl_text = text
	if is_instance_valid(_dl_bar):
		_dl_bar.value = frac
	if is_instance_valid(_dl_label):
		_dl_label.text = text


func _on_dl_finished(r: Dictionary) -> void:
	_dl_error = "" if r.ok else str(r.error)
	if r.ok:
		_resolve_song()   # 取り込んだ曲を見つけて、持っている印を net に伝える
	if _page == "lobby":
		_refresh_lobby()


## 開始できない理由(できるなら空文字)。
func _start_blocker() -> String:
	if net.room.get("song", {}).is_empty():
		return "曲を選んでください"
	for id in net.players:
		if not net.players[id].has_song:
			return "%s さんがこの曲を持っていません" % str(net.players[id].name)
	return ""


func _player_row(id: int, is_host: bool) -> Control:
	var p: Dictionary = net.players[id]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, 40)
	var dot := Control.new()
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var c: Color = MpGame.SLOT_COLORS[int(p.slot) % MpGame.SLOT_COLORS.size()]
	dot.draw.connect(func(): dot.draw_circle(Vector2(6, 6), 6.0, c))
	row.add_child(dot)
	var nm := UiStyle.label(str(p.name), 18, UiStyle.TEXT, id == net.my_id)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size = Vector2(190, 0)
	row.add_child(nm)
	if int(p.slot) == 0:
		var host_chip := UiStyle.chip("HOST", UiStyle.GOLD)
		host_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(host_chip)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	var has: bool = bool(p.has_song)
	if not net.room.get("song", {}).is_empty():
		row.add_child(UiStyle.label("曲あり" if has else "曲なし", 13, UiStyle.TEXT_DIM if has else UiStyle.DANGER))
	if is_host and id != 1:
		var pl := UiStyle.label("%.0f ms" % float(p.ping) if float(p.ping) >= 0.0 else "- ms", 12, UiStyle.TEXT_FAINT)
		pl.custom_minimum_size = Vector2(56, 0)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(pl)
		_ping_labels[id] = pl
		var kick := Button.new()
		kick.text = "×"
		kick.focus_mode = Control.FOCUS_NONE
		kick.custom_minimum_size = Vector2(34, 30)
		kick.pressed.connect(func(): net.kick(id))
		row.add_child(kick)
	return row


func _on_start() -> void:
	var err: String = net.start_game()
	if err != "":
		_set_status(err)


func _leave() -> void:
	net.leave()   # left が届いて、入口に戻る


func _open_songs_dir() -> void:
	var d := SongLibrary.ensure_user_dir()
	OS.shell_open(d)


## 背景と試聴: 部屋の曲を持っているとき、その画像を背景にして、サビ手前(プレビュー位置)から流す。
func _update_bg() -> void:
	var song: Dictionary = net.room.get("song", {})
	var md5 := str(song.get("md5", ""))
	if md5 == _preview_md5:
		return
	_preview_md5 = md5
	_audio.stop()
	var tex: Texture2D = null
	if net.song_loader != null and net.song_bm != null and net.song_bm.md5 == md5:
		var bm = net.song_bm
		if bm.background != "":
			tex = net.song_loader.load_image(bm.background)
		var s: AudioStream = net.song_loader.load_audio(bm.audio_filename)
		if s != null:
			_audio.stream = s
			_audio.play(maxf(bm.preview_time / 1000.0, 0.0))
	_bg.texture = tex
	UiStyle.tween(_bg, "modulate:a", 0.0, 1.0 if tex != null else 0.0, 0.7)


func _process(delta: float) -> void:
	_par = UiStyle.parallax(_bg_holder, _ambient, _par, delta, get_viewport())
	if _page != "lobby" or not net.is_active():
		return
	_t += delta
	if _t >= 1.0:
		_t = 0.0
		if net.is_host():   # 参加者の遅延の表示だけ更新する(作り直さない)
			for id in _ping_labels:
				if net.players.has(id):
					var pg := float(net.players[id].ping)
					_ping_labels[id].text = "%.0f ms" % pg if pg >= 0.0 else "- ms"
	_resolve_t += delta
	if _resolve_t >= 2.0:   # 曲をあとから入れたときに、見つけられるように
		_resolve_t = 0.0
		if not net.is_host() and not net.room.get("song", {}).is_empty() and net.song_bm == null:
			_resolve_song()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ESCAPE:
		if _page == "lobby":
			_leave()
		elif _page == "entry":
			back_requested.emit()
		get_viewport().set_input_as_handled()


## osu! の譜面ページの URL(例: https://osu.ppy.sh/beatmapsets/320118#osu/738063)。set_id は曲全体、map_id は難易度の ID(#osu/ は osu!standard)。
## 数字だけから作るので、他所から届いた文字列は URL に入らない。set_id が無ければ空文字。
static func osu_url(set_id: int, map_id: int) -> String:
	if set_id <= 0:
		return ""
	var url := "https://osu.ppy.sh/beatmapsets/%d" % set_id
	if map_id > 0:
		url += "#osu/%d" % map_id
	return url
