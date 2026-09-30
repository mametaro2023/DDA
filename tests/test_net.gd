extends SceneTree
## マルチプレイの通信まわりのテスト(招待コード)。
## godot --headless --path . --script tests/test_net.gd

const InviteCode = preload("res://scripts/net/invite_code.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	# 往復
	var code := InviteCode.encode("203.0.113.45", "192.168.10.7", 24680)
	print("code = ", code)
	_check(code.length() == 19 and code.count("-") == 3, "16 文字を 4 文字ずつ区切る: %s" % code)
	var d := InviteCode.decode(code)
	_check(d.ok and d.public == "203.0.113.45" and d.local == "192.168.10.7" and d.port == 24680, "往復で元に戻る: %s" % str(d))
	# 小文字・区切りなし・空白・読み替え(O → 0, I/L → 1)
	_check(InviteCode.decode(code.to_lower()).ok, "小文字でも読める")
	_check(InviteCode.decode(code.replace("-", "")).ok, "区切りなしでも読める")
	_check(InviteCode.decode(" " + code.replace("-", " ") + " ").ok, "空白区切りでも読める")
	var alt := InviteCode.encode("0.0.0.0", "10.0.0.1", 24700)   # 0 と 1 を含む
	_check(InviteCode.decode(alt.replace("0", "O").replace("1", "l")).ok, "O → 0、l → 1 に読み替える: %s" % alt)
	# 欠けた IP は空文字、ポートの範囲
	var d2 := InviteCode.decode(InviteCode.encode("", "192.168.0.2", 24935))
	_check(d2.ok and d2.public == "" and d2.local == "192.168.0.2" and d2.port == 24935, "グローバル IP なし・ポート上限: %s" % str(d2))
	_check(InviteCode.encode("1.2.3.4", "", 24679) == "" and InviteCode.encode("1.2.3.4", "", 24936) == "", "範囲外のポートは作れない")
	# 誤り検出: 1 文字変えると(ほぼ必ず)チェックで弾かれる
	var undetected := 0
	var raw := code.replace("-", "")
	for i in range(raw.length()):
		var alt_ch := "Q" if raw[i] != "Q" else "R"
		var bad := raw.substr(0, i) + alt_ch + raw.substr(i + 1)
		if InviteCode.decode(bad).ok:
			undetected += 1
	_check(undetected == 0, "1 文字の誤りは全て検出する(見逃し %d)" % undetected)
	_check(not InviteCode.decode("").ok and not InviteCode.decode("ABCD").ok and not InviteCode.decode(code + "0").ok, "短い・長い・空は弾く")
	_check(not InviteCode.decode("UUUU-UUUU-UUUU-UUUU").ok, "使えない文字(U)は弾く")
	# 全部のポートと、いろいろな IP で往復
	var ok_all := true
	for off in [0, 1, 127, 255]:
		for ip in ["1.1.1.1", "255.255.255.255", "10.20.30.40", "100.64.0.1"]:
			var dd := InviteCode.decode(InviteCode.encode(ip, "172.16.0.9", InviteCode.BASE_PORT + off))
			if not (dd.ok and dd.public == ip and dd.local == "172.16.0.9" and dd.port == InviteCode.BASE_PORT + off):
				ok_all = false
	_check(ok_all, "ポート・IP の組み合わせで往復")

	# IP の直接入力
	var a := InviteCode.parse_address("192.168.1.5")
	_check(a.ok and a.host == "192.168.1.5" and a.port == InviteCode.BASE_PORT, "ポート省略は既定")
	a = InviteCode.parse_address(" 10.0.0.2:25000 ")
	_check(a.ok and a.host == "10.0.0.2" and a.port == 25000, "ポート指定")
	for bad in ["", "abc", "1.2.3", "256.1.1.1", "1.2.3.4:abc", "1.2.3.4:80", "1.2.3.4:70000", code]:
		_check(not InviteCode.parse_address(bad).ok, "アドレスとして不正: '%s'" % bad)
	# 分類
	_check(InviteCode.is_private("192.168.0.1") and InviteCode.is_private("10.1.2.3") and InviteCode.is_private("172.20.0.1") and not InviteCode.is_private("172.32.0.1") and not InviteCode.is_private("8.8.8.8"), "プライベート判定")
	_check(InviteCode.is_non_routable("100.64.1.1") and InviteCode.is_non_routable("127.0.0.1") and InviteCode.is_non_routable("0.0.0.0") and not InviteCode.is_non_routable("203.0.113.9"), "到達不能(CGNAT 等)の判定")

	print("test_net: ", "OK" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)
