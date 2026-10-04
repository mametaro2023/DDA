extends SceneTree
## 遊び方パネル(classic: howto_panel.gd / lazer 風: lazer_howto.gd)の確認。
##   ・見出し(SECTIONS)と中身を作る関数(PAGE_BUILDERS)の数が合う
##   ・すべてのページが、どちらの UI でも作れる(挿絵・囲み・番号つきの説明を含む)。挿絵の種類が、高さの表にある
## godot --headless --path . --script tests/test_howto.gd

const Classic = preload("res://scripts/ui/howto_panel.gd")
const Lazer = preload("res://scripts/ui/lazer/lazer_howto.gd")
const HowtoArt = preload("res://scripts/ui/howto_art.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	_check(Classic.SECTIONS.size() == Classic.PAGE_BUILDERS.size(), "見出し(%d)と、中身を作る関数(%d)の数が同じ" % [Classic.SECTIONS.size(), Classic.PAGE_BUILDERS.size()])
	for pair in [["classic", Classic], ["lazer", Lazer]]:
		var panel: Control = pair[1].new()
		root.add_child(panel)
		var ok := true
		var arts := 0
		for fn in Classic.PAGE_BUILDERS:
			var page: Control = panel.call(fn)
			if page == null or page.get_child_count() == 0:
				ok = false
				continue
			arts += page.find_children("*", "Control", true, false).filter(func(c): return str(c.get("kind")) != "" and c.get_script() == HowtoArt).size()
			page.free()
		_check(ok, "%s: すべてのページが作れる(挿絵 %d 枚)" % [pair[0], arts])
		panel.queue_free()
	var kinds := ["flow", "arena", "hud", "keys", "zones", "timeline", "gauge", "ranks", "eq", "lv", "select", "multi", "songs"]
	var all_known := true
	for k in kinds:
		if not HowtoArt.HEIGHTS.has(k):
			all_known = false
	_check(all_known and HowtoArt.HEIGHTS.size() == kinds.size(), "挿絵の種類(%d)が、高さの表にそろっている" % kinds.size())
	print("test_howto: ", "OK" if _fail == 0 else "%d FAIL" % _fail)
	quit(1 if _fail > 0 else 0)
