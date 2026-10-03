extends RefCounted
## 特殊エリア(弾幕 v2)の形。盤面の 3×3 のマスではなく、自機が動ける範囲(GameSim.move_rect)に対する割合で決める
## (小型化 MOD でも、その範囲に合わせて拡縮する)。決定的で、位置と時刻だけから決まる(協力でも全員が同じになる)。
##
## 形(shape の辞書):
##   rect    {k: "rect", r: Rect2(割合), mv: Vector2(割合)} … 長方形。mv は、エリアが出ている間に動く量(発動から終わりまでで、mv だけ平行移動する。帯が盤面を横切る「走査線」)
##   ellipse {k: "ellipse", c: Vector2(割合), r: float} … 円。r は、動ける範囲の短いほうの辺に対する半径の割合
## 半面・帯・角はすべて rect(割合の置き方が違うだけ)。

const RECT := "rect"
const DISC := "disc"


static func rect(x0: float, y0: float, x1: float, y1: float, mv := Vector2.ZERO) -> Dictionary:
	return {"k": RECT, "r": Rect2(x0, y0, x1 - x0, y1 - y0), "mv": mv}


static func disc(cx: float, cy: float, r: float) -> Dictionary:
	return {"k": DISC, "c": Vector2(cx, cy), "r": r}


## エリアが出ている間の進み具合 0..1(予告の間は 0)。
static func progress(z: Dictionary, now: float) -> float:
	var span := maxf(float(z.end) - float(z.t), 0.001)
	return clampf((now - float(z.t)) / span, 0.0, 1.0)


## 形の、いまの長方形(世界の座標。field = 自機が動ける範囲)。rect でなければ、円の外接の正方形。
static func bounds(shape: Dictionary, field: Rect2, u: float) -> Rect2:
	if str(shape.k) == RECT:
		var n: Rect2 = shape.r
		var s: Vector2 = shape.mv * u
		return Rect2(field.position + (n.position + s) * field.size, n.size * field.size)
	var rr := world_radius(shape, field)
	var c: Vector2 = field.position + (shape.c as Vector2) * field.size
	return Rect2(c - Vector2(rr, rr), Vector2(rr, rr) * 2.0)


static func world_radius(shape: Dictionary, field: Rect2) -> float:
	return float(shape.r) * minf(field.size.x, field.size.y)


## 点 p が、形の中か。
static func contains(shape: Dictionary, p: Vector2, field: Rect2, u: float) -> bool:
	if str(shape.k) == RECT:
		return bounds(shape, field, u).has_point(p)
	var c: Vector2 = field.position + (shape.c as Vector2) * field.size
	var rr := world_radius(shape, field)
	return p.distance_squared_to(c) <= rr * rr


## 形の面積が、自機が動ける範囲に占める割合(0..1。動く長方形は、最初の位置で数える。範囲の外にはみ出す分は数えない)。
static func area_fraction(shape: Dictionary) -> float:
	if str(shape.k) == RECT:
		return ((shape.r as Rect2).intersection(Rect2(0, 0, 1, 1))).get_area()
	return PI * float(shape.r) * float(shape.r) * 0.75   # 4:3 の盤面で、半径は短いほうの辺(縦)に対する割合


## エリアの種類(type)ごとの、そのエリアの中の効果の種類。"trial" = 自機が不利になる(デバフ)/ "boon" = 有利になる / "warp" = 弾に作用する。
static func family_of(type: String) -> String:
	match type:
		"slow", "fragile", "poison", "big":
			return "trial"
		"heal", "precise", "bonus":
			return "boon"
		"warp":
			return "warp"
	return ""


## ある時刻 now に、点 p にいる自機に効いているエリアの種類(なければ ""。弾に作用する warp は、自機には効かないので "")。
## z は z.areas を持つ新しい形式(弾幕 v2)。重なるときは、先に書いてあるものが勝つ。
static func type_at(z: Dictionary, p: Vector2, now: float, field: Rect2) -> String:
	var u := progress(z, now)
	for a in z.areas:
		if contains(a.shape, p, field, u):
			return "" if str(a.type) == "warp" else str(a.type)
	return ""
