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
const SfxBank = preload("res://scripts/sfx_bank.gd")
const HpGraph = preload("res://scripts/ui/hp_graph.gd")
const FpsOverlay = preload("res://scripts/ui/fps_overlay.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiFx = preload("res://scripts/ui/ui_fx.gd")
const Volume = preload("res://scripts/volume.gd")
const HudOverlay = preload("res://scripts/ui/hud_overlay.gd")
const Updater = preload("res://scripts/updater.gd")
const UpdatePanel = preload("res://scripts/ui/update_panel.gd")
const HowToPanel = preload("res://scripts/ui/howto_panel.gd")
const OszImport = preload("res://scripts/osz_import.gd")
const SingleInstance = preload("res://scripts/single_instance.gd")
const CursorOverlay = preload("res://scripts/ui/cursor_overlay.gd")
const OptionsPanel = preload("res://scripts/ui/options_panel.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const Juice = preload("res://scripts/ui/juice.gd")
const ScreenWipe = preload("res://scripts/ui/screen_wipe.gd")

var _current: Node
var _ui_layer: CanvasLayer         # 設定・選択のパネルを、画面の上に重ねる層
var _settings_panel: Control       # 開いている設定パネル(どの画面からでも開ける。プレイ中は除く)
var _settings_dict: Dictionary = {}
var _settings_btn: Button          # 画面の右上の「設定」(タイトル・選曲画面は、自分で設定を開く入口を持つので出さない)
var _watch_known := {}             # songs フォルダに、いま見えている .osz(名前|大きさ → パス)
var _watch_pending := {}           # 見つけたが、コピーの途中かもしれないもの(大きさが落ち着くまで待つ)
var _watch_ready := false
var _watch_t := 0.0
var net                    # 通信層(マルチプレイを開くときに作る。部屋を出ても使い回す)
var _last_play := {}
var overlay                # 音量メーター・通知(全画面の上)
var updater                # アプリ内アップデート(GitHub のリリースを確認する)
var _instance            # 1 つだけ動かして、あとから開いた .osz を受け取る
var _music: AudioStreamPlayer = null   # クリアで引き継いだ曲(リザルト中に流れ続ける)

## 画面切替の暗転フェード(通常起動のときだけ。開発用フックは即時に切り替える)
var _fade_enabled := false
var _wipe: Node                    # 画面の切り替えの幕(斜めのワイプ)
var _fading := false
var _f11_down := false              # F11 を押している間(押した瞬間だけ全画面を切り替えるため)
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
	if args.has("--smoke-new"):
		_smoke_new()
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
	if args.has("--smoke-start"):
		_smoke_start()
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
	if args.has("--smoke-sfx"):
		_smoke_sfx()
		return
	if args.has("--smoke-speed-study"):
		_smoke_speed_study()
		return
	if args.has("--smoke-autoupdate"):
		_smoke_autoupdate()
		return
	if args.has("--smoke-modscroll"):
		_smoke_modscroll()
		return
	if args.has("--prof-play"):
		_prof_play()
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
	var ui_settings := Settings.load_all()
	UiSfx.enabled = bool(ui_settings.ui_sound)
	SfxBank.preload_all(["pop", "whistle", "clap", "boom", "tick", "hit", "explosion"])   # ゲーム中の効果音は、プレイ画面を開く前に読んでおく
	Settings.apply_display(ui_settings)   # 垂直同期・ウィンドウの大きさ
	add_child(UiSfx.new())   # UI の効果音(ホバー・クリック・開閉など)
	add_child(Juice.new())   # すべてのボタン・スライダーに、弾む動きと音を自動でつける
	_setup_fade()
	overlay = HudOverlay.new()
	add_child(overlay)
	add_child(FpsOverlay.new())   # 右下の FPS 表示(設定の「画面」/ F3)
	add_child(CursorOverlay.new())   # アプリ独自のマウスカーソル(OS のカーソルは、ウィンドウの中では隠す)
	_setup_ui_layer()
	_watch_sync()
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
		_maybe_auto_update(info)


## 起動時の自動更新: 新しいバージョンが見つかったら、タイトル画面でパネルを開き、すぐダウンロード → 入れ替え → 再起動する。
## 次のときは自動で始めない(案内のボタンだけ残る): 設定で切ってある / 書き出した版でない・書き込めない場所 / もう別の操作を始めている /
## 前回この版で自動更新を始めたのに、まだ古いまま(版の付け間違いなどで、更新を繰り返し続けないための印。使う人が途中でキャンセルしたときは、印を戻す)。
func _maybe_auto_update(info: Dictionary) -> bool:
	var st := Settings.load_all()
	if not (bool(st.check_update) and bool(st.auto_update)):
		return false
	if updater == null or not updater.can_self_update():
		return false
	if str(st.last_auto_update) == str(info.get("version", "")):
		return false
	var t = _current
	if t == null or t.get_script() != TitleScreen or t._overlay != null or t._leaving or _settings_panel != null or _fading:
		return false
	st.last_auto_update = str(info.get("version", ""))
	Settings.save_all(st)
	var p := UpdatePanel.new()
	p.setup(updater)
	p.auto_start = true
	p.cancelled.connect(func():
		var s2 := Settings.load_all()
		s2.last_auto_update = ""
		Settings.save_all(s2))
	t._open(p)
	return true


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
	_open_in_dda(path)


## このアプリで開く(取り込んで、選曲画面でその曲を選んだ状態にする)。
func _open_in_dda(path: String) -> void:
	var r := OszImport.import_file(path)
	if not r.ok:
		if overlay != null:
			overlay.toast(str(r.error))
		if _current == null:
			show_title()
		return
	_watch_sync()   # 取り込んだ曲は、フォルダの監視には「新しい曲」として知らせない
	if overlay != null:
		overlay.toast(("%s を開きます" if r.existed else "%s を取り込みました") % (str(r.title) if str(r.title) != "" else str(r.path).get_file()))
	if _current != null and (_current.get_script() == GameScreen or _current.get_script() == MultiScreen):
		return
	var st := Settings.load_all()
	st.last_song = r.path
	st.last_diff = ""
	Settings.save_all(st)
	show_menu()


## ウィンドウに .osz をドロップした(どの画面でも同じ)。すべて取り込み(songs にコピー。次の起動でも残る)、最後の曲を選ぶ。
## 選曲画面では、画面を作り直さずに一覧へ足して選ぶ。プレイ中・ロビーでは取り込みだけ。
func _on_files_dropped(files: PackedStringArray) -> void:
	var oszs: Array = []
	for f in files:
		if str(f).to_lower().ends_with(".osz"):
			oszs.append(str(f).replace("\\", "/"))
	if oszs.is_empty():
		if overlay != null and _current != null:
			overlay.toast(".osz ファイル以外は取り込めません")
		return
	if UiStyle.animate and _current is Control:   # 受け取った合図: 画面の真ん中から輪が広がる(ドロップされるまで、アプリは何も知らされないので、これが最初の反応)
		UiFx.ring(_current, Vector2(640, 360), UiStyle.ACCENT, 30.0, 560.0, 0.7, 3.0)
	var imported := 0
	for i in range(oszs.size() - 1):   # 最後の 1 つ以外は、取り込みだけ
		if OszImport.import_file(oszs[i]).ok:
			imported += 1
	var last: String = oszs[oszs.size() - 1]
	if _current != null and _current.get_script() == MenuScreen:
		var r := OszImport.import_file(last)
		if not r.ok:
			if overlay != null:
				overlay.toast(str(r.error))
			return
		_watch_sync()
		_current.refresh_songs()
		_current.select_path(str(r.path))
		if overlay != null:
			var name := str(r.title) if str(r.title) != "" else str(r.path).get_file()
			overlay.toast("%d 曲を取り込みました" % (imported + 1) if oszs.size() > 1 else (("%s を開きます" if r.existed else "%s を取り込みました") % name))
		return
	_open_in_dda(last)
	if oszs.size() > 1 and overlay != null:
		overlay.toast("%d 曲を取り込みました" % (imported + 1))


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
	close_settings()   # 画面が変わるときは、開いている設定は閉じる
	if _current != null:
		_current.queue_free()
	_current = n
	add_child(n)
	_update_settings_button()


# --- 設定(プレイ中以外の、どの画面からでも開ける) ---

## 設定・選択のパネルを重ねる層と、右上の「設定」ボタンを用意する(1 度だけ)。
func _setup_ui_layer() -> void:
	if _ui_layer != null:
		return
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 80   # 画面より上、音量メーター(90)・カーソル(127)・暗転(100)より下
	add_child(_ui_layer)
	_settings_btn = Button.new()
	_settings_btn.theme = UiStyle.make_theme()
	_settings_btn.text = "設定"
	_settings_btn.focus_mode = Control.FOCUS_NONE
	_settings_btn.position = Vector2(1174, 14)
	_settings_btn.size = Vector2(90, 34)
	_settings_btn.pressed.connect(func(): open_settings(0))
	_settings_btn.visible = false
	_ui_layer.add_child(_settings_btn)


## 右上の「設定」ボタンを出すか。プレイ中は出さない。タイトル・選曲画面は自分の入口があるので出さない。パネルが開いている間も出さない。
func _update_settings_button() -> void:
	if _settings_btn == null:
		return
	var s = _current.get_script() if _current != null else null
	_settings_btn.visible = _current != null and s != GameScreen and s != TitleScreen and s != MenuScreen and _settings_panel == null


## 設定パネルを開く(section: 0=操作 1=音 2=画面 3=その他)。いまの画面が設定の辞書(settings)を持っていれば、それを直接変える。
func open_settings(section := 0) -> void:
	if _settings_panel != null or _current == null or _current.get_script() == GameScreen:
		return
	_setup_ui_layer()
	var st = _current.get("settings")
	_settings_dict = st if st is Dictionary else Settings.load_all()
	var p := OptionsPanel.new()
	p.theme = UiStyle.make_theme()
	p.setup(_settings_dict)
	p.changed.connect(func(kind: String):
		if _current != null and _current.has_method("on_settings_changed"):
			_current.on_settings_changed(kind))
	p.closed.connect(close_settings)
	_ui_layer.add_child(p)
	p.show_section(section)
	_settings_panel = p
	if "_options" in _current:
		_current._options = p
	_current.set_process_input(false)   # 開いている間、下の画面は Esc や矢印に反応しない(パネルより先にキーを受け取ってしまうため)
	_update_settings_button()


func close_settings() -> void:
	if _settings_panel == null:
		return
	Settings.save_all(_settings_dict)
	var p := _settings_panel
	_settings_panel = null
	if _current != null and "_options" in _current:
		_current._options = null
	if is_instance_valid(_current):
		_current.set_process_input(true)
	p.queue_free()
	_update_settings_button()


func _setup_fade() -> void:
	_wipe = ScreenWipe.new()
	add_child(_wipe)
	_fade_enabled = true


## 画面の切り替え: 幕が覆う → 入れ替え → 幕が抜けて新しい画面が現れる。覆っている間にさらに要求が来たら、新しいほうだけ使う。
func _run_fade() -> void:
	_fading = true
	UiSfx.play("whoosh")
	while _pending != null:
		await _wipe.cover()
		var n := _pending
		_pending = null
		_swap_now(n)
		await get_tree().process_frame   # 新しい画面を作った重いフレームは、幕の裏で済ませる
		await _wipe.reveal()
	_fading = false


## タイトル画面(起動時)。プレイ → 選曲画面。遊び方・設定はタイトルの上に重なるパネル。
func show_title() -> void:
	var t := TitleScreen.new()
	t.play_requested.connect(show_menu)
	t.multi_requested.connect(show_multi)
	t.settings_requested.connect(open_settings)
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
	m.settings_requested.connect(open_settings)
	if pick:
		m.song_picked.connect(_on_song_picked)
		m.back_requested.connect(func(): show_multi())
	else:
		m.play_requested.connect(func(l, b, st: Dictionary, pre: Dictionary): start_game(l, b, st, -1.0, -1.0, pre))
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
			settings.mods, 1.0, loader, bm)
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


func start_game(loader, bm, settings: Dictionary, debug_seek := -1.0, debug_death_t := -1.0, pre := {}) -> void:
	_last_play = {"loader": loader, "bm": bm, "settings": settings, "pre": pre}
	var g := GameScreen.new()
	g.setup(loader, bm, settings)
	g.pre = pre
	g.debug_seek = debug_seek
	g.debug_death_t = debug_death_t
	g.finished.connect(func(stats, music): show_result(stats, music))
	g.quit_requested.connect(show_menu)
	g.retry_requested.connect(func(): start_game(loader, bm, settings, -1.0, -1.0, pre))
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
			start_game(_last_play.loader, _last_play.bm, _last_play.settings, -1.0, -1.0, _last_play.get("pre", {})))
	if music != null:
		_stop_music(0.0)
		_music = music
		add_child(music)
		music.finished.connect(func(): if _music == music: _stop_music(0.0))
	_swap(r, music != null)


# --- songs フォルダの見張り(.osz を置いたら、アプリの中で知らせる) ---

## いま見えている曲を「すでにあるもの」として覚える(取り込んだあと・起動したときに呼ぶ)。
func _watch_sync() -> void:
	_watch_known = SongLibrary.snapshot()
	_watch_pending.clear()
	_watch_ready = true


func _process(delta: float) -> void:
	_poll_fullscreen_key()
	_watch_t += delta
	if _watch_t < 2.0:
		return
	_watch_t = 0.0
	if overlay == null or _current == null or _current.get_script() == GameScreen:
		return   # 通常の起動でだけ、プレイ中以外に見張る
	_watch_poll()


## F11 で全画面 ⇔ ウィンドウ。パネルがキーを全部受け止めている間も効くよう、押した瞬間を見て判断する。プレイ中(ポーズ以外)は効かない。
func _poll_fullscreen_key() -> void:
	var down := Input.is_key_pressed(KEY_F11)
	var edge := down and not _f11_down
	_f11_down = down
	if not edge or _current == null or _fading:
		return
	if _current.get_script() == GameScreen and not _current._paused:
		return
	var st = _current.get("settings")
	var d: Dictionary = _settings_dict if _settings_panel != null else (st if st is Dictionary else Settings.load_all())
	Settings.toggle_fullscreen(d)
	Settings.save_all(d)
	if _settings_panel != null:
		_settings_panel.refresh_size.call_deferred()   # 開いている設定の「解像度」の表示も合わせる


## 新しく置かれた .osz を見つけて知らせる。コピーの途中かもしれないので、大きさが 2 回続けて同じになってから(読めたら)知らせる。
func _watch_poll() -> void:
	if not _watch_ready:
		_watch_sync()   # まだ覚えていない(初めて): いまあるものを「すでにあるもの」にして、知らせずに始める
		return
	var now := SongLibrary.snapshot()
	var added: Array = []
	for k in now:
		if _watch_known.has(k):
			continue
		var sz := int(str(k).get_slice("|", 1))
		if sz > 0 and _watch_pending.get(k, -2) == sz:
			_watch_known[k] = now[k]
			_watch_pending.erase(k)
			added.append(now[k])
		else:
			_watch_pending[k] = sz
	for k in _watch_known.keys():   # 消えたものは、忘れる(同じ曲をもう一度置いたら、また知らせる)
		if not now.has(k):
			_watch_known.erase(k)
	for k in _watch_pending.keys():
		if not now.has(k):
			_watch_pending.erase(k)
	if added.is_empty():
		return
	var ok := 0
	var last_title := ""
	var failed := ""
	for p in added:
		var info := SongLibrary.info(p)
		if info.ok:
			ok += 1
			last_title = "%s - %s" % [info.artist, info.title]
		else:
			failed = str(p).get_file()
	SongLibrary.save_index()
	var msg := ""
	if ok == 1:
		msg = "曲が追加されました: " + last_title
	elif ok > 1:
		msg = "曲が %d 件追加されました" % ok
	if failed != "":
		msg += ("    " if msg != "" else "") + "読み込めませんでした: " + failed
	overlay.toast(msg)
	if ok > 0 and _current != null and _current.has_method("refresh_songs"):
		_current.refresh_songs()


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
## 開発用: スクリーンショットで使う曲。指定の .osz がこの環境になければ、見つかった最初の曲を使う。
func _dev_osz(path: String) -> String:
	if FileAccess.file_exists(path):
		return path
	var found := SongLibrary.find_all()
	return str(found[0]) if not found.is_empty() else path


func _shot(kind: String, out: String, extra: Array, animated := false) -> void:
	match kind:
		"title":
			show_title()   # 例: --shot title out.png [howto|options|quit] [fps]
			if extra.size() > 0 and extra[0] == "howto":
				_current._activate(2)
				if extra.size() > 1 and extra[1].is_valid_int():
					_current._overlay._show(int(extra[1]))
			elif extra.size() > 0 and extra[0] == "options":
				_current._activate(3)
			elif extra.size() > 0 and extra[0] == "quit":
				_current._activate(4)   # 終了の確認
			if extra.has("fps"):   # FPS 表示つき
				FpsOverlay.enabled = true
				add_child(FpsOverlay.new())
				await get_tree().create_timer(1.2).timeout
		"menu":
			show_menu()
			_current.debug_set_mods(extra.filter(func(x): return not Mods.find(x).is_empty()))   # 例: --shot menu out.png rush storm
			if extra.has("empty"):   # 曲が 1 つもない状態: --shot menu out.png empty
				await _current.debug_empty()
			if extra.has("loading"):   # 曲の読み込み中の見た目: --shot menu out.png loading
				await _current.debug_loading()
		"cursor":
			show_menu()   # 独自カーソル(押せるもの・ふつうの場所)。例: --shot cursor out.png hover|idle
			var cu := CursorOverlay.new()
			add_child(cu)
			cu._inside = true
			cu._focused = true
			var at := Vector2(700, 262) if extra.has("hover") else Vector2(700, 600)
			cu.debug_pos = at
			for n in range(30):
				await get_tree().process_frame
		"mod":
			show_menu()   # MOD パネル。例: --shot mod out.png rush storm
			while _current._job_pending or _current._diff_cards.is_empty():   # 曲の読み込みを待つ
				await get_tree().process_frame
			_current.debug_set_mods(extra.filter(func(x): return not Mods.find(x).is_empty()))
			_current.open_mods()
		"options":
			show_menu()   # 例: --shot options out.png 2(先頭の数字はセクション 0=操作 1=音 2=画面 3=その他)
			_current.debug_set_mods(extra.filter(func(x): return not Mods.find(x).is_empty()))
			_current.open_options(int(extra[0]) if extra.size() > 0 and extra[0].is_valid_int() else 0)
		"game":
			var loader := OszLoader.new()
			var path := "C:/Desktop/my_apps/DDA/320118 Reol - No title.osz"
			if extra.size() > 3 and extra[3] == "soleily":
				path = "C:/Desktop/my_apps/DDA/241526 Soleily - Renatus.osz"
			loader.open(_dev_osz(path))
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
			nn.results = {1: {"name": "Alice", "score": 903120.0, "hits": 0, "graze": 214, "hit_ms": 0}, 2: {"name": "Bob", "score": 871400.0, "hits": 3, "graze": 180, "hit_ms": 480,
				"hp": HpGraph.downsample(HpGraph.points_from_log(_fake_hp(2, 118.0, false, 3).hp_log, 0.25, 118.0, 0.7), 48), "dur": 118.0}}
			var mode_r := "coop" if extra.has("coop") else "versus"
			show_result({"title": "Reol - No title [Insane]", "level": 5.8, "mean": 105.0, "peak": 141.0, "failed": false, "progress": 1.0, "hits": 3, "hit_ms": 480, "graze": 394, "score": 903120.0, "score_gross": 1013000.0,
				"damage_factor": 0.89, "score_graze": 13000.0, "practice": false, "score_base": 1000000.0, "mod_ids": [], "mods": "",
				"mp": {"mode": mode_r, "my_id": 1, "players": [{"id": 1, "name": "Alice", "slot": 0}, {"id": 2, "name": "Bob", "slot": 1}, {"id": 3, "name": "Carol", "slot": 2}]}}.merged(_fake_hp(1, 118.0, false, 3)))
			_current.skip_animation()
		"bullets":
			_shot_bullets()
		"result":
			var rl := OszLoader.new()
			rl.open(_dev_osz("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz"))
			var rbm = rl.difficulties[rl.difficulties.size() - 1]
			show_result({"title": "Reol - No title [Insane]", "level": 5.8, "mean": 105.0, "peak": 141.0, "failed": extra.size() > 0 and extra[0] == "failed", "progress": 0.63, "hits": 0 if extra.has("ss") else 2, "hit_ms": 180, "graze": 123, "score": 1013000.0 if extra.has("ss") else (300000.0 if extra.has("f") else 830660.0), "score_gross": 1013000.0, "damage_factor": 0.82, "score_graze": 13000.0, "practice": false,
				"score_base": 1060000.0, "mod_ids": ["hell", "rush"], "mods": "地獄 + 加速",
				"bg": rl.load_image(rbm.background) if rbm.background != "" else null}.merged(_fake_hp(1, 118.0, extra.size() > 0 and extra[0] == "failed", 3)))
			_current.skip_animation()   # スクリーンショットでは、演出を待たない
	_setup_ui_layer()   # 右上の「設定」ボタンも撮る
	_update_settings_button()
	if animated:
		var t0 := Time.get_ticks_msec()
		var k := 0
		var times := [0.1, 0.3, 0.6, 1.2, 2.5]
		for e in extra:   # 例: t=0.7,0.8,0.9 で、撮る時刻(開いてからの秒)を指定できる
			if str(e).begins_with("t="):
				times = str(e).trim_prefix("t=").split(",")
				times = times.map(func(x): return float(x))
		for at in times:
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
	while _current != null and "_job_pending" in _current and _current._job_pending:   # 選曲画面は、曲の読み込み(別スレッド)を待つ
		await get_tree().process_frame
	for n in range(4):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()


## 開発用: 結果画面の見た目確認用の、作り物の体力の推移(0.25 秒ごと。被弾のたびに減り、少しずつ戻る)。
func _fake_hp(seed_n: int, dur: float, fail: bool, n_hits: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	var hit_times := PackedFloat32Array()
	for k in range(n_hits):
		hit_times.append(rng.randf_range(12.0, dur - 12.0))
	hit_times.sort()
	var log := PackedFloat32Array()
	var g := 1.0
	var i := 0
	var t := 0.0
	var end_t := dur if not fail else dur * 0.63
	while t <= end_t:
		for h in hit_times:
			if h >= t and h < t + 0.25:
				g -= rng.randf_range(0.18, 0.3) * (2.2 if fail else 1.0)
		g = clampf(g + 0.015 * 0.25, 0.0, 1.0)
		log.append(g)
		t += 0.25
	return {"hp_log": log, "hp_step": 0.25, "hp_end": 0.0 if fail else g, "hp_t_end": end_t, "hit_log": hit_times, "breaks": [[48.0, 60.0]], "first_fire": 8.0}


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


## ノードの下から、題名の文字が name のラベルを持つカードを探す(開発用)。
func _find_card(root: Node, name: String) -> Control:
	for c in root.find_children("*", "PanelContainer", true, false):
		for l in c.find_children("*", "Label", true, false):
			if (l as Label).text.begins_with(name) and c.has_meta("state"):
				return c
	return null


## 開発用: 選曲・設定・ポーズの操作を、実際のキー入力で通しで確認する。-- --smoke-ui(ユーザーの設定ファイルは終了時に元へ戻す)
func _smoke_ui() -> void:
	var orig := Settings.load_all()
	show_menu()
	for i in range(4):
		await get_tree().process_frame
	var m = _current
	while m._job_pending:   # 曲の読み込み(別スレッド)を待つ
		await get_tree().process_frame
	print("menu: songs=%d diffs=%d diff_sel=%d play_enabled=%s" % [m._song_cards.size(), m._diff_cards.size(), m._diff_sel, str(not m._play_btn.disabled)])
	# ↑↓ は常に曲、← → は常に難易度
	var song_before: int = m._song_sel
	await _key(KEY_DOWN)
	print("Down       -> song_sel %d -> %d (expect +1)  loading=%s play_enabled=%s (expect true, false)" % [song_before, m._song_sel, str(m._job_pending), str(not m._play_btn.disabled)])
	while m._job_pending:
		await get_tree().process_frame
	var diff_before: int = m._diff_sel
	await _key(KEY_RIGHT)
	print("Right      -> diff_sel %d -> %d (expect +1 unless last)  song_sel=%d (expect unchanged)" % [diff_before, m._diff_sel, m._song_sel])
	await _key(KEY_LEFT)
	await _key(KEY_UP)
	while m._job_pending:
		await get_tree().process_frame
	print("Left, Up   -> diff_sel=%d song_sel=%d (expect back at %d)  play_enabled=%s" % [m._diff_sel, m._song_sel, song_before, str(not m._play_btn.disabled)])
	var lv_before: float = m._ratings[m._diff_sel].level
	await _key(KEY_M)
	print("M          -> mod panel open=%s" % str(m._mod_panel != null))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var storm_card: Control = _find_card(m._mod_panel, "暴風雨")
	storm_card.gui_input.emit(click)
	await get_tree().process_frame
	print("click STORM-> mods=%s Lv %.2f -> %.2f | mul: %s lv: %s" % [str(m.settings.mods), lv_before, m._ratings[m._diff_sel].level, m._mod_panel._mul_l.text, m._mod_panel._lv_l.text])
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(0.4).timeout   # 閉じる動きのぶん待つ
	print("Esc        -> mod panel open=%s (menu still %s)" % [str(m._mod_panel != null), str(_current == m)])
	await _key(KEY_O)
	print("O          -> options open=%s" % str(m._options != null))
	await _key(KEY_TAB)
	print("Tab in options -> page 1 visible=%s" % str(m._options._pages[1].visible))
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(0.4).timeout
	print("Esc        -> options open=%s (menu still %s)" % [str(m._options != null), str(_current == m)])
	await _key(KEY_ENTER)
	await get_tree().create_timer(0.7).timeout   # 発進の演出(0.4 秒)のあとで、ゲーム画面になる
	var g = _current
	print("Enter      -> screen=%s mods=%s Lv=%.2f (MODなし %.2f)" % [g.get_script().resource_path.get_file(), str(g._mods.ids), g.gen.level, g.gen.base_level])
	await _key(KEY_ESCAPE)
	print("Esc        -> paused=%s layer=%s" % [str(g._paused), str(g._pause_layer.visible)])
	var vol0 := int(g.settings.volume)
	await _key(KEY_DOWN)
	await _key(KEY_RIGHT)
	print("Down,Right -> sel=%d (expect 1)  volume %d -> %d (expect unchanged: ボタンの行では ← → は何もしない)" % [g._pause_sel, vol0, int(g.settings.volume)])
	for i in range(3):   # 1 → 0 → 5(効果音)→ 4(音楽)
		await _key(KEY_UP)
	var music0 := int(g.settings.get("music_volume", 100))
	await _key(KEY_LEFT)
	print("Up x3,Left -> sel=%d (expect 4)  music %d -> %d (expect -5)" % [g._pause_sel, music0, int(g.settings.get("music_volume", 100))])
	for i in range(2):   # 4 → 5 → 0(先頭へ戻る)
		await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	print("Down x2, Enter -> sel=%d (expect 0)  paused=%s (expect false: 再開)" % [g._pause_sel, str(g._paused)])
	await _key(KEY_ESCAPE)   # もう一度ポーズ
	print("Esc        -> paused=%s (expect true)" % str(g._paused))
	await _key(KEY_Q)
	for i in range(3):
		await get_tree().process_frame
	print("Q          -> screen=%s" % _current.get_script().resource_path.get_file())
	Settings.restore(orig)   # ユーザーの設定ファイルを元に戻す
	print("settings restored")
	get_tree().quit()


## 開発用: PLAY を押してからゲームが始まるまでの「間」を、時間を追って確認する(発進の演出 → カーソルが自機へ飛ぶ → 自機が現れる → GO)。
## 例: --smoke-start [keyboard]   画面写真は user:// ではなく、第 1 引数の接頭辞があればそこへ保存(--shots <接頭辞>)
func _smoke_start() -> void:
	var args := OS.get_cmdline_user_args()
	var orig := Settings.load_all()
	var st := Settings.load_all()
	st.control = "keyboard" if args.has("keyboard") else "mouse"
	Settings.save_all(st)
	var shots := ""
	var si := args.find("--shots")
	if si >= 0 and args.size() > si + 1:
		shots = str(args[si + 1])
	add_child(UiSfx.new())
	var cur := CursorOverlay.new()
	add_child(cur)
	cur._inside = true
	cur._focused = true
	show_menu()
	for i in range(4):
		await get_tree().process_frame
	var m = _current
	while m._job_pending:
		await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout
	# カーソルは PLAY ボタンの上
	var from: Vector2 = m._play_btn.get_global_rect().get_center()
	cur.debug_pos = from
	await get_tree().create_timer(0.2).timeout
	print("start: control=%s  cursor at PLAY %s  mouse_mode=%d" % [st.control, str(from), Input.mouse_mode])
	var t0 := Time.get_ticks_msec()
	m._play_btn.pressed.emit()
	var marks := [0.1, 0.25, 0.45, 0.6, 0.8, 1.0, 1.2, 1.5, 2.0, 2.6]
	var k := 0
	var g = null
	while k < marks.size():
		while (Time.get_ticks_msec() - t0) / 1000.0 < marks[k]:
			await get_tree().process_frame
		if g == null and _current != m and _current.get_script() == GameScreen:
			g = _current
		var line := "t=%.2f screen=%s" % [(Time.get_ticks_msec() - t0) / 1000.0, _current.get_script().resource_path.get_file().get_basename()]
		line += "  cursor_pos=(%.0f,%.0f) fly=%.2f" % [cur._pos.x, cur._pos.y, cur._fly_t]
		if g != null and is_instance_valid(g):
			line += "  guiding=%s arrived=%s ship_in=%.2f mouse_mode=%d now=%.2f label=%s" % [str(g._guiding), str(g._arrived), g._view_under.ship_in, Input.mouse_mode, g._now, g._center_label.text]
		print(line)
		if shots != "":
			get_viewport().get_texture().get_image().save_png("%s_%d.png" % [shots, k])
		k += 1
	if g != null and is_instance_valid(g):
		var ship_at: Vector2 = GameScreen.ARENA_POS + g.sim.player_pos
		print("ship start (screen) = %s   cursor flew to = %s" % [str(ship_at), str(cur._fly_to)])
	Settings.restore(orig)
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


## 開発用: 効果音のファイルが(書き出した exe の中でも)読めて、鳴らせることを確かめる。-- --smoke-sfx
func _smoke_sfx() -> void:
	var st := {"fails": 0}
	var chk := func(cond: bool, msg: String):
		print(("  ok   " if cond else "  FAIL ") + msg)
		if not cond:
			st.fails += 1
	var game_names := ["pop", "whistle", "clap", "boom", "tick", "hit", "explosion"]
	var counts := []
	for nm in game_names:
		counts.append("%s=%d" % [nm, SfxBank.variants(nm).size()])
	chk.call(SfxBank.variants("pop").size() >= 4 and SfxBank.variants("explosion").size() == 1, "ゲームの効果音が読める: %s" % ", ".join(counts))
	var ui := UiSfx.new()
	add_child(ui)
	chk.call(ui._streams.size() == UiSfx.SPECS.size(), "UI の効果音が全部読める(%d / %d)" % [ui._streams.size(), UiSfx.SPECS.size()])
	var Sfx = load("res://scripts/game/sfx.gd")
	var s = Sfx.new()
	add_child(s)
	for nm in game_names:
		s.play(nm)
	await get_tree().create_timer(0.3).timeout
	var playing := 0
	for p in s._players:
		if p.playing:
			playing += 1
	chk.call(playing >= 3, "鳴らすと、プレイヤーが再生を始める(%d 個)" % playing)
	# 発射音は、発生源の横の位置で左右に振る(左端 = 左寄りのバス、真ん中 = マスター)
	var bl: StringName = Sfx.pan_bus(-1.0)
	var bi := AudioServer.get_bus_index(bl)
	var pan_ok: bool = bi >= 0 and AudioServer.get_bus_effect_count(bi) > 0 and (AudioServer.get_bus_effect(bi, 0) as AudioEffectPanner).pan < 0.0
	chk.call(pan_ok and Sfx.pan_bus(0.0) == &"Master" and Sfx.pan_bus(1.0) != bl, "発射音は左右に振れる(左端: %s / 真ん中: %s)" % [bl, Sfx.pan_bus(0.0)])
	# 弾に触れている間のダメージ音(ループ): 触れている間は鳴り続け、離れると消える
	var loop_ok: bool = s._dmg_player != null and s._dmg_player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD
	chk.call(loop_ok, "ダメージ音はループ再生の設定になっている")
	var t_end := Time.get_ticks_msec() + 700
	var was_playing := true
	while Time.get_ticks_msec() < t_end:
		s.touch_damage(0.5)
		await get_tree().process_frame
		if Time.get_ticks_msec() > t_end - 400 and not s._dmg_player.playing:
			was_playing = false
	chk.call(was_playing and s._dmg_level > 0.9, "触れている間は鳴り続ける(音の大きさ %.2f)" % s._dmg_level)
	await get_tree().create_timer(0.5).timeout
	chk.call(not s._dmg_player.playing, "離れると消える")
	print("smoke-sfx: ", "OK" if st.fails == 0 else "%d FAILED" % st.fails)
	get_tree().quit()


## 開発用: 起動時の自動更新の判断を確かめる(新しいバージョンが見つかったときに、パネルが開いて更新を始めるか。ダウンロード先は存在しないアドレス)。-- --smoke-autoupdate
func _smoke_autoupdate() -> void:
	var original := Settings.load_all()
	var st := {"fails": 0}
	var chk := func(cond: bool, msg: String):
		print(("  ok   " if cond else "  FAIL ") + msg)
		if not cond:
			st.fails += 1
	updater = Updater.new()
	add_child(updater)
	updater.allow_any_url = true
	updater.force_apply = true   # 開発中の実行でも、入れ替えられるものとして扱う
	var info := {"ok": true, "newer": true, "version": "9.9.9", "notes": "test", "page": Updater.PAGE_URL, "asset_url": "http://127.0.0.1:9/none.zip", "asset_size": 0, "digest": ""}
	updater.info = info
	var set_st := func(auto: bool, last: String):
		var d := Settings.load_all()
		d.check_update = true
		d.auto_update = auto
		d.last_auto_update = last
		Settings.save_all(d)
	var fresh_title := func():
		show_title()
		await get_tree().create_timer(1.2).timeout
	# 1) 切ってあれば、始めない
	set_st.call(false, "")
	await fresh_title.call()
	chk.call(not _maybe_auto_update(info) and _current._overlay == null, "設定で切ってあると、自動では始めない")
	# 2) 入れていて、まだ試していない版なら、パネルが開いてすぐダウンロードを始める
	set_st.call(true, "")
	await fresh_title.call()
	var t = _current
	t._update_btn = null
	chk.call(_maybe_auto_update(info), "入れていれば、自動で始める")
	await get_tree().create_timer(0.5).timeout
	chk.call(t._overlay != null and t._overlay.get_script() == UpdatePanel and t._overlay._busy, "更新のパネルが開き、ダウンロード中になっている")
	chk.call(str(Settings.load_all().last_auto_update) == "9.9.9", "始めた版の印が残る: %s" % str(Settings.load_all().last_auto_update))
	# 3) 使う人がキャンセルすると、閉じて、印が戻る(次の起動で、また自動で始められる)
	t._overlay._on_later()
	await get_tree().create_timer(0.6).timeout
	chk.call(t._overlay == null and str(Settings.load_all().last_auto_update) == "", "キャンセルすると、パネルが閉じて、印が戻る")
	# 4) 前回この版で自動更新を始めたのに、まだ古いままなら、繰り返さない
	set_st.call(true, "9.9.9")
	await fresh_title.call()
	chk.call(not _maybe_auto_update(info) and _current._overlay == null, "同じ版で自動更新を繰り返さない(案内のボタンだけ)")
	# 5) 別の操作を始めていたら(遊び方を開いているなど)、割り込まない
	set_st.call(true, "")
	await fresh_title.call()
	_current._open(HowToPanel.new())
	await get_tree().create_timer(0.4).timeout
	chk.call(not _maybe_auto_update(info), "パネルを開いている間は、割り込まない")
	# 6) 入れ替えられない環境(書き出した版でない)では、始めない
	updater.force_apply = false
	set_st.call(true, "")
	await fresh_title.call()
	chk.call(OS.has_feature("template") or not _maybe_auto_update(info), "入れ替えられない環境(開発中の実行)では、始めない")
	Settings.restore(original)
	print("smoke-autoupdate: ", "OK" if st.fails == 0 else "%d FAILED" % st.fails)
	get_tree().quit()


## 開発用: MOD パネルの 6 枚がスクロールなしで収まり、パネルの上でホイールを回しても、後ろの難易度・曲の一覧は動かないことを確かめる。-- --smoke-modscroll
func _smoke_modscroll() -> void:
	var orig := Settings.load_all()
	var st := {"fails": 0}
	var chk := func(cond: bool, msg: String):
		print(("  ok   " if cond else "  FAIL ") + msg)
		if not cond:
			st.fails += 1
	overlay = HudOverlay.new()
	add_child(overlay)
	show_menu()
	await get_tree().create_timer(0.5).timeout
	var m = _current
	while m._job_pending:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	# 曲を続けて切り替えても、難易度の一覧が暗いまま残らない(読み込み中の暗転と、完了後の復帰が重ならない)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for n in range(14):
		m._select_song(rng.randi_range(0, m._songs.size() - 1))
		await get_tree().create_timer(rng.randf_range(0.0, 0.45)).timeout
	while m._job_pending:
		await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	chk.call(m._diff_scroll.modulate.a > 0.999, "曲を続けて切り替えたあとも、難易度の一覧は暗くならない(透明度 %.3f)" % m._diff_scroll.modulate.a)
	# 一度読んだ曲は、弾幕を作り直さないので速い
	var idx_a := 5
	var idx_b := 6
	m._select_song(idx_a)
	while m._job_pending:
		await get_tree().process_frame
	m._select_song(idx_b)
	while m._job_pending:
		await get_tree().process_frame
	var t_hit := Time.get_ticks_msec()
	m._select_song(idx_a)
	while m._job_pending:
		await get_tree().process_frame
	var ms_hit := Time.get_ticks_msec() - t_hit
	chk.call(m._loader != null and m._diff_cards.size() >= 1 and ms_hit < 400, "一度読んだ曲は、弾幕を作り直さず速く読める(%d ms)" % ms_hit)
	await get_tree().create_timer(1.0).timeout
	var diff_before: int = m._diff_scroll.scroll_vertical
	var song_before: int = m._song_scroll.scroll_vertical
	m.open_mods()
	await get_tree().create_timer(0.8).timeout
	var sc: ScrollContainer = m._mod_panel.find_children("*", "ScrollContainer", true, false)[0]
	chk.call(sc.get_v_scroll_bar().max_value - sc.get_v_scroll_bar().page <= 0.5, "MOD の 6 枚は、スクロールなしで収まる(高さ %d / 表示 %d)" % [int(sc.get_v_scroll_bar().max_value), int(sc.get_v_scroll_bar().page)])
	# 難易度の一覧の真上でもある位置(パネルの中)にマウスを置いて、ホイールを回す
	var at: Vector2 = sc.get_global_rect().get_center()
	get_viewport().warp_mouse(at)
	await get_tree().process_frame
	await get_tree().process_frame
	for i in range(4):
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = true
		e.position = at
		e.global_position = at
		Input.parse_input_event(e)
		await get_tree().process_frame
		await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	chk.call(m._diff_scroll.scroll_vertical == diff_before and m._song_scroll.scroll_vertical == song_before, "後ろの難易度・曲の一覧は動かない(%d → %d)" % [diff_before, m._diff_scroll.scroll_vertical])
	# マウスだけで: パネルの中のクリックでは閉じず、外のクリックと「✕」で閉じる。「すべて解除」で MOD が外れる
	var click_at := func(p: Vector2) -> InputEventMouseButton:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.position = p
		ev.global_position = p
		return ev
	m._mod_panel.gui_input.emit(click_at.call(Vector2(640, 300)))
	await get_tree().create_timer(0.4).timeout
	chk.call(m._mod_panel != null, "MOD: パネルの中のクリックでは閉じない")
	var storm: Control = _find_card(m._mod_panel, "暴風雨")
	storm.gui_input.emit(click_at.call(Vector2(10, 10)))
	await get_tree().process_frame
	chk.call(m.settings.mods == ["storm"], "MOD: カードのクリックで付く(%s)" % str(m.settings.mods))
	var clear_btn: Button
	var x_btn: Button
	for b in m._mod_panel.find_children("*", "Button", true, false):
		if (b as Button).text == "すべて解除":
			clear_btn = b
		elif (b as Button).text == "✕":
			x_btn = b
	chk.call(clear_btn != null and not clear_btn.disabled and x_btn != null, "MOD: 「すべて解除」(付けると押せる)と右上の「✕」がある")
	clear_btn.pressed.emit()
	await get_tree().process_frame
	chk.call((m.settings.mods as Array).is_empty() and clear_btn.disabled, "MOD: 「すべて解除」で外れ、ボタンは押せなくなる")
	x_btn.pressed.emit()
	await get_tree().create_timer(0.5).timeout
	chk.call(m._mod_panel == null, "MOD: 「✕」で閉じる")
	m.open_mods()
	await get_tree().create_timer(0.6).timeout
	m._mod_panel.gui_input.emit(click_at.call(Vector2(20, 400)))
	await get_tree().create_timer(0.5).timeout
	chk.call(m._mod_panel == null, "MOD: パネルの外をクリックすると閉じる")
	open_settings(0)
	await get_tree().create_timer(0.6).timeout
	_settings_panel.gui_input.emit(click_at.call(Vector2(20, 400)))
	await get_tree().create_timer(0.5).timeout
	chk.call(_settings_panel == null, "設定: パネルの外をクリックすると閉じる")
	open_settings(0)
	await get_tree().create_timer(0.6).timeout
	for b in _settings_panel.find_children("*", "Button", true, false):
		if (b as Button).text == "✕":
			b.pressed.emit()
	await get_tree().create_timer(0.5).timeout
	chk.call(_settings_panel == null, "設定: 「✕」で閉じる")
	Settings.restore(orig)
	print("smoke-modscroll: ", "OK" if st.fails == 0 else "%d FAILED" % st.fails)
	get_tree().quit()


## 開発用: 選曲画面で PLAY を押してから自機が出るまでの、フレームの間隔(止まりの長さ)を測る。-- --prof-play [曲名の一部]
func _prof_play() -> void:
	var orig := Settings.load_all()
	var args := OS.get_cmdline_user_args()
	var want := ""
	for a in args:
		if not str(a).begins_with("--") and str(a) != "nocache":
			want = str(a)
	var st := Settings.load_all()
	for p in SongLibrary.find_all():
		if want != "" and str(p).contains(want):
			st.last_song = str(p)
	st.last_diff = ""
	st.mods = []
	st.control = "mouse"
	Settings.save_all(st)
	overlay = HudOverlay.new()
	add_child(overlay)
	add_child(CursorOverlay.new())
	_setup_ui_layer()
	SfxBank.preload_all(["pop", "whistle", "clap", "boom", "tick", "hit", "explosion"])
	FpsOverlay.enabled = true
	var fps_node := FpsOverlay.new()
	add_child(fps_node)
	_setup_fade()
	show_menu()
	await get_tree().create_timer(0.5).timeout
	var m = _current
	while m._job_pending:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	m._diff_sel = m._diff_cards.size() - 1   # 一番難しい譜面
	if args.has("nocache"):   # 比較用: 選曲で作った弾幕を渡さない(プレイ画面が作り直す)
		m._gens[m._diff_sel] = {}
	m._start()
	var t0 := Time.get_ticks_usec()
	var last := t0
	var worst := 0.0
	var log := []
	while Time.get_ticks_usec() - t0 < 3000000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000.0
		last = now
		worst = maxf(worst, dt)
		if dt > 22.0:
			log.append("%.0fms@%.2fs" % [dt, (now - t0) / 1e6])
	var g = _current
	print("prof-play: FPS 表示 = ", fps_node._label.text.replace("
", " / "))
	print("prof-play: screen=%s worst frame %.1f ms | long frames (>22ms): %s" % [g.get_script().resource_path.get_file(), worst, ", ".join(log)])
	Settings.restore(orig)
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
	# マウス操作: スキップできる間は、マウスを捕まえず、ボタンで飛ばせる。飛ばしたら、自機の位置で捕まえる
	var fails := 0
	start_game(loader, bm, {"mods": ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "mouse", "sfx_volume": 0})
	var gm = _current
	await get_tree().create_timer(1.6).timeout
	var ok1: bool = gm._skip_btn.visible and Input.mouse_mode == Input.MOUSE_MODE_HIDDEN
	var now0: float = gm._now
	gm._skip_btn.pressed.emit()
	await get_tree().create_timer(0.3).timeout
	var ok2: bool = not gm._skip_btn.visible and gm._now > now0 + 5.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	print("[mouse] skip button visible & cursor free: %s | after click: jumped %.1f -> %.1f, button hidden, captured: %s" % ["OK" if ok1 else "FAIL", now0, gm._now, "OK" if ok2 else "FAIL"])
	fails += (0 if ok1 else 1) + (0 if ok2 else 1)
	print("smoke-skip: ", "OK" if fails == 0 else "%d FAILED" % fails)
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


## 開発用: 弾速の実験(scripts/speed_study.gd)を、実際のプレイ画面で通す。2 回遊ぶ(最後の発射の直前まで進めて終える)と、記録が 2 行でき、
## 条件がそれぞれ違い(回数の少ない条件から選ぶ)、遊んだ時間が入っている。マルチプレイ・MOD つきでは記録しない。-- --smoke-speed-study
## 記録は確認用の別ファイルに書く(本物の記録 user://speed_study.csv は触らない)。
func _smoke_speed_study() -> void:
	var SpeedStudy = load("res://scripts/speed_study.gd")
	var real_path: String = SpeedStudy.path
	SpeedStudy.path = "user://smoke_speed_study.csv"
	if FileAccess.file_exists(SpeedStudy.path):
		DirAccess.remove_absolute(SpeedStudy.path)
	var fails := 0
	var chk := func(c: bool, m: String) -> void:
		print(("  ok   " if c else "  FAIL ") + m)
		if not c:
			fails += 1
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[0]
	var conds: Array = []
	for run in range(3):
		var st := {"mods": ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0, "speed_study": true}
		if run == 2:
			st.mods = ["storm"]   # 弾幕に効く MOD: 記録しない
		start_game(loader, bm, st)
		var g = _current
		conds.append(g._study_cond)
		await get_tree().create_timer(2.5).timeout
		var last: float = g.sim.events[g.sim.events.size() - 1].t
		g._audio.seek((last - 0.5) * g._rate)
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 15000 and is_instance_valid(g) and _current == g:
			await get_tree().process_frame
		chk.call(_current != g, "%d 回目: 結果画面まで進んだ(条件: %s)" % [run + 1, conds[run] if conds[run] != "" else "なし"])
	var rows: Array = SpeedStudy.read_rows()
	chk.call(rows.size() == 2, "記録は、実験した 2 回ぶん(MOD つきの 3 回目は記録しない): %d 行" % rows.size())
	chk.call(conds[0] != "" and conds[1] != "" and conds[0] != conds[1] and conds[2] == "", "条件は 1 回目と 2 回目で違い、MOD つきは実験しない: %s" % str(conds))
	if rows.size() >= 1:
		var r: Dictionary = rows[0]
		chk.call(str(r.cond) == conds[0] and float(r.played_s) > 10.0 and str(r.map).contains(bm.version), "記録の中身: 条件 %s・遊んだ時間 %.0f 秒・譜面 %s" % [r.cond, r.played_s, r.map])
	DirAccess.remove_absolute(SpeedStudy.path)
	SpeedStudy.path = real_path
	print("smoke-speed-study: ", "OK" if fails == 0 else "%d FAILED" % fails)
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
	print("options open=%s (selected=%d)" % [str(_settings_panel != null), t._sel])
	# 設定を開いている間は、下のタイトルがキーに反応しない(Esc で終了確認が開いたり、項目が動いたりしない)
	await _key(KEY_DOWN)
	print("title ignores keys while settings open: sel=%d (expect 3) quit_panel=%s (expect false)" % [t._sel, str(t._overlay != null)])
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(0.6).timeout
	print("options closed=%s  title_overlay=%s (expect true, false)" % [str(_settings_panel == null), str(t._overlay != null)])
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
	chk.call(a.start_game().contains("準備"), "参加者が準備完了を押すまで開始できない: '%s'" % a.start_game())
	b.set_my_ready(true)
	await get_tree().create_timer(0.3).timeout
	chk.call(a.players[b.my_id].ready and b.players[b.my_id].ready, "準備完了が、ホストと本人の名簿に載る")
	a.set_mode("coop")   # 部屋の設定が変わると、準備完了は全員外れる(確かめ直し)
	await get_tree().create_timer(0.3).timeout
	chk.call(not a.players[b.my_id].ready and not b.players[b.my_id].ready, "部屋の設定を変えると、準備完了が外れる")
	b.report_song(false)   # 曲を持たない人は、準備完了にできない
	await get_tree().create_timer(0.2).timeout
	b.set_my_ready(true)
	await get_tree().create_timer(0.2).timeout
	chk.call(not a.players[b.my_id].ready, "曲を持っていない人は、準備完了にならない")
	b.report_song(true)
	await get_tree().create_timer(0.2).timeout
	b.set_my_ready(true)
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
	b.set_my_ready(true)
	await get_tree().create_timer(0.3).timeout
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
	if not fail_test:   # 動かない a が被弾するまで待つ(譜面によって、発生源の近く(猶予の範囲)で、最初の弾が当たらないことがある)
		var t1 := Time.get_ticks_msec()
		while gs.a.sim.damage_total < 0.15 and not (gs.a.sim.finished or gs.b.sim.finished) and Time.get_ticks_msec() - t1 < 25000:
			await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout   # 被弾の最中でなく、共有の状態が届いてから見る
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
	if not nosong:
		for k in range(_shot_nets.size()):
			if not (three and k == _shot_nets.size() - 1):   # 3 人のときは、最後の 1 人だけ準備中のまま
				_shot_nets[k].set_my_ready(true)
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
	# 他の参加者がいるホストが退室しようとすると、先に確認が出る(部屋が閉じてしまうため)。キャンセルすれば残る
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(0.3).timeout
	chk.call(m._confirm != null and n.is_active() and m._page == "lobby", "参加者がいるホストが Esc を押すと、確認が出て、まだ部屋にいる")
	await _key(KEY_ESCAPE)   # 確認のキャンセル
	await get_tree().create_timer(0.3).timeout
	chk.call(m._confirm == null and n.is_active() and m._page == "lobby", "キャンセルすると、部屋に残る")
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
	await get_tree().create_timer(0.2).timeout
	while menu._job_pending:   # 曲の読み込み(別スレッド)を待つ
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
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
	chk.call(m._start_blocker().contains("準備"), "全員が曲を持っても、参加者が準備完了を押すまで開始できない('%s')" % m._start_blocker())
	b.set_my_ready(true)
	await get_tree().create_timer(0.4).timeout
	chk.call(m._start_blocker() == "", "参加者が準備完了を押せば、開始できる('%s')" % m._start_blocker())
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


## 開発用: 音量バーのドラッグ / 選曲の別スレッド読み込み / なめらかスクロール / 独自カーソル / どの画面でも設定 / フォルダの見張りを確認する。-- --smoke-new
func _smoke_new() -> void:
	var original := Settings.load_all()
	var st := {"fails": 0}
	var chk := func(cond: bool, msg: String):
		print(("  ok   " if cond else "  FAIL ") + msg)
		if not cond:
			st.fails += 1
	overlay = HudOverlay.new()
	add_child(overlay)
	var cur := CursorOverlay.new()
	add_child(cur)
	_setup_ui_layer()
	_watch_sync()
	await get_tree().process_frame
	await get_tree().process_frame
	chk.call(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN, "OS のカーソルは隠れている(独自カーソルを描く)")
	# 音量バーをマウスで動かす
	Volume.set_master(50)
	Volume.set_music(50)
	show_title()
	await get_tree().create_timer(0.5).timeout
	overlay._sel = 0
	overlay._show_panel()
	await get_tree().process_frame
	await get_tree().process_frame
	var row: Control = overlay._rows[1]
	var bx: float = overlay._bar_x()
	var bw: float = overlay._bar_w(row)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(bx + bw * 0.8, 15)
	row.gui_input.emit(press)
	chk.call(overlay._sel == 1 and Volume.music == 80, "バーをクリックすると、その位置の音量になる: 音楽 %d" % Volume.music)
	var move := InputEventMouseMotion.new()
	move.position = Vector2(bx + bw * 0.25, 15)
	row.gui_input.emit(move)
	chk.call(Volume.music == 25 and Volume.master == 50, "押したまま動かすと追従する: 音楽 %d(全体 %d は変わらない)" % [Volume.music, Volume.master])
	move.position = Vector2(bx + bw * 1.5, 15)
	row.gui_input.emit(move)
	chk.call(Volume.music == 100, "バーの外まで動かしても 100 で止まる")
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	row.gui_input.emit(rel)
	move.position = Vector2(bx + bw * 0.1, 15)
	row.gui_input.emit(move)
	chk.call(Volume.music == 100, "離したあとは追従しない")
	# 選曲画面: 曲を選ぶと別スレッドで読み込み、その間も画面は止まらない
	show_menu()
	await get_tree().create_timer(0.3).timeout
	var m = _current
	while m._job_pending:
		await get_tree().process_frame
	chk.call(m._loader != null and m._diff_cards.size() >= 1, "選曲画面が開き、最初の曲の難易度カードが出る(%d 枚)" % m._diff_cards.size())
	var frames := {"n": 0, "max": 0.0}
	m._select_song(3 if m._song_sel != 3 else 4)
	var t0 := Time.get_ticks_usec()
	var last := t0
	while m._job_pending:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.max = maxf(frames.max, (now - last) / 1000.0)
		last = now
		frames.n += 1
	for k in range(45):   # 読み込みが終わってからの、カード・背景・音の切り替えのあいだも測る
		await get_tree().process_frame
		var now2 := Time.get_ticks_usec()
		frames.max = maxf(frames.max, (now2 - last) / 1000.0)
		last = now2
		frames.n += 1
	chk.call(frames.n >= 1 and frames.max < 40.0, "曲の読み込み中・切り替えの間も描画が続く(%d フレーム、最長 %.0f ms)" % [frames.n, frames.max])
	var first_loader = m._loader
	m._select_song(1)
	m._select_song(2)   # 続けて選び直したら、前の読み込みは捨てられる
	m._start()
	chk.call(m._job_pending and _current == m, "読み込み中に決定しても始まらない")
	while m._job_pending:
		await get_tree().process_frame
	chk.call(m._song_sel == 2 and m._loader != first_loader and m._title_l.text == m._songs[2].title, "最後に選んだ曲だけが反映される: %s" % m._title_l.text)
	# なめらかなスクロール(音量メーターが出ている間は、ホイールは音量になる。消えてから)
	overlay._hide_panel()
	var sc: ScrollContainer = m._song_scroll
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.factor = 1.0
	wheel.position = sc.global_position + Vector2(100, 100)
	wheel.global_position = wheel.position
	Input.warp_mouse(wheel.position)
	await get_tree().process_frame
	Input.parse_input_event(wheel)
	await get_tree().process_frame
	var s0 := sc.scroll_vertical
	await get_tree().process_frame
	var s1 := sc.scroll_vertical
	await get_tree().create_timer(0.6).timeout
	var s2 := sc.scroll_vertical
	chk.call(s0 <= s1 and s1 < s2 and s2 > 40, "ホイールで、目標へ少しずつ近づく(%d → %d → %d)" % [s0, s1, s2])
	var play_loader = m._loader
	# どの画面でも設定を開ける(選曲画面のキー O)
	var key := InputEventKey.new()
	key.keycode = KEY_O
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().process_frame
	await get_tree().process_frame
	chk.call(_settings_panel != null and m._options == _settings_panel, "選曲画面で O キー: 設定パネルが開く")
	var key2 := InputEventKey.new()
	key2.keycode = KEY_DOWN
	key2.pressed = true
	var sel_before: int = m._song_sel
	Input.parse_input_event(key2)
	await get_tree().process_frame
	chk.call(m._song_sel == sel_before, "設定を開いている間、下の画面はキーに反応しない")
	close_settings()
	await get_tree().process_frame
	chk.call(_settings_panel == null and m._options == null, "閉じられる")
	show_multi()
	await get_tree().create_timer(0.4).timeout
	chk.call(_settings_btn.visible, "マルチプレイ画面には、右上に「設定」ボタンが出る")
	_settings_btn.pressed.emit()
	await get_tree().process_frame
	chk.call(_settings_panel != null, "ボタンで設定が開く")
	close_settings()
	show_title()
	await get_tree().create_timer(0.4).timeout
	chk.call(not _settings_btn.visible, "タイトル画面には出ない(自分の入口がある)")
	start_game(play_loader, play_loader.difficulties[0], {"mods": ["practice"], "offset_ms": 0, "control": "mouse", "sfx_volume": 0})
	await get_tree().create_timer(1.0).timeout   # カーソルが自機へ飛ぶ演出(0.6 秒)のあとで、マウスが捕まえられる
	open_settings(0)
	chk.call(not _settings_btn.visible and _settings_panel == null, "プレイ中は、設定を開けない")
	var cap0 := Input.mouse_mode
	start_game(play_loader, play_loader.difficulties[0], {"mods": ["practice"], "offset_ms": 0, "control": "mouse", "sfx_volume": 0})   # リトライ: 新しいプレイ画面が先にできて、古いほうがあとで消える
	await get_tree().create_timer(0.5).timeout
	chk.call(cap0 == Input.MOUSE_MODE_CAPTURED and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "リトライしても、マウスは捕まえたまま(独自カーソルは出ない) cap0=%d now=%d" % [cap0, Input.mouse_mode])
	_current.queue_free()
	_current = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().process_frame
	await get_tree().process_frame
	chk.call(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN, "プレイから離れたとき、OS のカーソルは隠れたまま(独自カーソルに戻る)")
	# フォルダの見張り: songs に .osz を置くと知らせる(コピーの途中でないことを、大きさで確かめてから)
	show_menu()
	await get_tree().create_timer(0.5).timeout
	m = _current
	var src := "C:/Desktop/my_apps/DDA/22699 Len - U.N. Owen was her.osz"
	var dst := SongLibrary.ensure_user_dir().path_join("watch_test.osz")
	if FileAccess.file_exists(dst):
		DirAccess.remove_absolute(dst)
	_watch_sync()
	var songs_before: int = m._songs.size()
	DirAccess.copy_absolute(src, dst)
	_watch_poll()   # 1 回目: 見つけた(まだ知らせない)
	chk.call(not overlay._toast.visible, "見つけた直後は知らせない(コピーの途中かもしれない)")
	_watch_poll()   # 2 回目: 大きさが落ち着いたので知らせる
	chk.call(overlay._toast.visible and overlay._toast_l.text.begins_with("曲が追加されました"), "少しあとに「%s」と知らせる" % overlay._toast_l.text)
	chk.call(m._songs.size() == songs_before + 1 or m._songs.size() == songs_before, "選曲画面の一覧が更新される(%d → %d 曲)" % [songs_before, m._songs.size()])
	overlay._toast.visible = false
	_watch_poll()
	chk.call(not overlay._toast.visible, "同じ曲は、もう知らせない")
	DirAccess.remove_absolute(dst)
	_watch_poll()
	chk.call(not _watch_known.has("watch_test.osz|%d" % SongLibrary.file_size(src)), "消したら忘れる")
	Settings.restore(original)
	SongLibrary.save_index()
	print("smoke-new: ", "OK" if st.fails == 0 else "%d FAILED" % st.fails)
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
	# ウィンドウへのドロップ(選曲画面で、複数のファイルを一度に): すべて songs へ取り込まれ、画面は作り直されず、最後の曲が選ばれる
	var drop_dir := ProjectSettings.globalize_path("user://drop_test")
	DirAccess.make_dir_recursive_absolute(drop_dir)
	var drop_names := ["13887 ZUN - U.N. Owen Was Her.osz", "68893 Yiruma & Skullee - River Flows In You (A Love Note).osz"]
	var drop_dsts: Array = []
	var drop_pre: Array = []
	for nm in drop_names:
		DirAccess.copy_absolute("C:/Desktop/my_apps/DDA/" + nm, drop_dir.path_join(nm))
		var dst := SongLibrary.ensure_user_dir().path_join(nm)
		drop_dsts.append(dst)
		drop_pre.append(FileAccess.file_exists(dst))
	m = _current
	get_window().files_dropped.emit(PackedStringArray([drop_dir.path_join(drop_names[0]), "C:/x/readme.txt", drop_dir.path_join(drop_names[1])]))
	await get_tree().create_timer(1.5).timeout
	chk.call(_current == m, "ドロップしても、選曲画面は作り直されない")
	chk.call(m._song_sel >= 0 and m._songs[m._song_sel].path.contains("Yiruma"), "最後の .osz が選ばれる: %s" % (m._songs[m._song_sel].path.get_file() if m._song_sel >= 0 else "-"))
	chk.call(FileAccess.file_exists(drop_dsts[0]) and FileAccess.file_exists(drop_dsts[1]), "どちらも songs にコピーされる(次の起動でも残る)")
	get_window().files_dropped.emit(PackedStringArray(["C:/x/readme.txt"]))   # .osz 以外だけ: 通知だけで、何も起きない
	await get_tree().create_timer(0.3).timeout
	chk.call(_current == m, ".osz 以外のドロップでは、何も起きない")
	for i in range(drop_dsts.size()):   # 後始末(もとからあったものは消さない)
		if not drop_pre[i]:
			DirAccess.remove_absolute(drop_dsts[i])
		DirAccess.remove_absolute(drop_dir.path_join(drop_names[i]))
	SongLibrary.save_index()
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
