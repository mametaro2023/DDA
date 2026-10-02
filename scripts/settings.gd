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
	"check_update": true, # 起動時に、新しいバージョンがないか確認する
	"player_name": "",    # マルチプレイでの表示名(空なら初回に自動で決める)
}


static func load_all() -> Dictionary:
	var out := DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for k in DEFAULTS:
			out[k] = cfg.get_value("game", k, DEFAULTS[k])
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


## 全画面にする(枠のない全画面。画面の解像度のまま、ゲームの画面は縦横の比を保って広がる)。
static func apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
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
