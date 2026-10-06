extends Control
## lazer 風 UI のアイコン(線画。フォントに頼らず、描画で作る)。Control として置くか、static の draw で CanvasItem に直接描く。
## kind: mod_hell / mod_storm / mod_giant / mod_rush / mod_dark / mod_shrink / mod_noregen / mod_boss / mod_heaven / mod_slow / mod_v1 / mod_practice(MOD の絵)/ gear / back / shuffle / search / star / plus / dots / play / folder / clock / user / users / power / retry / download / alert / book / mods / list / x / up / down / repeat / pencil / trash / image / note

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
		# --- MOD の絵(MOD パネルの札。id ごと) ---
		"mod_hell":   # 炎
			var f := PackedVector2Array([c + Vector2(0, -r * 0.95), c + Vector2(r * 0.38, -r * 0.35), c + Vector2(r * 0.7, r * 0.1), c + Vector2(r * 0.55, r * 0.62),
				c + Vector2(0, r * 0.92), c + Vector2(-r * 0.55, r * 0.62), c + Vector2(-r * 0.7, r * 0.1), c + Vector2(-r * 0.3, -r * 0.2), c + Vector2(-r * 0.12, -r * 0.55), c + Vector2(0, -r * 0.95)])
			ci.draw_polyline(f, col, w, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, r * 0.15), c + Vector2(r * 0.25, r * 0.5), c + Vector2(0, r * 0.72), c + Vector2(-r * 0.25, r * 0.5), c + Vector2(0, r * 0.15)]), col, w * 0.9, true)
		"mod_storm":   # 雨(斜めの線 3 本)
			for i in range(3):
				var o := Vector2((i - 1) * r * 0.55, (0.15 if i == 1 else -0.1) * r)
				ci.draw_line(c + o + Vector2(r * 0.3, -r * 0.55), c + o + Vector2(-r * 0.3, r * 0.5), col, w, true)
			ci.draw_arc(c + Vector2(0, -r * 0.55), r * 0.5, PI, TAU, 14, col, w * 0.9, true)
		"mod_giant":   # 小さな円から大きな円へ(外向きの印)
			ci.draw_arc(c, r * 0.3, 0.0, TAU, 20, col, w, true)
			for i in range(4):
				var d := Vector2.from_angle(PI * 0.25 + PI * 0.5 * float(i))
				ci.draw_line(c + d * r * 0.55, c + d * r * 0.95, col, w, true)
				ci.draw_polyline(PackedVector2Array([c + d * r * 0.95 + d.rotated(PI * 0.75) * r * 0.26, c + d * r * 0.95, c + d * r * 0.95 + d.rotated(-PI * 0.75) * r * 0.26]), col, w, true)
		"mod_rush":   # 進む向きの二重の山形
			for i in range(2):
				var x := (i - 0.5) * r * 0.85
				ci.draw_polyline(PackedVector2Array([c + Vector2(x - r * 0.3, -r * 0.65), c + Vector2(x + r * 0.3, 0), c + Vector2(x - r * 0.3, r * 0.65)]), col, w * 1.15, true)
		"mod_dark":   # 三日月
			var cr := PackedVector2Array()
			for i in range(0, 21):
				var a := lerpf(PI * 0.62, TAU - PI * 0.62, float(i) / 20.0) + PI
				cr.append(c + Vector2.from_angle(a) * r * 0.85)
			var inner := PackedVector2Array()
			for i in range(0, 21):
				var a2 := lerpf(PI * 0.5, -PI * 0.5, float(i) / 20.0) + PI
				inner.append(c + Vector2(r * 0.32, 0) + Vector2.from_angle(a2) * r * 0.62)
			cr.append_array(inner)
			cr.append(cr[0])
			ci.draw_polyline(cr, col, w, true)
		"mod_shrink":   # 四隅から内側へ
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					var kc := c + Vector2(sx, sy) * r * 0.85
					ci.draw_polyline(PackedVector2Array([kc + Vector2(-sx * r * 0.5, 0), kc, kc + Vector2(0, -sy * r * 0.5)]), col, w, true)
			ci.draw_rect(Rect2(c - Vector2(r * 0.28, r * 0.28), Vector2(r * 0.56, r * 0.56)), col, false, w)
		"mod_noregen":   # ハートに斜線
			var h := PackedVector2Array()
			for i in range(0, 33):
				var t := TAU * float(i) / 32.0
				h.append(c + Vector2(16.0 * pow(sin(t), 3.0), -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))) * r * 0.052 + Vector2(0, r * 0.05))
			ci.draw_polyline(h, col, w, true)
			ci.draw_line(c + Vector2(-r * 0.9, -r * 0.8), c + Vector2(r * 0.9, r * 0.85), col, w * 1.2, true)
		"mod_boss":   # 照準
			ci.draw_arc(c, r * 0.62, 0.0, TAU, 28, col, w, true)
			ci.draw_circle(c, r * 0.12, col)
			for i in range(4):
				var d := Vector2.from_angle(PI * 0.5 * float(i))
				ci.draw_line(c + d * r * 0.45, c + d * r * 1.0, col, w, true)
		"mod_heaven":   # 光の輪と雲
			ci.draw_arc(c + Vector2(0, -r * 0.55), r * 0.5, 0.0, TAU, 24, col, w, true)
			ci.draw_arc(c + Vector2(-r * 0.4, r * 0.4), r * 0.35, PI * 0.5, PI * 1.5, 12, col, w, true)
			ci.draw_arc(c + Vector2(0, r * 0.28), r * 0.45, PI, TAU, 14, col, w, true)
			ci.draw_arc(c + Vector2(r * 0.4, r * 0.4), r * 0.35, -PI * 0.5, PI * 0.5, 12, col, w, true)
			ci.draw_line(c + Vector2(-r * 0.4, r * 0.75), c + Vector2(r * 0.4, r * 0.75), col, w, true)
		"mod_slow":   # 戻る向きの二重の山形
			for i in range(2):
				var x := (i - 0.5) * r * 0.85
				ci.draw_polyline(PackedVector2Array([c + Vector2(x + r * 0.3, -r * 0.65), c + Vector2(x - r * 0.3, 0), c + Vector2(x + r * 0.3, r * 0.65)]), col, w * 1.15, true)
		"mod_v1":   # 巻き戻した時計
			ci.draw_arc(c, r * 0.8, 0.9, 0.9 + TAU * 0.82, 28, col, w, true)
			var tp := c + Vector2.from_angle(0.9) * r * 0.8
			ci.draw_polyline(PackedVector2Array([tp + Vector2(-r * 0.05, -r * 0.42), tp, tp + Vector2(r * 0.42, -r * 0.1)]), col, w, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -r * 0.4), c, c + Vector2(r * 0.32, r * 0.2)]), col, w, true)
		"mod_practice":   # 無限(∞)
			var lm := PackedVector2Array()
			for i in range(0, 41):
				var t2 := TAU * float(i) / 40.0
				var dn := 1.0 + sin(t2) * sin(t2)
				lm.append(c + Vector2(cos(t2) / dn, sin(t2) * cos(t2) / dn) * r * 1.0 * 1.35)
			ci.draw_polyline(lm, col, w * 1.15, true)
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
