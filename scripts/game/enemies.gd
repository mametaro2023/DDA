extends RefCounted
## サバイバル(S2): 自機の自動の連射・雑魚・経験値の玉。描画・音声に依存しない(GameSim が毎ステップ update を呼ぶ。ヘッドレスでも回せる)。
## docs/survival_plan.md の §4。
##
## ## 自機の弾
## 最初の発射から(休憩を除く)、自機から上へ自動で連射する(撃破 MOD のボスと同じ速さ・同じ列の並び。Boss は触らず、ここで別に持つ)。
## 攻撃力・連射・ワイド(列の数)は、サバイバルの強化で上がる(setup の params)。追尾弾(近くの雑魚へ曲がる)・貫通(雑魚を通り抜ける)・
## 誘爆(倒した雑魚が爆発して、まわりにダメージ)も、強化で付く。
##
## ## 雑魚
## 弾を撃たない・体当たりもない「的」。倒しても譜面の弾幕は変わらない(Lv の意味と、曲と弾の合い方を守る)。
## 出る時刻と場所は、譜面から決まる(乱数の種も譜面から決める = 同じ曲・同じ強化なら、毎回同じ):
##   ふつうの雑魚 … 最初〜最後の発射の間に、SPAWN_GAP 秒おき(±ゆらぎ)。場所は、その時刻にいちばん近い発射の位置の x と、
##                   盤面の上の帯(y)。上から降りてきて、左右にゆらぎながら少しずつ下がり、LIFE 秒たつと上へ抜けて消える。
##   スライダーに乗る雑魚 … スライダー(SLIDER_MIN 秒以上)の一部で、スライダーの発射位置の動きを、上の帯に写した道を進む。
##   硬い雑魚 … HARD_EVERY 体に 1 体くらい。HP と落とす経験値が多い(色と形が違う)。
## 休憩地帯では出ず、休憩に入ったら、いる雑魚は上へ抜ける。
## HP は、何曲目かで少しずつ増える(params.hp_mul)。
##
## ## 経験値
## 倒すと、経験値の玉を落とす(ふつう 1 個・硬い雑魚 HARD_XP 個。1 個 = 1)。玉は少し跳ねてから、ゆっくり落ちる。
## 自機から吸い寄せる範囲(MAGNET_R × params.magnet_mul)に入ると、自機へ寄ってきて取れる。画面の下へ落ちたら消える。
## 取った経験値は xp_got(params.xp_mul 倍)。レベルの計算は SurvivalRun(曲をまたいで続く)。

const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")

const ARENA := PatternGen.ARENA
# 自機の弾(撃破のボスと同じ)
const FIRE_INTERVAL := 1.0 / 15.0
const SHOT_SPEED := 1500.0
const SHOT_DMG := 1.0
const WIDE_OFFSETS := [[-7.0, 7.0], [-20.0, -7.0, 7.0, 20.0], [-33.0, -20.0, -7.0, 7.0, 20.0, 33.0]]
const POWER_STEP := 0.25
const RATE_STEP := 0.25
# 雑魚
const SPAWN_GAP := 1.5          # ふつうの雑魚の間隔(秒。1 分に 40 体。20 体では少なかった)
const SPAWN_JITTER := 0.5
const SLIDER_MIN := 0.6         # これより短いスライダーには乗せない
const SLIDER_SHARE := 0.35      # スライダーに乗る雑魚の、全体に対する割合の上限
const LIFE := 6.0               # ふつうの雑魚がいる秒(そのあと上へ抜ける)
const ENTER_T := 0.6            # 上から降りてくる秒
const LEAVE_T := 0.8            # 上へ抜ける秒
const BAND_TOP := 70.0          # 雑魚がいる帯(盤面の上)
const BAND_BOTTOM := 300.0
const DRIFT_DOWN := 10.0        # 少しずつ下がる速さ(px/s)
const SWAY := 36.0              # 左右のゆらぎ(px)
const R := 15.0                 # 当たり判定の半径(自機の弾)
const R_HARD := 20.0
const HP := 16.0                # ふつうの雑魚の HP(弾 1 発 = 1。攻撃力の強化なしで、2 列が当たり続けて約 0.5 秒)
const HP_HARD_MUL := 3.5
const HARD_EVERY := 8
const HARD_XP := 4
const FLASH_TIME := 0.06
# 経験値の玉
const ORB_POP := 140.0
const ORB_GRAVITY := 380.0
const ORB_FALL := 110.0
const MAGNET_R := 70.0
const MAGNET_SPEED := 620.0
const PICK_R := 18.0
# 強化(段ごと。0 段目 = なし)
const HOMING_TURN := [0.0, 4.0, 9.0]   # 追尾弾: 弾の向きが変わる速さ(rad/s)
const HOMING_RANGE := 420.0            # 追尾弾: この距離より近い、前にいる雑魚へ曲がる
const CHAIN_R := [0.0, 60.0, 85.0]     # 誘爆: 爆発の半径(px)
const CHAIN_DMG := [0.0, 0.5, 1.0]     # 誘爆: 爆発のダメージ(その曲のふつうの雑魚の HP に対する割合)

var shots := PackedVector2Array()
var shot_v := PackedVector2Array()     # 弾の向き(単位ベクトル。追尾弾でなければ真上)
var shot_pierce := PackedInt32Array()  # 弾が、あと何体通り抜けられるか(貫通)
var shot_last := PackedInt32Array()    # 弾が最後に当たった雑魚の id(通り抜けている間に、同じ雑魚に何度も当たらない。-1 = なし)
var enemies: Array = []          # {id, kind("normal"/"hard"/"slider"), hp, max_hp, t0, t1(いなくなる時刻), p, home, g(スライダー), flash, leaving_t}
var orbs: Array = []             # {p, v, t, pulled}
var kill_events: Array = []      # 倒した {p, t, hard, boom(誘爆の半径。0 = 爆発しない)}(古い順。読む側が、どこまで読んだかを覚える)
var pick_events: Array = []      # 取った玉 {p, t}
var xp_got := 0.0                # この曲で取った経験値(xp_mul を掛けたもの)
var kills := 0
var spawned := 0
var power_mul := 1.0
var rate_lv := 0
var wide_lv := 0
var magnet_mul := 1.0
var xp_mul := 1.0
var hp_mul := 1.0
var homing_lv := 0
var pierce_lv := 0
var chain_lv := 0

var _plan: Array = []            # 出る予定 {t, kind, x, y, g}(t の順)
var _plan_i := 0
var _breaks: Array = []
var _rect := Rect2(Vector2.ZERO, ARENA)
var _fire_from := -1.0
var _fire_acc := 0.0
var _next_id := 0


## events / gizmos / breaks: 弾幕(GameSim と同じもの)。rect: 自機が動ける範囲。fire_from / fire_to: 最初と最後の発射の時刻。
## params: {power, rate, wide, magnet, homing, pierce, chain(段), xp_mul, hp_mul}
func setup(events: Array, gizmos: Array, breaks: Array, rect: Rect2, fire_from: float, fire_to: float, params: Dictionary = {}) -> void:
	_breaks = breaks
	_rect = rect
	_fire_from = fire_from
	power_mul = 1.0 + POWER_STEP * int(params.get("power", 0))
	rate_lv = int(params.get("rate", 0))
	wide_lv = clampi(int(params.get("wide", 0)), 0, WIDE_OFFSETS.size() - 1)
	magnet_mul = 1.0 + 0.4 * int(params.get("magnet", 0))
	xp_mul = float(params.get("xp_mul", 1.0))
	hp_mul = float(params.get("hp_mul", 1.0))
	homing_lv = clampi(int(params.get("homing", 0)), 0, HOMING_TURN.size() - 1)
	pierce_lv = maxi(int(params.get("pierce", 0)), 0)
	chain_lv = clampi(int(params.get("chain", 0)), 0, CHAIN_R.size() - 1)
	_plan = make_plan(events, gizmos, breaks, fire_from, fire_to)
	_plan_i = 0


## 出る予定を作る(譜面から決まる)。戻り値: [{t, kind, x, y, g}](t の順)。
static func make_plan(events: Array, gizmos: Array, breaks: Array, fire_from: float, fire_to: float) -> Array:
	var out: Array = []
	if fire_from < 0.0 or fire_to <= fire_from:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("enemies_%d_%.3f_%.3f" % [events.size(), fire_from, fire_to])
	var fires: Array = []   # [t, pos]
	for e in events:
		if not e.shots.is_empty():
			fires.append([float(e.t), e.pos])
	# スライダーに乗る雑魚(長いスライダーの一部)
	var budget := int(ceil((fire_to - fire_from) / SPAWN_GAP))
	var riders := 0
	for g in gizmos:
		if g.kind != "slider" or float(g.end) - float(g.t) < SLIDER_MIN or _in(breaks, float(g.t)):
			continue
		if riders >= int(budget * SLIDER_SHARE) or rng.randf() > 0.5:
			continue
		riders += 1
		out.append({"t": float(g.t), "kind": "slider", "x": 0.0, "y": 0.0, "g": g})
	# ふつうの雑魚(スライダーに乗る雑魚のぶん、少し間をあける)
	var gap := SPAWN_GAP * (1.0 + float(riders) / maxf(float(budget), 1.0))
	var t := fire_from + 1.0
	var n := 0
	var fi := 0
	while t < fire_to - 1.0:
		var tt := t + rng.randf_range(-SPAWN_JITTER, SPAWN_JITTER)
		if not _in(breaks, tt):
			while fi + 1 < fires.size() and float(fires[fi + 1][0]) <= tt:
				fi += 1
			var src: Vector2 = fires[fi][1] if not fires.is_empty() else ARENA * 0.5
			n += 1
			var hard := n % HARD_EVERY == 0
			var x := clampf(src.x + rng.randf_range(-60.0, 60.0), 50.0, ARENA.x - 50.0)
			var y := lerpf(BAND_TOP, BAND_BOTTOM, clampf(src.y / ARENA.y, 0.0, 1.0))
			out.append({"t": tt, "kind": "hard" if hard else "normal", "x": x, "y": y, "g": null})
		t += gap
	out.sort_custom(func(a, b): return a.t < b.t)
	return out


static func _in(breaks: Array, t: float) -> bool:
	for b in breaks:
		if t >= float(b[0]) and t <= float(b[1]):
			return true
	return false


## スライダーの発射位置を、上の帯に写した位置。
static func rider_pos(g: Dictionary, now: float) -> Vector2:
	var p := GameSim.slider_emitter(g, clampf(now, float(g.t), float(g.end)))
	return Vector2(clampf(p.x, 40.0, ARENA.x - 40.0), lerpf(BAND_TOP, BAND_BOTTOM, clampf(p.y / ARENA.y, 0.0, 1.0)))


## 雑魚の当たり判定の半径。
static func radius_of(e: Dictionary) -> float:
	return R_HARD if e.kind == "hard" else R


func fire_interval() -> float:
	return FIRE_INTERVAL / (1.0 + RATE_STEP * rate_lv)


## 1 ステップ進める。resting: 休憩地帯の中(撃たない・雑魚は出ない、いる雑魚は抜ける)。
func update(now: float, dt: float, ppos: Vector2, resting: bool) -> void:
	_spawn(now, resting)
	# 自動の連射
	if _fire_from >= 0.0 and now >= _fire_from and not resting:
		_fire_acc += dt
		var iv := fire_interval()
		while _fire_acc >= iv:
			_fire_acc -= iv
			for ox in WIDE_OFFSETS[wide_lv]:
				shots.append(ppos + Vector2(ox, -10.0))
				shot_v.append(Vector2.UP)
				shot_pierce.append(pierce_lv)
				shot_last.append(-1)
	else:
		_fire_acc = FIRE_INTERVAL
	_move_enemies(now, dt, resting)
	# 自機の弾を進めて、雑魚との当たりを調べる(このステップで進んだ線分と、雑魚の円)。
	# 雑魚の位置・半径・id は、いちど数の並びにしてから調べる(弾の数 × 雑魚の数だけ、辞書を引かないように)
	var step := SHOT_SPEED * dt
	var turn: float = HOMING_TURN[homing_lv] * dt
	var ep := PackedVector2Array()
	var er := PackedFloat32Array()
	var eid := PackedInt32Array()
	_pack_alive(ep, er, eid)
	var i := shots.size() - 1
	while i >= 0:
		var p := shots[i]
		var v := shot_v[i]
		if turn > 0.0:
			v = _steer(p, v, turn, ep)
			shot_v[i] = v
		var d := v * step
		var hit := -1
		var last := shot_last[i]
		for k in range(ep.size()):
			if eid[k] != last and _seg_hits(p, d, ep[k], er[k]):
				hit = eid[k]
				break
		var np := p + d
		var gone := np.y < -20.0 or np.y > ARENA.y + 20.0 or np.x < -20.0 or np.x > ARENA.x + 20.0
		if hit >= 0:
			if shot_pierce[i] > 0:   # 貫通: 通り抜けて、次の雑魚へ
				shot_pierce[i] -= 1
				shot_last[i] = hit
			else:
				gone = true
			var k := _index_of(hit)
			if k >= 0 and _damage(k, SHOT_DMG * power_mul, now):   # 倒れた(誘爆も含めて、雑魚が減った)ので、並びを作り直す
				_pack_alive(ep, er, eid)
		if gone:
			var j := shots.size() - 1
			shots[i] = shots[j]
			shot_v[i] = shot_v[j]
			shot_pierce[i] = shot_pierce[j]
			shot_last[i] = shot_last[j]
			shots.resize(j)
			shot_v.resize(j)
			shot_pierce.resize(j)
			shot_last.resize(j)
		else:
			shots[i] = np
		i -= 1
	_update_orbs(now, dt, ppos)


## 当たる雑魚(上へ抜けていないもの)の位置・半径・id を、数の並びにする。
func _pack_alive(ep: PackedVector2Array, er: PackedFloat32Array, eid: PackedInt32Array) -> void:
	ep.resize(0)
	er.resize(0)
	eid.resize(0)
	for e in enemies:
		if e.leaving_t < 0.0:
			ep.append(e.p)
			er.append(radius_of(e))
			eid.append(int(e.id))


## 線分 p → p + d が、中心 c・半径 r の円に触れるか。
static func _seg_hits(p: Vector2, d: Vector2, c: Vector2, r: float) -> bool:
	var dd := d.length_squared()
	var u := 0.0 if dd <= 0.0 else clampf((c - p).dot(d) / dd, 0.0, 1.0)
	return (p + d * u).distance_squared_to(c) < r * r


## 追尾弾: 向き v を、前にいて HOMING_RANGE より近い、いちばん近い雑魚へ、turn(rad)まで回す。
static func _steer(p: Vector2, v: Vector2, turn: float, ep: PackedVector2Array) -> Vector2:
	var best := HOMING_RANGE * HOMING_RANGE
	var to := Vector2.ZERO
	for c in ep:
		var w := c - p
		var d2 := w.length_squared()
		if d2 < best and w.dot(v) > 0.0:
			best = d2
			to = w
	if to == Vector2.ZERO:
		return v
	var a := v.angle_to(to)
	return v.rotated(clampf(a, -turn, turn))


func _index_of(id: int) -> int:
	for k in range(enemies.size()):
		if int(enemies[k].id) == id:
			return k
	return -1


func _spawn(now: float, resting: bool) -> void:
	while _plan_i < _plan.size() and float(_plan[_plan_i].t) <= now:
		var s: Dictionary = _plan[_plan_i]
		_plan_i += 1
		if resting or now - float(s.t) > 1.0:   # 休憩中・飛ばした(イントロのスキップなど)ものは出さない
			continue
		var hard: bool = s.kind == "hard"
		var mhp := HP * hp_mul * (HP_HARD_MUL if hard else 1.0)
		var home := Vector2(float(s.x), float(s.y)) if s.g == null else rider_pos(s.g, float(s.t))
		var t1 := float(s.t) + LIFE if s.g == null else float(s.g.end) + 0.5
		enemies.append({"id": _next_id, "kind": s.kind, "hp": mhp, "max_hp": mhp, "t0": float(s.t), "t1": t1,
			"p": Vector2(home.x, -30.0), "home": home, "g": s.g, "flash": 0.0, "leaving_t": -1.0, "seed": float(_next_id % 7)})
		_next_id += 1
		spawned += 1


func _move_enemies(now: float, dt: float, resting: bool) -> void:
	var i := enemies.size() - 1
	while i >= 0:
		var e: Dictionary = enemies[i]
		e.flash = maxf(float(e.flash) - dt, 0.0)
		if e.leaving_t < 0.0 and (now >= float(e.t1) or resting):
			e.leaving_t = now
		var age := now - float(e.t0)
		var home: Vector2 = e.home
		var target: Vector2
		if e.g != null:
			target = rider_pos(e.g, now)
		else:
			target = home + Vector2(sin(age * 0.9 + float(e.seed)) * SWAY, DRIFT_DOWN * age)
		var p: Vector2
		if age < ENTER_T:   # 上から降りてくる(速く来て、ゆっくり止まる)
			var u := age / ENTER_T
			p = Vector2(target.x, -30.0).lerp(target, 1.0 - pow(1.0 - u, 3.0))
		else:
			p = target
		if e.leaving_t >= 0.0:   # 上へ抜ける
			var k := (now - float(e.leaving_t)) / LEAVE_T
			if k >= 1.0:
				enemies.remove_at(i)
				i -= 1
				continue
			p = p.lerp(Vector2(p.x, -40.0), k * k)
		e.p = p
		i -= 1


## enemies[k] に dmg を与える。戻り値: 倒れたか。
func _damage(k: int, dmg: float, now: float) -> bool:
	var e: Dictionary = enemies[k]
	e.flash = FLASH_TIME
	e.hp = float(e.hp) - dmg
	if float(e.hp) > 0.0:
		return false
	var hard: bool = e.kind == "hard"
	var c: Vector2 = e.p
	var boom: float = CHAIN_R[chain_lv]
	kills += 1
	kill_events.append({"p": c, "t": now, "hard": hard, "boom": boom})
	var n := HARD_XP if hard else 1
	for q in range(n):
		var ang := -PI * 0.5 + (float(q) - (n - 1) * 0.5) * 0.5
		orbs.append({"p": c, "v": Vector2.from_angle(ang) * ORB_POP, "t": now, "pulled": false})
	enemies.remove_at(k)
	if boom > 0.0:   # 誘爆: まわりの雑魚にダメージ(倒れた雑魚も、また爆発する)
		var ids: Array = []
		for o in enemies:
			if o.leaving_t < 0.0 and (o.p as Vector2).distance_to(c) < boom + radius_of(o):
				ids.append(int(o.id))
		var bd := HP * hp_mul * float(CHAIN_DMG[chain_lv])
		for id in ids:
			var j := _index_of(id)
			if j >= 0:
				_damage(j, bd, now)
	return true


func _update_orbs(now: float, dt: float, ppos: Vector2) -> void:
	var mr := MAGNET_R * magnet_mul
	var i := orbs.size() - 1
	while i >= 0:
		var o: Dictionary = orbs[i]
		var p: Vector2 = o.p
		if o.pulled or p.distance_to(ppos) < mr:   # 吸い寄せる範囲に入ったら、自機へ寄る(一度寄り始めたら、離れても寄り続ける)
			o.pulled = true
			p = p.move_toward(ppos, MAGNET_SPEED * dt)
		else:
			var v: Vector2 = o.v
			v.x *= exp(-2.0 * dt)
			v.y = minf(v.y + ORB_GRAVITY * dt, ORB_FALL)
			o.v = v
			p += v * dt
		o.p = p
		if p.distance_to(ppos) < PICK_R:
			xp_got += xp_mul
			pick_events.append({"p": p, "t": now})
			orbs.remove_at(i)
		elif p.y > ARENA.y + 20.0:
			orbs.remove_at(i)
		i -= 1


## 曲を終えたとき: 落ちている玉を、すべて取ったことにする。
func sweep() -> void:
	xp_got += float(orbs.size()) * xp_mul
	orbs.clear()
	shots.clear()
	shot_v.clear()
	shot_pierce.clear()
	shot_last.clear()
