extends Node
## ゲーム中の効果音。音は tools/sfx_forge.gd が作って assets/sfx/ に置いたファイルを読み、ボイスプール経由で再生する(scripts/sfx_bank.gd)。
## 弾幕の発射音(音の中身は tools/sfx_recipes.gd):
##   pop = ふつう(打撃音)/ whistle = 口笛 / clap = 手拍子 / boom = 大きな弾(重い衝撃)/ tick = 細かい弾(木の小さな粒)
## 弾に触れている間は、ダメージが続く。触れた瞬間に hit(ツッ)を 1 回鳴らし、触れている間は hit_loop(ジジジ…)をループ再生する(touch_damage を毎フレーム呼ぶ。呼ばれなくなると、少しの間で消える)。
## 発射音は 6 種類の変種からランダムに選び(同じ変種が続けて鳴らない)、さらに音程も少し揺らして、同じ音の繰り返しに聞こえないようにする
## (揺らし幅は音ごと。音程のはっきりした whistle はほとんど揺らさず、曲と音程がずれないようにする)。被弾(hit)・爆発(explosion)は揺らさない。
## 発射音は、弾の発生源の横の位置に合わせて左右に振る(pan: -1 = 左端 〜 1 = 右端。振り幅は PAN_WIDTH まで。左右の振り分けは、音量を変える専用のバスで行う)。

const SfxBank = preload("res://scripts/sfx_bank.gd")

const POOL := 14

## 名前 → [最小再生間隔(秒), 基本ゲイン]
const SPECS := {
	"pop": [0.035, 1.0],
	"whistle": [0.05, 1.0],
	"clap": [0.05, 1.0],
	"boom": [0.08, 1.0],
	"tick": [0.07, 0.85],
	"hit": [0.25, 0.95],
	"explosion": [0.5, 0.95],
}

## 触れている間のダメージ音(ループ)の基本ゲインと、立ち上がり・消えるまでの時間(秒)
const DAMAGE_GAIN := 0.9
const DAMAGE_ATTACK := 0.03
const DAMAGE_RELEASE := 0.14
## 最後に touch_damage が呼ばれてから、触れ終わったと見なすまでの時間(秒)
const DAMAGE_HOLD := 0.07

## 発射音と、その音程の揺らし幅(± の割合)
const PITCH_JITTER := {"pop": 0.03, "clap": 0.04, "boom": 0.02, "whistle": 0.004, "tick": 0.04}
## 左右の振り幅(0..1)と、振り分けの段階(バスの数。奇数で、真ん中はマスターへそのまま送る)
const PAN_WIDTH := 0.5
const PAN_STEPS := 7
const PAN_BUS_PREFIX := "SfxPan"

## 効果音の音量(0..1)。設定値から反映する。
var volume := 0.8

## デバッグ用: 再生要求の履歴 [名前, 時刻(ms)]
var log: Array = []

var _streams := {}    # 名前 → 最初の変種(確認用)
var _variants := {}   # 名前 → [AudioStreamWAV, ...]
var _last := {}
var _lastv := {}      # 名前 → 直前に使った変種の番号
var _players: Array = []
var _next := 0
var _dmg_player: AudioStreamPlayer
var _dmg_level := 0.0       # 触れている間の音の大きさ 0..1(なめらかに出入りする)
var _dmg_hold := 0.0        # 触れていると見なす残り時間
var _dmg_urgency := 0.0


func _init() -> void:
	for nm in SPECS:
		var list := SfxBank.variants(nm)
		_variants[nm] = list
		if not list.is_empty():
			_streams[nm] = list[0]


func _ready() -> void:
	# 音楽と効果音が重なっても割れないよう、マスターにリミッターを 1 つ付ける(効果音を大きめに鳴らすため)
	if ClassDB.class_exists("AudioEffectHardLimiter"):
		var has := false
		for i in range(AudioServer.get_bus_effect_count(0)):
			if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
				has = true
		if not has:
			var lim := AudioEffectHardLimiter.new()
			lim.ceiling_db = -0.5
			AudioServer.add_bus_effect(0, lim)
	for i in range(POOL):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_ensure_pan_buses()
	var dl := SfxBank.variants("hit_loop")
	if not dl.is_empty():
		_dmg_player = AudioStreamPlayer.new()
		_dmg_player.stream = dl[0]
		add_child(_dmg_player)


## 弾に触れている間、毎フレーム呼ぶ。urgency(0..1。体力が減るほど大きい)が大きいほど、音程が少し上がる。
func touch_damage(urgency := 0.0) -> void:
	_dmg_hold = DAMAGE_HOLD
	_dmg_urgency = clampf(urgency, 0.0, 1.0)


func _process(delta: float) -> void:
	if _dmg_player == null:
		return
	_dmg_hold = maxf(_dmg_hold - delta, 0.0)
	var target := 1.0 if (_dmg_hold > 0.0 and volume > 0.0) else 0.0
	if _dmg_level < target:
		_dmg_level = minf(_dmg_level + delta / DAMAGE_ATTACK, target)
	elif _dmg_level > target:
		_dmg_level = maxf(_dmg_level - delta / DAMAGE_RELEASE, target)
	if _dmg_level <= 0.001:
		if _dmg_player.playing:
			_dmg_player.stop()
		return
	if not _dmg_player.playing:
		_dmg_player.play()
	_dmg_player.volume_db = linear_to_db(maxf(volume * DAMAGE_GAIN * _dmg_level, 0.0001))
	_dmg_player.pitch_scale = 1.0 + 0.22 * _dmg_urgency


## 左右に振るためのバス(PAN_STEPS 個。真ん中を除く)を、まだなければ作る。それぞれ AudioEffectPanner で左右の音量を変え、マスターへ送る。
static func _ensure_pan_buses() -> void:
	var half := PAN_STEPS / 2
	for k in range(PAN_STEPS):
		if k == half:
			continue
		var nm := StringName("%s%d" % [PAN_BUS_PREFIX, k])
		if AudioServer.get_bus_index(nm) >= 0:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, nm)
		AudioServer.set_bus_send(i, &"Master")
		var pn := AudioEffectPanner.new()
		pn.pan = PAN_WIDTH * float(k - half) / float(half)
		AudioServer.add_bus_effect(i, pn)


## 左右の位置(-1..1)を鳴らすバスの名前へ。
static func pan_bus(pan: float) -> StringName:
	var half := PAN_STEPS / 2
	var k := clampi(int(round((clampf(pan, -1.0, 1.0) + 1.0) * half)), 0, PAN_STEPS - 1)
	return &"Master" if k == half else StringName("%s%d" % [PAN_BUS_PREFIX, k])


func play(sfx_name: String, gain := 1.0, pan := 0.0) -> void:
	log.append([sfx_name, Time.get_ticks_msec()])
	if volume <= 0.0 or not SPECS.has(sfx_name) or _players.is_empty():
		return
	var list: Array = _variants.get(sfx_name, [])
	if list.is_empty():
		return
	var spec: Array = SPECS[sfx_name]
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last.get(sfx_name, -10.0) < spec[0]:
		return
	_last[sfx_name] = now
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	var idx := randi() % list.size()
	if list.size() > 1 and idx == int(_lastv.get(sfx_name, -1)):   # 同じ変種を続けて鳴らさない
		idx = (idx + 1 + randi() % (list.size() - 1)) % list.size()
	_lastv[sfx_name] = idx
	p.stream = list[idx]
	p.volume_db = linear_to_db(maxf(volume * spec[1] * gain, 0.0001))
	var jit: float = PITCH_JITTER.get(sfx_name, 0.0)
	p.pitch_scale = 1.0 + randf_range(-jit, jit)
	p.bus = pan_bus(pan)
	p.play()
