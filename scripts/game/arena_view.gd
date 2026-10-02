extends Node2D
## アリーナ内の描画。layer 0 = 弾の下(予兆/軌道)、layer 1 = 弾の上(自機/発射エフェクト)。

const GameSim = preload("res://scripts/game/game_sim.gd")
const BulletField = preload("res://scripts/game/bullet_field.gd")
const Boss = preload("res://scripts/game/boss.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")

var sim
var layer := 0
var now := 0.0
## ゲームオーバー演出(dead=true の間、自機の代わりに爆散エフェクトを描く)
var dead := false
var death_t := 0.0
var death_pos := Vector2.ZERO
## 被弾中の赤み(0..1)。game_screen が被弾で 1 に上げ、なめらかに減衰させる(点滅させない)
var hit_glow := 0.0
## 自機の現れ具合(0 = 見えない / 1 = ふつう。BACK で行き過ぎて 1 に戻る)。ゲーム開始で、カーソルが自機になる演出に使う(中心 = 自機を軸に拡大)
var ship_in := 1.0
## 自機の軌跡(尾)。{p, t} を古い順に持つ。TRAIL_LIFE 秒で消える
const TRAIL_LIFE := 0.2
var _trail: Array = []
var _trail_now := -1.0
var _slider_nodes := {}   # スライダーの軌道の描画ノード(key → {body, core})
## マルチプレイ: 自分の機体の色と、他の人の機体 [{pos, color, name, slow, alpha}](mp_game.gd が決める)
var own_color := Color(0.32, 0.80, 1.0)
var remotes: Array = []
## 再開の待ち(ポーズから戻る前): 自機と、その周りの輪だけを描く(弾・予兆・軌道・危険エリアは見せない)。wait_t は輪を動かす時間(秒)
var ship_only := false
var wait_t := 0.0


func _draw() -> void:
	if sim == null:
		return
	if layer == 0:
		_draw_under()
	else:
		_draw_over()


func _color(idx: int) -> Color:
	return BulletField.PALETTE[idx % BulletField.PALETTE.size()]


func _draw_under() -> void:
	_draw_move_rect()
	if ship_only:
		if not dead:
			_draw_player_body()
		return
	_draw_zones()
	var lead: float = sim.warn_lead
	for g in sim.active_gizmos:
		var c := _color(g.color)
		var fade_in := clampf((now - (g.t - lead)) / lead, 0.0, 1.0)
		var fade_out := clampf((g.end + 0.3 - now) / 0.3, 0.0, 1.0)
		var a := fade_in * fade_out
		if g.kind == "slider":
			if now >= g.t - lead:
				var ep := GameSim.slider_emitter(g, now)
				draw_circle(ep, 9.0, Color(c.r, c.g, c.b, 0.9 * a))
				draw_arc(ep, 13.0, 0.0, TAU, 24, Color(1, 1, 1, 0.8 * a), 2.0, true)
		else:
			draw_arc(g.pos, 42.0, 0.0, TAU, 48, Color(c.r, c.g, c.b, 0.8 * a), 3.0, true)
			draw_circle(g.pos, 8.0, Color(1, 1, 1, 0.7 * a))
	# 発射地点の印(暗闇 MOD: 弾が見えなくても、どこから撃ったかが分かる。撃った瞬間に立ち上がり、ゆっくり広がって消える)
	for f in sim.recent_fires:
		var k := clampf((now - f.t) / GameSim.FIRE_MARK_TIME, 0.0, 1.0)
		var fc := _color(f.color)
		var a := pow(1.0 - k, 1.6)
		draw_arc(f.pos, 10.0 + 34.0 * (1.0 - pow(1.0 - k, 2.0)), 0.0, TAU, 40, Color(fc.r, fc.g, fc.b, 0.8 * a), 2.5, true)
		draw_circle(f.pos, 6.0 * (1.0 - 0.5 * k), Color(1, 1, 1, 0.75 * a))
	for e in sim.active_warns:
		var p: float = clampf((e.t - now) / lead, 0.0, 1.0)  # 1→0
		var c := Color.WHITE
		if not e.shots.is_empty():
			c = _color(e.shots[0].color)
		var r := 12.0 + 56.0 * p
		var a := 0.25 + 0.6 * (1.0 - p)
		draw_arc(e.pos, r, 0.0, TAU, 40, Color(c.r, c.g, c.b, a), 2.5, true)
		draw_circle(e.pos, 5.0, Color(1, 1, 1, a))
	if sim.boss != null and not dead:
		_draw_boss_under()
	# 自機の機体は予兆・軌道の上、弾の下に描く(弾が機体の上に見える)
	if not dead:
		for r in remotes:
			_draw_remote_ship(r)
		_draw_player_body()


## 危険エリア(文字は出さない。種類は色とマークで分かる):
##   予告(発動の 2 小節前から): 薄い点線の枠とマークが、ふわっと現れ(フェードイン)、発動に近づくほど速く点滅する。
##   発動: 枠が一瞬、広がりながら光り(合図)、そのあと、濃い面・実線の太い枠・はっきりしたマークで「効いている」ことを示す。点滅しない。
##   終わる直前: ゆっくり消える。弾より奥に描く。
func _draw_zones() -> void:
	for z in sim.zones:
		var t0: float = z.t
		var t1: float = z.end
		var lead: float = z.lead
		if now < t0 - lead or now >= t1:
			continue
		var warn := now < t0
		var fade_out := clampf((t1 - now) / 0.4, 0.0, 1.0)
		var tau := now - (t0 - lead)               # 予告が始まってからの秒
		var fade_in := clampf(tau / 0.6, 0.0, 1.0)  # 予告が始まったときの、フェードイン
		var blink := 1.0
		if warn:   # 点滅は、発動に近づくほど速い(1.5 Hz → 5 Hz)。なめらかに明暗を行き来する
			var phase := TAU * (1.5 * tau + (5.0 - 1.5) * tau * tau / (2.0 * lead))
			blink = 0.5 + 0.5 * sin(phase)
		var since := now - t0                      # 発動してからの秒
		for c in z.cells:
			var idx: int = c.c
			var r: Rect2 = sim.cell_rect(idx).grow(-3.0)   # 動ける範囲(小型化なら中央の長方形)を 3×3 に分けたマス
			var col := GameSim.zone_color(str(c.type))
			var center := r.get_center()
			if warn:
				var a := fade_in * (0.25 + 0.75 * blink) * fade_out
				draw_rect(r, Color(col.r, col.g, col.b, 0.08 * a), true)
				_dashed_rect(r, Color(col.r, col.g, col.b, 0.8 * a), 2.0)
				_draw_zone_icon(str(c.type), center, Color(col.r, col.g, col.b, 0.7 * a))
			else:
				var a := fade_out
				draw_rect(r, Color(col.r, col.g, col.b, 0.26 * a), true)
				draw_rect(r, Color(col.r, col.g, col.b, 0.95 * a), false, 4.0)
				_draw_zone_icon(str(c.type), center, Color(col.r, col.g, col.b, 0.95 * a))
				if since < 0.4:   # 発動の合図: 白い枠が、外へ広がりながら消える
					var k := since / 0.4
					draw_rect(r.grow(18.0 * k), Color(1, 1, 1, 0.9 * (1.0 - k) * a), false, 3.0)
					draw_rect(r, Color(1, 1, 1, 0.35 * (1.0 - k) * a), true)


## 点線の枠。
func _dashed_rect(r: Rect2, col: Color, width: float) -> void:
	var p0 := r.position
	var p1 := r.position + Vector2(r.size.x, 0.0)
	var p2 := r.end
	var p3 := r.position + Vector2(0.0, r.size.y)
	draw_dashed_line(p0, p1, col, width, 10.0)
	draw_dashed_line(p1, p2, col, width, 10.0)
	draw_dashed_line(p2, p3, col, width, 10.0)
	draw_dashed_line(p3, p0, col, width, 10.0)


## デバフの種類を示すマーク(文字の代わり)。鈍足: 下向きの山形 / 脆弱: 割れた輪 / 毒: しずく / 巨大: 広がる輪。
func _draw_zone_icon(type: String, c: Vector2, col: Color) -> void:
	match type:
		"slow":
			draw_polyline(PackedVector2Array([c + Vector2(-16, -16), c + Vector2(0, -2), c + Vector2(16, -16)]), col, 4.0, true)
			draw_polyline(PackedVector2Array([c + Vector2(-16, 2), c + Vector2(0, 16), c + Vector2(16, 2)]), col, 4.0, true)
		"fragile":
			draw_arc(c, 20.0, 0.5, TAU - 0.5, 32, col, 4.0, true)
			draw_polyline(PackedVector2Array([c + Vector2(4, -14), c + Vector2(-4, -3), c + Vector2(5, 4), c + Vector2(-3, 16)]), col, 3.0, true)
		"poison":
			draw_polyline(PackedVector2Array([c + Vector2(0, -22), c + Vector2(-13, -2)]), col, 4.0, true)
			draw_polyline(PackedVector2Array([c + Vector2(0, -22), c + Vector2(13, -2)]), col, 4.0, true)
			draw_arc(c + Vector2(0, 6), 13.0, -0.5, PI + 0.5, 24, col, 4.0, true)
		"big":
			draw_circle(c, 6.0, col)
			draw_arc(c, 18.0, 0.0, TAU, 32, col, 3.5, true)
			for i in range(4):
				var d := Vector2.from_angle(PI * 0.25 + PI * 0.5 * i)
				draw_line(c + d * 24.0, c + d * 32.0, col, 3.5, true)


func _draw_over() -> void:
	if dead:
		_draw_death()
		return
	if ship_only:
		_draw_wait_rings()
		_draw_player_marks()
		return
	_draw_remote_marks()
	if sim.boss != null:
		_draw_boss_over()
	_draw_player_marks()


## 小型化 MOD: 動ける範囲の外を少し暗くし、範囲の枠を描く(弾・発射位置は範囲の外にも出る)。
func _draw_move_rect() -> void:
	var r: Rect2 = sim.move_rect
	if r.size.is_equal_approx(GameSim.ARENA):
		return
	var shade := Color(0.0, 0.0, 0.0, 0.32)
	var a := GameSim.ARENA
	draw_rect(Rect2(0, 0, a.x, r.position.y), shade)
	draw_rect(Rect2(0, r.end.y, a.x, a.y - r.end.y), shade)
	draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), shade)
	draw_rect(Rect2(r.end.x, r.position.y, a.x - r.end.x, r.size.y), shade)
	draw_rect(r, Color(0.45, 0.95, 0.75, 0.55), false, 2.0)
	var k := 14.0   # 角の目印
	for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if c.x <= r.get_center().x else -1.0
		var sy := 1.0 if c.y <= r.get_center().y else -1.0
		draw_polyline(PackedVector2Array([c + Vector2(0, k * sy), c, c + Vector2(k * sx, 0)]), Color(0.75, 1.0, 0.88, 0.9), 3.0, true)


## 撃破 MOD(弾の下の層): 自機の弾と、ボスの本体(回る六角形と三角形・コア・HP の輪)。命中した瞬間は白く光る。
func _draw_boss_under() -> void:
	var b = sim.boss
	for p in b.shots:
		draw_line(p, p + Vector2(0, 16), Color(0.65, 0.95, 1.0, 0.55), 2.0, true)
	if b.defeated:
		return
	var c: Vector2 = b.pos
	var R := Boss.BOSS_R
	var base := Color(1.0, 0.5, 0.42).lerp(Color.WHITE, clampf(b.flash / Boss.FLASH_TIME, 0.0, 1.0) * 0.8)
	var frac: float = b.hp / maxf(b.max_hp, 1.0)
	draw_circle(c, R * 1.25, Color(base.r, base.g, base.b, 0.08))
	var hexa := PackedVector2Array()
	for k in range(7):
		hexa.append(c + Vector2.from_angle(TAU * float(k) / 6.0 + now * 0.8) * R)
	draw_colored_polygon(hexa.slice(0, 6), Color(base.r * 0.35, base.g * 0.2, base.b * 0.2, 0.75))
	draw_polyline(hexa, Color(base.r, base.g, base.b, 0.95), 2.5, true)
	var tri := PackedVector2Array()
	for k in range(4):
		tri.append(c + Vector2.from_angle(TAU * float(k) / 3.0 - now * 1.6) * R * 0.6)
	draw_polyline(tri, Color(1.0, 0.8, 0.6, 0.85), 2.0, true)
	draw_circle(c, R * 0.24, Color(1.0, 0.9, 0.8, 0.95))
	# ボーナスタイム: ボスがひるんでいる(金色の輪と、頭の上を回る星)
	var bl: float = sim.bonus_left(now)
	if bl >= 0.0:
		var env := clampf((Boss.BONUS_TIME - bl) / 0.25, 0.0, 1.0) * clampf(bl / 0.3, 0.0, 1.0)
		draw_arc(c, R + 16.0, 0.0, TAU, 48, Color(1.0, 0.86, 0.4, 0.55 * env), 2.0, true)
		for k in range(3):
			var ang := now * 4.0 + TAU * float(k) / 3.0
			var sp := c + Vector2(cos(ang) * (R * 0.9), -R - 10.0 + sin(ang) * 7.0)
			var star := PackedVector2Array()
			for q in range(10):
				star.append(sp + Vector2.from_angle(-PI * 0.5 + PI * 0.2 * q) * (6.0 if q % 2 == 0 else 2.6))
			draw_colored_polygon(star, Color(1.0, 0.9, 0.45, 0.95 * env))
	# HP の輪(上から時計回りに減る。残りが少ないほど赤く)
	var hc := Color(1.0, 0.85, 0.4).lerp(Color(1.0, 0.25, 0.3), 1.0 - frac)
	draw_arc(c, R + 9.0, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 3.0, true)
	if frac > 0.0:
		draw_arc(c, R + 9.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, Color(hc.r, hc.g, hc.b, 0.9), 3.0, true)


## 撃破 MOD(弾の上の層): アイテム(種類ごとの色と文字。P 攻撃力 / S 連射 / W ワイド / H 回復 / B ボム)と、撃破の演出。
func _draw_boss_over() -> void:
	var b = sim.boss
	var font := UiStyle.bold()
	for it in b.items:
		var p: Vector2 = it.p
		var spec: Dictionary = Boss.ITEMS[it.kind]
		var c: Color = spec.color
		var age := now - float(it.t)
		var pulse := 0.5 + 0.5 * sin(age * 6.0)
		draw_circle(p, 17.0, Color(c.r, c.g, c.b, 0.14 + 0.08 * pulse))
		draw_arc(p, 14.0 + 3.0 * pulse, 0.0, TAU, 24, Color(c.r, c.g, c.b, 0.55 * (1.0 - 0.5 * pulse)), 2.0, true)
		# ゆっくり回るひし形の札
		var rot := age * 1.2
		var pts := PackedVector2Array()
		for k in range(4):
			pts.append(p + Vector2.from_angle(rot + PI * 0.5 * k) * 12.5)
		draw_colored_polygon(pts, Color(c.r * 0.75, c.g * 0.75, c.b * 0.75, 0.95))
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.95), 1.5, true)
		draw_string(font, p + Vector2(-9, 5), str(spec.mark), HORIZONTAL_ALIGNMENT_CENTER, 18.0, 13, Color.WHITE)
	if b.defeated:
		_draw_boss_burst(b.defeat_pos, now - float(b.defeat_t))


## ボスの撃破の演出(1.6 秒): 白い閃光 → 3 重の輪が広がる → 破片と火花が散る。
func _draw_boss_burst(c: Vector2, t: float) -> void:
	if t < 0.0 or t > 1.6:
		return
	var flash := clampf(1.0 - t / 0.25, 0.0, 1.0)
	if flash > 0.0:
		draw_circle(c, 30.0 + 50.0 * (1.0 - flash), Color(1.0, 0.95, 0.85, 0.6 * flash))
	for i in range(3):
		var tt := (t - 0.08 * i) / (0.9 + 0.3 * i)
		if tt <= 0.0 or tt >= 1.0:
			continue
		var r := 20.0 + (160.0 + 90.0 * i) * (1.0 - pow(1.0 - tt, 3.0))
		var col := [Color(1.0, 0.85, 0.6), Color(1.0, 0.45, 0.4), Color(1.0, 0.7, 0.35)][i] as Color
		draw_arc(c, r, 0.0, TAU, 72, Color(col.r, col.g, col.b, 0.85 * pow(1.0 - tt, 2.0)), lerpf(6.0, 1.0, tt), true)
	for i in range(28):
		var hh := _h(i, 11.0)
		var life := 0.6 + 0.8 * _h(i, 12.0)
		if t >= life:
			continue
		var k := t / life
		var d := Vector2.from_angle(TAU * float(i) / 28.0 + hh)
		var p1 := c + d * (180.0 + 360.0 * hh) * (1.0 - exp(-3.0 * t)) / 3.0
		var p0 := c + d * (180.0 + 360.0 * hh) * (1.0 - exp(-3.0 * maxf(t - 0.06, 0.0))) / 3.0
		draw_line(p0, p1, Color(1.0, 0.9 - 0.5 * k, 0.6 - 0.5 * k, 1.0 - k), 2.0, true)


## 再開の待ち: 自機の周りで、輪がゆっくり広がっては消える(点滅ではなく、なめらかに。ここから動かし始められる合図)。
func _draw_wait_rings() -> void:
	var p: Vector2 = sim.player_pos
	var sc: float = sim.player_scale
	for k in range(2):
		var ph := fposmod(wait_t * 0.6 + 0.5 * float(k), 1.0)
		var a := sin(PI * ph) * 0.6
		draw_arc(p, (18.0 + 36.0 * ph) * sc, 0.0, TAU, 48, Color(own_color.r, own_color.g, own_color.b, a), 2.0, true)


## スライダーの軌道(帯 + 中心線)を、現在のギズモに合わせて作る・更新する・消す。game_screen が描画の前に呼ぶ。
## 半透明の太線を draw_polyline で描くと、折れ線の関節ごとに重なって濃くなり、鋭い角ではトゲも出る。そこで、
## 「不透明な 1 本の線(Line2D。角と端は丸い)」を CanvasGroup に入れ、グループ全体に 1 度だけ透明度をかける(重なりで濃くならない)。
## 機体や予兆のリングより奥に描く(show_behind_parent)。
func sync_sliders() -> void:
	var live := {}
	for g in ([] if ship_only else sim.active_gizmos):
		if g.kind != "slider":
			continue
		var key := "%s_%s" % [str(g.t), str(g.points[0])]
		live[key] = true
		if not _slider_nodes.has(key):
			var c := _color(g.color)
			_slider_nodes[key] = {
				"body": _make_line_group(g.points, Color(c.r, c.g, c.b, 1.0), 10.0),
				"core": _make_line_group(g.points, Color(1, 1, 1, 1.0), 2.0)}
		var lead: float = sim.warn_lead
		var a := clampf((now - (g.t - lead)) / lead, 0.0, 1.0) * clampf((g.end + 0.3 - now) / 0.3, 0.0, 1.0)
		_slider_nodes[key].body.modulate.a = 0.28 * a
		_slider_nodes[key].core.modulate.a = 0.35 * a
	for key in _slider_nodes.keys():
		if not live.has(key):
			_slider_nodes[key].body.queue_free()
			_slider_nodes[key].core.queue_free()
			_slider_nodes.erase(key)


func _make_line_group(points: PackedVector2Array, color: Color, width: float) -> CanvasGroup:
	var grp := CanvasGroup.new()
	grp.show_behind_parent = true
	var ln := Line2D.new()
	ln.points = points
	ln.width = width
	ln.default_color = color
	ln.joint_mode = Line2D.LINE_JOINT_ROUND
	ln.begin_cap_mode = Line2D.LINE_CAP_ROUND
	ln.end_cap_mode = Line2D.LINE_CAP_ROUND
	ln.antialiased = true
	grp.add_child(ln)
	add_child(grp)
	return grp


## 自機の軌跡を更新する(時間ベース。フレームレートによらず、動いた分だけ約 TRAIL_LIFE 秒で消える尾になる)。
func _update_trail() -> void:
	if now == _trail_now:
		return
	_trail_now = now
	var p: Vector2 = sim.player_pos
	var moved := 0.0
	if not _trail.is_empty():
		moved = p.distance_to(_trail[_trail.size() - 1].p)
	if _trail.is_empty() or moved > 1.0:
		_trail.append({"p": p, "t": now})
	while not _trail.is_empty() and (now - _trail[0].t > TRAIL_LIFE or _trail.size() > 80):
		_trail.remove_at(0)


## 自機を、自機の位置を軸に ship_in 倍で描くための変換(描画の前に呼ぶ。終わったら _end_ship_scale)。見えないときは false。
func _begin_ship_scale() -> bool:
	if ship_in >= 0.999 and ship_in <= 1.001:
		return true
	if ship_in <= 0.01:
		return false
	var p: Vector2 = sim.player_pos
	draw_set_transform(p * (1.0 - ship_in), 0.0, Vector2(ship_in, ship_in))
	return true


func _end_ship_scale() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_player_body() -> void:
	_update_trail()
	if not _begin_ship_scale():
		return
	_draw_player_body_scaled()
	_end_ship_scale()


## 自機の機体: 1 色の矢じり + 淡い光 + 動くと伸びる尾。中心の白い点(当たり判定)は _draw_player_marks が描く。
## **弾の下の層(layer 0)に描く**: 巨大化 MOD などで自機が大きくても、機体の下にある弾が隠れず、弾が機体の上に見える。
func _draw_player_body_scaled() -> void:
	var p: Vector2 = sim.player_pos
	var sc: float = sim.player_scale   # MOD で自機が大きくなる(当たり判定の点も同じ倍率)
	var body := own_color.lerp(Color(1.0, 0.32, 0.34), hit_glow)   # 被弾中は赤みがかる

	# 尾(軌跡): 1 本の帯。古いほど細く薄い(線分の重なりによる縞が出ないよう、頂点ごとに幅と透明度を変えた四角形でつなぐ)
	if _trail.size() >= 2:
		var left: Array = []
		var right: Array = []
		var cols: Array = []
		for i in range(_trail.size()):
			var q: Vector2 = _trail[i].p
			var dir: Vector2 = (_trail[mini(i + 1, _trail.size() - 1)].p - _trail[maxi(i - 1, 0)].p)
			if dir.length() < 0.001:
				dir = Vector2.UP
			var nrm := dir.normalized().orthogonal()
			var k := 1.0 - clampf((now - float(_trail[i].t)) / TRAIL_LIFE, 0.0, 1.0)
			var half := (0.4 + 3.4 * k) * sc
			left.append(q + nrm * half)
			right.append(q - nrm * half)
			cols.append(Color(body.r, body.g, body.b, 0.5 * k))
		for i in range(1, _trail.size()):
			# 四角形のまま描くと、細かく折り返す動きで辺が交差(蝶ネクタイ)して描画エラーになるので、2 枚の三角形で描く(面積のないものは飛ばす)
			for tri in [[left[i - 1], left[i], right[i], cols[i - 1], cols[i], cols[i]], [left[i - 1], right[i], right[i - 1], cols[i - 1], cols[i], cols[i - 1]]]:
				var ta: Vector2 = tri[0]
				var tb: Vector2 = tri[1]
				var tc: Vector2 = tri[2]
				if absf((tb - ta).cross(tc - ta)) > 0.01:
					draw_primitive(PackedVector2Array([ta, tb, tc]), PackedColorArray([tri[3], tri[4], tri[5]]), PackedVector2Array())
	# 淡い光
	draw_circle(p, 20.0 * sc, Color(body.r, body.g, body.b, 0.06))
	draw_circle(p, 13.0 * sc, Color(body.r, body.g, body.b, 0.10))
	# 機体: 1 色の矢じり(暗い縁取り + 明るい線)
	var dart := _dart(p, sc * sim.hit_mult)
	draw_colored_polygon(dart, Color(body.r, body.g, body.b, 0.85))
	dart.append(dart[0])
	draw_polyline(dart, Color(0, 0, 0, 0.5), 3.6, true)
	draw_polyline(dart, body.lerp(Color.WHITE, 0.6), 1.6, true)


## 機体の形(矢じり)。中心 c = 当たり判定の中心。s = 大きさの倍率(巨大のデバフで当たり判定が大きくなると、機体も同じだけ大きくなる)。
## 中心の白い点(当たり判定)が、機体の内側に収まる形にしてある。
static func _dart(c: Vector2, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for v in [Vector2(0, -15), Vector2(10.5, 9), Vector2(0, 6), Vector2(-10.5, 9)]:
		pts.append(c + v * s)
	return pts


## 自機の目印(弾の上の層 layer 1 に描く): 低速時に回る 4 本の弧、ゲージの残量リング、被弾リング、中心の当たり判定の白い点。
## どれも細いので、弾を隠さない。当たり判定の点は、機体が大きくても位置が分かるように最前面に置く。
func _draw_player_marks() -> void:
	if not _begin_ship_scale():
		return
	_draw_player_marks_scaled()
	_end_ship_scale()


func _draw_player_marks_scaled() -> void:
	var p: Vector2 = sim.player_pos
	var sc: float = sim.player_scale
	# 低速: 周りを回る 4 本の短い弧
	if sim.slow:
		for i in range(4):
			var a0 := now * 1.6 + TAU * float(i) / 4.0
			draw_arc(p, 21.0 * sc, a0, a0 + 0.9, 10, Color(1, 1, 1, 0.5), 1.5, true)
	# ゲージが減っているときだけ、自機の周りに残量のリングを出す(色は残量に応じて連続的に変わる。点滅なし)
	if sim.gauge < 0.999:
		var gc := UiStyle.hp_color(sim.gauge)
		draw_arc(p, 27.0 * sc, -PI * 0.5, -PI * 0.5 + TAU * sim.gauge, 48, Color(gc.r, gc.g, gc.b, 0.85), 3.0, true)
	# 危険エリアのデバフを受けている間は、その色の細い輪と名前を出す(点滅しない)
	if sim.zone_debuff != "":
		var zc := GameSim.zone_color(sim.zone_debuff)
		draw_arc(p, 34.0 * sc, 0.0, TAU, 48, Color(zc.r, zc.g, zc.b, 0.85), 2.5, true)
	if hit_glow > 0.01:
		draw_arc(p, 17.0 * sc, 0.0, TAU, 32, Color(1.0, 0.35, 0.35, 0.7 * hit_glow), 2.5, true)
	_draw_hitbox(p, sim.player_r * sim.hit_mult)


## 当たり判定の点(自分も他の人も、まったく同じ見た目): 白い円の縁が、そのまま当たり判定の縁(大きさも同じ)。
## 暗い縁取りで、明るい弾の上でも縁が見える。hr = 当たり判定の半径。
func _draw_hitbox(p: Vector2, hr: float) -> void:
	draw_circle(p, hr + 1.4, Color(0, 0, 0, 0.6))
	draw_circle(p, hr, Color.WHITE)


## 決まった疑似乱数(0..1)。i = 粒の番号、salt = 用途ごとにずらす値。毎回同じ配置になる。
func _h(i: int, salt: float) -> float:
	return fmod(absf(sin(float(i) * 12.9898 + salt * 78.233) * 43758.5453), 1.0)


## ゲームオーバーの爆散演出。加算合成で光らせる(game_screen が dead にする時に material を設定する)。
## 点滅・画面全体のフラッシュ・画面揺れはなし。すべて、立ち上がり → なめらかな減衰。
## 時間軸(death_t 秒):
##   0〜0.1   中心のコアが立ち上がる(小さな光。画面全体は光らせない)
##   0〜1.9   衝撃波(3 重: 円 / 六角形 / 大きく薄い円)、放射状の光条(彗星のように伸びて縮む)
##   0〜1.6   火花(尾を引いて減速)、自機の破片(回転しながら散る)
##   0.4〜2.9 余韻の火の粉(ゆっくり漂って消える)
func _draw_death() -> void:
	var t := death_t
	var c := death_pos

	# 1) コア: 小さな光。0.1 秒で立ち上がり、減衰しながら少し広がる
	var core_out := clampf(1.0 - (t - 0.1) / 0.75, 0.0, 1.0)
	var core := smoothstep(0.0, 0.1, t) * core_out * core_out
	if core > 0.01:
		var spread := 1.0 + 1.6 * (1.0 - core_out)
		for k in range(6):
			draw_circle(c, (7.0 + k * 8.0) * spread, Color(1.0, 0.78 - k * 0.06, 0.5 - k * 0.05, 0.085 * core))
		draw_circle(c, (5.0 + 8.0 * core), Color(1, 1, 1, 0.6 * core))

	# 2) 衝撃波(3 重)
	var ring_col := [Color(1.0, 0.86, 0.72), Color(1.0, 0.38, 0.32), Color(0.55, 0.78, 1.0)]
	var ring_delay := [0.0, 0.07, 0.18]
	var ring_dur := [1.0, 1.3, 1.9]
	var ring_max := [480.0, 600.0, 720.0]
	for i in range(3):
		var tt: float = (t - ring_delay[i]) / ring_dur[i]
		if tt <= 0.0 or tt >= 1.0:
			continue
		var e: float = 1.0 - pow(1.0 - tt, 3.0)          # 速く出て、減速する
		var r: float = 12.0 + ring_max[i] * e
		var a: float = pow(1.0 - tt, 2.0)
		var w: float = lerpf(7.0 - 2.0 * i, 0.8, tt)
		var col: Color = ring_col[i]
		if i == 1:
			# 六角形の衝撃波(ゆっくり回る)
			var pts := PackedVector2Array()
			for k in range(7):
				pts.append(c + Vector2.from_angle(TAU * float(k) / 6.0 + tt * 0.9) * r)
			draw_polyline(pts, Color(col.r, col.g, col.b, a * 0.9), w, true)
			draw_polyline(pts, Color(col.r, col.g, col.b, a * 0.2), w * 3.0, true)
		else:
			draw_arc(c, r, 0.0, TAU, 96, Color(col.r, col.g, col.b, a * 0.9), w, true)
			draw_arc(c, r, 0.0, TAU, 96, Color(col.r, col.g, col.b, a * 0.2), w * 3.2, true)   # にじみ

	# 3) 光条: 先頭が速く走り、後端が遅れて追いつく(彗星のように伸びて、縮んで消える)
	for i in range(36):
		var hh := _h(i, 1.0)
		var life := 0.55 + 0.5 * hh
		if t >= life:
			continue
		var k := t / life
		var d := Vector2.from_angle(TAU * float(i) / 36.0 + hh * 0.12)
		var head := (40.0 + 330.0 * (0.4 + hh)) * (1.0 - pow(1.0 - k, 3.0))
		var tail := head * clampf(k * 1.6 - 0.15, 0.0, 1.0)
		var col := Color(1.0, 0.9, 0.75) if i % 3 == 0 else (Color(1.0, 0.42, 0.36) if i % 3 == 1 else Color(0.62, 0.86, 1.0))
		draw_line(c + d * tail, c + d * head, Color(col.r, col.g, col.b, (1.0 - k) * 0.85), 1.5 + (1.0 - k) * 1.5, true)

	# 4) 火花: 尾を引いて減速し、白 → 橙 → 赤に変わりながら消える
	for i in range(64):
		var hh := _h(i, 2.0)
		var h2 := _h(i, 3.0)
		var life := 0.5 + 0.9 * h2
		if t >= life:
			continue
		var kk := t / life
		var d := Vector2.from_angle(h2 * TAU + hh)
		var spd := 220.0 + 900.0 * hh * hh
		var p1 := c + d * (spd * (1.0 - exp(-3.0 * t)) / 3.0)
		var p0 := c + d * (spd * (1.0 - exp(-3.0 * maxf(t - 0.07, 0.0))) / 3.0)
		var col := Color(1.0, 1.0 - 0.6 * kk, 0.8 - 0.7 * kk)
		draw_line(p0, p1, Color(col.r, col.g, col.b, 1.0 - kk), 2.0, true)
		draw_circle(p1, 1.8 * (1.0 - kk) + 0.6, Color(1, 1, 1, 1.0 - kk))

	# 5) 自機の破片: 三角形が回りながら散り、薄れる
	for i in range(10):
		var hh := _h(i, 4.0)
		var life := 1.5 + 0.4 * hh
		if t >= life:
			continue
		var k := t / life
		var ang := TAU * float(i) / 10.0 + hh * 0.5
		var pos := c + Vector2.from_angle(ang) * ((90.0 + 260.0 * hh) * (1.0 - exp(-2.2 * t)) / 2.2)
		var rot := ang + (hh - 0.5) * 14.0 * t
		var sz := 5.0 + 7.0 * hh
		var tri := PackedVector2Array([
			pos + Vector2(sz, 0.0).rotated(rot),
			pos + Vector2(-sz * 0.6, sz * 0.7).rotated(rot),
			pos + Vector2(-sz * 0.6, -sz * 0.7).rotated(rot)])
		var a := clampf((1.0 - k) * 1.6, 0.0, 1.0)
		draw_colored_polygon(tri, Color(0.5, 0.92, 1.0, a * 0.55))
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(1, 1, 1, a * 0.85), 1.4, true)

	# 6) 余韻の火の粉: ゆっくり漂いながら現れ、なめらかに消える
	for i in range(22):
		var hh := _h(i, 5.0)
		var h2 := _h(i, 6.0)
		var born := 0.35 + 0.7 * hh
		var life := 1.6 + 0.8 * h2
		var k := (t - born) / life
		if k <= 0.0 or k >= 1.0:
			continue
		var start := c + Vector2.from_angle(h2 * TAU) * (20.0 + 90.0 * hh)
		var pos := start + Vector2(sin(t * 1.3 + hh * 6.0) * 14.0, -26.0 * (t - born) * (0.6 + hh))
		var env := pow(sin(PI * k), 1.2)
		var col := Color(1.0, 0.7 - 0.3 * hh, 0.4)
		draw_circle(pos, 1.6 + 1.4 * hh, Color(col.r, col.g, col.b, 0.55 * env))


## 他の人の機体(マルチプレイ)。自機と同じ矢じりで、その人の色。尾はなし。弾の下の層に描く(対戦では淡いゴースト)。
func _draw_remote_ship(r: Dictionary) -> void:
	var p: Vector2 = r.pos
	var sc: float = sim.player_scale
	var a: float = r.alpha
	var body: Color = r.color
	draw_circle(p, 20.0 * sc, Color(body.r, body.g, body.b, 0.05 * a))
	var dart := _dart(p, sc * sim.hit_mult_at(p, now))   # 巨大のデバフ中は、自機と同じく大きくなる
	draw_colored_polygon(dart, Color(body.r, body.g, body.b, 0.85 * a))
	dart.append(dart[0])
	draw_polyline(dart, Color(0, 0, 0, 0.5 * a), 3.6, true)
	draw_polyline(dart, Color(body.r, body.g, body.b, a).lerp(Color(1, 1, 1, a), 0.6), 1.6, true)


## 他の人の目印(弾の上の層): 低速の弧・当たり判定の点・名前。どれも細く淡いので、弾を隠さない。
## 当たり判定の点だけは、色・濃さ・大きさを自分のものとまったく同じにする(_draw_hitbox)。
func _draw_remote_marks() -> void:
	var font := ThemeDB.fallback_font
	for r in remotes:
		var p: Vector2 = r.pos
		var sc: float = sim.player_scale
		var a: float = minf(float(r.alpha) + 0.25, 1.0)
		var c: Color = r.color
		if r.slow:
			for i in range(4):
				var a0 := now * 1.6 + TAU * float(i) / 4.0
				draw_arc(p, 21.0 * sc, a0, a0 + 0.9, 10, Color(c.r, c.g, c.b, 0.5 * a), 1.5, true)
		_draw_hitbox(p, sim.player_r * sim.hit_mult_at(p, now))
		draw_string(font, p + Vector2(-60, -22.0 * sc - 4.0), str(r.name), HORIZONTAL_ALIGNMENT_CENTER, 120.0, 11, Color(c.r, c.g, c.b, 0.7 * a))
