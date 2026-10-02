extends Node
## UI の効果音(ホバー・クリック・選択・開閉・スタンプなど)。音は tools/sfx_forge.gd が作って assets/sfx/ に置いたファイルを読む(scripts/sfx_bank.gd)。
## ゲーム中の弾の音(game/sfx.gd)とは別。カリンバ・マリンバ・鉄琴のような、短く丸い音で揃える(耳に刺さる高い音・長い余韻は使わない)。
## 使い方: UiSfx.play("click")。pitch で音程を、gain で大きさを変える(選択の ↑↓ で音程を上げ下げするなど)。
## 音量は「効果音」の設定(Volume.sfx)に従い、設定の「UI の音」を切ると鳴らない。

const Volume = preload("res://scripts/volume.gd")
const SfxBank = preload("res://scripts/sfx_bank.gd")

const POOL := 8

## 名前 → [最小再生間隔(秒), 基本ゲイン]
const SPECS := {
	"hover": [0.05, 0.45],
	"click": [0.04, 0.9],
	"select": [0.035, 0.7],
	"confirm": [0.1, 1.0],
	"back": [0.08, 0.85],
	"open": [0.12, 0.9],
	"close": [0.12, 0.8],
	"on": [0.05, 0.9],
	"off": [0.05, 0.9],
	"tick": [0.025, 0.55],
	"stamp": [0.2, 1.0],
	"whoosh": [0.15, 0.8],
	"toast": [0.15, 0.8],
	"deny": [0.1, 0.8],
	"count": [0.03, 0.5],
}

static var inst: Node
## false のとき、鳴らさない(設定の「UI の音」)
static var enabled := true

## デバッグ用: 再生要求の履歴 [名前, 時刻(ms)]
var log: Array = []

var _streams := {}
var _last := {}
var _players: Array = []
var _next := 0


func _init() -> void:
	for nm in SPECS:
		var list := SfxBank.variants(_file_of(nm))
		if not list.is_empty():
			_streams[nm] = list[0]


## 音の名前 → ファイルの名前(ゲーム中の tick と区別するため、UI の tick は tick_ui)。
static func _file_of(sfx_name: String) -> String:
	return "tick_ui" if sfx_name == "tick" else sfx_name


func _ready() -> void:
	inst = self
	for i in range(POOL):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func _exit_tree() -> void:
	if inst == self:
		inst = null


## 鳴らす(UiSfx.inst がなければ何もしない。テストや起動前でも安全)。
static func play(sfx_name: String, pitch := 1.0, gain := 1.0) -> void:
	if inst != null:
		inst.play_sound(sfx_name, pitch, gain)


## 値 0..1 を、半音ごとの音程(ペンタトニック)へ。スライダーや選択の移動を、音階として聞かせる。
static func scale_pitch(t: float, octaves := 1.0) -> float:
	var steps := [0, 2, 4, 7, 9]
	var n := int(round(clampf(t, 0.0, 1.0) * 5.0 * octaves))
	var semis: int = steps[n % 5] + 12 * (n / 5)
	return pow(2.0, semis / 12.0)


func play_sound(sfx_name: String, pitch := 1.0, gain := 1.0) -> void:
	log.append([sfx_name, Time.get_ticks_msec()])
	if not enabled or Volume.sfx <= 0 or not _streams.has(sfx_name) or _players.is_empty():
		return
	var spec: Array = SPECS[sfx_name]
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last.get(sfx_name, -10.0) < spec[0]:
		return
	_last[sfx_name] = now
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sfx_name]
	p.volume_db = linear_to_db(maxf(Volume.sfx / 100.0 * spec[1] * gain, 0.0001))
	p.pitch_scale = clampf(pitch, 0.25, 4.0)
	p.play()
