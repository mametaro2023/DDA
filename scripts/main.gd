extends Node
## 画面遷移(メニュー → プレイ → リザルト)。

const TitleScreen = preload("res://scripts/ui/title_screen.gd")
const MenuScreen = preload("res://scripts/ui/menu_screen.gd")
const GameScreen = preload("res://scripts/game/game_screen.gd")
const ResultScreen = preload("res://scripts/ui/result_screen.gd")
const MultiScreen = preload("res://scripts/ui/multi_screen.gd")
const NetScript = preload("res://scripts/net/net.gd")
const SongLibrary = preload("res://scripts/song_library.gd")
const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const Settings = preload("res://scripts/settings.gd")
const Mods = preload("res://scripts/mods.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Volume = preload("res://scripts/volume.gd")
const HudOverlay = preload("res://scripts/ui/hud_overlay.gd")
const Updater = preload("res://scripts/updater.gd")
const UpdatePanel = preload("res://scripts/ui/update_panel.gd")
const OszImport = preload("res://scripts/osz_import.gd")
const SingleInstance = preload("res://scripts/single_instance.gd")

var _current: Node
var net                    # 通信層(マルチプレイを開くときに作る。部屋を出ても使い回す)
var _last_play := {}
var overlay                # 音量メーター・通知(全画面の上)
var updater                # アプリ内アップデート(GitHub のリリースを確認する)
var _instance            # 1 つだけ動かして、あとから開いた .osz を受け取る
var _music: AudioStreamPlayer = null   # クリアで引き継いだ曲(リザルト中に流れ続ける)

## 画面切替の暗転フェード(通常起動のときだけ。開発用フックは即時に切り替える)
var _fade_enabled := false
var _fade: ColorRect
var _fading := false
var _pending: Node = null


func _ready() -> void:
	Volume.init_from(Settings.load_all())
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shot")
	if i >= 0 and args.size() > i + 2:
		UiStyle.animate = false   # スクリーンショットは動きを待たず、最終状態で撮る
		_shot(args[i + 1], args[i + 2], args.slice(i + 3))
		return
	# 動きの確認: --shot-anim <画面> <出力の接頭辞> [...]  →  接頭辞_0.png ... を、開いてからの経過時間ごとに撮る
	i = args.find("--shot-anim")
	if i >= 0 and args.size() > i + 2:
		_shot(args[i + 1], args[i + 2], args.slice(i + 3), true)
		return
	if args.has("--smoke-upnp"):
		_smoke_upnp()
		return
	if args.has("--smoke-update"):
		_smoke_update()
		return
	if args.has("--smoke-volume"):
		_smoke_volume()
		return
	if args.has("--smoke-open"):
		_smoke_open()
		return
	if args.has("--smoke-mp-ui"):
		_smoke_mp_ui()
		return
	if args.has("--smoke-mp"):
		_smoke_mp()
		return
	if args.has("--smoke-net"):
		_smoke_net()
		return
	if args.has("--smoke-ui"):
		_smoke_ui()
		return
	if args.has("--smoke-clock"):
		_smoke_clock()
		return
	if args.has("--smoke-slider"):
		_smoke_slider()
		return
	if args.has("--smoke-kiai"):
		_smoke_kiai()
		return
	if args.has("--smoke-title"):
		_smoke_title()
		return
	if args.has("--smoke-back"):
		_smoke_back()
		return
	if args.has("--smoke-clear"):
		_smoke_clear()
		return
	if args.has("--smoke-rush"):
		_smoke_rush()
		return
	if args.has("--smoke-skip"):
		_smoke_skip()
		return
	if args.has("--smoke-score"):
		_smoke_score()
		return
	if args.has("--smoke-death"):
		_smoke_death()
		return
	if args.has("--smoke"):
		_smoke()
		return
	# .osz をつけて起動された(ファイルを開いた)とき: すでに動いているアプリがあれば、そちらへ渡して終わる
	var osz := _osz_arg()
	if osz != "" and SingleInstance.forward(osz):
		get_tree().quit()
		return
	_setup_fade()
	overlay = HudOverlay.new()
	add_child(overlay)
	_instance = SingleInstance.new()
	add_child(_instance)
	_instance.start()
	_instance.file_received.connect(_on_open_osz)
	Updater.cleanup_after_update()
	updater = Updater.new()
	add_child(updater)
	updater.check_finished.connect(_on_update_checked)
	if bool(Settings.load_all().check_update):
		updater.check()
	get_window().files_dropped.connect(_on_files_dropped)
	if osz != "":
		_on_open_osz(osz)   # 起動したので、取り込んで選曲画面へ
	else:
		show_title()


## 開発用: 実時間で数秒プレイ(音声クロック/入力の確認)。-- --smoke
func _smoke() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[1]
	var mouse := OS.get_cmdline_user_args().has("mouse")
	start_game(loader, bm, {"mods": ["practice", "dark"] if OS.get_cmdline_user_args().has("dark") else ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "mouse" if mouse else "keyboard", "sfx_volume": 70})
	var g = _current
	var t0 := Time.get_ticks_msec()
	var press := InputEventKey.new()
	press.physical_keycode = KEY_LEFT
	press.keycode = KEY_LEFT
	press.pressed = true
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(300, 300)
	motion.global_position = motion.position
	motion.relative = Vector2(50, -40)
	for sec in range(8):
		if sec == 4:
			if mouse:
				Input.parse_input_event(motion)
			else:
				Input.parse_input_event(press)
		await get_tree().create_timer(1.0).timeout
		print("real=%.2fs song_now=%.2f audio_playing=%s player=(%.0f,%.0f) bullets=%d sfx_played=%s" % [
			(Time.get_ticks_msec() - t0) / 1000.0, g._now, str(g._audio.playing), g.sim.player_pos.x, g.sim.player_pos.y, g.field.count, str(g._sfx._last.keys())])
	get_tree().quit()


## 更新の確認が終わった。新しいバージョンがあれば、タイトル画面に案内を出す。
func _on_update_checked(info: Dictionary) -> void:
	if bool(info.get("newer", false)) and _current != null and _current.get_script() == TitleScreen:
		_current.show_update(info)


## 起動時の引数から、開く .osz を探す(ファイルの関連付けからは `-- "パス"` で届く。単に引数として渡されても拾う)。
func _osz_arg() -> String:
	for list in [OS.get_cmdline_user_args(), OS.get_cmdline_args()]:
		for a in list:
			var s := str(a)
			if s.to_lower().ends_with(".osz") and FileAccess.file_exists(s):
				return s.replace("\\", "/")
	return ""


## .osz を開いた(関連付け・ドロップ・別のアプリから)。取り込んで、選曲画面でその曲を選んだ状態にする。
## プレイ中は邪魔をしない(取り込みだけして、通知を出す)。マルチプレイのロビーでは取り込みだけ(部屋の曲があれば、自動で見つかる)。
func _on_open_osz(path: String) -> void:
	print("[open] ", path)
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_move_to_foreground()
	var r := OszImport.import_file(path)
	if not r.ok:
		if overlay != null:
			overlay.toast(str(r.error))
		if _current == null:
			show_title()
		return
	if overlay != null:
		overlay.toast(("%s を開きます" if r.existed else "%s を取り込みました") % (str(r.title) if str(r.title) != "" else str(r.path).get_file()))
	if _current != null and (_current.get_script() == GameScreen or _current.get_script() == MultiScreen):
		return
	var st := Settings.load_all()
	st.last_song = r.path
	st.last_diff = ""
	Settings.save_all(st)
	show_menu()


## ウィンドウに .osz をドロップした(選曲画面では、選曲画面が自分で受け取る)。
func _on_files_dropped(files: PackedStringArray) -> void:
	if _current != null and _current.get_script() == MenuScreen:
		return
	for f in files:
		if f.to_lower().ends_with(".osz"):
			_on_open_osz(f)
			return


## 画面を切り替える。通常起動では、短い暗転(フェードアウト → 入れ替え → フェードイン。点滅・フラッシュなし)を挟む。
func _swap(n: Node, instant := false) -> void:
	if not _fade_enabled or _current == null or (instant and not _fading):
		_swap_now(n)
		return
	if _pending != null:
		_pending.free()   # 暗転中にさらに要求が来たら、新しいほうだけ使う
	_pending = n
	if not _fading:
		_run_fade()


func _swap_now(n: Node) -> void:
	if _current != null:
		_current.queue_free()
	_current = n
	add_child(n)


func _setup_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.03, 0.035, 0.06, 0.0)
	_fade.size = Vector2(1280, 720)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_fade_enabled = true


func _run_fade() -> void:
	_fading = true
	while _pending != null:
		var t_in := create_tween()
		t_in.tween_property(_fade, "color:a", 1.0, 0.12)
		await t_in.finished
		var n := _pending
		_pending = null
		_swap_now(n)
		var t_out := create_tween()
		t_out.tween_property(_fade, "color:a", 0.0, 0.2)
		await t_out.finished
	_fading = false


## タイトル画面(起動時)。プレイ → 選曲画面。遊び方・設定はタイトルの上に重なるパネル。
func show_title() -> void:
	var t := TitleScreen.new()
	t.play_requested.connect(show_menu)
	t.multi_requested.connect(show_multi)
	t.update_requested.connect(func():
		var p := UpdatePanel.new()
		p.setup(updater)
		t._open(p))
	if updater != null:
		t.update_info = updater.info
	_stop_music()
	_swap(t)


func show_menu(pick := false) -> void:
	var m := MenuScreen.new()
	m.pick_mode = pick   # マルチプレイの部屋の曲を選ぶとき(決定でロビーへ戻る)
	if pick:
		m.song_picked.connect(_on_song_picked)
		m.back_requested.connect(func(): show_multi())
	else:
		m.play_requested.connect(start_game)
		m.back_requested.connect(show_title)
	_stop_music()
	_swap(m)


## 通信層(net.gd)。マルチプレイを開くときに作り、以後は使い回す(部屋を出ても、作り直さない)。
func _get_net():
	if net == null:
		net = NetScript.new()
		add_child(net)
		net.prepare_game.connect(_on_prepare_game)
		net.left.connect(_on_net_left)
	return net


## マルチプレイの画面(入口 → ロビー)。部屋にいる間は、ゲームやリザルトのあともロビーへ戻る。
func show_multi(notice := "") -> void:
	var m := MultiScreen.new()
	m.setup(_get_net(), notice)
	m.back_requested.connect(show_title)
	m.pick_song_requested.connect(func(): show_menu(true))
	_stop_music()
	_swap(m)


## ホストが選曲画面で決めた曲・MOD を、部屋に反映してロビーへ戻る。
func _on_song_picked(loader, bm, settings: Dictionary, level: float) -> void:
	var n = _get_net()
	if n.is_host():
		n.set_song({"md5": bm.md5, "title": bm.title, "artist": bm.artist, "version": bm.version, "level": level, "set_id": bm.beatmapset_id, "map_id": bm.beatmap_id},
			settings.mods, float(settings.density_mul), loader, bm)
	show_multi()


## ゲームの準備(全員)。部屋の曲でプレイ画面を作る。作り終えると、画面が通信層へ準備完了を伝える(全員が済むと、ホストが開始の合図を出す)。
func _on_prepare_game(info: Dictionary) -> void:
	if net.song_bm == null:
		net.leave()
		show_multi("曲を読み込めませんでした")
		return
	var g := GameScreen.new()
	g.setup_multi(net, info, net.song_loader, net.song_bm, Settings.load_all())
	g.finished.connect(func(stats, music): show_result(stats, music))
	g.quit_requested.connect(func():
		net.leave()
		show_title())
	_stop_music()
	_swap(g, true)


## 部屋を出た・閉じられた・切れた。理由があるとき(自分から出たのではないとき)、ロビー以外の画面なら入口へ戻す。
func _on_net_left(reason: String) -> void:
	if reason == "" or (_current != null and _current.get_script() == MultiScreen):
		return
	show_multi(reason)


func _on_mp_result_done() -> void:
	if net != null and net.is_host():
		net.return_to_lobby()
	show_multi()


func start_game(loader, bm, settings: Dictionary, debug_seek := -1.0, debug_death_t := -1.0) -> void:
	_last_play = {"loader": loader, "bm": bm, "settings": settings}
	var g := GameScreen.new()
	g.setup(loader, bm, settings)
	g.debug_seek = debug_seek
	g.debug_death_t = debug_death_t
	g.finished.connect(func(stats, music): show_result(stats, music))
	g.quit_requested.connect(show_menu)
	g.retry_requested.connect(func(): start_game(loader, bm, settings))
	_stop_music()
	_swap(g)


## music: クリアで引き継いだ曲(鳴ったまま、リザルトでも流し続ける。メニュー/リトライで消える)。画面は間を置かずに切り替える。
func show_result(stats: Dictionary, music: AudioStreamPlayer = null) -> void:
	var r := ResultScreen.new()
	r.setup(stats, net)
	if stats.has("mp"):   # マルチプレイ: ロビーへ戻る(リトライはない)
		r.menu_requested.connect(_on_mp_result_done)
	else:
		r.menu_requested.connect(show_menu)
		r.retry_requested.connect(func():
			start_game(_last_play.loader, _last_play.bm, _last_play.settings))
	if music != null:
		_stop_music(0.0)
		_music = music
		add_child(music)
		music.finished.connect(func(): if _music == music: _stop_music(0.0))
	_swap(r, music != null)


## 引き継いだ曲を止める(fade 秒でなめらかに小さくして消す)。
func _stop_music(fade := 0.4) -> void:
	if _music == null:
		return
	var m := _music
	_music = null
	if fade <= 0.0 or not m.playing:
		m.queue_free()
		return
	var t := m.create_tween()
	t.tween_property(m, "volume_db", -50.0, fade)
	t.tween_callback(m.queue_free)


## スクリーンショット(開発用): -- --shot menu|game|result out.png [difficulty-substring] [seconds]
func _shot(kind: String, out: String, extra: Array, animated := false) -> void:
	match kind:
		"title":
			show_title()   # 例: --shot title out.png [howto|options 0..4]
			if extra.size() > 0 and extra[0] == "howto":
				_current._activate(2)
				if extra.size() > 1 and extra[1].is_valid_int():
					_current._overlay._show(int(extra[1]))
			elif extra.size() > 0 and extra[0] == "options":
				_current._activate(3)
		"menu":
			show_menu()
			_current.debug_set_mods(extra.filter(func(x): return not Mods.find(x).is_empty()))   # 例: --shot menu out.png rush storm
		"options":
			show_menu()   # 例: --shot options out.png 0 rush storm(先頭の数字はセクション 0=MOD 1=操作 2=音 3=ゲーム)
			_current.debug_set_mods(extra.filter(func(x): return not Mods.find(x).is_empty()))
			_current.open_options(int(extra[0]) if extra.size() > 0 and extra[0].is_valid_int() else 0)
		"game":
			var loader := OszLoader.new()
			var path := "C:/Desktop/my_apps/DDA/320118 Reol - No title.osz"
			if extra.size() > 3 and extra[3] == "soleily":
				path = "C:/Desktop/my_apps/DDA/241526 Soleily - Renatus.osz"
			loader.open(path)
			var want: String = extra[0] if extra.size() > 0 else "Extra"
			var secs: float = float(extra[1]) if extra.size() > 1 else 30.0
			var bm = loader.difficulties[loader.difficulties.size() - 1]
			for d in loader.difficulties:
				if d.version.contains(want):
					bm = d
			var gs := {"offset_ms": 0, "density_mul": 1.0,
				"mods": extra.filter(func(x): return not Mods.find(x).is_empty())}   # 例: ... Extra 40 hell rush
			var death_t := -1.0
			if extra.size() > 2 and extra[2].begins_with("death"):
				death_t = float(extra[2].trim_prefix("death"))
			start_game(loader, bm, gs, secs, death_t)
			if extra.size() > 2 and extra[2] == "pause":
				_current._set_paused(true)
			if extra.has("nearhp") or extra.has("nearscore"):   # 自機を体力バー / スコアの近くに置いて、HUD の透過を撮る
				_current.sim.player_pos = Vector2(200, 34) if extra.has("nearhp") else Vector2(800, 40)
				_current._update_hud_fade(0.0, true)
				_current._refresh()
			if extra.has("scorered"):   # 被ダメージでスコアが減っている間の赤い数字
				_current._score_red = 1.0
				_current._refresh()
			if extra.has("trail"):   # 自機が右へ動いているときの尾を撮る
				var vw = _current._view_over
				for i in range(20):
					_current.sim.player_pos += Vector2(3.8, 0)
					vw.now += 0.01
					vw._update_trail()
				vw.queue_redraw()
			if extra.has("kiai"):   # キアイの光のピークを撮る(拍の頭)
				_current._kiai_a = 1.0
				_current._beat_glow = 1.0
				_current._apply_kiai()
				_current._refresh()
			if extra.has("slow"):   # 低速中の見た目(暗闇の可視範囲が狭まる)を撮る  例: ... Extra 40 dark slow
				_current.sim.slow = true
				_current._dark_scale = _current.DARK_SLOW_SCALE
				_current._refresh()
			for e in extra:   # 体力を指定して撮る(例: ... Extra 40 practice hp0.15)
				if e.begins_with("hp") and e.trim_prefix("hp").is_valid_float():
					var hp := float(e.trim_prefix("hp"))
					_current.sim.gauge = hp
					_current._gauge_ghost = minf(1.0, hp + 0.12)
					_current._hit_any = extra.has("hit")   # 例: ... hp0.6 hit(被弾中の先端の演出)
					_current._hit_glow = 1.0 if extra.has("hit") else 0.0
					for f in range(100):   # 先端の演出(火花・流れる光)を 100 フレームぶん進めてから撮る
						_current._animate_hud(1.0 / 60.0)
					_current._low_vis = _current._low_target()
					_current._refresh()
		"update":
			show_title()   # 新しいバージョンの案内とパネル。例: --shot update out.png [panel]
			updater = Updater.new()
			add_child(updater)
			updater.info = {"ok": true, "newer": true, "version": "0.3.0-beta", "notes": "## v0.3.0 beta\n- 新機能 A を追加\n- **修正** B\n- `songs` フォルダの扱いを改善", "page": Updater.PAGE_URL}
			_current.show_update(updater.info)
			if extra.has("panel"):
				var up := UpdatePanel.new()
				up.setup(updater)
				_current._open(up)
		"volume":
			show_title()   # 音量メーター(音楽を選択中)と通知。例: --shot volume out.png
			overlay = HudOverlay.new()
			add_child(overlay)
			await get_tree().process_frame
			Volume.set_master(60)
			Volume.set_music(35)
			Volume.set_sfx(85)
			overlay._sel = 1
			overlay._show_panel()
			overlay.toast("320118 Reol - No title.osz を取り込みました")
		"multi":
			show_multi()   # 入口
		"lobby":
			await _mp_room("coop" if extra.has("coop") else "versus", extra.has("nosong"), extra.has("three"))
			show_multi()   # 例: --shot lobby out.png [coop] [nosong] [three]
		"lobbyguest":
			await _mp_guest_room(extra.has("nosong"))   # 参加者から見たロビー。例: --shot lobbyguest out.png [nosong(曲を持っていない)]
			show_multi()
		"mpgame":
			await _mp_room("coop" if extra.has("coop") else "versus", false, false)
			var secs_mp := 7.0
			for e in extra:
				if e.is_valid_float():
					secs_mp = float(e)
			net.start_game()   # 例: --shot mpgame out.png coop 8(何秒進めて撮るか)
			var t_mp := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t_mp < secs_mp * 1000.0 + 2500.0:
				await get_tree().process_frame
			_current.debug_move = func(): return _bot_dodge(_current)
		"mpresult":
			var nn = _get_net()
			nn.results = {1: {"name": "Alice", "score": 903120.0, "hits": 0, "graze": 214, "hit_ms": 0}, 2: {"name": "Bob", "score": 871400.0, "hits": 3, "graze": 180, "hit_ms": 480}}
			var mode_r := "coop" if extra.has("coop") else "versus"
			show_result({"title": "Reol - No title [Insane]", "level": 5.8, "mean": 105.0, "peak": 141.0, "failed": false, "progress": 1.0, "hits": 3, "hit_ms": 480, "graze": 394, "score": 903120.0, "score_gross": 1013000.0,
				"damage_factor": 0.89, "score_graze": 13000.0, "practice": false, "score_base": 1000000.0, "mod_ids": [], "mods": "",
				"mp": {"mode": mode_r, "my_id": 1, "players": [{"id": 1, "name": "Alice", "slot": 0}, {"id": 2, "name": "Bob", "slot": 1}, {"id": 3, "name": "Carol", "slot": 2}]}})
		"bullets":
			_shot_bullets()
		"result":
			var rl := OszLoader.new()
			rl.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
			var rbm = rl.difficulties[rl.difficulties.size() - 1]
			show_result({"title": "Reol - No title [Insane]", "level": 5.8, "mean": 105.0, "peak": 141.0, "failed": extra.size() > 0 and extra[0] == "failed", "progress": 0.63, "hits": 0 if extra.has("ss") else 2, "hit_ms": 180, "graze": 123, "score": 1013000.0 if extra.has("ss") else (300000.0 if extra.has("f") else 830660.0), "score_gross": 1013000.0, "damage_factor": 0.82, "score_graze": 13000.0, "practice": false,
				"score_base": 1060000.0, "mod_ids": ["hell", "rush"], "mods": "地獄 + 加速",
				"bg": rl.load_image(rbm.background) if rbm.background != "" else null})
			if not (extra.size() > 0 and extra[0] == "failed"):
				_current._score_disp = _current._score_target   # スクリーンショットではカウントアップを待たない
	if animated:
		var t0 := Time.get_ticks_msec()
		var k := 0
		for at in [0.1, 0.3, 0.6, 1.2, 2.5]:
			while (Time.get_ticks_msec() - t0) / 1000.0 < at:
				await get_tree().process_frame
			var path := "%s_%d.png" % [out, k]
			get_viewport().get_texture().get_image().save_png(path)
			print("saved ", path, " at %.2fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
			k += 1
		get_tree().quit()
		return
	for n in range(6):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()


## 開発用: 動かずに被弾するまで待ち、ゲームオーバー演出→リザルト遷移を確認する。-- --smoke-death
func _smoke_death() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[3]
	start_game(loader, bm, {"mods": [], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 70})
	var g = _current
	var t0 := Time.get_ticks_msec()
	var was_dead := false
	var dead_at := 0.0
	var last_pos := 0.0
	var last_log: Array = []
	while Time.get_ticks_msec() - t0 < 60000:
		await get_tree().create_timer(0.5).timeout
		var real := (Time.get_ticks_msec() - t0) / 1000.0
		if not is_instance_valid(g) or _current != g:
			print("[%.1fs] screen switched -> %s" % [real, _current.get_script().resource_path])
			break
		last_log = g._sfx.log
		if g._dead:
			if not was_dead:
				await _sample_death_frames(g)
				was_dead = true
				dead_at = real
				last_pos = g._audio.get_playback_position()
				print("[%.1fs] DEAD at song_now=%.2f hits=%d" % [real, g._now, g.sim.hits])
			var pos: float = g._audio.get_playback_position()
			var rate := (pos - last_pos) / 0.5
			last_pos = pos
			print("  +%.1fs pitch=%.2f vol_db=%.1f playing=%s playback_rate=%.2fx bullets_alpha=%.2f label=%s a=%.2f" % [
				real - dead_at, g._audio.pitch_scale, g._audio.volume_db, str(g._audio.playing), rate, g.field.modulate.a, g._center_label.text, g._center_label.modulate.a])
	# 爆発音の再生要求以降に、何が何回要求されたか(連打がなければ explosion 1 回のみ)
	var t_exp := -1
	for e in last_log:
		if e[0] == "explosion":
			t_exp = e[1]
	var after := {}
	for e in last_log:
		if t_exp >= 0 and e[1] >= t_exp:
			after[e[0]] = after.get(e[0], 0) + 1
	print("sfx requests since explosion: ", after, "   (total requests in run: ", last_log.size(), ")")
	get_tree().quit()


## ゲームオーバー中の 100 フレームを記録し、揺れ・点滅がないことを確認する。
func _sample_death_frames(g) -> void:
	var max_shift := 0.0
	var alpha_ok := true
	var prev_alpha: float = g.field.modulate.a
	var max_alpha_step := 0.0
	var bullets_moved := 0.0
	var first_pos: Vector2 = g.field.pos[0] if g.field.count > 0 else Vector2.ZERO
	for i in range(100):
		await get_tree().process_frame
		max_shift = maxf(max_shift, (g._arena.position - g.ARENA_POS).length())
		var a: float = g.field.modulate.a
		if a > prev_alpha + 0.0001:
			alpha_ok = false
		max_alpha_step = maxf(max_alpha_step, prev_alpha - a)
		prev_alpha = a
		if g.field.count > 0:
			bullets_moved = maxf(bullets_moved, (g.field.pos[0] - first_pos).length())
	print("death frames: arena_shift_max=%.3fpx alpha_monotonic=%s alpha_max_step_per_frame=%.3f bullet_moved=%.3fpx" % [
		max_shift, str(alpha_ok), max_alpha_step, bullets_moved])


## 弾の見た目の確認用: 上段=通常の弾、下段=発射直後(当たり判定なし)の弾。
func _shot_bullets() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.07)
	bg.size = Vector2(1280, 720)
	add_child(bg)
	var BulletFieldScript = load("res://scripts/game/bullet_field.gd")
	var f = BulletFieldScript.new()
	f.position = Vector2(100, 100)
	add_child(f)
	f.setup_render()
	for i in range(10):
		f.add(Vector2(i * 110, 0), Vector2.ZERO, 7.5, i % 10, 0.0)           # 通常
		f.add(Vector2(i * 110, 100), Vector2.ZERO, 7.5, i % 10, 100.0)       # 発射直後(無害)
		f.add(Vector2(i * 110, 220), Vector2.ZERO, 12.0, i % 10, 0.0)        # 大きい弾
		f.add(Vector2(i * 110, 320), Vector2.ZERO, 12.0, i % 10, 100.0)
	f.sync_render()


## 開発用: 選曲・設定・ポーズの操作を、実際のキー入力で通しで確認する。-- --smoke-ui(ユーザーの設定ファイルは終了時に元へ戻す)
func _smoke_ui() -> void:
	var orig := Settings.load_all()
	show_menu()
	for i in range(4):
		await get_tree().process_frame
	var m = _current
	print("menu: songs=%d diffs=%d diff_sel=%d focus_diff=%s" % [m._song_cards.size(), m._diff_cards.size(), m._diff_sel, str(m._focus_diff)])
	await _key(KEY_DOWN)
	print("Down       -> diff_sel=%d" % m._diff_sel)
	await _key(KEY_TAB)
	var song_before: int = m._song_sel
	await _key(KEY_UP)
	print("Tab, Down  -> focus_diff=%s song_sel %d -> %d (diffs=%d)" % [str(m._focus_diff), song_before, m._song_sel, m._diff_cards.size()])
	await _key(KEY_TAB)
	var lv_before: float = m._ratings[m._diff_sel].level
	await _key(KEY_O)
	print("O          -> options open=%s" % str(m._options != null))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	m._options._mod_cards["storm"].gui_input.emit(click)
	await get_tree().process_frame
	print("click STORM-> mods=%s Lv %.2f -> %.2f | summary: %s" % [str(m.settings.mods), lv_before, m._ratings[m._diff_sel].level, m._options._mod_summary.text])
	await _key(KEY_TAB)
	print("Tab in options -> page 1 visible=%s" % str(m._options._pages[1].visible))
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(0.4).timeout   # 閉じる動きのぶん待つ
	print("Esc        -> options open=%s (menu still %s)" % [str(m._options != null), str(_current == m)])
	await _key(KEY_ENTER)
	for i in range(4):
		await get_tree().process_frame
	var g = _current
	print("Enter      -> screen=%s mods=%s Lv=%.2f (MODなし %.2f)" % [g.get_script().resource_path.get_file(), str(g._mods.ids), g.gen.level, g.gen.base_level])
	await _key(KEY_ESCAPE)
	print("Esc        -> paused=%s layer=%s" % [str(g._paused), str(g._pause_layer.visible)])
	await _key(KEY_DOWN)
	await _key(KEY_RIGHT)
	print("Down,Right -> sel=%d volume=%d" % [g._pause_sel, int(g.settings.volume)])
	for i in range(3):
		await _key(KEY_UP)
	await _key(KEY_ENTER)
	print("Up x3, Enter  -> paused=%s" % str(g._paused))
	await _key(KEY_ESCAPE)
	await _key(KEY_Q)
	for i in range(3):
		await get_tree().process_frame
	print("Q          -> screen=%s" % _current.get_script().resource_path.get_file())
	Settings.restore(orig)   # ユーザーの設定ファイルを元に戻す
	print("settings restored")
	get_tree().quit()


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame


## 開発用: MOD「加速」(再生速度 ×1.5)の曲クロックを実時間で確認する。-- --smoke-rush
func _smoke_rush() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[2]   # Normal: 最初のノーツは 2.40 秒(加速で 1.60 秒)
	start_game(loader, bm, {"offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0, "mods": ["practice", "rush"]})
	var g = _current
	print("first fire (game time) = %.3f  end_time=%.2f  pitch=%.2f  Lv=%.2f (MODなし %.2f)" % [g.sim.first_fire_time, g._end_time, g._audio.pitch_scale, g.gen.level, g.gen.base_level])
	var t0 := Time.get_ticks_msec()
	var last_now := 0.0
	var last_real := 0.0
	for i in range(6):
		await get_tree().create_timer(1.0).timeout
		var real := (Time.get_ticks_msec() - t0) / 1000.0
		var pos: float = g._audio.get_playback_position()
		print("real=%.2f now=%.2f (%.2f/s) audio_pos=%.2f (pos/now=%.2f) fired=%d bullets=%d" % [real, g._now, (g._now - last_now) / (real - last_real), pos, pos / maxf(g._now, 0.001), g.sim.bullets_fired, g.field.count])
		last_now = g._now
		last_real = real
	get_tree().quit()


## 開発用: イントロのスキップを実時間で確認する(READY 中 / 再生中の 2 通り)。-- --smoke-skip
func _smoke_skip() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[0]   # Beginner: 最初のノーツが約 12 秒
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.keycode = KEY_SPACE
	space.pressed = true
	for when in [0.5, 3.0]:   # 0.5 秒 = READY(リードイン)中、3.0 秒 = 再生中
		start_game(loader, bm, {"mods": ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
		var g = _current
		await get_tree().create_timer(when).timeout
		var before: float = g._now
		var can_before: bool = g._can_skip()
		Input.parse_input_event(space)
		await get_tree().process_frame
		await get_tree().process_frame
		var after: float = g._now
		var can_after: bool = g._can_skip()
		var first: float = g.sim.first_fire_time
		print("[press at %.1fs] now %.2f -> %.2f (target %.2f, first note %.2f) can_skip before=%s after=%s audio_playing=%s audio_pos=%.2f" % [
			when, before, after, g._skip_target(), first, str(can_before), str(can_after), str(g._audio.playing), g._audio.get_playback_position()])
		Input.parse_input_event(space)   # 2 回目は無視される(進む幅がない)
		await get_tree().create_timer(1.0).timeout
		print("   +1.0s: now=%.2f bullets=%d (first note at %.2f)" % [g._now, g.field.count, first])
		await get_tree().create_timer(1.2).timeout
		print("   +2.2s: now=%.2f bullets=%d fired=%d" % [g._now, g.field.count, g.sim.bullets_fired])
	get_tree().quit()


## 開発用: 表示スコアのイージングをフレームごとに記録して確認する。-- --smoke-score
func _smoke_score() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[2]   # Normal: 最初のノーツが約 2.4 秒
	start_game(loader, bm, {"mods": ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
	var g = _current
	g.sim.debug_invincible = true   # ダメージによる目標の低下を除き、上昇だけを見る
	var t0 := Time.get_ticks_msec()
	var frames := 0
	var max_lag := 0.0
	var overshoot := false
	var early_nonzero := false
	var target_moves := 0
	var last_target := 0.0
	var eased_frames := 0     # 目標に追いついていない(イージング中)のフレーム
	var last_disp := 0.0
	var monotone := true
	while Time.get_ticks_msec() - t0 < 9000:
		await get_tree().process_frame
		frames += 1
		var target: float = g.sim.score
		var disp: float = g._score_disp
		if g._now < g.sim.events[0].t - 0.05 and (target > 0.0 or disp > 0.0):
			early_nonzero = true      # 最初のノーツより前にスコアが動いた(あってはならない)
		if target > last_target + 0.5:
			target_moves += 1
		if disp > target + 0.5 and target >= last_target:
			overshoot = true          # 上昇中に目標を追い越した(イージングなら起きない)
		if absf(target - disp) > 0.5:
			eased_frames += 1
		max_lag = maxf(max_lag, target - disp)
		if disp < last_disp - 0.5 and target >= last_target:
			monotone = false
		last_target = target
		last_disp = disp
	print("frames=%d first_note=%.2fs | target moved in %d frames, easing active in %d frames | max lag=%.0f pts | overshoot=%s early_nonzero=%s monotone=%s" % [
		frames, g.sim.events[0].t, target_moves, eased_frames, max_lag, str(overshoot), str(early_nonzero), str(monotone)])
	print("final: target=%.0f disp=%.0f bullets_fired=%d/%d" % [g.sim.score, g._score_disp, g.sim.bullets_fired, g.sim.bullets_total])
	get_tree().quit()


## 開発用: クリアの流れを実時間で確認する(弾が抜けたら即クリア → リザルトでも曲が流れ続ける)。-- --smoke-clear
func _smoke_clear() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[0]
	start_game(loader, bm, {"mods": ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
	var g = _current
	await get_tree().create_timer(2.5).timeout   # READY(1.5s)のあと、曲が流れ始める
	var last: float = g.sim.events[g.sim.events.size() - 1].t
	print("seek audio to %.2f (last event %.2f)  audio_playing=%s" % [last - 0.5, last, str(g._audio.playing)])
	g._audio.seek((last - 0.5) * g._rate)
	var t0 := Time.get_ticks_msec()
	var was_game := true
	while Time.get_ticks_msec() - t0 < 12000:
		await get_tree().process_frame
		if was_game and is_instance_valid(g) and g.sim.finished:
			print("sim finished at now=%.2f  failed=%s  bullets=%d  score_progress=%.2f" % [g._now, str(g.sim.failed), g.field.count, g.sim.score_progress])
			was_game = false
		if not is_instance_valid(g) or _current != g:
			print("screen swapped to result at %.2fs  music=%s playing=%s pos=%.2f" % [(Time.get_ticks_msec() - t0) / 1000.0, str(_music != null), str(_music != null and _music.playing), _music.get_playback_position() if _music != null else -1.0])
			break
	await get_tree().create_timer(1.0).timeout
	print("+1.0s in result: music playing=%s pos=%.2f" % [str(_music != null and _music.playing), _music.get_playback_position() if _music != null else -1.0])
	_current.menu_requested.emit()
	await get_tree().create_timer(0.1).timeout
	print("after menu request: music node alive=%s (fading)" % str(_music != null))
	await get_tree().create_timer(0.6).timeout
	print("+0.7s: music=%s" % str(_music))
	get_tree().quit()


## 開発用: 曲クロック(_now)の増分が、実際のフレーム時間とどれだけずれるか(= 弾の移動距離のばらつき)を測る。-- --smoke-clock
func _smoke_clock() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[0]
	start_game(loader, bm, {"mods": ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
	var g = _current
	while not g._audio_started or g._now < 3.0:
		await get_tree().process_frame
	var last_now: float = g._now
	var last_us := Time.get_ticks_usec()
	var errs: Array = []   # 曲クロックの増分 − 実時間の増分(ms)
	var frozen := 0
	var drift_max := 0.0   # 曲クロックと音声クロックのずれ(ms)の絶対値の最大
	var drift_sum := 0.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
		var us := Time.get_ticks_usec()
		var dn: float = g._now - last_now
		var dr := (us - last_us) / 1e6
		errs.append((dn - dr) * 1000.0)
		if dn <= 0.0:
			frozen += 1
		var ta: float = g._audio.get_playback_position() / g._rate + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		drift_max = maxf(drift_max, absf(g._now - ta) * 1000.0)
		drift_sum += (g._now - ta) * 1000.0
		last_now = g._now
		last_us = us
	var mean := 0.0
	for e in errs:
		mean += e
	mean /= errs.size()
	var var_sum := 0.0
	var worst := 0.0
	for e in errs:
		var_sum += (e - mean) * (e - mean)
		worst = maxf(worst, absf(e - mean))
	print("frames=%d  clock-step minus real-step: mean=%.3fms  stdev=%.3fms  worst=%.2fms  frozen_frames=%d  |  vs audio clock: mean=%.2fms max=%.1fms" % [errs.size(), mean, sqrt(var_sum / errs.size()), worst, frozen, drift_sum / errs.size(), drift_max])
	get_tree().quit()


## 開発用: プレイして選択画面に戻ったとき、直前の曲・難易度が選ばれていることを確認する。-- --smoke-back
func _smoke_back() -> void:
	var original := Settings.load_all()
	show_menu()
	await get_tree().create_timer(0.5).timeout
	var m = _current
	var target_song := -1
	for i in range(m._songs.size()):
		if m._songs[i].path.contains("Reol"):
			target_song = i
	m._select_song(target_song)
	await get_tree().create_timer(0.5).timeout
	m._select_diff(4)
	var want: String = m._loader.difficulties[4].version
	print("song=%s  diff picked: idx=%d '%s' (of %d)" % [m._songs[m._song_sel].path.get_file(), m._diff_sel, want, m._loader.difficulties.size()])
	m._start()
	await get_tree().create_timer(0.5).timeout
	_current.quit_requested.emit()   # ゲームからメニューへ戻る
	await get_tree().create_timer(1.0).timeout
	var m2 = _current
	var got: String = m2._loader.difficulties[m2._diff_sel].version if m2._diff_sel >= 0 else "-"
	print("back in menu: song=%s idx=%d '%s'  -> %s" % [m2._songs[m2._song_sel].path.get_file(), m2._diff_sel, got, "OK" if got == want else "MISMATCH"])
	Settings.restore(original)   # ユーザーの設定を元に戻す
	get_tree().quit()


## 開発用: 実時間で曲を進め、スライダーの軌道の描画(CanvasGroup)を撮る。-- --smoke-slider <出力の接頭辞>
func _smoke_slider() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/241526 Soleily - Renatus.osz")
	var bm = loader.difficulties[loader.difficulties.size() - 1]
	start_game(loader, bm, {"mods": ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
	var g = _current
	await get_tree().create_timer(2.5).timeout
	g._audio.seek(48.0 * g._rate)   # 鋭く折れ返るスライダー(48.4 秒)の直前
	await get_tree().create_timer(0.55).timeout
	var pref: String = OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--smoke-slider") + 1] if OS.get_cmdline_user_args().size() > OS.get_cmdline_user_args().find("--smoke-slider") + 1 else "tmp_slider"
	get_viewport().get_texture().get_image().save_png("C:/Desktop/my_apps/DDA/%s.png" % pref)
	print("now=%.2f nodes=%d" % [g._now, g._view_under._slider_nodes.size()])
	get_tree().quit()


## 開発用: キアイ中の光が、拍に合わせて出入りすることを実時間で確認する。-- --smoke-kiai
func _smoke_kiai() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[loader.difficulties.size() - 1]   # キアイは 50〜70 秒、BPM 200(1 拍 0.3 秒)
	start_game(loader, bm, {"mods": ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
	var g = _current
	await get_tree().create_timer(2.5).timeout
	g._audio.seek(48.0)
	var samples: Array = []   # [曲の時刻, 光, キアイの度合い]
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
		samples.append([g._now, g._beat_glow, g._kiai_a, g.field.halo])
	var pre_max := 0.0
	var kiai_max := 0.0
	var kiai_min := 9.0
	var peaks: Array = []
	for i in range(samples.size()):
		var s: Array = samples[i]
		if s[0] < 49.6:
			pre_max = maxf(pre_max, s[1])
		elif s[0] > 51.0:
			kiai_max = maxf(kiai_max, s[1])
			kiai_min = minf(kiai_min, s[1])
			if i > 0 and i < samples.size() - 1 and s[1] > samples[i - 1][1] and s[1] >= samples[i + 1][1] and s[1] > 0.5:
				peaks.append(s[0])
	var gaps: Array = []
	for i in range(1, peaks.size()):
		gaps.append(snappedf(peaks[i] - peaks[i - 1], 0.001))
	print("frames=%d  キアイ前(<49.6s)の最大の光=%.3f  キアイ中(>51s)の光: 最小=%.3f 最大=%.3f  拍のピーク %d 回、間隔(秒)=%s  (1 拍 = 0.300 秒)" % [samples.size(), pre_max, kiai_min, kiai_max, peaks.size(), str(gaps.slice(0, 8))])
	get_tree().quit()


## 開発用: タイトル画面の流れを、実際のキー入力で通して確認する。-- --smoke-title
##   起動 → タイトル(曲が流れる)→ 遊び方を開閉 → 設定を開閉 → プレイ → 選曲画面 → Esc → タイトル
func _smoke_title() -> void:
	var original := Settings.load_all()
	show_title()
	await get_tree().create_timer(2.0).timeout
	var t = _current
	print("title: %s  items=%d  music_playing=%s  song=%s" % [t.get_script().resource_path.get_file(), t._cards.size(), str(t._audio.playing), t._last_path.get_file()])
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)   # 遊び方
	print("selected=%d (expect 2)" % t._sel)
	await _key(KEY_ENTER)
	await get_tree().create_timer(0.5).timeout
	print("howto open=%s  music_still_playing=%s" % [str(t._overlay != null), str(t._audio.playing)])
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(0.6).timeout
	print("howto closed=%s" % str(t._overlay == null))
	await _key(KEY_DOWN)   # 設定
	await _key(KEY_ENTER)
	await get_tree().create_timer(0.5).timeout
	print("options open=%s (selected=%d)" % [str(t._overlay != null), t._sel])
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(0.6).timeout
	print("options closed=%s" % str(t._overlay == null))
	await _key(KEY_UP)
	await _key(KEY_UP)
	await _key(KEY_UP)   # プレイ
	await _key(KEY_ENTER)
	await get_tree().create_timer(1.2).timeout
	print("after PLAY: %s" % _current.get_script().resource_path.get_file())
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(0.8).timeout
	print("after Esc:  %s" % _current.get_script().resource_path.get_file())
	t = _current
	await get_tree().create_timer(0.5).timeout
	await _key(KEY_DOWN)   # マルチプレイ
	await _key(KEY_ENTER)
	await get_tree().create_timer(1.2).timeout
	print("after MULTI: %s" % _current.get_script().resource_path.get_file())
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(0.8).timeout
	print("after Esc:  %s" % _current.get_script().resource_path.get_file())
	Settings.restore(original)
	get_tree().quit()


## 開発用: 通信層(net.gd)を、同じプロセス内のホストと参加者で確認する(localhost。UPnP は使わない)。-- --smoke-net
func _smoke_net() -> void:
	var NetScript = load("res://scripts/net/net.gd")
	var st := {"fails": 0}   # ラムダの中から増やせるように、辞書に持つ
	var chk := func(cond: bool, msg: String):
		print(("  ok   " if cond else "  FAIL ") + msg)
		if not cond:
			st.fails += 1
	var a = NetScript.new()
	a.use_upnp = false
	add_child(a)
	var b = NetScript.new()
	b.use_upnp = false
	add_child(b)
	chk.call(a.host_room("versus", "Alice"), "ホストが待ち受けを始める(port %d)" % a.port)
	await get_tree().process_frame
	chk.call(a.code != "" and a.players.size() == 1, "招待コード %s / 状況: %s" % [a.code, a.code_note])
	# 参加(コードは LAN の IP を含むので、localhost へは ip:port で)
	var ev := {"joined": false, "failed": ""}
	b.joined.connect(func(): ev.joined = true)
	b.join_failed.connect(func(r): ev.failed = r)
	b.join("127.0.0.1:%d" % a.port, "Bob")
	var t0 := Time.get_ticks_msec()
	while not ev.joined and ev.failed == "" and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
	chk.call(ev.joined, "参加できる(%d ms)" % (Time.get_ticks_msec() - t0))
	await get_tree().create_timer(0.6).timeout
	chk.call(a.players.size() == 2 and b.players.size() == 2, "名簿が両方に届く: host=%s guest=%s" % [str(a.players.values().map(func(p): return p.name + "#" + str(p.slot))), str(b.players.values().map(func(p): return p.name + "#" + str(p.slot)))])
	chk.call(b.my_id != 1 and b.players.has(b.my_id) and b.players[b.my_id].slot == 1, "参加者のスロットは 1")
	chk.call(absf(b.clock_offset) < 0.01 and b.ping_ms >= 0.0 and b.ping_ms < 50.0, "時計合わせ: offset=%.4fs ping=%.2fms" % [b.clock_offset, b.ping_ms])
	# 部屋の設定
	a.set_mode("coop")
	a.set_song({"md5": "abc", "title": "T", "artist": "A", "version": "V", "level": 4.2}, ["dark"], 1.0, null, null)
	await get_tree().create_timer(0.3).timeout
	chk.call(b.room.mode == "coop" and b.room.song.get("md5") == "abc" and b.room.mods == ["dark"], "部屋の設定が参加者に届く: %s" % str(b.room))
	# 曲を持っていない人がいると開始できない
	chk.call(a.start_game() != "", "曲を持っていない人がいると開始できない: '%s'" % a.start_game())
	b.report_song(true)
	await get_tree().create_timer(0.3).timeout
	var got := {"prep_a": false, "prep_b": false, "go_a": -1.0, "go_b": -1.0, "msg_a": "", "msg_b": ""}
	a.prepare_game.connect(func(info): got.prep_a = true; a.report_loaded(7))
	b.prepare_game.connect(func(info): got.prep_b = info.mode == "coop" and info.players.size() == 2; b.report_loaded(7))
	a.go.connect(func(s): got.go_a = s)
	b.go.connect(func(s): got.go_b = s)
	a.game_message.connect(func(from, m): got.msg_a = m.t)
	b.game_message.connect(func(from, m): got.msg_b = m.t)
	chk.call(a.start_game() == "", "全員が曲を持っていれば開始できる")
	await get_tree().create_timer(0.8).timeout
	chk.call(got.prep_a and got.prep_b, "全員に準備の合図が届く")
	chk.call(got.go_a > 0.0 and got.go_b > 0.0 and absf(got.go_a - got.go_b) < 0.001, "開始の合図(共通の時計): %.3f / %.3f" % [got.go_a, got.go_b])
	chk.call(a.room.phase == "playing" and b.room.phase == "playing", "phase = playing")
	# 開始後は参加できない
	var c = NetScript.new()
	c.use_upnp = false
	add_child(c)
	var cf := {"r": ""}
	c.join_failed.connect(func(r): cf.r = r)
	c.join("127.0.0.1:%d" % a.port, "Carol")
	t0 = Time.get_ticks_msec()
	while cf.r == "" and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
	chk.call(cf.r.contains("ゲーム中"), "ゲーム中の部屋には入れない: '%s'" % cf.r)
	# ゲーム中のメッセージ
	b.to_host({"t": "g_test", "x": 1})
	a.broadcast({"t": "g_back"})
	await get_tree().create_timer(0.3).timeout
	chk.call(got.msg_a == "g_test" and got.msg_b == "g_back", "ゲーム中のメッセージが届く")
	# 最終成績
	b.send_final({"score": 123456.0, "hits": 2})
	a.send_final({"score": 654321.0, "hits": 0})
	await get_tree().create_timer(0.4).timeout
	chk.call(b.results.size() == 2 and a.results.size() == 2 and float(b.results[1].score) == 654321.0, "最終成績が全員に配られる")
	# ロビーへ戻ると参加できる
	a.return_to_lobby()
	await get_tree().create_timer(0.2).timeout
	cf.r = ""
	var cj := {"ok": false}
	c.joined.connect(func(): cj.ok = true)
	c.join("127.0.0.1:%d" % a.port, "Carol")
	t0 = Time.get_ticks_msec()
	while not cj.ok and cf.r == "" and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
	chk.call(cj.ok, "ロビーに戻れば 3 人目が入れる")
	await get_tree().create_timer(0.4).timeout
	chk.call(a.players.size() == 3, "3 人")
	# 参加者が抜ける
	var slot_c: int = a.players[c.my_id].slot
	c.leave()
	await get_tree().create_timer(0.5).timeout
	chk.call(a.players.size() == 2 and b.players.size() == 2, "参加者が抜けると名簿から消える")
	# 抜けたスロットは次の人が使う
	var d = NetScript.new()
	d.use_upnp = false
	add_child(d)
	var dj := {"ok": false}
	d.joined.connect(func(): dj.ok = true)
	var by_code: String = a.code   # 招待コードで参加する(LAN の IP から試す)
	d.join(by_code, "Dave")
	t0 = Time.get_ticks_msec()
	while not dj.ok and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	chk.call(dj.ok and a.players.has(d.my_id) and a.players[d.my_id].slot == slot_c, "招待コード(%s)で参加でき、空いたスロットを再利用する(slot %d)" % [by_code, slot_c])
	d.leave()
	# ホストが閉じると参加者に知らせる
	var lf := {"reason": "-"}
	b.left.connect(func(r): lf.reason = r)
	a.leave()
	t0 = Time.get_ticks_msec()
	while lf.reason == "-" and Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
	chk.call(lf.reason != "-" and lf.reason != "" , "ホストが閉じると参加者に届く: '%s' (%d ms)" % [lf.reason, Time.get_ticks_msec() - t0])
	# 不正なコード・つながらない行き先
	var e = NetScript.new()
	e.use_upnp = false
	add_child(e)
	var ef := {"r": ""}
	e.join_failed.connect(func(r): ef.r = r)
	e.join("ZZZZ", "Eve")
	chk.call(ef.r.contains("正しくありません"), "不正なコードは即座に弾く: '%s'" % ef.r)
	ef.r = ""
	e.join("127.0.0.1:24999", "Eve")
	t0 = Time.get_ticks_msec()
	while ef.r == "" and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	chk.call(ef.r != "", "誰もいない行き先は、時間内に失敗する: '%s' (%d ms)" % [ef.r, Time.get_ticks_msec() - t0])
	print("smoke-net: ", "OK" if st.fails == 0 else "%d FAILED" % st.fails)
	get_tree().quit()


## 開発用: マルチプレイの対戦・協力を、同じプロセス内のホストと参加者(ボットが操作)で、実時間で通して確認する(localhost。UPnP なし)。
##   -- --smoke-mp [coop|versus] [fail]     coop: 共有ゲージ・同じ弾・クリアの一致 / fail: 全員が動かず、ゲームオーバーが全員に届くか
func _smoke_mp() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := "coop" if args.has("coop") else "versus"
	var fail_test := args.has("fail")
	var st := {"fails": 0}   # ラムダの中から増やせるように、辞書に持つ
	var chk := func(cond: bool, msg: String):
		print(("  ok   " if cond else "  FAIL ") + msg)
		if not cond:
			st.fails += 1
	var a = NetScript.new()
	a.use_upnp = false
	add_child(a)
	var b = NetScript.new()
	b.use_upnp = false
	add_child(b)
	var lag := 0.0
	for arg in args:
		if arg.begins_with("lag"):
			lag = float(arg.trim_prefix("lag"))   # 例: lag120(片道 120ms + ゆらぎ 30ms)
	a.debug_latency_ms = lag
	b.debug_latency_ms = lag
	a.debug_jitter_ms = lag * 0.25
	b.debug_jitter_ms = lag * 0.25
	a.host_room(mode, "Alice")
	var joined := {"ok": false}
	b.joined.connect(func(): joined.ok = true)
	b.join("127.0.0.1:%d" % a.port, "Bob")
	while not joined.ok:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[loader.difficulties.size() - 1 if args.has("hard") else 2]   # 既定は Normal(最初のノーツは 2.4 秒)。hard は最上位(自機狙い・弾数が多い)
	var found := SongLibrary.find_by_md5(bm.md5)
	chk.call(not found.is_empty(), "参加者が、MD5 から曲を見つけられる: %s" % str(found.get("path", "")).get_file())
	var lb := OszLoader.new()
	lb.open(found.path)
	var bmb = null
	for d in lb.difficulties:
		if d.md5 == bm.md5:
			bmb = d
	var mods: Array = [] if (fail_test or mode == "versus") else ["practice"]
	a.set_mode(mode)
	a.set_song({"md5": bm.md5, "title": bm.title, "artist": bm.artist, "version": bm.version, "level": 3.0}, mods, 1.0, loader, bm)
	b.report_song(true, lb, bmb)
	await get_tree().create_timer(0.4).timeout
	var gs := {}
	var done := {}
	var settings := {"offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0, "mods": []}
	var make := func(n, key: String, dodge: bool):
		n.prepare_game.connect(func(info):
			var g := GameScreen.new()
			g.setup_multi(n, info, n.song_loader, n.song_bm, settings)
			g.finished.connect(func(stats, music): done[key] = stats)
			if dodge:
				g.debug_move = func(): return _bot_dodge(g)
			else:
				g.debug_move = func(): return Vector2.ZERO   # 動かない(被弾し続ける)
			gs[key] = g
			add_child(g))
	make.call(a, "a", false)   # ホストは動かない
	make.call(b, "b", not fail_test)   # 参加者は避ける(fail のときは動かない)
	chk.call(a.start_game() == "", "開始できる(%s)" % mode)
	var t0 := Time.get_ticks_msec()
	while gs.size() < 2 or not (gs.a._audio_started and gs.b._audio_started):
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 > 10000:
			break
	chk.call(gs.size() == 2 and gs.a._audio_started and gs.b._audio_started, "全員の曲が始まる(%d ms)" % (Time.get_ticks_msec() - t0))
	chk.call(absf(gs.a._now - gs.b._now) < 0.06, "曲の時計が揃っている: a=%.3f b=%.3f" % [gs.a._now, gs.b._now])
	# しばらくプレイ(最初のノーツは 2.4 秒)
	var play_s := maxf(8.0, gs.a.sim.first_fire_time + 8.0) if not fail_test else 40.0   # 最初の弾のあと 8 秒ぶん
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < play_s * 1000.0 and not (gs.a.sim.finished or gs.b.sim.finished):
		await get_tree().process_frame
	var ga = gs.a
	var gb = gs.b
	print("  [%.1fs] a: now=%.2f gauge=%.3f hits=%d graze=%d score=%.0f bullets=%d | b: now=%.2f gauge=%.3f hits=%d graze=%d score=%.0f bullets=%d" % [
		play_s, ga._now, ga.sim.gauge, ga.sim.hits, ga.sim.graze, ga.sim.score, ga.field.count, gb._now, gb.sim.gauge, gb.sim.hits, gb.sim.graze, gb.sim.score, gb.field.count])
	if fail_test:
		await get_tree().create_timer(0.6).timeout   # ホストの決定が届くのを待つ
		chk.call(ga.sim.failed and gb.sim.failed, "全員が動かないと、ゲームオーバーが全員に届く(a=%s b=%s)" % [str(ga.sim.failed), str(gb.sim.failed)])
		chk.call(absf(ga.sim.death_time - gb.sim.death_time) < 0.5, "ほぼ同時に終わる: a=%.2f b=%.2f" % [ga.sim.death_time, gb.sim.death_time])
		t0 = Time.get_ticks_msec()
		while done.size() < 2 and Time.get_ticks_msec() - t0 < 8000:
			await get_tree().process_frame
		chk.call(done.size() == 2 and done.a.failed and done.b.failed, "両方がリザルトへ進む(ゲームオーバー)")
		await get_tree().create_timer(0.5).timeout
		chk.call(a.results.size() == 2 and b.results.size() == 2, "最終成績が全員に配られる")
		print("smoke-mp fail: ", "OK" if st.fails == 0 else "%d FAILED" % st.fails)
		get_tree().quit()
		return
	# 位置が届いている
	var rb: Vector2 = ga._mp.remotes[b.my_id].target
	var ra: Vector2 = gb._mp.remotes[1].target
	chk.call(rb.distance_to(gb.sim.player_pos) < 80.0 and ra.distance_to(ga.sim.player_pos) < 80.0, "互いの位置が届く: b を a から見た誤差 %.0fpx / a を b から見た誤差 %.0fpx" % [rb.distance_to(gb.sim.player_pos), ra.distance_to(ga.sim.player_pos)])
	chk.call(ga._mp.draw_list().size() == 1 and gb._mp.draw_list().size() == 1, "相手の自機の描画リスト")
	chk.call(absf(ga.field.count - gb.field.count) <= maxi(4, int(0.06 * ga.field.count)), "弾の数がほぼ同じ(a=%d b=%d)" % [ga.field.count, gb.field.count])
	if mode == "coop":
		chk.call(absf(ga.sim.gauge - gb.sim.gauge) < 0.06, "ゲージが共有されている: a=%.3f b=%.3f" % [ga.sim.gauge, gb.sim.gauge])
		chk.call(ga.sim.hits > 0 and absi(ga.sim.hits - gb.sim.hits) <= 1, "被弾回数が共有されている: a=%d b=%d" % [ga.sim.hits, gb.sim.hits])
		chk.call(absi(ga.sim.graze - gb.sim.graze) <= 4, "グレイズが共有されている: a=%d b=%d" % [ga.sim.graze, gb.sim.graze])
		chk.call(ga.sim.gauge < 1.0, "動かない a の被弾でゲージが減っている")
		# 全員が同じ弾になっている: a の弾それぞれについて、b の最も近い弾との距離(曲の時計のずれぶんは許す)
		var worst := 0.0
		for i in range(ga.field.count):
			var best := 1e9
			for j in range(gb.field.count):
				best = minf(best, ga.field.pos[i].distance_to(gb.field.pos[j]))
			worst = maxf(worst, best)
		chk.call(worst < 12.0, "弾の位置がほぼ一致(a の各弾から、b の最も近い弾までの最大 %.1fpx)" % worst)
	else:
		chk.call(gb.sim.gauge > ga.sim.gauge + 0.05 or ga.sim.gauge < 0.999, "対戦: ゲージは各自(a は被弾で減る、b は避けて減らない): a=%.3f b=%.3f" % [ga.sim.gauge, gb.sim.gauge])
		chk.call(gb.sim.score > ga.sim.score, "対戦: プレイ中は、避けた b のスコアが、動かない a より高い(a=%.0f、b=%.0f)" % [ga.sim.score, gb.sim.score])
		chk.call(ga._mp.remotes[b.my_id].score > 0.0 and absf(ga._mp.remotes[b.my_id].score - gb.sim.score) < 0.05 * maxf(gb.sim.score, 1.0) + 2000.0, "相手のスコアが届く: %.0f / %.0f" % [ga._mp.remotes[b.my_id].score, gb.sim.score])
	# 終盤へ飛んで、クリアまでの流れ
	var last: float = ga.sim.events[ga.sim.events.size() - 1].t
	ga._audio.seek((last - 0.5) * ga._rate)
	gb._audio.seek((last - 0.5) * gb._rate)
	t0 = Time.get_ticks_msec()
	while done.size() < 2 and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	chk.call(done.size() == 2, "両方がクリアしてリザルトへ進む(%d ms)" % (Time.get_ticks_msec() - t0))
	if done.size() == 2:
		print("  final a: score=%.0f hits=%d graze=%d failed=%s | b: score=%.0f hits=%d graze=%d failed=%s" % [done.a.score, done.a.hits, done.a.graze, str(done.a.failed), done.b.score, done.b.hits, done.b.graze, str(done.b.failed)])
		if mode == "coop":
			chk.call(not done.a.failed and not done.b.failed and absf(done.a.score - done.b.score) < 1.0 and done.a.hits == done.b.hits, "協力: 同じチームの結果(スコア・被弾)になる")
		else:
			chk.call(not done.a.failed and not done.b.failed and absf(done.a.score - done.b.score) > 1.0, "対戦: 各自が自分のスコアで終わる(a=%.0f、b=%.0f)" % [done.a.score, done.b.score])
	await get_tree().create_timer(0.6).timeout
	chk.call(a.results.size() == 2 and b.results.size() == 2, "最終成績が全員に配られる: %s" % str(a.results.keys()))
	if a.results.size() == 2:
		print("  results: ", str(a.results))
	print("smoke-mp %s: " % mode, "OK" if st.fails == 0 else "%d FAILED" % st.fails)
	get_tree().quit()


## ボット: 近くの弾から離れる(弾がなければ、下寄りの中央へ戻る)。
func _bot_dodge(g) -> Vector2:
	var p: Vector2 = g.sim.player_pos
	var f = g.field
	var v := Vector2.ZERO
	for i in range(f.count):
		var d: Vector2 = p - f.pos[i]
		var l := d.length()
		if l < 110.0 and l > 0.1:
			v += d / l * (110.0 - l) / 110.0
	v += (Vector2(480, 560) - p) * 0.004
	return v


## 開発用(スクリーンショット・確認): 自分がホストの部屋を作り、もう 1〜2 人(ボット)を参加させ、曲を設定しておく。参加者のプレイ画面は、見えない場所で動く。
var _shot_nets: Array = []


func _mp_room(mode: String, nosong: bool, three: bool) -> void:
	var n = _get_net()
	n.use_upnp = false
	n.host_room(mode, "Alice")
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[2]
	var names := ["Bob", "Carol"] if three else ["Bob"]
	for nm in names:
		var b = NetScript.new()
		b.use_upnp = false
		add_child(b)
		_shot_nets.append(b)
		var ok := {"v": false}
		b.joined.connect(func(): ok.v = true)
		b.join("127.0.0.1:%d" % n.port, nm)
		while not ok.v:
			await get_tree().process_frame
		b.report_song(true, loader, bm)
		b.prepare_game.connect(func(info):
			var g := GameScreen.new()
			g.setup_multi(b, info, loader, bm, {"offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0, "mods": []})
			g.debug_move = func(): return _bot_dodge(g)
			g.visible = false
			g.process_mode = Node.PROCESS_MODE_INHERIT
			add_child(g))
	await get_tree().create_timer(0.4).timeout
	if not nosong:
		n.set_song({"md5": bm.md5, "title": bm.title, "artist": bm.artist, "version": bm.version, "level": 4.62}, ["hell"] if mode == "versus" else [], 1.0, loader, bm)
	n.set_mode(mode)
	await get_tree().create_timer(0.4).timeout


## 開発用: マルチプレイの画面の流れを、ホスト側の実際の画面操作で通して確認する(参加者は同じプロセス内のボット)。-- --smoke-mp-ui
##   タイトル → マルチプレイ → 部屋を作る → 選曲(決定)→ ロビー → 開始 → プレイ画面(メニューを開いても止まらない)→ 退出 → タイトル
func _smoke_mp_ui() -> void:
	var original := Settings.load_all()
	var st := {"fails": 0}
	var chk := func(cond: bool, msg: String):
		print(("  ok   " if cond else "  FAIL ") + msg)
		if not cond:
			st.fails += 1
	var n = _get_net()
	n.use_upnp = false
	show_title()
	await get_tree().create_timer(1.0).timeout
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	await get_tree().create_timer(1.0).timeout
	var m = _current
	chk.call(m.get_script() == MultiScreen and m._page == "entry", "タイトルからマルチプレイの入口へ: %s / %s" % [m.get_script().resource_path.get_file(), m._page])
	m._on_create()
	await get_tree().create_timer(0.3).timeout
	chk.call(m._page == "lobby" and n.role == "host" and n.code != "", "部屋を作るとロビー(招待コード %s)" % n.code)
	# 参加者(ボット)
	var b = NetScript.new()
	b.use_upnp = false
	add_child(b)
	var ok := {"v": false, "left": "-"}
	b.joined.connect(func(): ok.v = true)
	b.left.connect(func(r): ok.left = r)
	b.join("127.0.0.1:%d" % n.port, "Bob")
	while not ok.v:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	chk.call(n.players.size() == 2, "参加者が入ると、ホストの名簿に載る")
	# 選曲
	m.pick_song_requested.emit()
	await get_tree().create_timer(1.0).timeout
	var menu = _current
	chk.call(menu.get_script() == MenuScreen and menu.pick_mode, "曲・MOD を選ぶ画面(選曲モード)")
	var idx := -1
	for i in range(menu._songs.size()):
		if menu._songs[i].path.contains("Reol"):
			idx = i
	menu._select_song(idx)
	await get_tree().create_timer(0.4).timeout
	menu._select_diff(2)
	var want_md5: String = menu._loader.difficulties[2].md5
	menu._start()
	await get_tree().create_timer(0.8).timeout
	m = _current
	chk.call(m.get_script() == MultiScreen and n.room.song.get("md5") == want_md5, "決定でロビーへ戻り、部屋に曲が設定される: %s" % str(n.room.song.get("title", "")))
	# 参加者は、MD5 から曲を探す(ロビー画面と同じ処理)
	var found := SongLibrary.find_by_md5(want_md5)
	var lb := OszLoader.new()
	lb.open(found.path)
	var bmb = null
	for d in lb.difficulties:
		if d.md5 == want_md5:
			bmb = d
	b.report_song(true, lb, bmb)
	b.prepare_game.connect(func(info):
		var g := GameScreen.new()
		g.setup_multi(b, info, lb, bmb, {"offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0, "mods": []})
		g.visible = false
		add_child(g))
	await get_tree().create_timer(0.5).timeout
	chk.call(m._start_blocker() == "", "全員が曲を持てば、開始できる('%s')" % m._start_blocker())
	m._on_start()
	var t0 := Time.get_ticks_msec()
	while not (_current.get_script() == GameScreen and _current._audio_started) and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	var g = _current
	chk.call(g.get_script() == GameScreen and g._mp != null and g._audio_started, "プレイ画面が始まる(%d ms)" % (Time.get_ticks_msec() - t0))
	await get_tree().create_timer(1.0).timeout
	# Esc でメニュー: ゲームは止まらない
	var before: float = g._now
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(1.0).timeout
	chk.call(g._mp_menu and not g._paused and g._pause_layer.visible and g._now > before + 0.8, "Esc でメニューが開くが、ゲームは止まらない(now %.2f → %.2f)" % [before, g._now])
	chk.call(not g._pause_btns[1].visible and g._pause_btns[2].text == "退出", "リトライはなく、「退出」になる")
	await _key(KEY_DOWN)
	chk.call(g._pause_sel == 2, "↓ でリトライを飛ばして「退出」へ(sel=%d)" % g._pause_sel)
	await _key(KEY_ENTER)
	await get_tree().create_timer(1.0).timeout
	chk.call(_current.get_script() == TitleScreen and n.role == "", "退出するとタイトルへ戻り、部屋を出る")
	t0 = Time.get_ticks_msec()
	while ok.left == "-" and Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
	chk.call(ok.left != "-" and ok.left != "", "ホストが抜けると、参加者に「%s」と届く" % ok.left)
	Settings.restore(original)
	print("smoke-mp-ui: ", "OK" if st.fails == 0 else "%d FAILED" % st.fails)
	get_tree().quit()


## 開発用(スクリーンショット): 自分は参加者、ホストはボット。nosong なら、自分はその曲を持っていない状態にする。
func _mp_guest_room(nosong: bool) -> void:
	var h = NetScript.new()
	h.use_upnp = false
	add_child(h)
	_shot_nets.append(h)
	h.host_room("coop", "Alice")
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[3]
	h.set_song({"md5": "0".repeat(32) if nosong else bm.md5, "title": bm.title, "artist": bm.artist, "version": bm.version, "level": 4.62, "set_id": bm.beatmapset_id, "map_id": bm.beatmap_id}, ["dark"], 1.0, loader, bm)   # nosong: 参加者の手元にない曲(MD5 が見つからない)
	var n = _get_net()
	n.use_upnp = false
	var ok := {"v": false}
	n.joined.connect(func(): ok.v = true)
	n.join("127.0.0.1:%d" % h.port, "Bob")
	while not ok.v:
		await get_tree().process_frame
	if not nosong:
		n.report_song(true, loader, bm)
	await get_tree().create_timer(0.6).timeout


## 開発用: UPnP を使う本番と同じ部屋作り(ルーターのポートを一時的に開けて、すぐ閉じる)。招待コードの中身を確認する。-- --smoke-upnp
func _smoke_upnp() -> void:
	var InviteCode = load("res://scripts/net/invite_code.gd")
	var n = NetScript.new()
	add_child(n)
	var ev := {"code": false}
	n.code_changed.connect(func(): ev.code = true)
	var t0 := Time.get_ticks_msec()
	print("host_room: ", n.host_room("versus", "Test"))
	while not ev.code and Time.get_ticks_msec() - t0 < 12000:
		await get_tree().process_frame
	print("code=%s  (%d ms)  note=%s" % [n.code, Time.get_ticks_msec() - t0, n.code_note])
	print("decoded: ", InviteCode.decode(n.code))
	n.leave()   # ポートを閉じる
	print("closed")
	get_tree().quit()


## 開発用: ホイールで音量が変わること(メーターの表示・選択・消えたら戻る)を、実際の入力で確認する。-- --smoke-volume
func _smoke_volume() -> void:
	var original := Settings.load_all()
	var st := {"fails": 0}
	var chk := func(cond: bool, msg: String):
		print(("  ok   " if cond else "  FAIL ") + msg)
		if not cond:
			st.fails += 1
	overlay = HudOverlay.new()
	add_child(overlay)
	Volume.set_master(50)
	Volume.set_music(60)
	Volume.set_sfx(70)
	show_title()
	await get_tree().create_timer(0.8).timeout
	var wheel := func(up: bool):
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = true
		e.position = Vector2(900, 400)
		e.global_position = e.position
		Input.parse_input_event(e)
		await get_tree().process_frame
		await get_tree().process_frame
	await wheel.call(true)
	await wheel.call(true)
	chk.call(Volume.master == 60 and Volume.music == 60 and overlay._shown and overlay._panel.visible, "ホイールを 2 回: 全体音量 50 → %d、メーターが出る" % Volume.master)
	await wheel.call(false)
	chk.call(Volume.master == 55, "ホイール下で下がる: %d" % Volume.master)
	# 音楽のメーターをクリックして選ぶ
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	overlay._rows[1].gui_input.emit(click)
	await wheel.call(true)
	chk.call(overlay._sel == 1 and Volume.music == 65 and Volume.master == 55, "「音楽」を選んで回すと音楽だけ変わる: 音楽 %d / 全体 %d" % [Volume.music, Volume.master])
	overlay._rows[2].gui_input.emit(click)
	await wheel.call(false)
	chk.call(Volume.sfx == 65 and Volume.music == 65, "「効果音」を選んで回すと効果音だけ変わる: 効果音 %d" % Volume.sfx)
	# 触れずにいると消えて、選択が戻る
	await get_tree().create_timer(2.4).timeout
	chk.call(not overlay._shown and not overlay._panel.visible and overlay._sel == 0, "しばらくすると消えて、選択は「全体」に戻る")
	await wheel.call(true)
	chk.call(Volume.master == 60 and Volume.sfx == 65 and overlay._sel == 0, "次に回すと、また全体音量が変わる: 全体 %d / 効果音 %d" % [Volume.master, Volume.sfx])
	# 保存される
	await get_tree().create_timer(2.4).timeout
	var saved := ConfigFile.new()
	saved.load(Settings.PATH)
	chk.call(int(saved.get_value("game", "volume", -1)) == 60 and int(saved.get_value("game", "sfx_volume", -1)) == 65 and int(saved.get_value("game", "music_volume", -1)) == 65, "消えたときに保存される(全体 %s / 音楽 %s / 効果音 %s)" % [str(saved.get_value("game", "volume")), str(saved.get_value("game", "music_volume")), str(saved.get_value("game", "sfx_volume"))])
	# 古い設定を持った画面が保存しても、変えた音量を戻さない
	var stale := Settings.load_all()
	stale.volume = 1
	Settings.save_all(stale)
	var saved2 := ConfigFile.new()
	saved2.load(Settings.PATH)
	chk.call(int(saved2.get_value("game", "volume", -1)) == 60, "古い値を持った画面が保存しても、音量は戻らない")
	Settings.restore(original)
	print("smoke-volume: ", "OK" if st.fails == 0 else "%d FAILED" % st.fails)
	get_tree().quit()


## 開発用: .osz を開いたときの流れ(取り込み → 選曲画面で選ぶ)と、別のプロセスから渡す動きを確認する。-- --smoke-open
func _smoke_open() -> void:
	var original := Settings.load_all()
	var st := {"fails": 0}
	var chk := func(cond: bool, msg: String):
		print(("  ok   " if cond else "  FAIL ") + msg)
		if not cond:
			st.fails += 1
	overlay = HudOverlay.new()
	add_child(overlay)
	_instance = SingleInstance.new()
	add_child(_instance)
	chk.call(_instance.start(), "待ち受けを始める(127.0.0.1:%d)" % SingleInstance.PORT)
	_instance.file_received.connect(_on_open_osz)
	get_window().files_dropped.connect(_on_files_dropped)
	show_title()
	await get_tree().create_timer(1.0).timeout
	# 別のプロセスが、.osz をつけて起動する → こちらへ渡して、自分は終わる
	var osz := "C:/Desktop/my_apps/DDA/241526 Soleily - Renatus.osz"
	var pid := OS.create_process(OS.get_executable_path(), ["--path", ProjectSettings.globalize_path("res://"), "--", osz])
	var t0 := Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().process_frame
	chk.call(not OS.is_process_running(pid), "あとから起動したほうは、渡して終了する(%d ms)" % (Time.get_ticks_msec() - t0))
	await get_tree().create_timer(1.5).timeout
	chk.call(_current.get_script() == MenuScreen, "こちらは選曲画面へ移る: %s" % _current.get_script().resource_path.get_file())
	var m = _current
	chk.call(m._song_sel >= 0 and m._songs[m._song_sel].path.contains("Soleily"), "開いた曲が選ばれている: %s" % (m._songs[m._song_sel].path.get_file() if m._song_sel >= 0 else "-"))
	# 別の曲を、ウィンドウへのドロップの代わりに直接開く(取り込み済みなので、そのまま使う)
	_on_open_osz("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	await get_tree().create_timer(1.5).timeout
	m = _current
	chk.call(m.get_script() == MenuScreen and m._songs[m._song_sel].path.contains("Reol"), "続けて別の曲を開くと、その曲が選ばれる")
	# プレイ中は、画面を変えない
	start_game(m._loader, m._loader.difficulties[0], {"mods": ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
	await get_tree().create_timer(1.0).timeout
	var g = _current
	_on_open_osz("C:/Desktop/my_apps/DDA/241526 Soleily - Renatus.osz")
	await get_tree().create_timer(0.8).timeout
	chk.call(_current == g and g.get_script() == GameScreen, "プレイ中に開いても、画面は変わらない(通知だけ)")
	# 壊れたファイルは通知を出すだけ
	_on_open_osz("C:/Desktop/my_apps/DDA/README.md")
	await get_tree().create_timer(0.5).timeout
	chk.call(_current == g, "対応しないファイルでは、何も起きない")
	Settings.restore(original)
	print("smoke-open: ", "OK" if st.fails == 0 else "%d FAILED" % st.fails)
	get_tree().quit()


## 開発用: アプリ内アップデートの流れを、手元のサーバー(tests/fake_release_server.js)で確認する。-- --smoke-update <APIのURL> [apply]
##   確認 → ダウンロード → 検証 → 取り出し(apply をつけると、そのあと入れ替えて再起動まで)
func _smoke_update() -> void:
	var args := OS.get_cmdline_user_args()
	var url: String = args[args.find("--smoke-update") + 1]
	var st := {"fails": 0}
	var chk := func(cond: bool, msg: String):
		print(("  ok   " if cond else "  FAIL ") + msg)
		if not cond:
			st.fails += 1
	updater = Updater.new()
	add_child(updater)
	updater.api_url = url
	updater.allow_any_url = true
	updater.force_apply = true
	var ev := {"info": null, "staged": false, "failed": ""}
	updater.check_finished.connect(func(i): ev.info = i)
	updater.staged.connect(func(): ev.staged = true)
	updater.failed.connect(func(m): ev.failed = m)
	updater.check()
	while ev.info == null:
		await get_tree().process_frame
	var info: Dictionary = ev.info
	chk.call(info.ok and info.newer, "新しいバージョンを見つける: 現在 %s → %s (%s)" % [updater.current, str(info.get("version", "")), "newer" if info.get("newer", false) else "-"])
	chk.call(str(info.get("digest", "")).begins_with("sha256:") and int(info.get("asset_size", 0)) > 0, "サイズとハッシュが分かる: %d bytes %s" % [int(info.get("asset_size", 0)), str(info.get("digest", "")).left(18)])
	updater.start_download()
	var t0 := Time.get_ticks_msec()
	while not ev.staged and ev.failed == "" and Time.get_ticks_msec() - t0 < 120000:
		await get_tree().process_frame
	if args.has("expect-fail"):
		chk.call(ev.failed != "" and not ev.staged, "壊れたダウンロードは断る: %s" % ev.failed)
		print("smoke-update: ", "OK" if st.fails == 0 else "%d FAILED" % st.fails)
		get_tree().quit()
		return
	chk.call(ev.staged, "ダウンロード・検証・取り出しができる(%d ms)%s" % [Time.get_ticks_msec() - t0, " " + ev.failed if ev.failed != "" else ""])
	chk.call(FileAccess.file_exists(updater.stage_dir.path_join("DDA.exe")) and FileAccess.file_exists(updater.stage_dir.path_join("README.txt")), "DDA.exe と README.txt が取り出されている")
	print("smoke-update: ", "OK" if st.fails == 0 else "%d FAILED" % st.fails)
	if args.has("apply") and st.fails == 0:
		print("applying...")
		updater.apply_and_quit()
		return
	get_tree().quit()
