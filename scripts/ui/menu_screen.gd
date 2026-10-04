extends Control
## 選曲画面。左に曲、右に難易度カード。MOD は下の「MOD」ボタン(mod_panel.gd)、操作・音・画面・ゲームの設定は「設定」(options_panel.gd)に分けてある。
## .osz は、プロジェクト直下 / songs / 実行ファイルの隣 / user://songs を自動検出し、ドラッグ&ドロップや「開く」でも追加できる。
##
## 配置: 左上に「戻る」、右上に「設定」、右下に主ボタン(PLAY / 決定)。流れは 曲(左)→ 難易度(右)→ PLAY(右下)の一方向。
## 操作: マウスで全部できる(難易度のダブルクリックで開始)。キーは ↑↓ で曲、← → で難易度(易→難)、Enter 開始、M で MOD、O で設定、Esc でタイトルへ。

## pre: 選曲のときに作っておいたもの {gen: 選んだ難易度の弾幕(MOD 適用前), audio: 曲全体の音声(あれば)}。プレイ画面が、作り直さず(読み直さず)に使う
signal play_requested(loader, bm, settings: Dictionary, pre: Dictionary)
signal back_requested
## 設定を開く(パネルは main が持つ。どの画面でも開ける)。section: 0=操作 1=音 2=画面 3=その他
signal settings_requested(section: int)
## マルチプレイの部屋の曲を選ぶモード(pick_mode = true): 「決定」で、開始せずに選んだ内容を返す(level は MOD 適用後の Lv)
signal song_picked(loader, bm, settings: Dictionary, level: float)

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const PatternGenV2 = preload("res://scripts/game/pattern_gen_v2.gd")
const Settings = preload("res://scripts/settings.gd")
const Mods = preload("res://scripts/mods.gd")
const ModPanel = preload("res://scripts/ui/mod_panel.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Volume = preload("res://scripts/volume.gd")
const Ambient = preload("res://scripts/ui/ambient.gd")
const SmoothScroll = preload("res://scripts/ui/smooth_scroll.gd")
const SongLibrary = preload("res://scripts/song_library.gd")
const OszImport = preload("res://scripts/osz_import.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const UiFx = preload("res://scripts/ui/ui_fx.gd")

const BG_TINT := Color(0.34, 0.34, 0.4)

## 難易度カードの弾数バー(平均・最大)の満点
const BAR_MAX := 500.0
const LAUNCH_TIME := 0.4   # PLAY を押してから、次の画面へ切り替えるまでの演出の長さ(秒)

var kind := "menu"   # 画面の種類(main が、いまの画面を知るのに使う。ui_set.gd の契約)
var settings: Dictionary = {}
var pick_mode := false

var _songs: Array = []          # [{path, title, artist, key, key2, md5, folder}]
var _song_keys := {}            # key → _songs の index(重複の確認が、曲が何千あっても速いように)
var _song_key2s := {}           # key2(名前|大きさ) → index
var _song_md5s := {}            # 譜面の識別子 → index
var _osu_cursor := 0            # osu! の Songs の曲(SongLibrary.take_ready)を、どこまで一覧に足したか
var _osu_gen := 0               # 足している osu! の曲の一覧の世代(SongLibrary.osu_gen)。変わったら、足し直す
var _want_key := ""             # 前回選んでいた曲(まだ一覧に出ていなければ、出たときに選ぶ)
var _auto_sel_idx := -1         # 自動で選んだ曲の index(その曲のまま、ユーザーが触っていないときだけ、前回の曲に選び直す)
var _restore_key := ""          # 一覧を作り直す間、選んでいた曲(足し直されたときに、選択を戻す)
var _pump_status_at := 0.0
var _loader                     # 選択中の OszLoader
var _gens: Array = []           # 難易度リストと同じ並びの、MOD 適用前の弾幕(生成結果)
var _gens_v2 := false           # _gens が弾幕 v2(MOD)で作ったものか
var _reload_keep := ""          # MOD で弾幕の作り方(v1/v2)が変わって読み直すとき: 選んでいた難易度の version(空なら、ふつうの選曲)
var _ratings: Array = []        # 同じ並びの Danmaku 難易度(MOD 適用後)
var _song_sel := -1
var _diff_sel := -1
var _song_cards: Array = []
var _diff_cards: Array = []

var _bg: TextureRect            # 今見えている背景(もう 1 枚 _bg2 と交代でクロスフェードする)
var _bg2: TextureRect
var _bg_holder: Control
var _ambient: Node2D
var _par := Vector2.ZERO
var _drift: Tween               # 背景のゆっくりした拡大・縮小(発進のときに止めて、ズームインに切り替える)
var _play_btn: Button
var _launching := false         # 発進の演出中(操作は受け付けない)
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
var _v2_btn: Button                # 下部バーの「弾幕 v2 で遊ぼう」(v2 を付けていないときだけ出る)
const V2_BAR_WIDE := 496.0         # MOD のチップの欄の幅(v2 のボタンが出ていないとき)
const V2_BAR_NARROW := 284.0       # 同(v2 のボタンが出ているとき)
var _status: Label
var _empty_box: Control           # 曲が 1 つもないときだけ、右側に出す案内
var _loading_tween: Tween         # 読み込みが長引いたときに、一覧を薄くする
var _audio: AudioStreamPlayer
var _dialog: FileDialog
var _options: Control            # 開いている設定パネル(main が持つ。開いている間だけ設定される)
var _mod_panel: Control          # 開いている MOD パネル
var _full_audio: AudioStream      # 選んでいる曲の、全体の音声(試聴用は途中から切り出したもの。プレイ画面へ渡す)
var _full_audio_file := ""


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
		_drift = drift
		drift.tween_property(_bg_holder, "scale", Vector2(1.08, 1.08), 22.0).from(Vector2(1.02, 1.02)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		drift.tween_property(_bg_holder, "scale", Vector2(1.02, 1.02), 22.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.025, 0.05, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_ambient = Ambient.new()   # 背景で漂うリング
	add_child(_ambient)

	# --- 左上: 戻る(どの画面も同じ場所)とロゴ ---
	var back_btn := Button.new()
	back_btn.text = "◀  ロビー" if pick_mode else "◀  タイトル"
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.pressed.connect(func(): back_requested.emit())
	_intro_nodes.append(_place(back_btn, 32, 20, 116, 34))
	_buttons.append(back_btn)
	_intro_nodes.append(_place(UiStyle.label("Danmaku", 30, UiStyle.ACCENT, true), 164, 18, 200, 40))
	# --- 左: 曲リスト ---
	_intro_nodes.append(_place(UiStyle.caption("SONGS"), 38, 96, 200, 16))
	_song_scroll = ScrollContainer.new()
	_song_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_place(_song_scroll, 32, 118, 404, 494)
	_song_smooth = SmoothScroll.attach(_song_scroll, true)   # ドラッグでもスクロールできる(左 = ふつう・右 = 速い)
	_song_smooth.active = _lists_active
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
	_place(_title_l, 468, 26, 690, 40)   # 右上の「設定」ボタン(1174〜)に重ならない幅
	_artist_l = UiStyle.label("", 16, UiStyle.TEXT_DIM)
	_artist_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_place(_artist_l, 468, 70, 780, 24)
	_meta_l = UiStyle.label("", 13, UiStyle.TEXT_FAINT)
	_place(_meta_l, 468, 98, 780, 20)
	_place(UiStyle.caption("DIFFICULTY"), 470, 146, 780, 16)
	_diff_scroll = ScrollContainer.new()
	_diff_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_place(_diff_scroll, 468, 168, 780, 384)
	_diff_smooth = SmoothScroll.attach(_diff_scroll, true)
	_diff_smooth.active = _lists_active
	_diff_box = VBoxContainer.new()
	_diff_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diff_box.add_theme_constant_override("separation", 6)
	_diff_scroll.add_child(_diff_box)

	var detail := PanelContainer.new()
	detail.add_theme_stylebox_override("panel", UiStyle.box(Color(0, 0, 0, 0.35), UiStyle.LINE, 1, 5, 14, 8))
	_intro_nodes.append(_place(detail, 468, 562, 780, 38))
	_detail_l = UiStyle.label("", 13, UiStyle.TEXT_DIM)
	detail.add_child(_detail_l)

	# --- 右上: 設定(戻るの反対側。どの画面も同じ場所) ---
	var opt_btn := Button.new()
	opt_btn.text = "設定"
	opt_btn.focus_mode = Control.FOCUS_NONE
	opt_btn.pressed.connect(func(): open_options(0))
	_intro_nodes.append(_place(opt_btn, 1174, 14, 90, 34))
	_buttons.append(opt_btn)

	# --- 下部バー: 左に MOD(付けたものがチップで並ぶ)、右下に主ボタン(PLAY / 決定) ---
	var mod_btn := Button.new()
	mod_btn.text = "MOD"
	mod_btn.focus_mode = Control.FOCUS_NONE
	mod_btn.pressed.connect(open_mods)
	_intro_nodes.append(_place(mod_btn, 468, 626, 96, 40))
	_buttons.append(mod_btn)
	_mod_bar = HBoxContainer.new()
	_mod_bar.add_theme_constant_override("separation", 8)
	_mod_bar.clip_contents = true
	_intro_nodes.append(_place(_mod_bar, 576, 626, V2_BAR_WIDE, 40))
	_build_v2_button()
	var play := Button.new()
	play.text = "決定" if pick_mode else "PLAY"
	play.focus_mode = Control.FOCUS_NONE
	UiStyle.style_primary(play)
	play.disabled = true   # 曲を読み込み終わるまで押せない(_set_loading が切り替える)
	play.pressed.connect(_start)
	_play_btn = play
	_intro_nodes.append(_place(play, 1096, 622, 152, 48))
	_buttons.append(play)
	_status = UiStyle.label("", 12, UiStyle.TEXT_FAINT)   # 読み込みに失敗したときのメッセージ用(難易度の詳細の下)
	_place(_status, 470, 604, 778, 18)
	_build_empty()

	_audio = AudioStreamPlayer.new()
	Volume.route_music(_audio)   # 音楽バスへ(ホイールなどの「音楽」の音量が効く)
	_audio.volume_db = -6.0
	add_child(_audio)
	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.filters = PackedStringArray(["*.osz ; osu! beatmap"])
	_dialog.use_native_dialog = true
	_dialog.file_selected.connect(_import_and_select)
	add_child(_dialog)

	_refresh_mod_bar()
	_intro()
	_want_key = SongLibrary.norm(str(settings.last_song))
	_osu_gen = SongLibrary.osu_gen
	SongLibrary.start_osu_warmup()   # osu! の Songs の曲は、裏で調べる。できた曲から、_process で少しずつ足す(何千曲あっても画面が止まらない)
	_scan()
	_rebuild_song_cards()
	if not _songs.is_empty():
		var pick := 0
		for i in range(_songs.size()):
			if _songs[i].key == _want_key:
				pick = i
		_select_song(pick)
		_auto_sel_idx = pick
		_center_selected()


func _process(delta: float) -> void:
	_par = UiStyle.parallax(_bg_holder, _ambient, _par, delta, get_viewport())
	_pump_osu()


## 画面を開いたときの入場: 見出し・下部バー・ボタンが順に滑り込み、ボタンはホバーで少し大きくなる。
func _intro() -> void:
	var k := 0
	for c in _intro_nodes:
		var from := Vector2(-24, 0)   # 左の見出し・曲リストは、左から
		if c.position.y > 500.0:
			from = Vector2(0, 18)   # 下の段は、下から
		elif c.position.x > 1000.0:
			from = Vector2(0, -18)   # 右上の「設定」は、上から
		UiStyle.pop_in(c, 0.05 + k * 0.05, from, 0.5)
		k += 1
	for b in _buttons:
		UiStyle.hover_scale(b)


## 曲が 1 つもないとき、右側に出す案内(曲の入れ方へ誘導するボタン付き)。曲が入ると隠れる。
func _build_empty() -> void:
	_empty_box = VBoxContainer.new()
	_empty_box.add_theme_constant_override("separation", 14)
	_empty_box.visible = false
	var v: VBoxContainer = _empty_box
	v.add_child(UiStyle.label("曲がありません", 28, UiStyle.TEXT, true))
	v.add_child(UiStyle.label("osu! の譜面(.osz)を追加してください", 16, UiStyle.TEXT_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var add := Button.new()
	add.text = ".osz を開く…"
	add.focus_mode = Control.FOCUS_NONE
	add.custom_minimum_size = Vector2(190, 44)
	UiStyle.style_primary(add)
	add.pressed.connect(func(): _dialog.popup_centered_ratio(0.7))
	row.add_child(add)
	var folder := Button.new()
	folder.text = "曲フォルダを開く"
	folder.focus_mode = Control.FOCUS_NONE
	folder.custom_minimum_size = Vector2(190, 44)
	folder.pressed.connect(func(): OS.shell_open(SongLibrary.ensure_user_dir()))
	row.add_child(folder)
	v.add_child(row)
	_place(_empty_box, 468, 200, 700, 160)


func _sync_empty() -> void:
	if _empty_box != null:
		_empty_box.visible = _songs.is_empty() and not (SongLibrary.osu_dir != "" and bool(SongLibrary.warm_progress().running))   # osu! の曲を調べている間は、「曲がありません」を出さない


## 曲の読み込み中の見た目: 難易度の一覧を薄くして「読み込み中…」と出し、PLAY を押せなくする。
## 薄くするのは、0.25 秒たってもまだ読み込み中のときだけ(すぐ終わる読み込みで、一覧が明滅しないように)。
## 一覧の透明度を動かす tween は、_loading_tween の 1 本だけにする(暗くする動きと戻す動きが同時に走って、暗いまま残ることがないように)。
func _set_loading(on: bool) -> void:
	if _loading_tween != null and _loading_tween.is_valid():
		_loading_tween.kill()
	if _diff_scroll != null:
		if on:
			if UiStyle.animate and is_inside_tree():
				_loading_tween = create_tween()
				_loading_tween.tween_interval(0.25)
				_loading_tween.tween_callback(func(): _detail_l.text = "読み込み中…")
				_loading_tween.tween_property(_diff_scroll, "modulate:a", 0.35, 0.18)
		elif UiStyle.animate and is_inside_tree() and _diff_scroll.modulate.a < 0.999:
			_loading_tween = create_tween()
			_loading_tween.tween_property(_diff_scroll, "modulate:a", 1.0, 0.15)
		else:
			_diff_scroll.modulate.a = 1.0
	if _play_btn != null:
		_play_btn.disabled = on or _loader == null
	if _v2_btn != null:
		_v2_btn.disabled = on or _loader == null


## 画面の下のほうに、メッセージを出す(失敗したときなど。赤い文字で、読み落としにくくする)。
func _set_status(msg: String) -> void:
	_status.text = msg
	_status.add_theme_color_override("font_color", UiStyle.DANGER)


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


func _clear_songs() -> void:
	_songs.clear()
	_song_keys.clear()
	_song_key2s.clear()
	_song_md5s.clear()


## 起動時: .osz の曲を一覧にする(osu! の Songs の曲は、_pump_osu が少しずつ足す)。
func _scan() -> void:
	_clear_songs()
	_osu_cursor = 0
	var paths := SongLibrary.find_osz()   # 同じファイルは 1 つにまとめて返る
	var failed := _add_songs(paths)
	SongLibrary.save_index(paths)
	_report_failed(failed)


func _add_songs(paths: Array) -> Array:
	var failed: Array = []
	for p in paths:
		if _add_song(p) < 0:
			failed.append(str(p).get_file())
	return failed


func _report_failed(failed: Array) -> void:
	if not failed.is_empty():   # 読めなかった曲は、黙って飛ばさず、名前を出す
		_set_status("読み込めなかった曲: " + ", ".join(failed.slice(0, 3)) + (" ほか %d 件" % (failed.size() - 3) if failed.size() > 3 else ""))


## songs フォルダの中身が変わったとき(main が知らせる): 一覧を更新する。選んでいる曲はそのまま(読み込み直さない)。
## すでに一覧にある曲(何千曲の osu! の曲も)は作り直さず、増えた .osz を足し、なくなった曲を外す。osu! の Songs の設定が変わったときだけ、osu! の曲を足し直す。
func refresh_songs() -> void:
	var cur := ""
	if _song_sel >= 0 and _song_sel < _songs.size():
		cur = str(_songs[_song_sel].key)
	var osu_reset := SongLibrary.osu_gen != _osu_gen   # osu! の Songs の設定が変わった
	_osu_gen = SongLibrary.osu_gen
	SongLibrary.start_osu_warmup()
	var keep: Array = []
	for sg in _songs:
		if sg.folder:
			if not osu_reset:
				keep.append(sg)
		elif FileAccess.file_exists(sg.path):
			keep.append(sg)
	var removed := keep.size() != _songs.size()
	if removed:
		_clear_songs()
		for sg in keep:
			_register_song(sg)
	if osu_reset:
		_osu_cursor = 0
		if cur != "" and (not _song_keys.has(cur)):
			_restore_key = cur   # 足し直されたときに、選択を戻す
	var paths := SongLibrary.find_osz()
	var failed := _add_songs(paths)
	SongLibrary.save_index(paths)
	_report_failed(failed)
	_song_sel = int(_song_keys.get(cur, -1))
	if removed:
		_rebuild_song_cards(false)
	else:
		_sync_cards()
	if _song_sel < 0 and not _songs.is_empty() and _loader == null and _restore_key == "":
		_select_song(0)


## osu! の Songs の、索引ができた曲を、少しずつ一覧に足す(毎フレーム、4ms まで。何千曲あっても、画面が止まらない)。
func _pump_osu() -> void:
	if SongLibrary.osu_dir == "" or _osu_gen != SongLibrary.osu_gen:
		return
	var t0 := Time.get_ticks_usec()
	var added := false
	while Time.get_ticks_usec() - t0 < 4000:
		var batch := SongLibrary.take_ready(_osu_cursor, 10)
		if batch.is_empty():
			break
		_osu_cursor += batch.size()
		for e in batch:
			var n := _songs.size()
			var idx := _append_song(str(e.path), e.info, true)
			if idx == n:
				added = true
	if added:
		_sync_cards()
		_pump_select()
	_pump_progress()


## 足した曲のうち、選び直すもの: 一覧を作り直す前に選んでいた曲(選択を戻す)/ 前回の曲(自動で選んだままなら、そこへ移す)/ 何も選ばれていなければ最初の曲。
func _pump_select() -> void:
	if _restore_key != "" and _song_keys.has(_restore_key):
		_song_sel = int(_song_keys[_restore_key])
		_restore_key = ""
		_restyle_all()
		return
	if _want_key != "" and _song_keys.has(_want_key) and _auto_sel_idx >= 0 and _song_sel == _auto_sel_idx and _song_sel != int(_song_keys[_want_key]):
		_auto_sel_idx = int(_song_keys[_want_key])
		_select_song(_auto_sel_idx)   # ユーザーがまだ触っていないので、前回の曲へ
		_center_selected()
		return
	if _song_sel < 0 and _loader == null and not _job_pending and _restore_key == "" and not _songs.is_empty():
		_auto_sel_idx = int(_song_keys.get(_want_key, 0))
		_select_song(_auto_sel_idx)
		_center_selected()


## 画面を開いたときに選んだ曲(前回の曲)を、曲の一覧の真ん中に出す(プレイから戻ったとき、一覧の先頭が出ないように)。
## カードの位置は、レイアウトが終わるまで決まらないので、2 フレーム待ってから、動かさずに置く。待っている間に、ユーザーが別の曲を選んだら、何もしない。
func _center_selected() -> void:
	var want := _song_sel
	if want < 0 or not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or _song_sel != want or want >= _song_cards.size():
		return
	_song_smooth.center_on_control(_song_cards[want], true)


## osu! の曲を調べている間の、進み具合(画面の下に、薄い文字で)。
func _pump_progress() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _pump_status_at < 0.3 or _status == null:
		return
	_pump_status_at = now
	var pr := SongLibrary.warm_progress()
	var mine := _status.text.begins_with("osu! の曲")
	if bool(pr.running) and (_status.text == "" or mine):
		_status.text = "osu! の曲を準備しています… %d / %d" % [pr.done, pr.total]
		_status.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
		_sync_empty()
	elif mine:
		_status.text = ""
		_sync_empty()


## 追加して一覧の index を返す(重複は既存の index、読めなければ -1)。カードは _rebuild_song_cards で作る。
func _add_song(path: String) -> int:
	path = path.replace("\\", "/")
	var key := SongLibrary.norm(path)
	var size := SongLibrary.file_size(path)
	var key2 := "%s|%d" % [path.get_file().to_lower(), size]
	if _song_keys.has(key):   # すでに一覧にある(パスが同じ、または名前と大きさが同じ)
		return _song_keys[key]
	if size >= 0 and _song_key2s.has(key2):
		return _song_key2s[key2]
	var info := SongLibrary.info(path)   # 曲を全部は開かずに、題名などを得る(結果は保存されて、次からは開き直さない)
	if not info.ok:
		_last_error = str(info.error)
		return -1
	return _append_song(path, info, false)


## 索引の要約(info)から、一覧に足して index を返す(重複は既存の index)。ファイルには触らない(osu! の曲を何千も足すため)。
func _append_song(path: String, info: Dictionary, folder: bool) -> int:
	path = path.replace("\\", "/")
	var key := SongLibrary.norm(path)
	if _song_keys.has(key):
		return _song_keys[key]
	var key2 := "%s|%d" % [path.get_file().to_lower(), -1 if folder else SongLibrary.file_size(path)]
	if not folder and _song_key2s.has(key2):
		return _song_key2s[key2]
	if _song_md5s.has(info.md5):   # 別の名前で同じ曲が入っている(譜面の中身が同じ)ときも、1 つにする
		return _song_md5s[info.md5]
	var sg := {"path": path, "title": info.title, "artist": info.artist, "key": key, "key2": key2, "md5": info.md5, "folder": folder}
	_songs.append(sg)
	_register_song(sg, _songs.size() - 1)
	return _songs.size() - 1


func _register_song(sg: Dictionary, idx := -1) -> void:
	if idx < 0:
		_songs.append(sg)
		idx = _songs.size() - 1
	_song_keys[sg.key] = idx
	_song_key2s[sg.key2] = idx
	_song_md5s[sg.md5] = idx


func _add_song_and_select(path: String) -> void:
	var i := _add_song(path)
	if i < 0:
		_set_status("%s を読み込めませんでした: %s" % [path.get_file(), SongLibrary.info(path).error])
		return
	_rebuild_song_cards()
	_select_song(i)


## 「.osz を開く…」で選んだファイル: songs に取り込んで(次の起動でも残る)、一覧に加えて選ぶ。ドロップは main が受け取り、select_path で届く。
func _import_and_select(path: String) -> void:
	var r := OszImport.import_file(path)
	if not r.ok:
		_set_status(str(r.error))
		return
	_add_song_and_select(str(r.path))


## main から: 取り込み済みの曲(のパス)を、一覧に加えて選ぶ。
func select_path(path: String) -> void:
	_add_song_and_select(path)


# --- 曲リスト ---

func _rebuild_song_cards(animate := true) -> void:
	for c in _song_box.get_children():
		c.queue_free()
	_song_cards.clear()
	for i in range(_songs.size()):
		_make_song_card(i, animate)
	_sync_empty()


## 一覧に足された曲(_song_cards にまだないもの)のカードを作る。
func _sync_cards() -> void:
	for i in range(_song_cards.size(), _songs.size()):
		_make_song_card(i, false)
	_sync_empty()


func _make_song_card(i: int, animate: bool) -> void:
	var card := UiStyle.card(56, func(): _select_song(i))
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
	card.mouse_entered.connect(func():
		card.set_meta("hover", true)
		if i != _song_sel:
			UiSfx.play("hover", 1.0)
		_restyle_song(i))
	card.mouse_exited.connect(func(): card.set_meta("hover", false); _restyle_song(i))
	_song_box.add_child(UiStyle.wrap_card(card, 56))
	_song_cards.append(card)
	_restyle_song(i)
	if animate:
		UiStyle.enter_card(card, 0.08 + mini(i, 10) * 0.06, -40.0)   # 左から順に滑り込む(曲が多くても、後ろの曲を待たせない)


func _restyle_song(i: int) -> void:
	if i < 0 or i >= _song_cards.size():
		return
	var c: PanelContainer = _song_cards[i]
	var sel := (i == _song_sel)
	var hover := bool(c.get_meta("hover", false))
	UiStyle.style_card(c, sel, true, UiStyle.ACCENT, hover)
	UiStyle.shift_card(c, 10.0 if sel else (4.0 if hover else 0.0))   # 選択中・ホバー中は少し右へ


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
	UiSfx.play("select", UiSfx.scale_pitch(float(i % 6) / 5.0, 1.0))   # 曲を移るごとに、音階が上がる・下がる
	_restyle_song(old)
	_restyle_song(i)
	_song_smooth.scroll_to_control(_song_cards[i])
	# 曲名などは、一覧に持っている値をすぐ出す
	_title_l.text = _songs[i].title
	_artist_l.text = _songs[i].artist
	_meta_l.text = ""
	_job += 1
	_job_pending = true
	_set_loading(true)
	_reload_keep = ""
	_start_load_job(_songs[i].path)


## 曲の読み込み(別スレッド)を始める。結果は _on_song_loaded へ(いまの _job のものだけが使われる)。
func _start_load_job(path: String) -> void:
	var job := _job
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


## MOD で弾幕の作り方(v1 / v2)が変わった: 同じ曲を読み直す。弾幕は作り方ごとに覚えているので、戻すときは速い。
## 選んでいた難易度はそのまま、試聴も止めない。
func _reload_for_style() -> void:
	if _loader == null or _job_pending or _song_sel < 0 or _song_sel >= _songs.size():
		return
	_reload_keep = str(_loader.difficulties[_diff_sel].version) if _diff_sel >= 0 else ""
	_job += 1
	_job_pending = true
	_set_loading(true)
	_start_load_job(_songs[_song_sel].path)


## 前の曲の OszLoader を、別スレッドで手放す(主スレッドで手放すと止まる)。弾幕の一覧は、キャッシュ(_gen_cache)と共有しているので、ここでは壊さない。
func _release_later(old_loader) -> void:
	if old_loader == null:
		return
	WorkerThreadPool.add_task(func():
		old_loader.close()
		old_loader.difficulties.clear())


## 弾幕のキャッシュ(曲のファイル → 難易度の並び順と、MOD 適用前の弾幕)。別スレッドからも使うので、Mutex で守る。新しく使ったものを末尾にして、古いものから捨てる。
const GEN_CACHE_MAX := 10
static var _gen_cache: Dictionary = {}
static var _gen_cache_keys: Array = []
static var _gen_mutex := Mutex.new()


static func _gen_cache_get(key: String, count: int) -> Dictionary:
	_gen_mutex.lock()
	var hit: Dictionary = {}
	if _gen_cache.has(key) and (_gen_cache[key].order as Array).size() == count:
		hit = _gen_cache[key]
		_gen_cache_keys.erase(key)
		_gen_cache_keys.append(key)
	_gen_mutex.unlock()
	return hit


static func _gen_cache_put(key: String, order: Array, gens: Array) -> void:
	_gen_mutex.lock()
	_gen_cache[key] = {"order": order, "gens": gens}
	_gen_cache_keys.erase(key)
	_gen_cache_keys.append(key)
	while _gen_cache_keys.size() > GEN_CACHE_MAX:
		_gen_cache.erase(_gen_cache_keys.pop_front())
	_gen_mutex.unlock()


## 弾幕を作る。v2 = MOD「弾幕 v2」(PatternGenV2)。
static func _make_gen(bm, v2: bool) -> Dictionary:
	return PatternGenV2.generate(bm, {}) if v2 else PatternGen.generate(bm, {})


## (別スレッドで動く)曲を開いて、難易度ごとの弾幕・難易度(MOD 適用後)・背景画像・試聴用の音声まで作る。画面には触らない。
static func _load_song(path: String, mod_params: Dictionary) -> Dictionary:
	var l = OszLoader.new()
	if not l.open(path):
		return {"ok": false, "error": l.error}
	var first = l.difficulties[0]
	var image: Image = l.load_image_data(first.background) if first.background != "" else null
	if image != null and image.get_width() > 1280:   # 背景は 1280×720 の画面に出すだけ。大きい画像は、ここ(別スレッド)で縮めて、テクスチャにする負担を減らす
		image.resize(1280, maxi(int(round(1280.0 * image.get_height() / image.get_width())), 1), Image.INTERPOLATE_BILINEAR)
	# Danmaku 難易度(Lv。MOD なしの状態)の低い順に並べ替える
	# 弾幕の生成が読み込みの大半(1 難易度で 20〜200 ms)。一度作った曲は覚えておき(直近 GEN_CACHE_MAX 曲)、次からは作らない。
	# 作るときは、難易度どうしが独立なので並列に作る(generate は共有の状態を持たない)。MOD の適用は別(下の ratings)なので、MOD を変えても使える
	var diffs: Array = l.difficulties
	var v2 := bool(mod_params.get("gen_v2", false))   # MOD「弾幕 v2」: 弾幕の作り方が違うので、覚えておくのも別(v1 / v2 の両方を覚える)
	var key := "%s|%d|%d|%s" % [path, SongLibrary.file_size(path), FileAccess.get_modified_time(path), "v2" if v2 else "v1"]   # ファイルが差し替わったら別物
	var gens: Array = []
	var cached := _gen_cache_get(key, diffs.size())
	if not cached.is_empty():
		var order: Array = cached.order
		l.difficulties = order.map(func(i): return diffs[i])
		gens = cached.gens
	else:
		var made: Array = []
		made.resize(diffs.size())
		if diffs.size() > 1:
			var gid := WorkerThreadPool.add_group_task(func(i: int): made[i] = _make_gen(diffs[i], v2), diffs.size())
			WorkerThreadPool.wait_for_group_task_completion(gid)
		else:
			made[0] = _make_gen(diffs[0], v2)
		var pairs: Array = []
		for i in range(diffs.size()):
			pairs.append({"i": i, "bm": diffs[i], "g": made[i]})
		# 並びは表示する Lv の低い順(同じなら本家★)。生の密度(rating.score)では、弾速が AR で変わる弾幕 v2 で Lv と順が食い違う
		pairs.sort_custom(func(a, b): return a.g.level < b.g.level if not is_equal_approx(a.g.level, b.g.level) else a.g.stars < b.g.stars)
		l.difficulties = pairs.map(func(q): return q.bm)
		gens = pairs.map(func(q): return q.g)
		_gen_cache_put(key, pairs.map(func(q): return q.i), gens)
	var ratings: Array = gens.map(func(g): return PatternGen.summary(Mods.apply(g, mod_params)))
	var audio: AudioStream = l.load_audio(first.audio_filename)
	var from := maxf(first.preview_time / 1000.0, 0.0)
	var full: AudioStream = audio
	var cropped := _crop_mp3(audio, from)
	if cropped != null:   # MP3 の途中から流すと、探す処理で数十 ms 止まる。あらかじめ、その位置から始まる音声にしておく
		audio = cropped
		from = 0.0
	return {"ok": true, "loader": l, "gens": gens, "v2": v2, "ratings": ratings, "image": image, "audio": audio, "audio_from": from, "audio_full": full, "audio_file": first.audio_filename}


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
		_reload_keep = ""
		_set_status(str(res.error))
		var bad := _song_sel
		_song_sel = _prev_sel   # 選べなかったので、元の曲の選択に戻す
		_restyle_song(bad)
		_restyle_song(_song_sel)
		if _loader != null and _song_sel >= 0 and _song_sel < _songs.size():
			_title_l.text = _songs[_song_sel].title
			_artist_l.text = _songs[_song_sel].artist
		_set_loading(false)   # 前の曲の難易度が残っていれば、それをまた選べる
		_update_detail()
		return
	var reload := _reload_keep != ""   # MOD で弾幕の作り方が変わった読み直し: 曲情報は滑り込ませず、選んでいた難易度に戻し、試聴は止めない
	_release_later(_loader)   # 前の曲の譜面は、量が多く、ここで手放すと解放だけで十数 ms かかる
	_loader = res.loader
	var i := _song_sel
	var first = _loader.difficulties[0]
	_meta_l.text = "BPM %.0f     Creator  %s" % [60000.0 / first.beat_length_at(first.first_time()), first.creator]
	var k := 0
	for lab in ([] if reload else [_title_l, _artist_l, _meta_l]):   # 曲情報は順に滑り込む
		UiStyle.pop_in(lab, k * 0.07, Vector2(30, 0), 0.45)
		k += 1
	var tex: Texture2D = null
	if res.image != null:
		tex = ImageTexture.create_from_image(res.image)
	_set_background(tex)
	_gens = res.gens
	_gens_v2 = bool(res.v2)
	_full_audio = res.audio_full
	_full_audio_file = str(res.audio_file)
	# 曲を移ったときは、前に選んでいた難易度に Lv がいちばん近いものを選ぶ(Lv 7 を遊んでいる人が、曲を変えるたびに易しい譜面に戻らない)。最初の 1 回は 3 番目
	var prev_lv := -1.0
	if _diff_sel >= 0 and _diff_sel < _ratings.size():
		prev_lv = float(_ratings[_diff_sel].level)
	_ratings = res.ratings
	_diff_sel = mini(2, _gens.size() - 1)
	if prev_lv >= 0.0:
		var best := INF
		for k3 in range(_ratings.size()):
			var gap := absf(float(_ratings[k3].level) - prev_lv)
			if gap < best:
				best = gap
				_diff_sel = k3
	# 直前にプレイした曲に戻ったときは、そのとき選んだ難易度を選んだ状態にする
	if _songs[i].key == SongLibrary.norm(str(settings.last_song)) and settings.last_diff != "":
		for k2 in range(_loader.difficulties.size()):
			if _loader.difficulties[k2].version == settings.last_diff:
				_diff_sel = k2
	if reload:
		for k2 in range(_loader.difficulties.size()):
			if str(_loader.difficulties[k2].version) == _reload_keep:
				_diff_sel = k2
		_reload_keep = ""
	else:
		_lv_shown.clear()
	_rebuild_diff_cards(not reload)
	_set_loading(false)
	if _mod_panel != null:   # MOD パネルを開いたまま曲が読み込まれた
		_mod_panel.refresh_info()
	if reload:
		_reload_if_style_changed()
		return
	_audio.stop()
	if res.audio != null:
		await get_tree().process_frame   # カードを作る処理と、同じフレームにしない(音の開始も、少し時間がかかる)
		if int(res.job) == _job and is_inside_tree():
			_audio.stream = res.audio
			_audio.play(float(res.audio_from))
	_reload_if_style_changed()


## 読み込んでいるあいだに MOD(弾幕 v2 の入り切り)が変わっていたら、弾幕を作り直すために読み直す。
func _reload_if_style_changed() -> void:
	if is_inside_tree() and not _job_pending and bool(Mods.params(settings.mods).gen_v2) != _gens_v2:
		_reload_for_style()


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
		var card := UiStyle.card(68, func(): _select_diff(i), func(): _start())
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
		card.mouse_entered.connect(func():
			card.set_meta("hover", true)
			if i != _diff_sel:
				UiSfx.play("hover", 1.15)
			_restyle_diff(i))
		card.mouse_exited.connect(func(): card.set_meta("hover", false); _restyle_diff(i))
		_diff_box.add_child(UiStyle.wrap_card(card, 68))
		_diff_cards.append(card)
		_restyle_diff(i)
		var delay := (i * 0.035) if animate_in else 0.0   # (出現の段差は短く。一覧がすぐ見えるように)
		if animate_in:
			UiStyle.enter_card(card, delay, 50.0)
		# Lv は数え上がり(または前の値から)、弾数バーは左から伸びる
		var key: String = bm.version
		var from_lv: float = 0.0 if animate_in else float(_lv_shown.get(key, r.level))
		var set_lv := func(v: float):
			lv_l.text = "%.2f" % v
			lv_l.add_theme_color_override("font_color", UiStyle.level_color(v))
			_lv_shown[key] = v
		UiStyle.tween_value(lv_l, from_lv, r.level, 0.4, set_lv, delay + (0.03 if animate_in else 0.0))
		var state: Dictionary = bars.get_meta("state")
		var grow := func(v: float):
			state.p = v
			bars.queue_redraw()
		UiStyle.tween_value(bars, 0.0, 1.0, 0.5, grow, delay + 0.05)
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
	UiStyle.style_card(c, sel, true, col, hover)
	UiStyle.shift_card(c, 10.0 if sel else (4.0 if hover else 0.0))


func _restyle_all() -> void:
	for i in range(_song_cards.size()):
		_restyle_song(i)
	for i in range(_diff_cards.size()):
		_restyle_diff(i)


func _select_diff(i: int) -> void:
	if _ratings.is_empty() or _loader == null:
		return
	i = clampi(i, 0, _ratings.size() - 1)   # (カードは数フレームに分けて作るので、作成済みの枚数ではなく、難易度の数で止める)
	var old := _diff_sel
	_diff_sel = i
	if old != i:
		UiSfx.play("select", 1.35 * UiSfx.scale_pitch(float(i % 6) / 5.0, 1.0))
	_restyle_all()
	if i < _diff_cards.size():
		_diff_smooth.scroll_to_control(_diff_cards[i])
	_update_detail()
	if _mod_panel != null and old != i:
		_mod_panel.refresh_info()


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
	if _v2_btn != null:   # 弾幕 v2 を付けていないときだけ、右に「弾幕 v2 で遊ぼう」のボタンを出す。出ている間は、チップの幅を狭める
		var want: bool = not p.gen_v2
		if want and not _v2_btn.visible:
			_v2_btn.visible = true
			UiStyle.pop_scale(_v2_btn, 0.9, 0.3)
		_v2_btn.visible = want
		_mod_bar.size.x = V2_BAR_NARROW if want else V2_BAR_WIDE
	if p.ids.is_empty():
		var none := UiStyle.label("MOD なし", 13, UiStyle.TEXT_FAINT)
		none.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_mod_bar.add_child(none)
		return
	var k := 0
	for id in p.ids:
		var m := Mods.find(id)
		var chip := UiStyle.chip(m.name, m.color)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_mod_bar.add_child(chip)
		UiStyle.pop_scale(chip, 0.5, 0.35, 0.05 * k)   # チップは、弾んで現れる
		k += 1
	var sc := UiStyle.label("ベーススコア ×%.4f" % p.score_mul, 13, UiStyle.TEXT_DIM)
	sc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mod_bar.add_child(sc)


# --- 設定パネル ---

## main が設定パネルを開いた・閉じた(ui_set.gd の契約)。開いている間は、キーも MOD パネルも受け付けない
func on_overlay(open: bool, panel: Control = null) -> void:
	_options = panel if open else null


func open_options(section := 0) -> void:
	settings_requested.emit(section)


## MOD パネルを開く。
func open_mods() -> void:
	if _mod_panel != null or _options != null or _launching:
		return
	var p := ModPanel.new()
	p.theme = UiStyle.make_theme()
	p.multi = pick_mode
	p.setup(settings, _mod_level)
	p.changed.connect(_on_mods_changed)
	p.closed.connect(_close_mods)
	_mod_panel = p
	add_child(p)


## 下部バーの「弾幕 v2 で遊ぼう」: MOD「弾幕 v2」の色の枠のボタン(右の PLAY の隣。付けるまで出る)。押すと v2 を付けて、曲を読み直す。
func _build_v2_button() -> void:
	var c: Color = Mods.find("v2").color
	var b := Button.new()
	b.text = "弾幕 v2 で遊ぼう   ＋"
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "MOD「弾幕 v2」を付ける: 譜面ごとに特徴の出る弾幕と、特殊エリア(体力 300ms)。いつでも MOD から外せます"
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_font_override("font", UiStyle.bold())
	b.add_theme_stylebox_override("normal", UiStyle.box(Color(c.r, c.g, c.b, 0.14), Color(c.r, c.g, c.b, 0.85), 2, 6, 14, 8))
	b.add_theme_stylebox_override("hover", UiStyle.box(Color(c.r, c.g, c.b, 0.30), c, 2, 6, 14, 8))
	b.add_theme_stylebox_override("pressed", UiStyle.box(Color(c.r, c.g, c.b, 0.45), c, 2, 6, 14, 8))
	b.add_theme_stylebox_override("disabled", UiStyle.box(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.15), 2, 6, 14, 8))
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, c)
	b.add_theme_color_override("font_disabled_color", UiStyle.TEXT_FAINT)
	b.pressed.connect(_enable_v2)
	_v2_btn = b
	_intro_nodes.append(_place(b, 868, 626, 216, 40))
	_buttons.append(b)


## 「弾幕 v2 で遊ぼう」を押した: MOD「弾幕 v2」を付ける。
func _enable_v2() -> void:
	if _launching or _mod_panel != null or _options != null:
		return
	var ids: Array = settings.mods.duplicate()
	if not ids.has("v2"):
		ids.append("v2")
	settings.mods = ids
	Settings.save_all(settings)
	_refresh_mod_bar()
	_on_mods_changed()


## MOD が変わった: 難易度を測り直す。
func _on_mods_changed() -> void:
	if _loader == null:
		return
	if bool(Mods.params(settings.mods).gen_v2) != _gens_v2:   # 弾幕 v2 の入り切り: 弾幕そのものが変わるので、曲を読み直す(終わったら難易度も出る)
		_reload_for_style()
		return
	_rate_all()
	_rebuild_diff_cards()
	if _mod_panel != null:
		_mod_panel.refresh_info()


func _close_mods() -> void:
	if _mod_panel == null:
		return
	var p := _mod_panel
	_mod_panel = null
	Settings.save_all(settings)
	p.queue_free()


## MOD パネルに出す、選択中の難易度の MOD 適用後 Lv(難易度がなければ -1)。
func _mod_level() -> float:
	if _diff_sel < 0 or _diff_sel >= _ratings.size():
		return -1.0
	return float(_ratings[_diff_sel].level)


## 曲・難易度の一覧がホイールを受け付けるか(MOD パネルや設定パネルが上に重なっているときは、受け付けない)。
func _lists_active() -> bool:
	return _mod_panel == null and _options == null


# --- 開始 ---

func _start() -> void:
	if _loader == null or _diff_sel < 0 or _job_pending or _launching:   # 曲を読み込み中は、まだ始められない(選び直した曲の難易度が出るまで)
		return
	if _song_sel >= 0:
		settings.last_song = _songs[_song_sel].path
		settings.last_diff = _loader.difficulties[_diff_sel].version
	Settings.save_all(settings)
	UiSfx.play("confirm")
	# 発進: すぐには切り替えず、選んだ難易度が前に出て、ほかが退き、背景がズームインして、曲が小さくなる(0.4 秒)。それから次の画面へ
	_launching = true
	_launch_anim()
	if UiStyle.animate:
		await get_tree().create_timer(LAUNCH_TIME).timeout
		if not is_inside_tree():
			return
	_audio.stop()
	if pick_mode:
		song_picked.emit(_loader, _loader.difficulties[_diff_sel], settings, float(_ratings[_diff_sel].level))
		return
	var bm = _loader.difficulties[_diff_sel]
	var pre := {"gen": _gens[_diff_sel]}
	if _full_audio != null and bm.audio_filename == _full_audio_file:
		pre["audio"] = _full_audio
	play_requested.emit(_loader, bm, settings, pre)


## 発進の演出。選んだ難易度のカードと曲名だけを残して、ほかをなめらかに退かせる。
func _launch_anim() -> void:
	if not UiStyle.animate:
		return
	var keep: Array = [_title_l, _artist_l, _meta_l, _diff_scroll, _bg_holder]
	_diff_scroll.clip_contents = false   # 選んだカードは少し拡大する。一覧の枠で、左右が切れないように
	for c in get_children():
		if c is Control and not c is ColorRect and not keep.has(c):   # (背景の暗幕・下地は、そのまま)
			var dx := -40.0 if c.position.x < 460.0 else 0.0   # 左の曲リストは左へ、右の部品はその場で薄れる
			var t := c.create_tween().set_parallel(true)
			t.tween_property(c, "modulate:a", 0.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			if dx != 0.0:
				t.tween_property(c, "position:x", c.position.x + dx, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	for i in range(_diff_cards.size()):
		var holder: Control = _diff_cards[i].get_parent()
		if i == _diff_sel:   # 選んだカードは、前に出る
			holder.pivot_offset = holder.size * 0.5
			UiStyle.spring(holder, "scale", Vector2.ONE, Vector2(1.035, 1.035), 0.3)
		else:
			var t2 := holder.create_tween().set_parallel(true)
			t2.tween_property(holder, "modulate:a", 0.0, 0.25)
			t2.tween_property(holder, "position:x", holder.position.x + 30.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	# PLAY ボタンから輪と粒が広がる
	if _play_btn != null:
		var at := _play_btn.get_global_rect().get_center()
		UiFx.ring(self, at, UiStyle.ACCENT, 20.0, 200.0, 0.5, 3.0)
		UiFx.burst(self, at, UiStyle.ACCENT, 14, 260.0, 0.55, 3.0)
	# 背景はズームイン(ずっと続けていた拡大縮小は止める)
	if _drift != null and _drift.is_valid():
		_drift.kill()
	var tz := _bg_holder.create_tween()
	tz.tween_property(_bg_holder, "scale", Vector2(1.16, 1.16), LAUNCH_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	# 曲は小さくなりながら消える
	var ta := _audio.create_tween()
	ta.tween_property(_audio, "volume_db", -40.0, LAUNCH_TIME)


func _input(event: InputEvent) -> void:
	if _options != null or _mod_panel != null or _launching or not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_UP, KEY_DOWN:   # 曲
			if not event.echo:   # 曲の切替は重い(難易度の再計算)ので、押しっぱなしでは進めない
				_select_song(_song_sel + (-1 if event.keycode == KEY_UP else 1))
			get_viewport().set_input_as_handled()
		KEY_LEFT, KEY_RIGHT:   # 難易度(左が易しい・右が難しい。端で止まる)
			_select_diff(_diff_sel + (-1 if event.keycode == KEY_LEFT else 1))
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			if not event.echo:
				_start()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if not event.echo:
				UiSfx.play("back")
				_audio.stop()
				back_requested.emit()
			get_viewport().set_input_as_handled()
		KEY_M:
			if not event.echo:
				open_mods()
			get_viewport().set_input_as_handled()
		KEY_O:
			if not event.echo:
				UiSfx.play("open")
				open_options(0)
			get_viewport().set_input_as_handled()


# --- 開発用(スクリーンショット) ---

## 曲が 1 つもない状態にする(右側の案内を確かめる)。
func debug_empty() -> void:
	while _job_pending:
		await get_tree().process_frame
	_clear_songs()
	_song_sel = -1
	_diff_sel = -1
	_loader = null
	_gens = []
	_ratings = []
	_rebuild_song_cards(false)
	_rebuild_diff_cards()
	_title_l.text = ""
	_artist_l.text = ""
	_meta_l.text = ""
	_detail_l.text = ""
	_set_loading(false)


## 曲の読み込み中の見た目にする。
func debug_loading() -> void:
	while _job_pending:
		await get_tree().process_frame
	_set_loading(true)
	_diff_scroll.modulate.a = 0.35
	_detail_l.text = "読み込み中…"


## MOD を指定して付けた状態にする。
func debug_set_mods(ids: Array) -> void:
	settings.mods = ids
	if _loader != null:
		var v2 := bool(Mods.params(ids).gen_v2)
		if v2 != _gens_v2:   # 開発用: その場で作り直す(順序は変えない)
			_gens = _loader.difficulties.map(func(bm): return _make_gen(bm, v2))
			_gens_v2 = v2
		_rate_all()
		_rebuild_diff_cards()
	_refresh_mod_bar()
