extends SceneTree
## マルチプレイのイントロのスキップ(全員が押したら、全員で同時に飛ばす)の単体テスト。
## godot --headless --path . --script tests/test_skip.gd

const MpGame = preload("res://scripts/net/mp_game.gd")

var _fail := 0


## 通信層のふり。送ったものを記録する。
class FakeNet:
	extends RefCounted
	var host := false
	var my_id := 1
	var t := 100.0
	var sent: Array = []
	func is_host() -> bool:
		return host
	func shared_time() -> float:
		return t
	func broadcast(msg: Dictionary, _reliable := true, _ch := 0) -> void:
		sent.append(msg)
	func to_host(msg: Dictionary, _reliable := true, _ch := 0) -> void:
		sent.append(msg)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _make(net: FakeNet, ids: Array, store: Dictionary) -> MpGame:
	var g := MpGame.new()
	var players: Array = []
	for i in range(ids.size()):
		players.append({"id": ids[i], "name": "P%d" % i, "slot": i})
	g.setup(net, {"mode": "coop", "players": players}, null)
	g.skip_cb = func(elapsed: float): store["elapsed"] = elapsed
	return g


func _init() -> void:
	# 3 人: ホスト(1)と参加者(2, 3)
	var hn := FakeNet.new()
	hn.host = true
	hn.my_id = 1
	var hs := {}
	var host := _make(hn, [1, 2, 3], hs)
	host.request_skip()
	_check(host.skip_n == 1 and host.skip_total == 3 and not hs.has("elapsed"), "ホストが押しても、全員が押すまで飛ばない(1/3)")
	_check(hn.sent.size() == 1 and hn.sent[0].t == "g_skipn" and hn.sent[0].n == 1 and hn.sent[0].total == 3, "押した人数(1/3)を全員へ配る")
	host.request_skip()
	_check(hn.sent.size() == 1, "同じ人が 2 回押しても、数えない")
	host.handle(2, {"t": "g_skipv"})
	_check(host.skip_n == 2 and not hs.has("elapsed"), "参加者が押して 2/3")
	host.handle(2, {"t": "g_skipv"})
	_check(host.skip_n == 2, "参加者が 2 回押しても 2/3 のまま")
	host.handle(99, {"t": "g_skipv"})
	_check(host.skip_n == 2, "名簿にいない人の分は数えない")
	hn.t = 100.5
	host.handle(3, {"t": "g_skipv"})
	var go: Dictionary = hn.sent.back()
	_check(go.t == "g_skipgo" and absf(float(go.st) - 100.5) < 1e-9 and hs.has("elapsed"), "全員が押したら、合図を出して、ホストも飛ばす")

	# 参加者の側
	var cn := FakeNet.new()
	cn.host = false
	cn.my_id = 2
	var cs := {}
	var cl := _make(cn, [1, 2, 3], cs)
	cl.request_skip()
	_check(cl.skip_mine and cn.sent.size() == 1 and cn.sent[0].t == "g_skipv" and not cs.has("elapsed"), "参加者が押すと、ホストへ伝える(自分では飛ばさない)")
	cl.handle(1, {"t": "g_skipn", "n": 2, "total": 3})
	_check(cl.skip_n == 2 and cl.skip_total == 3, "ホストが配った人数(2/3)が表示に使われる")
	cl.handle(1, {"t": "g_skipn", "n": 99, "total": -5})
	_check(cl.skip_n == 8 and cl.skip_total == 1, "届いた人数は、範囲内に直す")
	cn.t = 100.8
	cl.handle(1, {"t": "g_skipgo", "st": 100.5})
	_check(cs.has("elapsed") and absf(cs.elapsed - 0.3) < 1e-9, "合図が届いたら飛ばす(合図から %.2f 秒ぶん先へ)" % cs.get("elapsed", -1.0))
	cs.erase("elapsed")
	cl.handle(1, {"t": "g_skipgo", "st": 100.5})
	_check(not cs.has("elapsed"), "合図が重ねて届いても、2 回は飛ばさない")

	# 押していない人が去ったら、残りの全員が押していれば飛ばす
	var hn2 := FakeNet.new()
	hn2.host = true
	hn2.my_id = 1
	var hs2 := {}
	var h2 := _make(hn2, [1, 2, 3], hs2)
	h2.request_skip()
	h2.handle(2, {"t": "g_skipv"})
	_check(not hs2.has("elapsed"), "3 人のうち 2 人が押した(2/3)")
	h2.handle(3, {"t": "g_left"})
	h2._gone(3)
	_check(hs2.has("elapsed"), "押していない人が去ったら、残りの全員で飛ばす")

	# ひとり: 自分が押したらすぐ飛ばす
	var sn := FakeNet.new()
	sn.host = true
	var ss := {}
	var solo := _make(sn, [1], ss)
	solo.request_skip()
	_check(ss.has("elapsed") and solo.skip_total == 1, "部屋に自分だけなら、すぐ飛ばす")

	print("test_skip: ", "OK" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)
