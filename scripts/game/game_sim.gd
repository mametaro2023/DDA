extends RefCounted
## ゲーム進行(自機・イベント発射・被弾・ゲージ・スコア)。描画/音声に依存しないのでヘッドレスでも回せる。
##
## ## ゲージ制
## 弾に当たっている間は継続ダメージ。ゲージ満タンは GAUGE_DRAIN_TIME(250ms)ぶんの被弾に相当する。
## ゲージが GAUGE_LOW_THRESHOLD(20%)以下のときは被ダメージが半分になる(連続被弾で 0 になるまで合計約 300ms)。
## ゲージが 0 になったらゲームオーバー(練習モードでは 0 でも続行)。
## 当たっていないときは、ごくわずかに回復する(GAUGE_REGEN /秒)。
##
## ## 危険エリア(デバフ)
## 盤面を 3×3 の 9 マスに分け、特定の小節ごとに、いくつかのマス(1〜8)が「危険エリア」になる(PatternGen が譜面から決めて、gen.zones で渡す。
## 数・種類は難易度などに応じて変わる)。入っている間、そのマスのデバフを受ける:
##   鈍足(slow): 移動が ZONE_SLOW 倍 / 脆弱(fragile): 被ダメージが ZONE_FRAGILE 倍 / 毒(poison): ゲージが ZONE_POISON_DRAIN(/秒)で減る / 巨大(big): 自機の当たり判定が ZONE_BIG 倍
## 弾幕には手を入れない(自機が受けるものだけ)。休憩地帯では効かない。練習モードでは、毒のゲージ減少だけ効かない。

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
## 猶予は「不意打ち」を防ぐためのもの。同じ場所(スピナーの中央・重なったノーツ・スライダーの発射点など)で待ち続けて、近くから撃たれ続ける間は、
## 猶予は最初の GRACE_STREAK_MAX 秒ぶんの発射にだけつける(それより後に近くで撃たれた弾は、ふつうに当たる)。近くでの発射が GRACE_STREAK_GAP 秒より空いたら、数え直す。
## (猶予がずっと続くと、スピナーの間は中央に居座るだけで、すべて避けられてしまう)
const GRACE_STREAK_MAX := 0.6
const GRACE_STREAK_GAP := 0.5

const GAUGE_DRAIN_TIME := 0.25   # ゲージ満タンぶんの被弾時間(通常時の被ダメージ速度)
const GAUGE_LOW_THRESHOLD := 0.2 # ゲージがこれ以下のとき、
const GAUGE_LOW_FACTOR := 0.5    # 被ダメージはこの倍率になる
const GAUGE_REGEN := 0.015       # 被弾していないときの回復(ゲージ全体に対する割合 / 秒)
## 実際の弾・自機の大きさの倍率(見た目と当たり判定)。値は PatternGen が持つ(Lv の計算の危険半径と、同じ値を使うため)。
const BULLET_SIZE_MUL := PatternGen.BULLET_SIZE_MUL
const PLAYER_SIZE_MUL := PatternGen.PLAYER_SIZE_MUL
const CLEAR_TIMEOUT := 8.0       # 最後の弾を撃ってからこの秒数たっても弾が残っていたら、消してクリアにする
## 自機の周りが「落ち着いている」とみなす範囲(休憩の一掃・クリア判定): 近くの弾は SAFE_NEAR_R 以内、接近中の弾は SAFE_LOOK_T 秒以内に自機から SAFE_APPROACH_R 以内を通る弾
const SAFE_NEAR_R := 120.0
const SAFE_APPROACH_R := 50.0
const SAFE_LOOK_T := 3.0
const EPISODE_GAP := 0.15       # これ以上被弾が途切れたら、次の被弾は「別の被弾」として数える
const ZONE_SLOW := 0.45            # 鈍足: 移動の倍率
const ZONE_FRAGILE := 2.0          # 脆弱: 被ダメージの倍率
const ZONE_BIG := 1.8              # 巨大: 自機の当たり判定の倍率(見た目の当たり判定の点も大きくなる)
const ZONE_POISON_DRAIN := 0.10    # 毒: ゲージの減る速さ(ゲージ全体に対する割合 / 秒)

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

## 結果画面の体力グラフ用の記録: 曲の時刻 0 から GAUGE_LOG_STEP 秒ごとのゲージ(0..1)。i 番目は i × GAUGE_LOG_STEP 秒のとき
const GAUGE_LOG_STEP := 0.25

## 判定の計算(_update)を行った回数の通算(FPS 表示の「判定 /s」用)
static var steps_total := 0

var field: Node2D
var events: Array = []
var gizmos: Array = []
var breaks: Array = []          # [[開始秒, 終了秒], ...] 休憩地帯
var warn_lead := 0.6
var practice := false
var zones: Array = []              # 危険エリアの予定(gen.zones。時刻順)
var zone_debuff := ""              # いま自機が受けているデバフ("" = なし)
var hit_mult := 1.0                # 巨大のデバフ中の、当たり判定の倍率(描画の点の大きさにも使う)
var contact_extra := 0.0           # 参加者: まだホストへ送っていない、デバフによる追加ダメージ(被弾時間に換算した秒)
var _zone_i := 0
var _last_fire := -1.0
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
var gauge_log := PackedFloat32Array()   # ゲージの推移(GAUGE_LOG_STEP 秒ごと)
var hit_log := PackedFloat32Array()     # 自分が新しく被弾した時刻(秒)
var log_end_t := 0.0                    # 最後に記録した時刻(秒)
var _log_i := 0                         # 次に記録するサンプルの番号

## このステップで起きたこと(描画/音声側が読む)
var sfx_queue: Array = []
var sfx_pan: Array = []          # sfx_queue と同じ順の、音の左右の位置(-1 = 左端 〜 1 = 右端。弾の発生源の横の位置)
var just_hit := false           # 新しい被弾が始まったステップ

var active_warns: Array = []
var active_gizmos: Array = []

## --- マルチプレイ(協力モード。setup_coop で有効になる) ---
var net_mode := ""               # "" = ひとり(対戦も、各自が自分の GameSim を回すので "")/ "coop"
var authority := true            # false = 協力の参加者(ホスト以外): ゲージ・スコア・クリア・ゲームオーバーはホストが決めて、apply_net_* で受け取る
var players_n := 1
var graze_div := 1.0             # グレイズのボーナスは、全員の合計を人数で割って(平均で)数える
var aim_targets := {}            # イベント番号 → 自機狙いの目標位置の一覧(スロット順。ホストが決めて全員へ配る。全員で同じ弾になる)
var slot_positions: Array = []   # スロット順の全員の位置(協力: 自機狙いの相手の選び方・休憩/クリアの判定)。自分の位置も入る
var net_events: Array = []       # ホストが全員へ配る出来事 {k: "wipe" / "clear" / "fail", ...}
var contact_dt := 0.0            # 参加者: まだホストへ送っていない、自分の被弾時間・グレイズ・被弾回数
var contact_graze := 0
var contact_hits := 0
var own_graze := 0                # 自分ひとりぶんの成績(協力では、graze・hits・hit_time は全員の合計になるので、結果画面の個人別の表示に使う)
var own_hits := 0
var own_hit_time := 0.0

var _prev_pos := Vector2.ZERO  # このステップ開始時の自機位置(移動経路上の当たり判定用)
var _ext_hit_t := 0.0          # ホスト: 他の人が被弾した直後は、ゲージが回復しない(秒)
var _ev_idx := 0
var _warn_idx := 0
var _near_start := -100.0   # 近くでの発射が続いている区間の始まり(GRACE_STREAK_*)
var _near_last := -100.0    # 最後に近くで撃たれた時刻
var _giz_idx := 0
var _no_hit_time := 1.0        # 最後に被弾してからの経過秒
var _graze_tau := GRAZE_TAU_MIN
var _all_fired_t := -1.0       # 最後の弾幕を撃ち終えた時刻(まだなら -1)


func setup(bullet_field: Node2D, gen: Dictionary, end_t: float, practice_mode: bool, mods := {}) -> void:
	field = bullet_field
	field.clear()
	events = gen.events
	gizmos = gen.gizmos
	zones = gen.get("zones", [])
	breaks = gen.get("breaks", [])
	warn_lead = gen.warn_lead
	end_time = end_t
	practice = practice_mode or bool(mods.get("practice", false))
	track_fires = bool(mods.get("dark", false))
	drain_time = float(mods.get("drain_time", GAUGE_DRAIN_TIME))
	low_protect = bool(mods.get("low_protect", true))
	score_base = SCORE_BASE * float(mods.get("score_mul", 1.0))
	player_scale = float(mods.get("player_scale", 1.0)) * PLAYER_SIZE_MUL
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
		_last_fire = e.t
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


## 協力モードにする(setup のあとに呼ぶ)。体力は全員で 1 本を共有し、人数に応じて増える(満タン = 1 人ぶんの被弾時間 × 人数)。
## 全員の被弾時間を足して減るので、1 人あたりの負担は、ひとりで遊ぶときと同じになる。
func setup_coop(n: int, is_host: bool) -> void:
	net_mode = "coop"
	players_n = maxi(n, 1)
	authority = is_host
	drain_time *= float(players_n)
	graze_div = float(players_n)
	_update_score()


## ホスト: 参加者から届いた被弾の報告(被弾時間・グレイズ・被弾回数)を、共有のゲージとスコアに反映する。
func ext_report(contact_s: float, graze_n: int, hit_n: int, extra_s := 0.0) -> void:
	if not authority or finished:
		return
	if extra_s > 0.0:   # 参加者のデバフ(脆弱・毒)による追加ダメージ
		var sdmg := extra_s / drain_time
		damage_total += sdmg
		gauge -= sdmg
	graze += maxi(graze_n, 0)
	hits += maxi(hit_n, 0)
	if contact_s > 0.0:
		hit_time += contact_s
		var factor := GAUGE_LOW_FACTOR if (low_protect and gauge <= GAUGE_LOW_THRESHOLD) else 1.0
		var dmg := contact_s / drain_time * factor
		damage_total += dmg
		gauge -= dmg
		_ext_hit_t = 0.3
	_update_score()


## 参加者: ホストから届いた共有の状態(ゲージ・累計ダメージ・グレイズ・被弾回数・被弾時間)を反映する。
func apply_net_state(d: Dictionary) -> void:
	gauge = clampf(float(d.get("g", gauge)), 0.0, 1.0)
	damage_total = float(d.get("d", damage_total))
	graze = int(d.get("z", graze))
	hits = int(d.get("h", hits))
	hit_time = float(d.get("ht", hit_time))
	_update_score()


## 参加者: ホストが決めた出来事(休憩の一掃・クリア・ゲームオーバー)を反映する。
func apply_net_event(e: Dictionary, now: float) -> void:
	match str(e.get("k", "")):
		"wipe":
			field.clear()
			break_clear_t = now
			break_end_t = float(e.get("end", now))
		"clear":
			if e.has("st"):
				apply_net_state(e.st)
			field.clear()
			finished = true
			progress = 1.0
			score_progress = 1.0
			break_clear_t = -1.0
			_update_score()
		"fail":
			if e.has("st"):
				apply_net_state(e.st)
			failed = true
			finished = true
			death_pos = player_pos
			death_time = now
			_update_score()


## 参加者: まだ送っていない被弾の報告を取り出す(取り出すと 0 に戻る)。何もなければ空の辞書。
func take_contact() -> Dictionary:
	if contact_dt <= 0.0 and contact_graze == 0 and contact_hits == 0 and contact_extra <= 0.0:
		return {}
	var out := {"c": contact_dt, "z": contact_graze, "h": contact_hits, "s": contact_extra}
	contact_dt = 0.0
	contact_extra = 0.0
	contact_graze = 0
	contact_hits = 0
	return out


## ホスト: 今の共有の状態(参加者へ配る)。
func net_state() -> Dictionary:
	return {"g": gauge, "d": damage_total, "z": graze, "h": hits, "ht": hit_time}


## 自機狙いの目標位置の一覧。協力では、全員を 1 発ずつ(全員が同じ頻度で狙われる)。ホストが決めて配った位置があればそれ、
## なければ(届く前に撃つ場合)いま分かっている全員の位置(スロット順)。ひとり・対戦では、自分だけ。
func aim_targets_for(idx: int) -> Array:
	if aim_targets.has(idx):
		return aim_targets[idx]
	if net_mode == "coop" and slot_positions.size() > 1:
		return slot_positions
	return [player_pos]


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
	_update_zone_debuff(now)
	if move != Vector2.ZERO:
		var spd := PLAYER_SLOW if slow else PLAYER_SPEED
		if zone_debuff == "slow":
			spd *= ZONE_SLOW
		_move_player(player_pos + move.normalized() * spd * dt)
	_update(now, dt)


## マウス操作。delta_px: このフレームのカーソル移動量(アリーナ座標系、感度・低速の倍率は適用済み)。
func step_relative(now: float, dt: float, delta_px: Vector2, slow_mode: bool) -> void:
	if finished:
		return
	slow = slow_mode
	_prev_pos = player_pos
	_update_zone_debuff(now)
	if zone_debuff == "slow":
		delta_px *= ZONE_SLOW
	_move_player(player_pos + delta_px)
	_update(now, dt)


func _move_player(p: Vector2) -> void:
	var m := PLAYER_MARGIN * player_scale
	player_pos = p.clamp(Vector2(m, m), ARENA - Vector2(m, m))


func _update(now: float, dt: float) -> void:
	steps_total += 1
	sfx_queue.clear()
	sfx_pan.clear()
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
	field.update(dt, player_pos, player_r * hit_mult, true, _prev_pos)
	var resting := in_break(now)  # 休憩地帯: スコアは上がらず、ゲージも回復しない
	if authority:
		_update_break_wipe(now, resting)
	elif not resting:
		break_clear_t = -1.0
	if not resting:
		own_graze += field.graze_count
		if authority:
			graze += field.graze_count
		else:
			contact_graze += field.graze_count   # 協力の参加者: ホストへ報告する
	hit_now = field.hit and not debug_invincible
	_ext_hit_t = maxf(_ext_hit_t - dt, 0.0)
	if hit_now:
		if _no_hit_time >= EPISODE_GAP:
			own_hits += 1
			if authority:
				hits += 1
			else:
				contact_hits += 1
			just_hit = true
			hit_log.append(now)
		_no_hit_time = 0.0
		own_hit_time += dt
		if authority:
			hit_time += dt
			# ゲージが少ないとき(20% 以下)は被ダメージが半分(MOD で無効になる)
			var factor := GAUGE_LOW_FACTOR if (low_protect and gauge <= GAUGE_LOW_THRESHOLD) else 1.0
			var dmg := dt / drain_time * factor * (ZONE_FRAGILE if zone_debuff == "fragile" else 1.0)
			damage_total += dmg
			gauge -= dmg
		else:
			contact_dt += dt
			if zone_debuff == "fragile":
				contact_extra += dt * (ZONE_FRAGILE - 1.0)
	else:
		_no_hit_time += dt
		if not resting and authority and _ext_hit_t <= 0.0:
			gauge = minf(gauge + GAUGE_REGEN * dt, 1.0)

	_update_poison(dt, resting)
	_record_gauge(now)

	# 進行率: 曲の進行(時間)とは別に、スコア用の進行率は「発射した弾数」で進める
	progress = clampf(now / maxf(end_time, 0.001), 0.0, 1.0)
	score_progress = clampf(float(bullets_fired) / float(maxi(bullets_total, 1)), 0.0, 1.0) if bullets_total > 0 else 0.0
	_update_score()

	if not authority:
		return   # 協力の参加者: ゲームオーバー・クリアはホストが決める(apply_net_event)

	if gauge <= 0.000001:
		gauge = 0.0
		if not practice:
			failed = true
			finished = true
			death_pos = player_pos
			death_time = now
			_update_score()  # ゲームオーバーは 0 点
			if net_mode == "coop":
				net_events.append({"k": "fail", "st": net_state()})
			return
	if _check_clear(now):
		field.clear()
		finished = true
		progress = 1.0
		score_progress = 1.0  # クリア: 表示点数が最終点になる
		break_clear_t = -1.0
		_update_score()
		if net_mode == "coop":
			net_events.append({"k": "clear", "st": net_state()})


## ゲージの推移を GAUGE_LOG_STEP 秒ごとに記録する(曲の時刻が 0 になってから。時刻が飛んだときは、その間は同じ値で埋める)。
func _record_gauge(now: float) -> void:
	if now < 0.0:
		return
	log_end_t = now
	while float(_log_i) * GAUGE_LOG_STEP <= now and _log_i < 20000:
		gauge_log.append(clampf(gauge, 0.0, 1.0))
		_log_i += 1


## いまの時刻・自機の位置で受けるデバフを決める(動く前に呼ぶ。休憩では効かない)。
func _update_zone_debuff(now: float) -> void:
	zone_debuff = ""
	hit_mult = 1.0
	if zones.is_empty() or in_break(now):
		return
	while _zone_i < zones.size() and float(zones[_zone_i].end) <= now:
		_zone_i += 1
	if _zone_i >= zones.size() or float(zones[_zone_i].t) > now:
		return
	var cell := zone_cell(player_pos)
	for c in zones[_zone_i].cells:
		if int(c.c) == cell:
			zone_debuff = str(c.type)
			hit_mult = ZONE_BIG if zone_debuff == "big" else 1.0
			return


## 盤面の 3×3 のマス番号(0..8。左上から横に数える)。
static func zone_cell(p: Vector2) -> int:
	return clampi(int(p.y / (ARENA.y / 3.0)), 0, 2) * 3 + clampi(int(p.x / (ARENA.x / 3.0)), 0, 2)


## デバフの名前と色(表示用)。
static func zone_name(type: String) -> String:
	return {"slow": "鈍足", "fragile": "脆弱", "poison": "毒", "big": "巨大"}.get(type, "")


static func zone_color(type: String) -> Color:
	return {"slow": Color(0.35, 0.68, 1.0), "fragile": Color(1.0, 0.62, 0.25), "poison": Color(0.62, 0.9, 0.35), "big": Color(0.92, 0.45, 0.92)}.get(type, Color.WHITE)


## 毒: ゲージが減る(休憩・練習では減らない)。協力の参加者は、被弾時間に換算してホストへ報告する。
func _update_poison(dt: float, resting: bool) -> void:
	if zone_debuff != "poison" or resting or practice:
		return
	var sd := ZONE_POISON_DRAIN * GAUGE_DRAIN_TIME * dt
	if authority:
		var dmg := sd / drain_time
		damage_total += dmg
		gauge -= dmg
	else:
		contact_extra += sd


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
		if net_mode == "coop":
			net_events.append({"k": "wipe", "end": break_end_t})


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
	if net_mode == "coop" and slot_positions.size() > 1:   # 協力: 全員の周りが落ち着いているとき
		for p in slot_positions:
			if not field.is_calm(p, player_r, SAFE_NEAR_R, SAFE_APPROACH_R, SAFE_LOOK_T):
				return false
		return true
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
	score_graze = SCORE_GRAZE * (1.0 - exp(-float(graze) / graze_div / _graze_tau))   # 3 万点に漸近(届かない)
	score_gross = score_base + score_graze
	score_potential = score_gross * damage_factor
	score = score_potential * score_progress


func _fire(e: Dictionary, now: float) -> void:
	var late := maxf(now - e.t, 0.0)
	var pos: Vector2 = e.pos
	var grace := 0.0
	if not e.shots.is_empty() and player_pos.distance_to(pos) < SAFE_RADIUS:   # 自機の近くで撃たれた: 続けて撃たれている間は、最初の GRACE_STREAK_MAX 秒だけ猶予
		if float(e.t) - _near_last > GRACE_STREAK_GAP:
			_near_start = float(e.t)
		_near_last = float(e.t)
		if float(e.t) - _near_start <= GRACE_STREAK_MAX:
			grace = SAFE_GRACE_PX
	var aims: Array = aim_targets_for(_ev_idx)   # 自機狙いの相手(協力では全員。ひとりでは自機)
	aim_targets.erase(_ev_idx)
	for s in e.shots:
		for at in (aims if s.aim else [Vector2.ZERO]):
			var base: float = s.a0
			if s.aim:
				base += (at - pos).angle()
			for i in range(s.n):
				var v: Vector2 = Vector2.from_angle(PatternGen.shot_angle(s, base, i)) * s.speed
				field.add(pos + v * late, v, s.size * BULLET_SIZE_MUL, s.color, grace, s.turn)
	if track_fires and not e.shots.is_empty():
		recent_fires.append({"pos": pos, "t": e.t, "color": e.shots[0].color})
	if not e.shots.is_empty():
		break_clear_t = -1.0   # 休憩中に新しい弾が撃たれたら、安全になるまで一掃を待ち直す
	if not in_break(e.t):
		for s in e.shots:
			bullets_fired += int(s.n) * (aims.size() if s.aim else 1)
	if e.sfx != "":
		sfx_queue.append(e.sfx)
		sfx_pan.append(clampf(pos.x / ARENA.x * 2.0 - 1.0, -1.0, 1.0))


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
