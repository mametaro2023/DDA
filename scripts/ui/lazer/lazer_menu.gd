extends "res://scripts/ui/lazer/lazer_screen.gd"
## lazer 風の選曲画面。左に曲の情報(長い曲名は流れる)と難易度の内訳、右に曲のカルーセル(背景が曲の画像の行。難易度は色の札だけで示し、
## 選んだ曲の下に、難易度の一覧が開く)。
## 下のフッターに、戻る・MOD・ランダム・設定・プレイ。曲を選ぶ中身は SongBrowser(classic の選曲画面と同じもの)。
## 契約は classic の選曲画面(menu_screen.gd)と同じ: signal play_requested / back_requested / song_picked / settings_requested、
## pick_mode / refresh_songs() / select_path() / on_overlay()。
## 操作: ↑↓ 曲、← → 難易度、Enter 開始、Esc 戻る、M で MOD、O で設定(キーの案内は画面に出さない。「遊び方」にある)。
## 曲の検索(右上の入力欄)と並び替え(曲名 / アーティスト / 追加順 / ランク / 難易度 / 長さ。行が滑って入れ替わる。難易度は、曲ではなく譜面ごとに 1 行ずつ並べる)ができ、左下に、選んだ難易度のローカル記録(上位 5 件)を出す(records.gd)。
## 曲の行の右には、その曲の最高ランクが出る。

## pre: 選曲のときに作っておいたもの {gen: 選んだ難易度の弾幕(MOD 適用前), audio: 曲全体の音声(あれば)}。プレイ画面が、作り直さず(読み込み直さず)に使う
signal play_requested(loader, bm, settings: Dictionary, pre: Dictionary)
signal back_requested
## マルチプレイの部屋の曲を選ぶモード(pick_mode = true): 「決定」で、開始せずに選んだ内容を返す(level は MOD 適用後の Lv)
signal song_picked(loader, bm, settings: Dictionary, level: float)

const SongBrowser = preload("res://scripts/song_browser.gd")
const ModPanel = preload("res://scripts/ui/lazer/lazer_mods.gd")
const SmoothScroll = preload("res://scripts/ui/smooth_scroll.gd")
const SongLibrary = preload("res://scripts/song_library.gd")
const OszImport = preload("res://scripts/osz_import.gd")
const Settings = preload("res://scripts/settings.gd")
const Mods = preload("res://scripts/mods.gd")
const Records = preload("res://scripts/records.gd")
const Volume = preload("res://scripts/volume.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const UiFx = preload("res://scripts/ui/ui_fx.gd")
const LazerMarquee = preload("res://scripts/ui/lazer/lazer_marquee.gd")
const SongArt = preload("res://scripts/song_art.gd")

const BAR_MAX := 500.0        # 弾数バーの満点
const SPEED_MAX := 500.0      # 弾速バーの満点(px/s)
const LAUNCH_TIME := 0.4      # プレイを押してから、次の画面へ切り替えるまでの演出の長さ(秒)
const ROW_H := 70.0           # 曲の行の高さ(1 画面に 7 行ほど入る。行の間は ROW_GAP)
const ROW_GAP := 6            # 行と行の間
const DIFF_H := 46.0          # 難易度の一覧の 1 行の高さ
const DIFF_GAP := 6
const DIFF_INDENT := 36.0     # 難易度の一覧の左の余白(曲の行より内側)
const INDENT := 44.0          # 行の左の余白(閉じているとき)
const INDENT_HOVER := 30.0
const INDENT_SEL := 6.0       # 選んでいる行は、左へせり出す
const MARGIN_R := 26.0        # 行の右の余白
const CHART_FILL_MAX := 160   # 難易度順で、中身を持っておく行の数(超えたら、古いものから手放す)
const CHART_FILL_PER_FRAME := 6   # 難易度順で、1 フレームに中身を作る行の数
const CHART_REBUILD_MS := 800     # 難易度を集めている間、並びを作り直す間隔(ミリ秒)

var kind := "menu"
var pick_mode := false

## 選曲の中身(曲の一覧・選択・別スレッドの読み込み・難易度の測定)。この画面は、その signal を見て表示するだけ(scripts/song_browser.gd)
var browser := SongBrowser.new()
## 以下は browser の状態への窓口(classic の選曲画面と同じ名前。確認用のコードも、この名前で読み書きする)
var _songs: Array:
	get: return browser.songs
	set(v): browser.songs = v
var _loader:
	get: return browser.loader
	set(v): browser.loader = v
var _gens: Array:
	get: return browser.gens
	set(v): browser.gens = v
var _ratings: Array:
	get: return browser.ratings
	set(v): browser.ratings = v
var _song_sel: int:
	get: return browser.song_sel
	set(v): browser.song_sel = v
var _diff_sel: int:
	get: return browser.diff_sel
	set(v): browser.diff_sel = v
var _job_pending: bool:
	get: return browser.job_pending
	set(v): browser.job_pending = v

var _rows: Array = []            # 曲ごとの行の入れもの(高さが変わる)
var _song_cards: Array = []           # 曲ごとのカード(押せる。中で左右にずれる)
var _diff_cards: Array = []      # 選んでいる曲の難易度の行(読み込み済みのときだけ。押せる)
var _diff_box: Control           # 選んでいる曲の下に開いた、難易度の一覧の入れもの(高さが伸び縮みする)
var _diff_inner: VBoxContainer
var _diff_rows: Array = []       # 一覧の行(読み込み中の仮の行も含む)
var _anchor_y := -1.0            # 選んでいる曲の行の、一覧の中での位置(並びが変わったら、その分スクロールをずらして、画面の同じ場所に保つ)
var _flip_before := {}           # 並び替えの直前の、行の位置
var _flip_pending := false
var _flip_s0 := 0.0              # 並び替えの直前の、スクロールの位置(どの行が見えていたかを決める)
var _was_chart := false          # いまの一覧が、難易度順(譜面ごと)か
var _chart_holders := {}         # 譜面の key(曲の識別子|譜面の識別子)→ 行の入れもの(難易度順のときだけ。中身は、近づいたときに作る)
var _chart_order: Array = []     # いま並んでいる譜面 [{s, id, name, lv, key}]
var _chart_list: Array = []      # 同じ並びの、行の入れもの(位置から、見えている範囲を探す)
var _chart_keys := PackedStringArray()   # 同じ並びの key(並びが変わったかの確認用)
var _chart_filled: Array = []    # 中身を作った行の key(古い順。CHART_FILL_MAX を超えたら古いものから手放す)
var _chart_by_song := {}         # 曲の識別子 → その曲の譜面の行
var _chart_sel := ""             # 選んでいる譜面の key
var _chart_want := ""            # 押した譜面の識別子(別の曲だったとき、読み込み終わりにこの難易度を選ぶ)
var _chart_center_pending := false   # 選んでいる曲を読み込み終わったら、その譜面を一覧の真ん中へ
var _meta_asked := {}            # 難易度を集めるよう頼んだ曲(曲の識別子)
var _len_asked := {}             # 長さを集めるよう頼んだ曲
var _charts_dirty := false       # 集めた難易度が増えた(並びを作り直す)
var _charts_at := 0              # 難易度順の並びを最後に作った時刻
## 一覧の上端・下端の余白(伸び縮みする)。スクロールでは打ち消せない高さの変化(上端・下端にいるとき)を、いったんここで受け止めて、
## あとから、止まった状態から加速するばねで、なめらかに戻す(閉じる一覧が大きくても、行がガクッと動かない)
var _head: Control
var _tail: Control
var _head_extra := 0.0
var _head_vel := 0.0
var _tail_extra := 0.0
var _tail_vel := 0.0
var _h_prev := -1.0
var _collapse_until := 0       # 一覧が閉じ終わる時刻(ミリ秒)。それまでは、余白を戻さない
const HEAD_BASE := 10.0
const SPACER_W := 9.0          # 余白を戻すばねの強さ(約 0.5 秒)
var _detail_tween: Tween          # 読み込み中に、左の情報を少し薄くする
var _stat_from: Array = []       # 内訳のバーの、動き始めの割合
var _stat_k := 1.0               # 内訳のバーの動きの進み(0 → 1)
var _art_asked := {}             # 画像を SongArt に頼んだ行
var _key_to_row := {}            # 曲の識別子 → 行の番号
var _art_t := 0.0
var _view_at := 0                # 最後に並びを行へ反映した時刻(osu! の曲を足している間に、ときどき反映する)
var _progress_at := 0
var _v2_btn: Button              # フッターの「弾幕 v2 で遊ぼう」(v2 を付けていないときだけ出る)
## 一度読み込んで測った Lv(MOD なし)。譜面の識別子 → Lv。行の色の札に使う(この起動の間だけ覚える)
static var _lv_seen := {}
static var _shade: Texture2D
var _scroll: ScrollContainer
var _box: VBoxContainer
var _smooth: Node
var _info: Control               # 左上の情報パネル(斜めの縁)
var _title_l: Control            # 曲名(長いときは流れる。LazerMarquee)
var _artist_l: Control
var _meta_l: Label
var _diff_l: Label
var _lv_holder: HBoxContainer    # 選んでいる難易度の Lv の札(+ MODなしの値)
var _mod_bar: HBoxContainer
var _status: Label
var _stats: Control              # 難易度の内訳(バー)
var _stat_rows: Array = []       # [[名前, 0..1, 値の文字]]
var _stat_note := ""
var _rec_card: Control            # 左下: 選んだ難易度のローカル記録
var _rec_rows: Array = []         # 記録の行(records.gd の 1 件ずつ)
var _search: LineEdit
var _sort_btns: Array = []
var _no_match: Label              # 検索に合う曲がないとき
var _empty_box: Control
var _play_btn: Button
var _audio: AudioStreamPlayer
var _dialog: FileDialog
var _options: Control            # 開いている設定パネル(main が持つ。開いている間だけ設定される)
var _mod_panel: Control          # 開いている MOD パネル
var _launching := false
var _intro_nodes: Array = []
var _cards_gen := 0


func _ready() -> void:
	settings = Settings.load_all()
	browser.settings = settings
	browser.song_changing.connect(_on_song_changing)
	browser.song_loaded.connect(_on_song_loaded)
	browser.song_load_failed.connect(_on_song_load_failed)
	browser.song_reloading.connect(func(): _set_loading(true))   # 弾幕 v2 の入り切りで、同じ曲を読み直している
	browser.sort_mode = str(settings.get("song_sort", "title"))
	browser.charts_of = _charts_of
	browser.length_of = func(i: int) -> float: return SongArt.length_of(str(_songs[i].md5))
	_build_base()
	_build_toolbar(["ロビー", "曲を選ぶ"] if pick_mode else ["ソロ"])
	_build_info()
	_build_stats()
	_build_records()
	_build_search()
	_build_carousel()
	_build_empty()
	_build_footer()
	_build_footer_buttons()
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
	_scan()
	_rebuild_song_cards()
	if not _songs.is_empty():
		var first := browser.last_song_index()
		_select_song(first)
		browser.auto_sel_idx = first
		_center_selected()


func _exit_tree() -> void:
	browser.close()   # 画面を離れたあとに届く、曲の読み込みの結果は捨てる


# --- 部品 ---

## 左上の情報パネル(右の縁が斜め): 曲名・アーティスト・譜面の情報・選んでいる難易度・付けた MOD。
func _build_info() -> void:
	_info = Control.new()
	_place(_info, 0, 56, 604, 232)
	_info.draw.connect(func():
		_info.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(604, 0), Vector2(574, 232), Vector2(0, 232)]), Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.9)))
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_l = LazerMarquee.new(32, LazerStyle.TEXT, true)   # 長い曲名は、流れて後ろまで読める
	_title_l.position = Vector2(32, 16)
	_title_l.size = Vector2(520, 46)
	_info.add_child(_title_l)
	_artist_l = LazerMarquee.new(19, LazerStyle.TEXT_DIM)
	_artist_l.position = Vector2(32, 62)
	_artist_l.size = Vector2(520, 28)
	_info.add_child(_artist_l)
	_meta_l = LazerStyle.label("", 14, LazerStyle.TEXT_MUTE)
	_meta_l.position = Vector2(32, 94)
	_meta_l.size = Vector2(520, 22)
	_info.add_child(_meta_l)
	_lv_holder = HBoxContainer.new()
	_lv_holder.add_theme_constant_override("separation", 10)
	_lv_holder.position = Vector2(32, 128)
	_lv_holder.size = Vector2(520, 30)
	_lv_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(_lv_holder)
	_mod_bar = HBoxContainer.new()
	_mod_bar.add_theme_constant_override("separation", 8)
	_mod_bar.clip_contents = true
	_mod_bar.position = Vector2(32, 176)
	_mod_bar.size = Vector2(520, 28)
	_mod_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(_mod_bar)
	_status = LazerStyle.label("", 13, LazerStyle.RED)   # 読み込みに失敗したときのメッセージ用
	_status.position = Vector2(32, 208)
	_status.size = Vector2(520, 20)
	_info.add_child(_status)
	_intro_nodes.append(_info)


## 難易度の内訳(平均弾数・最大弾数・弾速のバーと、一行の詳細)。
func _build_stats() -> void:
	_stats = Control.new()
	_place(_stats, 24, 304, 540, 156)
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.draw.connect(_draw_stats)
	_intro_nodes.append(_stats)


func _draw_stats() -> void:
	var w := _stats.size.x
	var h := _stats.size.y
	_stats.draw_style_box(LazerStyle.box(Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.78), Color(0, 0, 0, 0), 0, 12), Rect2(0, 0, w, h))
	var f := LazerStyle.font()
	var y := 20.0
	for q in range(_stat_rows.size()):
		var r: Array = _stat_rows[q]
		_stats.draw_string(f, Vector2(20, y + 13), str(r[0]), HORIZONTAL_ALIGNMENT_LEFT, 120, 14, LazerStyle.TEXT_DIM)
		var x0 := 130.0
		var bw := w - x0 - 100.0
		_stats.draw_rect(Rect2(x0, y + 6, bw, 6), Color(1, 1, 1, 0.12))
		var frac: float = clampf(_stat_from_old(q), 0.0, 1.0)   # 前の難易度の値から、なめらかに伸び縮みする
		_stats.draw_rect(Rect2(x0, y + 6, bw * frac, 6), LazerStyle.PINK)
		_stats.draw_string(f, Vector2(x0 + bw + 14, y + 13), str(r[2]), HORIZONTAL_ALIGNMENT_LEFT, 80, 14, LazerStyle.TEXT)
		y += 32.0
	if _stat_note != "":
		_stats.draw_string(f, Vector2(20, h - 14), _stat_note, HORIZONTAL_ALIGNMENT_LEFT, w - 40, 13, LazerStyle.TEXT_MUTE)


## 左下: 選んだ難易度のローカル記録(上位 5 件。ランク・スコア・付けた MOD・日付)。
func _build_records() -> void:
	_rec_card = Control.new()
	_place(_rec_card, 24, 476, 540, 180)
	_rec_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rec_card.draw.connect(_draw_records)
	_intro_nodes.append(_rec_card)


func _draw_records() -> void:
	var w := _rec_card.size.x
	var h := _rec_card.size.y
	_rec_card.draw_style_box(LazerStyle.box(Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.78), Color(0, 0, 0, 0), 0, 12), Rect2(0, 0, w, h))
	var f := LazerStyle.font()
	var fb := LazerStyle.font_bold()
	_rec_card.draw_string(f, Vector2(20, 24), "ローカル記録", HORIZONTAL_ALIGNMENT_LEFT, 200, 13, LazerStyle.TEXT_MUTE)
	if _rec_rows.is_empty():
		_rec_card.draw_string(f, Vector2(20, 66), "まだ記録がありません", HORIZONTAL_ALIGNMENT_LEFT, w - 40, 15, LazerStyle.TEXT_MUTE)
		return
	var y := 34.0
	for i in range(_rec_rows.size()):
		var r: Dictionary = _rec_rows[i]
		if i % 2 == 0:
			_rec_card.draw_style_box(LazerStyle.box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 6), Rect2(10, y, w - 20, 26))
		var rc: Color = UiStyle.rank_color(str(r.rank))
		_rec_card.draw_string(fb, Vector2(20, y + 19), str(r.rank), HORIZONTAL_ALIGNMENT_LEFT, 40, 17, rc)
		_rec_card.draw_string(fb, Vector2(62, y + 19), UiStyle.fmt(int(r.score)), HORIZONTAL_ALIGNMENT_LEFT, 150, 17, LazerStyle.TEXT)
		var mods: Array = []
		for id in r.get("mods", []):
			var m := Mods.find(id)
			if not m.is_empty():
				mods.append(str(m.tag))
		_rec_card.draw_string(f, Vector2(204, y + 18), " ".join(mods), HORIZONTAL_ALIGNMENT_LEFT, 190, 13, LazerStyle.PURPLE)
		var d := Time.get_datetime_dict_from_unix_time(int(r.get("t", 0)))
		_rec_card.draw_string(f, Vector2(w - 110, y + 18), "%d/%02d/%02d" % [d.year, d.month, d.day], HORIZONTAL_ALIGNMENT_RIGHT, 90, 13, LazerStyle.TEXT_MUTE)
		y += 28.0


## 選んでいる難易度の記録を読み直す。
func _update_records() -> void:
	_rec_rows = []
	if _loader != null and _diff_sel >= 0 and _diff_sel < _loader.difficulties.size():
		_rec_rows = Records.top(str(_loader.difficulties[_diff_sel].md5), 5)
	if _rec_card != null:
		_rec_card.queue_redraw()


## 右上: 曲の検索の入力欄と、並び替えの切り替え。
func _build_search() -> void:
	_search = LineEdit.new()
	_search.placeholder_text = "曲を検索…"
	_search.clear_button_enabled = true
	_search.max_length = 40
	_search.focus_mode = Control.FOCUS_CLICK
	_search.text_changed.connect(func(t: String):
		browser.query = t
		_apply_view())
	var group := ButtonGroup.new()
	var widths: Array = []
	var total := 0.0
	for m in SongBrowser.SORT_MODES:   # 並び替えのボタンは右に寄せ、残りの幅を入力欄にする
		var bw := LazerStyle.font().get_string_size(str(m[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 22.0
		widths.append(bw)
		total += bw + 6.0
	var x := 1280.0 - 20.0 - total + 6.0
	_place(_search, 624, 50, x - 624.0 - 12.0, 36)
	for m in SongBrowser.SORT_MODES:
		var b := Button.new()
		b.text = str(m[1])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.set_pressed_no_signal(browser.sort_mode == m[0])
		var mode_id: String = m[0]
		b.pressed.connect(func():
			if browser.sort_mode == mode_id:
				return
			browser.sort_mode = mode_id
			settings.song_sort = mode_id
			Settings.save_all(settings)
			_apply_view(true))
		var w: float = widths[_sort_btns.size()]
		_place(b, x, 50, w, 36)
		x += w + 6.0
		_sort_btns.append(b)


## 検索・並び替えを、行に反映する(行は曲ごとに作ってあり、見せるものと順番だけを変える)。難易度の一覧は、選んだ曲のすぐ下へ。
## sorted = true(並び替えを変えた): 行が、前の位置から新しい位置へ、少しずつ遅れて滑って入れ替わる。
func _apply_view(sorted := false, keep_scroll := false) -> void:
	if _rows.is_empty():
		return
	if browser.chart_mode():   # 難易度順: 曲ではなく、譜面を 1 つずつ並べる(滑る動きはなし)
		_apply_chart_view()
		return
	var leaving := _was_chart
	if leaving:   # 難易度順から戻った: 譜面の行は捨てて、曲の行を出す
		_was_chart = false
		_clear_charts()
		_anchor_y = -1.0
		_no_match.text = "一致する曲がありません"
	var before := {}
	if sorted and UiStyle.animate and not leaving:
		_flip_s0 = float(_scroll.scroll_vertical)
		for c in _box.get_children():
			if c is Control and c.visible:   # 動かすのは、いま見えている行だけ(画面の外の行は、そのまま入れ替える)
				var y: float = (c as Control).position.y
				if y + (c as Control).size.y > _flip_s0 and y < _flip_s0 + _scroll.size.y:
					before[c] = y
	if browser.sort_mode == "length":   # 長さが分かっていない曲を、裏で集める
		_crawl_meta()
	var v := browser.view()
	var shown := {}
	var at := 1   # 0 番目は、一番上の余白
	for k in range(v.size()):
		shown[v[k]] = true
		_box.move_child(_rows[v[k]], at)
		at += 1
		if v[k] == _song_sel and _diff_box != null:
			_box.move_child(_diff_box, at)
			at += 1
	if _tail != null and is_instance_valid(_tail):
		_box.move_child(_tail, -1)
	for i in range(_rows.size()):
		_rows[i].visible = shown.has(i)
	if _diff_box != null:
		_diff_box.visible = shown.has(_song_sel)
	_no_match.visible = v.is_empty() and not _songs.is_empty()
	_art_t = 1.0   # 見えるようになった行の画像を頼む
	if leaving:
		_fade_list()
	if not before.is_empty():   # 動きは、並びが決まった直後(_on_box_sorted)に始める
		_flip_before = before
		_flip_pending = true
		_box.queue_sort()
	elif not keep_scroll and _song_sel >= 0 and _song_sel < _rows.size() and _rows[_song_sel].visible:
		_smooth.scroll_to_control(_rows[_song_sel], 80.0)


# --- 難易度順(譜面ごとの一覧) ---
## 並び替えが「難易度」のときは、曲の行も難易度の一覧も出さず、譜面(曲 × 難易度)を 1 行ずつ、Lv の低い順に並べる。
## 行の中身(画像・文字・Lv の札)は、画面に近づいたときだけ作る(何千譜面あっても重くしない)。並びは、行を足し直すだけで、滑る動きはない。
## 並べる Lv は MOD なしの値(推定の★、曲を読み込んだあとは測った Lv)。MOD を変えても並びは変わらない。
## まだ難易度が分かっていない曲は、裏で 1 曲ずつ集めて(SongArt.request_meta)、分かった曲から並びに加わる。
## 押すと、その曲を読み込んでその難易度を選び、選んでいる譜面をもう一度押すと開始。↑↓ は 1 譜面ずつ、← → は同じ曲の隣の難易度。

## 難易度順の並びに使う、曲 i の譜面 [[譜面の識別子, 難易度名, Lv], ...](browser.charts_of)。
func _charts_of(i: int) -> Array:
	var out: Array = []
	for d in SongArt.diffs_of(str(_songs[i].md5)):
		out.append([str(d[0]), str(d[1]), float(_lv_seen.get(str(d[0]), d[2]))])
	return out


## 難易度順の一覧を、行に反映する(並びが変わったときだけ、行を足し直す)。
func _apply_chart_view() -> void:
	var entering := not _was_chart
	_was_chart = true
	_charts_at = Time.get_ticks_msec()
	_charts_dirty = false
	for r in _rows:   # 曲の行と、その難易度の一覧は隠す
		if r.visible:
			r.visible = false
	if _diff_box != null:
		_diff_box.visible = false
	_crawl_meta()
	var order: Array = browser.chart_view()
	var keys := PackedStringArray()
	var keep := {}
	for c in order:
		var key := "%s|%s" % [_songs[c.s].md5, c.id]
		c["key"] = key
		keys.append(key)
		keep[key] = true
		if _chart_holders.has(key):
			_set_chart_lv(_chart_holders[key], c)   # 測った Lv に変わっていたら、数字・色だけ差し替える(並びは、ここで決め直す)
		else:
			_chart_holders[key] = _make_chart_holder(c)
	_chart_order = order
	var pending := SongArt.meta_pending() > 0
	_no_match.text = "難易度を調べています…" if pending else "一致する曲がありません"
	_no_match.visible = order.is_empty() and not _songs.is_empty()
	if keys != _chart_keys or entering:   # 並びが同じなら、行には触らない
		_chart_keys = keys
		for key in _chart_holders.keys():
			if not keep.has(key):
				var gone: Control = _chart_holders[key]
				_chart_holders.erase(key)
				_chart_filled.erase(key)
				gone.visible = false
				gone.queue_free()
		var kids := _box.get_children()   # いったん外して、順に足し直す(move_child を何千回も呼ばない)
		for k in range(kids.size() - 1, -1, -1):
			if kids[k].has_meta("chart"):
				_box.remove_child(kids[k])
		_chart_list = []
		for c in order:
			var h: Control = _chart_holders[c.key]
			h.visible = true
			_box.add_child(h)
			_chart_list.append(h)
		if _tail != null and is_instance_valid(_tail):
			_box.move_child(_tail, -1)
	_sync_chart_sel(false)
	if entering:
		_anchor_y = -1.0   # 行の位置がまだ決まっていない
		_fade_list()
		if _chart_sel != "":
			_center_chart_later()
		else:
			_chart_center_pending = true   # 選んでいる曲を読み込み終わったら、その譜面を真ん中へ


## 難易度順をやめた(・一覧を作り直す): 譜面の行を捨てる。
func _clear_charts() -> void:
	for h in _chart_holders.values():
		if is_instance_valid(h):
			(h as Control).visible = false
			(h as Control).queue_free()
	_chart_holders.clear()
	_chart_order = []
	_chart_list = []
	_chart_filled = []
	_chart_by_song.clear()
	_chart_keys = PackedStringArray()
	_chart_sel = ""
	_chart_want = ""


## 一覧を、ふわっと現れさせる(並び方の種類が変わったとき)。行を滑らせないので、数が多くても目に優しい。
func _fade_list() -> void:
	if not UiStyle.animate or not is_inside_tree():
		return
	UiStyle.tween(_box, "modulate:a", 0.25, 1.0, 0.3)


## 譜面 c の行の入れもの(中身は、近づいたときに _fill_chart が作る)。
func _make_chart_holder(c: Dictionary) -> Control:
	var key: String = c.key
	var s: int = c.s
	var id: String = c.id
	var card := UiStyle.card(ROW_H, func(): _pick_chart(s, id), func(): _start())
	card.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	card.mouse_entered.connect(func():
		card.set_meta("hover", true)
		if key != _chart_sel:
			UiSfx.play("hover", 1.0)
		_style_chart(key, true))
	card.mouse_exited.connect(func():
		card.set_meta("hover", false)
		_style_chart(key, true))
	var holder := UiStyle.wrap_card(card, ROW_H)
	card.offset_right = -MARGIN_R
	holder.set_meta("chart", key)
	holder.set_meta("card", card)
	holder.set_meta("info", c)
	var base := LazerStyle.title_color(str(_songs[s].title))
	card.add_theme_stylebox_override("panel", LazerStyle.box(Color(base.r * 0.22, base.g * 0.22, base.b * 0.26), Color(0, 0, 0, 0), 0, 12, 0, 0))
	_shift_card(card, INDENT, false)
	var md5 := str(_songs[s].md5)
	if not _chart_by_song.has(md5):
		_chart_by_song[md5] = []
	(_chart_by_song[md5] as Array).append(holder)
	return holder


## 行の中身を作る: 背景の画像・暗くする帯・曲名・アーティスト・Lv の札と難易度名・その譜面の最高ランク・縁。
func _fill_chart(h: Control) -> void:
	if bool(h.get_meta("filled", false)):
		return
	h.set_meta("filled", true)
	var card: PanelContainer = h.get_meta("card")
	var c: Dictionary = h.get_meta("info")
	var md5 := str(_songs[c.s].md5)
	var bg := TextureRect.new()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.texture = SongArt.texture_of(md5)
	card.add_child(bg)
	var shade := TextureRect.new()
	shade.texture = _shade_tex()
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(shade)
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in [["left", 20], ["right", 16], ["top", 4], ["bottom", 4]]:
		m.add_theme_constant_override("margin_" + side[0], side[1])
	card.add_child(m)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(hb)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(v)
	var t := LazerStyle.label(_songs[c.s].title, 17, LazerStyle.TEXT, true)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	t.add_theme_constant_override("shadow_offset_y", 1)
	v.add_child(t)
	var a := LazerStyle.label(_songs[c.s].artist, 13, LazerStyle.TEXT_DIM)
	a.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(a)
	var line := HBoxContainer.new()   # Lv の札と難易度名
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pb := HBoxContainer.new()
	pb.add_theme_constant_override("separation", 3)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(pb)
	var star := LazerIcons.new("star", Color.WHITE, 10.0)
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.add_child(star)
	var lv_l := LazerStyle.label("", 11, Color.WHITE, true)
	pb.add_child(lv_l)
	line.add_child(pill)
	var name_l := LazerStyle.label(str(c.name), 13, LazerStyle.TEXT)
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_l)
	v.add_child(line)
	var rank := str(Records.best(str(c.id)).get("rank", ""))   # その譜面の最高ランク
	if rank != "":
		var badge := CenterContainer.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(LazerStyle.pill(rank, UiStyle.rank_color(rank), 15))
		hb.add_child(badge)
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(frame)
	card.set_meta("bg", bg)
	card.set_meta("shade", shade)
	card.set_meta("frame", frame)
	card.set_meta("pill", pill)
	card.set_meta("star", star)
	card.set_meta("lv_l", lv_l)
	_set_chart_lv(h, c)
	_style_chart(str(c.key), false)
	_chart_filled.append(str(c.key))
	while _chart_filled.size() > CHART_FILL_MAX:   # 遠くへ行った行の中身は、手放す(また近づいたら作る)
		_evict_chart(str(_chart_filled.pop_front()))
	if bg.texture == null:   # 画像は、見えている行のぶんだけ、先に頼む
		SongArt.request(get_tree(), md5, str(_songs[c.s].path), _on_art.bind(md5), true)


## 行の中身を手放す(入れものは残す)。
func _evict_chart(key: String) -> void:
	var h = _chart_holders.get(key)
	if h == null or not is_instance_valid(h):
		return
	var card: PanelContainer = (h as Control).get_meta("card")
	for ch in card.get_children():
		card.remove_child(ch)
		ch.queue_free()
	for mk in ["bg", "shade", "frame", "pill", "star", "lv_l"]:
		card.remove_meta(mk)
	(h as Control).set_meta("filled", false)


## 行の Lv の札(色と数字)を入れる・差し替える。中身がまだなら、値だけ覚えておく。
func _set_chart_lv(h: Control, c: Dictionary) -> void:
	h.set_meta("info", c)
	if not bool(h.get_meta("filled", false)):
		return
	var card: PanelContainer = h.get_meta("card")
	var lv := float(c.lv)
	var col := LazerStyle.level_color(lv)
	var ink := LazerStyle.ink_on(col)
	(card.get_meta("pill") as PanelContainer).add_theme_stylebox_override("panel", LazerStyle.box(col, Color(0, 0, 0, 0), 0, 10, 7, 1))
	var star: Control = card.get_meta("star")
	star.set("col", ink)
	star.queue_redraw()
	var lv_l: Label = card.get_meta("lv_l")
	lv_l.text = "%.2f" % lv
	lv_l.add_theme_color_override("font_color", ink)


## 曲を読み込んで測った Lv が分かった: その曲の譜面の行の数字・色を差し替える(並びは、次に一覧を作り直すときに決め直す)。
func _refresh_chart_lv(md5: String) -> void:
	for h in _chart_by_song.get(md5, []):
		if not is_instance_valid(h):
			continue
		var c: Dictionary = h.get_meta("info")
		c["lv"] = snappedf(float(_lv_seen.get(str(c.id), c.lv)), 0.01)
		_set_chart_lv(h, c)


## 譜面の行の見た目(選んでいる行は縁がピンクで明るく、左へせり出す)。
func _style_chart(key: String, animated := true) -> void:
	var h = _chart_holders.get(key)
	if h == null or not is_instance_valid(h):
		return
	_style_row_card((h as Control).get_meta("card"), key == _chart_sel, animated)


## 難易度順で、いま選んでいる譜面の key(曲 + 難易度。読み込み中は、押した譜面。なければ空)。
func _current_chart_key() -> String:
	if _song_sel < 0 or _song_sel >= _songs.size():
		return ""
	var id := ""
	if _diffs_ready() and _diff_sel >= 0 and _diff_sel < _loader.difficulties.size():
		id = str(_loader.difficulties[_diff_sel].md5)
	elif _chart_want != "":
		id = _chart_want
	else:
		return ""
	return "%s|%s" % [_songs[_song_sel].md5, id]


## 選んでいる譜面の行を、選んだ見た目にする(前の行は戻す)。選んだ行の位置を保つ基準も、ここで取り直す。
func _sync_chart_sel(animated := true) -> void:
	if not _was_chart:
		return
	var key := _current_chart_key()
	if key != _chart_sel:
		var old := _chart_sel
		_chart_sel = key
		_style_chart(old, animated)
		_style_chart(key, animated)
	var h = _chart_holders.get(_chart_sel) if _chart_sel != "" else null
	_anchor_y = (h as Control).position.y if h != null and is_instance_valid(h) else -1.0


## 譜面の行を押した: その曲を読み込んで、その難易度を選ぶ。同じ曲を読み込み済みなら、難易度だけ切り替える。
## 選んでいる譜面をもう一度押したら開始(repeat_starts = false なら開始しない)。
func _pick_chart(s: int, id: String, repeat_starts := true) -> void:
	if s == _song_sel and _diffs_ready():
		var k := _diff_index_of(id)
		if k < 0:
			return
		if k == _diff_sel:
			if repeat_starts and browser.can_start():
				_start()
			return
		_chart_want = ""
		_select_diff(k)
		return
	_select_song(s)   # 曲が変わるときは、押した難易度を覚えておき、読み込み終わりに選ぶ(_on_song_loaded)
	_chart_want = id
	_sync_chart_sel()


## 読み込んでいる曲の難易度のうち、識別子が id の番号(なければ -1)。
func _diff_index_of(id: String) -> int:
	if _loader == null:
		return -1
	for k in range(_loader.difficulties.size()):
		if str(_loader.difficulties[k].md5) == id:
			return k
	return -1


func _chart_index(key: String) -> int:
	for k in range(_chart_order.size()):
		if str(_chart_order[k].key) == key:
			return k
	return -1


## ↑↓: 並んでいる譜面を、dir(-1 / 1)だけ進む。選んでいる譜面が一覧にないときは、先頭(末尾)へ。
func _step_chart(dir: int) -> void:
	if _chart_order.is_empty():
		return
	var cur := _chart_index(_chart_sel)
	var to := (0 if dir >= 0 else _chart_order.size() - 1) if cur < 0 else clampi(cur + dir, 0, _chart_order.size() - 1)
	if to == cur:
		return
	var c: Dictionary = _chart_order[to]
	_pick_chart(int(c.s), str(c.id), false)
	_scroll_to_chart(str(c.key))


func _scroll_to_chart(key: String) -> void:
	var h = _chart_holders.get(key)
	if h != null and is_instance_valid(h):
		_smooth.scroll_to_control(h, 80.0)


## 選んでいる譜面の行を、一覧の真ん中に出す(行の位置は、レイアウトが終わるまで決まらないので、2 フレーム待つ)。
func _center_chart_later() -> void:
	var want := _chart_sel
	if want == "" or not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or want != _chart_sel:
		return
	var h = _chart_holders.get(want)
	if h != null and is_instance_valid(h):
		_smooth.center_on_control(h, true)


## 難易度がまだ分かっていない曲を、裏で 1 曲ずつ集める(分かった曲から、並びに加わる)。1 度頼んだ曲は、頼み直さない。
func _crawl_meta() -> void:
	if not is_inside_tree():
		return
	var need_len := browser.sort_mode == "length"   # 長さ順: 長さが分かっていない曲(前の版で保存した分も)を集める
	for i in range(_songs.size()):
		var key := str(_songs[i].md5)
		if need_len:
			if _len_asked.has(key) or SongArt.has_length(key):
				continue
			_len_asked[key] = true
		else:
			if _meta_asked.has(key) or not SongArt.diffs_of(key).is_empty():
				continue
			_meta_asked[key] = true
		SongArt.request_meta(get_tree(), key, str(_songs[i].path), func(_info: Dictionary):
			_charts_dirty = true
			_redraw_dots_of(key), need_len)


## 曲 key の行の、難易度の札と長さの表示を描き直す(長さが分かったとき)。
func _redraw_dots_of(key: String) -> void:
	var i := int(_key_to_row.get(key, -1))
	if i >= 0 and i < _song_cards.size() and _song_cards[i].has_meta("dots"):
		(_song_cards[i].get_meta("dots") as Control).queue_redraw()


## 近くの譜面の行の中身を作る(1 フレームに CHART_FILL_PER_FRAME 行まで)。行の高さは同じなので、位置から見えている範囲を二分探索で探す。
func _fill_visible_charts() -> void:
	if _chart_list.is_empty():
		return
	var top := float(_scroll.scroll_vertical) - ROW_H * 2.0
	var bot := float(_scroll.scroll_vertical) + _scroll.size.y + ROW_H * 2.0
	var lo := 0
	var hi := _chart_list.size()
	while lo < hi:   # 下端が top より下にある最初の行
		var mid := (lo + hi) >> 1
		var hm: Control = _chart_list[mid]
		if hm.position.y + hm.size.y < top:
			lo = mid + 1
		else:
			hi = mid
	var made := 0
	var k := lo
	while k < _chart_list.size() and made < CHART_FILL_PER_FRAME:
		var h: Control = _chart_list[k]
		if h.position.y > bot:
			break
		if not bool(h.get_meta("filled", false)):
			_fill_chart(h)
			made += 1
		k += 1


## 右の曲カルーセル。
func _build_carousel() -> void:
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_place(_scroll, 600, 96, 680, 560)
	_scroll.add_to_group("wheel_area")   # 一覧の上のホイールは、音量ではなくスクロールに使う(曲が少なくてスクロールしないときも)
	_smooth = SmoothScroll.attach(_scroll, true)   # ドラッグでもスクロールできる(左 = ふつう・右 = 速い)
	_smooth.active = _lists_active
	_no_match = LazerStyle.label("一致する曲がありません", 18, LazerStyle.TEXT_MUTE)
	_no_match.visible = false
	_place(_no_match, 640, 140, 600, 30)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", ROW_GAP)
	_box.sort_children.connect(_on_box_sorted)   # 並びが変わった直後(描く前)に、選んだ行の位置を保つ・並び替えの動きを始める
	_scroll.add_child(_box)


## 曲が 1 つもないとき、中央に出す案内(曲の入れ方へ誘導するボタン付き)。曲が入ると隠れる。
func _build_empty() -> void:
	_empty_box = VBoxContainer.new()
	_empty_box.add_theme_constant_override("separation", 14)
	_empty_box.visible = false
	var v: VBoxContainer = _empty_box
	v.add_child(LazerStyle.label("曲がありません", 30, LazerStyle.TEXT, true))
	v.add_child(LazerStyle.label("osu! の譜面(.osz)を追加してください", 17, LazerStyle.TEXT_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var add := LazerButton.new(".osz を開く", LazerStyle.PINK, "plus")
	add.custom_minimum_size = Vector2(190, 46)
	add.font_size = 16
	add.pressed.connect(func(): _dialog.popup_centered_ratio(0.7))
	row.add_child(add)
	var folder := LazerButton.new("曲フォルダを開く", LazerStyle.PANEL, "folder", LazerStyle.TEXT)
	folder.custom_minimum_size = Vector2(210, 46)
	folder.font_size = 16
	folder.pressed.connect(func(): OS.shell_open(SongLibrary.ensure_user_dir()))
	row.add_child(folder)
	v.add_child(row)
	_place(_empty_box, 660, 220, 580, 200)


func _build_footer_buttons() -> void:
	var back := _footer_button("ロビー" if pick_mode else "戻る", LazerStyle.PINK, "back", 0, 168, func(): _go_back())
	back.set_meta("juice_sound", "back")
	_footer_button("MOD", LazerStyle.PURPLE, "dots", 162, 150, open_mods, Color(0.1, 0.04, 0.2))
	_footer_button("ランダム", LazerStyle.BLUE, "shuffle", 306, 170, _random_song, Color(0.03, 0.12, 0.2))
	_footer_button("設定", Color(0.24, 0.22, 0.31), "gear", 470, 150, func(): open_options(0), LazerStyle.TEXT)
	var v2c: Color = Mods.find("v2").color
	_v2_btn = _footer_button("弾幕 v2 で遊ぼう", v2c, "plus", 760, 250, _enable_v2, v2c.darkened(0.75))
	_v2_btn.tooltip_text = "MOD「弾幕 v2」を付ける: 譜面ごとに特徴の出る弾幕と、特殊エリア。いつでも MOD から外せます"
	var play := _footer_button("決定" if pick_mode else "プレイ", LazerStyle.YELLOW, "play", 1280 - 260, 260, _start, Color(0.2, 0.13, 0.0))
	play.disabled = true   # 曲を読み込み終わるまで押せない(_set_loading が切り替える)
	play.font_size = 20
	_play_btn = play


func _go_back() -> void:
	UiSfx.play("back")
	_audio.stop()
	back_requested.emit()


## 画面を開いたときの入場: 情報・内訳が左から、カルーセルが右から滑り込む。
func _intro() -> void:
	var k := 0
	for c in _intro_nodes:
		UiStyle.pop_in(c, 0.05 + k * 0.06, Vector2(-30, 0), 0.5)
		k += 1


## 曲の読み込み中の見た目: プレイを押せなくし、左の情報(BPM・Lv・内訳・記録)を、消さずに少し薄くする。
func _set_loading(on: bool) -> void:
	_dim_detail(on)
	if _play_btn != null:
		_play_btn.disabled = on or _loader == null
		_play_btn.queue_redraw()
	if _v2_btn != null:
		_v2_btn.disabled = on or _loader == null
		_v2_btn.queue_redraw()


## 左の情報を薄くする・戻す。薄くするのは 0.15 秒たってもまだ読み込み中のときだけ(すぐ終わる読み込みでは、何も変わらない)。
func _dim_detail(on: bool) -> void:
	if _detail_tween != null and _detail_tween.is_valid():
		_detail_tween.kill()
	var nodes: Array = [_meta_l, _lv_holder, _stats, _rec_card]
	if not UiStyle.animate or not is_inside_tree():
		for n in nodes:
			n.modulate.a = 0.45 if on else 1.0
		return
	_detail_tween = create_tween().set_parallel(true)
	for n in nodes:
		if on:
			_detail_tween.tween_property(n, "modulate:a", 0.45, 0.25).set_delay(0.15)
		else:
			_detail_tween.tween_property(n, "modulate:a", 1.0, 0.2)


func _set_status(msg: String) -> void:
	_status.text = msg


func _sync_empty() -> void:
	if _empty_box != null:
		_empty_box.visible = _songs.is_empty() and not bool(browser.osu_progress().running)   # osu! の曲を調べている間は、「曲がありません」を出さない
		_info.visible = not _songs.is_empty()   # 曲がないときは、空の情報パネルを出さない
		_stats.visible = not _songs.is_empty()
		_rec_card.visible = not _songs.is_empty()
		_search.visible = not _songs.is_empty()
		for b in _sort_btns:
			b.visible = not _songs.is_empty()


# --- 曲の検出 ---

func _scan() -> void:
	var msg := browser.scan()
	if msg != "":
		_set_status(msg)


## songs フォルダの中身が変わったとき(main が知らせる): 一覧を作り直す。選んでいる曲はそのまま(読み込み直さない)。
func refresh_songs() -> void:
	var r := browser.rescan()
	if str(r.msg) != "":
		_set_status(str(r.msg))
	if bool(r.rebuild):
		_rebuild_song_cards(false)
	else:
		_sync_cards()
	if _song_sel < 0 and not _songs.is_empty() and _loader == null and not browser.restoring():
		_select_song(0)


func _add_song_and_select(path: String) -> void:
	var i := browser.add_song(path)
	if i < 0:
		_set_status("%s を読み込めませんでした: %s" % [path.get_file(), SongLibrary.info(path).error])
		return
	_rebuild_song_cards()
	_select_song(i)


## 「.osz を開く」で選んだファイル: songs に取り込んで(次の起動でも残る)、一覧に加えて選ぶ。ドロップは main が受け取り、select_path で届く。
func _import_and_select(path: String) -> void:
	var r := OszImport.import_file(path)
	if not r.ok:
		_set_status(str(r.error))
		return
	_add_song_and_select(str(r.path))


## main から: 取り込み済みの曲(のパス)を、一覧に加えて選ぶ。
func select_path(path: String) -> void:
	_add_song_and_select(path)


# --- 曲のカルーセル ---
## 曲の行: 背景は曲の画像(暗くして、左ほど濃く)。曲名・アーティストと、難易度を色だけで示す小さな札の列。右に、その曲の最高ランク。
## 選んだ曲の下には、難易度の一覧が開く(星の色の札・難易度名・その難易度の最高ランク)。押すと選び、選んでいる難易度をもう一度押すと開始。
## 画像と難易度の色は SongArt(song_art.gd)が、見えている行の分から別スレッドで用意する(初めての曲だけ .osz を開く)。

func _rebuild_song_cards(animate := true) -> void:
	_clear_charts()   # 難易度順の行も、いったん捨てる(続く _apply_view が、また作る)
	_was_chart = false
	for c in _box.get_children():
		c.queue_free()
	_diff_box = null
	_diff_inner = null
	_diff_cards.clear()
	var top := Control.new()   # 一番上の行が、ツールバーに貼りつかないように(上端の余白も兼ねる)
	top.custom_minimum_size = Vector2(0, HEAD_BASE)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(top)
	_head = top
	_tail = Control.new()   # 下端の余白(ふだんは 0)
	_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head_extra = 0.0
	_tail_extra = 0.0
	_head_vel = 0.0
	_tail_vel = 0.0
	_h_prev = -1.0
	_rows.clear()
	_song_cards.clear()
	_art_asked.clear()
	_key_to_row.clear()
	_diff_rows.clear()
	_anchor_y = -1.0
	_box.add_child(_tail)
	for i in range(_songs.size()):
		_make_row(i, animate)
	_sync_empty()
	_apply_view()
	if _song_sel >= 0 and _song_sel < _songs.size():
		_open_diffs(false)
	_art_t = 1.0   # 見えている行の画像を、すぐに頼む


## 曲 i の行を作って、一覧の末尾(下端の余白の手前)に足す。
func _make_row(i: int, animate: bool) -> void:
	_key_to_row[str(_songs[i].md5)] = i
	var card := UiStyle.card(ROW_H, func(): _select_song(i), func(): _start())
	card.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW   # 画像を、角丸の形で切り抜く
	card.mouse_entered.connect(func():
		card.set_meta("hover", true)
		if i != _song_sel:
			UiSfx.play("hover", 1.0)
		_restyle_song(i))
	card.mouse_exited.connect(func(): card.set_meta("hover", false); _restyle_song(i))
	var holder := UiStyle.wrap_card(card, ROW_H)
	card.offset_right = -MARGIN_R
	holder.visible = not _was_chart   # 難易度順のあいだは、曲の行は出さない
	_box.add_child(holder)
	if _tail != null and is_instance_valid(_tail):
		_box.move_child(_tail, -1)
	_rows.append(holder)
	_song_cards.append(card)
	_fill_row(i)
	_restyle_song(i, false)
	if animate:
		_enter_card(card, 0.08 + minf(i, 8) * 0.05)


## 一覧に足された曲(行がまだない曲)の行を作る。budget_ms > 0 なら、その時間まで(残りは次のフレーム)。作り終えたら true。
func _sync_cards(budget_ms := -1.0) -> bool:
	var t0 := Time.get_ticks_usec()
	var made := false
	while _song_cards.size() < _songs.size():
		_make_row(_song_cards.size(), false)
		made = true
		if budget_ms > 0.0 and Time.get_ticks_usec() - t0 > int(budget_ms * 1000.0):
			break
	var done := _song_cards.size() >= _songs.size()
	if made and (done or Time.get_ticks_msec() - _view_at > 500):   # 並びへの反映は、作り終えたとき(と、作っている間はときどき)
		_view_at = Time.get_ticks_msec()
		_apply_view()
	_sync_empty()
	return done


## 開いたときに選んだ曲(前回の曲)を、一覧の真ん中に出す(プレイから戻ったとき、一覧の先頭が出ないように)。
## 行の位置は、レイアウトが終わるまで決まらないので、2 フレーム待ってから、動かさずに置く。待っている間に、別の曲を選んだら何もしない。
func _center_selected() -> void:
	var want := _song_sel
	if want < 0 or not is_inside_tree():
		return
	if _was_chart:   # 難易度順: 選んでいる譜面を真ん中へ(まだ読み込み終わっていなければ、終わってから)
		if _chart_sel != "":
			_center_chart_later()
		else:
			_chart_center_pending = true
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or _song_sel != want or want >= _rows.size():
		return
	_smooth.center_on_control(_rows[want], true)


## osu! の Songs の曲を、少しずつ一覧に足す(毎フレーム)。前回の曲が見つかったら、そこを選ぶ。
func _pump_osu() -> void:
	var r := browser.pump(3000)
	if bool(r.added) or _song_cards.size() < _songs.size():
		_sync_cards(3.0)
	if bool(r.restored) or int(r.select) >= 0:
		_sync_cards()   # 選ぶ曲の行は、すぐに要る
	if bool(r.restored):   # 一覧を作り直す前に選んでいた曲(読み込み直さない)
		_restyle_all()
		_anchor_y = (_rows[_song_sel] as Control).position.y if _song_sel >= 0 and _song_sel < _rows.size() else -1.0
		_open_diffs(false)
		_sync_chart_sel(false)
	elif int(r.select) >= 0:
		_select_song(int(r.select))
		_center_selected()
	_pump_progress()


## osu! の曲を調べている間の、進み具合(左上の情報の下に、薄い文字で)。
func _pump_progress() -> void:
	var now := Time.get_ticks_msec()
	if now - _progress_at < 300 or _status == null:
		return
	_progress_at = now
	var pr := browser.osu_progress()
	var mine := _status.text.begins_with("osu! の曲")
	if bool(pr.running) and (_status.text == "" or mine):
		_status.text = "osu! の曲を準備しています… %d / %d" % [int(pr.done), int(pr.total)]
		_status.add_theme_color_override("font_color", LazerStyle.TEXT_MUTE)
		_sync_empty()
	elif mine:
		_status.text = ""
		_status.add_theme_color_override("font_color", LazerStyle.RED)
		_sync_empty()


## 行の中身を作る: 背景の画像・暗くする帯・文字と難易度の色の札・最高ランク・縁。
func _fill_row(i: int) -> void:
	if i < 0 or i >= _song_cards.size():
		return
	var card: PanelContainer = _song_cards[i]
	for c in card.get_children():
		card.remove_child(c)
		c.queue_free()
	var key := str(_songs[i].md5)
	var base := LazerStyle.title_color(str(_songs[i].title))
	card.add_theme_stylebox_override("panel", LazerStyle.box(Color(base.r * 0.22, base.g * 0.22, base.b * 0.26), Color(0, 0, 0, 0), 0, 12, 0, 0))
	var bg := TextureRect.new()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.texture = SongArt.texture_of(key)
	card.add_child(bg)
	var shade := TextureRect.new()   # 左ほど濃い暗幕(文字が読めるように)
	shade.texture = _shade_tex()
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(shade)
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in [["left", 20], ["right", 16], ["top", 5], ["bottom", 5]]:
		m.add_theme_constant_override("margin_" + side[0], side[1])
	card.add_child(m)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var t := LazerStyle.label(_songs[i].title, 17, LazerStyle.TEXT, true)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	t.add_theme_constant_override("shadow_offset_y", 1)
	v.add_child(t)
	var a := LazerStyle.label(_songs[i].artist, 13, LazerStyle.TEXT_DIM)
	a.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(a)
	var dots := Control.new()   # 難易度の色だけの札(易しい順)
	dots.custom_minimum_size = Vector2(0, 14)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dots.draw.connect(func(): _draw_dots(dots, i))
	v.add_child(dots)
	var best := Records.best_of_song(_songs[i].get("ids", []))
	if not best.is_empty():   # その曲の最高ランク
		var badge := CenterContainer.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(LazerStyle.pill(str(best.rank), UiStyle.rank_color(str(best.rank)), 15))
		h.add_child(badge)
	var frame := Panel.new()   # 縁(状態で色が変わる)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(frame)
	card.set_meta("bg", bg)
	card.set_meta("shade", shade)
	card.set_meta("frame", frame)
	card.set_meta("dots", dots)


## 難易度の色の札: 白い丸(譜面の印)と、難易度ごとの小さな角丸の札。多いときは、入るだけ並べて「+n」。
func _draw_dots(dots: Control, i: int) -> void:
	var secs := int(SongArt.length_of(str(_songs[i].md5)))   # 右端に、曲の長さ(分かっていれば)
	if secs > 0:
		dots.draw_string(LazerStyle.font(), Vector2(0, 11), "%d:%02d" % [secs / 60, secs % 60], HORIZONTAL_ALIGNMENT_RIGHT, dots.size.x, 12, LazerStyle.TEXT_DIM)
	var cols := _dot_colors(i)
	if cols.is_empty():
		return
	var y := 3.0
	dots.draw_arc(Vector2(6, y + 4), 5.0, 0.0, TAU, 20, Color(1, 1, 1, 0.9), 2.0, true)
	var x := 17.0
	var room := int((dots.size.x - x - 30.0 - (44.0 if secs > 0 else 0.0)) / 13.0)
	for k in range(mini(cols.size(), room)):
		dots.draw_style_box(LazerStyle.box(cols[k], Color(0, 0, 0, 0), 0, 4), Rect2(x, y, 10, 8))
		x += 13.0
	if cols.size() > room:
		dots.draw_string(LazerStyle.font_bold(), Vector2(x + 2, y + 9), "+%d" % (cols.size() - room), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LazerStyle.TEXT_DIM)


## 行 i の難易度の色(易しい順)。読み込んで測った Lv があればそれ、なければ譜面の★の推定から。
func _dot_colors(i: int) -> Array:
	var out: Array = []
	if i == _song_sel and _loader != null and not _job_pending and _ratings.size() == _loader.difficulties.size():
		for r in _ratings:
			out.append(LazerStyle.level_color(float(r.base_level)))
		return out
	for d in SongArt.diffs_of(str(_songs[i].md5)):
		out.append(LazerStyle.level_color(float(_lv_seen.get(str(d[0]), d[2]))))
	return out


## 行の暗幕(左が濃く、右へ薄くなる)。全部の行で 1 枚を使い回す。
static func _shade_tex() -> Texture2D:
	if _shade == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.05, 0.04, 0.09, 0.88))
		g.set_color(1, Color(0.05, 0.04, 0.09, 0.38))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.width = 64
		gt.height = 4
		_shade = gt
	return _shade


## SongArt から、行の画像と難易度が届いた。
func _on_art(info: Dictionary, key: String) -> void:
	if info.tex != null:   # 難易度順の、その曲の譜面の行にも画像を入れる
		for h in _chart_by_song.get(key, []):
			if is_instance_valid(h) and (h as Control).has_meta("card") and ((h as Control).get_meta("card") as Control).has_meta("bg"):
				var cbg: TextureRect = ((h as Control).get_meta("card") as Control).get_meta("bg")
				if cbg.texture != info.tex:
					cbg.texture = info.tex
					UiStyle.tween(cbg, "modulate:a", 0.0, 1.0, 0.35)
	var i := int(_key_to_row.get(key, -1))
	if i < 0 or i >= _song_cards.size():
		return
	var card: PanelContainer = _song_cards[i]
	if not card.has_meta("bg"):
		return
	var bg: TextureRect = card.get_meta("bg")
	if info.tex != null and bg.texture != info.tex:
		bg.texture = info.tex
		UiStyle.tween(bg, "modulate:a", 0.0, 1.0, 0.35)   # 画像は、ふわっと現れる
	(card.get_meta("dots") as Control).queue_redraw()
	if i == _song_sel and not _diffs_ready():   # 読み込み中の曲: 難易度が分かった(まだ開いていなければ開く。開いていれば、その場で差し替える)
		_fill_diffs()


## 見えている行(と、その少し先)の画像を SongArt に頼む。
func _request_visible_art() -> void:
	if _rows.is_empty() or not is_inside_tree():
		return
	var view := _scroll.get_global_rect().grow(ROW_H * 3.0)
	for i in range(_rows.size()):
		if _art_asked.has(i) or not _rows[i].visible:
			continue
		if view.intersects((_rows[i] as Control).get_global_rect()):
			_art_asked[i] = true
			var key := str(_songs[i].md5)
			SongArt.request(get_tree(), key, str(_songs[i].path), _on_art.bind(key), i == _song_sel)


func _process(delta: float) -> void:
	super._process(delta)
	_pump_osu()
	_release_spacers(delta)
	_art_t += delta
	if _art_t > 0.2:
		_art_t = 0.0
		_request_visible_art()
	if _was_chart:
		_fill_visible_charts()
	if _charts_dirty and (_was_chart or browser.sort_mode == "length") and Time.get_ticks_msec() - _charts_at > CHART_REBUILD_MS:   # 集めた難易度・長さが増えた: 並びに加える(ときどき、まとめて。スクロールは動かさない)
		_charts_dirty = false
		_charts_at = Time.get_ticks_msec()
		_apply_view(false, true)


func _set_head(v: float) -> void:
	_head_extra = maxf(v, 0.0)
	if _head != null and is_instance_valid(_head):
		_head.custom_minimum_size.y = HEAD_BASE + _head_extra


func _set_tail(v: float) -> void:
	_tail_extra = maxf(v, 0.0)
	if _tail != null and is_instance_valid(_tail):
		_tail.custom_minimum_size.y = _tail_extra


## 上端・下端の余白を戻す。画面の外にある分は、すぐに(見た目は変わらない)。見えている分は、一覧が閉じ終わってから、ばねでなめらかに。
func _release_spacers(delta: float) -> void:
	if _head == null or not is_instance_valid(_head):
		return
	var dt := minf(delta, 1.0 / 30.0)
	var settled := Time.get_ticks_msec() >= _collapse_until
	if _head_extra > 0.0:
		var hidden := minf(_head_extra, float(_scroll.scroll_vertical))   # 画面より上に隠れている分: 消して、同じだけスクロールを戻す
		if hidden >= 1.0:
			_set_head(_head_extra - hidden)
			_anchor_y -= hidden
			_h_prev -= hidden
			_smooth.shift(-hidden)
		elif settled:
			var before := _head_extra
			_head_vel += (-SPACER_W * SPACER_W * _head_extra - 2.0 * SPACER_W * _head_vel) * dt
			_set_head(_head_extra + _head_vel * dt if _head_extra > 0.6 else 0.0)
			if _head_extra <= 0.0:
				_head_vel = 0.0
			_anchor_y -= before - _head_extra   # わざと動かしている(選んだ行の位置を保つ処理に、打ち消させない)
			_h_prev -= before - _head_extra
	if _tail_extra > 0.0:
		var max_s := maxf(_scroll.get_v_scroll_bar().max_value - _scroll.get_v_scroll_bar().page, 0.0)
		var below := minf(_tail_extra, max_s - float(_scroll.scroll_vertical))   # 画面より下に隠れている分: すぐ消す
		if below >= 1.0:
			_set_tail(_tail_extra - below)
			_h_prev -= below
		elif settled:
			var before_t := _tail_extra
			_tail_vel += (-SPACER_W * SPACER_W * _tail_extra - 2.0 * SPACER_W * _tail_vel) * dt
			_set_tail(_tail_extra + _tail_vel * dt if _tail_extra > 0.6 else 0.0)
			if _tail_extra <= 0.0:
				_tail_vel = 0.0
			_h_prev -= before_t - _tail_extra


## 行の見た目と、横のずれ(選んでいる行は左へせり出し、縁がピンクになって明るくなる)。
func _restyle_song(i: int, animated := true) -> void:
	if i < 0 or i >= _song_cards.size():
		return
	_style_row_card(_song_cards[i], i == _song_sel, animated)


## 行(曲の行も、難易度順の譜面の行も)のカードの見た目。縁(選んでいる = ピンク・ホバー = 白)・暗幕の濃さ・横のずれ。
func _style_row_card(card: PanelContainer, sel: bool, animated := true) -> void:
	if not card.has_meta("frame"):
		return
	var hover := bool(card.get_meta("hover", false))
	var frame: Panel = card.get_meta("frame")
	var fs := StyleBoxFlat.new()
	fs.draw_center = false
	fs.set_corner_radius_all(12)
	fs.anti_aliasing = true
	if sel:
		fs.border_color = LazerStyle.PINK
		fs.set_border_width_all(3)
	elif hover:
		fs.border_color = Color(1, 1, 1, 0.35)
		fs.set_border_width_all(2)
	else:
		fs.border_color = Color(1, 1, 1, 0.07)
		fs.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", fs)
	var shade: Control = card.get_meta("shade")
	var to_a := 0.62 if sel else (0.82 if hover else 1.0)   # 選んでいる行は、画像を明るく見せる
	if animated and UiStyle.animate and shade.is_inside_tree():
		UiStyle.tween(shade, "modulate:a", shade.modulate.a, to_a, 0.25)
	else:
		shade.modulate.a = to_a
	var indent := INDENT_SEL if sel else (INDENT_HOVER if hover else INDENT)
	_shift_card(card, indent, animated)


## カードを左右に動かす(カードは入れものいっぱいに広がっていて、左端の位置 = 余白)。
func _shift_card(card: Control, indent: float, animated: bool) -> void:
	card.set_meta("indent_target", indent)
	if card.get_meta("entering", false):
		return
	var old = card.get_meta("shift_tween") if card.has_meta("shift_tween") else null
	if old is Tween and old.is_valid():
		old.kill()
	if not animated or not UiStyle.animate or not card.is_inside_tree():
		card.offset_left = indent
		card.set_meta("indent", indent)
		return
	var from := card.offset_left
	var t := card.create_tween()
	t.tween_method(func(v: float): card.offset_left = v, from, indent, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	card.set_meta("indent", indent)
	card.set_meta("shift_tween", t)


# --- 難易度の一覧(選んだ曲の下に開く) ---
## 開くのは 1 回だけ: 曲を選んだ時点で難易度が分かっていれば(SongArt に保存済み)すぐ、分からなければ分かった時点で開く。
## 読み込みが終わったら、行は作り直さず、その場で数字・色だけを差し替える(点滅させない)。

## 選んでいる曲の下に、難易度の一覧を開く(前の一覧は閉じる)。animate: 高さが 0 から伸び、行が上から順に現れる。
func _open_diffs(animate := true) -> void:
	_close_diffs(animate)
	if _song_sel < 0 or _song_sel >= _rows.size():
		return
	var items := _diff_items()
	if items.is_empty():   # まだ何も分からない(初めての曲の読み込み中): 分かってから開く
		return
	var holder := Control.new()
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(0, 0)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", DIFF_GAP)
	inner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	inner.offset_left = DIFF_INDENT
	inner.offset_right = -MARGIN_R
	inner.offset_top = 2.0
	inner.set_meta("base_y", 2.0)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(inner)
	_box.add_child(holder)
	_box.move_child(holder, (_rows[_song_sel] as Control).get_index() + 1)
	holder.visible = (_rows[_song_sel] as Control).visible
	_diff_box = holder
	_diff_inner = inner
	_diff_rows.clear()
	for k in range(items.size()):
		var row := _diff_row(k)
		_set_diff_row(row, items[k])
		inner.add_child(row)
		_diff_rows.append(row)
		if animate and UiStyle.animate:   # 上から順に、ふわっと現れる
			row.modulate.a = 0.0
			UiStyle.tween(row, "modulate:a", 0.0, 1.0, 0.24, 0.05 + 0.035 * k)
	_diff_cards = _diff_rows.duplicate() if _diffs_ready() else []
	_set_diff_height(items.size(), animate)
	_style_diffs(false)


## 難易度の一覧を閉じる(高さを 0 へ縮めてから消す)。
func _close_diffs(animate := true) -> void:
	_diff_cards.clear()
	_diff_rows.clear()
	if _diff_box == null:
		return
	var old := _diff_box
	_diff_box = null
	_diff_inner = null
	if not animate or not UiStyle.animate or not old.is_inside_tree():
		old.queue_free()
		return
	var h := old.custom_minimum_size.y
	var dur := clampf(0.24 + h / 1500.0, 0.24, 0.62)   # 大きい一覧ほど、ゆっくり閉じる(下の行が一度に大きく動かない)
	_collapse_until = Time.get_ticks_msec() + int(dur * 1000.0) + 30
	var t := old.create_tween().set_parallel(true)
	t.tween_property(old, "custom_minimum_size:y", 0.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(old, "modulate:a", 0.0, minf(0.18, dur * 0.5))
	t.chain().tween_callback(old.queue_free)


## 読み込みが終わった・MOD が変わった: 一覧の中身を、今の値にする。行の数が同じなら、その場で差し替える(作り直さない)。
func _fill_diffs() -> void:
	if _diff_box == null:
		_open_diffs()
		_scroll_to_selection()
		return
	var items := _diff_items()
	if items.size() != _diff_rows.size():   # 数が変わった(推定と実際が違った): 足りない行を足す・余った行を消す
		while _diff_rows.size() > items.size():
			var r: Control = _diff_rows.pop_back()
			r.queue_free()
		while _diff_rows.size() < items.size():
			var row := _diff_row(_diff_rows.size())
			_diff_inner.add_child(row)
			_diff_rows.append(row)
		_set_diff_height(items.size(), true)
		_scroll_to_selection()
	for k in range(items.size()):
		_set_diff_row(_diff_rows[k], items[k])
	_diff_cards = _diff_rows.duplicate() if _diffs_ready() else []
	_style_diffs(true)


## 一覧の高さを、行の数に合わせる(なめらかに)。
func _set_diff_height(n: int, animate: bool) -> void:
	var holder := _diff_box
	if holder == null:
		return
	var target := _diff_list_h(n)
	var old = holder.get_meta("h_tween") if holder.has_meta("h_tween") else null
	if old is Tween and old.is_valid():
		old.kill()
	if not animate or not UiStyle.animate or not holder.is_inside_tree():
		holder.custom_minimum_size.y = target
		return
	var t := holder.create_tween()
	t.tween_property(holder, "custom_minimum_size:y", target, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	holder.set_meta("h_tween", t)


func _diff_list_h(n: int) -> float:
	return float(n) * DIFF_H + float(maxi(n - 1, 0)) * DIFF_GAP + 10.0


## 読み込み済みで、測った Lv が使えるか。
func _diffs_ready() -> bool:
	return _loader != null and not _job_pending and _ratings.size() == _loader.difficulties.size()


## 一覧に出すもの [[譜面の識別子, 難易度名, Lv, 測った値か], ...]。読み込み済みなら測った Lv、まだなら推定の★(または、前に測った Lv)。
func _diff_items() -> Array:
	var items: Array = []
	if _song_sel < 0 or _song_sel >= _songs.size():
		return items
	if _diffs_ready():
		for k in range(_ratings.size()):
			var bm = _loader.difficulties[k]
			items.append([str(bm.md5), str(bm.version), float(_ratings[k].level), true])
	else:
		for d in SongArt.diffs_of(str(_songs[_song_sel].md5)):
			items.append([str(d[0]), str(d[1]), float(_lv_seen.get(str(d[0]), d[2])), _lv_seen.has(str(d[0]))])
	return items


## 難易度の 1 行(中身は _set_diff_row で入れる)。押すと選び、選んでいる難易度をもう一度押すと開始(読み込み中は押せない)。
func _diff_row(k: int) -> Control:
	var card := UiStyle.card(DIFF_H, func():
		if not _diffs_ready():
			return
		if k == _diff_sel and browser.can_start():   # 選んでいる難易度を、もう一度押した: 開始
			_start()
		else:
			_select_diff(k), func(): if _diffs_ready(): _start())
	card.set_meta("base_y", 0.0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pb := HBoxContainer.new()
	pb.add_theme_constant_override("separation", 4)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(pb)
	var star := LazerIcons.new("star", Color.WHITE, 12.0)
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.add_child(star)
	var lv_l := LazerStyle.label("", 14, Color.WHITE, true)
	lv_l.custom_minimum_size = Vector2(34, 0)   # 数字の幅が変わっても、札の大きさが揺れない
	pb.add_child(lv_l)
	h.add_child(pill)
	var name_l := LazerStyle.label("", 16, LazerStyle.TEXT, true)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(name_l)
	var badge := CenterContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(badge)
	var wrap := UiStyle.wrap_card(card, DIFF_H)
	wrap.set_meta("card", card)
	card.set_meta("pill", pill)
	card.set_meta("star", star)
	card.set_meta("lv_l", lv_l)
	card.set_meta("name_l", name_l)
	card.set_meta("badge", badge)
	card.set_meta("col", LazerStyle.PANEL)
	return wrap


## 行の中身を入れる・差し替える(Lv の札の色と数字・難易度名・その難易度の最高ランク)。
func _set_diff_row(wrap: Control, item: Array) -> void:
	var card: PanelContainer = wrap.get_meta("card")
	var lv := float(item[2])
	var col := LazerStyle.level_color(lv)
	var ink := LazerStyle.ink_on(col)
	card.set_meta("col", col)
	(card.get_meta("pill") as PanelContainer).add_theme_stylebox_override("panel", LazerStyle.box(col, Color(0, 0, 0, 0), 0, 12, 9, 2))
	var star: Control = card.get_meta("star")
	star.set("col", ink)
	star.queue_redraw()
	var lv_l: Label = card.get_meta("lv_l")
	lv_l.text = "%.2f" % lv
	lv_l.add_theme_color_override("font_color", ink)
	(card.get_meta("name_l") as Label).text = str(item[1])
	var badge: Control = card.get_meta("badge")
	var rank := str(Records.best(str(item[0])).get("rank", ""))
	if str(badge.get_meta("rank", "")) != rank:
		badge.set_meta("rank", rank)
		for c in badge.get_children():
			c.queue_free()
		if rank != "":
			badge.add_child(LazerStyle.pill(rank, UiStyle.rank_color(rank), 13))


## 難易度の行の面: 縁と左の太い帯が Lv の色。選んでいると明るい地に、はっきりした縁。
static func _diff_style(col: Color, sel: bool) -> StyleBoxFlat:
	var s := LazerStyle.box(Color(LazerStyle.PANEL_SEL.r, LazerStyle.PANEL_SEL.g, LazerStyle.PANEL_SEL.b, 0.97) if sel else Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.86),
		Color(col.r, col.g, col.b, 1.0 if sel else 0.45), 2 if sel else 1, 10, 0, 0)
	s.border_width_left = 7   # 左の太い帯が、Lv の色
	s.content_margin_left = 18
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


## 難易度の行の見た目(選んでいる難易度は明るく、縁がはっきりして、ほかより左へ出る)。読み込み中は、どれも選んでいない見た目。
func _style_diffs(animated := true) -> void:
	var ready := _diffs_ready()
	for k in range(_diff_rows.size()):
		var card: PanelContainer = (_diff_rows[k] as Control).get_meta("card")
		var col: Color = card.get_meta("col")
		var sel := ready and k == _diff_sel
		card.add_theme_stylebox_override("panel", _diff_style(col, sel))
		var to := 0.0 if sel else 16.0
		var old = card.get_meta("x_tween") if card.has_meta("x_tween") else null
		if old is Tween and old.is_valid():
			old.kill()
		if not animated or not UiStyle.animate or not card.is_inside_tree():
			card.offset_left = to
		elif not is_equal_approx(card.offset_left, to):
			var t := card.create_tween()
			t.tween_property(card, "offset_left", to, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			card.set_meta("x_tween", t)


## 選んだ曲と、その難易度の一覧(開ききった高さ)が見えるように、1 回だけ、なめらかにスクロールする。
## 一覧が高すぎるときは、曲の行を上に合わせる。前の一覧が閉じていく分は、_on_box_sorted が位置を保つ(ここでは考えなくてよい)。
func _scroll_to_selection() -> void:
	if _song_sel < 0 or _song_sel >= _rows.size() or not (_rows[_song_sel] as Control).visible:
		return
	var row: Control = _rows[_song_sel]
	var n := _diff_rows.size() if _diff_box != null else SongArt.diffs_of(str(_songs[_song_sel].md5)).size()
	var top := row.position.y
	var bottom := top + ROW_H + (float(ROW_GAP) + _diff_list_h(n) if n > 0 else 0.0)
	var page := _scroll.size.y
	var cur: float = _smooth.target()
	var t := cur
	if top - 16.0 < cur:
		t = top - 16.0
	elif bottom + 16.0 > cur + page:
		t = minf(bottom + 16.0 - page, top - 16.0)
	if not is_equal_approx(t, cur):
		_smooth.scroll_to(t)


## 一覧の並び(高さ・順番)が変わった直後(描く前に呼ばれる): 選んでいる曲の行が、画面の同じ位置に残るように、スクロールをずらす
## (上の一覧が閉じても、選んだ行がガクッと動かない)。並び替えの直後なら、行を前の見た目の位置から新しい位置へ滑らせる。
func _on_box_sorted() -> void:
	var applied := 0
	var anchor: Control = _rows[_song_sel] if _song_sel >= 0 and _song_sel < _rows.size() else null
	if _was_chart:   # 難易度順: 選んでいる譜面の行を、基準にする
		var ch = _chart_holders.get(_chart_sel) if _chart_sel != "" else null
		anchor = ch if ch != null and is_instance_valid(ch) and (ch as Control).is_inside_tree() else null
	if anchor != null and anchor.visible:
		var y := anchor.position.y
		if _anchor_y >= 0.0 and absf(y - _anchor_y) > 0.01:
			var dy := y - _anchor_y
			applied = _smooth.shift(dy)
			var miss := dy - float(applied)   # スクロールでは打ち消せなかった分(上端にいて、これ以上上へスクロールできない)
			if miss < -0.5:   # 行が上へ動いてしまう: その分を上端の余白で受け止める
				_set_head(_head_extra - miss)
				y -= miss
		_anchor_y = y
	else:
		_anchor_y = -1.0
	if _tail != null and is_instance_valid(_tail):   # 中身が縮んだ: 下端の余白で受け止める(下端にいても、見えている行が押し下げられない)
		var h := _box.get_combined_minimum_size().y
		if _h_prev >= 0.0 and h < _h_prev - 0.5:
			_set_tail(_tail_extra + (_h_prev - h))
			h = _h_prev
		_h_prev = h
	if _flip_pending:
		_flip_pending = false
		_run_flip(applied)


## 並び替えの動き: 前も後も画面に見えている行だけを、前の位置から新しい位置へ滑らせる(上から順に少しずつ遅れて。遠くへ動く行ほど少し長く)。
## 画面の外から入ってきた行は、滑らせず、そっと現れさせる(曲が多いと、遠くから速く飛んでくる動きが、目にうるさいため)。画面の外に出ていく行・外のままの行は、動かさない。
func _run_flip(scrolled: int) -> void:
	var page := _scroll.size.y
	var s1 := _flip_s0 + float(scrolled)   # 並び替えのあとの、スクロールの位置
	var k := 0
	for c in _box.get_children():
		if not (c is Control) or not c.visible or c.get_child_count() == 0:
			continue
		var inner: Control = c.get_child(0)   # 行はカード、難易度の一覧は中の VBox を動かす
		var base_y := float(inner.get_meta("base_y", 0.0))
		var old = inner.get_meta("flip_tween") if inner.has_meta("flip_tween") else null
		if old is Tween and old.is_valid():
			old.kill()
		var y1: float = (c as Control).position.y
		if not (y1 + (c as Control).size.y > s1 and y1 < s1 + page):   # 並び替えのあとも画面の外: 動かさない
			inner.position.y = base_y
			inner.modulate.a = 1.0
			continue
		if not _flip_before.has(c):   # 画面の外から入ってきた行
			inner.position.y = base_y
			inner.modulate.a = 0.5
			var tf := inner.create_tween()
			tf.tween_property(inner, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			inner.set_meta("flip_tween", tf)
			continue
		var dy: float = float(_flip_before[c]) - y1 + float(scrolled)   # 見た目の位置の差(スクロールのずれも含める)
		if absf(dy) < 0.5:
			inner.position.y = base_y
			continue
		inner.position.y = base_y + dy
		var dur := clampf(0.34 + absf(dy) / 4000.0, 0.34, 0.6)
		var tw := inner.create_tween()
		tw.tween_property(inner, "position:y", base_y, dur).set_delay(minf(0.016 * k, 0.1)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		inner.set_meta("flip_tween", tw)
		k += 1
	_flip_before = {}


## カードの登場: 右から滑り込みながらフェードイン。
func _enter_card(card: Control, delay: float) -> void:
	if not UiStyle.animate or not card.is_inside_tree():
		return
	card.modulate.a = 0.0
	card.set_meta("entering", true)
	var t := card.create_tween().set_parallel(true)
	t.tween_property(card, "modulate:a", 1.0, 0.35).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_method(func(v: float): card.offset_left = lerpf(160.0, float(card.get_meta("indent_target", INDENT)), v), 0.0, 1.0, 0.45) \
		.set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.chain().tween_callback(func(): card.set_meta("entering", false))
	card.offset_left = 160.0


func _restyle_all() -> void:
	for i in range(_song_cards.size()):
		_restyle_song(i)


## 曲を選ぶ。選んだ表示はすぐ切り替わり、重い読み込みは browser が別スレッドで行う。終わったら _on_song_loaded で札などを入れ替える。
func _select_song(i: int) -> void:
	if _songs.is_empty():
		return
	i = clampi(i, 0, _songs.size() - 1)
	if i == _song_sel and (_loader != null or _job_pending):
		_restyle_all()
		return
	browser.select_song(i)


## 曲を選んだ(browser から。読み込みの開始)。表示をすぐ切り替えて、読み込み中の見た目にする。
func _on_song_changing(old: int, i: int) -> void:
	UiSfx.play("select", UiSfx.scale_pitch(float(i % 6) / 5.0, 1.0))   # 曲を移るごとに、音階が上がる・下がる
	_restyle_song(old)
	_restyle_song(i)
	if old >= 0 and old < _song_cards.size() and _song_cards[old].has_meta("dots"):
		(_song_cards[old].get_meta("dots") as Control).queue_redraw()
	_anchor_y = (_rows[i] as Control).position.y   # ここから先は、この行を画面の同じ位置に保つ
	_open_diffs()   # 選んだ曲の下に、難易度の一覧を開く(難易度がまだ分からなければ、分かったときに開く)
	if not _art_asked.has(i):   # 選んだ曲の画像は、先に頼む
		_art_asked[i] = true
		SongArt.request(get_tree(), str(_songs[i].md5), str(_songs[i].path), _on_art.bind(str(_songs[i].md5)), true)
	_scroll_to_selection()
	_title_l.text = _songs[i].title   # 曲名・アーティストはすぐ分かるので、ここで 1 回だけ滑り込ませる(読み込み後は動かさない)
	_artist_l.text = _songs[i].artist
	var k := 0
	for lab in [_title_l, _artist_l]:
		UiStyle.pop_in(lab, k * 0.06, Vector2(24, 0), 0.4)
		k += 1
	_set_loading(true)   # BPM・Lv・内訳・記録は、消さずに少し薄くして、読み込み後に差し替える
	_sync_chart_sel()


## 曲を読み込めなかった(browser から)。選択は前の曲に戻してある。
func _on_song_load_failed(error: String, bad: int) -> void:
	_chart_want = ""
	_set_status(error)
	_restyle_song(bad)
	_restyle_song(_song_sel)
	if _loader != null and _song_sel >= 0 and _song_sel < _songs.size():
		_title_l.text = _songs[_song_sel].title
		_artist_l.text = _songs[_song_sel].artist
	_set_loading(false)   # 前の曲の難易度が残っていれば、それをまた選べる
	if _song_sel >= 0 and _song_sel < _rows.size():   # 前の曲の難易度の一覧を、開き直す
		_anchor_y = (_rows[_song_sel] as Control).position.y
		_open_diffs()
		_scroll_to_selection()
	_sync_chart_sel()
	_update_detail()


## 曲を読み込み終わった(browser から。loader・gens・ratings・diff_sel は更新済み)。
func _on_song_loaded(res: Dictionary) -> void:
	var first = _loader.difficulties[0]
	_meta_l.text = "BPM %.0f      譜面  %s" % [60000.0 / first.beat_length_at(first.first_time()), first.creator]
	var reload := bool(res.get("reload", false))   # 弾幕 v2 の入り切りで読み直した: 背景と試聴は、そのまま
	var tex: Texture2D = null
	if res.image != null and not reload:
		tex = ImageTexture.create_from_image(res.image)
	if not reload:
		set_background(tex)
	for d in range(_ratings.size()):   # 測った Lv を覚えておく(ほかの曲へ移ったあとも、行の色の札に使う)
		_lv_seen[str(_loader.difficulties[d].md5)] = float(_ratings[d].base_level)
	if _chart_want != "":   # 難易度順で押した譜面: 読み込めたので、その難易度を選ぶ
		var wk := _diff_index_of(_chart_want)
		if wk >= 0:
			browser.select_diff(wk)
		_chart_want = ""
	if _was_chart:
		_refresh_chart_lv(str(_songs[_song_sel].md5))
		_sync_chart_sel(false)
		if _chart_center_pending and _chart_sel != "":
			_chart_center_pending = false
			_center_chart_later()
	var card: PanelContainer = _song_cards[_song_sel]
	if card.has_meta("bg"):
		if (card.get_meta("bg") as TextureRect).texture == null and tex != null:   # 行の画像がまだなら、読み込んだ画像を使う
			(card.get_meta("bg") as TextureRect).texture = tex
		(card.get_meta("dots") as Control).queue_redraw()
	_set_loading(false)
	_fill_diffs()   # 開いていなければ開き、開いていれば、その場で数字・色を差し替える
	_update_detail()
	if _mod_panel != null:   # MOD パネルを開いたまま曲が読み込まれた
		_mod_panel.refresh_info()
	if reload:
		return
	_audio.stop()
	if res.audio != null:
		await get_tree().process_frame   # 札を作る処理と、同じフレームにしない(音の開始も、少し時間がかかる)
		if int(res.job) == browser.job and is_inside_tree():
			_audio.stream = res.audio
			_audio.play(float(res.audio_from))


# --- 難易度 ---

func _rate_all() -> void:
	browser.rate_all()


func _select_diff(i: int) -> void:
	var old := browser.select_diff(i)
	if old == -2:
		return
	i = _diff_sel
	if old != i:
		UiSfx.play("select", 1.35 * UiSfx.scale_pitch(float(i % 6) / 5.0, 1.0))
	_style_diffs()
	_sync_chart_sel()
	_update_detail()
	if _mod_panel != null and old != i:
		_mod_panel.refresh_info()


func _lv_holder_clear() -> void:
	for c in _lv_holder.get_children():
		_lv_holder.remove_child(c)
		c.queue_free()


## 選んでいる難易度の情報(左上の Lv の札・難易度名・内訳)を作り直す。
func _update_detail() -> void:
	_lv_holder_clear()
	_update_records()
	if _diff_sel < 0 or _diff_sel >= _ratings.size() or _loader == null:
		_stat_rows = []
		_stat_note = ""
		_stats.queue_redraw()
		return
	var r: Dictionary = _ratings[_diff_sel]
	var bm = _loader.difficulties[_diff_sel]
	var col := LazerStyle.level_color(float(r.level))
	var ink := LazerStyle.ink_on(col)
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", LazerStyle.box(col, Color(0, 0, 0, 0), 0, 15, 12, 3))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(hb)
	var star := LazerIcons.new("star", ink, 15.0)
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(star)
	hb.add_child(LazerStyle.label("%.2f" % float(r.level), 18, ink, true))
	_lv_holder.add_child(pill)
	var name_l := LazerStyle.label(str(bm.version), 20, LazerStyle.TEXT, true)
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_lv_holder.add_child(name_l)
	if absf(float(r.level) - float(r.base_level)) >= 0.005:
		var base := LazerStyle.label("MODなし  %.2f" % float(r.base_level), 14, LazerStyle.TEXT_MUTE)
		base.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_lv_holder.add_child(base)
	var secs := int(round((bm.last_time() - bm.first_time()) / 1000.0))
	var cur: Array = []
	for q in range(_stat_rows.size()):   # いま見えている長さから動かす
		cur.append(_stat_from_old(q))
	_stat_from = cur
	_stat_rows = [
		["平均弾数", clampf(float(r.mean) / BAR_MAX, 0.0, 1.0), "%d 発" % int(round(float(r.mean)))],
		["最大弾数", clampf(float(r.peak) / BAR_MAX, 0.0, 1.0), "%d 発" % int(r.peak)],
		["弾速", clampf(float(r.speed) / SPEED_MAX, 0.0, 1.0), "%d px/s" % int(round(float(r.speed)))],
	]
	_stat_note = "弾径 %.1f      イベント %d      長さ %d:%02d      本家★≈%.2f" % [float(r.size), _gens[_diff_sel].events.size(), secs / 60, secs % 60, float(r.stars)]
	_stat_k = 0.0 if UiStyle.animate and is_inside_tree() else 1.0
	if _stat_k < 1.0:
		var t := _stats.create_tween()
		t.tween_method(func(v: float):
			_stat_k = v
			_stats.queue_redraw(), 0.0, 1.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_stats.queue_redraw()


## 内訳のバーの q 番目が、いま見えている長さ(動いている途中なら、その途中の長さ)。
func _stat_from_old(q: int) -> float:
	if q >= _stat_rows.size():
		return 0.0
	var from := float(_stat_from[q]) if q < _stat_from.size() else 0.0
	return lerpf(from, float(_stat_rows[q][1]), _stat_k)


# --- 付けている MOD ---

func _refresh_mod_bar() -> void:
	for c in _mod_bar.get_children():
		c.queue_free()
	var p := Mods.params(settings.mods)
	if _v2_btn != null:   # 弾幕 v2 を付けていないときだけ、フッターに「弾幕 v2 で遊ぼう」を出す
		var want: bool = not p.gen_v2
		if want and not _v2_btn.visible:
			UiStyle.pop_in(_v2_btn, 0.0, Vector2(0, 20), 0.35)
		_v2_btn.visible = want
	if p.ids.is_empty():
		_mod_bar.add_child(LazerStyle.label("MOD なし", 14, LazerStyle.TEXT_MUTE))
		return
	for id in p.ids:
		var m := Mods.find(id)
		var chip := PanelContainer.new()
		var c: Color = m.color
		chip.add_theme_stylebox_override("panel", LazerStyle.box(Color(c.r, c.g, c.b, 0.22), Color(c.r, c.g, c.b, 0.8), 1, 12, 10, 2))
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(LazerStyle.label(str(m.name), 14, c))
		_mod_bar.add_child(chip)
		UiStyle.pop_scale(chip, 0.5, 0.35, 0.05)
	var sc := LazerStyle.label("ベーススコア ×%.4f" % p.score_mul, 14, LazerStyle.TEXT_DIM)
	_mod_bar.add_child(sc)


# --- ランダム・開始 ---

func _random_song() -> void:
	if _was_chart:   # 難易度順: 表示している譜面から(いまの譜面以外)
		if _chart_order.size() < 2 or _launching:
			return
		var cur := _chart_index(_chart_sel)
		var to := randi() % _chart_order.size()
		if to == cur:
			to = (to + 1) % _chart_order.size()
		var c: Dictionary = _chart_order[to]
		_pick_chart(int(c.s), str(c.id), false)
		_scroll_to_chart(str(c.key))
		return
	var v := browser.view()
	v.erase(_song_sel)   # いまの曲以外の、表示している曲から選ぶ
	if v.is_empty() or _launching:
		return
	_select_song(v[randi() % v.size()])


func _start() -> void:
	if not browser.can_start() or _launching:   # 曲を読み込み中は、まだ始められない(選び直した曲の難易度が出るまで)
		return
	browser.remember_selection()
	UiSfx.play("confirm")
	# 発進: すぐには切り替えず、選んだ曲の行が前に出て、ほかが退き、背景がズームインして、曲が小さくなる(0.4 秒)。それから次の画面へ
	_launching = true
	_launch_anim()
	if UiStyle.animate:
		await get_tree().create_timer(LAUNCH_TIME).timeout
		if not is_inside_tree():
			return
	_audio.stop()
	var info := browser.launch_info()
	if pick_mode:
		song_picked.emit(info.loader, info.bm, settings, info.level)
		return
	play_requested.emit(info.loader, info.bm, settings, info.pre)


## 発進の演出。選んだ曲の行と情報だけを残して、ほかをなめらかに退かせる。
func _launch_anim() -> void:
	if not UiStyle.animate:
		return
	for c in [_stats, _toolbar, _footer]:
		var t: Tween = c.create_tween()
		t.tween_property(c, "modulate:a", 0.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	for i in range(_rows.size()):
		if i == _song_sel:
			continue
		var t2: Tween = _rows[i].create_tween()
		t2.tween_property(_rows[i], "modulate:a", 0.0, 0.25)
	for hk in _chart_holders.keys():   # 難易度順: 選んでいる譜面の行以外を退かせる
		if hk != _chart_sel and is_instance_valid(_chart_holders[hk]) and (_chart_holders[hk] as Control).visible:
			var t3: Tween = (_chart_holders[hk] as Control).create_tween()
			t3.tween_property(_chart_holders[hk], "modulate:a", 0.0, 0.25)
	if _was_chart and _chart_holders.has(_chart_sel):
		var chold: Control = (_chart_holders[_chart_sel] as Control).get_meta("card")
		chold.pivot_offset = chold.size * 0.5
		UiStyle.spring(chold, "scale", Vector2.ONE, Vector2(1.03, 1.03), 0.3)
	elif _song_sel >= 0 and _song_sel < _song_cards.size():
		var holder: Control = _song_cards[_song_sel]
		holder.pivot_offset = holder.size * 0.5
		UiStyle.spring(holder, "scale", Vector2.ONE, Vector2(1.03, 1.03), 0.3)
	if _play_btn != null:
		var at := _play_btn.get_global_rect().get_center()
		UiFx.ring(self, at, LazerStyle.PINK, 20.0, 200.0, 0.5, 3.0)
		UiFx.burst(self, at, LazerStyle.PINK, 14, 260.0, 0.55, 3.0)
	if _drift != null and _drift.is_valid():
		_drift.kill()
	var tz := _bg_holder.create_tween()
	tz.tween_property(_bg_holder, "scale", Vector2(1.16, 1.16), LAUNCH_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	var ta := _audio.create_tween()
	ta.tween_property(_audio, "volume_db", -40.0, LAUNCH_TIME)


# --- パネル ---

## 設定を開く(パネルは main が持つ。どの画面でも開ける)。
func open_options(section := 0) -> void:
	settings_requested.emit(section)


## main が設定パネルを開いた・閉じた(ui_set.gd の契約)。開いている間は、キーも MOD パネルも受け付けない
func on_overlay(open: bool, panel: Control = null) -> void:
	_options = panel if open else null


## MOD パネルを開く(下からせり上がる lazer 風のシート)。
func open_mods() -> void:
	if _mod_panel != null or _options != null or _launching:
		return
	var p := ModPanel.new()
	p.multi = pick_mode
	p.setup(settings, _mod_level)
	p.changed.connect(_on_mods_changed)
	p.closed.connect(_close_mods)
	_mod_panel = p
	add_child(p)


func _on_mods_changed() -> void:
	_refresh_mod_bar()
	if _loader == null:
		return
	if browser.needs_style_reload():   # 弾幕 v2 の入り切り: 弾幕そのものが変わるので、曲を読み直す(終わったら難易度も出る)
		browser.reload_for_style()
		return
	_rate_all()
	_refresh_mod_bar()
	_fill_diffs()
	_update_detail()
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
	return browser.selected_level()


## 「弾幕 v2 で遊ぼう」を押した: MOD「弾幕 v2」を付ける(曲を読み直す)。
func _enable_v2() -> void:
	if _launching or _mod_panel != null or _options != null:
		return
	var ids: Array = settings.mods.duplicate()
	if not ids.has("v2"):
		ids.append("v2")
	settings.mods = ids
	Settings.save_all(settings)
	_on_mods_changed()


## 曲の一覧がホイールを受け付けるか(MOD パネルや設定パネルが上に重なっているときは、受け付けない)。
func _lists_active() -> bool:
	return _mod_panel == null and _options == null


func _input(event: InputEvent) -> void:
	if _options != null or _mod_panel != null or _launching:
		return
	if event is InputEventMouseButton and event.pressed and _search.has_focus() and not _search.get_global_rect().has_point(event.global_position):
		_search.release_focus()   # 入力欄の外をクリックしたら、入力を終える(矢印キーなどが、また曲の選択に使える)
	if not (event is InputEventKey and event.pressed):
		return
	if _search.has_focus():   # 入力中は、文字のキーを入力欄に任せる。Esc で閉じて(文字があれば消して)、Enter・↓ で、表示している先頭の曲へ
		match event.keycode:
			KEY_ESCAPE:
				if _search.text != "":
					_search.text = ""
					browser.query = ""
					_apply_view()
				_search.release_focus()
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER, KEY_DOWN:
				_search.release_focus()
				if _was_chart:   # 難易度順: 選んでいる譜面が一覧になければ、表示している先頭の譜面へ
					if not _chart_order.is_empty() and _chart_index(_chart_sel) < 0:
						var c0: Dictionary = _chart_order[0]
						_pick_chart(int(c0.s), str(c0.id), false)
						_scroll_to_chart(str(c0.key))
				else:
					var first := browser.step_in_view(_song_sel, 0)
					if first >= 0 and first != _song_sel:
						_select_song(first)
				get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_UP, KEY_DOWN:   # 曲(表示している曲の中で)
			if not event.echo:   # 曲の切替は重い(難易度の再計算)ので、押しっぱなしでは進めない
				if _was_chart:   # 難易度順: 1 譜面ずつ
					_step_chart(-1 if event.keycode == KEY_UP else 1)
				else:
					var to := browser.step_in_view(_song_sel, -1 if event.keycode == KEY_UP else 1)
					if to >= 0:
						_select_song(to)
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
				_go_back()
			get_viewport().set_input_as_handled()
		KEY_SLASH:   # 曲の検索へ
			if not event.echo:
				_search.grab_focus()
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

## 曲が 1 つもない状態にする(案内を確かめる)。
func debug_empty() -> void:
	while _job_pending:
		await get_tree().process_frame
	_songs.clear()
	_song_sel = -1
	_diff_sel = -1
	_loader = null
	_gens = []
	_ratings = []
	_rebuild_song_cards(false)
	_title_l.text = ""
	_artist_l.text = ""
	_meta_l.text = ""
	_lv_holder_clear()
	_stat_rows = []
	_stat_note = ""
	_stats.queue_redraw()
	_set_loading(false)


## 曲の読み込み中の見た目にする。
func debug_loading() -> void:
	while _job_pending:
		await get_tree().process_frame
	_set_loading(true)
	_meta_l.text = "読み込み中…"


## MOD を指定して付けた状態にする。
func debug_set_mods(ids: Array) -> void:
	settings.mods = ids
	browser.debug_regen()
	if _loader != null:
		_rate_all()
		_fill_diffs()
		_update_detail()
	_refresh_mod_bar()


## 検索の文字を入れた状態にする。
func debug_search(text: String) -> void:
	_search.text = text
	browser.query = text
	_apply_view()


## 並び替えを指定する(曲名 / アーティスト / 追加順)。
func debug_sort(mode: String) -> void:
	browser.sort_mode = mode
	for k in range(_sort_btns.size()):
		_sort_btns[k].set_pressed_no_signal(SongBrowser.SORT_MODES[k][0] == mode)
	_apply_view(true)


## 作り物の記録を出す(保存しない。見た目の確認用)。
func debug_records() -> void:
	var now := int(Time.get_unix_time_from_system())
	_rec_rows = [
		{"rank": "SS", "score": 1013000, "mods": ["rush"], "t": now},
		{"rank": "S", "score": 981420, "mods": [], "t": now - 86400},
		{"rank": "A", "score": 903120, "mods": ["dark", "shrink"], "t": now - 86400 * 3},
		{"rank": "B", "score": 812300, "mods": [], "t": now - 86400 * 9},
	]
	_rec_card.queue_redraw()
