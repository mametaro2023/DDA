extends RefCounted
## ゲーム進行(自機・イベント発射・被弾・ゲージ・スコア)。描画/音声に依存しないのでヘッドレスでも回せる。
##
## ## ゲージ制
## 弾に当たっている間は継続ダメージ。ゲージ満タンは GAUGE_DRAIN_TIME(250ms)ぶんの被弾に相当する。
## ゲージが GAUGE_LOW_THRESHOLD(20%)以下のときは被ダメージが半分になる(連続被弾で 0 になるまで合計約 300ms)。
## ゲージが 0 になったらゲームオーバー(練習モードでは 0 でも続行)。
## 当たっていないときは、ごくわずかに回復する(GAUGE_REGEN /秒)。
##
## ## スコア
##   ノーダメージなら SCORE_BASE(1,000,000)。これにグレイズのボーナス(SCORE_GRAZE = 最大 3%)を足し、
##   被ダメージ係数を「掛け算」して最終点にする:
##       最終点 = (SCORE_BASE + SCORE_GRAZE * (1 - exp(-グレイズ数 / graze_tau))) * 被ダメージ係数
##   グレイズのボーナスは SCORE_GRAZE(3 万点)に漸近する: 増えるほど上乗せは小さくなり、無限にグレイズしても 3 万点には届かない
##       被ダメージ係数 = exp(-累計ダメージ / damage_tau)     ← 1 から始まり 0 に漸近する(0 にはならない)
##   damage_tau = DAMAGE_TAU × max(弾が飛んでいる時間 ÷ DAMAGE_REF_TIME, 1)。長い曲ほど累計ダメージの絶対値が大きくなるので、
##   弾が飛んでいる時間(最初〜最後の発射の間から休憩地帯を除いたもの)に比例して τ を伸ばし、長い曲が不利にならないようにする
##   (基準 DAMAGE_REF_TIME = 120 秒より短い譜面は従来どおり)。
##   累計ダメージの単位は「ゲージ満タン = 1」。回復しても累計は減らない(いったん下がった係数は戻らない)。
##   ゲームオーバーのときは常に 0 点(スコアなし)。クリアしたときだけスコアが残る。
##   プレイ中の表示は、その「クリアした場合の点数(score_potential)」に「スコア進捗(score_progress)」を掛けたもの:
##       score = score_potential * score_progress
##   スコア進捗 = これまでに発射した弾数 / 曲全体で発射する弾数(0 → 1)。弾が発射されるたびに、弾 1 発ぶんずつ増える。
##   最初のノーツまでのイントロでは増えず、休憩地帯(発射なし。念のため休憩中の発射も数えない)でも増えない。
##   クリアした瞬間に 1 になり、score が最終点になる。
##   被ダメージ係数は全体にかかるので、ダメージを受けるとその時点の score も下がる。
##
## ## 休憩地帯(譜面の Break)
## スコアが上がる(グレイズ)ことも、ゲージが回復することもない。
## 休憩に入って、自機の近くに弾がなく、自機に接近している弾もない状態(BulletField.is_calm。近く = SAFE_NEAR_R 以内)になったら、弾をすべて消す。
## そのときから休憩が終わるまでのカウントダウンを出す(break_clear_t / break_end_t。表示は game_screen)。
##
## ## クリア
## 最後の弾幕を撃ち終えたあと、自機の近くに弾がなく、接近している弾もない状態(休憩中と同じ)になったら、弾をすべて消してクリアにする
## (弾が残り続ける場合の保険として、撃ち終えてから CLEAR_TIMEOUT 秒でクリア)。
##
## ## MOD
## setup() の mods(Mods.params の結果)で、ゲージ満タンぶんの被弾時間(drain_time)、低体力の半減の有無(low_protect)、
## ベーススコアの倍率(score_mul)、自機サイズ(player_scale)が変わる。弾サイズ・弾速・弾数・再生速度は、
## 弾を作る側(Mods.apply)で events に掛けてから渡す。

const BulletField = preload("res://scripts/game/bullet_field.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")

const ARENA := PatternGen.ARENA
const PLAYER_SPEED := 380.0      # キーボード
const PLAYER_SLOW := 160.0
const MOUSE_SLOW_FACTOR := 0.3   # マウスの低速時に移動量へ掛ける倍率
const PLAYER_HIT_R := 3.5
const PLAYER_MARGIN := 8.0
const SAFE_RADIUS := 100.0       # 発射点にこの距離以内に自機がいたら弾は一時無害
const SAFE_GRACE_PX := 140.0

const GAUGE_DRAIN_TIME := 0.25   # ゲージ満タンぶんの被弾時間(通常時の被ダメージ速度)
const GAUGE_LOW_THRESHOLD := 0.2 # ゲージがこれ以下のとき、
const GAUGE_LOW_FACTOR := 0.5    # 被ダメージはこの倍率になる
const GAUGE_REGEN := 0.02        # 被弾していないときの回復(ゲージ全体に対する割合 / 秒)
const CLEAR_TIMEOUT := 8.0       # 最後の弾を撃ってからこの秒数たっても弾が残っていたら、消してクリアにする
## 自機の周りが「落ち着いている」とみなす範囲(休憩の一掃・クリア判定): 近くの弾は SAFE_NEAR_R 以内、接近中の弾は SAFE_LOOK_T 秒以内に自機から SAFE_APPROACH_R 以内を通る弾
const SAFE_NEAR_R := 120.0
const SAFE_APPROACH_R := 50.0
const SAFE_LOOK_T := 3.0
const EPISODE_GAP := 0.15       # これ以上被弾が途切れたら、次の被弾は「別の被弾」として数える

const SCORE_BASE := 1000000.0
## ランク(クリアしたときだけ)。被弾 0 回なら SS。それ以外は「達成率 = 最終点 ÷ ベーススコア(MOD の倍率を含む)」で決める。
## MOD の倍率を打ち消した率なので、練習(×0.5)や +6% の MOD でランクが上下しない。達成率 = 被ダメージ係数 + グレイズのボーナス分。
const RANK_TABLE := [["S", 0.95], ["A", 0.85], ["B", 0.70], ["C", 0.55], ["D", 0.40]]   # これ未満は F
## 発射地点の印(暗闇 MOD 用)を残す秒数
const FIRE_MARK_TIME := 0.9
## 被ダメージ係数の減衰の時定数(累計ダメージ = この値で係数が 1/e ≒ 0.37 になる。ゲージ満タン = 1)
const DAMAGE_TAU := 3.0
## damage_tau を伸ばし始める、弾が飛んでいる時間の基準(秒)。これ以下の譜面の τ は DAMAGE_TAU のまま
const DAMAGE_REF_TIME := 120.0
const SCORE_GRAZE := 30000.0     # グレイズのボーナスの最大(3%)
## グレイズのボーナスの立ち上がりの目安 graze_tau = 発射イベント数 × この係数(下限 GRAZE_TAU_MIN)。
## グレイズ数が graze_tau で最大の約 63%、2 倍で約 86%、3 倍で約 95%(3 万点には漸近するだけで届かない)
const GRAZE_TAU_PER_EVENT := 0.15
const GRAZE_TAU_MIN := 10.0

var field: Node2D
var events: Array = []
var gizmos: Array = []
var breaks: Array = []          # [[開始秒, 終了秒], ...] 休憩地帯
var warn_lead := 0.6
var practice := false
## 発射地点の印を記録するか(暗闇 MOD。弾が見えなくても、どこから撃ったかを表示するため)
var track_fires := false
var recent_fires: Array = []     # {pos, t, color}: 発射から FIRE_MARK_TIME 秒だけ残る
## 開発用: true なら被弾しない(テスト用。スコア表示の検証などで、ダメージの影響を除きたいときに使う)
var debug_invincible := false
var end_time := 0.0
## MOD で変わる設定(既定は MOD なし)
var drain_time := GAUGE_DRAIN_TIME    # ゲージ満タンぶんの被弾時間(秒)
var low_protect := true               # ゲージ 20% 以下で被ダメージが半分になるか
var score_base := SCORE_BASE          # ベーススコア(MOD で増える)
var player_scale := 1.0                # 自機サイズの倍率(MOD)
var player_r := PLAYER_HIT_R          # 自機の当たり判定半径(= PLAYER_HIT_R × player_scale)
## 最初に弾を撃つイベントの時刻(なければ -1)。イントロのスキップ先の基準
var first_fire_time := -1.0

var player_pos := Vector2(ARENA.x * 0.5, ARENA.y * 0.85)
var slow := false
var gauge := 1.0                # 0..1
var hit_now := false            # 今このステップで弾に当たっているか
var hit_time := 0.0             # 累計被弾時間(秒)
var damage_total := 0.0         # 累計ダメージ(ゲージ満タン = 1。回復は差し引かない)
var hits := 0                   # 被弾の回数(連続した被弾は 1 回)
var graze := 0                  # スコアに数えたグレイズ(休憩地帯のぶんは数えない)
var score := 0.0                # 今の表示点数 = score_potential × score_progress(ゲームオーバーなら 0)
var score_potential := 0.0      # 今クリアした場合の最終点(= score_gross × damage_factor)
var progress := 0.0             # 曲の進行率 0..1(時間。休憩地帯でも進む)
var score_progress := 0.0       # スコア用の進行率 0..1(= 発射した弾数 / 全弾数)
var bullets_fired := 0          # ここまでに発射した弾数(休憩地帯の発射は数えない)
var bullets_total := 0          # 曲全体で発射する弾数(同上)
var score_gross := 0.0          # 被ダメージ係数を掛ける前の点数(score_base + グレイズのボーナス)
var score_graze := 0.0          # グレイズのボーナス
var damage_factor := 1.0        # 被ダメージ係数(1 → 0 に漸近)
var damage_tau := DAMAGE_TAU   # 被ダメージ係数の時定数(曲の長さに応じて伸びる。setup で決まる)
var active_time := 0.0          # 弾が飛んでいる時間(秒)= 最初〜最後の発射の間から休憩地帯を除いたもの
var finished := false
var failed := false
## 休憩中に弾を一掃した時刻と、その休憩の終わりの時刻(一掃していないとき break_clear_t = -1)
var break_clear_t := -1.0
var break_end_t := 0.0
var death_pos := Vector2.ZERO
var death_time := 0.0

## このステップで起きたこと(描画/音声側が読む)
var sfx_queue: Array = []
var just_hit := false           # 新しい被弾が始まったステップ

var active_warns: Array = []
var active_gizmos: Array = []

var _prev_pos := Vector2.ZERO  # このステップ開始時の自機位置(移動経路上の当たり判定用)
var _ev_idx := 0
var _warn_idx := 0
var _giz_idx := 0
var _no_hit_time := 1.0        # 最後に被弾してからの経過秒
var _graze_tau := GRAZE_TAU_MIN
var _all_fired_t := -1.0       # 最後の弾幕を撃ち終えた時刻(まだなら -1)


func setup(bullet_field: Node2D, gen: Dictionary, end_t: float, practice_mode: bool, mods := {}) -> void:
	field = bullet_field
	field.clear()
	events = gen.events
	gizmos = gen.gizmos
	breaks = gen.get("breaks", [])
	warn_lead = gen.warn_lead
	end_time = end_t
	practice = practice_mode or bool(mods.get("practice", false))
	track_fires = bool(mods.get("dark", false))
	drain_time = float(mods.get("drain_time", GAUGE_DRAIN_TIME))
	low_protect = bool(mods.get("low_protect", true))
	score_base = SCORE_BASE * float(mods.get("score_mul", 1.0))
	player_scale = float(mods.get("player_scale", 1.0))
	player_r = PLAYER_HIT_R * player_scale
	_graze_tau = maxf(GRAZE_TAU_MIN, GRAZE_TAU_PER_EVENT * events.size())
	bullets_total = 0
	first_fire_time = -1.0
	var last_fire := -1.0
	for e in events:
		if e.shots.is_empty():
			continue
		if first_fire_time < 0.0:
			first_fire_time = e.t
		last_fire = e.t
		if not in_break(e.t):
			for s in e.shots:
				bullets_total += int(s.n)
	# 弾が飛んでいる時間 → 被ダメージ係数の時定数
	active_time = 0.0
	if first_fire_time >= 0.0 and last_fire > first_fire_time:
		active_time = last_fire - first_fire_time
		for b in breaks:
			active_time -= maxf(minf(float(b[1]), last_fire) - maxf(float(b[0]), first_fire_time), 0.0)
	damage_tau = DAMAGE_TAU * maxf(active_time / DAMAGE_REF_TIME, 1.0)
	_update_score()


## 休憩地帯の中か。
func in_break(now: float) -> bool:
	for b in breaks:
		if now >= b[0] and now <= b[1]:
			return true
	return false


## キーボード操作。now: 曲時間(秒)、dt: 経過秒、move: 入力方向(未正規化可)
func step(now: float, dt: float, move: Vector2, slow_mode: bool) -> void:
	if finished:
		return
	slow = slow_mode
	_prev_pos = player_pos
	if move != Vector2.ZERO:
		var spd := PLAYER_SLOW if slow else PLAYER_SPEED
		_move_player(player_pos + move.normalized() * spd * dt)
	_update(now, dt)


## マウス操作。delta_px: このフレームのカーソル移動量(アリーナ座標系、感度・低速の倍率は適用済み)。
func step_relative(now: float, dt: float, delta_px: Vector2, slow_mode: bool) -> void:
	if finished:
		return
	slow = slow_mode
	_prev_pos = player_pos
	_move_player(player_pos + delta_px)
	_update(now, dt)


func _move_player(p: Vector2) -> void:
	var m := PLAYER_MARGIN * player_scale
	player_pos = p.clamp(Vector2(m, m), ARENA - Vector2(m, m))


func _update(now: float, dt: float) -> void:
	sfx_queue.clear()
	just_hit = false
	# 予兆の開始
	while _warn_idx < events.size() and events[_warn_idx].t - warn_lead <= now:
		var e: Dictionary = events[_warn_idx]
		if e.warn and e.t > now:
			active_warns.append(e)
		_warn_idx += 1
	# ギズモ(スライダー軌道/スピナー)の開始
	while _giz_idx < gizmos.size() and gizmos[_giz_idx].t - warn_lead <= now:
		active_gizmos.append(gizmos[_giz_idx])
		_giz_idx += 1
	# 発射
	while _ev_idx < events.size() and events[_ev_idx].t <= now:
		_fire(events[_ev_idx], now)
		_ev_idx += 1
	# 発射地点の印の掃除
	if not recent_fires.is_empty():
		recent_fires = recent_fires.filter(func(f): return now - f.t < FIRE_MARK_TIME)
	# 掃除
	if not active_warns.is_empty():
		active_warns = active_warns.filter(func(e): return e.t > now)
	if not active_gizmos.is_empty():
		active_gizmos = active_gizmos.filter(func(g): return g.end + 0.3 > now)

	# 弾(当たっている間は毎ステップダメージ。弾は消えない)
	field.update(dt, player_pos, player_r, true, _prev_pos)
	var resting := in_break(now)  # 休憩地帯: スコアは上がらず、ゲージも回復しない
	_update_break_wipe(now, resting)
	if not resting:
		graze += field.graze_count
	hit_now = field.hit and not debug_invincible
	if hit_now:
		if _no_hit_time >= EPISODE_GAP:
			hits += 1
			just_hit = true
		_no_hit_time = 0.0
		hit_time += dt
		# ゲージが少ないとき(20% 以下)は被ダメージが半分(MOD で無効になる)
		var factor := GAUGE_LOW_FACTOR if (low_protect and gauge <= GAUGE_LOW_THRESHOLD) else 1.0
		var dmg := dt / drain_time * factor
		damage_total += dmg
		gauge -= dmg
	else:
		_no_hit_time += dt
		if not resting:
			gauge = minf(gauge + GAUGE_REGEN * dt, 1.0)

	# 進行率: 曲の進行(時間)とは別に、スコア用の進行率は「発射した弾数」で進める
	progress = clampf(now / maxf(end_time, 0.001), 0.0, 1.0)
	score_progress = clampf(float(bullets_fired) / float(maxi(bullets_total, 1)), 0.0, 1.0) if bullets_total > 0 else 0.0
	_update_score()

	if gauge <= 0.000001:
		gauge = 0.0
		if not practice:
			failed = true
			finished = true
			death_pos = player_pos
			death_time = now
			_update_score()  # ゲームオーバーは 0 点
			return
	if _check_clear(now):
		field.clear()
		finished = true
		progress = 1.0
		score_progress = 1.0  # クリア: 表示点数が最終点になる
		break_clear_t = -1.0
		_update_score()


## 休憩中、残った弾が当たりえない状態になったら一掃して、カウントダウンを始める。休憩が終わったら状態を戻す。
func _update_break_wipe(now: float, resting: bool) -> void:
	if not resting:
		break_clear_t = -1.0
		return
	if break_clear_t >= 0.0:
		return
	if _all_safe():
		field.clear()
		break_clear_t = now
		for b in breaks:
			if now >= b[0] and now <= b[1]:
				break_end_t = b[1]
				break


## クリアの条件: 最後の弾幕を撃ち終え(予兆も終わり)、弾が当たりえない状態になった(または撃ち終えて CLEAR_TIMEOUT 秒たった)。
func _check_clear(now: float) -> bool:
	if events.is_empty():
		return now >= end_time
	if _ev_idx < events.size() or not active_warns.is_empty():
		return false
	if _all_fired_t < 0.0:
		_all_fired_t = now
	return now - _all_fired_t >= CLEAR_TIMEOUT or _all_safe()


## 残った弾がどれも「当たらない」か: 自機の近くに弾がなく、自機に接近している弾もない(BulletField.is_calm)。
func _all_safe() -> bool:
	return field.is_calm(player_pos, player_r, SAFE_NEAR_R, SAFE_APPROACH_R, SAFE_LOOK_T)


## 今の点数を計算し直す。ゲームオーバーなら 0。
func _update_score() -> void:
	damage_factor = exp(-damage_total / damage_tau)
	if failed:
		score_gross = 0.0
		score_graze = 0.0
		score_potential = 0.0
		score = 0.0
		return
	score_graze = SCORE_GRAZE * (1.0 - exp(-float(graze) / _graze_tau))   # 3 万点に漸近(届かない)
	score_gross = score_base + score_graze
	score_potential = score_gross * damage_factor
	score = score_potential * score_progress


func _fire(e: Dictionary, now: float) -> void:
	var late := maxf(now - e.t, 0.0)
	var pos: Vector2 = e.pos
	var grace := SAFE_GRACE_PX if player_pos.distance_to(pos) < SAFE_RADIUS else 0.0
	for s in e.shots:
		var base: float = s.a0
		if s.aim:
			base += (player_pos - pos).angle()
		for i in range(s.n):
			var v: Vector2 = Vector2.from_angle(PatternGen.shot_angle(s, base, i)) * s.speed
			field.add(pos + v * late, v, s.size, s.color, grace, s.turn)
	if track_fires and not e.shots.is_empty():
		recent_fires.append({"pos": pos, "t": e.t, "color": e.shots[0].color})
	if not e.shots.is_empty():
		break_clear_t = -1.0   # 休憩中に新しい弾が撃たれたら、安全になるまで一掃を待ち直す
	if not in_break(e.t):
		for s in e.shots:
			bullets_fired += int(s.n)
	if e.sfx != "":
		sfx_queue.append(e.sfx)


## ランク。failed(ゲームオーバー)なら "-"(ランクなし)。ノーミス(hits == 0)は SS、それ以外は達成率(score / score_base)で S〜F。
static func rank_of(failed: bool, hits: int, score: float, score_base: float) -> String:
	if failed:
		return "-"
	if hits == 0:
		return "SS"
	var ratio := score / maxf(score_base, 1.0)
	for r in RANK_TABLE:
		if ratio >= float(r[1]):
			return r[0]
	return "F"


## ギズモ上のエミッタ位置(スライダーは往復を考慮)。
static func slider_emitter(g: Dictionary, now: float) -> Vector2:
	var pts: PackedVector2Array = g.points
	var span: float = g.span
	var u := 0.0 if span <= 0.0 else clampf((now - g.t) / span, 0.0, float(g.repeats))
	var slide := int(floor(u))
	var frac := u - slide
	if slide >= g.repeats:
		slide = g.repeats - 1
		frac = 1.0
	if slide % 2 == 1:
		frac = 1.0 - frac
	return _polyline_at(pts, frac)


static func _polyline_at(pts: PackedVector2Array, frac: float) -> Vector2:
	if pts.size() == 1:
		return pts[0]
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	var target := total * frac
	var acc := 0.0
	for i in range(1, pts.size()):
		var seg := pts[i].distance_to(pts[i - 1])
		if acc + seg >= target and seg > 0.0:
			return pts[i - 1].lerp(pts[i], (target - acc) / seg)
		acc += seg
	return pts[pts.size() - 1]
