extends "res://scripts/ui/lazer/lazer_screen.gd"
## lazer 風のタイトル画面。左に DDA のロゴ、右に横に並ぶ 5 つのボタン(プレイ / マルチプレイ / 遊び方 / 設定 / 終了)。
## 背景は、ランダムに選んだ曲の画像(暗く)で、その曲を流しておく(曲が終わったら、別のランダムな曲へ)。遊び方と設定は、この画面の上に重ねるパネル(曲は流れ続ける)。
## 契約は classic のタイトル(title_screen.gd)と同じ: signal play_requested / multi_requested / update_requested / settings_requested、
## update_info / show_update() / can_accept_auto_update() / open_panel()。
## 操作: ← → ↑ ↓ で選び、Enter で決める。Esc で終了の確認(キーの案内は画面に出さない。「遊び方」にある)。

signal play_requested
signal multi_requested
signal update_requested

const AttractBackdrop = preload("res://scripts/attract_backdrop.gd")
const HowToPanel = preload("res://scripts/ui/lazer/lazer_howto.gd")
const QuitPanel = preload("res://scripts/ui/lazer/lazer_quit.gd")
const LazerLogo = preload("res://scripts/ui/lazer/lazer_logo.gd")
const Volume = preload("res://scripts/volume.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const NowPlaying = preload("res://scripts/ui/lazer/now_playing.gd")
const UiFx = preload("res://scripts/ui/ui_fx.gd")
const Settings = preload("res://scripts/settings.gd")

const MUSIC_DB := -4.0
## 項目の名前・アイコン・色・文字色
const ITEMS := [
	["プレイ", "play", LazerStyle.PINK, Color(0.2, 0.04, 0.11)],
	["マルチプレイ", "users", LazerStyle.PURPLE, Color(0.1, 0.04, 0.22)],
	["遊び方", "search", LazerStyle.BLUE, Color(0.03, 0.12, 0.2)],
	["設定", "gear", Color(0.3, 0.28, 0.38), LazerStyle.TEXT],
	["終了", "power", LazerStyle.RED, Color(0.2, 0.03, 0.06)],
]
const PITCHES := [1.0, 1.122, 1.26, 1.5, 1.68]   # 項目ごとの選択音の高さ(選ぶたびに音階のように聞こえる)
const LOGO_C := Vector2(310, 360)
const STRIP_Y := 300.0
const STRIP_H := 120.0
const BTN_X := 480.0
const BTN_W := 156.0
const BTN_STEP := 142.0

var kind := "title"
var update_info: Dictionary = {}   # 新しいバージョンがあるとき、main が渡す(あとから見つかった場合は show_update)
var _sel := 0
var _cards: Array = []             # 項目のボタン
var _logo: Control
var _audio: AudioStreamPlayer
var _last_path := ""
var _overlay: Control              # 開いているパネル(遊び方 / 終了の確認)
var _leaving := false
var _update_btn: Button
var _ver_l: Label


func _ready() -> void:
	settings = Settings.load_all()
	_build_base()
	_build_toolbar(["ホーム"])
	# ロゴと、右に伸びる帯(その上にボタンが並ぶ)
	var strip := ColorRect.new()
	strip.color = Color(0.03, 0.025, 0.06, 0.55)
	_place(strip, LOGO_C.x, STRIP_Y, 1280.0 - LOGO_C.x, STRIP_H)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo = LazerLogo.new(380.0)
	_logo.position = LOGO_C - _logo.size * 0.5
	add_child(_logo)
	_logo.pressed.connect(func(): _activate(0))
	for i in range(ITEMS.size()):
		var it: Array = ITEMS[i]
		var b := LazerButton.new(it[0], it[2], it[1], it[3])
		b.stacked = true
		b.font_size = 18
		b.slant = 16.0
		b.position = Vector2(BTN_X + i * BTN_STEP, STRIP_Y + 8.0)
		b.size = Vector2(BTN_W, STRIP_H - 16.0)
		b.mouse_entered.connect(func(): _select(i))
		b.pressed.connect(func(): _activate(i))
		if i == 4:
			b.set_meta("juice_sound", "back")
		add_child(b)
		_cards.append(b)
	_restyle(false)
	_ver_l = LazerStyle.label("Danmaku      BETA v%s" % _version(), 14, LazerStyle.TEXT_MUTE)
	_ver_l.position = Vector2(28, 720 - 38)
	add_child(_ver_l)
	# 入場: ロゴが弾んで現れ、ボタンが順に右から滑り込む
	if UiStyle.animate:
		_logo.scale = Vector2(0.55, 0.55)
		_logo.modulate.a = 0.0
		UiStyle.spring(_logo, "scale", Vector2(0.55, 0.55), Vector2.ONE, 0.7, 0.05)
		UiStyle.tween(_logo, "modulate:a", 0.0, 1.0, 0.35, 0.05)
		for i in range(_cards.size()):
			UiStyle.pop_in(_cards[i], 0.3 + 0.07 * i, Vector2(60, 0), 0.5)
		UiStyle.pop_in(_ver_l, 0.4, Vector2(-30, 0), 0.6)
	# 背景と曲は、最初の画面を出してから読み込む(読み込みで最初のフレームが遅れないように)
	_audio = AudioStreamPlayer.new()
	Volume.route_music(_audio)   # 音楽バスへ(ホイールなどの「音楽」の音量が効く)
	_audio.volume_db = -40.0
	_audio.finished.connect(_play_random)
	add_child(_audio)
	_play_random.call_deferred()
	if bool(update_info.get("newer", false)):
		show_update(update_info)


func _version() -> String:
	var v := str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	return v.replace("-beta", "")


## 新しいバージョンの案内(版の表示の下)。押すと、アップデートのパネルが開く。
func show_update(info: Dictionary) -> void:
	if _update_btn != null:
		return
	_update_btn = Button.new()
	_update_btn.text = "新しいバージョン v%s があります  ▶" % str(info.get("version", "?"))
	_update_btn.focus_mode = Control.FOCUS_NONE
	_update_btn.add_theme_stylebox_override("normal", LazerStyle.box(Color(LazerStyle.PINK.r, LazerStyle.PINK.g, LazerStyle.PINK.b, 0.2), LazerStyle.PINK, 1, 14, 14, 5))
	_update_btn.add_theme_stylebox_override("hover", LazerStyle.box(Color(LazerStyle.PINK.r, LazerStyle.PINK.g, LazerStyle.PINK.b, 0.4), LazerStyle.PINK, 1, 14, 14, 5))
	_update_btn.add_theme_color_override("font_color", LazerStyle.PINK)
	_update_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	_update_btn.add_theme_font_override("font", LazerStyle.font_bold())
	_update_btn.add_theme_font_size_override("font_size", 14)
	_update_btn.position = Vector2(28, 720 - 74)
	_update_btn.pressed.connect(func():
		if _overlay == null and not _leaving:
			update_requested.emit())
	add_child(_update_btn)
	UiStyle.pop_in(_update_btn, 0.35, Vector2(-30, 0), 0.5)


## 自動更新のパネルを、いま開いてよいか(別のパネルが開いている・画面を離れ始めているときは、だめ)
func can_accept_auto_update() -> bool:
	return _overlay == null and not _leaving


## パネル(遊び方・更新・終了の確認など)を重ねて開く。閉じるのはパネルの closed(ui_set.gd の契約)
func open_panel(panel: Control) -> void:
	_open(panel)


func _open(panel: Control) -> void:
	_overlay = panel
	panel.closed.connect(_close_overlay)
	add_child(panel)
	if panel.has_method("show_section"):
		panel.show_section(0)


func _close_overlay() -> void:
	if _overlay == null:
		return
	_overlay.queue_free()
	_overlay = null


# --- ランダムな曲 ---

var _picking := false   # 曲を別スレッドで読み込んでいる途中


## ランダムな曲(と、その中のランダムな譜面)を選んで、背景にして流す。直前と同じ曲は避ける。
func _play_random() -> void:
	if _leaving:
		return
	if _picking:
		return
	if not UiStyle.animate:   # 撮影など(動きなし)は、その場で読み込む(撮る前に背景がそろう)
		_on_picked(AttractBackdrop.new().pick(_last_path))
		return
	_picking = true
	AttractBackdrop.pick_async(_last_path, _on_picked)   # 選び方は scripts/attract_backdrop.gd(classic のタイトルと共通)。読み込みは別スレッド


func _on_picked(pick: Dictionary) -> void:
	_picking = false
	if pick.is_empty() or _leaving or not is_inside_tree():
		return
	_last_path = pick.path
	set_background(pick.tex)
	_audio.stream = pick.stream
	_audio.volume_db = -40.0
	var start: float = pick.start
	NowPlaying.set_track(_audio, str(pick.get("title", "")), str(pick.get("artist", "")), start, func(): _audio.seek(start), _play_random)   # 上のプレイヤー: 前 = 頭から聴き直す・次 = 別のランダムな曲
	_audio.play(start)
	UiStyle.tween(_audio, "volume_db", -40.0, MUSIC_DB, 1.6)   # 曲は、ふわっと入る


func _exit_tree() -> void:
	NowPlaying.clear(_audio)


## 曲を小さくして止める。
func _fade_music(dur: float) -> void:
	if _audio == null or not _audio.playing:
		return
	if not UiStyle.animate:
		_audio.stop()
		return
	var t := _audio.create_tween()
	t.tween_property(_audio, "volume_db", -50.0, dur)
	t.tween_callback(_audio.stop)


# --- 項目の選択 ---

func _select(i: int) -> void:
	if i == _sel or _overlay != null or _leaving:
		return
	_sel = i
	UiSfx.play("select", PITCHES[i])
	_restyle(true)


## 選んでいる項目は、上下へ少し伸びて明るくなる。
func _restyle(animated: bool) -> void:
	for i in range(_cards.size()):
		var b: Control = _cards[i]
		var sel := i == _sel
		(b as LazerButton).emphasized = sel
		b.queue_redraw()
		var to_y := STRIP_Y - 6.0 if sel else STRIP_Y + 8.0
		var to_h := STRIP_H + 12.0 if sel else STRIP_H - 16.0
		if not animated or not UiStyle.animate or not is_inside_tree():
			b.position.y = to_y
			b.size.y = to_h
			continue
		var t := b.create_tween().set_parallel(true)
		t.tween_property(b, "position:y", to_y, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(b, "size:y", to_h, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _activate(i: int) -> void:
	if _overlay != null or _leaving:
		return
	if i != _sel:
		_sel = i
		_restyle(true)
	match i:
		0, 1:
			UiSfx.play("confirm")
			_leaving = true
			_fade_music(0.35)
			var at := (_cards[i] as Control).get_global_rect().get_center()
			UiFx.ring(self, at, LazerStyle.PINK, 20.0, 160.0, 0.5, 2.5)
			UiFx.burst(self, at, LazerStyle.PINK, 14, 240.0, 0.55, 3.0)
			_slide_out()
			if UiStyle.animate:
				await get_tree().create_timer(0.3).timeout
			(play_requested if i == 0 else multi_requested).emit()
		2:
			UiSfx.play("open")
			_open(HowToPanel.new())
		3:
			UiSfx.play("open")
			settings_requested.emit(0)   # 設定パネルは main が持つ(どの画面でも開ける)
		4:
			var q := QuitPanel.new()
			q.confirmed.connect(func(): get_tree().quit())
			_open(q)


## 画面を出るとき、ボタンが右へ順に流れ出て、ロゴが小さくなる。
func _slide_out() -> void:
	if not UiStyle.animate:
		return
	for k in range(_cards.size()):
		var c: Control = _cards[k]
		var t := c.create_tween().set_parallel(true)
		t.tween_property(c, "modulate:a", 0.0, 0.2).set_delay(0.03 * k)
		t.tween_property(c, "position:x", c.position.x + 50.0, 0.22).set_delay(0.03 * k).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	var tl := _logo.create_tween().set_parallel(true)
	tl.tween_property(_logo, "modulate:a", 0.0, 0.25)
	tl.tween_property(_logo, "position:x", _logo.position.x - 40.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


func _input(event: InputEvent) -> void:
	if _overlay != null or _leaving or not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_UP, KEY_LEFT:
			_select(posmod(_sel - 1, ITEMS.size()))
			get_viewport().set_input_as_handled()
		KEY_DOWN, KEY_RIGHT:
			_select(posmod(_sel + 1, ITEMS.size()))
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			if not event.echo:
				_activate(_sel)
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if not event.echo:
				_activate(ITEMS.size() - 1)   # 終了の確認
			get_viewport().set_input_as_handled()
