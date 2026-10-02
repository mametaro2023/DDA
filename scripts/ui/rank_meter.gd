extends Control
## 結果画面のランクの周りの、円状のメーター。真上から時計回りに、点数の達成率(ベーススコア = 100%)まで伸びる。
## ランクの境目(D 40% / C 55% / B 70% / A 85% / S 95%)に目盛りと文字を置き、ランクごとの範囲を色分けして示す。
## 伸びている最中は、その点が入っているランクの色になる。ゲームオーバーのときは、色分けなしで到達度を示す。

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")

## 範囲の境目(0 から順に F D C B A S)。ランクの境目は GameSim.RANK_TABLE と同じ値
const BOUNDS := [0.0, 0.40, 0.55, 0.70, 0.85, 0.95, 1.0]
const RANKS := ["F", "D", "C", "B", "A", "S"]
const GAP := 0.012          # 範囲と範囲の間のすきま(ラジアン)
const WIDTH := 14.0

## 最終的な達成率(0..1。1 を超える分は 1 に切る)
var ratio := 0.0
## 伸びの進み具合 0..1(ratio のうち、どこまで見せるか)
var fill := 0.0:
	set(v):
		fill = v
		queue_redraw()
## 目盛り(各ランクの点数)を出すときの、100% にあたる点数
var scale_score := 1000000.0
## false なら、ランクの色分け・目盛りを出さず、accent 1 色で伸ばす(ゲームオーバーの到達度)
var zones := true
var accent := UiStyle.ACCENT

var _font: Font = UiStyle.bold()


func _angle(v: float) -> float:
	return -PI * 0.5 + TAU * clampf(v, 0.0, 1.0)


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 40.0
	var value := clampf(ratio, 0.0, 1.0) * clampf(fill, 0.0, 1.0)
	draw_arc(c, r, 0.0, TAU, 120, Color(1, 1, 1, 0.06), WIDTH + 6.0, true)   # 外枠のうっすらした溝
	if zones:
		for i in range(RANKS.size()):
			var lo: float = BOUNDS[i]
			var hi: float = BOUNDS[i + 1]
			var col := UiStyle.rank_color(RANKS[i])
			var a0 := _angle(lo) + GAP
			var a1 := _angle(hi) - GAP
			draw_arc(c, r, a0, a1, maxi(int((a1 - a0) * 24.0), 4), Color(col.r, col.g, col.b, 0.2), WIDTH, true)   # 範囲(うす色)
			if value > lo:   # 伸びたぶん(濃い色)
				var e := _angle(minf(value, hi)) - (GAP if value >= hi else 0.0)
				if e > a0:
					draw_arc(c, r, a0, e, maxi(int((e - a0) * 24.0), 3), col, WIDTH, true)
		# 境目の目盛りと、ランクの文字・点数
		for i in range(1, RANKS.size()):
			var b: float = BOUNDS[i]
			var col2 := UiStyle.rank_color(RANKS[i])
			var dir := Vector2.from_angle(_angle(b))
			draw_line(c + dir * (r - WIDTH * 0.5 - 5.0), c + dir * (r + WIDTH * 0.5 + 5.0), Color(col2.r, col2.g, col2.b, 0.95), 2.0, true)
			var p := c + dir * (r + WIDTH * 0.5 + 17.0)   # ランクの文字
			var q := c + dir * (r + WIDTH * 0.5 + 35.0)   # その外側に、そのランクになる点数
			draw_string(_font, p + Vector2(-20.0, 7.0), RANKS[i], HORIZONTAL_ALIGNMENT_CENTER, 40.0, 19, col2)
			draw_string(_font, q + Vector2(-24.0, 4.0), "%dk" % int(round(b * scale_score / 1000.0)), HORIZONTAL_ALIGNMENT_CENTER, 48.0, 11, Color(1, 1, 1, 0.45))
	else:
		draw_arc(c, r, _angle(0.0), _angle(1.0), 120, Color(accent.r, accent.g, accent.b, 0.14), WIDTH, true)
		if value > 0.001:
			draw_arc(c, r, _angle(0.0), _angle(value), maxi(int(value * 100.0), 4), accent, WIDTH, true)
	# 先端の光
	if value > 0.002 and fill < 1.0:
		var tip := c + Vector2.from_angle(_angle(value)) * r
		draw_circle(tip, WIDTH * 0.95, Color(1, 1, 1, 0.16))
		draw_circle(tip, WIDTH * 0.55, Color(1, 1, 1, 0.95))
	# 100% に届いたら、外側に金の細い輪
	if zones and ratio >= 0.9999 and fill >= 1.0:
		draw_arc(c, r + WIDTH * 0.5 + 4.0, 0.0, TAU, 120, Color(UiStyle.GOLD.r, UiStyle.GOLD.g, UiStyle.GOLD.b, 0.55), 2.0, true)
