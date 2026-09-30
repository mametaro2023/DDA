extends RefCounted
## プレイ中のマルチプレイ処理(game_screen が 1 つ持つ)。位置・スコアのやりとり、協力モードのホスト/参加者の役割分担。
##
## ## 考え方
## どの端末も、同じ譜面から同じ弾幕を作り、曲の時計に合わせて自分で弾を動かす(弾の位置は通信しない)。通信するのは小さなものだけ:
##   位置・低速・スコア … 全員が 30 回/秒。ホストが集めて、全員へ配る(自機を表示するため)
## 各自の被弾判定は、自分の端末で自分の自機だけ行う(自分の見えている弾で当たる)。
##
## ## 対戦(versus)
## 各自が自分ひとりの GameSim を回す(体力が 0 でもゲームオーバーにならず、最後まで続く)。互いの弾・被弾は干渉しない。
## 終わったら最終成績を送り、スコアの高い順で勝敗を決める。
##
## ## 協力(coop)
## 同じフィールドで一緒に避ける。体力・スコア・ゲームオーバー・クリア・休憩の一掃は、ホストが決める(権威)。
##   参加者 → ホスト: 自分の被弾時間・グレイズ・被弾回数を 15 回/秒でまとめて報告(g_ct)
##   ホスト → 全員: 共有の状態(ゲージ・累計ダメージなど)を 20 回/秒(g_cs)、出来事(一掃・クリア・ゲームオーバー)を即時(g_ev)
##   自機狙いの弾: 誰を狙うかと、その位置をホストが撃つ AIM_LEAD 秒前に決めて配る(g_aim)。全員が同じ向きの弾になる
## 自機に近い位置から撃たれた弾の猶予(SAFE_RADIUS)だけは、自分の自機の位置で各自が決める(自分は理不尽に被弾しない)。

const GameSim = preload("res://scripts/game/game_sim.gd")
const NetCore = preload("res://scripts/net/net.gd")

const STATE_INTERVAL := 1.0 / 30.0
const COOP_INTERVAL := 1.0 / 20.0
const CONTACT_INTERVAL := 1.0 / 15.0
const AIM_LEAD := 0.25
const SMOOTH := 22.0            # 他の人の自機の表示を目標位置へ寄せる速さ
const SORT_INTERVAL := 1.0      # 対戦の順位表を並べ替える間隔(秒。頻繁に入れ替わって落ち着かないのを避ける)
## 自機の色(スロット順)
const SLOT_COLORS := [Color(0.32, 0.80, 1.0), Color(1.0, 0.45, 0.75), Color(0.6, 1.0, 0.45), Color(1.0, 0.85, 0.35)]

var net
var sim
var mode := ""                  # "versus" / "coop"
var is_host := false
var my_id := 0
var roster: Array = []          # [{id, name, slot}] スロット順
var remotes: Dictionary = {}    # 他の人 id → {pos, target, slow, score, gone}
var start_shared := -1.0        # 開始の合図で決まる、開始時刻(共通の時計)
var started := false
var now := 0.0                  # 今の曲時間(game_screen が毎フレーム渡す)

var _t_state := 0.0
var _t_coop := 0.0
var _t_contact := 0.0
var _aim_idx := 0
var _latest: Dictionary = {}    # ホスト: 参加者の最新の状態
var _order: Array = []          # 順位表の並び(id)
var _t_sort := 0.0
var _sent_final := false


func setup(p_net, info: Dictionary, p_sim) -> void:
	net = p_net
	sim = p_sim
	mode = str(info.mode)
	is_host = net.is_host()
	my_id = net.my_id
	roster = info.players.duplicate()
	for p in roster:
		if p.id != my_id:
			remotes[p.id] = {"pos": Vector2.ZERO, "target": Vector2.ZERO, "slow": false, "score": 0.0, "gone": false, "seen": false}
		_order.append(p.id)


func slot_of(id: int) -> int:
	for p in roster:
		if p.id == id:
			return int(p.slot)
	return 0


func color_of(id: int) -> Color:
	return SLOT_COLORS[slot_of(id) % SLOT_COLORS.size()]


func name_of(id: int) -> String:
	for p in roster:
		if p.id == id:
			return str(p.name)
	return ""


func my_color() -> Color:
	return color_of(my_id)


## 開始の合図(共通の時計での時刻)。
func on_go(start: float) -> void:
	start_shared = start
	started = true


# --- 毎フレーム ---

func tick(delta: float, p_now: float) -> void:
	now = p_now
	# 他の人の自機を、目標の位置へなめらかに寄せる
	var k := 1.0 - exp(-delta * SMOOTH)
	for id in remotes:
		var r: Dictionary = remotes[id]
		r.pos = r.pos + (r.target - r.pos) * k
	if mode == "coop":
		sim.slot_positions = _slot_positions()
	if not started:
		return
	# 自分の状態(30 回/秒)
	_t_state -= delta
	if _t_state <= 0.0:
		_t_state = STATE_INTERVAL
		if is_host:
			var d := {my_id: [sim.player_pos, sim.slow, sim.score]}
			for id in _latest:
				d[id] = _latest[id]
			net.broadcast({"t": "g_sts", "d": d}, false)
		else:
			net.to_host({"t": "g_st", "p": sim.player_pos, "sl": sim.slow, "sc": sim.score}, false)
	if mode != "coop":
		return
	if is_host:
		_resolve_aims()
		_t_coop -= delta
		if _t_coop <= 0.0:
			_t_coop = COOP_INTERVAL
			net.broadcast({"t": "g_cs", "st": sim.net_state()}, false)
		for e in sim.net_events:
			net.broadcast({"t": "g_ev", "e": e})
		sim.net_events.clear()
	else:
		_t_contact -= delta
		if _t_contact <= 0.0:
			_t_contact = CONTACT_INTERVAL
			var c: Dictionary = sim.take_contact()
			if not c.is_empty():
				net.to_host({"t": "g_ct", "c": c.c, "z": c.z, "h": c.h})


## スロット順の全員の位置(去った人を除く。自分は今の自機の位置)。
func _slot_positions() -> Array:
	var out: Array = []
	for p in roster:
		if p.id == my_id:
			out.append(sim.player_pos)
		elif remotes.has(p.id) and not remotes[p.id].gone and remotes[p.id].seen:
			out.append(remotes[p.id].target)
	return out


## ホスト: これから撃つ自機狙いのイベントについて、狙う相手(スロット順の持ち回り)の位置を決めて配る。
func _resolve_aims() -> void:
	var events: Array = sim.events
	while _aim_idx < events.size() and float(events[_aim_idx].t) - AIM_LEAD <= now:
		var i := _aim_idx
		_aim_idx += 1
		if i < sim._ev_idx:
			continue
		var aims := false
		for s in events[i].shots:
			if s.aim:
				aims = true
				break
		if not aims:
			continue
		var pos: Array = sim.slot_positions
		if pos.size() < 2:
			continue   # ひとりなら、撃つときの自機の位置(sim が決める)
		var target: Vector2 = pos[i % pos.size()]
		sim.aim_targets[i] = target
		net.broadcast({"t": "g_aim", "i": i, "p": target})


# --- 受信 ---

func handle(from: int, msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"g_st":   # ホスト: 参加者の状態
			if remotes.has(from):
				var p = msg.get("p")
				if p is Vector2 and p.is_finite():
					var sc := NetCore._num(msg.get("sc", 0.0), 0.0, 0.0, 1e9)
					_latest[from] = [p, bool(msg.get("sl", false)), sc]
					_apply_remote(from, p, bool(msg.get("sl", false)), sc)
		"g_sts":   # 参加者: ホストが集めた全員の状態
			var d = msg.get("d")
			if d is Dictionary:
				for id in d:
					if int(id) != my_id and remotes.has(int(id)):
						var a = d[id]
						if a is Array and a.size() == 3 and a[0] is Vector2 and a[0].is_finite():
							_apply_remote(int(id), a[0], bool(a[1]), NetCore._num(a[2], 0.0, 0.0, 1e9))
		"g_ct":   # ホスト(協力): 参加者の被弾の報告
			if mode == "coop" and is_host and remotes.has(from) and not sim.finished:
				sim.ext_report(NetCore._num(msg.get("c", 0.0), 0.0, 0.0, 0.5), int(NetCore._num(msg.get("z", 0), 0.0, 0.0, 1000.0)), int(NetCore._num(msg.get("h", 0), 0.0, 0.0, 100.0)))
		"g_cs":   # 参加者(協力): 共有の状態
			var st = msg.get("st")
			if mode == "coop" and not is_host and st is Dictionary and not sim.finished:
				sim.apply_net_state(_clean_state(st))
		"g_ev":   # 参加者(協力): ホストが決めた出来事
			var e = msg.get("e")
			if mode == "coop" and not is_host and e is Dictionary and ["wipe", "clear", "fail"].has(e.get("k")):
				var ev := {"k": e.k, "end": NetCore._num(e.get("end", 0.0), 0.0, 0.0, 1e6)}
				if e.get("st") is Dictionary:
					ev["st"] = _clean_state(e.st)
				sim.apply_net_event(ev, now)
		"g_aim":  # 参加者(協力): 自機狙いの目標
			var p2 = msg.get("p")
			if mode == "coop" and not is_host and p2 is Vector2 and p2.is_finite():
				sim.aim_targets[int(NetCore._num(msg.get("i", -1), -1.0, -1.0, 1e7))] = p2
		"g_left":  # ホスト: 誰かが去った
			_gone(from)
			if is_host:
				net.broadcast({"t": "g_gone", "id": from})
		"g_gone":  # 参加者: 誰かが去った
			_gone(int(msg.get("id", 0)))


## ホストから届いた共有の状態を、範囲のある数値に整える。
func _clean_state(d: Dictionary) -> Dictionary:
	return {"g": NetCore._num(d.get("g", 1.0), 1.0, 0.0, 1.0), "d": NetCore._num(d.get("d", 0.0), 0.0, 0.0, 1e6), "z": int(NetCore._num(d.get("z", 0), 0.0, 0.0, 1e7)),
		"h": int(NetCore._num(d.get("h", 0), 0.0, 0.0, 1e6)), "ht": NetCore._num(d.get("ht", 0.0), 0.0, 0.0, 1e6)}


func _apply_remote(id: int, pos: Vector2, slow: bool, score: float) -> void:
	var r: Dictionary = remotes[id]
	r.target = pos
	r.slow = slow
	r.score = score
	if not r.seen:
		r.seen = true
		r.pos = pos


func _gone(id: int) -> void:
	if remotes.has(id):
		remotes[id].gone = true
		_latest.erase(id)


# --- 表示用 ---

## 他の人の自機の描画リスト。対戦では淡く(ゴースト)、協力ではしっかり描く。
func draw_list() -> Array:
	var out: Array = []
	for p in roster:
		var id: int = p.id
		if id == my_id or not remotes.has(id):
			continue
		var r: Dictionary = remotes[id]
		if r.gone or not r.seen:
			continue
		out.append({"pos": r.pos, "color": color_of(id), "name": str(p.name), "slow": r.slow, "alpha": 0.42 if mode == "versus" else 0.9})
	return out


## 一覧用の行(名前・色・スコア)。対戦はスコアの高い順(SORT_INTERVAL ごとに並べ替える)、協力はスロット順。
func rows(delta: float) -> Array:
	_t_sort -= delta
	if mode == "versus" and _t_sort <= 0.0:
		_t_sort = SORT_INTERVAL
		_order.sort_custom(func(a, b): return _score_of(a) > _score_of(b))
	var out: Array = []
	for id in _order:
		if id != my_id and (not remotes.has(id) or remotes[id].gone):
			continue
		out.append({"id": id, "name": name_of(id), "color": color_of(id), "score": _score_of(id), "me": id == my_id})
	return out


func _score_of(id: int) -> float:
	if id == my_id:
		return sim.score
	return float(remotes[id].score) if remotes.has(id) else 0.0


## 最終成績(ホストへ送る。全員に配られる)。協力では、hits・graze・hit_ms は自分ひとりぶん(スコア・ダメージ係数はチームの値)。
func final_stats(stats: Dictionary) -> Dictionary:
	return {"name": name_of(my_id), "score": float(stats.score), "failed": bool(stats.failed),
		"hits": sim.own_hits, "graze": sim.own_graze, "hit_ms": int(round(sim.own_hit_time * 1000.0)),
		"damage_factor": float(stats.damage_factor), "progress": float(stats.progress)}


func send_final(stats: Dictionary) -> void:
	if _sent_final:
		return
	_sent_final = true
	net.send_final(final_stats(stats))
