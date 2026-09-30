extends Control
## 選曲画面。左に曲、右に難易度カード。MOD・操作・音・ゲームの設定は「OPTIONS」(options_panel.gd)に分けてある。
## .osz は、プロジェクト直下 / songs / 実行ファイルの隣 / user://songs を自動検出し、ドラッグ&ドロップや「開く」でも追加できる。
##
## 操作: ↑↓ 選択、← → / Tab で「曲 ⇔ 難易度」の切替、Enter 開始、O で設定、Esc でタイトルへ。マウスでも全部できる(難易度のダブルクリックで開始)。

signal play_requested(loader, bm, settings: Dictionary)
signal back_requested
## 設定を開く(パネルは main が持つ。どの画面でも開ける)。section: 0=MOD 1=操作 2=音 3=ゲーム
signal settings_requested(section: int)
## マルチプレイの部屋の曲を選ぶモード(pick_mode = true): 「決定」で、開始せずに選んだ内容を返す(level は MOD 適用後の Lv)
signal song_picked(loader, bm, settings: Dictionary, level: float)

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const Settings = preload("res://scripts/settings.gd")
const Mods = preload("res://scripts/mods.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Volume = preload("res://scripts/volume.gd")
const Ambient = preload("res://scripts/ui/ambient.gd")
const SmoothScroll = preload("res://scripts/ui/smooth_scroll.gd")
const SongLibrary = preload("res://scripts/song_library.gd")

const BG_TINT := Color(0.34, 0.34, 0.4)

## 難易度カードの弾数バー(平均・最大)の満点
const BAR_MAX := 500.0

var settings: Dictionary = {}
var pick_mode := false

var _songs: Array = []          # [{path, title, artist}]
var _loader                     # 選択中の OszLoader
var _gens: Array = []           # 難易度リストと同じ並びの、MOD 適用前の弾幕(生成結果)
var _ratings: Array = []        # 同じ並びの DDA 難易度(MOD 適用後)
var _song_sel := -1
var _diff_sel := -1
var _focus_diff := true         # ↑↓ の対象: true = 難易度 / false = 曲
var _song_cards: Array = []
var _diff_cards: Array = []

var _bg: TextureRect            # 今見えている背景(もう 1 枚 _bg2 と交代でクロスフェードする)
var _bg2: TextureRect
var _bg_holder: Control
var _intro_nodes: Array = []       # 入場アニメーションで滑り込むもの
var _buttons: Array = []           # ホバーで少し大きくなるボタン
var _lv_shown := {}             # 難易度名 → 表示中の Lv(MOD で変わるとき、前の値から数え直す)
var _song_box: VBoxContainer
var _diff_box: VBoxContainer
var _diff_scroll: ScrollContainer
var _song_scroll: ScrollContainer
var _diff_smooth: Node            # スクロールをなめらかにする(smooth_scroll.gd)
var _song_smooth: Node
var _last_error := ""
var _cards_gen := 0               # 難易度カードを作り直すたびに増える(分けて作っている途中の古いものを止める)
var _job := 0                    # 曲の読み込み(別スレッド)の通し番号。最新のものだけ使う
var _job_pending := false         # 読み込み中か
var _prev_sel := -1               # 読み込み中の曲を選ぶ前に選んでいた曲(読めなかったときに戻す)
var _title_l: Label
var _artist_l: Label
var _meta_l: Label
var _detail_l: Label
var _mod_bar: HBoxContainer
var _status: Label
var _audio: AudioStreamPlayer
var _dialog: FileDialog
var _options: Control            # 開いている設定パネル(main が持つ。開いている間だけ設定される)


func _ready() -> void:
	settings = Settings.load_all()
	theme = UiStyle.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiStyle.backdrop(self)
	_bg_holder = Control.new()
	_bg_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_holder.pivot_offset = Vector2(640, 360)
	_bg_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_holder)
	_bg = _bg_layer()
	_bg2 = _bg_layer()
	if UiStyle.animate:   # 背景画像をごくゆっくり拡大・縮小する(ずっと動き続ける)
		var drift := create_tween().set_loops()
		drift.tween_property(_bg_holder, "scale", Vector2(1.08, 1.08), 22.0).from(Vector2(1.02, 1.02)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		drift.tween_property(_bg_holder, "scale", Vector2(1.02, 1.02), 22.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.025, 0.05, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	add_child(Ambient.new())   # 背景で漂うリング

	# --- 左: 曲リスト ---
	_intro_nodes.append(_place(UiStyle.label("DDA", 30, UiStyle.ACCENT, true), 36, 20, 200, 40))
	_intro_nodes.append(_place(UiStyle.caption("OSU! DANMAKU DODGER"), 38, 62, 300, 16))
	var back_btn := Button.new()
	back_btn.text = "◀  ロビー" if pick_mode else "◀  タイトル"
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.pressed.connect(func(): back_requested.emit())
	_intro_nodes.append(_place(back_btn, 312, 24, 124, 32))
	_buttons.append(back_btn)
	_intro_nodes.append(_place(UiStyle.caption("SONGS"), 38, 96, 200, 16))
	_song_scroll = ScrollContainer.new()
	_song_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_place(_song_scroll, 32, 118, 404, 494)
	_song_smooth = SmoothScroll.attach(_song_scroll)
	_song_box = VBoxContainer.new()
	_song_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_song_box.add_theme_constant_override("separation", 6)
	_song_scroll.add_child(_song_box)
	var open_btn := Button.new()
	open_btn.text = ".osz を開く…"
	open_btn.focus_mode = Control.FOCUS_NONE
	open_btn.pressed.connect(func(): _dialog.popup_centered_ratio(0.7))
	_intro_nodes.append(_place(open_btn, 32, 626, 404, 40))
	_buttons.append(open_btn)

	# --- 右: 曲情報 + 難易度カード ---
	_title_l = UiStyle.label("", 28, UiStyle.TEXT, true)
	_title_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_place(_title_l, 468, 26, 780, 40)
	_artist_l = UiStyle.label("", 16, UiStyle.TEXT_DIM)
	_artist_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_place(_artist_l, 468, 70, 780, 24)
	_meta_l = UiStyle.label("", 13, UiStyle.TEXT_FAINT)
	_place(_meta_l, 468, 98, 780, 20)
	_place(UiStyle.caption("DIFFICULTY"), 470, 146, 780, 16)
	_diff_scroll = ScrollContainer.new()
	_diff_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_place(_diff_scroll, 468, 168, 780, 384)
	_diff_smooth = SmoothScroll.attach(_diff_scroll)
	_diff_box = VBoxContainer.new()
	_diff_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diff_box.add_theme_constant_override("separation", 6)
	_diff_scroll.add_child(_diff_box)

	var detail := PanelContainer.new()
	detail.add_theme_stylebox_override("panel", UiStyle.box(Color(0, 0, 0, 0.35), UiStyle.LINE, 1, 5, 14, 8))
	_intro_nodes.append(_place(detail, 468, 562, 780, 38))
	_detail_l = UiStyle.label("", 13, UiStyle.TEXT_DIM)
	detail.add_child(_detail_l)

	# --- 下部バー: MOD / OPTIONS / PLAY ---
	_mod_bar = HBoxContainer.new()
	_mod_bar.add_theme_constant_override("separation", 8)
	_intro_nodes.append(_place(_mod_bar, 468, 626, 520, 40))
	var opt_btn := Button.new()
	opt_btn.text = "設定"
	opt_btn.focus_mode = Control.FOCUS_NONE
	opt_btn.pressed.connect(func(): open_options(0))
	_intro_nodes.append(_place(opt_btn, 996, 626, 118, 40))
	_buttons.append(opt_btn)
	var play := Button.new()
	play.text = "決定" if pick_mode else "PLAY"
	play.focus_mode = Control.FOCUS_NONE
	play.add_theme_stylebox_override("normal", UiStyle.box(Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.9), Color(0, 0, 0, 0), 0, 4, 16, 8))
	play.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.ACCENT, Color(0, 0, 0, 0), 0, 4, 16, 8))
	play.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.ACCENT, Color(0, 0, 0, 0), 0, 4, 16, 8))
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		play.add_theme_color_override(k, Color(0.02, 0.06, 0.1))
	play.add_theme_font_override("font", UiStyle.bold())
	play.pressed.connect(_start)
	_intro_nodes.append(_place(play, 1124, 626, 124, 40))
	_buttons.append(play)
	_status = UiStyle.label("", 12, UiStyle.TEXT_FAINT)   # 読み込みに失敗したときのメッセージ用
	_place(_status, 470, 680, 780, 18)

	_audio = AudioStreamPlayer.new()
	Volume.route_music(_audio)   # 音楽バスへ(ホイールなどの「音楽」の音量が効く)
	_audio.volume_db = -6.0
	add_child(_audio)
	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.filters = PackedStringArray(["*.osz ; osu! beatmap"])
	_dialog.use_native_dialog = true
	_dialog.file_selected.connect(_add_song_and_select)
	add_child(_dialog)

	get_window().files_dropped.connect(_on_files_dropped)
	_refresh_mod_bar()
	_intro()
	_scan()
	_rebuild_song_cards()
	if not _songs.is_empty():
		var pick := 0
		for i in range(_songs.size()):
			if _songs[i].key == SongLibrary.norm(str(settings.last_song)):
				pick = i
		_select_song(pick)


func _exit_tree() -> void:
	var w := get_window()
	if w != null and w.files_dropped.is_connected(_on_files_dropped):
		w.files_dropped.disconnect(_on_files_dropped)


## 画面を開いたときの入場: 見出し・下部バー・ボタンが順に滑り込み、ボタンはホバーで少し大きくなる。
func _intro() -> void:
	var k := 0
	for c in _intro_nodes:
		UiStyle.pop_in(c, 0.05 + k * 0.05, Vector2(0, 18) if c.position.y > 500.0 else Vector2(-24, 0), 0.5)
		k += 1
	for b in _buttons:
		UiStyle.hover_scale(b)


func _bg_layer() -> TextureRect:
	var t := TextureRect.new()
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.modulate = Color(BG_TINT.r, BG_TINT.g, BG_TINT.b, 0.0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_holder.add_child(t)
	return t


## 背景画像を、前の画像からクロスフェードで切り替える。
func _set_background(tex: Texture2D) -> void:
	var cur := _bg
	var nxt := _bg2
	nxt.texture = tex
	var to_a := 1.0 if tex != null else 0.0
	UiStyle.tween(nxt, "modulate:a", 0.0, to_a, 0.7, 0.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	UiStyle.tween(cur, "modulate:a", cur.modulate.a, 0.0, 0.7, 0.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	_bg = nxt
	_bg2 = cur


func _place(c: Control, x: float, y: float, w: float, h: float) -> Control:
	c.position = Vector2(x, y)
	c.size = Vector2(w, h)
	add_child(c)
	return c


# --- 曲の検出 ---

func _search_dirs() -> Array:
	return SongLibrary.search_dirs()


func _scan() -> void:
	_songs.clear()
	var failed: Array = []
	var paths := SongLibrary.find_all()   # 同じファイルは 1 つにまとめて返る
	for p in paths:
		if _add_song(p) < 0:
			failed.append(str(p).get_file())
	SongLibrary.save_index(paths)
	if not failed.is_empty():   # 読めなかった曲は、黙って飛ばさず、名前を出す
		_status.text = "読み込めなかった曲: " + ", ".join(failed.slice(0, 3)) + (" ほか %d 件" % (failed.size() - 3) if failed.size() > 3 else "")


## songs フォルダの中身が変わったとき(main が知らせる): 一覧を作り直す。選んでいる曲はそのまま(読み込み直さない)。
func refresh_songs() -> void:
	var cur := ""
	if _song_sel >= 0 and _song_sel < _songs.size():
		cur = str(_songs[_song_sel].key)
	_scan()
	_song_sel = -1
	for i in range(_songs.size()):
		if _songs[i].key == cur:
			_song_sel = i
	_rebuild_song_cards(false)
	if _song_sel < 0 and not _songs.is_empty() and _loader == null:
		_select_song(0)


## 追加して一覧の index を返す(重複は既存の index、読めなければ -1)。カードは _rebuild_song_cards で作る。
func _add_song(path: String) -> int:
	path = path.replace("\\", "/")
	var key := SongLibrary.norm(path)
	var size := -1
	var fh := FileAccess.open(path, FileAccess.READ)
	if fh != null:
		size = fh.get_length()
		fh.close()
	var key2 := "%s|%d" % [path.get_file().to_lower(), size]
	for i in range(_songs.size()):   # すでに一覧にある(パスが同じ、または名前と大きさが同じ)
		if _songs[i].key == key or (size >= 0 and _songs[i].key2 == key2):
			return i
	var info := SongLibrary.info(path)   # 曲を全部は開かずに、題名などを得る(結果は保存されて、次からは開き直さない)
	if not info.ok:
		_last_error = str(info.error)
		return -1
	for i in range(_songs.size()):   # 別の名前で同じ曲が入っている(譜面の中身が同じ)ときも、1 つにする
		if _songs[i].md5 == info.md5:
			return i
	_songs.append({"path": path, "title": info.title, "artist": info.artist, "key": key, "key2": key2, "md5": info.md5})
	return _songs.size() - 1


func _add_song_and_select(path: String) -> void:
	var i := _add_song(path)
	if i < 0:
		_status.text = "読み込めませんでした: " + path.get_file()
		return
	_rebuild_song_cards()
	_select_song(i)


func _on_files_dropped(files: PackedStringArray) -> void:
	for f in files:
		if f.to_lower().ends_with(".osz"):
			_add_song_and_select(f)
			return
	_status.text = ".osz ファイル以外は読み込めません"


# --- 曲リスト ---

func _rebuild_song_cards(animate := true) -> void:
	for c in _song_box.get_children():
		c.queue_free()
	_song_cards.clear()
	for i in range(_songs.size()):
		var card := UiStyle.card(56, func(): _focus_diff = false; _select_song(i))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := UiStyle.label(_songs[i].title, 15, UiStyle.TEXT, true)
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(t)
		var a := UiStyle.label(_songs[i].artist, 12, UiStyle.TEXT_DIM)
		a.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(a)
		card.add_child(v)
		card.mouse_entered.connect(func(): card.set_meta("hover", true); _restyle_song(i))
		card.mouse_exited.connect(func(): card.set_meta("hover", false); _restyle_song(i))
		_song_box.add_child(UiStyle.wrap_card(card, 56))
		_song_cards.append(card)
		_restyle_song(i)
		if animate:
			UiStyle.enter_card(card, 0.08 + i * 0.06, -40.0)   # 左から順に滑り込む


func _restyle_song(i: int) -> void:
	if i < 0 or i >= _song_cards.size():
		return
	var c: PanelContainer = _song_cards[i]
	var sel := (i == _song_sel)
	var hover := bool(c.get_meta("hover", false))
	UiStyle.style_card(c, sel, not _focus_diff, UiStyle.ACCENT, hover)
	UiStyle.shift_card(c, (10.0 if not _focus_diff else 6.0) if sel else (4.0 if hover else 0.0))   # 選択中・ホバー中は少し右へ


## 曲を選ぶ。選んだ表示はすぐ切り替わり、重い読み込み(.osz を開く・弾幕の生成・画像/音声の読み込み)は別スレッドで行う。
## 終わったら _on_song_loaded で難易度カードなどを入れ替える(そのあいだに別の曲を選び直したら、前の結果は捨てる)。
func _select_song(i: int) -> void:
	if _songs.is_empty():
		return
	i = clampi(i, 0, _songs.size() - 1)
	if i == _song_sel and (_loader != null or _job_pending):
		_restyle_all()
		return
	_prev_sel = _song_sel if not _job_pending else _prev_sel
	var old := _song_sel
	_song_sel = i
	_restyle_song(old)
	_restyle_song(i)
	_song_smooth.scroll_to_control(_song_cards[i])
	# 曲名などは、一覧に持っている値をすぐ出す
	_title_l.text = _songs[i].title
	_artist_l.text = _songs[i].artist
	_meta_l.text = ""
	_job += 1
	_job_pending = true
	var job := _job
	var path: String = _songs[i].path
	var p := Mods.params(settings.mods)
	var me: WeakRef = weakref(self)   # 読み込み中に画面が閉じられても、届け先がなければ捨てる
	WorkerThreadPool.add_task(func():
		var res := _load_song(path, p)
		res["job"] = job
		var target: Object = me.get_ref()
		if target != null:
			target._on_song_loaded.call_deferred(res)
		elif res.get("loader") != null:
			res.loader.close())


## 前の曲の OszLoader と弾幕の一覧を、別スレッドで中身ごと手放す(主スレッドで手放すと、大量の辞書の解放で止まる)。
func _release_later(old_loader, old_gens: Array) -> void:
	if old_loader == null and old_gens.is_empty():
		return
	WorkerThreadPool.add_task(func():
		if old_loader != null:
			old_loader.close()
			old_loader.difficulties.clear()
		old_gens.clear())


## (別スレッドで動く)曲を開いて、難易度ごとの弾幕・難易度(MOD 適用後)・背景画像・試聴用の音声まで作る。画面には触らない。
static func _load_song(path: String, mod_params: Dictionary) -> Dictionary:
	var l = OszLoader.new()
	if not l.open(path):
		return {"ok": false, "error": l.error}
	var first = l.difficulties[0]
	var image: Image = l.load_image_data(first.background) if first.background != "" else null
	if image != null and image.get_width() > 1280:   # 背景は 1280×720 の画面に出すだけ。大きい画像は、ここ(別スレッド)で縮めて、テクスチャにする負担を減らす
		image.resize(1280, maxi(int(round(1280.0 * image.get_height() / image.get_width())), 1), Image.INTERPOLATE_BILINEAR)
	# DDA 難易度(画面内の弾数。MOD なしの状態)の低い順に並べ替える
	var pairs: Array = []
	for bm in l.difficulties:
		pairs.append({"bm": bm, "g": PatternGen.generate(bm, {})})
	pairs.sort_custom(func(a, b): return a.g.rating.score < b.g.rating.score)
	l.difficulties = pairs.map(func(q): return q.bm)
	var gens: Array = pairs.map(func(q): return q.g)
	var ratings: Array = gens.map(func(g): return PatternGen.summary(Mods.apply(g, mod_params)))
	var audio: AudioStream = l.load_audio(first.audio_filename)
	var from := maxf(first.preview_time / 1000.0, 0.0)
	var cropped := _crop_mp3(audio, from)
	if cropped != null:   # MP3 の途中から流すと、探す処理で数十 ms 止まる。あらかじめ、その位置から始まる音声にしておく
		audio = cropped
		from = 0.0
	return {"ok": true, "loader": l, "gens": gens, "ratings": ratings, "image": image, "audio": audio, "audio_from": from}


## MP3 の、from 秒あたりから始まる音声(データの途中から切り出す。MP3 は、途中からでも読み始められる)。MP3 でない・先頭のとき・長さが分からないときは null。
static func _crop_mp3(audio: AudioStream, from: float) -> AudioStream:
	if not audio is AudioStreamMP3 or from < 1.0:
		return null
	var total: float = audio.get_length()
	var bytes: PackedByteArray = audio.data
	if total <= from + 1.0 or bytes.is_empty():
		return null
	var out := AudioStreamMP3.new()
	out.data = bytes.slice(int(float(bytes.size()) * from / total))
	return out


func _on_song_loaded(res: Dictionary) -> void:
	if not is_inside_tree() or int(res.job) != _job:   # 画面を離れた / 別の曲を選び直した
		if res.get("loader") != null:
			res.loader.close()
		return
	_job_pending = false
	if not res.ok:
		_status.text = str(res.error)
		var bad := _song_sel
		_song_sel = _prev_sel   # 選べなかったので、元の曲の選択に戻す
		_restyle_song(bad)
		_restyle_song(_song_sel)
		if _loader != null and _song_sel >= 0 and _song_sel < _songs.size():
			_title_l.text = _songs[_song_sel].title
			_artist_l.text = _songs[_song_sel].artist
		return
	_release_later(_loader, _gens)   # 前の曲の弾幕・譜面は、量が多く、ここで手放すと解放だけで十数 ms かかる
	_loader = res.loader
	var i := _song_sel
	var first = _loader.difficulties[0]
	_meta_l.text = "BPM %.0f     Creator  %s" % [60000.0 / first.beat_length_at(first.first_time()), first.creator]
	var k := 0
	for lab in [_title_l, _artist_l, _meta_l]:   # 曲情報は順に滑り込む
		UiStyle.pop_in(lab, k * 0.07, Vector2(30, 0), 0.45)
		k += 1
	var tex: Texture2D = null
	if res.image != null:
		tex = ImageTexture.create_from_image(res.image)
	_set_background(tex)
	_gens = res.gens
	_ratings = res.ratings
	_diff_sel = mini(2, _gens.size() - 1)
	# 直前にプレイした曲に戻ったときは、そのとき選んだ難易度を選んだ状態にする
	if _songs[i].key == SongLibrary.norm(str(settings.last_song)) and settings.last_diff != "":
		for k2 in range(_loader.difficulties.size()):
			if _loader.difficulties[k2].version == settings.last_diff:
				_diff_sel = k2
	_lv_shown.clear()
	_rebuild_diff_cards(true)
	_audio.stop()
	if res.audio != null:
		await get_tree().process_frame   # カードを作る処理と、同じフレームにしない(音の開始も、少し時間がかかる)
		if int(res.job) == _job and is_inside_tree():
			_audio.stream = res.audio
			_audio.play(float(res.audio_from))


# --- 難易度カード ---

## 全難易度について、今の MOD を適用した弾幕で難易度を測り直す。
func _rate_all() -> void:
	var p := Mods.params(settings.mods)
	_ratings = _gens.map(func(g): return PatternGen.summary(Mods.apply(g, p)))


## animate_in = true(曲を選び直したとき)は、カードが右から滑り込み、Lv が 0 から数え上がる。MOD などで作り直すときは、前の Lv から数え直す。
## 曲を選び直したとき(animate_in)は、カードを 3 枚ずつ、数フレームに分けて作る(1 フレームで全部作ると、一瞬止まって見えるため)。
func _rebuild_diff_cards(animate_in := false) -> void:
	for c in _diff_box.get_children():
		c.queue_free()
	_diff_cards.clear()
	_cards_gen += 1
	var gen := _cards_gen
	_update_detail()
	_refresh_mod_bar()
	for i in range(_ratings.size()):
		if animate_in and i > 0 and i % 3 == 0:
			await get_tree().process_frame
			if gen != _cards_gen or not is_inside_tree():   # 作っている間に、作り直された・画面が閉じられた
				return
		var bm = _loader.difficulties[i]
		var r: Dictionary = _ratings[i]
		var col := UiStyle.level_color(r.level)
		var card := UiStyle.card(68, func(): _focus_diff = true; _select_diff(i), func(): _start())
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Lv(大きく。値で色が変わる)
		var lv := VBoxContainer.new()
		lv.custom_minimum_size = Vector2(92, 0)
		lv.add_theme_constant_override("separation", -2)
		lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lv.add_child(UiStyle.caption("LV"))
		var lv_l := UiStyle.label("%.2f" % r.level, 30, col, true)
		lv.add_child(lv_l)
		h.add_child(lv)
		# 名前と補助情報
		var nm := VBoxContainer.new()
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.alignment = BoxContainer.ALIGNMENT_CENTER
		nm.add_theme_constant_override("separation", 3)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_l := UiStyle.label(bm.version, 17, UiStyle.TEXT, true)
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.add_child(name_l)
		var sub := "本家★≈%.2f" % r.stars
		if absf(r.level - r.base_level) >= 0.005:
			sub += "     MODなし  Lv %.2f" % r.base_level   # MOD 適用後との差が分かるように
		nm.add_child(UiStyle.label(sub, 12, UiStyle.TEXT_DIM))
		h.add_child(nm)
		# 弾数バー(平均と最大)
		var bars_box := VBoxContainer.new()
		bars_box.custom_minimum_size = Vector2(210, 0)
		bars_box.alignment = BoxContainer.ALIGNMENT_CENTER
		bars_box.add_theme_constant_override("separation", 4)
		bars_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bars_box.add_child(UiStyle.label("平均 %d  ·  最大 %d 発" % [int(round(r.mean)), int(r.peak)], 12, UiStyle.TEXT_DIM))
		var bars := _bars(clampf(r.mean / BAR_MAX, 0.0, 1.0), clampf(r.peak / BAR_MAX, 0.0, 1.0), col)
		bars_box.add_child(bars)
		h.add_child(bars_box)
		card.add_child(h)
		card.mouse_entered.connect(func(): card.set_meta("hover", true); _restyle_diff(i))
		card.mouse_exited.connect(func(): card.set_meta("hover", false); _restyle_diff(i))
		_diff_box.add_child(UiStyle.wrap_card(card, 68))
		_diff_cards.append(card)
		_restyle_diff(i)
		var delay := (0.1 + i * 0.07) if animate_in else 0.0
		if animate_in:
			UiStyle.enter_card(card, delay, 50.0)
		# Lv は数え上がり(または前の値から)、弾数バーは左から伸びる
		var key: String = bm.version
		var from_lv: float = 0.0 if animate_in else float(_lv_shown.get(key, r.level))
		var set_lv := func(v: float):
			lv_l.text = "%.2f" % v
			lv_l.add_theme_color_override("font_color", UiStyle.level_color(v))
			_lv_shown[key] = v
		UiStyle.tween_value(lv_l, from_lv, r.level, 0.55, set_lv, delay + (0.1 if animate_in else 0.0))
		var state: Dictionary = bars.get_meta("state")
		var grow := func(v: float):
			state.p = v
			bars.queue_redraw()
		UiStyle.tween_value(bars, 0.0, 1.0, 0.7, grow, delay + 0.15)
	if _diff_sel >= 0 and _diff_sel < _diff_cards.size():
		# カードのレイアウト確定後にスクロール位置を合わせる
		_diff_smooth.scroll_to_control.call_deferred(_diff_cards[_diff_sel])


## 平均・最大の弾数を、2 本の細いバーで表す。
func _bars(mean_f: float, peak_f: float, col: Color) -> Control:
	var b := Control.new()
	b.custom_minimum_size = Vector2(210, 14)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var state := {"p": 1.0}   # 0 → 1 で左から伸びる
	b.set_meta("state", state)
	b.draw.connect(func():
		var w: float = b.size.x * state.p
		b.draw_rect(Rect2(0, 1, w, 4), Color(1, 1, 1, 0.1))
		b.draw_rect(Rect2(0, 1, w * mean_f, 4), col)
		b.draw_rect(Rect2(0, 9, w, 4), Color(1, 1, 1, 0.1))
		b.draw_rect(Rect2(0, 9, w * peak_f, 4), Color(col.r, col.g, col.b, 0.5)))
	return b


func _restyle_diff(i: int) -> void:
	if i < 0 or i >= _diff_cards.size():
		return
	var c: PanelContainer = _diff_cards[i]
	var col: Color = UiStyle.level_color(_ratings[i].level)
	var sel := (i == _diff_sel)
	var hover := bool(c.get_meta("hover", false))
	UiStyle.style_card(c, sel, _focus_diff, col, hover)
	UiStyle.shift_card(c, (10.0 if _focus_diff else 6.0) if sel else (4.0 if hover else 0.0))


func _restyle_all() -> void:
	for i in range(_song_cards.size()):
		_restyle_song(i)
	for i in range(_diff_cards.size()):
		_restyle_diff(i)


func _select_diff(i: int) -> void:
	if _diff_cards.is_empty():
		return
	i = clampi(i, 0, _diff_cards.size() - 1)
	var old := _diff_sel
	_diff_sel = i
	_restyle_all()
	_diff_smooth.scroll_to_control(_diff_cards[i])
	_update_detail()
	if _options != null and old != i:
		_options.refresh_mod_info()


## 選択中の難易度の詳細(弾速・弾径・弾数・長さ)。
func _update_detail() -> void:
	if _diff_sel < 0 or _diff_sel >= _ratings.size():
		_detail_l.text = ""
		return
	var r: Dictionary = _ratings[_diff_sel]
	var bm = _loader.difficulties[_diff_sel]
	UiStyle.tween(_detail_l, "modulate:a", 0.25, 1.0, 0.25)   # 選択が変わると、詳細がふわっと入れ替わる
	var secs := int(round((bm.last_time() - bm.first_time()) / 1000.0))
	_detail_l.text = "弾速 %d px/s     弾径 %.1f     平均 %d 発 / 最大 %d 発     イベント %d     長さ %d:%02d" % [
		int(round(r.speed)), r.size, int(round(r.mean)), int(r.peak), _gens[_diff_sel].events.size(), secs / 60, secs % 60]


# --- 下部バー(付けている MOD) ---

func _refresh_mod_bar() -> void:
	for c in _mod_bar.get_children():
		c.queue_free()
	var p := Mods.params(settings.mods)
	if p.ids.is_empty():
		_mod_bar.add_child(UiStyle.label("MOD なし", 13, UiStyle.TEXT_FAINT))
		return
	for id in p.ids:
		var m := Mods.find(id)
		_mod_bar.add_child(UiStyle.chip(m.name, m.color))
	_mod_bar.add_child(UiStyle.label("ベーススコア ×%.4f" % p.score_mul, 13, UiStyle.TEXT_DIM))


# --- 設定パネル ---

func open_options(section := 0) -> void:
	settings_requested.emit(section)


## 設定パネル(main が持つ)で、設定が変わった。MOD が変わったら、難易度を測り直す。
func on_settings_changed(kind: String) -> void:
	if _loader == null:
		return
	if kind == "mods":
		_rate_all()
		_rebuild_diff_cards()


## 設定パネルの MOD 欄に出す、選択中の難易度の MOD 適用後 Lv。
func _mod_preview_text() -> String:
	if _diff_sel < 0 or _diff_sel >= _ratings.size():
		return ""
	var r: Dictionary = _ratings[_diff_sel]
	var bm = _loader.difficulties[_diff_sel]
	var s := "選択中の難易度  %s   Lv %.2f" % [bm.version, r.level]
	if absf(r.level - r.base_level) >= 0.005:
		s += "   (MODなし %.2f)" % r.base_level
	return s


# --- 開始 ---

func _start() -> void:
	if _loader == null or _diff_sel < 0 or _job_pending:   # 曲を読み込み中は、まだ始められない(選び直した曲の難易度が出るまで)
		return
	if _song_sel >= 0:
		settings.last_song = _songs[_song_sel].path
		settings.last_diff = _loader.difficulties[_diff_sel].version
	Settings.save_all(settings)
	_audio.stop()
	if pick_mode:
		song_picked.emit(_loader, _loader.difficulties[_diff_sel], settings, float(_ratings[_diff_sel].level))
		return
	play_requested.emit(_loader, _loader.difficulties[_diff_sel], settings)


func _input(event: InputEvent) -> void:
	if _options != null or not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_UP, KEY_DOWN:
			var d := -1 if event.keycode == KEY_UP else 1
			if _focus_diff:
				_select_diff(_diff_sel + d)
			elif not event.echo:   # 曲の切替は重い(難易度の再計算)ので、押しっぱなしでは進めない
				_select_song(_song_sel + d)
			get_viewport().set_input_as_handled()
		KEY_LEFT, KEY_RIGHT, KEY_TAB:
			_focus_diff = (event.keycode == KEY_RIGHT) or (event.keycode == KEY_TAB and not _focus_diff)
			_restyle_all()
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			if not event.echo:
				_start()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if not event.echo:
				_audio.stop()
				back_requested.emit()
			get_viewport().set_input_as_handled()
		KEY_O:
			if not event.echo:
				open_options(0)
			get_viewport().set_input_as_handled()


# --- 開発用(スクリーンショット) ---

## MOD を指定して付けた状態にする。
func debug_set_mods(ids: Array) -> void:
	settings.mods = ids
	if _loader != null:
		_rate_all()
		_rebuild_diff_cards()
	_refresh_mod_bar()
