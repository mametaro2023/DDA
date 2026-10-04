extends Control
## 上のツールバーの、いま流れている曲のプレイヤー(時計の左)。前の曲 / 再生・一時停止 / 次の曲、曲名 - アーティスト(長いときは流れる)、曲の進み具合の細い線。
## 流れている曲は NowPlaying が持つ(画面が申告する)。曲がないときは「再生なし」と出して、ボタンは暗くなる。

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerMarquee = preload("res://scripts/ui/lazer/lazer_marquee.gd")
const NowPlaying = preload("res://scripts/ui/lazer/now_playing.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")

const W := 300.0
const H := 40.0
const BTN_X := [18.0, 46.0, 74.0]   # 前・再生/一時停止・次の中心
const BTN_R := 13.0
const TEXT_X := 98.0

var _marquee
var _hover := -1
var _rev := -1
var _was_playing := false


func _init() -> void:
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_marquee = LazerMarquee.new(13, LazerStyle.TEXT_DIM)
	_marquee.position = Vector2(TEXT_X, 10)
	_marquee.size = Vector2(W - TEXT_X - 8.0, 20)
	add_child(_marquee)


func _process(_delta: float) -> void:
	if NowPlaying.rev != _rev:
		_rev = NowPlaying.rev
		var t := "再生なし"
		if NowPlaying.player != null and NowPlaying.title != "":
			t = NowPlaying.title if NowPlaying.artist == "" else "%s - %s" % [NowPlaying.title, NowPlaying.artist]
		_marquee.text = t
		_marquee.modulate.a = 1.0 if NowPlaying.is_set() else 0.5
		queue_redraw()
	var playing := NowPlaying.is_playing()
	if playing or playing != _was_playing:
		_was_playing = playing
		queue_redraw()


func _enabled(i: int) -> bool:
	if not NowPlaying.is_set():
		return false
	match i:
		0:
			return NowPlaying.on_prev.is_valid()
		2:
			return NowPlaying.on_next.is_valid()
	return true


func _button_at(p: Vector2) -> int:
	for i in range(3):
		if p.distance_to(Vector2(BTN_X[i], H * 0.5)) <= BTN_R:
			return i
	return -1


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var h := _button_at(ev.position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var i := _button_at(ev.position)
		if i < 0 or not _enabled(i):
			return
		UiSfx.play("click")
		match i:
			0:
				NowPlaying.player.stream_paused = false
				NowPlaying.on_prev.call()
			1:
				NowPlaying.toggle()
			2:
				NowPlaying.player.stream_paused = false
				NowPlaying.on_next.call()
		queue_redraw()
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
		_hover = -1
		queue_redraw()


func _draw() -> void:
	var cy := H * 0.5
	for i in range(3):
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
	# 曲の進み具合(文字の下の細い線)
	if NowPlaying.is_set():
		var bx := TEXT_X
		var bw := W - TEXT_X - 8.0
		draw_rect(Rect2(bx, H - 6.0, bw, 2.0), Color(1, 1, 1, 0.12))
		draw_rect(Rect2(bx, H - 6.0, bw * NowPlaying.progress(), 2.0), LazerStyle.PINK)
