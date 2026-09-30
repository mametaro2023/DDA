extends RefCounted
## user://settings.cfg の読み書き。

const PATH := "user://settings.cfg"
const Volume = preload("res://scripts/volume.gd")

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
	"check_update": true, # 起動時に、新しいバージョンがないか確認する
	"player_name": "",    # マルチプレイでの表示名(空なら初回に自動で決める)
	"osz_open": "ask",    # .osz をアプリで開いたとき: ask(毎回聞く) / dda(このアプリで開く) / osu(osu! で開く)
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


## 全体音量(%)を反映する(Volume に集約)。
static func apply_volume(percent: float) -> void:
	Volume.set_master(percent)


## 設定を元の内容へ戻す(開発用のスモークテストが、ユーザーの設定を戻すのに使う。音量も元へ戻す)。
static func restore(original: Dictionary) -> void:
	Volume.init_from(original)
	save_all(original)
