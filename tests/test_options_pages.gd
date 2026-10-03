extends SceneTree
## 設定パネルの全ページを、動き(アニメーション)つきで開く。ページの中に、画面でないもの(ダイアログ・タイマー)があっても壊れないこと。
## godot --headless --path . --script tests/test_options_pages.gd   (エラーが出たら失敗)

const OptionsPanel = preload("res://scripts/ui/options_panel.gd")
const Settings = preload("res://scripts/settings.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")

var p
var frames := 0
var page := 0
var _bad := 0


func _initialize() -> void:
	UiStyle.animate = true
	p = OptionsPanel.new()
	p.theme = UiStyle.make_theme()
	p.setup(Settings.load_all())
	root.add_child(p)


func _process(_d: float) -> bool:
	frames += 1
	if frames % 20 == 0:
		if page < OptionsPanel.SECTIONS.size():
			p.show_section(page)
			# 中身の子は、画面の部品だけ(Window や Timer が混ざると、現れる動きが壊れる)
			for c in p._pages[page].get_children():
				if not (c is Control):
					_bad += 1
					printerr("FAIL: ページ %d に Control でない子がある: %s" % [page, c.get_class()])
			page += 1
		else:
			print("test_options_pages: ", "OK" if _bad == 0 else "%d FAILED" % _bad)
			quit(_bad)
			return true
	return false
