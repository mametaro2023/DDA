extends SceneTree
## UI セットの契約テスト: どの UI セットの画面・パネルも、main.gd が頼っている signal・メソッドを持っているか。
## (ノードを作るだけで、木には入れない。見た目は確かめない)
## godot --headless --path . --script tests/test_ui_contract.gd

const UiSets = preload("res://scripts/ui/ui_sets.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


## ノード n が、契約(signals / methods / props)を満たしているか確かめる
func _contract(label: String, n: Node, signals: Array, methods: Array, props: Array = []) -> void:
	_check(n != null, "%s: 作れる" % label)
	if n == null:
		return
	for s in signals:
		_check(n.has_signal(s), "%s: signal %s" % [label, s])
	for m in methods:
		_check(n.has_method(m), "%s: func %s" % [label, m])
	for p in props:
		_check(p in n, "%s: var %s" % [label, p])
	n.free()


func _init() -> void:
	_check(UiSets.ids().has("classic") and UiSets.ids().has("lazer"), "UI セットに classic と lazer がある")
	_check(UiSets.get_set("no-such-ui").id() == "lazer", "知らない名前は lazer(既定)に戻る")
	_check(UiSets.selectable_ids() == ["lazer"], "設定で選べるのは lazer だけ(classic は選べない)")
	for id in UiSets.ids():
		var ui = UiSets.get_set(id)
		_check(ui.id() == id and ui.display_name() != "", "%s: 名前を持つ" % id)

		var t = ui.make_title()
		_check(t != null and t.kind == "title", "%s: タイトルの kind" % id)
		_contract(id + " title", t, ["play_requested", "multi_requested", "update_requested", "settings_requested"],
			["show_update", "can_accept_auto_update", "open_panel"], ["update_info", "settings"])

		var m = ui.make_menu(false)
		_check(m != null and m.kind == "menu" and not m.pick_mode, "%s: 選曲の kind と pick_mode(通常)" % id)
		_contract(id + " menu", m, ["play_requested", "back_requested", "settings_requested", "song_picked"],
			["refresh_songs", "select_path", "on_overlay"], ["pick_mode", "settings"])
		var mp = ui.make_menu(true)
		_check(mp != null and mp.pick_mode, "%s: 選曲の pick_mode(部屋の曲選び)" % id)
		if mp != null:
			mp.free()

		var mu = ui.make_multi()
		_check(mu != null and mu.kind == "multi", "%s: マルチの kind" % id)
		_contract(id + " multi", mu, ["back_requested", "pick_song_requested"], ["setup"])

		var g = ui.make_game()
		_check(g != null and g.kind == "game", "%s: プレイ画面の kind" % id)
		_contract(id + " game", g, ["finished", "quit_requested", "retry_requested"], ["setup", "setup_multi", "is_paused"], ["pre"])

		var r = ui.make_result()
		_check(r != null and r.kind == "result", "%s: リザルトの kind" % id)
		_contract(id + " result", r, ["menu_requested", "retry_requested"], ["setup", "skip_animation"])

		_contract(id + " options", ui.make_options(), ["changed", "closed"], ["setup", "show_section", "refresh_size", "close_panel"])
		_contract(id + " update", ui.make_update(), ["closed", "cancelled"], ["setup", "close_panel"], ["auto_start"])
		_contract(id + " howto", ui.make_howto(), ["closed"], ["close_panel"])
		_contract(id + " mods", ui.make_mods(), ["changed", "closed"], ["setup", "refresh_info", "close_panel"], ["multi"])
		_contract(id + " quit", ui.make_quit(), ["closed", "confirmed"], ["setup"])
		_contract(id + " survival setup", ui.make_survival_setup(), ["start_requested", "back_requested", "settings_requested"], ["on_overlay"], ["kind", "settings"])
		_contract(id + " survival break", ui.make_survival_break(), ["choices_done", "go_requested", "give_up_requested"], ["setup", "show_next", "set_ready", "show_error", "on_overlay"], ["kind"])
		_contract(id + " survival result", ui.make_survival_result(), ["again_requested", "menu_requested"], ["setup", "on_overlay"], ["kind"])

	print("test_ui_contract: ", "OK" if _fail == 0 else "%d FAIL" % _fail)
	quit(1 if _fail > 0 else 0)
