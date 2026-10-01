extends CanvasLayer
## 画面の切り替えの幕。斜めに切った幕が左から画面を覆い(cover)、入れ替えたあと、右へ抜けて新しい画面が現れる(reveal)。
## 体力バーの斜めのケースと同じ向きの斜め線で、縁に水色の細い線が走る。点滅はなく、一方向へ動くだけ。
## 使い方: await wipe.cover() → 画面を入れ替える → await wipe.reveal()。

const UiStyle = preload("res://scripts/ui/ui_style.gd")

const SIZE := Vector2(1280, 720)
const SLANT := 240.0          # 斜めの縁の、上端と下端の横のずれ
const COVER_TIME := 0.22
const REVEAL_TIME := 0.3

var _c: Control
var _p := 0.0                 # 覆う側の縁の位置 0..1(0 = 左の外 / 1 = 右の外)
var _q := 0.0                 # 抜ける側の縁の位置 0..1(0 = 左の外 / 1 = 右の外)
var _covering := false


func _ready() -> void:
	layer = 100
	_c = Control.new()
	_c.size = SIZE
	_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_c.draw.connect(_on_draw)
	add_child(_c)
	_set_state(0.0, 0.0)


func _edge(k: float) -> float:
	return lerpf(-SLANT * 0.5, SIZE.x + SLANT * 0.5, k)


func _set_state(p: float, q: float) -> void:
	_p = p
	_q = q
	_c.visible = not (p <= 0.0 or q >= 1.0)
	_c.queue_redraw()


func _slab(x0: float, x1: float, col: Color) -> void:
	# 左の縁 x0・右の縁 x1(どちらも、斜めの縁の真ん中の位置)で挟んだ帯
	var h := SLANT * 0.5
	_c.draw_colored_polygon(PackedVector2Array([
		Vector2(x0 + h, 0), Vector2(x1 + h, 0), Vector2(x1 - h, SIZE.y), Vector2(x0 - h, SIZE.y)]), col)


func _line(x: float, col: Color, w: float) -> void:
	var h := SLANT * 0.5
	_c.draw_line(Vector2(x + h, 0), Vector2(x - h, SIZE.y), col, w, true)


func _on_draw() -> void:
	var a := UiStyle.ACCENT
	var body := Color(0.03, 0.035, 0.06, 1.0)
	var lead := _edge(_p)
	var trail := _edge(_q)
	# 幕の本体(trail から lead まで。まだ抜け始めていなければ、画面の左外から)
	_slab(trail if _q > 0.0 else -SLANT * 2.0, lead, body)
	# 走る縁: 覆うときは先頭、抜けるときは後ろの縁に、水色の細い線と、うっすらした帯
	if _q <= 0.0 and _p < 1.0:
		_slab(lead - 70.0, lead, Color(a.r, a.g, a.b, 0.07))
		_line(lead, Color(a.r, a.g, a.b, 0.85), 2.5)
	elif _q > 0.0 and _q < 1.0:
		_slab(trail, trail + 70.0, Color(a.r, a.g, a.b, 0.07))
		_line(trail, Color(a.r, a.g, a.b, 0.85), 2.5)


## 画面を覆う(終わるまで待てる)。アニメーションなしのときは、すぐ覆う。
func cover(dur := COVER_TIME) -> void:
	_covering = true
	if not UiStyle.animate:
		_set_state(1.0, 0.0)
		return
	_set_state(0.0, 0.0)
	var t := create_tween()
	t.tween_method(func(v: float): _set_state(v, 0.0), 0.0, 1.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await t.finished


## 幕を抜けさせて、画面を見せる。
func reveal(dur := REVEAL_TIME) -> void:
	if not UiStyle.animate:
		_set_state(1.0, 1.0)
		_covering = false
		return
	var t := create_tween()
	t.tween_method(func(v: float): _set_state(1.0, v), 0.0, 1.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await t.finished
	_set_state(0.0, 0.0)
	_covering = false
