extends RefCounted
## 音量の一元管理(全体・音楽・効果音。0..100 %)。画面をまたいで同じ値を使う(ホイール・設定・ポーズのどこで変えても、ここに集まる)。
##   全体   … マスターバス
##   音楽   … 「Music」バス(曲を流すプレイヤーはすべてこのバスに送る。マスターの子)
##   効果音 … sfx.gd の volume(プレイ画面が rev の変化を見て反映する)
## 値の保存は Settings が行う(save_all は、ここの値を書き込む)。

const MUSIC_BUS := &"Music"

static var master := 80
static var music := 100
static var sfx := 70
static var loaded := false
## 値が変わるたびに増える(プレイ画面が効果音の音量を反映し直すのに使う)
static var rev := 0


## 保存された値を取り込む(起動時に 1 度)。以後は、この値が正。
static func init_from(d: Dictionary) -> void:
	master = clampi(int(d.get("volume", 80)), 0, 100)
	music = clampi(int(d.get("music_volume", 100)), 0, 100)
	sfx = clampi(int(d.get("sfx_volume", 70)), 0, 100)
	loaded = true
	apply()


## 設定の辞書へ、今の値を書き込む(画面が古い値を持ったまま保存して、ホイールで変えた値を上書きしないように)。
static func write_into(d: Dictionary) -> void:
	if loaded:
		d["volume"] = master
		d["music_volume"] = music
		d["sfx_volume"] = sfx


static func ensure_bus() -> int:
	var i := AudioServer.get_bus_index(MUSIC_BUS)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, MUSIC_BUS)
		AudioServer.set_bus_send(i, &"Master")
	return i


## 曲を流すプレイヤーを、音楽バスへ送る。
static func route_music(p: AudioStreamPlayer) -> void:
	ensure_bus()
	p.bus = MUSIC_BUS


static func apply() -> void:
	AudioServer.set_bus_mute(0, master <= 0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master / 100.0, 0.0001)))
	var i := ensure_bus()
	AudioServer.set_bus_mute(i, music <= 0)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(music / 100.0, 0.0001)))


static func set_master(v: float) -> void:
	master = clampi(int(round(v)), 0, 100)
	loaded = true
	rev += 1
	apply()


static func set_music(v: float) -> void:
	music = clampi(int(round(v)), 0, 100)
	loaded = true
	rev += 1
	apply()


static func set_sfx(v: float) -> void:
	sfx = clampi(int(round(v)), 0, 100)
	loaded = true
	rev += 1


static func get_value(kind: int) -> int:
	return [master, music, sfx][kind]


static func set_value(kind: int, v: float) -> void:
	match kind:
		0: set_master(v)
		1: set_music(v)
		_: set_sfx(v)
