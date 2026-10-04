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
const UserDirMigrate = preload("res://scripts/user_dir_migrate.gd")
const FileAssoc = preload("res://scripts/file_assoc.gd")
const Mods = preload("res://scripts/mods.gd")
const Boss = preload("res://scripts/game/boss.gd")
const SfxBank = preload("res://scripts/sfx_bank.gd")
const HpGraph = preload("res://scripts/ui/hp_graph.gd")
const FpsOverlay = preload("res://scripts/ui/fps_overlay.gd")
const HitchLog = preload("res://scripts/hitch_log.gd")
const SongArt = preload("res://scripts/song_art.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiSets = preload("res://scripts/ui/ui_sets.gd")
const Records = preload("res://scripts/records.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")
const Replay = preload("res://scripts/replay.gd")
const UiFx = preload("res://scripts/ui/ui_fx.gd")
const Volume = preload("res://scripts/volume.gd")
const NowPlaying = preload("res://scripts/ui/lazer/now_playing.gd")
const HudOverlay = preload("res://scripts/ui/hud_overlay.gd")
const Updater = preload("res://scripts/updater.gd")
const UPDATE_RECHECK_SEC := 1800.0   # 起動したままの間、新しいバージョンを確かめ直す間隔(GitHub の API は、1 時間に 60 回まで)
const UPDATE_TOAST_TIME := 7.0       # 新しいバージョンの知らせを出しておく秒数
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
var _kind := ""                    # いまの画面の種類(画面の kind。"title" / "menu" / "multi" / "game" / "result")。クラスでは判定しない(UI セットで中身が変わる)
var _ui_layer: CanvasLayer         # 設定・選択のパネルを、画面の上に重ねる層
var _settings_panel: Control       # 開いている設定パネル(どの画面からでも開ける。プレイ中は除く)
var _settings_dict: Dictionary = {}
var _ui_before := ""               # 設定を開いたときの UI の見た目(閉じたとき、変わっていたら、いまの画面を作り直す)
var _settings_btn: Button          # 画面の右上の「設定」(タイトル・選曲画面は、自分で設定を開く入口を持つので出さない)
var _songs_changed := false      # 設定パネルで、osu! の Songs フォルダの設定が変わった(閉じたときに、選曲画面の一覧を作り直す)
var _watch_known := {}             # songs フォルダに、いま見えている .osz(名前|大きさ → パス)
var _watch_pending := {}           # 見つけたが、コピーの途中かもしれないもの(大きさが落ち着くまで待つ)
var _watch_ready := false
var _watch_t := 0.0
var net                    # 通信層(マルチプレイを開くときに作る。部屋を出ても使い回す)
var _last_play := {}
var overlay                # 音量メーター・通知(全画面の上)
var updater                # アプリ内アップデート(GitHub のリリースを確認する)
var _update_timer: Timer     # 起動している間の、更新の再確認(UPDATE_RECHECK_SEC ごと)
var _update_rechecking := false   # いまの確認が、再確認(起動時の確認ではない)か。再確認では、自動更新はしない(知らせるだけ)
var _update_notified := ""   # もう知らせた版(同じ版を、何度も知らせない)
var _update_pending: Dictionary = {}   # プレイ中に見つかって、まだ知らせていない新しい版(プレイを離れてから知らせる)
var _instance            # 1 つだけ動かして、あとから開いた .osz を受け取る
var _music: AudioStreamPlayer = null   # クリアで引き継いだ曲(リザルト中に流れ続ける)

## 画面切替の暗転フェード(通常起動のときだけ。開発用フックは即時に切り替える)
var _fade_enabled := false
var _wipe: Node                    # 画面の切り替えの幕(斜めのワイプ)
var _fading := false
var _f11_down := false              # F11 を押している間(押した瞬間だけ全画面を切り替えるため)
var _pending: Node = null


func _ready() -> void:
	UserDirMigrate.run()   # アプリの名前を変えたので、前の名前のユーザーデータ(設定・曲・記録)を移す(残っていなければ何もしない)
	if OS.has_feature("template"):   # 書き出した版: 前の名前(DDA.osz)で「プログラムから開く」に登録していたら、新しい名前へ移す
		FileAssoc.migrate_legacy(OS.get_executable_path())
	var first_settings := Settings.load_all()
	Volume.init_from(first_settings)
	SongLibrary.apply_osu_settings(first_settings)   # osu! の Songs フォルダを使う設定のとき、その場所(スクリーンショット・動作確認の起動でも同じ)
	var args := OS.get_cmdline_user_args()
	for a in args:   # 開発用の確認・スクリーンショットでは、使う人のプレイ記録を残さない
		var a_s := str(a)
		if a_s.begins_with("--smoke") or a_s.begins_with("--shot") or a_s.begins_with("--prof"):
			Records.enabled = false
	var hi := args.find("--hitch")   # 開発用: 長いフレームを記録する。例: -- --hitch 25 --smoke-ui
	if hi >= 0:
		var hl := HitchLog.new()
		if args.size() > hi + 1 and str(args[hi + 1]).is_valid_float():
			hl.threshold_ms = float(args[hi + 1])
		hl.screen_of = func() -> String: return str(_current.get("kind")) if is_instance_valid(_current) else ""
		add_child(hl)
	var ui_i := args.find("--ui")   # 例: -- --ui classic(設定の ui_style を、この起動だけ上書きする)
	if ui_i >= 0 and args.size() > ui_i + 1:
		UiSets.override_id = args[ui_i + 1]
	var ri := args.find("--replay-export")   # 動画の書き出しの子プロセス(親が --write-movie 付きで起動する)。-- --replay-export <ファイル> <軌道のモード> <軌道の秒> <区間の始点> <区間の終点>(区間がなければ -1)
	if ri >= 0 and args.size() > ri + 1:
		Records.enabled = false
		Replay.enabled = false
		_replay_export_child(str(args[ri + 1]), int(args[ri + 2]) if args.size() > ri + 2 else 1, float(args[ri + 3]) if args.size() > ri + 3 else 3.0,
			float(args[ri + 4]) if args.size() > ri + 4 else -1.0, float(args[ri + 5]) if args.size() > ri + 5 else -1.0)
		return
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
	if args.has("--smoke-uiswitch"):
		_smoke_uiswitch()
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
	if args.has("--smoke-updatenotice"):
		_smoke_updatenotice()
		return
	if args.has("--smoke-modscroll"):
		_smoke_modscroll()
		return
	if args.has("--prof-frames"):
		_prof_frames()
		return
	if args.has("--prof-play"):
		_prof_play()
		return
	if args.has("--smoke-osu-menu"):
		_smoke_osu_menu()
		return
	if args.has("--smoke-carousel"):
		_smoke_carousel()
		return
	if args.has("--prof-ui"):
		_prof_ui()
		return
	if args.has("--smoke-skip"):
		_smoke_skip()
		return
	if args.has("--smoke-replay"):
		_smoke_replay()
		return
	if args.has("--smoke-drag"):
		_smoke_drag()
		return
	if args.has("--smoke-retryhold"):
		_smoke_retryhold()
		return
	if args.has("--smoke-focus"):
		_smoke_focus()
		return
	if args.has("--smoke-break"):
		_smoke_break()
		return
	if args.has("--smoke-death"):
		_smoke_death()
		return
	if args.has("--smoke-bossloop"):
		_smoke_bossloop()
		return
	if args.has("--smoke-score"):
		_smoke_score()
		return
	if args.has("--smoke-tapestop"):
		_smoke_tapestop()
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
	SongLibrary.start_osu_warmup()   # osu! の Songs フォルダの曲の索引を、裏で作っておく
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
	_update_timer = Timer.new()   # 起動したままの間に公開された新しい版も、知らせる(自動では更新しない)
	_update_timer.wait_time = UPDATE_RECHECK_SEC
	_update_timer.timeout.connect(_recheck_update)
	add_child(_update_timer)
	_update_timer.start()
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


## 更新の確認が終わった。新しいバージョンがあれば、タイトル画面に案内を出す(起動時の確認のとき。条件が合えば自動更新も始める)。
## 起動したままの間の再確認(_recheck_update)で見つかったときは、知らせるだけ(_announce_update)。自動更新はしない。
func _on_update_checked(info: Dictionary) -> void:
	var recheck := _update_rechecking
	_update_rechecking = false
	if not bool(info.get("newer", false)):
		return
	if recheck:
		if str(info.get("version", "")) != _update_notified:
			_announce_update(info)
		return
	if _kind == "title":
		_update_notified = str(info.get("version", ""))   # タイトルの案内のボタンで知らせた
		_current.show_update(info)
		_maybe_auto_update(info)
	elif _kind != "game":
		_announce_update(info)   # タイトル以外から始まった(曲のファイルから開いた)
	else:
		_update_pending = info


## 起動したままの間の再確認。設定で切ってあれば確認しない。確認中・ダウンロード中・入れ替えの準備ができているときも、しない。
func _recheck_update() -> void:
	if updater == null or not bool(Settings.load_all().check_update) or updater.is_busy():
		return
	_update_rechecking = updater.check()


## 新しいバージョンが公開されたことを知らせる(画面の下に、少し長めに出す)。タイトル画面なら、案内のボタンも出す。
## プレイ中は、画面の邪魔をしないよう、プレイを離れてから知らせる(_update_pending)。更新はしない(押して、更新のパネルから始める)。
func _announce_update(info: Dictionary) -> void:
	_update_notified = str(info.get("version", ""))
	if _kind == "game":
		_update_pending = info
		return
	_update_pending = {}
	if _kind == "title":
		_current.show_update(info)
	overlay.toast("新しいバージョン v%s が公開されました(タイトル画面から更新できます)" % str(info.get("version", "?")), UPDATE_TOAST_TIME)


## プレイを離れた: プレイ中に見つかった新しい版があれば、画面が落ち着いてから知らせる。
func _flush_update_notice() -> void:
	if _update_pending.is_empty():
		return
	await get_tree().create_timer(1.5).timeout
	if not _update_pending.is_empty() and _kind != "game" and not _fading:
		_announce_update(_update_pending)


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
	if _kind != "title" or not t.can_accept_auto_update() or _settings_panel != null or _fading:
		return false
	st.last_auto_update = str(info.get("version", ""))
	Settings.save_all(st)
	var p = UiSets.current().make_update()
	p.setup(updater)
	p.auto_start = true
	p.cancelled.connect(func():
		var s2 := Settings.load_all()
		s2.last_auto_update = ""
		Settings.save_all(s2))
	t.open_panel(p)
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
	if _kind == "game" or _kind == "multi":
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
	if _kind == "menu":
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
	var k = n.get("kind")
	_kind = k if k is String else ""
	if n.has_signal("settings_requested") and not n.is_connected("settings_requested", open_settings):   # 画面が設定の入口を持つとき(タイトル・選曲・lazer 風の画面)
		n.connect("settings_requested", open_settings)
	add_child(n)
	_update_settings_button()
	if _kind != "game" and not _update_pending.is_empty():
		_flush_update_notice()


# --- 設定(プレイ中以外の、どの画面からでも開ける) ---

## 設定で UI の見た目を変えたあと、いまの画面を新しい見た目で作り直す(タイトル・選曲のみ。曲・難易度の選択は設定に残っているので、同じ状態で開く)。
func _rebuild_current() -> void:
	match _kind:
		"title":
			show_title()
		"menu":
			var pm = _current.get("pick_mode")
			show_menu(pm == true)

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
	# 設定の入口を、画面が自分で持っているとき(own_settings_button)は、ここでは出さない(lazer 風の画面は、ツールバーの歯車を持つ)
	var own_v = _current.get("own_settings_button") if _current != null else null
	var own: bool = own_v == true
	_settings_btn.visible = _current != null and not own and _kind != "game" and _kind != "title" and _kind != "menu" and _settings_panel == null


## 設定パネルを開く(section: 0=操作 1=音 2=画面 3=曲 4=その他)。いまの画面が設定の辞書(settings)を持っていれば、それを直接変える。
func _exit_tree() -> void:
	SongLibrary.stop_warmup()   # 裏で索引を作っているスレッドを、閉じる前に止める
	Replay.flush()   # リプレイを書いている途中なら、書き終わるのを待つ


func open_settings(section := 0) -> void:
	if _settings_panel != null or _current == null or _kind == "game":
		return
	_setup_ui_layer()
	var st = _current.get("settings")
	_settings_dict = st if st is Dictionary else Settings.load_all()
	_ui_before = str(UiSets.current().id())
	var p = UiSets.current().make_options()
	p.setup(_settings_dict)
	p.changed.connect(func(kind: String):
		if kind == "songs":
			_songs_changed = true   # 一覧の作り直しは、パネルを閉じたとき(曲が多いと重いので、設定中は止めない)
			Settings.save_all(_settings_dict)   # 選んだ時点で保存する(パネルを閉じずにゲームを終えても、次の起動で使えるように)
		if _current != null and _current.has_method("on_settings_changed"):
			_current.on_settings_changed(kind))
	p.closed.connect(close_settings)
	_ui_layer.add_child(p)
	p.show_section(section)
	_settings_panel = p
	if _current.has_method("on_overlay"):
		_current.on_overlay(true, p)
	_current.set_process_input(false)   # 開いている間、下の画面は Esc や矢印に反応しない(パネルより先にキーを受け取ってしまうため)
	_update_settings_button()


func close_settings() -> void:
	if _settings_panel == null:
		return
	Settings.save_all(_settings_dict)
	var p := _settings_panel
	_settings_panel = null
	var ui_changed: bool = UiSets.override_id == "" and str(UiSets.current().id()) != _ui_before
	if is_instance_valid(_current) and _current.has_method("on_overlay"):
		_current.on_overlay(false)
	if is_instance_valid(_current):
		_current.set_process_input(true)
		if _songs_changed and _current.has_method("refresh_songs"):
			_current.refresh_songs()
	_songs_changed = false
	p.queue_free()
	_update_settings_button()
	if ui_changed:   # UI の見た目が変わった: タイトル・選曲は、新しい見た目で作り直す(ほかの画面は、次に開くときから)
		_rebuild_current()


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
func show_title(open_replays := false) -> void:
	var t = UiSets.current().make_title()
	t.play_requested.connect(show_menu)
	t.multi_requested.connect(show_multi)
	t.replays_requested.connect(func(): _open_replay_list(t))
	t.settings_requested.connect(open_settings)
	if t.has_signal("ui_try_requested"):   # クラシックのタイトルの「新しい UI で遊ぼう」
		t.ui_try_requested.connect(_try_ui)
	t.update_requested.connect(func():
		var p = UiSets.current().make_update()
		p.setup(updater)
		t.open_panel(p))
	if updater != null:
		t.update_info = updater.info
	if open_replays:   # リプレイを見終わって、一覧へ戻る
		t.ready.connect(func(): _open_replay_list(t), CONNECT_ONE_SHOT)
	_stop_music()
	_swap(t)


## リプレイの一覧を、タイトルの上に重ねる。選んだリプレイを再生して、閉じたら一覧へ戻る。
func _open_replay_list(t) -> void:
	var p = UiSets.current().make_replays()
	p.replay_requested.connect(func(name: String): show_replay(name, func(): show_title(true)))
	t.open_panel(p)


## 別の UI セットを試す: 設定の UI の見た目を変えて保存し、タイトルをその見た目で作り直す(幕の切り替えで)。
## 一度試したら、「新しい UI で遊ぼう」は出さない(設定の「画面」で戻した人に、また勧めない)。
func _try_ui(ui_id: String) -> void:
	var st := Settings.load_all()
	st.ui_style = ui_id
	st.ui_promo_hidden = true
	Settings.save_all(st)
	UiSets.override_id = ""   # 起動オプション --ui の上書きより、選んだものを使う
	UiSets.current()
	show_title()


func show_menu(pick := false) -> void:
	var m = UiSets.current().make_menu(pick)   # pick: マルチプレイの部屋の曲を選ぶとき(決定でロビーへ戻る)
	m.settings_requested.connect(open_settings)
	if pick:
		m.song_picked.connect(_on_song_picked)
		m.back_requested.connect(func(): show_multi())
	else:
		m.play_requested.connect(func(l, b, st: Dictionary, pre: Dictionary): start_game(l, b, st, -1.0, -1.0, pre))
		m.back_requested.connect(show_title)
		if m.has_signal("replay_requested"):   # lazer 風の選曲: 記録の再生ボタン
			m.replay_requested.connect(func(n: String): show_replay(n, func(): show_menu()))
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
	var m = UiSets.current().make_multi()
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
			Mods.multi_ok(settings.mods), 1.0, loader, bm)   # 撃破はひとり用
	show_multi()


## ゲームの準備(全員)。部屋の曲でプレイ画面を作る。作り終えると、画面が通信層へ準備完了を伝える(全員が済むと、ホストが開始の合図を出す)。
func _on_prepare_game(info: Dictionary) -> void:
	if net.song_bm == null:
		net.leave()
		show_multi("曲を読み込めませんでした")
		return
	var g = UiSets.current().make_game()
	g.setup_multi(net, info, net.song_loader, net.song_bm, Settings.load_all())
	g.finished.connect(func(stats, music): show_result(stats, music))
	g.quit_requested.connect(func():
		net.leave()
		show_title())
	_stop_music()
	_swap(g, true)


## 部屋を出た・閉じられた・切れた。理由があるとき(自分から出たのではないとき)、ロビー以外の画面なら入口へ戻す。
func _on_net_left(reason: String) -> void:
	if reason == "" or _kind == "multi":
		return
	show_multi(reason)


func _on_mp_result_done() -> void:
	if net != null and net.is_host():
		net.return_to_lobby()
	show_multi()


func start_game(loader, bm, settings: Dictionary, debug_seek := -1.0, debug_death_t := -1.0, pre := {}) -> void:
	_last_play = {"loader": loader, "bm": bm, "settings": settings, "pre": pre}
	var g = UiSets.current().make_game()
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
	if not stats.has("new_best"):   # リプレイから戻ったときは、もう記録した
		stats["new_best"] = Records.record_stats(stats)   # ひとりでクリアしたものだけ記録される(これまでの最高を超えたとき true)
	var r = UiSets.current().make_result()
	r.setup(stats, net)
	if stats.has("mp"):   # マルチプレイ: ロビーへ戻る(リトライはない)
		r.menu_requested.connect(_on_mp_result_done)
	else:
		r.menu_requested.connect(show_menu)
		r.replay_requested.connect(func(): show_replay(str(stats.get("replay", "")), func(): show_result(stats)))
		r.retry_requested.connect(func():
			start_game(_last_play.loader, _last_play.bm, _last_play.settings, -1.0, -1.0, _last_play.get("pre", {})))
	if music != null:
		_stop_music(0.0)
		_music = music
		add_child(music)
		music.finished.connect(func(): if _music == music: _stop_music(0.0))
	_swap(r, music != null)


# --- リプレイ ---

## リプレイを再生する。name: user://replays/ の中のファイル名。on_close: 閉じたあとに出す画面を作る関数。
func show_replay(name: String, on_close: Callable) -> void:
	var data := Replay.load_file(name)
	if data.is_empty():
		if overlay != null:
			overlay.toast("リプレイを読めません(消えたか、別のバージョンで作られたものです)")
		return
	var found := Replay.find_chart(str(data.md5))
	if found.is_empty():
		if overlay != null:
			overlay.toast("このリプレイの曲が見つかりません: %s" % str(data.get("title", "")))
		return
	var g = UiSets.current().make_game()
	g.setup_replay(found.loader, found.bm, Settings.load_all(), data)
	g.quit_requested.connect(func():
		_export_forget(g)
		on_close.call())
	g.replay_export_requested.connect(func(d: Dictionary, opts: Dictionary): _replay_export(name, d, opts, g))
	_stop_music()
	_swap(g)


var _export_last := ""          # 最後の書き出しの結果の文(確認用)
var _export := {}              # 動画の書き出し中: {pid, avi, mp4, dir, screen, phase, ffmpeg_pid}
var _export_timer: Timer


## 動画の書き出しの子プロセス: 操作パネルなしで、リプレイを(区間があればその区間だけ)1 倍の速さで流す。流し終わると、自分で終了する。
func _replay_export_child(path: String, trail_mode: int, trail_sec: float, range_a: float, range_b: float) -> void:
	var data := Replay.load_file(path)
	var found := Replay.find_chart(str(data.get("md5", ""))) if not data.is_empty() else {}
	if data.is_empty() or found.is_empty():
		printerr("replay-export: リプレイまたは曲を読めません: ", path)
		get_tree().quit(1)
		return
	var g = UiSets.current().make_game()
	g.replay_export = true
	g.replay_trail_mode = trail_mode
	g.replay_trail_sec = trail_sec
	g.replay_range_a = range_a
	g.replay_range_b = range_b
	g.setup_replay(found.loader, found.bm, Settings.load_all(), data)
	_stop_music()
	_swap(g)


## ffmpeg の場所(なければ ""): アプリと同じフォルダに置いたもの → PATH の通ったもの、の順。
func _ffmpeg_exe() -> String:
	var beside := OS.get_executable_path().get_base_dir().path_join("ffmpeg.exe")
	if FileAccess.file_exists(beside):
		return beside
	return "ffmpeg" if OS.execute("ffmpeg", ["-version"], []) == 0 else ""


## 動画の書き出し: 別のプロセスの Godot が、Movie Maker(--write-movie)で、リプレイを固定のフレーム時間で再生しながら、画面と音を AVI に書く。
## opts: {w, h, fps, trail_mode, trail_sec, a, b}(a, b = 区間。なければ -1)。空なら、書き出し中の中止。
## ffmpeg が PC にあれば、そのあと mp4 にも変換する(変換できたら、AVI は消す)。
func _replay_export(name: String, data: Dictionary, opts: Dictionary, screen) -> void:
	if opts.is_empty() or not _export.is_empty():
		if not _export.is_empty():
			_export_cancel()
		return
	var out_dir := OS.get_system_dir(OS.SYSTEM_DIR_MOVIES).path_join("Danmaku")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var base := ("%s_%s_%s" % [data.get("title", "replay"), data.get("diff", ""), stamp]).validate_filename().replace(" ", "_")
	var avi := out_dir.path_join(base + ".avi")
	var args := PackedStringArray()
	if not OS.has_feature("template"):   # 書き出した版は、自分の中にプロジェクトを持っている
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--write-movie", avi, "--fixed-fps", str(int(opts.get("fps", 60))), "--resolution", "%dx%d" % [int(opts.get("w", 1280)), int(opts.get("h", 720))], "--windowed", "--",
		"--replay-export", ProjectSettings.globalize_path(Replay.dir.path_join(name)), str(int(opts.get("trail_mode", 1))), str(float(opts.get("trail_sec", 3.0))),
		str(float(opts.get("a", -1.0))), str(float(opts.get("b", -1.0)))])
	Replay.write_progress(0.0)
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		if overlay != null:
			overlay.toast("動画の書き出しを始められませんでした")
		return
	_export = {"pid": pid, "avi": avi, "mp4": out_dir.path_join(base + ".mp4"), "dir": out_dir, "screen": screen, "phase": "movie", "ffmpeg_pid": 0}
	if _export_timer == null:
		_export_timer = Timer.new()
		_export_timer.wait_time = 0.5
		_export_timer.timeout.connect(_export_poll)
		add_child(_export_timer)
	_export_timer.start()
	_export_status("動画を書き出し中 0%(別のウィンドウが開きます。閉じないでください)")


func _export_status(text: String) -> void:
	var sc = _export.get("screen")
	if sc != null and is_instance_valid(sc) and sc.has_method("set_export_status"):
		sc.set_export_status(text)


## 画面を離れた(リプレイを閉じた)。書き出しは続けて、終わりは通知で知らせる。
func _export_forget(screen) -> void:
	if not _export.is_empty() and _export.screen == screen:
		_export.screen = null


func _export_cancel() -> void:
	if not _export.is_empty():
		OS.kill(int(_export.pid))
		if int(_export.ffmpeg_pid) > 0:
			OS.kill(int(_export.ffmpeg_pid))
		DirAccess.remove_absolute(str(_export.avi))
		_export_status("")
		_export = {}
		_export_timer.stop()
		if overlay != null:
			overlay.toast("動画の書き出しを中止しました")


func _export_poll() -> void:
	if _export.is_empty():
		_export_timer.stop()
		return
	if _export.phase == "movie":
		if OS.is_process_running(int(_export.pid)):
			_export_status("動画を書き出し中 %d%%(別のウィンドウ。閉じないでください)" % int(Replay.read_progress() * 100.0))
			return
		if not FileAccess.file_exists(str(_export.avi)):
			_export_finish("動画を書き出せませんでした")
			return
		if Replay.read_progress() < 0.98:   # 途中でウィンドウを閉じた
			DirAccess.remove_absolute(str(_export.avi))
			_export_finish("動画の書き出しが途中で終わったので、取り消しました")
			return
		var ff := _ffmpeg_exe()
		if ff != "":   # ffmpeg があれば、mp4 にも変換する
			var pid := OS.create_process(ff, ["-y", "-loglevel", "error", "-i", str(_export.avi), "-c:v", "libx264", "-preset", "medium", "-crf", "18",
				"-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", str(_export.mp4)])
			if pid > 0:
				_export.phase = "ffmpeg"
				_export.ffmpeg_pid = pid
				_export_status("mp4 に変換中…")
				return
		_export_finish("動画を書き出しました: %s(ffmpeg があれば mp4 にも変換できます)" % str(_export.avi), str(_export.avi))
		return
	if OS.is_process_running(int(_export.ffmpeg_pid)):
		return
	if FileAccess.file_exists(str(_export.mp4)) and FileAccess.open(str(_export.mp4), FileAccess.READ).get_length() > 1024:
		DirAccess.remove_absolute(str(_export.avi))
		_export_finish("動画を書き出しました: %s" % str(_export.mp4), str(_export.mp4))
	else:
		_export_finish("mp4 への変換に失敗したので、AVI を残しました: %s" % str(_export.avi), str(_export.avi))


## 書き出しが終わった。path: できたファイル(失敗なら "")。リプレイ画面が開いていれば、結果と「出力先を開く」を出す。
func _export_finish(msg: String, path := "") -> void:
	var sc = _export.get("screen")
	_export_status("")
	if sc != null and is_instance_valid(sc) and sc.has_method("set_export_done"):
		sc.set_export_done(path, msg.get_slice("(", 0) if path != "" else msg)
	_export = {}
	_export_timer.stop()
	if overlay != null:
		overlay.toast(msg, 9.0)
	_export_last = msg




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
	if overlay == null or _current == null or _kind == "game":
		return   # 通常の起動でだけ、プレイ中以外に見張る
	_watch_poll()


## F11 で全画面 ⇔ ウィンドウ。パネルがキーを全部受け止めている間も効くよう、押した瞬間を見て判断する。プレイ中(ポーズ以外)は効かない。
func _poll_fullscreen_key() -> void:
	var down := Input.is_key_pressed(KEY_F11)
	var edge := down and not _f11_down
	_f11_down = down
	if not edge or _current == null or _fading:
		return
	if _kind == "game" and not _current.is_paused():
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
			failed = "%s(%s)" % [str(p).get_file(), info.error]   # 読めない理由(mania だけの曲など)を添える
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
			if extra.has("toggle"):   # 読み込みのあとで MOD を付ける(弾幕 v1 の入り切りで、曲を読み直す流れ): --shot menu out.png toggle v1
				while _current._job_pending or _current._diff_cards.is_empty():
					await get_tree().process_frame
				print("toggle: 読み込み後 v2=%s Lv=%.2f" % [str(_current._gens_v2), float(_current._ratings[_current._diff_sel].level)])
				_current.settings.mods = extra.filter(func(x): return not Mods.find(x).is_empty())
				_current._on_mods_changed()
				while _current._job_pending:
					await get_tree().process_frame
				await get_tree().process_frame
				print("toggle: 切り替え後 v2=%s Lv=%.2f 選択=%d" % [str(_current._gens_v2), float(_current._ratings[_current._diff_sel].level), _current._diff_sel])
			if extra.has("empty"):   # 曲が 1 つもない状態: --shot menu out.png empty
				await _current.debug_empty()
			if extra.has("loading"):   # 曲の読み込み中の見た目: --shot menu out.png loading
				await _current.debug_loading()
			if extra.has("records") and _current.has_method("debug_records"):   # lazer 風: 作り物の記録(保存しない): --shot menu out.png records
				while _current._job_pending:
					await get_tree().process_frame
				_current.debug_records()
			for e in extra:   # lazer 風: 検索 q=文字 / 並び替え sort=title|artist|added
				if str(e).begins_with("q=") and _current.has_method("debug_search"):
					_current.debug_search(str(e).trim_prefix("q="))
				if str(e).begins_with("sort=") and _current.has_method("debug_sort"):
					_current.debug_sort(str(e).trim_prefix("sort="))
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
			show_menu()   # 例: --shot options out.png 2(先頭の数字はセクション 0=操作 1=音 2=画面 3=曲 4=その他)
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
			var gs := {"offset_ms": 0, "density_mul": 1.0, "eye_comfort": not extra.has("sharp"),   # sharp: 目に優しい表示を切る(既定は入)
				"mods": extra.filter(func(x): return not Mods.find(x).is_empty())}   # 例: ... Extra 40 hell rush
			var death_t := -1.0
			if extra.size() > 2 and extra[2].begins_with("death"):
				death_t = float(extra[2].trim_prefix("death"))
			start_game(loader, bm, gs, secs, death_t)
			if extra.size() > 2 and extra[2] == "pause":
				_current._set_paused(true)
			if extra.size() > 2 and extra[2] == "wait":   # 再開の待ち(自機だけを見せている)
				_current._set_paused(true)
				_current._set_paused(false)
				_current._set_ship_in(1.0)
				_current._tick_resume_wait(0.35)
			for ex in extra:   # 自機の位置を決める(エリアの中の自機の演出を撮る): ... Insane 62 v2 practice pos:200,360
				if str(ex).begins_with("pos:"):
					var xy := str(ex).trim_prefix("pos:").split(",")
					_current.sim.player_pos = Vector2(float(xy[0]), float(xy[1]))
					_current.sim._update_zone_debuff(_current._now)
					_current._refresh()
			for ex in extra:   # エリアの効果の演出だけを撮る(自機にその効果がかかっている状態にする): ... Insane 30 v2 practice fx:heal
				if str(ex).begins_with("fx:"):
					_current.sim.zone_debuff = str(ex).trim_prefix("fx:")
					_current.sim.zone_push = Vector2(110, 0) if _current.sim.zone_debuff == "flow" else Vector2.ZERO
					_current._refresh()
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
			if extra.has("retry"):   # R 長押しの途中(進み具合の輪)を撮る
				_current._retry_hold = _current.RETRY_HOLD * 0.6
				_current._update_retry_ui()
			if extra.has("kiai"):   # キアイの光のピークを撮る(拍の頭)
				_current._kiai_a = 1.0
				_current._beat_glow = 1.0
				_current._apply_kiai()
				_current._refresh()
			if extra.has("slow"):   # 低速中の見た目(暗闇の可視範囲が狭まる)を撮る  例: ... Extra 40 dark slow
				_current.sim.slow = true
				_current._dark_scale = _current.DARK_SLOW_SCALE
				_current._refresh()
			if _current.sim.boss != null:   # 撃破 MOD: ボスの真下に自機を置く / bossitem: アイテム・攻撃力 / bossdown: 撃破の演出の途中
				var b = _current.sim.boss
				var r: Rect2 = _current.sim.move_rect
				_current.sim.player_pos = Vector2(clampf(b.pos.x, r.position.x + 10.0, r.end.x - 10.0), clampf(b.pos.y + 160.0, r.position.y + 10.0, r.end.y - 10.0))
				if extra.has("bossitem"):   # 強化の途中・アイテムが 5 種類落ちている・HP 42%
					b.power = 2
					b.power_mul = 1.5
					b.rate_lv = 1
					b.wide_lv = 1
					b.hp = b.max_hp * 0.42
					var kinds := ["power", "rate", "wide", "heal", "bomb"]
					for k in range(kinds.size()):
						b.items.append({"kind": kinds[k], "p": _current.sim.player_pos + Vector2(-120.0 + 60.0 * k, -110.0), "v": Vector2.ZERO, "t": 0.0})
					for k in range(16):
						b.shots.append(_current.sim.player_pos + Vector2(Boss.WIDE_OFFSETS[1][k % 4], -20.0 - 30.0 * float(k / 4)))
				if extra.has("bossdown"):
					_current._update_boss_hud(10.0)   # ゲージを出しきってから倒す
					b.hp = 0.0
					b.defeated = true
					b.defeat_t = _current._now - 0.35
					b.defeat_pos = b.pos
				if extra.has("bosswarn"):   # ボスの登場(WARNING の途中・ゲージが現れるところ)
					var tw: float = b.appear_t + 0.15
					_current._now = tw
					b.pos = b.pos_at(tw)
					_current.field.clear()
					for k in range(40):
						_current._boss_gauge.tick(1.0 / 60.0, tw - 40.0 / 60.0 + k / 60.0)
				elif extra.has("bossbonus"):   # ボーナスタイムの途中(早送りの速いところ)
					var tb: float = _current.sim.loop_end + 1.3
					_current._now = tb
					b.pos = b.pos_at(tb)
					_current.field.clear()
					_current._update_boss_hud(10.0)
				elif not extra.has("bossdown"):
					_current._update_boss_hud(10.0)
				if extra.has("bossdown"):   # ゲージが砕けている途中
					for k in range(24):
						_current._boss_gauge.tick(1.0 / 60.0, _current._now)
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
				var up = UiSets.current().make_update()
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
			nn.results = {1: {"name": "Alice", "score": 903120.0, "hits": 0, "graze": 214, "hit_ms": 0, "dmg": 0.00, "damage": 0.00}, 2: {"name": "Bob", "score": 871400.0, "hits": 3, "graze": 180, "hit_ms": 480, "dmg": 0.43, "damage": 0.43,
				"hp": HpGraph.downsample(HpGraph.points_from_log(_fake_hp(2, 118.0, false, 3).hp_log, 0.25, 118.0, 0.7), 48), "dur": 118.0}}
			var mode_r := "coop" if extra.has("coop") else "versus"
			show_result({"title": "Reol - No title [Insane]", "level": 5.8, "mean": 105.0, "peak": 141.0, "failed": false, "progress": 1.0, "hits": 3, "hit_ms": 480, "dmg": 0.43, "damage": 0.43, "graze": 394, "score": 903120.0, "score_gross": 1013000.0,
				"damage_factor": 0.89, "score_graze": 13000.0, "practice": false, "score_base": 1000000.0, "mod_ids": [], "mods": "",
				"mp": {"mode": mode_r, "my_id": 1, "players": [{"id": 1, "name": "Alice", "slot": 0}, {"id": 2, "name": "Bob", "slot": 1}, {"id": 3, "name": "Carol", "slot": 2}]}}.merged(_fake_hp(1, 118.0, false, 3)))
			_current.skip_animation()
		"bullets":
			_shot_bullets()
		"result":
			var rl := OszLoader.new()
			rl.open(_dev_osz("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz"))
			var rbm = rl.difficulties[rl.difficulties.size() - 1]
			show_result({"title": "Reol - No title [Insane]", "level": 5.8, "mean": 105.0, "peak": 141.0, "failed": extra.size() > 0 and extra[0] == "failed", "progress": 0.63, "hits": 0 if extra.has("ss") else 2, "hit_ms": 180, "dmg": 0.16, "damage": 0.16, "graze": 123, "score": 1013000.0 if extra.has("ss") or extra.has("s") else (300000.0 if extra.has("f") else 830660.0), "score_gross": 1013000.0, "damage_factor": 0.82, "score_graze": 13000.0, "practice": false,
				"score_base": 1060000.0, "mod_ids": ["hell", "rush"], "mods": "地獄 + 加速",
				"bg": rl.load_image(rbm.background) if rbm.background != "" else null}.merged(_fake_hp(1, 118.0, extra.size() > 0 and extra[0] == "failed", 3)).merged(
				{"boss": {"defeated": not (extra.size() > 0 and extra[0] == "failed"), "defeat_t": 152.0, "hp_left": 0.38, "loops": 2}, "score_boss_time": 15600.0, "mod_ids": ["boss", "shrink"], "mods": "撃破 + 小型化"} if extra.has("boss") else {}, true))   # 例: --shot result out.png [failed] boss
			_current.skip_animation()   # スクリーンショットでは、演出を待たない
	_setup_ui_layer()   # 右上の「設定」ボタンも撮る
	_update_settings_button()
	if animated:
		var t0 := Time.get_ticks_msec()
		var k := 0
		var times := [0.1, 0.3, 0.6, 1.2, 2.5]
		for e in extra:   # 例: t=0.7,0.8,0.9 で、撮る時刻(開いてからの秒)を指定できる。slow=0.2 で、動きを 0.2 倍にゆっくりにする(短い演出を撮る)
			if str(e).begins_with("slow="):
				Engine.time_scale = float(str(e).trim_prefix("slow="))
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
	var art_t0 := Time.get_ticks_msec()
	for n in range(3):
		await get_tree().process_frame
	while SongArt.busy() and Time.get_ticks_msec() - art_t0 < 8000:   # 曲の一覧の画像(別スレッド)がそろうのを待つ
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
	return {"hp_log": log, "hp_step": 0.25, "hp_end": 0.0 if fail else g, "hp_t_end": end_t, "hit_log": hit_times, "breaks": [[48.0, 60.0]], "first_fire": 8.0, "last_fire": dur - 4.0}


## 開発用: 動かずに被弾するまで待ち、ゲームオーバー演出→リザルト遷移を確認する。-- --smoke-death
## 撃破 MOD の曲の繰り返し: 周の最後のノーツの少し前へ飛ばし、ボーナスタイムの早送りで次の周の始まりに着くこと
## (早送りで速くなる・曲クロックが戻らない・着いたあと曲と曲クロックがそろっている・ゲームが終わらない)。
func _smoke_bossloop() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	start_game(loader, loader.difficulties[0], {"mods": ["boss", "practice"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
	var g = _current
	while not g._audio_started:
		await get_tree().process_frame
	var sim = g.sim
	print("loop_len=%.2f loop_from=%.2f loop_end=%.2f song_len=%.2f" % [sim.loop_len, sim.loop_from, sim.loop_end, g._audio.stream.get_length()])
	var start: float = sim.loop_end - 1.0
	g._audio.seek(start * g._rate)
	g._now = start
	g._sim_t = start
	var prev: float = g._now
	var mono := true
	var peak := 0.0
	var bonus_seen := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 10000:
		await get_tree().process_frame
		mono = mono and g._now >= prev - 0.0001
		prev = g._now
		peak = maxf(peak, g._audio.pitch_scale)
		bonus_seen = bonus_seen or sim.bonus_left(g._now) >= 0.0
	var pos: float = g._audio.get_playback_position()
	var clock_from_audio: float = pos / g._rate + float(g._loop_k) * sim.loop_len
	print("after: loop_k=%d now=%.2f pos=%.2f audio_clock=%.2f peak_pitch=%.2f pitch=%.2f bonus_seen=%s monotonic=%s finished=%s loop_index=%d" % [g._loop_k, g._now,
		pos, clock_from_audio, peak, g._audio.pitch_scale, str(bonus_seen), str(mono), str(sim.finished), sim.loop_index(g._now)])
	var ok: bool = g._loop_k == 1 and sim.loop_index(g._now) == 1 and g._audio.playing and mono and not sim.finished and bonus_seen \
		and peak > g.FF_PEAK * 0.9 and is_equal_approx(g._audio.pitch_scale, g._rate) and absf(clock_from_audio - g._now) < 0.15
	print("smoke-bossloop: ", "OK" if ok else "FAILED")
	get_tree().quit(0 if ok else 1)


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
	print("Esc        -> paused=%s layer=%s  arena_cover=%s (expect true: ポーズ中は弾を見せない)" % [str(g._paused), str(g._pause_layer.visible), str(g._pause_cover.visible and g._pause_cover.color.a > 0.99)])
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
	print("Down x2, Enter -> sel=%d (expect 0)  resume_wait=%s (expect true: 自機だけを見せて、操作を待つ)  bullets_hidden=%s ship_only=%s  pause_menu=%s (expect false)" % [g._pause_sel, str(g._resume_wait), str(not g.field.visible), str(g._view_under.ship_only), str(g._pause_layer.visible)])
	await _key(KEY_SPACE)   # 待ちに入った直後は、操作を受けない(ダブルクリックで、すぐ始まらないように)
	print("Space right away -> still waiting=%s (expect true)" % str(g._resume_wait))
	await get_tree().create_timer(0.4).timeout
	await _key(KEY_ESCAPE)   # 待ちの間の Esc は、ポーズへ戻る
	print("Esc while waiting -> back to pause menu=%s (expect true)  resume_wait=%s (expect false)" % [str(g._pause_layer.visible), str(g._resume_wait)])
	await _key(KEY_DOWN)
	await _key(KEY_UP)
	await _key(KEY_ENTER)   # もう一度「再開」
	await get_tree().create_timer(0.4).timeout
	await _key(KEY_SPACE)   # 操作で、動き出す
	print("Space after wait -> paused=%s (expect false)  bullets_visible=%s (expect true)  ship_only=%s (expect false)" % [str(g._paused), str(g.field.visible), str(g._view_under.ship_only)])
	await _key(KEY_ESCAPE)   # 再開した直後は、またポーズできない(連続ポーズで、止めた弾を観察する悪用を防ぐ)
	print("Esc right after resume -> paused=%s (expect false: クールダウン %.1fs)  bullets_alpha=%.2f (expect < 1 か 1: 弾が現れていく)" % [str(g._paused), g._pause_cd, g.field.modulate.a])
	await get_tree().create_timer(GameScreen.PAUSE_COOLDOWN + 0.2).timeout
	await _key(KEY_ESCAPE)   # もう一度ポーズ
	print("Esc after cooldown -> paused=%s (expect true)  bullets_alpha=%.2f" % [str(g._paused), g.field.modulate.a])
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
		if g == null and _current != m and (_current.get("kind") == "game"):
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


## 開発用: 起動したままの間に見つかった新しいバージョンの知らせを確かめる(知らせるだけ・同じ版は 1 度だけ・プレイ中は離れてから・自動更新はしない)。-- --smoke-updatenotice
func _smoke_updatenotice() -> void:
	var original := Settings.load_all()
	var st := {"fails": 0}
	var chk := func(cond: bool, msg: String):
		print(("  ok   " if cond else "  FAIL ") + msg)
		if not cond:
			st.fails += 1
	var d := Settings.load_all()
	d.check_update = true
	d.auto_update = true   # 入れていても、再確認では自動更新しない
	d.last_auto_update = ""
	Settings.save_all(d)
	updater = Updater.new()
	add_child(updater)
	updater.allow_any_url = true
	updater.force_apply = true
	updater.check_finished.connect(_on_update_checked)   # 本番では、_ready がつなぐ
	overlay = HudOverlay.new()
	add_child(overlay)
	var mk := func(v: String) -> Dictionary:
		return {"ok": true, "newer": true, "version": v, "notes": "test", "page": Updater.PAGE_URL, "asset_url": "http://127.0.0.1:9/none.zip", "asset_size": 0, "digest": ""}
	# 1) 選曲画面にいるとき: 画面の下に知らせる。パネルは開かない・自動更新は始めない
	show_menu()
	await get_tree().create_timer(1.0).timeout
	overlay._toast.visible = false
	_update_notified = ""
	_update_rechecking = true
	_on_update_checked(mk.call("9.9.9"))
	chk.call(overlay._toast.visible and overlay._toast_l.text.contains("9.9.9") and overlay._toast_t > 5.0, "見つかったら、知らせる(%s。%.0f 秒出す)" % [overlay._toast_l.text, overlay._toast_t])
	chk.call(_settings_panel == null and str(Settings.load_all().last_auto_update) == "", "知らせるだけ(自動更新は始めない)")
	# 2) 同じ版は、もう知らせない
	overlay._toast.visible = false
	_update_rechecking = true
	_on_update_checked(mk.call("9.9.9"))
	chk.call(not overlay._toast.visible, "同じ版は、2 回目は知らせない")
	# 3) 古い版・見つからなかったときは、何もしない
	_update_rechecking = true
	_on_update_checked({"ok": true, "newer": false})
	chk.call(not overlay._toast.visible and not _update_rechecking, "新しい版がなければ、何もしない(再確認の印は戻る)")
	# 4) プレイ中に見つかったら、すぐには知らせず、プレイを離れてから知らせる
	_kind = "game"
	_update_rechecking = true
	_on_update_checked(mk.call("9.9.10"))
	chk.call(not overlay._toast.visible and not _update_pending.is_empty(), "プレイ中は、知らせずに取っておく")
	show_menu()
	await get_tree().create_timer(2.6).timeout
	chk.call(overlay._toast.visible and overlay._toast_l.text.contains("9.9.10") and _update_pending.is_empty(), "プレイを離れたあとに、知らせる(%s)" % overlay._toast_l.text)
	# 5) タイトル画面では、案内のボタンも出る。ここでも自動更新はしない
	overlay._toast.visible = false
	show_title()
	await get_tree().create_timer(1.2).timeout
	_current._update_btn = null
	_update_rechecking = true
	_on_update_checked(mk.call("9.9.11"))
	chk.call(_current._update_btn != null and overlay._toast.visible, "タイトル画面では、案内のボタンも出る")
	await get_tree().create_timer(0.5).timeout
	chk.call(_current._overlay == null and str(Settings.load_all().last_auto_update) == "", "タイトル画面でも、再確認では自動更新しない")
	# 6) 確認の失敗で、見つけた新しい版の情報を消さない / 確認中・ダウンロード中は再確認しない
	updater.info = mk.call("9.9.11")
	updater._finish_check({"ok": false, "error": "x"})
	chk.call(bool(updater.info.get("newer", false)), "あとの確認が失敗しても、見つけた版の情報は残る")
	updater._finish_check({"ok": true, "newer": false})
	chk.call(not bool(updater.info.get("newer", false)), "確認できて「新しい版はない」なら、置き換わる")
	chk.call(not updater.is_busy(), "何もしていないときは、再確認できる")
	updater.stage_exe = "Danmaku.exe"
	chk.call(updater.is_busy(), "入れ替えの準備ができている間は、再確認しない")
	updater.stage_exe = ""
	# 7) 手元のサーバー(tests/fake_release_server.js)があれば、定期の再確認(通信 → 知らせる)まで通して確かめる。-- --smoke-updatenotice api=http://127.0.0.1:8765/releases
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("api="):
			updater.api_url = str(arg).trim_prefix("api=")
			updater.info = {}
			_update_notified = ""
			_update_rechecking = false
			show_menu()
			await get_tree().create_timer(1.0).timeout
			overlay._toast.visible = false
			_recheck_update()
			chk.call(_update_rechecking, "再確認を始めた(確認中の印)")
			var t0 := Time.get_ticks_msec()
			while not overlay._toast.visible and Time.get_ticks_msec() - t0 < 20000:
				await get_tree().process_frame
			chk.call(overlay._toast.visible and overlay._toast_l.text.contains("9.9.9") and not _update_rechecking, "サーバーから新しい版を見つけて、知らせた(%s / 表示=%s 確認中の印=%s)" % [overlay._toast_l.text, str(overlay._toast.visible), str(_update_rechecking)])
			chk.call(bool(updater.info.get("newer", false)) and _settings_panel == null and str(Settings.load_all().last_auto_update) == "", "info に残り(タイトルのボタンの元)、自動更新は始めない")
			overlay._toast.visible = false
			_recheck_update()
			await get_tree().create_timer(1.5).timeout
			chk.call(not overlay._toast.visible, "もう一度確認しても、同じ版は知らせない")
	Settings.restore(original)
	print("smoke-updatenotice: ", "OK" if st.fails == 0 else "%d FAILED" % st.fails)
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
	chk.call(t._overlay != null and "auto_start" in t._overlay and t._overlay._busy, "更新のパネルが開き、ダウンロード中になっている")
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
	_current._open(UiSets.current().make_howto())
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


## .osz の中の譜面(.osu)の数。
func _osu_count(osz: String) -> int:
	var z := ZIPReader.new()
	if z.open(osz) != OK:
		return 0
	var n := 0
	for f in z.get_files():
		if f.to_lower().ends_with(".osu"):
			n += 1
	z.close()
	return n


## 開発用: 選曲画面(いまの UI)で、osu! の Songs フォルダの曲が、少しずつ一覧に足され、選んで読み込めることを確かめる。
## あわせて、弾幕 v2 の入り切りで同じ曲を読み直し、選んでいた難易度が保たれることも見る。-- [--ui lazer] --smoke-osu-menu
## 手元の .osz(songs に入れていないもの)を一時フォルダに展開して、Songs フォルダの代わりにする。ユーザーの設定は、終わりに元へ戻す。
func _smoke_osu_menu() -> void:
	var original := Settings.load_all()
	var st := {"fails": 0}
	var chk := func(cond: bool, msg: String):
		print(("  ok   " if cond else "  FAIL ") + msg)
		if not cond:
			st.fails += 1
	var have := {}
	for p in SongLibrary.find_osz():
		have[str(p).get_file().to_lower()] = true
	var src: Array = []
	for f in DirAccess.get_files_at("C:/Desktop/my_apps/DDA"):
		if f.to_lower().ends_with(".osz") and not have.has(f.to_lower()):
			src.append("C:/Desktop/my_apps/DDA/" + f)
	src.sort_custom(func(a, b): return _osu_count(a) > _osu_count(b))   # 難易度の多い曲から(弾幕 v2 の読み直しで、難易度が保たれるかを見るため)
	src = src.slice(0, 2)
	if src.is_empty():
		print("smoke-osu-menu: (試せる .osz がないので省略)")
		get_tree().quit()
		return
	var tmp := OS.get_temp_dir().path_join("danmaku_osu_menu_test").replace("\\", "/")
	var songs_dir := tmp.path_join("Songs")
	for osz in src:
		var dest := songs_dir.path_join(str(osz).get_file().get_basename())
		DirAccess.make_dir_recursive_absolute(dest)
		var z := ZIPReader.new()
		z.open(osz)
		for f in z.get_files():
			if f.ends_with("/"):
				continue
			var out := dest.path_join(f)
			DirAccess.make_dir_recursive_absolute(out.get_base_dir())
			var w := FileAccess.open(out, FileAccess.WRITE)
			w.store_buffer(z.read_file(f))
			w.close()
		z.close()
	var s2 := original.duplicate()
	s2.osu_songs = true
	s2.osu_songs_dir = songs_dir
	s2.mods = []
	Settings.save_all(s2)
	SongLibrary.apply_osu_settings(s2)
	show_menu()
	await get_tree().create_timer(0.8).timeout
	var m = _current
	var folders := func() -> int: return m._songs.filter(func(sg): return bool(sg.get("folder", false))).size()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000 and (folders.call() < src.size() or m._song_cards.size() < m._songs.size()):
		await get_tree().process_frame
	chk.call(folders.call() == src.size(), "osu! の Songs の曲が一覧に足される(フォルダの曲 %d / %d、全部で %d 曲)" % [folders.call(), src.size(), m._songs.size()])
	chk.call(m._song_cards.size() == m._songs.size(), "足された曲にも行ができる(%d 行)" % m._song_cards.size())
	var idx: int = m._songs.size() - 1
	chk.call(bool(m._songs[idx].get("folder", false)), "足された曲は、フォルダの曲として覚えている(%s)" % str(m._songs[idx].path).get_file())
	while m._job_pending:
		await get_tree().process_frame
	m._select_song(idx)
	while m._job_pending:
		await get_tree().process_frame
	await get_tree().process_frame
	chk.call(m._loader != null and m._song_sel == idx and m._diff_cards.size() >= 1, "フォルダの曲を選んで読み込める(難易度 %d 個)" % m._diff_cards.size())
	# 弾幕の作り方の切り替え(初期状態は v2。MOD「弾幕 v1」で v1): 同じ曲を読み直し、選んでいた難易度はそのまま
	if m.has_method("_on_mods_changed") and m._diff_cards.size() >= 2:
		var v2_now := func() -> bool: return bool(m.browser.gens_v2) if "browser" in m else bool(m._gens_v2)
		chk.call(v2_now.call() and str((m._gens[m._diff_sel] as Dictionary).get("style", "")) == "v2", "初期状態の弾幕は v2 の作り方")
		m._select_diff(1)
		var ver: String = str(m._loader.difficulties[m._diff_sel].version)
		m.settings.mods = ["v1"]
		m._on_mods_changed()
		var t1 := Time.get_ticks_msec()
		while (m._job_pending or v2_now.call()) and Time.get_ticks_msec() - t1 < 20000:
			await get_tree().process_frame
		await get_tree().process_frame
		chk.call(not v2_now.call() and str(m._loader.difficulties[m._diff_sel].version) == ver, "MOD「弾幕 v1」を付けると読み直し、難易度はそのまま(%s)" % ver)
		chk.call(str((m._gens[m._diff_sel] as Dictionary).get("style", "")) == "v1", "弾幕が v1 の作り方になっている")
		m.settings.mods = []
		m._on_mods_changed()
		t1 = Time.get_ticks_msec()
		while (m._job_pending or not v2_now.call()) and Time.get_ticks_msec() - t1 < 20000:
			await get_tree().process_frame
		await get_tree().process_frame
		chk.call(v2_now.call() and str((m._gens[m._diff_sel] as Dictionary).get("style", "")) == "v2", "MOD を外すと v2 に戻る")
	# 上のツールバーのプレイヤー(lazer): いま流れている曲が出て、次の曲・一時停止が効く
	if m.has_method("_player_step"):
		var t1 := Time.get_ticks_msec()
		while (m._job_pending or not NowPlaying.is_playing()) and Time.get_ticks_msec() - t1 < 20000:
			await get_tree().process_frame
		var title0 := NowPlaying.title
		chk.call(NowPlaying.is_playing() and title0 != "" and title0 == str(m._songs[m._song_sel].title), "プレイヤーに、流れている曲が出る(%s)" % title0)
		m._player_step(1)
		t1 = Time.get_ticks_msec()
		while (m._job_pending or NowPlaying.title == title0 or not NowPlaying.is_playing()) and Time.get_ticks_msec() - t1 < 20000:
			await get_tree().process_frame
		chk.call(NowPlaying.title != title0 and NowPlaying.title == str(m._songs[m._song_sel].title), "次の曲で、プレイヤーの曲名が変わる(%s → %s)" % [title0, NowPlaying.title])
		NowPlaying.toggle()
		chk.call(not NowPlaying.is_playing() and NowPlaying.player.stream_paused, "一時停止できる")
		NowPlaying.toggle()
		chk.call(NowPlaying.is_playing(), "再生に戻せる")
	Settings.restore(original)
	SongLibrary.apply_osu_settings(original)
	print("smoke-osu-menu: ", "OK" if st.fails == 0 else "%d FAILED" % st.fails)
	get_tree().quit()


## 開発用: lazer 風の選曲の一覧の動きを確かめる。-- --ui lazer --smoke-carousel
## 曲を移ったとき: 選んだ行が、フレームごとに大きく跳ばない / 読み込みが終わっても、難易度の行を作り直さない(同じ行のまま数字だけ変わる)。
## 並び替えたとき: 並びが変わった最初のフレームから、行が動き始めている(見えていた行は滑り、外から入る行はそっと現れる)。
func _smoke_carousel() -> void:
	var original := Settings.load_all()
	var st := {"fails": 0}
	var chk := func(cond: bool, msg: String):
		print(("  ok   " if cond else "  FAIL ") + msg)
		if not cond:
			st.fails += 1
	show_menu()
	await get_tree().create_timer(0.8).timeout
	var m = _current
	while m._job_pending:
		await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	for step in range(3):
		var nxt: int = m.browser.step_in_view(m._song_sel, 1 if step < 2 else -1)
		if nxt == m._song_sel:
			nxt = m.browser.step_in_view(m._song_sel, -1)
		m._select_song(nxt)
		var row: Control = m._rows[nxt]
		var ys: Array = []
		var heights: Array = []
		var dbg: Array = [[m._scroll.scroll_vertical, int(row.position.y), int(m._smooth.target()), int(row.get_global_rect().position.y)]]
		for f in range(50):
			await get_tree().process_frame
			ys.append(row.get_global_rect().position.y)
			if f < 6:
				dbg.append([m._scroll.scroll_vertical, int(row.position.y), int(m._smooth.target()), int(row.get_global_rect().position.y)])
			heights.append(m._diff_box.custom_minimum_size.y if m._diff_box != null else 0.0)
		while m._job_pending:
			await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout
		var max_jump := 0.0
		var reversals := 0
		for k in range(1, ys.size()):
			max_jump = maxf(max_jump, absf(float(ys[k]) - float(ys[k - 1])))
			if k >= 2 and (float(ys[k]) - float(ys[k - 1])) * (float(ys[k - 1]) - float(ys[k - 2])) < -0.01:
				reversals += 1
		var shrank := false
		for k in range(1, heights.size()):
			if float(heights[k]) < float(heights[k - 1]) - 0.5:
				shrank = true
		if max_jump >= 60.0:
			print("    [scroll, row_y, target, screen_y]=", dbg)
			print("    ys=", ys.map(func(v): return int(v)), "
    h=", heights.map(func(v): return int(v)), "
    scroll target=", m._smooth.target(), " sc=", m._scroll.scroll_vertical)
		chk.call(max_jump < 60.0 and reversals <= 1, "曲 %d へ: 選んだ行の動きはなめらか(1 フレームの最大 %.1f px、向きの反転 %d 回)" % [nxt, max_jump, reversals])
		chk.call(not shrank, "曲 %d へ: 難易度の一覧の高さは、伸びるだけ(縮んでから伸び直さない)" % nxt)
		var kept: bool = m._diff_rows.size() > 0 and m._diff_cards.size() == m._diff_rows.size()
		chk.call(kept, "曲 %d へ: 読み込み後、難易度の行が押せる(%d 行)" % [nxt, m._diff_cards.size()])
	# 難易度の多い曲の一覧が閉じるとき: 一覧の端(上端・下端)にいても、新しく選んだ行が跳ばない
	var big := -1
	var big_n := 0
	for i in range(m._songs.size()):
		var n: int = SongArt.diffs_of(str(m._songs[i].md5)).size()
		if n > big_n:
			big_n = n
			big = i
	for case_i in range(4):
		m._select_song(big)
		while m._job_pending:
			await get_tree().process_frame
		await get_tree().create_timer(0.6).timeout
		var at_end := case_i % 2 == 0
		m._smooth.scroll_to(1.0e6 if at_end else 0.0)
		await get_tree().create_timer(0.8).timeout
		var to: int = m.browser.step_in_view(big, -1 if case_i < 2 else 1)
		if to == big:
			continue
		m._select_song(to)
		var view: Rect2 = m._scroll.get_global_rect()
		var prev := {}
		var mj := 0.0
		for f in range(80):   # 画面に見えている曲の行すべての、1 フレームの動き(いちばん大きいもの)
			await get_tree().process_frame
			for r in m._rows:
				var gy: float = (r as Control).get_global_rect().position.y
				if prev.has(r) and view.has_point(Vector2(view.position.x + 10, gy + 20)):
					mj = maxf(mj, absf(gy - float(prev[r])))
				prev[r] = gy
		while m._job_pending:
			await get_tree().process_frame
		chk.call(mj < 16.0, "難易度 %d 個の一覧が閉じる(%s・%s の曲へ): 見えている行の 1 フレームの最大の動き %.1f px" % [big_n, "下端" if at_end else "上端", "上" if case_i < 2 else "下", mj])
	# 読み込みで行を作り直さない: 読み込み前の行と、読み込み後の行が同じもの
	var nxt2: int = m.browser.step_in_view(m._song_sel, 1)
	m._select_song(nxt2)
	await get_tree().process_frame
	var before_rows: Array = m._diff_rows.duplicate()
	while m._job_pending:
		await get_tree().process_frame
	await get_tree().process_frame
	chk.call(before_rows.is_empty() or before_rows == m._diff_rows, "読み込みの前後で、難易度の行は同じもの(作り直していない。%d 行)" % before_rows.size())
	# 並び替え: 最初のフレームから動いている
	for mode in ["artist", "title", "rank", "added"]:
		var order0: Array = m.browser.view()
		m.debug_sort(mode)
		var changed: bool = m.browser.view() != order0
		await get_tree().process_frame
		var moving := 0
		for c in m._box.get_children():
			if c is Control and c.visible and c.get_child_count() > 0:
				var inner: Control = c.get_child(0)
				if absf(inner.position.y - float(inner.get_meta("base_y", 0.0))) > 1.0 or inner.modulate.a < 0.99:   # 滑っている行、または、画面の外から入ってきて現れている行
					moving += 1
		chk.call((moving > 0) == changed, "並び替え(%s): 並びが%s → 最初のフレームで、%d 行が前の位置から動き始めている" % [mode, "変わった" if changed else "同じ", moving])
		await get_tree().create_timer(0.8).timeout
	# 曲が多いとき(作り物の曲を 300 曲足す): 滑る行は、前も後も画面の中にあった行だけ。外から入る行は、滑らずにそっと現れる(目にうるさくしない)
	var n_real: int = m._songs.size()
	for q in range(300):
		m._songs.append({"path": "user://none%d.osz" % q, "title": "Fake %03d" % ((q * 37) % 300), "artist": "Z%d" % (q % 7), "key": "fake%d" % q, "key2": "fake%d" % q, "md5": "fake%d" % q, "ids": [], "mtime": q, "folder": false})
		m._art_asked[n_real + q] = true   # 本物の曲ではないので、画像は頼まない
	m._sync_cards()
	m.debug_sort("title")
	await get_tree().create_timer(0.8).timeout
	m._smooth.scroll_to(3000.0)
	await get_tree().create_timer(1.0).timeout
	m.debug_sort("artist")
	await get_tree().process_frame
	var sliding := 0
	var fading := 0
	var max_off := 0.0
	var tweened := 0
	for c in m._box.get_children():
		if c is Control and c.visible and c.get_child_count() > 0:
			var inner2: Control = c.get_child(0)
			var off := absf(inner2.position.y - float(inner2.get_meta("base_y", 0.0)))
			if off > 1.0:
				sliding += 1
				max_off = maxf(max_off, off)
			elif inner2.modulate.a < 0.99:
				fading += 1
			if inner2.has_meta("flip_tween") and (inner2.get_meta("flip_tween") as Tween).is_valid():
				tweened += 1
	chk.call(sliding + fading > 0 and tweened <= 16, "曲が多いとき(%d 曲): 動かす行は画面の中の分だけ(滑る %d 行・現れる %d 行・動きを持つ行 %d)" % [m._songs.size(), sliding, fading, tweened])
	chk.call(max_off <= m._scroll.size.y + 100.0, "曲が多いとき: 滑る行の動く距離は画面の高さ以内(最大 %.0f px。画面 %.0f px)" % [max_off, m._scroll.size.y])
	await get_tree().create_timer(0.8).timeout
	m._songs.resize(n_real)   # 作り物を外す
	m._rebuild_song_cards(false)
	m.debug_sort("title")
	await get_tree().create_timer(0.5).timeout
	# 長さ順: 短い順に並ぶ(長さが分からない曲は、裏で集めて、集まったら並びに入る)。行の右に、長さが出る
	m.debug_sort("length")
	var t_len := Time.get_ticks_msec()
	while (SongArt.meta_pending() > 0 or m._charts_dirty) and Time.get_ticks_msec() - t_len < 30000:
		await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	m._apply_view()
	await get_tree().process_frame
	var lens_ok := true
	var prev_len := 0.0
	var order_v: Array = m.browser.view()
	for i in order_v:
		var ln: float = SongArt.length_of(str(m._songs[i].md5))
		if ln <= 0.0 or ln < prev_len:
			lens_ok = false
		prev_len = ln
	chk.call(lens_ok and order_v.size() == m._songs.size(), "長さ順: 短い順に並んでいる(%d 曲)" % order_v.size())
	chk.call(m._rows[order_v[0]].is_visible_in_tree(), "長さ順: 曲の行が出ている")
	m.debug_sort("title")
	await get_tree().create_timer(0.5).timeout
	# 難易度順: 譜面ごとの行が、Lv の低い順に並ぶ / 押すと、その曲のその難易度を選ぶ / 戻すと、曲の行が出る
	m.debug_sort("diff")
	var t_wait := Time.get_ticks_msec()
	while (SongArt.meta_pending() > 0 or m._charts_dirty) and Time.get_ticks_msec() - t_wait < 30000:   # 難易度を集め終わるまで(並びは、集めたぶんが ときどきまとめて加わる)
		await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	m._apply_view()
	await get_tree().process_frame
	var n_known := 0
	for i in range(m._songs.size()):
		n_known += SongArt.diffs_of(str(m._songs[i].md5)).size()
	chk.call(m._was_chart and m._chart_order.size() == n_known and n_known > 0, "難易度順: 譜面が 1 つずつ並ぶ(%d 譜面 / 分かっている難易度 %d)" % [m._chart_order.size(), n_known])
	var sorted_ok := true
	for k in range(1, m._chart_order.size()):
		if float(m._chart_order[k].lv) < float(m._chart_order[k - 1].lv):
			sorted_ok = false
	chk.call(sorted_ok, "難易度順: Lv の低い順に並んでいる")
	var shown_rows := 0
	for r in m._rows:
		if r.visible:
			shown_rows += 1
	chk.call(shown_rows == 0, "難易度順: 曲の行は出ていない")
	if m._chart_order.size() > 3:
		var pick: Dictionary = m._chart_order[m._chart_order.size() >> 1]
		if str(pick.key) == m._chart_sel:
			pick = m._chart_order[m._chart_order.size() >> 1 + 1]
		m._pick_chart(int(pick.s), str(pick.id), false)
		while m._job_pending:
			await get_tree().process_frame
		await get_tree().process_frame
		var picked_id: String = str(m._loader.difficulties[m._diff_sel].md5)
		chk.call(m._song_sel == int(pick.s) and picked_id == str(pick.id) and m._chart_sel == str(pick.key), "難易度順: 譜面を押すと、その曲のその難易度(%s)が選ばれる" % str(pick.name))
		# 同じ曲の別の難易度(← →)でも、選んでいる譜面の行が追いかける
		var cur_diff: int = m._diff_sel
		m._select_diff(cur_diff + 1 if cur_diff + 1 < m._ratings.size() else cur_diff - 1)
		await get_tree().process_frame
		chk.call(m._chart_sel == "%s|%s" % [m._songs[m._song_sel].md5, m._loader.difficulties[m._diff_sel].md5], "難易度順: 同じ曲の隣の難易度へ → 選んでいる譜面の行も移る")
	m.debug_sort("title")
	await get_tree().process_frame
	var shown_back := 0
	for r in m._rows:
		if r.visible:
			shown_back += 1
	chk.call(not m._was_chart and m._chart_holders.is_empty() and shown_back == m.browser.view().size(), "難易度順から戻す: 曲の行が出て、譜面の行は捨てられる(%d 曲)" % shown_back)
	await get_tree().create_timer(0.5).timeout
	Settings.restore(original)
	print("smoke-carousel: ","OK" if st.fails == 0 else "%d FAILED" % st.fails)
	get_tree().quit()


## 開発用: UI の操作ごとに、呼び出しにかかった時間と、そのあと 0.7 秒の間で一番長いフレームを測る(プチフリーズ探し)。-- [--ui lazer] --prof-ui
func _prof_ui() -> void:
	add_child(UiSfx.new())
	add_child(Juice.new())
	_setup_fade()
	var rows: Array = []
	var measure := func(label: String, act: Callable) -> void:
		var t0 := Time.get_ticks_usec()
		await act.call()
		var call_ms := (Time.get_ticks_usec() - t0) / 1000.0
		var worst := 0.0
		var last := Time.get_ticks_usec()
		var end := last + 700000
		while Time.get_ticks_usec() < end:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			worst = maxf(worst, (now - last) / 1000.0)
			last = now
		rows.append("%-28s call %7.1f ms   worst frame %7.1f ms" % [label, call_ms, worst])
	await get_tree().create_timer(0.5).timeout
	await measure.call("show_title", func(): show_title())
	await get_tree().create_timer(1.0).timeout
	await measure.call("title: howto open", func(): _current._activate(2))
	await measure.call("title: howto close", func(): _current._overlay.close_panel())
	await get_tree().create_timer(0.4).timeout
	await measure.call("title: howto open 2nd", func(): _current._activate(2))
	await measure.call("title: howto close 2nd", func(): _current._overlay.close_panel())
	await get_tree().create_timer(0.4).timeout
	await measure.call("title: quit open", func(): _current._activate(4))
	await measure.call("title: quit close", func(): _current._overlay._cancel())
	await get_tree().create_timer(0.4).timeout
	await measure.call("title: settings open", func(): open_settings(0))
	await measure.call("settings: page 2", func(): _settings_panel.show_section(2))
	await measure.call("settings close", func(): _settings_panel.close_panel())
	await get_tree().create_timer(0.4).timeout
	await measure.call("title: settings open 2nd", func(): open_settings(0))
	await measure.call("settings close 2nd", func(): _settings_panel.close_panel())
	await get_tree().create_timer(0.4).timeout
	await measure.call("show_menu", func(): show_menu())
	while _current._job_pending:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	await measure.call("menu: mods open", func(): _current.open_mods())
	await measure.call("menu: mods close", func(): _current._mod_panel.close_panel())
	await get_tree().create_timer(0.4).timeout
	await measure.call("menu: mods open 2nd", func(): _current.open_mods())
	await measure.call("menu: mods close 2nd", func(): _current._mod_panel.close_panel())
	await get_tree().create_timer(0.4).timeout
	for k in range(3):
		await measure.call("menu: next song %d" % k, func():
			var nxt: int = _current.browser.step_in_view(_current._song_sel, 1)
			_current._select_song(nxt))
		while _current._job_pending:
			await get_tree().process_frame
		await measure.call("  (after load %d)" % k, func(): pass)
	if _current.has_method("debug_sort"):
		await measure.call("menu: sort artist", func(): _current.debug_sort("artist"))
		await measure.call("menu: sort title", func(): _current.debug_sort("title"))
	await measure.call("menu -> title", func(): show_title())
	await get_tree().create_timer(1.0).timeout
	await measure.call("title -> menu 2nd", func(): show_menu())
	await get_tree().create_timer(1.0).timeout
	await measure.call("menu -> title 2nd", func(): show_title())
	for r in rows:
		print(r)
	get_tree().quit()


## 開発用: プレイ中のフレームの長さを実時間で測り、長いフレームの内訳(判定の刻み・弾の数・描画の準備・描画)を出す。垂直同期は切る。
## -- --prof-frames <osz のパス> [難易度名の一部] [秒] [MOD ...](既定: 練習。弾幕は v2)
func _prof_frames() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--prof-frames")
	var rest := Array(args.slice(i + 1))
	var loader := OszLoader.new()
	loader.open(rest[0])
	var bm = loader.difficulties[loader.difficulties.size() - 1]
	if rest.size() > 1:
		for d in loader.difficulties:
			if d.version.contains(rest[1]):
				bm = d
	var secs: float = float(rest[2]) if rest.size() > 2 else 60.0
	var mods: Array = rest.slice(3).filter(func(x): return not Mods.find(x).is_empty())
	if mods.is_empty():
		mods = ["practice"]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 320 if args.has("fps320") else 0   # fps320: 320Hz のモニターと同じ間隔で回す
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	start_game(loader, bm, {"mods": mods, "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
	var g = _current
	g.prof_on = true
	while not g._audio_started:
		await get_tree().process_frame
	for a in rest:   # from=秒: 曲の途中から(判定が追いつくまで待ってから測る) / hide=名前,...: 画面の部品を隠す(どれが重いかの切り分け)
		if str(a).begins_with("from="):
			g._audio.seek(float(str(a).trim_prefix("from=")) * g._rate)
			while g._now - g._sim_t > 0.05 or g._now < float(str(a).trim_prefix("from=")):
				await get_tree().process_frame
		elif str(a) == "noglow":   # 弾の光の層だけ隠す
			g.field.get_child(0).visible = false
		elif str(a).begins_with("hide="):
			for nm in str(a).trim_prefix("hide=").split(","):
				var nd = g.get(nm)
				if nd is CanvasItem:
					nd.visible = false
				else:
					print("hide: no CanvasItem ", nm)
	print("prof-frames: %s [%s] mods=%s" % [bm.title, bm.version, str(mods)])
	var frames: Array = []   # [間隔 ms, 前のフレームの prof, 描画(CPU) ms, GPU ms, 全ノードの処理 ms, 区切り]
	var marks := {"pre": 0, "post": 0}   # 描画の前後の時刻(処理 → 描画 → 表示待ち の区切り)
	RenderingServer.frame_pre_draw.connect(func(): marks.pre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func(): marks.post = Time.get_ticks_usec())
	var last := Time.get_ticks_usec()
	var t0 := last
	while (Time.get_ticks_usec() - t0) / 1000000.0 < secs and is_instance_valid(g) and _current == g and not g.sim.finished:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append([(now - last) / 1000.0, g.prof.duplicate(), RenderingServer.viewport_get_measured_render_time_cpu(vp), RenderingServer.viewport_get_measured_render_time_gpu(vp), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			[(marks.pre - last) / 1000.0, (marks.post - marks.pre) / 1000.0, (now - marks.post) / 1000.0]])
		last = now
		if frames[frames.size() - 1][0] > 15.0 and args.has("spike-shots"):   # 長いフレームの直後の画面(何が初めて出たかを見る)
			get_viewport().get_texture().get_image().save_png("user://spike_%.2f.png" % float(g.prof.get("now", 0.0)))
			last = Time.get_ticks_usec()
	var ms: Array = frames.map(func(f): return f[0])
	ms.sort()
	var med: float = ms[ms.size() / 2]
	print("frames=%d  median %.2f ms  p99 %.2f  p99.9 %.2f  max %.2f" % [ms.size(), med, ms[int(ms.size() * 0.99)], ms[int(ms.size() * 0.999)], ms[ms.size() - 1]])
	var lim := 4.7 if args.has("fps320") else maxf(med * 2.5, 6.0)
	print("frames over %.1f ms: %d" % [lim, ms.filter(func(x): return x > lim).size()])
	var shown := 0
	for k in range(frames.size()):
		var f: Array = frames[k]
		if f[0] > lim and shown < 60:
			shown += 1
			var p: Dictionary = f[1]
			print(("  %6.2f ms  t=%6.2f  bullets=%4d  steps=%3d  sim=%5.2f  refresh=%5.2f  proc=%5.2f  render_cpu=%5.2f" % [f[0], float(p.get("now", 0.0)), int(p.get("n", 0)), int(p.get("steps", 0)),
				p.get("sim", 0) / 1000.0, p.get("refresh", 0) / 1000.0, p.get("proc", 0) / 1000.0, float(f[2])]) + ("  gpu=%5.2f  all_process=%5.2f  warp=%d ts=%s halo=%.2f zone=%s" % [float(f[3]), float(f[4]), int(p.get("warp", 0)), str(p.get("ts", false)), float(p.get("halo", 0.0)), str(p.get("zone", ""))]) + ("  | to_draw=%.2f draw=%.2f after=%.2f" % f[5]))
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


## 開発用: 選曲画面の一覧を、ドラッグでスクロールできるか確かめる(左 = つかんだ分だけ / 右 = 速く)。-- --smoke-drag
## ドラッグしたときは曲を選ばず、動かさずにクリックしたときだけ選ぶ。
func _smoke_drag() -> void:
	var fails := 0
	show_menu()
	await get_tree().create_timer(0.5).timeout
	var m = _current
	while m._job_pending:
		await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout
	if m._songs.size() < 30:   # 曲が少ないとスクロールできないので、一覧だけ水増しする(ファイルは触らない)
		var base: Array = m._songs.duplicate()
		while m._songs.size() < 30:
			m._songs.append_array(base)
		m._rebuild_song_cards(false)
		await get_tree().create_timer(0.3).timeout
	var sc: ScrollContainer = m._song_scroll
	var mx: float = sc.get_v_scroll_bar().max_value - sc.get_v_scroll_bar().page
	var at := sc.get_global_rect().position + Vector2(150, 300)
	var send := func(ev: InputEvent): Input.parse_input_event(ev); await get_tree().process_frame
	var button := func(idx: int, down: bool, pos: Vector2) -> InputEventMouseButton:
		var e := InputEventMouseButton.new()
		e.button_index = idx
		e.pressed = down
		e.position = pos
		e.global_position = pos
		return e
	var motion := func(pos: Vector2) -> InputEventMouseMotion:
		var e := InputEventMouseMotion.new()
		e.position = pos
		e.global_position = pos
		return e
	for btn in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		m._song_smooth._target = 0.0
		m._song_smooth._pos = 0.0
		m._song_smooth._apply()
		await get_tree().process_frame
		var sel0: int = m._song_sel
		Input.warp_mouse(get_viewport().get_screen_transform() * at)
		await send.call(motion.call(at))
		await send.call(button.call(btn, true, at))
		for k in range(1, 7):
			await send.call(motion.call(at - Vector2(0, 5.0 * k)))   # 上へ 30px(一覧は下へ進む)
		await send.call(button.call(btn, false, at - Vector2(0, 30)))
		await get_tree().create_timer(0.5).timeout
		var moved: float = sc.scroll_vertical
		# しきい値(6px)を越えたのは 10px の時点。そこから動いた 20px ぶん(右は FAST_MIN 倍以上)。左は離したあと少し滑る(行き過ぎない)
		var mul: float = maxf(4.0, mx / (sc.size.y * 0.8))
		var expect := 20.0 if btn == MOUSE_BUTTON_LEFT else 20.0 * mul
		var ok: bool = moved >= expect - 2.0 and (btn == MOUSE_BUTTON_RIGHT or moved <= expect + 80.0) and m._song_sel == sel0
		print("[%s drag 30px] scroll %d (expect %d..%d, max %d)  song_sel %d -> %d: %s" % ["left" if btn == MOUSE_BUTTON_LEFT else "right", moved, int(expect), int(expect + 80.0), int(mx), sel0, m._song_sel, "OK" if ok else "FAIL"])
		fails += 0 if ok else 1
	# 動かさずにクリック: その曲を選ぶ
	var want := -1
	var cp := Vector2.ZERO
	for i in range(m._song_cards.size()):   # 見えているカードのうち、選んでいないもの
		var c: Vector2 = (m._song_cards[i] as Control).get_global_rect().get_center()
		if i != m._song_sel and sc.get_global_rect().grow(-30.0).has_point(c):
			want = i
			cp = c
			break
	await send.call(motion.call(cp))
	await send.call(button.call(MOUSE_BUTTON_LEFT, true, cp))
	await send.call(button.call(MOUSE_BUTTON_LEFT, false, cp))
	var ok2: bool = want < 0 or m._song_sel == want
	print("[click] song_sel=%d (expect %d): %s" % [m._song_sel, want, "OK" if ok2 else "FAIL"])
	fails += 0 if ok2 else 1
	print("smoke-drag: ", "OK" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()


## 開発用: 休憩のカウントダウンの動き(現れる・残り 3 秒からの合図・終わり)を、実際のプレイで確かめる。-- --smoke-break [--shots <接頭辞>]
## 曲の途中に、4.5 秒の休憩を作って、弾を一掃した状態にする。
func _smoke_break() -> void:
	var args := OS.get_cmdline_user_args()
	var si := args.find("--shots")
	var shots: String = str(args[si + 1]) if si >= 0 and args.size() > si + 1 else ""
	var loader := OszLoader.new()
	loader.open(_dev_osz("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz"))
	start_game(loader, loader.difficulties[0], {"mods": ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
	var g = _current
	await get_tree().create_timer(2.5).timeout
	var t0: float = g._now
	g.sim.breaks.append([t0, t0 + 4.5])
	g.sim.break_clear_t = t0
	g.sim.break_end_t = t0 + 4.5
	var fails := 0
	var secs: Array = []
	var start_ms := Time.get_ticks_msec()
	var k := 0
	for at in [0.15, 0.4, 1.0, 1.6, 2.6, 3.6, 4.65, 5.2]:
		while (Time.get_ticks_msec() - start_ms) / 1000.0 < at:
			await get_tree().process_frame
		secs.append(g._break_sec)
		print("  +%.2fs  shown=%d  left=%.2f  ring=%.2f  alpha=%.2f  pop=%.2f" % [at, g._break_sec, g._break_left, g._break_frac * (1.0 - pow(1.0 - g._break_in, 3.0)), g._break_a, g._break_pop])
		if shots != "":
			get_viewport().get_texture().get_image().save_png("%s_%d.png" % [shots, k])
		k += 1
	var ok: bool = secs[0] == 5 and secs[3] == 3 and secs[5] == 1 and secs[7] == -1 and g._break_a < 0.5
	print("smoke-break: ", "OK" if ok else "FAIL %s" % str(secs))
	get_tree().quit()


## 開発用: プレイ中の R 長押しでリトライできるか確かめる。-- --smoke-retryhold
## 短く押しただけではリトライしない / 長押しでリトライ / 押したまま新しいプレイが始まっても、離すまでは次のリトライをしない。
func _smoke_retryhold() -> void:
	var loader := OszLoader.new()
	loader.open(_dev_osz("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz"))
	var bm = loader.difficulties[0]
	start_game(loader, bm, {"mods": ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
	await get_tree().create_timer(1.0).timeout
	var key := func(down: bool):
		var e := InputEventKey.new()
		e.keycode = KEY_R
		e.physical_keycode = KEY_R
		e.pressed = down
		Input.parse_input_event(e)
	var fails := 0
	var g0 = _current
	key.call(true)
	await get_tree().create_timer(0.3).timeout
	key.call(false)
	await get_tree().create_timer(0.3).timeout
	var ok1: bool = _current == g0
	print("[tap 0.3s] no retry: %s" % ("OK" if ok1 else "FAIL"))
	key.call(true)
	await get_tree().create_timer(0.9).timeout
	var g1 = _current
	var ok2: bool = g1 != g0 and is_instance_valid(g1) and "sim" in g1   # 新しいプレイ画面になった
	print("[hold 0.9s] retried: %s" % ("OK" if ok2 else "FAIL"))
	await get_tree().create_timer(1.2).timeout   # 押したまま: 新しいプレイは、離すまでリトライしない
	var ok3: bool = _current == g1
	print("[keep holding 1.2s] no second retry: %s" % ("OK" if ok3 else "FAIL"))
	key.call(false)
	fails += (0 if ok1 else 1) + (0 if ok2 else 1) + (0 if ok3 else 1)
	print("smoke-retryhold: ", "OK" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()


## 開発用: プレイ中にウィンドウのフォーカスが外れたら、自動でポーズになるか確かめる。-- --smoke-focus
func _smoke_focus() -> void:
	DisplayServer.window_move_to_foreground()   # 起動したウィンドウが裏にあると、本物のフォーカス外れでポーズになってしまう
	await get_tree().create_timer(0.5).timeout
	GameScreen.focus_pause_in_dev = true
	var loader := OszLoader.new()
	loader.open(_dev_osz("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz"))
	var bm = loader.difficulties[0]
	start_game(loader, bm, {"mods": ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
	await get_tree().create_timer(0.5).timeout
	var g = _current
	while not g._audio_started:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var fails := 0
	var ok0: bool = not g.is_paused()
	print("[playing] not paused: %s" % ("OK" if ok0 else "FAIL"))
	g.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await get_tree().process_frame
	var ok1: bool = g.is_paused() and g._pause_layer.visible and g._audio.stream_paused
	print("[focus out] paused (menu shown, music paused): %s" % ("OK" if ok1 else "FAIL"))
	g.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await get_tree().process_frame
	var ok2: bool = g.is_paused()
	print("[focus in] stays paused: %s" % ("OK" if ok2 else "FAIL"))
	fails += (0 if ok0 else 1) + (0 if ok1 else 1) + (0 if ok2 else 1)
	print("smoke-focus: ", "OK" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()


## 開発用: ゲームオーバーで、弾の動きが曲のテープストップと同じように遅くなって止まるか確かめる。-- --smoke-tapestop
func _smoke_tapestop() -> void:
	var loader := OszLoader.new()
	loader.open(_dev_osz("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz"))
	var bm = loader.difficulties[loader.difficulties.size() - 1]
	start_game(loader, bm, {"mods": [], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
	var g = _current
	await get_tree().create_timer(1.0).timeout
	if g._can_skip():
		g._request_skip()
	while g.field.count < 20:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	g.sim.gauge = 0.0   # 次の判定で、ゲームオーバーになる
	while not g._dead:
		await get_tree().process_frame
	var fails := 0
	var prev: Vector2 = g.field.pos[0]
	var prev_now: float = g._now
	var speeds: Array = []
	for k in range(7):   # 0.25 秒ごとに、弾の動いた距離と、ゲームの時間の進みを測る(2 秒で結果画面へ移るので、その前まで)
		await get_tree().create_timer(0.25).timeout
		var p: Vector2 = g.field.pos[0] if g.field.count > 0 else prev
		speeds.append([p.distance_to(prev) / 0.25, (g._now - prev_now) / 0.25, g._audio.pitch_scale if g._audio.playing else 0.0])
		print("  +%.2fs  bullet %.1f px/s  game time x%.2f  pitch %.2f" % [0.25 * (k + 1), speeds[k][0], speeds[k][1], speeds[k][2]])
		prev = p
		prev_now = g._now
	var slowing: bool = speeds[0][0] > 1.0 and speeds[2][0] < speeds[0][0] and speeds[5][1] < 0.2
	var stopped: bool = speeds[6][0] < 1.0 and speeds[6][1] < 0.01
	print("smoke-tapestop: bullets keep moving then slow down: %s / stopped after the tape stop: %s" % ["OK" if slowing else "FAIL", "OK" if stopped else "FAIL"])
	fails += (0 if slowing else 1) + (0 if stopped else 1)
	print("smoke-tapestop: ", "OK" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()


## 開発用: プレイ → 保存 → リプレイの再生(停止・倍速・シーク・軌道・キー操作・閉じる)を、実時間で通して確認する。-- --smoke-replay [--shots <接頭辞>]
func _smoke_replay() -> void:
	var args := OS.get_cmdline_user_args()
	var si := args.find("--shots")
	var shots: String = str(args[si + 1]) if si >= 0 and args.size() > si + 1 else ""
	Replay.dir = "user://replays_smoke"
	Replay.force_record = true
	for n in DirAccess.get_files_at(Replay.dir):
		DirAccess.remove_absolute(Replay.dir.path_join(n))
	var fails := [0]
	var chk := func(ok: bool, msg: String):
		print(("ok:   " if ok else "FAIL: ") + msg)
		if not ok:
			fails[0] += 1
	var shot := func(tag: String):
		if shots != "":
			get_viewport().get_texture().get_image().save_png("%s_%s.png" % [shots, tag])
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[0]
	var key := func(code: Key):
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = true
		Input.parse_input_event(e)
		await get_tree().process_frame
		await get_tree().process_frame
	# 1) 実際にプレイして(キーボードのボットで動き回る)、記録を保存する
	start_game(loader, bm, {"mods": ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
	var g = _current
	var tk := [0.0]
	g.debug_move = func() -> Vector2:
		tk[0] += 1.0
		return Vector2.from_angle(sin(tk[0] * 0.02) * 3.0 + tk[0] * 0.01)
	var first_fire: float = g.sim.first_fire_time
	await get_tree().create_timer(0.8).timeout
	g._skip_intro()
	await get_tree().create_timer(9.0).timeout
	chk.call(g._rec != null and g._rec.frames.size() > 600 * Replay.STRIDE / 2, "プレイ中に入力が記録される(%d フレーム)" % (g._rec.frames.size() / Replay.STRIDE if g._rec != null else 0))
	var st: Dictionary = g._stats()
	g._save_replay(st)
	Replay.flush()
	var name := str(st.get("replay", ""))
	chk.call(name != "" and FileAccess.file_exists(Replay.dir.path_join(name)), "終わりに保存される: %s" % name)
	# 2) リプレイを開く
	var closed := [false]
	show_replay(name, func(): closed[0] = true)
	await get_tree().create_timer(0.8).timeout
	var r = _current
	chk.call(r != g and r.get("_rp") != null and r.kind == "game", "リプレイ画面が開く(終わりの時刻 %.1f 秒)" % (r._rp.end_time() if r.get("_rp") != null else 0.0))
	var t1: float = r._rt
	await get_tree().create_timer(1.0).timeout
	chk.call(r._rt > t1 + 0.7 and r._rp_playing, "再生が進む(%.2f → %.2f)" % [t1, r._rt])
	chk.call(r.sim.player_pos.distance_to(Vector2(480, 612)) > 1.0, "自機が記録どおり動いている")
	shot.call("play")
	var drift_max := 0.0
	for _i in range(26):
		await get_tree().create_timer(0.1).timeout
		if r._audio.playing and _i >= 8:   # 画面写真の保存で一瞬止まるので、少し待ってから測る(止まったぶんは、ゆっくり音に追いつく)
			var song_t: float = r._rt - (float(r.sim.loop_index(r._rt)) * r.sim.loop_len if r.sim.loop_len > 0.0 else 0.0)
			var apos: float = r._audio.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
			drift_max = maxf(drift_max, absf(apos - song_t))
	chk.call(r._audio.playing and drift_max < 0.04, "再生の曲と、リプレイの時計が、ずれない(最大 %.3f 秒)" % drift_max)
	# 3) 停止 / 再開(Space)
	await key.call(KEY_SPACE)
	var tp: float = r._rt
	await get_tree().create_timer(0.5).timeout
	chk.call(not r._rp_playing and absf(r._rt - tp) < 0.001, "Space で止まる")
	await key.call(KEY_SPACE)
	await get_tree().create_timer(0.4).timeout
	chk.call(r._rp_playing and r._rt > tp + 0.2, "もう一度 Space で再開")
	# 4) 倍速
	r._replay_set_speed(4.0)
	var ts: float = r._rt
	await get_tree().create_timer(0.5).timeout
	chk.call(r._rt - ts > 1.5, "4 倍速で進む(0.5 秒で %.2f 秒)" % (r._rt - ts))
	# 遅い再生: 記録のフレームの途中のステップでも進むので、なめらかに動く(1 フレームの記録を 4 回に分けて見せる)
	r._replay_set_speed(0.25)
	var tsl: float = r._rt
	var mids := [0]
	var last_pos: Vector2 = r.sim.player_pos
	var moved_frames := [0]
	for _i in range(24):
		await get_tree().process_frame
		if r._rp.sub > 0:
			mids[0] += 1
		if r.sim.player_pos != last_pos:
			moved_frames[0] += 1
			last_pos = r.sim.player_pos
	chk.call(r._rt > tsl + 0.01 and mids[0] >= 8 and moved_frames[0] >= 18, "0.25 倍でも、ほぼ毎フレーム自機が動く(途中のステップで止まった %d / 24 回、動いた %d / 24 回)" % [mids[0], moved_frames[0]])
	r._replay_set_speed(1.0)
	r._replay_set_speed(1.0)
	await key.call(KEY_BRACKETLEFT)
	chk.call(is_equal_approx(r._rp_speed, 0.5), "[ キーで速さが下がる(%.2f)" % r._rp_speed)
	r._replay_set_speed(1.0)
	# 5) シーク(体力の記録・弾の状態も飛ぶ): 後ろ → 前 → 後ろ
	r._replay_set_playing(false)
	var seek_ok := true
	var base: float = first_fire - 1.5   # スキップで飛ばした先(記録のある区間の始まり)
	for target in [base + 1.5, base + 0.5, base + 7.0]:
		var a: float = Time.get_ticks_msec()
		r._replay_seek(target)
		var took: float = Time.get_ticks_msec() - a
		seek_ok = seek_ok and absf(r._rt - target) < 0.05
		print("   seek %.1f → %.3f (%d ms), bullets=%d gauge=%.3f" % [target, r._rt, int(took), r.field.count, r.sim.gauge])
	chk.call(seek_ok, "任意の秒へ飛べる")
	# 6) 軌道(T で 切 → 過去 → 過去+未来)
	r._replay_seek(base + 3.0)
	var m0: int = r.replay_trail_mode
	await key.call(KEY_T)
	await key.call(KEY_T)
	chk.call(r.replay_trail_mode == (m0 + 2) % 3 and r._view_under.trail_mode == r.replay_trail_mode, "T キーで軌道の表示が切り替わる(%d → %d)" % [m0, r.replay_trail_mode])
	r.replay_trail_mode = 2
	r._replay_apply_trail()
	await key.call(KEY_Y)
	chk.call(r.replay_trail_sec != 3.0, "Y キーで軌道の長さが変わる(%.0f 秒)" % r.replay_trail_sec)
	r.replay_trail_sec = 3.0
	r._replay_apply_trail()
	await get_tree().process_frame
	shot.call("trail")
	await key.call(KEY_H)
	await get_tree().create_timer(0.8).timeout
	chk.call(not r._rp_bar._panel.visible and r._rp_bar.pinned_hidden and is_equal_approx(r.scale.x, 1.0), "H キーで操作パネルが隠れ、プレイ画面が元の大きさに戻る")
	shot.call("trail_nobar")
	await key.call(KEY_H)
	await get_tree().create_timer(0.3).timeout
	chk.call(r._rp_bar._panel.visible and r.scale.x < 0.9, "もう一度 H で出て、プレイ画面が縮む")
	# 7) 操作パネル(ボタン)
	chk.call(r._rp_bar != null and r._rp_bar._panel.visible, "操作パネルが出ている")
	r._rp_bar.seek_requested.emit(base + 2.0)
	chk.call(absf(r._rt - (base + 2.0)) < 0.05, "体力グラフのクリック(seek_requested)で飛ぶ")
	r._rp_bar.restart_pressed.emit()
	await get_tree().create_timer(0.3).timeout
	chk.call(r._rt < base + 1.0 and r._rp_playing, "「最初へ」で、最初から再生される(イントロの空白は飛ぶ)")
	# 7b) 画面の構成・区間・OSD・操作の一覧・書き出しの選択・ドラッグ中の移動
	chk.call(is_equal_approx(r.scale.x, r.ReplayBar.DOCK_SCALE) and r._view_l < 0.0 and r._rp_state_l != null, "パネルのぶん、プレイ画面が縮んでいる(%.3f)。左のパネルに状態が出る(%s)" % [r.scale.x, r._rp_state_l.text if r._rp_state_l != null else ""])
	r._replay_seek(base + 2.0)
	await key.call(KEY_I)
	r._replay_seek(base + 4.0)
	await key.call(KEY_O)
	chk.call(is_equal_approx(r.replay_range_a, base + 2.0) and r._rp_range_ok(), "I / O で区間を決める(%.2f–%.2f)" % [r.replay_range_a, r.replay_range_b])
	chk.call(r._rp_bar._osd.modulate.a > 0.5, "操作の反応(OSD)が出る('%s')" % r._rp_bar._osd.text)
	r._replay_seek(base + 3.0)
	r._replay_set_playing(true)
	await get_tree().create_timer(3.6).timeout
	chk.call(r._rt >= base + 2.0 - 0.05 and r._rt <= base + 4.0 + 0.3 and r._rp_playing, "区間は繰り返される(3.6 秒後 %.2f)" % r._rt)
	chk.call(not r._rp_loop_key.is_empty(), "始点の状態を取っておき、繰り返しで一瞬で戻る")
	await key.call(KEY_X)
	chk.call(r.replay_range_a < 0.0 and not r._rp_range_ok(), "X で区間を解除")
	r._replay_set_playing(false)
	# ドラッグ中は止めて、飛んで、離したら続ける
	r._replay_set_playing(true)
	r._rp_bar.scrub_started.emit()
	r._rp_bar.seek_requested.emit(base + 5.0)
	chk.call(not r._rp_playing and absf(r._rt - (base + 5.0)) < 0.05, "グラフのドラッグ中は止まり、その秒へ飛ぶ")
	r._rp_bar.scrub_ended.emit()
	chk.call(r._rp_playing, "離したら、また再生する")
	r._replay_set_playing(false)
	# 操作の一覧(? / F1)・Esc は、まず一覧を閉じる
	await key.call(KEY_F1)
	chk.call(r._rp_bar.help_visible(), "F1 で操作の一覧が出る")
	await key.call(KEY_ESCAPE)
	chk.call(not r._rp_bar.help_visible() and not closed[0], "Esc は、まず一覧を閉じる(リプレイは閉じない)")
	# 書き出しの大きさの選択
	var got_opts := [{}]
	r._rp_bar.export_requested.connect(func(o: Dictionary): got_opts[0] = o)
	r._rp_bar._on_export_pressed()
	chk.call(r._rp_bar._exp_pop.visible, "「動画出力」で、大きさの選択が出る")
	r._rp_bar._exp_pop.find_children("*", "Button", true, false)[1].pressed.emit()
	chk.call(int(got_opts[0].get("w", 0)) == 1920 and int(got_opts[0].get("fps", 0)) == 60 and not r._rp_bar._exp_pop.visible, "1920×1080 を選ぶと、その指定で書き出しを頼む")
	# 画面のクリックで 再生 / 停止
	var was: bool = r._rp_playing
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(640, 300)
	r._unhandled_input(click)
	chk.call(r._rp_playing != was, "画面をクリックすると、再生 / 停止が切り替わる")
	r._replay_set_playing(false)
	# 8) 最後まで再生して止まる
	r._replay_seek(r._rp.end_time() - 0.5)
	r._replay_set_playing(true)
	await get_tree().create_timer(1.2).timeout
	chk.call(r._rp.at_end() and not r._rp_playing, "最後に着くと止まる")
	chk.call(r._rp_verified and r._rp_bar._warn_l == null, "最後まで流した結果は記録と合っていて、注意は出ない")
	await key.call(KEY_SPACE)
	await get_tree().create_timer(0.3).timeout
	chk.call(r._rp_playing and r._rt < base + 2.0, "最後で Space を押すと、最初から")
	# 9) 閉じる
	await key.call(KEY_ESCAPE)
	await get_tree().create_timer(0.3).timeout
	chk.call(closed[0], "Esc で閉じて、元の画面へ戻る")
	# 10) ゲームオーバーしたプレイ: 自動で保存 → リザルトにリプレイのボタン → 再生(終わりでゲームオーバー演出・前へ飛ぶと元に戻る)
	var hard = loader.difficulties[loader.difficulties.size() - 1]
	start_game(loader, hard, {"mods": ["hell", "storm"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
	var g2 = _current
	var tk2 := [0.0]
	g2.debug_move = func() -> Vector2:
		tk2[0] += 1.0
		return Vector2.from_angle(sin(tk2[0] * 0.013) * 3.0 + tk2[0] * 0.007)
	await get_tree().create_timer(0.8).timeout
	g2._skip_intro()
	var waited := 0.0
	while _kind != "result" and waited < 45.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	chk.call(_kind == "result", "ゲームオーバーでリザルトへ移る(%.1f 秒)" % waited)
	await get_tree().create_timer(3.0).timeout
	shot.call("result")
	var res = _current
	var rname := ""
	var files: Array = Array(DirAccess.get_files_at(Replay.dir))
	files.sort()
	rname = str(files[files.size() - 1]) if not files.is_empty() else ""
	Replay.flush()
	var d2 := Replay.load_file(rname)
	chk.call(not d2.is_empty() and bool(d2.stats.failed), "失敗したプレイも保存される(%s)" % rname)
	chk.call(res.has_signal("replay_requested") and str(res.stats.get("replay", "")) == rname, "リザルトの stats にリプレイのファイル名が入り、ボタンが出る")
	var closed2 := [false]
	res.replay_requested.emit()
	await get_tree().create_timer(1.0).timeout
	var r2 = _current
	chk.call(r2 != res and r2.get("_rp") != null and r2.sim.failed == false, "リザルトの「リプレイ」でリプレイが開く")
	chk.call(r2._rp_hits.size() > 0 and r2._rp_state_l != null, "被弾の記録が読める(%d 回)。ゲームオーバーのリプレイにも REPLAY の表示" % r2._rp_hits.size())
	r2._replay_seek(r2._rp.start_time())
	r2._replay_jump_hit(1)
	var h0: float = float(r2._rp_hits[0])
	chk.call(absf(r2._rt - maxf(h0 - 1.5, r2._rp.start_time())) < 0.05, "「次の被弾」で、最初の被弾の少し前へ飛ぶ(%.2f / 被弾 %.2f)" % [r2._rt, h0])
	r2._replay_seek(r2._rp.end_time() - 0.2)
	var rt_before: float = r2._rt
	r2._replay_jump_hit(-1)
	chk.call(r2._rt < rt_before - 0.3 and r2._rt <= float(r2._rp_hits[r2._rp_hits.size() - 1]) - 1.5 + 0.05, "「前の被弾」で、最後の被弾の少し前へ飛ぶ(%.2f)" % r2._rt)
	chk.call(not Replay.verify(r2.sim, {"hits": 999, "graze": 0, "score": 0.0}), "記録の結果と違えば、ずれとして見つかる")
	r2.replay_trail_mode = 2
	r2.replay_trail_sec = 5.0
	r2._replay_apply_trail()
	r2._replay_seek(maxf(h0 - 0.5, r2._rp.start_time()))
	await get_tree().process_frame
	await get_tree().process_frame
	shot.call("hit")
	r2.replay_trail_mode = 1
	r2.replay_trail_sec = 3.0
	r2._replay_apply_trail()
	r2._replay_seek(r2._rp.end_time())
	await get_tree().create_timer(1.6).timeout
	chk.call(r2.sim.failed and r2._dead, "最後まで飛ぶと、ゲームオーバーの演出になる")
	shot.call("dead")
	var tdead: float = r2._rp.end_time()
	r2._replay_seek(tdead - 6.0)
	await get_tree().create_timer(0.3).timeout
	chk.call(not r2._dead and not r2.sim.failed and r2.field.modulate.a == 1.0 and not r2._view_over.dead, "前へ飛ぶと、ゲームオーバーの演出が元に戻る")
	r2._replay_set_playing(true)
	await get_tree().create_timer(7.0).timeout
	chk.call(r2.sim.failed and r2._dead, "続きを再生すると、また最後でゲームオーバーになる")
	r2._replay_close()
	await get_tree().create_timer(0.3).timeout
	chk.call(_kind == "result", "閉じるとリザルトへ戻る")
	# 11) 撃破 MOD(弾幕が周回で伸びる・ボスの状態も戻る)
	start_game(loader, bm, {"mods": ["boss", "practice"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
	var g3 = _current
	var tk3 := [0.0]
	g3.debug_move = func() -> Vector2:
		tk3[0] += 1.0
		return Vector2.from_angle(sin(tk3[0] * 0.02) * 3.0 + tk3[0] * 0.01)
	var ff3: float = g3.sim.first_fire_time
	await get_tree().create_timer(0.8).timeout
	g3._skip_intro()
	await get_tree().create_timer(10.0).timeout
	var st3: Dictionary = g3._stats()
	g3._save_replay(st3)
	Replay.flush()
	var closed3 := [false]
	show_replay(str(st3.get("replay", "")), func(): closed3[0] = true)
	await get_tree().create_timer(0.8).timeout
	var r3 = _current
	chk.call(r3.get("_rp") != null and r3.sim.boss != null, "撃破 MOD のリプレイが開く")
	var hp_marks := []
	for tm in [0.4, 0.8]:
		r3._replay_seek(r3._rp.start_time() + (r3._rp.end_time() - r3._rp.start_time()) * tm)
		hp_marks.append(r3.sim.boss.hp)
	r3._replay_seek(r3._rp.start_time() + (r3._rp.end_time() - r3._rp.start_time()) * 0.4)
	chk.call(is_equal_approx(r3.sim.boss.hp, hp_marks[0]), "撃破: 同じ時刻へ戻すと、ボスの状態も同じ(HP %.1f)" % r3.sim.boss.hp)
	shot.call("boss")
	r3._replay_close()
	await get_tree().create_timer(0.3).timeout
	# 12) 動画出力(別のプロセスが、Movie Maker で書き出す。ffmpeg があれば mp4 へ変換する)
	if args.has("--export"):
		show_replay(name, func(): pass)
		await get_tree().create_timer(0.8).timeout
		var r4 = _current
		_replay_export(name, r4.replay_data, {"w": 1280, "h": 720, "fps": 30, "trail_mode": 1, "trail_sec": 3.0, "a": base + 1.0, "b": base + 4.0}, r4)
		chk.call(not _export.is_empty() and OS.is_process_running(int(_export.pid)), "動画出力を押すと、子プロセスが始まる")
		await get_tree().create_timer(1.5).timeout
		var shown: String = r4._rp_bar._status_l.text
		chk.call(shown.contains("書き出し中") and r4._rp_bar._export_btn.text == "書き出し中止", "操作パネルに、進み具合と「書き出し中止」が出る('%s')" % shown)
		var wait_s := 0.0
		while not _export.is_empty() and wait_s < 120.0:
			await get_tree().create_timer(1.0).timeout
			wait_s += 1.0
		print("   export: ", _export_last, " (", int(wait_s), " 秒)")
		chk.call(_export.is_empty() and _export_last.begins_with("動画を書き出しました"), "書き出しが終わる")
		var out_path := _export_last.substr(_export_last.find(": ") + 2).get_slice("(", 0)
		chk.call(FileAccess.file_exists(out_path), "ファイルができている: %s" % out_path)
		if FileAccess.file_exists(out_path):
			var pr := []
			OS.execute("ffprobe", ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height,r_frame_rate:format=duration", "-of", "default=nw=1", out_path], pr)
			var info := str(pr[0]) if not pr.is_empty() else ""
			print("   ffprobe: ", info.replace("\n", " "))
			var dur := 0.0
			for line in info.split("\n"):
				if str(line).begins_with("duration="):
					dur = str(line).substr(9).to_float()
			chk.call(info.contains("width=1280") and info.contains("r_frame_rate=30/1") and dur > 2.6 and dur < 4.6, "区間だけ(3 秒 + 余韻)・1280×720・30fps で書き出される(長さ %.2f 秒)" % dur)
			DirAccess.remove_absolute(out_path)
		chk.call(r4._rp_bar._export_btn.text == "動画出力" and r4._rp_bar._folder_btn.visible and r4._rp_bar._status_l.text.begins_with("動画を書き出しました"), "終わると、パネルに結果と「出力先を開く」が出る")
	# 13) リプレイの一覧(タイトルの「リプレイ」から開く。再生・保存・削除・絞り込み)
	show_title()
	await get_tree().create_timer(1.2).timeout
	var tt = _current
	chk.call(tt.kind == "title" and tt.has_signal("replays_requested"), "タイトルに「リプレイ」の項目がある")
	tt._activate(2)
	await get_tree().create_timer(0.8).timeout
	var lp = tt._overlay
	var all_n: int = Replay.list().size()
	chk.call(lp != null and lp.has_signal("replay_requested") and lp._items.size() == all_n and lp._cards.size() == all_n and all_n >= 3, "「リプレイ」で一覧が開く(%d 件)" % all_n)
	shot.call("list")
	var first_name := str(lp._shown[0].name)
	lp._toggle_keep(0)
	chk.call(Replay.kept_names().has(first_name), "「保存」すると、保存済みになる")
	lp._filter = 3
	lp._rebuild()
	chk.call(lp._shown.size() == 1 and str(lp._shown[0].name) == first_name, "「保存済み」で絞り込める")
	lp._filter = 2
	lp._rebuild()
	var only_failed := true
	for m in lp._shown:
		only_failed = only_failed and bool(m.failed)
	chk.call(not lp._shown.is_empty() and only_failed, "「ゲームオーバー」で絞り込める(%d 件)" % lp._shown.size())
	lp._filter = 0
	lp._rebuild()
	# 自動の整理は、保存済みのものを消さず、件数にも入れない
	Replay.prune(Records.replay_names(), 0)
	chk.call(FileAccess.file_exists(Replay.dir.path_join(first_name)), "保存済みは、自動の整理で消えない")
	var del_idx: int = lp._shown.size() - 1
	var del_name := str(lp._shown[del_idx].name)
	lp._delete(del_idx)
	chk.call(FileAccess.file_exists(Replay.dir.path_join(del_name)) and lp._del_name == del_name, "「削除」を 1 度押しただけでは、消えない(確認待ち)")
	lp._delete(del_idx)
	chk.call(not FileAccess.file_exists(Replay.dir.path_join(del_name)) and lp._items.size() == all_n - 1, "もう一度押すと、消える")
	lp._play(0)   # 一覧の先頭(いま「保存」したもの)を再生する
	await get_tree().create_timer(1.0).timeout
	var rl = _current
	chk.call(rl != tt and rl.kind == "game" and rl.get("_rp") != null and str(rl.replay_data.get("md5", "")) == str(Replay.load_file(first_name).get("md5", "x")), "一覧から選ぶと、そのリプレイが再生される")
	rl._replay_close()
	await get_tree().create_timer(2.0).timeout
	var tt2 = _current
	chk.call(tt2.kind == "title" and tt2._overlay != null and tt2._overlay.has_signal("replay_requested"), "リプレイを閉じると、一覧に戻る")
	tt2._overlay.close_panel()
	await get_tree().create_timer(0.6).timeout
	chk.call(tt2._overlay == null, "一覧を閉じると、タイトルへ戻る")
	Replay.set_kept(first_name, false)
	print("smoke-replay: ", "OK" if fails[0] == 0 else "%d FAILED" % fails[0])
	get_tree().quit(fails[0])


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
	# その間、自機はマウスの位置へ動き(カーソルの代わり)、アリーナの中では独自カーソルを出さない。画面写真: --shots <接頭辞>
	var args := OS.get_cmdline_user_args()
	var si := args.find("--shots")
	var shots: String = str(args[si + 1]) if si >= 0 and args.size() > si + 1 else ""
	var fails := 0
	var cur := CursorOverlay.new()
	add_child(cur)
	cur._inside = true
	cur._focused = true
	start_game(loader, bm, {"mods": ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "mouse", "sfx_volume": 0})
	var gm = _current
	await get_tree().create_timer(1.6).timeout
	var ok1: bool = gm._skip_btn.visible and Input.mouse_mode == Input.MOUSE_MODE_HIDDEN
	for spot in [["in", Vector2(500, 300)], ["button", gm._skip_btn.get_rect().get_center()], ["out", Vector2(60, 300)]]:
		var at: Vector2 = spot[1]
		Input.warp_mouse(get_viewport().get_screen_transform() * at)
		var mv := InputEventMouseMotion.new()
		mv.position = at
		mv.global_position = at
		Input.parse_input_event(mv)
		for k in range(6):
			await get_tree().process_frame
		var ship: Vector2 = gm.ARENA_POS + gm.sim.player_pos
		var inside: bool = spot[0] != "out"
		var ok: bool = (ship.distance_to(at) < 1.0) if inside else (absf(ship.y - at.y) < 1.0 and ship.x > at.x)
		ok = ok and cur._draw.visible != inside
		print("[mouse %s] cursor at %s ship at %s cursor drawn=%s: %s" % [spot[0], str(at), str(ship), str(cur._draw.visible), "OK" if ok else "FAIL"])
		fails += 0 if ok else 1
		if shots != "":
			get_viewport().get_texture().get_image().save_png("%s_%s.png" % [shots, spot[0]])
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
	while Time.get_ticks_msec() - t0 < 20000:
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
	while Time.get_ticks_msec() - t0 < 20000:
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
## 開発用: 設定で UI の見た目を切り替えると、いまのタイトルが新しい見た目で作り直される(戻すと、また戻る)。-- --smoke-uiswitch
func _smoke_uiswitch() -> void:
	var original := Settings.load_all()
	var st := original.duplicate()
	st.ui_style = "classic"
	Settings.save_all(st)
	show_title()
	await get_tree().create_timer(1.0).timeout
	print("start:   %s (expect title_screen.gd)" % _current.get_script().resource_path.get_file())
	open_settings(2)
	await get_tree().create_timer(0.5).timeout
	_settings_dict.ui_style = "lazer"
	close_settings()
	await get_tree().create_timer(1.0).timeout
	print("lazer:   %s (expect lazer_title.gd)" % _current.get_script().resource_path.get_file())
	open_settings(2)
	await get_tree().create_timer(0.5).timeout
	_settings_dict.ui_style = "classic"
	close_settings()
	await get_tree().create_timer(1.0).timeout
	print("classic: %s (expect title_screen.gd)" % _current.get_script().resource_path.get_file())
	# クラシックのタイトルの「新しい UI で遊ぼう」: 出ている → 「試してみる」で lazer 風になり、次からは出ない
	var st2 := Settings.load_all()
	st2.ui_promo_hidden = false
	Settings.save_all(st2)
	show_title()
	await get_tree().create_timer(1.2).timeout
	var t = _current
	print("promo:   shown=%s (expect true)" % str(t._promo != null))
	t.ui_try_requested.emit("lazer")
	await get_tree().create_timer(1.2).timeout
	var st3 := Settings.load_all()
	print("tried:   %s ui_style=%s promo_hidden=%s (expect lazer_title.gd, lazer, true)" % [_current.get_script().resource_path.get_file(), st3.ui_style, str(st3.ui_promo_hidden)])
	st3.ui_style = "classic"
	Settings.save_all(st3)
	UiSets.current()
	show_title()
	await get_tree().create_timer(1.2).timeout
	print("back:    %s promo_shown=%s (expect title_screen.gd, false)" % [_current.get_script().resource_path.get_file(), str(_current._promo != null)])
	Settings.restore(original)
	get_tree().quit()


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
	while lf.reason == "-" and Time.get_ticks_msec() - t0 < 20000:
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
	chk.call((m.get("kind") == "multi") and m._page == "entry", "タイトルからマルチプレイの入口へ: %s / %s" % [m.get_script().resource_path.get_file(), m._page])
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
	chk.call((menu.get("kind") == "menu") and menu.pick_mode, "曲・MOD を選ぶ画面(選曲モード)")
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
	chk.call((m.get("kind") == "multi") and n.room.song.get("md5") == want_md5, "決定でロビーへ戻り、部屋に曲が設定される: %s" % str(n.room.song.get("title", "")))
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
	while not ((_current.get("kind") == "game") and _current._audio_started) and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	var g = _current
	chk.call((g.get("kind") == "game") and g._mp != null and g._audio_started, "プレイ画面が始まる(%d ms)" % (Time.get_ticks_msec() - t0))
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
	chk.call((_current.get("kind") == "title") and n.role == "", "退出するとタイトルへ戻り、部屋を出る")
	t0 = Time.get_ticks_msec()
	while ok.left == "-" and Time.get_ticks_msec() - t0 < 20000:
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
	# 選曲画面の曲の一覧の上では、ホイールは音量を変えない(曲が少なくてスクロールしないときも)
	await get_tree().create_timer(2.4).timeout
	show_menu()
	await get_tree().create_timer(1.0).timeout
	var list_at := Vector2(900, 400)
	if "_scroll" in _current:
		list_at = (_current._scroll as Control).get_global_rect().get_center()
	Input.warp_mouse(list_at)
	await get_tree().process_frame
	var before_v := Volume.master
	var e2 := InputEventMouseButton.new()
	e2.button_index = MOUSE_BUTTON_WHEEL_DOWN
	e2.pressed = true
	e2.position = list_at
	e2.global_position = list_at
	Input.parse_input_event(e2)
	await get_tree().process_frame
	await get_tree().process_frame
	chk.call(Volume.master == before_v and not overlay._shown, "曲の一覧の上のホイールは、音量を変えない(全体 %d → %d)" % [before_v, Volume.master])
	# 音量メーターが出ている間でも、音量の優先度は低い: 一覧の上・画面のどこでも、ホイールは曲の一覧に使う(メーターの上と Ctrl のときだけ音量)
	var wheel_at := func(at: Vector2):
		var e3 := InputEventMouseButton.new()
		e3.button_index = MOUSE_BUTTON_WHEEL_DOWN
		e3.pressed = true
		e3.position = at
		e3.global_position = at
		Input.warp_mouse(at)
		await get_tree().create_timer(0.15).timeout   # 実際のマウスの位置が、ビューポートに伝わるのを待つ
		Input.parse_input_event(e3)
		await get_tree().process_frame
		await get_tree().process_frame
	overlay._show_panel()
	await get_tree().process_frame
	await wheel_at.call(list_at)
	chk.call(Volume.master == before_v and overlay._shown, "メーターが出ていても、曲の一覧の上のホイールは音量を変えない(全体 %d → %d)" % [before_v, Volume.master])
	await wheel_at.call(Vector2(1000, 700))
	chk.call(Volume.master == before_v, "メーターが出ていても、画面のどこで回しても音量を変えない(一覧がスクロールする。全体 %d → %d)" % [before_v, Volume.master])
	await wheel_at.call(Vector2(640, 60))
	chk.call(Volume.master != before_v, "メーターの上のホイールは音量を変える(全体 %d → %d。メーター %s・マウス %s)" % [before_v, Volume.master, str(HudOverlay.meter_rect), str(get_viewport().get_mouse_position())])
	Input.warp_mouse(Vector2(1000, 700))   # マウスをメーターの上に残さない(次に動かしたとき、メーターが消えなくなる)
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
	chk.call((_current.get("kind") == "menu"), "こちらは選曲画面へ移る: %s" % _current.get_script().resource_path.get_file())
	var m = _current
	chk.call(m._song_sel >= 0 and m._songs[m._song_sel].path.contains("Soleily"), "開いた曲が選ばれている: %s" % (m._songs[m._song_sel].path.get_file() if m._song_sel >= 0 else "-"))
	# 別の曲を、ウィンドウへのドロップの代わりに直接開く(取り込み済みなので、そのまま使う)
	_on_open_osz("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	await get_tree().create_timer(1.5).timeout
	m = _current
	chk.call((m.get("kind") == "menu") and m._songs[m._song_sel].path.contains("Reol"), "続けて別の曲を開くと、その曲が選ばれる")
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
	chk.call(_current == g and (g.get("kind") == "game"), "プレイ中に開いても、画面は変わらない(通知だけ)")
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
	chk.call(updater.stage_exe != "" and FileAccess.file_exists(updater.stage_dir.path_join(updater.stage_exe)) and FileAccess.file_exists(updater.stage_dir.path_join("README.txt")), "アプリ本体(%s)と README.txt が取り出されている" % updater.stage_exe)
	print("smoke-update: ", "OK" if st.fails == 0 else "%d FAILED" % st.fails)
	if args.has("apply") and st.fails == 0:
		print("applying...")
		updater.apply_and_quit()
		return
	get_tree().quit()
