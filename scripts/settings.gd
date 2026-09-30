extends RefCounted
## user://settings.cfg の読み書き。

const PATH := "user://settings.cfg"

const DEFAULTS := {
	"offset_ms": 0,       # 音と弾のタイミング校正(+で弾が遅れる)
	"density_mul": 1.0,   # 弾密度倍率(目標の画面内弾数に掛ける)
	"sfx_volume": 70,     # 効果音の音量 0..100(%)
	"control": "keyboard", # 操作: keyboard / mouse
	"mouse_sens": 1.0,    # マウス感度(相対移動の倍率)
	"mods": [],           # 付ける MOD の id(scripts/mods.gd)
	"last_song": "",
	"last_diff": "",      # 直前にプレイした難易度の名前(メニューに戻ったときに選んだ状態にする)
	"volume": 80,          # 全体音量 0..100(%)
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
	return out


static func save_all(d: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for k in DEFAULTS:
		cfg.set_value("game", k, d.get(k, DEFAULTS[k]))
	cfg.save(PATH)


## 全体音量(%)をマスターバスに反映する。
static func apply_volume(percent: float) -> void:
	var p := clampf(percent, 0.0, 100.0)
	AudioServer.set_bus_mute(0, p <= 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(p / 100.0, 0.0001)))
