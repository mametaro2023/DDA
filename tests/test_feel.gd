extends SceneTree
## 触り心地(juice.gd / screen_wipe.gd / ui_style.gd の動き)の確認。ヘッドレスで、シグナルを直接起こして動きと音の要求を調べる。
## godot --headless --path . --script tests/test_feel.gd

const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const Juice = preload("res://scripts/ui/juice.gd")
const ScreenWipe = preload("res://scripts/ui/screen_wipe.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiFx = preload("res://scripts/ui/ui_fx.gd")
const TitleScreen = preload("res://scripts/ui/title_screen.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _names(sfx: Node, from: int) -> Array:
	return sfx.log.slice(from).map(func(e): return e[0])


func _initialize() -> void:
	await process_frame   # root がツリーに入ってから始める(入る前に作ったノードには、Juice が間に合わない)
	UiStyle.animate = true
	var sfx := UiSfx.new()
	sfx.name = "UiSfx"
	root.add_child(sfx)
	root.add_child(Juice.new())
	var host := Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)

	# --- ボタン: ホバーで大きくなり(音つき)、押すと縮み、離すと戻る ---
	var b := Button.new()
	b.text = "テスト"
	b.size = Vector2(120, 40)
	b.position = Vector2(100, 100)
	host.add_child(b)
	await _frames(2)
	var mark := sfx.log.size()
	b.mouse_entered.emit()
	await _wait(0.45)
	_check(b.scale.x > 1.0 and b.scale.x < 1.1, "ホバーで少し大きくなる(%.3f)" % b.scale.x)
	_check(_names(sfx, mark).has("hover"), "ホバーの音が鳴る")
	mark = sfx.log.size()
	b.button_down.emit()
	await _wait(0.2)
	_check(b.scale.x < 1.0, "押すと縮む(%.3f)" % b.scale.x)
	_check(_names(sfx, mark).has("click"), "押した瞬間にクリック音")
	b.button_up.emit()
	await _wait(0.6)
	_check(absf(b.scale.x - 1.0) < 0.001 or b.scale.x > 1.0, "離すと戻る(%.3f)" % b.scale.x)
	b.mouse_exited.emit()
	await _wait(0.5)
	_check(absf(b.scale.x - 1.0) < 0.001, "マウスが外れると元の大きさ(%.3f)" % b.scale.x)

	# 「戻る」系は back の音、meta で変えられる、no_juice は何もしない
	var back := Button.new()
	back.text = "◀  タイトル"
	host.add_child(back)
	var conf := Button.new()
	conf.set_meta("juice_sound", "confirm")
	host.add_child(conf)
	var quiet := Button.new()
	quiet.set_meta("no_juice", true)
	host.add_child(quiet)
	await _frames(2)
	mark = sfx.log.size()
	back.button_down.emit()
	conf.button_down.emit()
	quiet.button_down.emit()
	var got := _names(sfx, mark)
	_check(got.has("back") and got.has("confirm"), "「◀」は back、meta 指定は confirm(%s)" % str(got))
	_check(got.size() == 2, "no_juice のボタンは何も鳴らさない")
	var dis := Button.new()
	dis.disabled = true
	host.add_child(dis)
	await _frames(2)
	mark = sfx.log.size()
	dis.mouse_entered.emit()
	_check(_names(sfx, mark).is_empty() and dis.scale == Vector2.ONE, "無効なボタンは反応しない")

	# --- スライダー: 人が動かしているときだけ音が鳴る ---
	var sl := HSlider.new()
	sl.size = Vector2(300, 20)
	sl.position = Vector2(100, 300)
	sl.min_value = 0
	sl.max_value = 100
	sl.step = 5
	host.add_child(sl)
	await _frames(2)
	mark = sfx.log.size()
	sl.value = 40   # コードが入れた値
	_check(not _names(sfx, mark).has("tick"), "コードが値を入れても鳴らない")
	sl.drag_started.emit()
	sl.value = 60
	_check(_names(sfx, mark).has("tick"), "ドラッグ中は値が変わるたびに鳴る")
	sl.drag_ended.emit(true)

	# --- 効果音の音程: 値が大きいほど高い ---
	_check(UiSfx.scale_pitch(0.9, 1.0) > UiSfx.scale_pitch(0.1, 1.0), "音階は、値が大きいほど高い")

	# --- ページの横スライド・弾み: 終わったら最終位置 ---
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(page)
	await _frames(1)
	UiStyle.slide_page(page, 40.0)
	await _frames(2)
	_check(page.offset_left > 0.0 and page.offset_left == page.offset_right, "スライド中は左右のオフセットが一緒に動く(%.1f)" % page.offset_left)
	await _wait(0.5)
	_check(page.offset_left == 0.0 and page.offset_right == 0.0, "スライドが終わると元の位置(アンカーのまま)")
	var pc := Control.new()
	pc.size = Vector2(100, 50)
	host.add_child(pc)
	UiStyle.pop_scale(pc, 0.8, 0.3)
	await _wait(0.6)
	_check(pc.scale.is_equal_approx(Vector2.ONE) and is_equal_approx(pc.modulate.a, 1.0), "pop_scale は最終的に等倍・不透明")
	UiFx.ring(host, Vector2(50, 50), Color.WHITE)
	UiFx.burst(host, Vector2(50, 50), Color.WHITE)
	var fx_n := host.get_children().filter(func(c): return c is UiFx).size()
	_check(fx_n == 2, "輪と粒が出る(%d)" % fx_n)
	await _wait(1.0)
	_check(host.get_children().filter(func(c): return c is UiFx).is_empty(), "輪と粒は消えると片付く")

	# --- 画面切り替えの幕: 覆う → 抜ける。途中で最終的に隠れる ---
	var wipe := ScreenWipe.new()
	root.add_child(wipe)
	await _frames(1)
	_check(not wipe._c.visible, "幕は、普段は見えない")
	var t0 := Time.get_ticks_msec()
	await wipe.cover()
	var cover_ms := Time.get_ticks_msec() - t0
	_check(wipe._c.visible and wipe._p >= 1.0, "cover の終わりで画面全体を覆う(%d ms)" % cover_ms)
	_check(cover_ms < 500, "覆う動きは 0.5 秒以内")
	t0 = Time.get_ticks_msec()
	await wipe.reveal()
	_check(not wipe._c.visible, "reveal のあとは見えない(%d ms)" % (Time.get_ticks_msec() - t0))
	UiStyle.animate = false
	await wipe.cover()
	_check(wipe._c.visible, "アニメーションなしでも、すぐ覆う")
	await wipe.reveal()
	_check(not wipe._c.visible, "アニメーションなしでも、すぐ抜ける")
	UiStyle.animate = true

	# --- タイトル: 選択の枠が、選んだ項目へ動く / 選択音 / 無効なとき動かない ---
	var title := TitleScreen.new()
	root.add_child(title)
	await _wait(0.9)
	_check(title._hl.position.is_equal_approx(title._hl_pos(0)), "枠は最初の項目の位置")
	mark = sfx.log.size()
	title._select(2)
	_check(_names(sfx, mark).has("select"), "選ぶと選択音")
	await _wait(0.6)
	_check(title._hl.position.is_equal_approx(title._hl_pos(2)), "枠が選んだ項目へ移る(%s)" % str(title._hl.position))
	mark = sfx.log.size()
	title._select(2)
	_check(_names(sfx, mark).is_empty(), "同じ項目を選び直しても鳴らない")
	title._leaving = true
	title._select(0)
	_check(title._sel == 2, "遷移中は選択を変えない")
	title.queue_free()

	print("RESULT: ", "OK" if _fail == 0 else "%d FAILURES" % _fail)
	quit(1 if _fail > 0 else 0)
