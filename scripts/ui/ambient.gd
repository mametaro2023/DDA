extends Node2D
## 背景でゆっくり漂う、弾のようなリング(動きだけの演出。点滅・明滅はしない)。
## 位置と色は決め打ちの乱数(毎回同じ配置)。画面外に出たら反対側から戻ってくる。

const AREA := Vector2(1280, 720)
const COLORS := [Color(0.42, 0.95, 1.0), Color(1.0, 0.5, 0.75), Color(0.7, 0.55, 1.0), Color(0.55, 1.0, 0.7)]

var count := 36
var strength := 1.0   # 見えやすさ(1 = 通常)
var _dots: Array = []


func _ready() -> void:
	z_index = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240607
	for i in range(count):
		_dots.append({
			"pos": Vector2(rng.randf_range(0.0, AREA.x), rng.randf_range(0.0, AREA.y)),
			"vel": Vector2(rng.randf_range(-9.0, 9.0), rng.randf_range(8.0, 30.0)),
			"r": rng.randf_range(3.0, 10.0),
			"col": COLORS[rng.randi() % COLORS.size()],
			"a": rng.randf_range(0.07, 0.2),
			"fill": rng.randf() < 0.35,
		})


func _process(delta: float) -> void:
	for d in _dots:
		var p: Vector2 = d.pos + d.vel * delta
		if p.y > AREA.y + 24.0:
			p.y = -24.0
		if p.x < -24.0:
			p.x = AREA.x + 24.0
		elif p.x > AREA.x + 24.0:
			p.x = -24.0
		d.pos = p
	queue_redraw()


func _draw() -> void:
	for d in _dots:
		var c: Color = d.col
		var a: float = d.a * strength
		draw_arc(d.pos, d.r, 0.0, TAU, 20, Color(c.r, c.g, c.b, a), 1.5, true)
		if d.fill:
			draw_circle(d.pos, d.r * 0.45, Color(c.r, c.g, c.b, a * 0.8))
