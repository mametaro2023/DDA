extends RefCounted
## user://settings.cfg の読み書き。

const PATH := "user://settings.cfg"
const Volume = preload("res://scripts/volume.gd")
const FpsOverlay = preload("res://scripts/ui/fps_overlay.gd")

const DEFAULTS := {
	"offset_ms": 0,       # 音と弾のタイミング校正(+で弾が遅れる)
	"sfx_volume": 70,     # 効果音の音量 0..100(%)
	"control": "mouse",   # 操作: keyboard / mouse
	"mouse_sens": 1.0,    # マウス感度(相対移動の倍率)
	"mods": [],           # 付ける MOD の id(scripts/mods.gd)
	"last_song": "",
	"last_diff": "",      # 直前にプレイした難易度の名前(メニューに戻ったときに選んだ状態にする)
	"volume": 80,          # 全体音量 0..100(%)
	"music_volume": 100, # 音楽の音量 0..100(%)
	"ui_sound": true,     # メニューなどの UI の効果音(ホバー・クリックなど)
	"vsync": true,         # 垂直同期(画面のちらつき・ずれを抑える。切ると遅延が減る)
	"window_size": "",    # ウィンドウの大きさ("1600x900" の形、または "fullscreen")。空なら変えない(標準は 1280x720。枠のドラッグで変えた大きさは保存しない)
	"show_fps": false,      # 画面右下に FPS(描画・処理)を出す
	"eye_comfort": true,  # アリーナの表示を目に優しくする(弾の色・白い芯・キアイの拍の光・予兆の点滅を抑える。当たり判定・難易度は変わらない)
	"check_update": true, # 起動時に、新しいバージョンがないか確認する
	"auto_update": true,  # 新しいバージョンが見つかったら、自動でダウンロードして入れ替える(check_update が入のとき。書き出した版のみ)
	"last_auto_update": "", # 最後に自動更新を始めたバージョン(同じバージョンで繰り返し更新し続けないための印)
	"player_name": "",    # マルチプレイでの表示名(空なら初回に自動で決める)
	"speed_study": false, # 弾速の実験に参加する(scripts/speed_study.gd。ひとりで遊ぶとき、弾速などを変えた弾幕で遊び、結果を user://speed_study.csv に記録する)
	"song_sort": "title", # 選曲の並び順(song_browser.gd の SORT_MODES の id。lazer 風の選曲画面)
	"ui_style": "classic", # UI の見た目(scripts/ui/ui_sets.gd の名前。知らない名前のときは classic)
	"ui_promo_hidden": false, # クラシックのタイトルの「新しい UI で遊ぼう」を出さない(✕ で閉じた・一度試した)
	"osu_songs": false,   # osu! の Songs フォルダの曲も、一覧に加える(コピーせず、その場で読む。scripts/song_library.gd)
	"osu_songs_dir": "",  # その Songs フォルダ。空なら osu! の標準の場所から探す
	"mirror_consent": false, # マルチプレイで曲を、非公式のミラーサイトからダウンロードすることに同意した(最初のダウンロードのときに聞く)
}


static func load_all() -> Dictionary:
	var out := DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for k in DEFAULTS:
			out[k] = cfg.get_value("game", k, DEFAULTS[k])
		# 弾幕 v2 は初期状態になった(旧版の MOD「弾幕 v2」は、もう無い)
		out.mods = (out.mods as Array).filter(func(id): return str(id) != "v2")
		# 旧版の「練習モード」の設定は、MOD「練習」に引き継ぐ
		if bool(cfg.get_value("game", "practice", false)) and not (out.mods as Array).has("practice"):
			var ms: Array = (out.mods as Array).duplicate()
			ms.append("practice")
			out.mods = ms
	Volume.write_into(out)   # 起動後は、音量は Volume の値が正(ホイールなどで変えた値を、古い読み込みで戻さない)
	return out


static func save_all(d: Dictionary) -> void:
	d = d.duplicate()
	Volume.write_into(d)
	var cfg := ConfigFile.new()
	cfg.load(PATH)   # いまの内容を土台にする(この版が知らない項目を、別の版が書いていても消さない)
	for k in DEFAULTS:
		cfg.set_value("game", k, d.get(k, DEFAULTS[k]))
	cfg.save(PATH)


## ウィンドウの大きさの候補(16:9)。画面に入らない大きさは選べない。
const WINDOW_SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]


## 垂直同期を反映する。
static func apply_vsync(on: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED)


## "1600x900" の形の文字を大きさにする(読めなければ Vector2i.ZERO)。
static func parse_size(text: String) -> Vector2i:
	var p := text.split("x")
	if p.size() != 2 or not p[0].is_valid_int() or not p[1].is_valid_int():
		return Vector2i.ZERO
	return Vector2i(int(p[0]), int(p[1]))


## いまのウィンドウがある画面に、この大きさ(枠・タイトルバーを含めて)が収まるか。
static func size_fits(size: Vector2i) -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	var area := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var deco := DisplayServer.window_get_size_with_decorations() - DisplayServer.window_get_size()
	return size.x + deco.x <= area.size.x and size.y + deco.y <= area.size.y


## ウィンドウを、この大きさ(中身の大きさ)にして、画面の中央へ置く。画面に収まらないときは、収まる大きさまで縮める。
static func apply_window_size(size: Vector2i) -> void:
	if DisplayServer.get_name() == "headless" or size.x < 320 or size.y < 180:
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var area := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var deco := DisplayServer.window_get_size_with_decorations() - DisplayServer.window_get_size()
	size = Vector2i(mini(size.x, area.size.x - deco.x), mini(size.y, area.size.y - deco.y))
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(area.position + (area.size - (size + deco)) / 2)


## 全画面にする前のウィンドウの大きさ(F11 で戻すとき用。まだ分からなければ標準の 1280x720)
static var windowed_size := Vector2i(1280, 720)


static func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## 全画面 ⇔ ウィンドウを入れ替える(F11)。d の window_size を、入れ替えた結果("fullscreen" または "1600x900")に書き換えて返す(保存は呼び出し側)。
## ウィンドウに戻すときは、全画面にする前の大きさへ戻す。
static func toggle_fullscreen(d: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if is_fullscreen():
		apply_window_size(windowed_size)
		var now := DisplayServer.window_get_size()
		d["window_size"] = "%dx%d" % [now.x, now.y]
	else:
		apply_fullscreen()
		d["window_size"] = "fullscreen"


## 全画面にする(枠のない全画面。画面の解像度のまま、ゲームの画面は縦横の比を保って広がる)。
static func apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not is_fullscreen():
		windowed_size = DisplayServer.window_get_size()   # F11 で戻すときの大きさ
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## 起動時に、保存した画面の設定を反映する。
static func apply_display(d: Dictionary) -> void:
	apply_vsync(bool(d.get("vsync", true)))
	FpsOverlay.enabled = bool(d.get("show_fps", false))
	var ws := str(d.get("window_size", ""))
	if ws == "fullscreen":
		apply_fullscreen()
		return
	var sz := parse_size(ws)
	if sz != Vector2i.ZERO:
		apply_window_size(sz)


## 全体音量(%)を反映する(Volume に集約)。
static func apply_volume(percent: float) -> void:
	Volume.set_master(percent)


## 設定を元の内容へ戻す(開発用のスモークテストが、ユーザーの設定を戻すのに使う。音量も元へ戻す)。
static func restore(original: Dictionary) -> void:
	Volume.init_from(original)
	save_all(original)
