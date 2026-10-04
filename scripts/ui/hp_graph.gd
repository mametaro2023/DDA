extends Control
## 結果画面の体力グラフ。横が曲の時刻、縦が体力(0〜100%)。左から右へ描かれていく。
## 低体力のライン(20%)・休憩地帯の帯・被弾した時刻の印を重ねる。複数の系列(対戦の参加者ぶん)を重ねて描ける。

const UiStyle = preload("res://scripts/ui/ui_style.gd")

const LEFT := 46.0
const RIGHT := 14.0
const TOP := 10.0
const BOTTOM := 24.0

## 描き進みの割合 0..1(左から右へ)
var reveal := 0.0:
	set(v):
		reveal = v
		queue_redraw()

var _series: Array = []        # [{pts: PackedVector2Array(時刻, 体力), color, thick, end_mark: bool}]
var _t0 := 0.0
var _t1 := 1.0
var _breaks: Array = []        # [[開始秒, 終了秒], ...]
var _hits := PackedFloat32Array()
var _low := 0.2
var _font: Font = UiStyle.bold()
## 余白(既定は上の定数。小さく置くとき(リプレイの操作パネル)だけ変える)
var left := LEFT
var right := RIGHT
var top := TOP
var bottom := BOTTOM


## series: 系列の配列。t0/t1: 横軸の範囲(秒)。breaks: 休憩地帯。hits: 自分が被弾した時刻。low: 低体力のライン。
func set_data(series: Array, t0: float, t1: float, breaks: Array, hits: PackedFloat32Array, low: float) -> void:
	_series = series
	_t0 = t0
	_t1 = maxf(t1, t0 + 1.0)
	_breaks = breaks
	_hits = hits
	_low = low
	queue_redraw()


## 体力のサンプル(GameSim.gauge_log)と最後の値から、グラフの点列(時刻, 体力)を作る。
static func points_from_log(log: PackedFloat32Array, step: float, end_t: float, end_value: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(log.size()):
		pts.append(Vector2(float(i) * step, clampf(log[i], 0.0, 1.0)))
	if pts.is_empty() or end_t > pts[pts.size() - 1].x:
		pts.append(Vector2(end_t, clampf(end_value, 0.0, 1.0)))
	return pts


## 点列を、時刻 t0〜t1 の範囲だけに切る(境目は補間する)。途中で終わっている点列(ゲームオーバー)は、終わりのまま。
static func clip_range(pts: PackedVector2Array, t0: float, t1: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(pts.size()):
		var q := pts[i]
		var prev := pts[i - 1] if i > 0 else q
		if q.x < t0:
			continue
		if out.is_empty() and i > 0 and prev.x < t0:   # 左端: t0 の位置の値を補間して始める
			out.append(Vector2(t0, lerpf(prev.y, q.y, (t0 - prev.x) / maxf(q.x - prev.x, 0.0001))))
		if q.x > t1:   # 右端: t1 の位置の値を補間して終える
			if not out.is_empty():
				out.append(Vector2(t1, lerpf(prev.y, q.y, (t1 - prev.x) / maxf(q.x - prev.x, 0.0001))))
			break
		out.append(q)
	return out


## 少ない点数(0..100 の整数が等間隔)に間引かれたものから、点列を作る(他の参加者の分。dur: 全体の長さ秒)。
static func points_from_samples(samples: Array, dur: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := samples.size()
	for i in range(n):
		pts.append(Vector2(dur * float(i) / float(maxi(n - 1, 1)), clampf(float(samples[i]) / 100.0, 0.0, 1.0)))
	return pts


## 点列を n 個の整数(0..100)に間引く(通信で送る用)。
static func downsample(pts: PackedVector2Array, n: int) -> Array:
	var out: Array = []
	if pts.is_empty():
		return out
	var end_t := pts[pts.size() - 1].x
	var j := 0
	for k in range(n):
		var t := end_t * float(k) / float(maxi(n - 1, 1))
		while j < pts.size() - 2 and pts[j + 1].x < t:
			j += 1
		var a := pts[j]
		var b := pts[mini(j + 1, pts.size() - 1)]
		var u := 0.0 if b.x <= a.x else clampf((t - a.x) / (b.x - a.x), 0.0, 1.0)
		out.append(int(round(lerpf(a.y, b.y, u) * 100.0)))
	return out


func _plot() -> Rect2:
	return Rect2(left, top, maxf(size.x - left - right, 1.0), maxf(size.y - top - bottom, 1.0))


func _x(p: Rect2, t: float) -> float:
	return p.position.x + p.size.x * clampf((t - _t0) / (_t1 - _t0), 0.0, 1.0)


func _y(p: Rect2, v: float) -> float:
	return p.position.y + p.size.y * (1.0 - clampf(v, 0.0, 1.0))


func _draw() -> void:
	var p := _plot()
	# 休憩地帯の帯
	for b in _breaks:
		var x0 := _x(p, float(b[0]))
		var x1 := _x(p, float(b[1]))
		if x1 > x0:
			draw_rect(Rect2(x0, p.position.y, x1 - x0, p.size.y), Color(1, 1, 1, 0.045))
	# 目盛りの線と文字(縦: 0 / 50 / 100%、低体力のライン)
	for v in [0.0, 0.5, 1.0]:
		var y := _y(p, v)
		draw_line(Vector2(p.position.x, y), Vector2(p.end.x, y), Color(1, 1, 1, 0.1 if v > 0.0 else 0.22), 1.0)
		draw_string(_font, Vector2(2.0, y + 5.0), "%d%%" % int(v * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, left - 8.0, 12, Color(1, 1, 1, 0.45))
	var ly := _y(p, _low)
	var x := p.position.x
	while x < p.end.x:   # 低体力のライン(点線)
		draw_line(Vector2(x, ly), Vector2(minf(x + 5.0, p.end.x), ly), Color(1.0, 0.4, 0.42, 0.4), 1.0)
		x += 10.0
	# 横軸の時刻(mm:ss)
	var span := _t1 - _t0
	var step := 30.0 if span > 150.0 else (15.0 if span > 70.0 else 10.0)
	var t := ceilf(_t0 / step) * step
	while t <= _t1:
		var tx := _x(p, t)
		draw_line(Vector2(tx, p.end.y), Vector2(tx, p.end.y + 4.0), Color(1, 1, 1, 0.3), 1.0)
		if bottom >= 20.0 or tx > p.position.x + 16.0:   # 余白が狭いときは、左端の「0:00」を出さない(縦軸の「0%」と重なる)
			draw_string(_font, Vector2(tx - 24.0, p.end.y + bottom - 7.0), "%d:%02d" % [int(t) / 60, int(t) % 60], HORIZONTAL_ALIGNMENT_CENTER, 48.0, 11, Color(1, 1, 1, 0.45))
		t += step
	# 描き進みの位置までに切る
	var clip_x := p.position.x + p.size.x * clampf(reveal, 0.0, 1.0)
	# 被弾の印(自分): 下の端に短い線
	for h in _hits:
		var hx := _x(p, float(h))
		if hx <= clip_x:
			draw_line(Vector2(hx, p.end.y - 7.0), Vector2(hx, p.end.y), Color(1.0, 0.45, 0.45, 0.85), 2.0)
	# 系列(体力の線と、その下のうすい塗り)
	for s in _series:
		var pts: PackedVector2Array = s.pts
		if pts.size() < 2:
			continue
		var col: Color = s.color
		var thick: float = s.thick
		var line := PackedVector2Array()
		var cols := PackedColorArray()
		var by_hp: bool = bool(s.get("by_hp", false))
		var tip := Vector2.ZERO
		for q in pts:
			var px := _x(p, q.x)
			var py := _y(p, q.y)
			if px > clip_x:   # 描き進みの位置を超えたら、その位置までの線の端を補間して止める
				if not line.is_empty():
					var prev := line[line.size() - 1]
					var u := 0.0 if px <= prev.x else (clip_x - prev.x) / (px - prev.x)
					line.append(Vector2(clip_x, lerpf(prev.y, py, clampf(u, 0.0, 1.0))))
					cols.append(UiStyle.hp_color(q.y) if by_hp else col)
				break
			line.append(Vector2(px, py))
			cols.append(UiStyle.hp_color(q.y) if by_hp else col)
		if line.size() >= 2:
			var poly := PackedVector2Array(line)
			poly.append(Vector2(line[line.size() - 1].x, p.end.y))
			poly.append(Vector2(line[0].x, p.end.y))
			if bool(s.get("fill", true)):
				draw_colored_polygon(poly, Color(col.r, col.g, col.b, 0.1))
			if by_hp:
				draw_polyline_colors(line, cols, thick, true)
			else:
				draw_polyline(line, col, thick, true)
			tip = line[line.size() - 1]
			var drawing := reveal < 1.0 and tip.x >= clip_x - 0.5   # まだ描き進んでいる(線が途中で終わっていれば、描き終わり)
			if drawing:
				draw_circle(tip, thick + 2.0, Color(1, 1, 1, 0.95))
			elif bool(s.get("end_mark", false)):   # ゲームオーバー: 終わりの位置に赤い点
				draw_circle(tip, thick + 3.0, Color(1.0, 0.4, 0.42, 1.0))
