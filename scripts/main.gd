extends Node
## 画面遷移(メニュー → プレイ → リザルト)。開発用の確認(--smoke* / --shot* / --prof*)は、継承先の scripts/main_dev.gd にある(main.tscn が付けるのは、そちら)。

const P_GameScreen := "res://scripts/game/game_screen.gd"
const RESULT_IN_VIDEO := 7.0   # 動画の最後に撮る、リザルト画面の秒数
const P_NetScript := "res://scripts/net/net.gd"
const SongLibrary = preload("res://scripts/song_library.gd")
const P_OszLoader := "res://scripts/osu/osz_loader.gd"
const Settings = preload("res://scripts/settings.gd")
const UserDirMigrate = preload("res://scripts/user_dir_migrate.gd")
const FileAssoc = preload("res://scripts/file_assoc.gd")
const P_Mods := "res://scripts/mods.gd"
const P_Boss := "res://scripts/game/boss.gd"
const SfxBank = preload("res://scripts/sfx_bank.gd")
const P_HpGraph := "res://scripts/ui/hp_graph.gd"
const FpsOverlay = preload("res://scripts/ui/fps_overlay.gd")
const HitchLog = preload("res://scripts/hitch_log.gd")
const SongArt = preload("res://scripts/song_art.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiSets = preload("res://scripts/ui/ui_sets.gd")
const P_Records := "res://scripts/records.gd"
const P_Replay := "res://scripts/replay.gd"
const UiFx = preload("res://scripts/ui/ui_fx.gd")
const Volume = preload("res://scripts/volume.gd")
const NowPlaying = preload("res://scripts/ui/lazer/now_playing.gd")
const Playlist = preload("res://scripts/playlist.gd")
const Profile = preload("res://scripts/profile.gd")
const P_LazerPlayer := "res://scripts/ui/lazer/lazer_player.gd"
const P_LazerPlaylist := "res://scripts/ui/lazer/lazer_playlist.gd"
const P_LazerProfile := "res://scripts/ui/lazer/lazer_profile.gd"
const HudOverlay = preload("res://scripts/ui/hud_overlay.gd")
const Updater = preload("res://scripts/updater.gd")
const UPDATE_RECHECK_SEC := 1800.0   # 起動したままの間、新しいバージョンを確かめ直す間隔(GitHub の API は、1 時間に 60 回まで)
const UPDATE_TOAST_TIME := 7.0       # 新しいバージョンの知らせを出しておく秒数
const P_OszImport := "res://scripts/osz_import.gd"
const P_SongDownload := "res://scripts/song_download.gd"
const SongSources = preload("res://scripts/song_sources.gd")
const SingleInstance = preload("res://scripts/single_instance.gd")
const CursorOverlay = preload("res://scripts/ui/cursor_overlay.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const Juice = preload("res://scripts/ui/juice.gd")
const ScreenWipe = preload("res://scripts/ui/screen_wipe.gd")
const SurvivalRun = preload("res://scripts/survival/survival_run.gd")
const SurvivalPicker = preload("res://scripts/survival/survival_picker.gd")
const SurvivalRecords = preload("res://scripts/survival/survival_records.gd")

var _current: Node
var _kind := ""                    # いまの画面の種類(画面の kind。"title" / "menu" / "multi" / "game" / "result")。クラスでは判定しない(UI セットで中身が変わる)
var _ui_layer: CanvasLayer         # 設定・選択のパネルを、画面の上に重ねる層
var _settings_panel: Control       # 開いている設定パネル(どの画面からでも開ける。プレイ中は除く)
var _aux_panel: Control            # 開いているプレイリスト・プロフィールのパネル(上のツールバーから開く。設定と同じく、どの画面からでも開ける)
var _settings_dict: Dictionary = {}
var _ui_before := ""               # 設定を開いたときの UI の見た目(閉じたとき、変わっていたら、いまの画面を作り直す)
var _settings_btn: Button          # 画面の右上の「設定」(タイトル・選曲画面は、自分で設定を開く入口を持つので出さない)
var _songs_changed := false      # 設定パネルで、osu! の Songs フォルダの設定が変わった(閉じたときに、選曲画面の一覧を作り直す)
var _fetch: Node                  # osu! の譜面ページの URL から曲を取るダウンロード(fetch_song_url。初めて使うときに作る)
var _fetch_note_at := 0            # ダウンロードの進み具合の通知を、最後に書き換えた時刻(ミリ秒)
var _fetch_queue: Array = []       # ダウンロードの順番待ち [{id, label, select}]
var _fetch_cur := {}               # いまダウンロードしている曲 {id, label, select}
## 曲の ID → ダウンロードの状態(_set_fetch_state)。lazer 風の選曲画面が、同じ辞書を持って「探す」の行に出す
var fetch_states := {}
var _watch_known := {}             # songs フォルダに、いま見えている .osz(名前|大きさ → パス)
var _watch_pending := {}           # 見つけたが、コピーの途中かもしれないもの(大きさが落ち着くまで待つ)
var _watch_ready := false
var _watch_t := 0.0
var net                    # 通信層(マルチプレイを開くときに作る。部屋を出ても使い回す)
var _last_play := {}
var _play_loader := true           # 選曲からプレイへ進むとき、開始前画面を挟むか(開発用の確認は、直接始める)
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
	NowPlaying.on_open_playlist = open_playlist   # 上のツールバーのプレイヤー・名前から開くパネル
	Profile.open_cb = open_profile
	for a in OS.get_cmdline_user_args():   # 開発用の確認・スクリーンショットは、使う人の設定(settings.cfg)でなく、写しの dev_settings.cfg を読み書きする(途中で止まっても、設定が壊れない)
		var a_s := str(a)
		if a_s.begins_with("--smoke") or a_s.begins_with("--shot") or a_s.begins_with("--prof"):
			Settings.use_dev_file()
			break
	var first_settings := Settings.load_all()
	Volume.init_from(first_settings)
	SongLibrary.apply_osu_settings(first_settings)   # osu! の Songs フォルダを使う設定のとき、その場所(スクリーンショット・動作確認の起動でも同じ)
	var args := OS.get_cmdline_user_args()
	for a in args:   # 開発用の確認・スクリーンショットでは、使う人のプレイ記録を残さない
		var a_s := str(a)
		if a_s.begins_with("--smoke") or a_s.begins_with("--shot") or a_s.begins_with("--prof"):
			load(P_Records).enabled = false
			SurvivalRecords.enabled = false
			Playlist.file_path = "user://dev_playlists.json"   # 確認用の起動は、使う人のプレイリストを書き換えない
			UiSets.override_id = "classic"   # 確認用の起動は、内部の変数を見る確認が多いので classic が既定(--ui で変えられる。下)
			_play_loader = false   # 確認用の起動は、開始前画面を挟まない(挟むのは、--smoke-loader だけ)
	if args.has("--smoke-loader"):
		_play_loader = true
	var hi := args.find("--hitch")   # 開発用: 長いフレームを記録する。例: -- --hitch 25 --smoke-ui
	if hi >= 0:
		var hl := HitchLog.new()
		if args.size() > hi + 1 and str(args[hi + 1]).is_valid_float():
			hl.threshold_ms = float(args[hi + 1])
		hl.screen_of = func() -> String: return str(_current.get("kind")) if is_instance_valid(_current) else ""
		add_child(hl)
	var ui_i := args.find("--ui")   # 例: -- --ui lazer(設定の ui_style を、この起動だけ上書きする。確認用の起動の既定は classic)
	if ui_i >= 0 and args.size() > ui_i + 1:
		UiSets.override_id = args[ui_i + 1]
	var ri := args.find("--replay-export")   # 動画の書き出しの子プロセス(親が --write-movie 付きで起動する)。-- --replay-export <ファイル> <軌道のモード> <軌道の秒> --chart <曲の場所>
	if ri >= 0 and args.size() > ri + 1:
		load(P_Records).enabled = false
		load(P_Replay).enabled = false
		UiSfx.enabled = bool(first_settings.ui_sound)   # リザルト画面の効果音(数え上げ・ランクの判子など)も、動画に入れる
		SfxBank.preload_all(["pop", "whistle", "clap", "boom", "tick", "hit", "explosion"])
		add_child(UiSfx.new())
		_replay_export_child(str(args[ri + 1]), int(args[ri + 2]) if args.size() > ri + 2 else 1, float(args[ri + 3]) if args.size() > ri + 3 else 3.0,
			str(args[args.find("--chart") + 1]) if args.has("--chart") and args.size() > args.find("--chart") + 1 else "")
		return
	if _dev_start(args):   # 開発用の確認・スクリーンショット(scripts/main_dev.gd が引き受ける。普通の起動では、何もしない)
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
	_warm_up()


## 起動のとき読まなかった画面(選曲・プレイ・リザルト・遊び方など)のスクリプトを、タイトルが出たあとに裏のスレッドで読んでおく。
## 起動を軽くするため、これらは使うときに load() している。先に読んでおけば、初めて開くときも待たない。
const WARM_UP_SCRIPTS := [
	"res://scripts/ui/lazer/lazer_menu.gd", "res://scripts/ui/lazer/lazer_game.gd", "res://scripts/ui/lazer/lazer_result.gd",
	"res://scripts/ui/lazer/lazer_howto.gd", "res://scripts/ui/lazer/lazer_quit.gd", "res://scripts/ui/lazer/lazer_options.gd",
	"res://scripts/ui/lazer/lazer_multi.gd", "res://scripts/ui/lazer/lazer_mods.gd", "res://scripts/ui/lazer/lazer_update.gd",
	"res://scripts/ui/lazer/lazer_loader.gd", "res://scripts/ui/lazer/lazer_playlist.gd", "res://scripts/ui/lazer/lazer_profile.gd",
	"res://scripts/ui/replay_list.gd", "res://scripts/records.gd", "res://scripts/replay.gd", "res://scripts/mods.gd",
]


func _warm_up() -> void:
	await get_tree().create_timer(0.5).timeout   # タイトルの最初の動きが始まってから
	for path in WARM_UP_SCRIPTS:
		ResourceLoader.load_threaded_request(path)


## 開発用の確認(--smoke* / --shot* / --prof*)を始める。始めたら true。本体では何もしない(scripts/main_dev.gd が、これを書き換えて引き受ける)。
func _dev_start(_args: PackedStringArray) -> bool:
	return false


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
	var r = load(P_OszImport).import_file(path)
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
		if load(P_OszImport).import_file(oszs[i]).ok:
			imported += 1
	var last: String = oszs[oszs.size() - 1]
	if _kind == "menu":
		var r = load(P_OszImport).import_file(last)
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


## タイトル・選曲画面で Ctrl+V: クリップボードに osu! の譜面ページの URL があれば、その曲を取り込む(なければ何もしない)。
## 入力欄に入力しているときは、入力欄が先に受け取るので、ここへは来ない。
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V and event.is_command_or_control_pressed()):
		return
	if (_kind != "title" and _kind != "menu") or _settings_panel != null or _aux_panel != null:
		return
	var text := DisplayServer.clipboard_get()
	if SongSources.set_id_of(text) != 0:
		get_viewport().set_input_as_handled()
		fetch_song_url(text)


## osu! の譜面ページの URL の曲を、ミラーサイトからダウンロードして取り込む(選曲画面の「URL から取り込む」・検索欄への貼り付け・Ctrl+V)。
## 取り込めたら、.osz を開いたときと同じく、選曲画面でその曲を選ぶ(プレイ中・ロビーなら、取り込みと通知だけ)。
func fetch_song_url(text: String) -> void:
	var id := SongSources.set_id_of(text)
	if id <= 0:
		if overlay != null:
			overlay.toast("難易度のページではなく、曲のページ(osu.ppy.sh/beatmapsets/…)の URL を使ってください" if id < 0 else "osu! の譜面ページの URL ではありません(osu.ppy.sh/beatmapsets/…)", 4.0)
		return
	fetch_song_set(id, "", true)


## 曲(BeatmapSet の ID)をダウンロードして取り込む(URL・lazer 風の選曲の「探す」)。ダウンロード中なら、順番待ちに足す。
## 初めては、非公式のミラーから取ることへの同意を求める(マルチプレイのダウンロードと同じ設定 mirror_consent)。
## select: 取り込めたら選曲画面でその曲を選ぶ(「探す」から続けて取るときは選ばない)。進み具合は fetch_states に入れ、画面の on_fetch_state へ知らせる。
func fetch_song_set(set_id: int, label := "", select := true) -> void:
	if set_id <= 0:
		return
	var cur_state := str((fetch_states.get(set_id, {}) as Dictionary).get("state", ""))
	if cur_state == "queued" or cur_state == "downloading":
		return
	var cur = _current.get("settings") if _current != null else null
	var st: Dictionary = cur if cur is Dictionary else Settings.load_all()
	if bool(st.get("mirror_consent", false)):
		_enqueue_fetch(set_id, label, select)
		return
	if _aux_panel != null:
		return
	var q = UiSets.current().make_quit()
	q.setup("非公式のミラーサイトから取得します", "同意してダウンロード", "キャンセル",
		"この曲(.osz)を、osu! 公式ではないミラーサイト(osu.direct・Nerinyan・catboy.best)からダウンロードして取り込みます。\n" +
		"本アプリと各ミラーサイトは無関係で、譜面・楽曲の権利は、それぞれの制作者にあります。公式のページから入れたいときは、ブラウザでダウンロードした .osz をドロップしてください。\n" +
		"同意すると、次からはこの確認を出しません。")
	q.confirmed.connect(func():
		st.mirror_consent = true
		Settings.save_all(st)
		close_aux()
		_enqueue_fetch(set_id, label, select))
	_open_aux(q)


func _ensure_fetch() -> void:
	if _fetch != null:
		return
	_fetch = load(P_SongDownload).new()
	add_child(_fetch)   # main の子なので、画面を移ってもダウンロードは続く
	_fetch.progress.connect(func(frac: float, text: String):
		var now := Time.get_ticks_msec()
		if now - _fetch_note_at >= 250:   # 文字の差し替え・画面への知らせは、ときどき
			_fetch_note_at = now
			if overlay != null:
				overlay.toast_update(("%s  %d%%" % [text, roundi(frac * 100.0)]) if frac > 0.0 else text, 30.0)
			if not _fetch_cur.is_empty():
				_set_fetch_state(int(_fetch_cur.id), {"state": "downloading", "frac": frac}))
	_fetch.finished.connect(_on_fetch_finished)


func _enqueue_fetch(set_id: int, label: String, select: bool) -> void:
	_fetch_queue.append({"id": set_id, "label": label, "select": select})
	_set_fetch_state(set_id, {"state": "queued"})
	_next_fetch()


func _next_fetch() -> void:
	_ensure_fetch()
	if _fetch.busy or _fetch_queue.is_empty():
		return
	_fetch_cur = _fetch_queue.pop_front()
	_fetch_note_at = 0
	var id := int(_fetch_cur.id)
	_set_fetch_state(id, {"state": "downloading", "frac": 0.0})
	if overlay != null:
		var name := str(_fetch_cur.label) if str(_fetch_cur.label) != "" else "曲(ID %d)" % id
		overlay.toast("%s をダウンロードしています…" % name + ("(あと %d 曲)" % _fetch_queue.size() if not _fetch_queue.is_empty() else ""), 30.0)
	_fetch.start(id, "", ("%d %s" % [id, _fetch_cur.label]) if str(_fetch_cur.label) != "" else str(id))


## ダウンロードの状態を覚えて、いまの画面に知らせる。s: {state: queued / downloading / done / failed, frac, path, error}
func _set_fetch_state(set_id: int, s: Dictionary) -> void:
	fetch_states[set_id] = s
	if _current != null and _current.has_method("on_fetch_state"):
		_current.on_fetch_state(set_id, s)


func _on_fetch_finished(r: Dictionary) -> void:
	var job := _fetch_cur
	_fetch_cur = {}
	var id := int(job.get("id", 0))
	if not r.ok:
		_set_fetch_state(id, {"state": "failed", "error": str(r.error)})
		if overlay != null:
			overlay.toast(str(r.error), 6.0)
		_next_fetch()
		return
	_watch_sync()   # 取り込んだ曲は、フォルダの監視には「新しい曲」として知らせない
	_set_fetch_state(id, {"state": "done", "path": str(r.path)})
	var name := str(r.title) if str(r.title) != "" else str(r.path).get_file()
	if overlay != null:
		overlay.toast(("%s はもう入っています" if r.get("existed", false) else "%s を取り込みました") % name)
	if _kind == "menu":
		_current.refresh_songs()
		if bool(job.get("select", true)):
			_current.select_path(str(r.path))
	elif _kind == "title" and bool(job.get("select", true)) and _settings_panel == null and _aux_panel == null:
		var st := Settings.load_all()
		st.last_song = r.path
		st.last_diff = ""
		Settings.save_all(st)
		show_menu()
	_next_fetch()


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
	close_aux()
	close_settings()   # 画面が変わるときは、開いている設定は閉じる
	if _current != null:
		_current.queue_free()
	_current = n
	var k = n.get("kind")
	_kind = k if k is String else ""
	SongArt.paused = _kind == "game"   # プレイ中は、選曲の一覧の画像・難易度の取得を止める(初めての曲で、プレイ中に画面が止まっていた)
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
	_settings_btn.visible = _current != null and not own and _kind != "game" and _kind != "title" and _kind != "menu" and _settings_panel == null and _aux_panel == null


## 設定パネルを開く(section: 0=操作 1=音 2=画面 3=曲 4=その他)。いまの画面が設定の辞書(settings)を持っていれば、それを直接変える。
func _exit_tree() -> void:
	SongLibrary.stop_warmup()   # 裏で索引を作っているスレッドを、閉じる前に止める
	load(P_Replay).flush()   # リプレイを書いている途中なら、書き終わるのを待つ


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


## プレイリストのパネルを開く(上のツールバーのプレイヤーの「≡」)。
func open_playlist() -> void:
	_open_aux(load(P_LazerPlaylist).new())


## 名前とアイコンを変えるパネルを開く(上のツールバーの右端の名前)。いまの画面が設定の辞書(settings)を持っていれば、それを直接変える。
func open_profile() -> void:
	if _current == null:
		return
	var p = load(P_LazerProfile).new()
	var st = _current.get("settings")
	p.setup(st if st is Dictionary else Settings.load_all())
	_open_aux(p)


func _open_aux(p: Control) -> void:
	if _aux_panel != null or _settings_panel != null or _current == null or _kind == "game":
		p.free()
		return
	_setup_ui_layer()
	_ui_layer.add_child(p)
	_aux_panel = p
	p.closed.connect(close_aux)
	_current.set_process_input(false)   # 開いている間、下の画面は Esc や矢印に反応しない(設定パネルと同じ)
	_update_settings_button()


func close_aux() -> void:
	if _aux_panel == null:
		return
	var p := _aux_panel
	_aux_panel = null
	if is_instance_valid(_current):
		_current.set_process_input(true)
	p.queue_free()
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
	if t.has_signal("survival_requested"):   # lazer 風のタイトルだけ
		t.survival_requested.connect(show_survival)
	t.settings_requested.connect(open_settings)
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


## タイトルの項目の番号(lazer 風のタイトルは id から引く。classic は決まった番号)。開発用の確認が使う。
func _title_idx(id: String, classic_i: int) -> int:
	if _current != null and _current.has_method("item_index"):
		return _current.item_index(id)
	return classic_i


## リプレイの一覧を、タイトルの上に重ねる。選んだリプレイを再生して、閉じたら一覧へ戻る。
func _open_replay_list(t) -> void:
	var p = UiSets.current().make_replays()
	p.replay_requested.connect(func(name: String): show_replay(name, func(): show_title(true)))
	t.open_panel(p)


func show_menu(pick := false) -> void:
	var m = UiSets.current().make_menu(pick)   # pick: マルチプレイの部屋の曲を選ぶとき(決定でロビーへ戻る)
	m.settings_requested.connect(open_settings)
	if m.has_signal("url_requested"):   # 「URL から取り込む」・検索欄への URL の貼り付け
		m.url_requested.connect(fetch_song_url)
	if m.has_signal("set_requested"):   # lazer 風の選曲の「探す」: 曲をダウンロードする
		m.set_requested.connect(func(id: int, label: String): fetch_song_set(id, label, false))
	if "fetch_states" in m:
		m.fetch_states = fetch_states
	if pick:
		m.song_picked.connect(_on_song_picked)
		m.back_requested.connect(func(): show_multi())
	else:
		m.play_requested.connect(func(l, b, st: Dictionary, pre: Dictionary): _on_play_requested(m, l, b, st, pre))
		m.back_requested.connect(show_title)
		if m.has_signal("replay_requested"):   # lazer 風の選曲: 記録の再生ボタン
			m.replay_requested.connect(func(n: String): show_replay(n, func(): show_menu()))
	_stop_music()
	_swap(m)


## 通信層(net.gd)。マルチプレイを開くときに作り、以後は使い回す(部屋を出ても、作り直さない)。
func _get_net():
	if net == null:
		net = load(P_NetScript).new()
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
			load(P_Mods).multi_ok(settings.mods), 1.0, loader, bm)   # 撃破はひとり用
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


## 選曲で「プレイ」を押した。開始前画面のある UI セットなら、それを挟む(背景は選曲の続き)。なければ、すぐ始める。
## リトライ・リザルトからのやり直し・リプレイ・マルチプレイは挟まず、start_game を直接呼ぶ。
func _on_play_requested(menu, loader, bm, settings: Dictionary, pre: Dictionary) -> void:
	var ld = UiSets.current().make_loader() if _play_loader else null
	if ld == null:
		start_game(loader, bm, settings, -1.0, -1.0, pre)
		return
	var tex = menu.current_background() if menu.has_method("current_background") else null
	ld.setup(loader, bm, settings, pre, tex, menu.current_zoom() if menu.has_method("current_zoom") else 1.0)
	ld.go_requested.connect(func(): start_game(loader, bm, settings, -1.0, -1.0, pre))
	ld.back_requested.connect(show_menu)
	_stop_music()
	SongArt.cancel_all()
	_swap(ld, true)   # 選曲の発進の演出がそのまま続くので、幕は入れずに切り替える(プレイへ進むときに、幕を入れる)


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
	SongArt.cancel_all()   # 選曲の一覧の画像・難易度の取得は、プレイ中は続けない(別スレッドの解析が、プレイ中の画面を止めることがある)
	_swap(g)


## music: クリアで引き継いだ曲(鳴ったまま、リザルトでも流し続ける。メニュー/リトライで消える)。画面は間を置かずに切り替える。
func show_result(stats: Dictionary, music: AudioStreamPlayer = null) -> void:
	if not stats.has("new_best"):   # リプレイから戻ったときは、もう記録した
		stats["new_best"] = load(P_Records).record_stats(stats)   # ひとりでクリアしたものだけ記録される(これまでの最高を超えたとき true)
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


# --- サバイバル(docs/survival_plan.md。1 回の状態と点は SurvivalRun、曲の選び方と用意は SurvivalPicker) ---
## 準備画面 → 曲の間(1 曲目の前は NEXT だけ)→ プレイ → 曲の間 → … → 倒れた・あきらめた → リザルト。
## 曲の間で 3 択が済んだら次の曲を選び、別スレッドで用意する(曲を開く・弾幕・MOD 込みの Lv・音声・背景)。
## プレイ中は裏で何もしない(別スレッドの解析が、プレイ中の画面を止めることがあるため)。プレイ画面は曲ごとに作り直す。

var _sv_run                    # いまのサバイバル(SurvivalRun。遊んでいないときは null)
var _sv_charts: Array = []     # 選べる譜面の一覧(SurvivalPicker.read_charts)
var _sv_next: Dictionary = {}  # 次の曲 {chart, mods, extra}
var _sv_loaded: Dictionary = {}   # 用意できた次の曲(SurvivalPicker.load_chart の結果)
var _sv_job := 0               # 用意の通し番号(最新のものだけ使う)
var _sv_bg: Texture2D          # 最後に遊んだ曲の背景(リザルトに敷く)


func show_survival() -> void:
	_sv_run = null
	_sv_job += 1
	var s = UiSets.current().make_survival_setup()
	s.start_requested.connect(_survival_start)
	s.back_requested.connect(show_title)
	_stop_music()
	_swap(s)


func _survival_start(start_lv: float, mods: Array, charts: Array) -> void:
	_sv_run = SurvivalRun.new()
	_sv_run.start(start_lv, mods)
	_sv_charts = charts
	_sv_bg = null
	_survival_break({}, 1.0, null, null)


## 曲の間の画面。last: 終えた曲の記録(1 曲目の前は空)/ music: クリアした曲(流れたまま来る。画面がフェードアウトさせる)
func _survival_break(last: Dictionary, hp_end: float, bg: Texture2D, music: AudioStreamPlayer) -> void:
	var b = UiSets.current().make_survival_break()
	b.setup(_sv_run, last, hp_end, bg, music)
	b.choices_done.connect(func(): _survival_pick(b))
	b.go_requested.connect(func(): _survival_play(b))
	b.give_up_requested.connect(_survival_end)
	_stop_music()
	_swap(b, music != null)


## 次の曲を選んで、裏で用意し始める。読めなかったら、別の曲を選び直す(数回まで)。
func _survival_pick(b, tries := 0) -> void:
	var run = _sv_run
	if run == null or _current != b:
		return
	var pk := SurvivalPicker.pick(_sv_charts, run.target_level(), run.mod_ids, run.used_keys, run.rng)
	if pk.is_empty():
		b.show_error("遊べる曲がありません")
		return
	var c: Dictionary = pk.chart
	var mods: Array = run.mod_ids.duplicate()
	for m in pk.extra_mods:
		mods = load(P_Mods).toggled(mods, str(m), true)
	_sv_next = {"chart": c, "mods": mods, "extra": pk.extra_mods}
	run.used_keys[c.key] = int(run.used_keys.get(c.key, 0)) + 1
	b.show_next({"title": c.title, "artist": c.artist, "version": c.version, "est": pk.est, "extra_mods": pk.extra_mods})
	_sv_job += 1
	var job := _sv_job
	_sv_loaded = {}
	WorkerThreadPool.add_task(func():
		var r := SurvivalPicker.load_chart(c, mods)
		_survival_loaded.call_deferred(job, r, b, tries))


func _survival_loaded(job: int, r: Dictionary, b, tries: int) -> void:
	if job != _sv_job or _current != b or not is_instance_valid(b):
		return
	if not bool(r.ok):
		if tries < 5:
			_survival_pick(b, tries + 1)
		else:
			b.show_error("曲を読み込めませんでした: %s" % str(r.get("error", "")))
		return
	r["tex"] = ImageTexture.create_from_image(r.image) if r.get("image") != null else null
	_sv_loaded = r
	b.set_ready(float(r.level), r.tex)


func _survival_play(b) -> void:
	if _sv_loaded.is_empty() or _current != b or _sv_run == null:
		return
	var r := _sv_loaded
	_sv_loaded = {}
	var st := Settings.load_all()
	st["mods"] = _sv_next.mods
	st["speed_study"] = false
	st["replay_save"] = false
	var g = UiSets.current().make_game()
	g.setup(r.loader, r.bm, st)
	g.pre = {"gen": r.gen, "audio": r.audio}
	g.survival = _sv_run.game_params()
	var info := {"key": str(_sv_next.chart.key), "extra_mods": _sv_next.extra}
	g.finished.connect(func(stats, music): _survival_song_done(stats, music, info))
	g.quit_requested.connect(_survival_end)
	_stop_music()
	SongArt.cancel_all()
	_swap(g)


func _survival_song_done(stats: Dictionary, music: AudioStreamPlayer, info: Dictionary) -> void:
	if _sv_run == null:
		return
	var e: Dictionary = _sv_run.song_done(stats, info)
	_sv_bg = stats.get("bg")
	if _sv_run.over:
		if music != null:
			music.queue_free()
		_survival_end()
		return
	_survival_break(e, float(stats.get("hp_end", 0.0)), _sv_bg, music)


## 終わり(倒れた・あきらめた): 記録して、リザルトへ。
func _survival_end() -> void:
	var run = _sv_run
	_sv_job += 1   # 用意の途中なら、結果は捨てる
	if run == null:
		show_title()
		return
	var rec: Dictionary = run.to_record()
	var best := SurvivalRecords.add(rec)
	var r = UiSets.current().make_survival_result()
	r.setup(rec, best, _sv_bg)
	r.again_requested.connect(show_survival)
	r.menu_requested.connect(show_title)
	_sv_run = null
	_stop_music()
	_swap(r)


# --- リプレイ ---

## リプレイを再生する。name: user://replays/ の中のファイル名。on_close: 閉じたあとに出す画面を作る関数。
func show_replay(name: String, on_close: Callable) -> void:
	var data = load(P_Replay).load_file(name)
	if data.is_empty():
		if overlay != null:
			overlay.toast("リプレイを読めません(消えたか、別のバージョンで作られたものです)")
		return
	var found = load(P_Replay).find_chart(str(data.md5))
	if found.is_empty():
		if overlay != null:
			overlay.toast("このリプレイの曲が見つかりません: %s" % str(data.get("title", "")))
		return
	var g = UiSets.current().make_game()
	g.setup_replay(found.loader, found.bm, Settings.load_all(), data)
	g.quit_requested.connect(func():
		_export_forget(g)
		on_close.call())
	g.replay_export_requested.connect(func(d: Dictionary, opts: Dictionary): _replay_export(name, d, opts, g, str(found.get("path", ""))))
	_stop_music()
	_swap(g)


var _export_last := ""          # 最後の書き出しの結果の文(確認用)
var _export := {}              # 動画の書き出し中: {pid, avi, mp4, dir, screen, phase, ffmpeg_pid}
var _export_timer: Timer


## 動画の書き出しの子プロセス: 操作パネルなしで、リプレイを 1 倍の速さで最後まで流し、続けてリザルト画面を数秒撮って、自分で終了する。
func _replay_export_child(path: String, trail_mode: int, trail_sec: float, chart_path := "") -> void:
	var data = load(P_Replay).load_file(path)
	var found := {}
	if not data.is_empty():
		found = load(P_Replay).open_chart(chart_path, str(data.get("md5", ""))) if chart_path != "" else {}
		if found.is_empty():
			found = load(P_Replay).find_chart(str(data.get("md5", "")))
	if data.is_empty() or found.is_empty():
		printerr("replay-export: リプレイまたは曲を読めません: ", path)
		get_tree().quit(1)
		return
	var g = UiSets.current().make_game()
	g.replay_export = true
	g.replay_trail_mode = trail_mode
	g.replay_trail_sec = trail_sec
	g.setup_replay(found.loader, found.bm, Settings.load_all(), data)
	g.replay_export_finished.connect(func(st: Dictionary, music: AudioStreamPlayer):
		show_result(st, music)   # リザルト画面(ボタンなし)を、数秒撮ってから終わる
		get_tree().create_timer(RESULT_IN_VIDEO).timeout.connect(func():
			print("replay-export: UI の効果音 %d 回" % (UiSfx.inst.log.size() if UiSfx.inst != null else -1))
			load(P_Replay).write_progress(1.0)
			get_tree().quit()))
	_stop_music()
	_swap(g)
	_setup_fade()   # リザルトへ移るときの幕(プレイのときと同じ見え方。始まりは幕なしで、すぐ映す)


## ffmpeg の場所(なければ ""): アプリと同じフォルダに置いたもの → PATH の通ったもの、の順。
func _ffmpeg_exe() -> String:
	var beside := OS.get_executable_path().get_base_dir().path_join("ffmpeg.exe")
	if FileAccess.file_exists(beside):
		return beside
	return "ffmpeg" if OS.execute("ffmpeg", ["-version"], []) == 0 else ""


## 動画の書き出し: 別のプロセスの Godot が、Movie Maker(--write-movie)で、リプレイを固定のフレーム時間で再生しながら、画面と音を AVI に書く。
## opts: {w, h, fps, trail_mode, trail_sec}。空なら、書き出し中の中止。chart_path: 曲の場所(子プロセスへ渡す)。
## ffmpeg が PC にあれば、そのあと mp4 にも変換する(変換できたら、AVI は消す)。
func _replay_export(name: String, data: Dictionary, opts: Dictionary, screen, chart_path := "") -> void:
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
		"--replay-export", ProjectSettings.globalize_path(load(P_Replay).dir.path_join(name)), str(int(opts.get("trail_mode", 1))), str(float(opts.get("trail_sec", 3.0))),
		"--chart", chart_path])
	load(P_Replay).write_progress(0.0)
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
			_export_status("動画を書き出し中 %d%%(別のウィンドウ。閉じないでください)" % int(load(P_Replay).read_progress() * 100.0))
			return
		if not FileAccess.file_exists(str(_export.avi)):
			_export_finish("動画を書き出せませんでした")
			return
		if load(P_Replay).read_progress() < 0.98:   # 途中でウィンドウを閉じた
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
