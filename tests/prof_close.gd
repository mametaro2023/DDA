extends SceneTree
## 部屋を立てた状態で閉じる(部屋を出る・アプリを閉じる)のにかかる時間(開発用)。godot --headless --path . --script tests/prof_close.gd
## 引数 quit を付けると、UPnP の探索中に、閉じないままアプリを終える(✕ で閉じる場合)。

const NetScript = preload("res://scripts/net/net.gd")


func _init() -> void:
	var n = NetScript.new()
	root.add_child(n)
	# 1) UPnP の結果を待たずにすぐ閉じる
	n.host_room("versus", "A")
	var t0 := Time.get_ticks_msec()
	n.close()
	print("close before UPnP finished: %d ms" % (Time.get_ticks_msec() - t0))
	# 2) 招待コードが出てから閉じる
	n.host_room("versus", "A")
	var t1 := Time.get_ticks_msec()
	while n.code == "" and Time.get_ticks_msec() - t1 < 15000:
		await process_frame
	print("code after %d ms: %s (%s)" % [Time.get_ticks_msec() - t1, n.code, n.code_note])
	var t2 := Time.get_ticks_msec()
	n.close()
	print("close after UPnP mapped: %d ms" % (Time.get_ticks_msec() - t2))
	# 3) 立て直した直後(古い探索の結果が、新しい部屋のものと取り違えられない)
	n.host_room("versus", "A")
	n.host_room("versus", "B")
	var t3 := Time.get_ticks_msec()
	while n.code == "" and Time.get_ticks_msec() - t3 < 15000:
		await process_frame
	print("rehost: code %s after %d ms, players=%d" % [n.code, Time.get_ticks_msec() - t3, n.players.size()])
	n.close()
	if OS.get_cmdline_user_args().has("quit"):
		n.host_room("versus", "A")
		var t4 := Time.get_ticks_msec()
		root.remove_child(n)   # ✕ で閉じたときと同じ(探索中に、木から外れる)
		n.free()
		print("free while discovering: %d ms" % (Time.get_ticks_msec() - t4))
	quit()
