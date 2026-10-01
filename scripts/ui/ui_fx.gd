extends Node2D
## 一度だけ動いて消える小さな演出(広がる輪 / 弾ける粒)。クリックの波紋・ランクのスタンプ・トグルの弾けなどで共有する。
## 点滅はなく、広がりながら薄れるだけ。UiStyle.animate が false のときは何も出さない(スクリーンショット用)。
## 使い方: UiFx.ring(親, 位置, 色) / UiFx.burst(親, 位置, 色)。親の座標系で描く(CanvasLayer の下の Control や Node2D)。

const UiStyle = preload("res://scripts/ui/ui_style.gd")

var _kind := "ring"
var _t := 0.0
var _dur := 0.5
var _color := Color.WHITE
# ring
var _r0 := 8.0
var _r1 := 60.0
var _width := 2.0
# burst
var _parts: Array = []   # [pos, vel, size]
var _drag := 3.0
var _gravity := 0.0


## 広がる輪。r0 → r1 へ ease-out で広がり、細く薄くなって消える。
static func ring(parent: Node, pos: Vector2, color: Color, r0 := 8.0, r1 := 64.0, dur := 0.5, width := 2.5) -> void:
	if not UiStyle.animate or parent == null or not parent.is_inside_tree():
		return
	var f := new()
	f._kind = "ring"
	f.position = pos
	f._color = color
	f._r0 = r0
	f._r1 = r1
	f._dur = dur
	f._width = width
	parent.add_child(f)


## 弾ける粒。count 個が放射状に飛び、減速しながら小さく薄くなって消える。
static func burst(parent: Node, pos: Vector2, color: Color, count := 12, speed := 170.0, dur := 0.6, size := 3.0, gravity := 0.0, drag := 2.2) -> void:
	if not UiStyle.animate or parent == null or not parent.is_inside_tree():
		return
	var f := new()
	f._kind = "burst"
	f.position = pos
	f._color = color
	f._dur = dur
	f._gravity = gravity
	f._drag = drag
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var a0 := rng.randf() * TAU
	for i in range(count):
		var a := a0 + TAU * float(i) / count + rng.randf_range(-0.25, 0.25)
		var v := Vector2.from_angle(a) * speed * rng.randf_range(0.55, 1.15)
		f._parts.append([Vector2.ZERO, v, size * rng.randf_range(0.6, 1.3)])
	parent.add_child(f)


func _process(delta: float) -> void:
	_t += delta
	if _t >= _dur:
		queue_free()
		return
	if _kind == "burst":
		var k := exp(-_drag * delta)
		for p in _parts:
			p[0] += p[1] * delta
			p[1] = p[1] * k + Vector2(0, _gravity) * delta
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / _dur, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)   # ease-out
	if _kind == "ring":
		var c := Color(_color.r, _color.g, _color.b, _color.a * (1.0 - k) * (1.0 - k))
		draw_arc(Vector2.ZERO, lerpf(_r0, _r1, e), 0.0, TAU, 48, c, maxf(_width * (1.0 - k), 0.5), true)
	else:
		var fade := 1.0 - k
		for p in _parts:
			var c := Color(_color.r, _color.g, _color.b, _color.a * fade)
			draw_circle(p[0], maxf(p[2] * fade, 0.4), c)
