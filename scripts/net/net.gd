extends Node
## マルチプレイの通信層。サーバーを持たない P2P(星型: ホスト 1 人 + 参加者)。
##
## 部屋を立てる人(ホスト)が UDP で待ち受け(Godot の ENet)、UPnP でルーターのポートを自動で開ける。
## 参加者は招待コード(invite_code.gd。ホストの IP とポート)でホストへ直接つなぐ。中継サーバーはない。
##
## ここは「部屋」と「メッセージの受け渡し」だけを担当する(ロビーの状態・時計合わせ・ゲーム開始の段取り)。
## ゲーム中のメッセージ("g_" で始まるもの)の中身は mp_game.gd が決める。UI は、この状態を見て描くだけ。
##
## ## メッセージ
## 辞書 {t: 種類, ...} を var_to_bytes で送る(オブジェクトは送らない)。信頼できる送信(制御用)と、順序だけ保つ送信(位置など)がある。
##   クライアント → ホスト: hello / song_status / name / ping / loaded / final / g_*
##   ホスト → クライアント: welcome / reject / roster / room / pong / prepare / go / abort / results / g_*
##
## ## 時計
## 参加者は、ホストとの ping を測り続けて、ホストの時計との差(clock_offset)を求める。shared_time() は、全員で共通の秒。
## ゲームの開始時刻は、この共通の時計で決める(全員が同じ瞬間に始められる)。

const InviteCode = preload("res://scripts/net/invite_code.gd")

const PROTOCOL := 1
const MAX_PLAYERS := 4
const HP_SAMPLES_MAX := 64   # 最終成績に付ける体力グラフ用のサンプルの上限
const CH_CTRL := 0
const CH_STATE := 1
const CONNECT_TIMEOUT := 3.5    # 1 つの行き先への接続を待つ秒数
const HELLO_TIMEOUT := 5.0      # つながってから、ホストの返事を待つ秒数
const LOAD_TIMEOUT := 20.0      # ゲーム開始前、全員の読み込み完了を待つ最大の秒数
const GO_DELAY := 0.5           # 開始の合図から、実際の開始までの余裕(全員に合図が届くように)
const PING_INTERVAL := 1.0
const NAME_MAX := 12

signal roster_changed
signal room_changed
signal joined                     # 参加できた
signal join_failed(reason: String)
signal left(reason: String)       # 部屋を出た・閉じた・切れた(reason が空なら自分から)
signal code_changed               # 招待コードや、その状況が変わった
signal prepare_game(info: Dictionary)   # ゲームを始める準備(全員。曲を読んで、プレイ画面を作る)
signal go(start_shared: float)    # 開始の合図(共通の時計での時刻)
signal aborted(reason: String)    # 開始の中止
signal game_message(from: int, msg: Dictionary)
signal results_changed

## UPnP・公開 IP の問い合わせをするか(テストでは切る)
var use_upnp := true
## 開発用: 送信を遅らせて、回線の遅延・ゆらぎを再現する(ms。0 なら遅らせない)
var debug_latency_ms := 0.0
var debug_jitter_ms := 0.0

var role := ""                    # "" / "host" / "client"
var my_id := 0
var my_name := "PLAYER"
## id → {id, name, slot, has_song, ready, ping}。slot は 0..3(ホストが 0。色・自機の並び順に使う)。
## ready: 参加者が「準備完了」を押したか(ホストは、開始を押す人なので数えない。曲・モード・MOD が変わるたび、ロビーに戻るたびに全員が外れる)
var players: Dictionary = {}
## 部屋の設定(ホストが決めて、全員へ送る): mode("versus" / "coop")、song({md5, title, artist, version, level})、mods、density_mul、phase("lobby" / "loading" / "playing")
var room: Dictionary = {"mode": "versus", "song": {}, "mods": [], "density_mul": 1.0, "phase": "lobby"}
var code := ""                    # 招待コード(準備できるまで空)
var code_note := ""               # 接続の状況(ホスト用)
var port := 0
## 部屋の曲を、この端末が持っているとき: その OszLoader と Beatmap(ロビーで見つけて置く)
var song_loader = null
var song_bm = null
## 最終成績: id → {score, hits, graze, hit_ms, ...}
var results: Dictionary = {}
var clock_offset := 0.0           # ホストの時計 − 自分の時計(秒)
var ping_ms := -1.0               # 自分からホストまでの往復(ms)

var _peer: ENetMultiplayerPeer
var _connecting := false
var _cands: Array = []            # 接続を試す行き先 {host, port}
var _cand_i := 0
var _conn_t := 0.0
var _hello_t := -1.0
var _ping_t := 0.0
var _samples: Array = []          # [往復 µs, 時計の差 µs]
var _upnp: UPNP
var _thread: Thread
var _gen := 0                     # 部屋を立て直すたびに増える(古い UPnP の結果を取り違えない)
var _zombies: Array = []          # 終わるのを待たずに手放したスレッド(終わってから回収する)
var _http: HTTPRequest
var _pub_ip := ""
var _loc_ip := ""
var _note_base := ""
var _loaded: Dictionary = {}      # ホスト: 読み込み完了した id
var _load_t := -1.0
var _started := false
var _out_q: Array = []            # 開発用: 遅らせている送信 [送る時刻(ms), 宛先, msg, reliable, channel]
var _out_last := 0.0


func _process(delta: float) -> void:
	_reap()
	if not _out_q.is_empty():
		var now_ms := Time.get_ticks_usec() / 1000.0
		while not _out_q.is_empty() and _out_q[0][0] <= now_ms:
			var q: Array = _out_q.pop_front()
			_raw_send(q[1], q[2], q[3], q[4])
	if _peer == null:
		return
	_peer.poll()
	var status := _peer.get_connection_status()
	if _connecting:
		_process_connecting(delta, status)
	elif role == "client" and status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_lost("ホストとの接続が切れました")
		return
	while _peer != null and _peer.get_available_packet_count() > 0:
		var from := _peer.get_packet_peer()
		var bytes := _peer.get_packet()
		if _peer.get_packet_error() != OK:
			continue
		_on_packet(from, bytes)
	if _peer == null:
		return
	if role == "client" and not _connecting:
		if _hello_t >= 0.0:
			_hello_t += delta
			if _hello_t > HELLO_TIMEOUT:
				_hello_t = -1.0
				_fail_join("ホストから返事がありません")
				return
		_ping_t -= delta
		if _ping_t <= 0.0:
			_ping_t = PING_INTERVAL if _samples.size() >= 6 else 0.15
			_send(1, {"t": "ping", "t0": Time.get_ticks_usec()}, false, CH_STATE)
	if role == "host" and _load_t >= 0.0:
		_load_t += delta
		if _load_t > LOAD_TIMEOUT:
			for id in players.keys():
				if not _loaded.has(id):
					_drop(id, "読み込みが間に合いませんでした")
			_maybe_go()


func _exit_tree() -> void:
	close()
	_reap(2500)   # UPnP の探索・ポートを閉じる処理が終わるのを待つ(どちらも数秒以内に終わる)
	if not _zombies.is_empty():
		OS.kill(OS.get_process_id())   # それでも終わらないスレッドが残ると、アプリの終了処理が止まる(貸し出したポートは 2 時間で閉じる)


## 手放したスレッドのうち、終わったものを回収する。wait_ms > 0 なら、その間は終わるのを待つ。
func _reap(wait_ms := 0) -> void:
	var t0 := Time.get_ticks_msec()
	while not _zombies.is_empty():
		for th in _zombies.duplicate():
			if not th.is_alive():
				th.wait_to_finish()
				_zombies.erase(th)
		if _zombies.is_empty() or Time.get_ticks_msec() - t0 >= wait_ms:
			return
		OS.delay_msec(10)


## UPnP のポートを閉じる(ルーターへの問い合わせで数秒止まることがあるので、別スレッドで)。
func _unmap(upnp: UPNP, p: int) -> void:
	var th := Thread.new()
	th.start(func(): upnp.delete_port_mapping(p, "UDP"))
	_zombies.append(th)


# --- 共通の時計 ---

## 全員で共通の秒(ホストの時計)。
func shared_time() -> float:
	return Time.get_ticks_usec() / 1e6 + clock_offset


# --- 部屋を立てる(ホスト) ---

## 部屋を立てて待ち受ける。うまくいけば true。招待コードは、UPnP の結果が出てから code_changed で届く。
func host_room(mode: String, p_name: String) -> bool:
	close()
	my_name = _clean_name(p_name)
	var peer: ENetMultiplayerPeer = null
	var p := 0
	for off in range(InviteCode.PORT_SPAN):
		peer = ENetMultiplayerPeer.new()
		if peer.create_server(InviteCode.BASE_PORT + off, MAX_PLAYERS - 1) == OK:
			p = InviteCode.BASE_PORT + off
			break
		peer = null
	if peer == null:
		return false
	_peer = peer
	port = p
	role = "host"
	my_id = 1
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	players = {1: _new_player(1, my_name, 0)}
	players[1].has_song = true
	room = {"mode": mode, "song": {}, "mods": [], "density_mul": 1.0, "phase": "lobby"}
	results.clear()
	code = ""
	code_note = "準備中…"
	_loc_ip = local_ip()
	_pub_ip = ""
	if use_upnp:
		_thread = Thread.new()
		_thread.start(_upnp_worker.bind(port, _gen))
	else:
		_finish_code("", "")
	return true


func _new_player(id: int, p_name: String, slot: int) -> Dictionary:
	return {"id": id, "name": p_name, "slot": slot, "has_song": false, "ready": false, "ping": -1.0}


## UPnP でポートを開けて、ルーターが知っているグローバル IP を得る(別スレッド。数秒かかることがある)。
func _upnp_worker(p: int, gen: int) -> void:
	var res := {"ok": false, "ip": "", "note": ""}
	var upnp := UPNP.new()
	var err := upnp.discover(2000, 2, "InternetGatewayDevice")
	if err == UPNP.UPNP_RESULT_SUCCESS and upnp.get_gateway() != null and upnp.get_gateway().is_valid_gateway():
		var r := upnp.add_port_mapping(p, p, "DDA", "UDP", 7200)   # 2 時間で自動的に閉じる(異常終了しても残らない)。貸し出し期間に非対応のルーターは、無期限で開ける
		if r != UPNP.UPNP_RESULT_SUCCESS:
			r = upnp.add_port_mapping(p, p, "DDA", "UDP")
		if r == UPNP.UPNP_RESULT_SUCCESS:
			res.ok = true
			res.ip = upnp.query_external_address()
		else:
			res.note = "UPnP でポートを開けませんでした"
	else:
		res.note = "UPnP に対応したルーターが見つかりません"
	res["upnp"] = upnp if res.ok else null
	res["port"] = p
	_on_upnp_done.call_deferred(res, gen)


func _on_upnp_done(res: Dictionary, gen: int) -> void:
	if gen != _gen or role != "host":   # 探している間に部屋を閉じた(または立て直した): 開けたポートは、すぐ閉じる(同じポートの部屋が今あるなら、そのまま使う)
		if res.get("upnp") != null and not (role == "host" and port == int(res.port)):
			_unmap(res.upnp, int(res.port))
		return
	if _thread != null:
		_thread.wait_to_finish()   # 結果を送ったあと、すぐ終わる
		_thread = null
	_upnp = res.get("upnp")
	var ip := str(res.ip)
	if res.ok and InviteCode.is_ipv4(ip) and not InviteCode.is_non_routable(ip):
		_finish_code(ip, "")
		return
	_note_base = "ルーターがさらに別のネットワークの内側にあります" if (res.ok and ip != "") else str(res.note)
	# UPnP が使えなかった: せめて公開 IP を調べて、コードに入れる(ルーターで UDP ポートを手動で開けていれば、それで参加できる)
	_http = HTTPRequest.new()
	_http.timeout = 4.0
	add_child(_http)
	_http.request_completed.connect(_on_ip_lookup)
	if _http.request("https://api.ipify.org") != OK:
		_finish_code("", _note_base)


func _on_ip_lookup(_result: int, code_http: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _http != null:
		_http.queue_free()
		_http = null
	var ip := body.get_string_from_utf8().strip_edges()
	if role != "host":
		return
	if code_http == 200 and InviteCode.is_ipv4(ip) and not InviteCode.is_non_routable(ip):
		_finish_code(ip, _note_base)
	else:
		_finish_code("", _note_base)


func _finish_code(pub: String, note: String) -> void:
	_pub_ip = pub
	code = InviteCode.encode(pub, _loc_ip, port)
	if note == "":
		code_note = "インターネット / LAN から参加できます" if pub != "" else "LAN から参加できます"
	else:
		code_note = note + (("。UDP %d をルーターで開けると、インターネットからも参加できます" % port) if pub != "" else "。同じ LAN の人だけ参加できます")
	code_changed.emit()


## この端末の LAN の IPv4(192.168 → 10 → 172.16 → その他の順に選ぶ)。なければ空文字。
static func local_ip() -> String:
	var best := ""
	var best_rank := 99
	for a in IP.get_local_addresses():
		var s := str(a)
		if not InviteCode.is_ipv4(s):
			continue
		var rank := 9
		if s.begins_with("192.168."):
			rank = 0
		elif s.begins_with("10."):
			rank = 1
		elif InviteCode.is_private(s):
			rank = 2
		elif s.begins_with("127.") or s.begins_with("169.254.") or s.begins_with("0."):
			continue
		if rank < best_rank:
			best_rank = rank
			best = s
	return best


# --- 部屋に入る(参加者) ---

## 招待コード、または IP アドレス(:ポート)で参加する。結果は joined / join_failed で届く。
func join(text: String, p_name: String) -> void:
	close()
	my_name = _clean_name(p_name)
	var cands: Array = []
	var d := InviteCode.decode(text)
	if d.ok:
		var mine := local_ip()
		var same_lan: bool = d.local != "" and mine != "" and d.local.get_slice(".", 0) == mine.get_slice(".", 0) and d.local.get_slice(".", 1) == mine.get_slice(".", 1)
		var order := ["local", "public"] if same_lan else ["public", "local"]
		for k in order:
			if d[k] != "":
				cands.append({"host": d[k], "port": d.port})
	else:
		var a := InviteCode.parse_address(text)
		if a.ok:
			cands.append({"host": a.host, "port": a.port})
	if cands.is_empty():
		join_failed.emit("招待コードが正しくありません")
		return
	role = "client"
	_cands = cands
	_cand_i = 0
	_try_candidate()


func _try_candidate() -> void:
	if _peer != null:
		_peer.close()
	_peer = ENetMultiplayerPeer.new()
	var c: Dictionary = _cands[_cand_i]
	if _peer.create_client(c.host, c.port) != OK:
		_next_candidate()
		return
	_connecting = true
	_conn_t = 0.0


func _next_candidate() -> void:
	_cand_i += 1
	if _cand_i >= _cands.size():
		_fail_join("接続できませんでした")
		return
	_try_candidate()


func _process_connecting(delta: float, status: int) -> void:
	_conn_t += delta
	if status == MultiplayerPeer.CONNECTION_CONNECTED:
		_connecting = false
		my_id = _peer.get_unique_id()
		_samples.clear()
		_ping_t = 0.0
		_hello_t = 0.0
		_send(1, {"t": "hello", "v": _version(), "pr": PROTOCOL, "name": my_name})
	elif status == MultiplayerPeer.CONNECTION_DISCONNECTED or _conn_t > CONNECT_TIMEOUT:
		_connecting = false
		_next_candidate()


func _fail_join(reason: String) -> void:
	close()
	join_failed.emit(reason)


# --- 部屋を出る ---

## 部屋を閉じる・出る(UPnP のポートも閉じる)。何もしていなければ何もしない。
func close() -> void:
	var was := role != ""
	if _peer != null:
		_peer.close()
	_peer = null
	_connecting = false
	_hello_t = -1.0
	if _http != null:
		_http.queue_free()
		_http = null
	_gen += 1
	if _thread != null:
		_zombies.append(_thread)   # UPnP の探索は数秒かかることがある。終わるのを待たない(あとで回収する)
		_thread = null
	if _upnp != null:
		_unmap(_upnp, port)
		_upnp = null
	role = ""
	my_id = 0
	players.clear()
	results.clear()
	room = {"mode": "versus", "song": {}, "mods": [], "density_mul": 1.0, "phase": "lobby"}
	code = ""
	code_note = ""
	song_loader = null
	song_bm = null
	clock_offset = 0.0
	ping_ms = -1.0
	_samples.clear()
	_loaded.clear()
	_load_t = -1.0
	_started = false
	if was:
		roster_changed.emit()


## 自分から部屋を出る(ホストなら部屋が閉じて、全員が切れる)。
func leave() -> void:
	var was := role != ""
	close()
	if was:
		left.emit("")


func _lost(reason: String) -> void:
	close()
	left.emit(reason)


func is_active() -> bool:
	return role != "" and not _connecting


func is_host() -> bool:
	return role == "host"


# --- 部屋の設定(ホスト) ---

func set_mode(mode: String) -> void:
	if role != "host" or room.phase != "lobby":
		return
	room.mode = mode
	_clear_ready()
	_push_room()
	_push_roster()


## 曲・MOD・密度を設定する(選曲画面のあと)。song: {md5, title, artist, version, level}
func set_song(song: Dictionary, mods: Array, density_mul: float, loader, bm) -> void:
	if role != "host":
		return
	room.song = song
	room.mods = mods.duplicate()
	room.density_mul = density_mul
	song_loader = loader
	song_bm = bm
	players[1].has_song = true
	_clear_ready()
	_push_room()
	_push_roster()


## 参加者の「準備完了」を全員外す(ホストが部屋の設定を変えたとき・ロビーに戻ったとき。内容を確かめ直してもらう)。
func _clear_ready() -> void:
	for id in players:
		players[id].ready = false


## 自分の「準備完了」を切り替える(参加者。ホストは、開始を押す人なので使わない)。
func set_my_ready(on: bool) -> void:
	if role == "client":
		_send(1, {"t": "ready", "r": on})


func _push_room() -> void:
	_send(0, {"t": "room", "room": room})
	room_changed.emit()


func _push_roster() -> void:
	_send(0, {"t": "roster", "players": players})
	roster_changed.emit()


## 自分が部屋の曲を持っているかを、ホストへ伝える(ロビーが曲を探して呼ぶ)。
func report_song(has: bool, loader = null, bm = null) -> void:
	song_loader = loader if has else null
	song_bm = bm if has else null
	if role == "client":
		_send(1, {"t": "song_status", "has": has})
	elif role == "host":
		players[1].has_song = has
		_push_roster()


func set_my_name(p_name: String) -> void:
	my_name = _clean_name(p_name)
	if role == "client":
		_send(1, {"t": "name", "name": my_name})
	elif role == "host":
		players[1].name = my_name
		_push_roster()


## ホストが参加者を外す。
func kick(id: int) -> void:
	if role == "host" and id != 1 and players.has(id):
		_drop(id, "ホストに外されました")


# --- ゲームの開始(ホスト) ---

## ゲームを始める。全員が部屋の曲を持っている・曲が決まっているときだけ。失敗したら理由の文字列、成功なら空文字。
func start_game() -> String:
	if role != "host" or room.phase != "lobby":
		return "開始できません"
	if room.song.is_empty():
		return "曲が選ばれていません"
	for id in players:
		if not players[id].has_song:
			return "曲を持っていない人がいます"
	for id in players:
		if id != 1 and not players[id].ready:
			return "準備ができていない人がいます"
	room.phase = "loading"
	results.clear()
	_loaded.clear()
	_started = false
	_load_t = 0.0
	var list: Array = []
	for id in players:
		list.append({"id": id, "name": players[id].name, "slot": players[id].slot})
	list.sort_custom(func(a, b): return a.slot < b.slot)
	var info := {"mode": room.mode, "song": room.song, "mods": room.mods, "density_mul": room.density_mul, "players": list}
	_send(0, {"t": "prepare", "info": info})
	_push_room()
	prepare_game.emit(info)
	return ""


## プレイ画面の準備ができたことを伝える(prepare_game を受けたあと、画面を作り終えたら呼ぶ)。
## chk は、作った弾幕の要約(全員が同じ弾幕を作れたかの確認。ホストと違う人は外す)。
func report_loaded(chk := 0) -> void:
	if role == "client":
		_send(1, {"t": "loaded", "chk": chk})
	elif role == "host":
		_loaded[1] = chk
		_maybe_go()


func _maybe_go() -> void:
	if role != "host" or _started or _load_t < 0.0:
		return
	for id in players:
		if not _loaded.has(id):
			return
	var bad: Array = []
	for id in players:
		if _loaded[id] != _loaded[1]:
			bad.append(id)
	if not bad.is_empty():   # 譜面から作った弾幕がホストと違う人は外す(同じ弾にならないので)
		for id in bad:
			_drop(id, "弾幕がホストと一致しません")
		return
	_started = true
	_load_t = -1.0
	var start := shared_time() + GO_DELAY
	room.phase = "playing"
	_send(0, {"t": "go", "start": start})
	_push_room()
	go.emit(start)


## ゲームが終わって、ロビーへ戻る(ホスト。参加を受け付ける状態に戻す)。
func return_to_lobby() -> void:
	if role == "host" and room.phase != "lobby":
		room.phase = "lobby"
		_load_t = -1.0
		_started = false
		_clear_ready()
		_push_room()
		_push_roster()


## ゲームの最終成績を伝える(全員に配られる)。
func send_final(stats: Dictionary) -> void:
	if role == "client":
		_send(1, {"t": "final", "res": stats})
	elif role == "host":
		results[1] = stats
		_send(0, {"t": "results", "r": results})
		results_changed.emit()


# --- ゲーム中のメッセージ ---

## ホストへ送る(参加者から)。
func to_host(msg: Dictionary, reliable := true) -> void:
	if role == "client":
		_send(1, msg, reliable, CH_CTRL if reliable else CH_STATE)


## 全員へ送る(ホストから)。
func broadcast(msg: Dictionary, reliable := true) -> void:
	if role == "host":
		_send(0, msg, reliable, CH_CTRL if reliable else CH_STATE)


## 1 人へ送る(ホストから)。
func to_peer(id: int, msg: Dictionary, reliable := true) -> void:
	if role == "host" and id != 1:
		_send(id, msg, reliable, CH_CTRL if reliable else CH_STATE)


# --- 送受信 ---

func _send(to: int, msg: Dictionary, reliable := true, channel := CH_CTRL) -> void:
	if _peer == null or _connecting:
		return
	if debug_latency_ms > 0.0:   # 開発用: 順序を保ったまま遅らせる
		var due := maxf(Time.get_ticks_usec() / 1000.0 + debug_latency_ms + randf() * debug_jitter_ms, _out_last)
		_out_last = due
		_out_q.append([due, to, msg, reliable, channel])
		return
	_raw_send(to, msg, reliable, channel)


func _raw_send(to: int, msg: Dictionary, reliable: bool, channel: int) -> void:
	if _peer == null or _connecting:
		return
	if role == "host" and to == 0 and players.size() <= 1:
		return
	_peer.set_target_peer(to)
	_peer.set_transfer_channel(channel)
	_peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)
	_peer.put_packet(var_to_bytes(msg))


func _on_packet(from: int, bytes: PackedByteArray) -> void:
	var msg = bytes_to_var(bytes)   # オブジェクトは復元しない(信用できない相手のデータなので)
	if not (msg is Dictionary) or not (msg.get("t") is String):
		return
	if role == "host":
		_host_msg(from, msg)
	elif role == "client":
		_client_msg(msg)


func _on_peer_connected(id: int) -> void:
	# つながっただけでは参加者にしない(hello が来るまで待つ。一定時間 hello が来なければ切る)
	get_tree().create_timer(HELLO_TIMEOUT).timeout.connect(func():
		if role == "host" and _peer != null and not players.has(id) and _peer.get_peer(id) != null:
			_peer.disconnect_peer(id))


func _on_peer_disconnected(id: int) -> void:
	if role != "host" or not players.has(id):
		return
	players.erase(id)
	results.erase(id)
	_loaded.erase(id)
	_push_roster()
	game_message.emit(id, {"t": "g_left"})
	_maybe_go()


func _drop(id: int, reason: String) -> void:
	if _peer != null and _peer.get_peer(id) != null:
		_send(id, {"t": "reject", "why": reason})
		_peer.disconnect_peer(id)
	_on_peer_disconnected(id)


func _host_msg(from: int, msg: Dictionary) -> void:
	var t: String = msg.t
	if t == "hello":
		_host_hello(from, msg)
		return
	if not players.has(from):
		return
	match t:
		"song_status":
			players[from].has_song = bool(msg.get("has", false))
			if not players[from].has_song:
				players[from].ready = false
			_push_roster()
		"ready":
			var on: bool = bool(msg.get("r", false)) and players[from].has_song and room.phase == "lobby" and not room.song.is_empty()
			if players[from].ready != on:
				players[from].ready = on
				_push_roster()
		"name":
			players[from].name = _clean_name(str(msg.get("name", "")))
			_push_roster()
		"ping":
			_send(from, {"t": "pong", "t0": msg.get("t0", 0), "th": Time.get_ticks_usec()}, false, CH_STATE)
			var pk := _peer.get_peer(from)
			if pk != null:
				players[from].ping = pk.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
		"loaded":
			_loaded[from] = int(msg.get("chk", 0))
			_maybe_go()
		"final":
			var res = msg.get("res")
			if res is Dictionary:
				results[from] = _clean_result(res)
				_send(0, {"t": "results", "r": results})
				results_changed.emit()
		_:
			if t.begins_with("g_"):
				game_message.emit(from, msg)


func _host_hello(from: int, msg: Dictionary) -> void:
	if players.has(from):
		return
	var why := ""
	if int(msg.get("pr", 0)) != PROTOCOL or str(msg.get("v", "")) != _version():
		why = "バージョンが違います(ホスト: %s)" % _version()
	elif room.phase != "lobby":
		why = "ゲーム中です"
	elif players.size() >= MAX_PLAYERS:
		why = "満員です"
	if why != "":
		_send(from, {"t": "reject", "why": why})
		_peer.disconnect_peer.call_deferred(from)
		return
	var slot := 0
	var used := players.values().map(func(p): return p.slot)
	while used.has(slot):
		slot += 1
	players[from] = _new_player(from, _clean_name(str(msg.get("name", ""))), slot)
	_send(from, {"t": "welcome", "id": from, "players": players, "room": room})
	_push_roster()


func _client_msg(msg: Dictionary) -> void:
	var t: String = msg.t
	match t:
		"welcome":
			_hello_t = -1.0
			var ps = msg.get("players")
			var rm = msg.get("room")
			if ps is Dictionary and rm is Dictionary:
				players = _clean_roster(ps)
				room = _clean_room(rm)
				joined.emit()
				roster_changed.emit()
				room_changed.emit()
		"reject":
			_fail_join(str(msg.get("why", "参加できませんでした")))
		"roster":
			var ps = msg.get("players")
			if ps is Dictionary:
				players = _clean_roster(ps)
				roster_changed.emit()
		"room":
			var rm = msg.get("room")
			if rm is Dictionary:
				var was_phase: String = room.get("phase", "lobby")
				room = _clean_room(rm)
				if was_phase != "lobby" and room.phase == "lobby":
					_started = false
				room_changed.emit()
		"pong":
			var t2 := Time.get_ticks_usec()
			var rtt: int = t2 - int(msg.get("t0", t2))
			if rtt >= 0:
				_samples.append([rtt, int(msg.get("th", 0)) + rtt / 2 - t2])
				if _samples.size() > 10:
					_samples.remove_at(0)
				var best: Array = _samples[0]
				for s in _samples:
					if s[0] < best[0]:
						best = s
				clock_offset = best[1] / 1e6
				ping_ms = best[0] / 1000.0
		"prepare":
			var info = msg.get("info")
			if info is Dictionary and _valid_info(info):
				results.clear()
				room.phase = "loading"
				prepare_game.emit(_clean_info(info))
		"go":
			room.phase = "playing"
			go.emit(float(msg.get("start", 0.0)))
		"abort":
			aborted.emit(str(msg.get("why", "")))
		"results":
			var r = msg.get("r")
			if r is Dictionary:
				results = {}
				for id in r:
					results[int(id)] = _clean_result(r[id])
				results_changed.emit()
		_:
			if t.begins_with("g_"):
				game_message.emit(1, msg)


## --- 受け取ったデータの整形(ホストが信用できるとは限らないので、決まった形・範囲のものだけを取り出して使う) ---

func _clean_roster(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		var p = d[k]
		if not (p is Dictionary) or out.size() >= MAX_PLAYERS:
			continue
		out[int(k)] = {"id": int(k), "name": _clean_name(str(p.get("name", ""))), "slot": clampi(int(p.get("slot", 0)), 0, MAX_PLAYERS - 1),
			"has_song": bool(p.get("has_song", false)), "ready": bool(p.get("ready", false)), "ping": _num(p.get("ping", -1.0), -1.0, 0.0, 100000.0)}
	return out


func _clean_room(d: Dictionary) -> Dictionary:
	var mode := str(d.get("mode", "versus"))
	var song := {}
	var sg = d.get("song", {})
	if sg is Dictionary and not sg.is_empty():
		song = {"md5": str(sg.get("md5", "")).substr(0, 32), "title": str(sg.get("title", "")).substr(0, 120), "artist": str(sg.get("artist", "")).substr(0, 120),
			"version": str(sg.get("version", "")).substr(0, 120), "level": _num(sg.get("level", 0.0), 0.0, 0.0, 100.0),
			"set_id": int(_num(sg.get("set_id", 0), 0.0, 0.0, 1e9)), "map_id": int(_num(sg.get("map_id", 0), 0.0, 0.0, 1e9))}
	var mods: Array = []
	var ms = d.get("mods", [])
	if ms is Array:
		for m in ms:
			if m is String and mods.size() < 16:
				mods.append(m)
	var phase := str(d.get("phase", "lobby"))
	return {"mode": mode if ["versus", "coop"].has(mode) else "versus", "song": song, "mods": mods,
		"density_mul": _num(d.get("density_mul", 1.0), 1.0, 0.1, 4.0), "phase": phase if ["lobby", "loading", "playing"].has(phase) else "lobby"}


func _valid_info(d: Dictionary) -> bool:
	return d.get("players") is Array and (d.players as Array).size() > 0 and (d.players as Array).size() <= MAX_PLAYERS and d.get("song") is Dictionary


func _clean_info(d: Dictionary) -> Dictionary:
	var room_part := _clean_room({"mode": d.get("mode"), "song": d.get("song"), "mods": d.get("mods"), "density_mul": d.get("density_mul"), "phase": "loading"})
	var list: Array = []
	for p in d.players:
		if p is Dictionary:
			list.append({"id": int(p.get("id", 0)), "name": _clean_name(str(p.get("name", ""))), "slot": clampi(int(p.get("slot", 0)), 0, MAX_PLAYERS - 1)})
	return {"mode": room_part.mode, "song": room_part.song, "mods": room_part.mods, "density_mul": room_part.density_mul, "players": list}


func _clean_result(r) -> Dictionary:
	var d: Dictionary = r if r is Dictionary else {}
	return {"name": _clean_name(str(d.get("name", ""))), "score": _num(d.get("score", 0.0), 0.0, 0.0, 1e9), "failed": bool(d.get("failed", false)),
		"hits": int(_num(d.get("hits", 0), 0.0, 0.0, 1e6)), "graze": int(_num(d.get("graze", 0), 0.0, 0.0, 1e7)), "hit_ms": int(_num(d.get("hit_ms", 0), 0.0, 0.0, 1e9)), "dmg": _num(d.get("dmg", 0.0), 0.0, 0.0, 1e4),
		"damage_factor": _num(d.get("damage_factor", 1.0), 1.0, 0.0, 1.0), "progress": _num(d.get("progress", 0.0), 0.0, 0.0, 1.0),
		"hp": _clean_hp(d.get("hp")), "dur": _num(d.get("dur", 0.0), 0.0, 0.0, 36000.0)}


## 体力グラフ用の間引いたサンプル(0..100 の整数が HP_SAMPLES 個まで)。形が違えば空。
static func _clean_hp(v) -> Array:
	var out: Array = []
	if not v is Array:
		return out
	for x in v:
		if out.size() >= HP_SAMPLES_MAX:
			break
		out.append(int(_num(x, 0.0, 0.0, 100.0)))
	return out


## 数値として読み、範囲に収める(数値でない・NaN・無限大なら既定値)。
static func _num(v, fallback: float, lo: float, hi: float) -> float:
	if not (v is int or v is float):
		return fallback
	var f := float(v)
	if is_nan(f) or is_inf(f):
		return fallback
	return clampf(f, lo, hi)


func _clean_name(s: String) -> String:
	s = s.strip_edges().replace("\n", " ")
	if s.length() > NAME_MAX:
		s = s.substr(0, NAME_MAX)
	return s if s != "" else "PLAYER"


static func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0"))
