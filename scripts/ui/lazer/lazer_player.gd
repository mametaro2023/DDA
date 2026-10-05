extends Control
## 上のツールバーの、いま流れている曲のプレイヤー(時計の左)。前の曲 / 再生・一時停止 / 次の曲 / プレイリスト、曲名 - アーティスト(長いときは流れる)、曲の進み具合の線。
## 進み具合の線は、押す・ドラッグで好きな位置へ飛べる(線の上では、曲名の代わりに、飛ぶ先の時刻が出る)。
## 流れている曲は NowPlaying が持つ(画面が申告する)。曲がないときは「再生なし」と出して、ボタンは暗くなる。
## プレイリストのボタンは、プレイリストのパネル(main が開く)を開く。プレイリストを流している間は、ピンクに光る。

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerMarquee = preload("res://scripts/ui/lazer/lazer_marquee.gd")
const LazerIcons = preload("res://scripts/ui/lazer/lazer_icons.gd")
const NowPlaying = preload("res://scripts/ui/lazer/now_playing.gd")
const Playlist = preload("res://scripts/playlist.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")

const W := 332.0
const H := 40.0
const BTN_X := [18.0, 46.0, 74.0, 106.0]   # 前・再生/一時停止・次・プレイリストの中心
const BTN_R := 13.0
const TEXT_X := 128.0
const BAR_Y := H - 7.0
const HOLD_SEC := 0.3   # 飛んだ直後、再生位置が追いつくまで、飛んだ先の位置を出しておく(線が一瞬戻らないように)

var _marquee
var _hover := -1
var _rev := -1
var _was_playing := false
var _bar_hover := false
var _scrub := false
var _scrub_f := 0.0     # ドラッグ中の位置(0..1)
var _hover_f := 0.0     # 線の上のマウスの位置(0..1)
var _hold_f := -1.0
var _hold_t := 0.0
var _hot := 0.0         # 線を操作している度合い(0..1。なめらかに出入りする)
var _list_rev := -1


func _init() -> void:
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_marquee = LazerMarquee.new(13, LazerStyle.TEXT_DIM)
	_marquee.position = Vector2(TEXT_X, 10)
	_marquee.size = Vector2(W - TEXT_X - 8.0, 20)
	add_child(_marquee)


func _process(delta: float) -> void:
	if NowPlaying.rev != _rev:
		_rev = NowPlaying.rev
		var t := "再生なし"
		if NowPlaying.player != null and NowPlaying.title != "":
			t = NowPlaying.title if NowPlaying.artist == "" else "%s - %s" % [NowPlaying.title, NowPlaying.artist]
		_marquee.text = t
		queue_redraw()
	if Playlist.state_rev != _list_rev:
		_list_rev = Playlist.state_rev
		queue_redraw()
	var want := 1.0 if (_scrub or _bar_hover) and _bar_enabled() else 0.0
	var k := move_toward(_hot, want, delta * 8.0)
	if k != _hot:
		_hot = k
	_marquee.modulate.a = (1.0 if NowPlaying.is_set() else 0.5) * (1.0 - _hot)
	if _hold_f >= 0.0:
		_hold_t -= delta
		if _hold_t <= 0.0:
			_hold_f = -1.0
	var playing := NowPlaying.is_playing()
	if playing or playing != _was_playing or _hot > 0.0 or _scrub or _hold_f >= 0.0:
		_was_playing = playing
		queue_redraw()


func _enabled(i: int) -> bool:
	match i:
		0:
			return NowPlaying.can_step(-1)
		1:
			return NowPlaying.is_set()
		2:
			return NowPlaying.can_step(1)
	return NowPlaying.on_open_playlist.is_valid()


func _bar_enabled() -> bool:
	return NowPlaying.is_set() and NowPlaying.length() > 0.0


func _button_at(p: Vector2) -> int:
	for i in range(BTN_X.size()):
		if p.distance_to(Vector2(BTN_X[i], H * 0.5)) <= BTN_R:
			return i
	return -1


## 線の押せる範囲(線のまわり。細い線を狙わなくてよいように、上下に広げる)
func _bar_rect() -> Rect2:
	return Rect2(TEXT_X - 4.0, H - 17.0, W - TEXT_X - 8.0 + 8.0, 17.0)


func _frac_at(x: float) -> float:
	return clampf((x - TEXT_X) / (W - TEXT_X - 8.0), 0.0, 1.0)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var h := _button_at(ev.position)
		if h != _hover:
			_hover = h
			queue_redraw()
		var over := _bar_rect().has_point(ev.position) and h < 0
		if over != _bar_hover:
			_bar_hover = over
			queue_redraw()
		_hover_f = _frac_at(ev.position.x)
		if _scrub:
			_scrub_f = _hover_f
			accept_event()
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			var i := _button_at(ev.position)
			if i >= 0:
				if not _enabled(i):
					return
				UiSfx.play("click")
				match i:
					0:
						NowPlaying.player.stream_paused = false
						NowPlaying.step(-1)
					1:
						NowPlaying.toggle()
					2:
						NowPlaying.player.stream_paused = false
						NowPlaying.step(1)
					3:
						NowPlaying.on_open_playlist.call()
				queue_redraw()
				accept_event()
			elif _bar_rect().has_point(ev.position) and _bar_enabled():
				_scrub = true
				_scrub_f = _frac_at(ev.position.x)
				accept_event()
		elif _scrub:   # 離した: そこへ飛ぶ(ドラッグの間は、飛ばさず、位置だけ動かす = 飛ぶたびの音の乱れを避ける)
			_scrub = false
			if _bar_enabled():
				NowPlaying.seek_to(_scrub_f)
				_hold_f = _scrub_f
				_hold_t = HOLD_SEC
				UiSfx.play("click")
			accept_event()
			queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		if _hover != -1 or _bar_hover:
			_hover = -1
			_bar_hover = false
			queue_redraw()


func _draw() -> void:
	var cy := H * 0.5
	for i in range(BTN_X.size()):
		var on := _enabled(i)
		var c := LazerStyle.TEXT_DIM if on else Color(1, 1, 1, 0.22)
		if on and i == _hover:
			draw_circle(Vector2(BTN_X[i], cy), BTN_R, Color(1, 1, 1, 0.12))
			c = LazerStyle.TEXT
		var x: float = BTN_X[i]
		match i:
			0:   # 前の曲(棒 + 左向きの三角)
				draw_rect(Rect2(x - 5.0, cy - 5.0, 2.0, 10.0), c)
				draw_colored_polygon(PackedVector2Array([Vector2(x + 5.0, cy - 5.5), Vector2(x + 5.0, cy + 5.5), Vector2(x - 2.0, cy)]), c)
			1:
				if NowPlaying.is_playing():   # 一時停止の印(縦の 2 本)
					draw_rect(Rect2(x - 4.5, cy - 5.5, 3.0, 11.0), LazerStyle.PINK if on else c)
					draw_rect(Rect2(x + 1.5, cy - 5.5, 3.0, 11.0), LazerStyle.PINK if on else c)
				else:   # 再生の印
					draw_colored_polygon(PackedVector2Array([Vector2(x - 4.0, cy - 6.5), Vector2(x - 4.0, cy + 6.5), Vector2(x + 6.0, cy)]), LazerStyle.PINK if on else c)
			2:   # 次の曲(右向きの三角 + 棒)
				draw_rect(Rect2(x + 3.0, cy - 5.0, 2.0, 10.0), c)
				draw_colored_polygon(PackedVector2Array([Vector2(x - 5.0, cy - 5.5), Vector2(x - 5.0, cy + 5.5), Vector2(x + 2.0, cy)]), c)
			3:   # プレイリスト(流している間は、ピンク)
				var lc := LazerStyle.PINK if Playlist.is_active() else c
				LazerIcons.draw_icon(self, "list", Vector2(x, cy), 7.0, lc, 1.6)
	# 区切り(ボタンと曲名の間)
	draw_line(Vector2(TEXT_X - 10.0, 11.0), Vector2(TEXT_X - 10.0, H - 11.0), Color(1, 1, 1, 0.10), 1.0)
	if not NowPlaying.is_set():
		return
	# 曲の進み具合(文字の下の線)。操作中は太くなり、飛ぶ先の時刻が曲名の代わりに出る
	var bx := TEXT_X
	var bw := W - TEXT_X - 8.0
	var f := NowPlaying.progress()
	if _hold_f >= 0.0:
		f = _hold_f
	if _scrub:
		f = _scrub_f
	var th := 2.0 + 2.0 * _hot
	draw_rect(Rect2(bx, BAR_Y - th * 0.5 + 1.0, bw, th), Color(1, 1, 1, 0.12 + 0.06 * _hot))
	draw_rect(Rect2(bx, BAR_Y - th * 0.5 + 1.0, bw * f, th), LazerStyle.PINK)
	if _hot > 0.01:
		draw_circle(Vector2(bx + bw * f, BAR_Y + 1.0), 4.0 * _hot, Color(1, 1, 1, 0.95))
		var target := _scrub_f if _scrub else _hover_f
		var total := NowPlaying.length()
		var txt := "%s / %s" % [NowPlaying.fmt(target * total), NowPlaying.fmt(total)]
		var font := LazerStyle.font()
		draw_string(font, Vector2(bx, 19.0), txt, HORIZONTAL_ALIGNMENT_CENTER, bw, 13, Color(LazerStyle.TEXT.r, LazerStyle.TEXT.g, LazerStyle.TEXT.b, _hot))
