extends Control
## lazer 風 UI のアイコン(線画。フォントに頼らず、描画で作る)。Control として置くか、static の draw で CanvasItem に直接描く。
## kind: gear / back / shuffle / search / star / plus / dots / play / folder / clock / user / users / power / retry / download / alert / book / mods / list / x / up / down / repeat / pencil / trash / image / note

var kind := "star"
var col := Color.WHITE
var width := 1.8


func _init(p_kind := "star", p_col := Color.WHITE, p_size := 16.0) -> void:
	kind = p_kind
	col = p_col
	custom_minimum_size = Vector2(p_size, p_size)
	size = Vector2(p_size, p_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_icon(self, kind, size * 0.5, minf(size.x, size.y) * 0.5, col, width)


## ci の c を中心に、半径 r の大きさでアイコンを描く。
static func draw_icon(ci: CanvasItem, k: String, c: Vector2, r: float, col: Color, w := 1.8) -> void:
	match k:
		"gear":
			var pts := PackedVector2Array()
			var teeth := 8
			for i in range(teeth * 4):
				var a := TAU * float(i) / float(teeth * 4)
				var phase := i % 4
				var rr := r if phase == 1 or phase == 2 else r * 0.78
				pts.append(c + Vector2.from_angle(a) * rr)
			pts.append(pts[0])
			ci.draw_polyline(pts, col, w, true)
			ci.draw_arc(c, r * 0.34, 0.0, TAU, 24, col, w, true)
		"back":
			ci.draw_polyline(PackedVector2Array([c + Vector2(r * 0.15, -r * 0.7), c + Vector2(-r * 0.55, 0), c + Vector2(r * 0.15, r * 0.7)]), col, w * 1.15, true)
			ci.draw_line(c + Vector2(-r * 0.55, 0), c + Vector2(r * 0.75, 0), col, w * 1.15, true)
		"shuffle":
			var a0 := c + Vector2(-r * 0.8, -r * 0.4)
			var a1 := c + Vector2(-r * 0.2, -r * 0.4)
			var a2 := c + Vector2(r * 0.2, r * 0.4)
			var a3 := c + Vector2(r * 0.7, r * 0.4)
			ci.draw_polyline(PackedVector2Array([a0, a1, a2, a3]), col, w, true)
			var b0 := c + Vector2(-r * 0.8, r * 0.4)
			var b1 := c + Vector2(-r * 0.2, r * 0.4)
			var b2 := c + Vector2(r * 0.2, -r * 0.4)
			var b3 := c + Vector2(r * 0.7, -r * 0.4)
			ci.draw_polyline(PackedVector2Array([b0, b1, b2, b3]), col, w, true)
			ci.draw_polyline(PackedVector2Array([a3 + Vector2(-r * 0.25, -r * 0.25), a3, a3 + Vector2(-r * 0.25, r * 0.25)]), col, w, true)
			ci.draw_polyline(PackedVector2Array([b3 + Vector2(-r * 0.25, -r * 0.25), b3, b3 + Vector2(-r * 0.25, r * 0.25)]), col, w, true)
		"search":
			ci.draw_arc(c + Vector2(-r * 0.12, -r * 0.12), r * 0.62, 0.0, TAU, 24, col, w, true)
			ci.draw_line(c + Vector2(r * 0.34, r * 0.34), c + Vector2(r * 0.85, r * 0.85), col, w * 1.2, true)
		"star":
			var pts2 := PackedVector2Array()
			for i in range(10):
				var a := -PI * 0.5 + TAU * float(i) / 10.0
				pts2.append(c + Vector2.from_angle(a) * (r if i % 2 == 0 else r * 0.45))
			ci.draw_colored_polygon(pts2, col)
		"plus":
			ci.draw_line(c + Vector2(-r * 0.7, 0), c + Vector2(r * 0.7, 0), col, w * 1.2, true)
			ci.draw_line(c + Vector2(0, -r * 0.7), c + Vector2(0, r * 0.7), col, w * 1.2, true)
		"dots":
			for i in range(3):
				ci.draw_circle(c + Vector2((i - 1) * r * 0.7, 0), r * 0.16, col)
		"play":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.45, -r * 0.65), c + Vector2(r * 0.7, 0), c + Vector2(-r * 0.45, r * 0.65)]), col)
		"folder":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.85, r * 0.6), c + Vector2(-r * 0.85, -r * 0.55), c + Vector2(-r * 0.2, -r * 0.55), c + Vector2(r * 0.05, -r * 0.25), c + Vector2(r * 0.85, -r * 0.25), c + Vector2(r * 0.85, r * 0.6), c + Vector2(-r * 0.85, r * 0.6)]), col, w, true)
		"clock":
			ci.draw_arc(c, r * 0.85, 0.0, TAU, 28, col, w, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -r * 0.5), c, c + Vector2(r * 0.4, r * 0.25)]), col, w, true)
		"retry":
			ci.draw_arc(c, r * 0.7, 0.35, 0.35 + TAU * 0.78, 28, col, w * 1.2, true)
			var tip := c + Vector2.from_angle(0.35) * r * 0.7
			ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(r * 0.42, -r * 0.18), tip + Vector2(-r * 0.12, -r * 0.5), tip + Vector2(-r * 0.2, r * 0.3)]), col)
		"power":
			ci.draw_arc(c + Vector2(0, r * 0.1), r * 0.78, -PI * 0.5 + 0.7, -PI * 0.5 + TAU - 0.7, 28, col, w * 1.2, true)
			ci.draw_line(c + Vector2(0, -r * 0.95), c + Vector2(0, -r * 0.1), col, w * 1.2, true)
		"users":
			ci.draw_circle(c + Vector2(-r * 0.45, -r * 0.4), r * 0.28, col)
			ci.draw_arc(c + Vector2(-r * 0.45, r * 0.75), r * 0.65, PI * 1.12, PI * 1.88, 16, col, w * 1.3, true)
			ci.draw_circle(c + Vector2(r * 0.5, -r * 0.5), r * 0.24, Color(col.r, col.g, col.b, col.a * 0.7))
			ci.draw_arc(c + Vector2(r * 0.5, r * 0.65), r * 0.55, PI * 1.12, PI * 1.88, 16, Color(col.r, col.g, col.b, col.a * 0.7), w * 1.2, true)
		"user":
			ci.draw_circle(c + Vector2(0, -r * 0.35), r * 0.32, col)
			ci.draw_arc(c + Vector2(0, r * 0.95), r * 0.8, PI * 1.1, PI * 1.9, 16, col, w * 1.4, true)
		"download":
			ci.draw_line(c + Vector2(0, -r * 0.85), c + Vector2(0, r * 0.25), col, w * 1.2, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.45, -r * 0.2), c + Vector2(0, r * 0.25), c + Vector2(r * 0.45, -r * 0.2)]), col, w * 1.2, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.85, r * 0.35), c + Vector2(-r * 0.85, r * 0.8), c + Vector2(r * 0.85, r * 0.8), c + Vector2(r * 0.85, r * 0.35)]), col, w * 1.2, true)
		"alert":
			var tri := PackedVector2Array([c + Vector2(0, -r * 0.9), c + Vector2(r * 0.95, r * 0.75), c + Vector2(-r * 0.95, r * 0.75), c + Vector2(0, -r * 0.9)])
			ci.draw_polyline(tri, col, w * 1.1, true)
			ci.draw_line(c + Vector2(0, -r * 0.3), c + Vector2(0, r * 0.2), col, w * 1.3, true)
			ci.draw_circle(c + Vector2(0, r * 0.48), w * 0.8, col)
		"book":
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -r * 0.55), c + Vector2(-r * 0.9, -r * 0.75), c + Vector2(-r * 0.9, r * 0.6), c + Vector2(0, r * 0.8), c + Vector2(r * 0.9, r * 0.6), c + Vector2(r * 0.9, -r * 0.75), c + Vector2(0, -r * 0.55), c + Vector2(0, r * 0.8)]), col, w, true)
		"mods":
			for i in range(3):   # 重なった 3 枚の札
				var o := Vector2((i - 1) * r * 0.32, (1 - i) * r * 0.22)
				ci.draw_rect(Rect2(c + o - Vector2(r * 0.42, r * 0.58), Vector2(r * 0.84, r * 1.16)), col, false, w)
		"check":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.7, 0.0), c + Vector2(-r * 0.2, r * 0.55), c + Vector2(r * 0.75, -r * 0.55)]), col, w * 1.2, true)
		"list":   # 3 本の行(左に点)
			for i in range(3):
				var y := (i - 1) * r * 0.62
				ci.draw_circle(c + Vector2(-r * 0.75, y), w * 0.7, col)
				ci.draw_line(c + Vector2(-r * 0.4, y), c + Vector2(r * 0.85, y), col, w, true)
		"x":
			ci.draw_line(c + Vector2(-r * 0.6, -r * 0.6), c + Vector2(r * 0.6, r * 0.6), col, w * 1.2, true)
			ci.draw_line(c + Vector2(-r * 0.6, r * 0.6), c + Vector2(r * 0.6, -r * 0.6), col, w * 1.2, true)
		"up":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.6, r * 0.3), c + Vector2(0, -r * 0.3), c + Vector2(r * 0.6, r * 0.3)]), col, w * 1.2, true)
		"down":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.6, -r * 0.3), c + Vector2(0, r * 0.3), c + Vector2(r * 0.6, -r * 0.3)]), col, w * 1.2, true)
		"repeat":   # 輪になった 2 本の矢印
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.85, 0), c + Vector2(-r * 0.85, -r * 0.45), c + Vector2(r * 0.55, -r * 0.45)]), col, w, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(r * 0.25, -r * 0.8), c + Vector2(r * 0.65, -r * 0.45), c + Vector2(r * 0.25, -r * 0.1)]), col, w, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(r * 0.85, 0), c + Vector2(r * 0.85, r * 0.45), c + Vector2(-r * 0.55, r * 0.45)]), col, w, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.25, r * 0.1), c + Vector2(-r * 0.65, r * 0.45), c + Vector2(-r * 0.25, r * 0.8)]), col, w, true)
		"pencil":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.75, r * 0.75), c + Vector2(-r * 0.7, r * 0.25), c + Vector2(r * 0.35, -r * 0.8), c + Vector2(r * 0.8, -r * 0.35), c + Vector2(-r * 0.25, r * 0.7), c + Vector2(-r * 0.75, r * 0.75)]), col, w, true)
		"trash":
			ci.draw_line(c + Vector2(-r * 0.8, -r * 0.55), c + Vector2(r * 0.8, -r * 0.55), col, w, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.3, -r * 0.55), c + Vector2(-r * 0.3, -r * 0.85), c + Vector2(r * 0.3, -r * 0.85), c + Vector2(r * 0.3, -r * 0.55)]), col, w, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.6, -r * 0.4), c + Vector2(-r * 0.5, r * 0.85), c + Vector2(r * 0.5, r * 0.85), c + Vector2(r * 0.6, -r * 0.4)]), col, w, true)
		"image":
			ci.draw_rect(Rect2(c - Vector2(r * 0.85, r * 0.65), Vector2(r * 1.7, r * 1.3)), col, false, w)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.85, r * 0.45), c + Vector2(-r * 0.2, -r * 0.1), c + Vector2(r * 0.25, r * 0.3), c + Vector2(r * 0.5, r * 0.05), c + Vector2(r * 0.85, r * 0.4)]), col, w, true)
			ci.draw_circle(c + Vector2(r * 0.4, -r * 0.3), r * 0.15, col)
		"note":
			ci.draw_circle(c + Vector2(-r * 0.35, r * 0.55), r * 0.32, col)
			ci.draw_line(c + Vector2(-r * 0.05, r * 0.5), c + Vector2(-r * 0.05, -r * 0.8), col, w * 1.2, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.05, -r * 0.8), c + Vector2(r * 0.65, -r * 0.45), c + Vector2(r * 0.65, -r * 0.1)]), col, w * 1.2, true)
