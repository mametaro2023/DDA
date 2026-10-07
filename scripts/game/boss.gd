extends RefCounted
## 撃破 MOD: ボス・自機の弾・アイテム。描画/音声に依存しない(GameSim が毎ステップ update を呼ぶ。ヘッドレスでも回せる)。
##
## ## 進み方
## 曲(と弾幕)はボスを倒すかゲームオーバーになるまで繰り返す(GameSim.loop_len。周回ごとに append_loop で次の周のアンカーを足す)。
## 各周の最後のノーツのあとの BONUS_TIME 秒はボーナスタイム: ボスはその場で止まり、撃ち放題(曲はその間に次の周の頭へ早送りする)。
## ボスを倒すとクリア(GameSim が少し待ってから終える)。
##
## ## ボスの動き(osu! のオートを、最高速度つきで追いかける)
## 目標の位置(target_at)は osu! のオート: 弾を撃つイベントの時刻ちょうどにその発射位置、スライダーの間は軌道の上(GameSim.slider_emitter)、
## スピナーの間は中心のまわりを回り、その間は前の位置から次の位置へなめらかに移る。ボスはこの目標を MAX_SPEED までの速さで追いかける
## (やさしい譜面では目標どおりに動き、ジャンプの速い譜面では遅れて、なめらかになる = 自機で追いかけられる)。
## 動きは TRACK_DT 刻みで先に計算しておき(_track)、pos_at はそれを引く。
## 最初は盤面の上の外にいて、最初の発射の ENTER_TIME 秒前から降りてきて、最初の発射位置に着く(appear_t = 降り始める時刻。この間は速さの上限なし)。
## 弾幕の発射位置はボスとは関係なく、今までどおり(ボスは見た目と、自機の弾の的)。ボスに体当たりの判定はない(被弾は弾だけ)。
##
## ## 自機の弾
## 最初の発射から(休憩地帯を除く)、自機から上へ自動で連射する。上へ直進するので、ボスの下にいるときだけ当たる。
## 弾の列の数(ワイド)・連射の速さ・1 発の攻撃力は、アイテムで上がる。
##
## ## HP
## 上へ撃つので、ボスの真下(動ける範囲の中)にいる間しか当てられず、ボスは音符ごとに大きく跳ぶので、ずっと真下にはいられない。
## そこで setup で「キーボードの最高速で、ボスの CHASE_BELOW px 下を追いかけ続ける自機(弾は気にしない・アイテムなし)」を
## SAMPLE_DT 刻みで 1 周ぶん(ボーナスタイムを含む)動かし、実際と同じ規則で弾を撃って当たった数(ref_hits)から、1 秒あたりの命中数を出す。
## HP は、その HP_CHASE_SECONDS 秒ぶん(アイテムなしで追いかけ続けて、弾の飛んでいる時間で約 HP_CHASE_SECONDS 秒。アイテムで縮む)。
## 譜面のジャンプの大きさ・小型化による違いが、HP に入る。
## (最高速度がないと、ジャンプの多い譜面ではボスが速すぎて、追いかけても動かない自機と命中数がほぼ同じだった。MAX_SPEED はこれを直すために、
## tests/test_boss.gd のボットで「動かない自機 ÷ 追いかける自機」の命中数の比を見て決めた)
##
## ## アイテム
## 命中ごとに DROP_CHANCE で、ボスの位置に 1 個落とす(種類は ITEMS の重みで選ぶ。上限に届いている強化は出さない)。少し跳ねてから、
## ゆっくり落ちる。落ちながら、動ける範囲の横幅の中へ寄る(必ず取りに行ける)。自機が触れると効果が付き、pick_events に記録する
## (回復・ボムは GameSim が、音と演出は game_screen が、それを見て行う)。

const GameSim = preload("res://scripts/game/game_sim.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")

const ARENA := PatternGen.ARENA
const BOSS_R := 36.0             # ボスの当たり判定(自機の弾)の半径
const FIRE_INTERVAL := 1.0 / 15.0   # 連射の間隔(強化なし)
const SHOT_SPEED := 1500.0
const SHOT_DMG := 1.0
## 弾の列の横の位置(自機の中心から)。ワイドの段階ごと
const WIDE_OFFSETS := [[-7.0, 7.0], [-20.0, -7.0, 7.0, 20.0], [-33.0, -20.0, -7.0, 7.0, 20.0, 33.0]]
const HP_CHASE_SECONDS := 240.0
const CHASE_BELOW := 160.0
const HP_MIN := 300.0
const SAMPLE_DT := 0.01
const ENTER_TIME := 2.0          # 登場: 盤面の上の外から、最初の発射位置まで降りてくる秒
const MAX_SPEED := 400.0         # ボスの移動の最高速度(px/s。自機のキーボードの最高速 380 と同じくらい)
const TRACK_DT := 0.01           # ボスの動きを先に計算しておく刻み(秒)
const BONUS_TIME := 3.0          # 各周の最後のノーツのあとのボーナスタイム(秒)
const ENTER_FROM_Y := -110.0
const SPIN_R := 30.0             # スピナーの間に回る半径
const SPIN_RATE := TAU * 1.5     # rad/s
const SPIN_IN := 0.25            # スピナーの始めに、中心から回る半径まで広がる秒
const DROP_CHANCE := 0.006
## アイテムの種類: 重み(出やすさ)・上限の段階(0 = 段階なし)・表示の文字と色
const ITEMS := {
	"power": {"w": 3.0, "max": 4, "mark": "P", "name": "POWER UP", "color": Color(0.95, 0.25, 0.3)},
	"rate": {"w": 3.0, "max": 3, "mark": "S", "name": "RAPID UP", "color": Color(0.25, 0.7, 1.0)},
	"wide": {"w": 2.0, "max": 2, "mark": "W", "name": "WIDE UP", "color": Color(0.35, 0.85, 0.4)},
	"heal": {"w": 2.0, "max": 0, "mark": "H", "name": "HEAL", "color": Color(1.0, 0.45, 0.75)},
	"bomb": {"w": 1.0, "max": 0, "mark": "B", "name": "BOMB", "color": Color(1.0, 0.8, 0.25)},
}
const POWER_STEP := 0.25         # 攻撃力: 1 段ごとに +25%(4 段で ×2)
const RATE_STEP := 0.25          # 連射: 1 段ごとに速さ +25%(3 段で ×1.75)
const HEAL_AMOUNT := 0.3         # 回復: ゲージ全体に対する割合
const ITEM_PICK_R := 22.0
const ITEM_POP := 160.0          # 出た瞬間の上向きの速さ(px/s)
const ITEM_GRAVITY := 400.0
const ITEM_FALL := 90.0          # 落ちる速さの上限(px/s)
const ITEM_X_PULL := 1.5         # 動ける範囲の横幅の中へ寄る速さ(1/s)
const ITEM_X_INSET := 16.0
const FLASH_TIME := 0.06         # 命中したときに白く光る秒

var max_hp := HP_MIN
var hp := HP_MIN
var power := 0                   # 攻撃力の段階
var power_mul := 1.0
var rate_lv := 0                 # 連射の段階
var wide_lv := 0                 # ワイドの段階
var pos := Vector2(ARENA.x * 0.5, ENTER_FROM_Y)
var appear_t := 0.0              # 盤面の外から降りてき始める時刻
var defeated := false
var defeat_t := -1.0
var defeat_pos := Vector2.ZERO
var ref_hits := 0                # 追いかけ続ける自機が、1 周で当てる数(HP の計算に使ったもの)
var ref_rate := 0.0              # 同じく、弾の飛んでいる 1 秒あたり
var endless := true              # 最後の発射の後も撃ち続ける(曲が繰り返す)
var drops := true                # 命中でアイテムを落とすか(サバイバルのボスの曲は落とさない。強化は曲の間の 3 択)
var max_speed := MAX_SPEED       # 移動の最高速度(setup の前に変えると、その速さで動く。調整用)
var flash := 0.0                 # 命中で FLASH_TIME に上がり、0 へ減る(描画用)
var hits_total := 0              # 当てた弾の数の通算
var shots := PackedVector2Array()   # 自機の弾の位置(上へ SHOT_SPEED で進む)
var items: Array = []            # {kind, p, v, t}
var pick_events: Array = []      # 取ったアイテム {kind, p, t}(古い順。読む側が自分で、どこまで読んだかを覚える)

var _anchors: Array = []         # {t0, t1, p0, p1, g}(t0 の順)
var _track := PackedVector2Array()   # ボスの位置(_track_t0 から TRACK_DT ごと)
var _track_t0 := 0.0
var _enter_end := 0.0            # 登場の終わり(最初のアンカーの時刻)。これより前は、速さの上限なし
var _t0s := PackedFloat64Array()
var _rect := Rect2(Vector2.ZERO, ARENA)
var _breaks: Array = []
var _fire_from := -1.0
var _fire_to := -1.0
var _fire_acc := 0.0
var _rng := RandomNumberGenerator.new()


## events / gizmos / breaks: 弾幕(1 周目。GameSim と同じもの)。rect: 自機が動ける範囲。
## fire_from / fire_to: 1 周目の最初と最後の発射の時刻(HP の計算に使う。endless なら、撃つのは fire_from から曲の終わりまで)。
func setup(events: Array, gizmos: Array, breaks: Array, rect: Rect2, fire_from: float, fire_to: float) -> void:
	_rect = rect
	_breaks = breaks
	_fire_from = fire_from
	_fire_to = fire_to
	_anchors = _make_anchors(events, gizmos)
	_rebuild_t0s()
	_track = PackedVector2Array()
	if not _anchors.is_empty():
		_enter_end = float(_anchors[0].t0)
		appear_t = _enter_end - ENTER_TIME
		_track_t0 = appear_t - 1.0
		_extend_track()
		pos = pos_at(_track_t0)
	_rng.seed = hash("%d_%.3f_%.3f" % [events.size(), fire_from, fire_to])
	ref_hits = _count_ref_hits()
	var active := maxf(fire_to - fire_from, 0.0) + BONUS_TIME
	for b in breaks:
		active -= maxf(minf(float(b[1]), fire_to) - maxf(float(b[0]), fire_from), 0.0)
	ref_rate = float(ref_hits) / maxf(active, 1.0)
	max_hp = maxf(HP_MIN, SHOT_DMG * ref_rate * HP_CHASE_SECONDS)
	hp = max_hp


## 曲の次の周の弾幕(時刻をずらしたもの)のアンカーを足す。GameSim が、周の始まる前に呼ぶ。
func append_loop(events: Array, gizmos: Array) -> void:
	_anchors.append_array(_make_anchors(events, gizmos))
	_rebuild_t0s()
	_extend_track()


## ボスの動き(目標を最高速度までの速さで追いかける)を、いまあるアンカーの終わりまで計算して足す。
func _extend_track() -> void:
	if _anchors.is_empty():
		return
	var end_t := float(_anchors.back().t1)
	var t := _track_t0 + float(_track.size()) * TRACK_DT
	var p := target_at(t) if _track.is_empty() else _track[_track.size() - 1]
	var step := max_speed * TRACK_DT
	while t <= end_t + TRACK_DT:
		var goal := target_at(t)
		p = goal if t <= _enter_end else p.move_toward(goal, step)
		_track.append(p)
		t += TRACK_DT


## 追いかけ続ける自機(弾は気にしない・アイテムなし)が、1 周目の最初から、最後の発射のあとのボーナスタイムの終わりまでに当てる数。
## update と同じ規則を、SAMPLE_DT 刻みで回す。
func _count_ref_hits() -> int:
	if _fire_from < 0.0 or _fire_to <= _fire_from:
		return 0
	var m := Vector2.ONE * GameSim.PLAYER_MARGIN
	var pp := Vector2(_rect.get_center().x, _rect.position.y + _rect.size.y * 0.85)   # 開始位置
	var sh := PackedVector2Array()
	var acc := FIRE_INTERVAL
	var step := SHOT_SPEED * SAMPLE_DT
	var n := 0
	var t := _fire_from
	while t <= _fire_to + BONUS_TIME:
		var bp := pos_at(t)
		pp = pp.move_toward((bp + Vector2(0.0, CHASE_BELOW)).clamp(_rect.position + m, _rect.end - m), GameSim.PLAYER_SPEED * SAMPLE_DT)
		if _in_break(t):
			acc = FIRE_INTERVAL
		else:
			acc += SAMPLE_DT
			while acc >= FIRE_INTERVAL:
				acc -= FIRE_INTERVAL
				for ox in WIDE_OFFSETS[0]:
					sh.append(pp + Vector2(ox, -10.0))
		var i := sh.size() - 1
		while i >= 0:
			var p := sh[i]
			var hit := _shot_hits(p, bp, step)
			if hit or p.y - step < -20.0:
				sh[i] = sh[sh.size() - 1]
				sh.resize(sh.size() - 1)
				if hit:
					n += 1
			else:
				sh[i] = Vector2(p.x, p.y - step)
			i -= 1
		t += SAMPLE_DT
	return n


## 上へ step だけ進む自機の弾(いま p)が、このステップで、中心 bp のボスに当たるか。
static func _shot_hits(p: Vector2, bp: Vector2, step: float) -> bool:
	var dx := absf(p.x - bp.x)
	if dx >= BOSS_R:
		return false
	var h := sqrt(BOSS_R * BOSS_R - dx * dx)
	return bp.y + h >= p.y - step and bp.y - h <= p.y


func _make_anchors(events: Array, gizmos: Array) -> Array:
	var out: Array = []
	for g in gizmos:
		var t0 := float(g.t)
		var t1 := float(g.end)
		out.append({"t0": t0, "t1": t1, "g": g, "p0": _gizmo_pos(g, t0), "p1": _gizmo_pos(g, t1)})
	for e in events:
		if e.shots.is_empty():
			continue
		var t := float(e.t)
		var inside := false
		for g in gizmos:
			if t >= float(g.t) and t <= float(g.end):
				inside = true
				break
		if not inside:
			out.append({"t0": t, "t1": t, "g": null, "p0": e.pos, "p1": e.pos})
	out.sort_custom(func(a, b): return a.t0 < b.t0)
	if not out.is_empty():   # ボーナスタイム: 最後の位置で止まる
		var last_t := 0.0
		for a in out:
			last_t = maxf(last_t, float(a.t1))
		var lp: Vector2 = out.back().p1
		for a in out:
			if is_equal_approx(float(a.t1), last_t):
				lp = a.p1
		out.append({"t0": last_t, "t1": last_t + BONUS_TIME, "g": null, "p0": lp, "p1": lp})
	return out


func _rebuild_t0s() -> void:
	_t0s = PackedFloat64Array()
	for a in _anchors:
		_t0s.append(a.t0)


func _gizmo_pos(g: Dictionary, now: float) -> Vector2:
	if g.kind == "slider":
		return GameSim.slider_emitter(g, now)
	var k := now - float(g.t)
	var r := SPIN_R * clampf(k / SPIN_IN, 0.0, 1.0)
	return g.pos + Vector2.from_angle(SPIN_RATE * k - PI * 0.5) * r


## 時刻 now のボスの位置(目標を最高速度で追いかけた動き。先に計算した _track を引く)。
func pos_at(now: float) -> Vector2:
	if _track.is_empty() or now <= _track_t0:
		return target_at(now)
	var f := (now - _track_t0) / TRACK_DT
	var i := int(f)
	if i + 1 >= _track.size():
		return _track[_track.size() - 1]
	return _track[i].lerp(_track[i + 1], f - float(i))


## 時刻 now のボスの目標の位置(オートのカーソルの動き。最初は盤面の上の外から降りてくる)。
func target_at(now: float) -> Vector2:
	if _anchors.is_empty():
		return pos
	var i := _t0s.bsearch(now, false) - 1   # t0 <= now の最後のアンカー
	if i < 0:
		var p0: Vector2 = _anchors[0].p0
		var from := Vector2(p0.x, ENTER_FROM_Y)
		var u := clampf((now - (float(_anchors[0].t0) - ENTER_TIME)) / ENTER_TIME, 0.0, 1.0)
		return from.lerp(p0, 1.0 - pow(1.0 - u, 3.0))   # 速く降りてきて、ゆっくり止まる
	var a: Dictionary = _anchors[i]
	if now <= float(a.t1):
		return _gizmo_pos(a.g, now) if a.g != null else a.p0
	if i + 1 >= _anchors.size():
		return a.p1
	var b: Dictionary = _anchors[i + 1]
	var span := float(b.t0) - float(a.t1)
	var u := clampf((now - float(a.t1)) / span, 0.0, 1.0) if span > 0.0 else 1.0
	return (a.p1 as Vector2).lerp(b.p0, smoothstep(0.0, 1.0, u))


func _in_break(t: float) -> bool:
	for b in _breaks:
		if t >= b[0] and t <= b[1]:
			return true
	return false


## 連射の間隔(連射の段階を反映)。
func fire_interval() -> float:
	return FIRE_INTERVAL / (1.0 + RATE_STEP * rate_lv)


## 1 ステップ進める。resting: 休憩地帯の中(撃たない)。
func update(now: float, dt: float, ppos: Vector2, resting: bool) -> void:
	if defeated:
		return
	flash = maxf(flash - dt, 0.0)
	pos = pos_at(now)
	# 自動の連射
	if now >= _fire_from and (endless or now <= _fire_to) and not resting:
		_fire_acc += dt
		var iv := fire_interval()
		while _fire_acc >= iv:
			_fire_acc -= iv
			for ox in WIDE_OFFSETS[wide_lv]:
				shots.append(ppos + Vector2(ox, -10.0))
	else:
		_fire_acc = FIRE_INTERVAL   # 撃てるようになったら、すぐ 1 発目
	# 自機の弾を進めて、ボスとの当たりを調べる(このステップで進んだ線分と、ボスの円)
	var step := SHOT_SPEED * dt
	var i := shots.size() - 1
	while i >= 0:
		var p := shots[i]
		var hit := _shot_hits(p, pos, step)
		if hit or p.y - step < -20.0:
			shots[i] = shots[shots.size() - 1]
			shots.resize(shots.size() - 1)
			if hit:
				_on_hit(now)
				if defeated:
					return
		else:
			shots[i] = Vector2(p.x, p.y - step)
		i -= 1
	_update_items(now, dt, ppos)


func _on_hit(now: float) -> void:
	hits_total += 1
	flash = FLASH_TIME
	hp -= SHOT_DMG * power_mul
	if hp <= 0.0:
		hp = 0.0
		defeated = true
		defeat_t = now
		defeat_pos = pos
		shots.clear()
		items.clear()
		return
	if drops and _rng.randf() < DROP_CHANCE:
		var kind := _pick_kind()
		if kind != "":
			items.append({"kind": kind, "p": pos, "v": Vector2(_rng.randf_range(-40.0, 40.0), -ITEM_POP), "t": now})


## 落とすアイテムの種類(重みで選ぶ。強化は、今の段階と落ちている分を足して上限に届くものは選ばない)。
func _pick_kind() -> String:
	var total := 0.0
	var ok: Array = []
	for k in ITEMS:
		var mx: int = ITEMS[k].max
		if mx > 0:
			var have := level_of(k)
			for it in items:
				if it.kind == k:
					have += 1
			if have >= mx:
				continue
		ok.append(k)
		total += float(ITEMS[k].w)
	var r := _rng.randf() * total
	for k in ok:
		r -= float(ITEMS[k].w)
		if r <= 0.0:
			return k
	return ok.back() if not ok.is_empty() else ""


## 強化の今の段階(power / rate / wide)。
func level_of(kind: String) -> int:
	match kind:
		"power":
			return power
		"rate":
			return rate_lv
		"wide":
			return wide_lv
	return 0


## アイテムの効果を付ける(回復・ボムは記録だけ。GameSim が pick_events を見て行う)。
func apply_item(kind: String, p: Vector2, now: float) -> void:
	match kind:
		"power":
			power = mini(power + 1, ITEMS.power.max)
			power_mul = 1.0 + POWER_STEP * power
		"rate":
			rate_lv = mini(rate_lv + 1, ITEMS.rate.max)
		"wide":
			wide_lv = mini(wide_lv + 1, ITEMS.wide.max)
	pick_events.append({"kind": kind, "p": p, "t": now})


func _update_items(now: float, dt: float, ppos: Vector2) -> void:
	var lo := _rect.position.x + ITEM_X_INSET
	var hi := _rect.end.x - ITEM_X_INSET
	var pull := 1.0 - exp(-ITEM_X_PULL * dt)
	var i := items.size() - 1
	while i >= 0:
		var it: Dictionary = items[i]
		var v: Vector2 = it.v
		v.x *= exp(-2.0 * dt)
		v.y = minf(v.y + ITEM_GRAVITY * dt, ITEM_FALL)
		var p: Vector2 = it.p + v * dt
		p.x += (clampf(p.x, lo, hi) - p.x) * pull
		it.v = v
		it.p = p
		if p.distance_to(ppos) < ITEM_PICK_R:
			apply_item(str(it.kind), p, now)
			items.remove_at(i)
		elif p.y > ARENA.y + 20.0:
			items.remove_at(i)
		i -= 1
