extends Node
## UI の効果音(ホバー・クリック・選択・開閉・スタンプなど)。外部素材なしで、波形をコードから合成する。
## ゲーム中の弾の音(game/sfx.gd)とは別。ガラスや木の小さな玉を弾くような、短く丸い音で揃える(耳に刺さる高い音・長い余韻は使わない)。
## 使い方: UiSfx.play("click")。pitch で音程を、gain で大きさを変える(選択の ↑↓ で音程を上げ下げするなど)。
## 音量は「効果音」の設定(Volume.sfx)に従い、設定の「UI の音」を切ると鳴らない。

const Volume = preload("res://scripts/volume.gd")

const RATE := 32000
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
var _seed := 777


func _init() -> void:
	_streams["hover"] = _make(_hover())
	_streams["click"] = _make(_click())
	_streams["select"] = _make(_select())
	_streams["confirm"] = _make(_confirm())
	_streams["back"] = _make(_back())
	_streams["open"] = _make(_sweep(0.22, 380.0, 1100.0, 0.5))
	_streams["close"] = _make(_sweep(0.18, 900.0, 320.0, 0.45))
	_streams["on"] = _make(_blip([620.0, 930.0], 0.07, 0.9))
	_streams["off"] = _make(_blip([700.0, 470.0], 0.07, 0.9))
	_streams["tick"] = _make(_tone(0.022, 2600.0, 2600.0, 120.0, 0.6))
	_streams["stamp"] = _make(_stamp())
	_streams["whoosh"] = _make(_whoosh())
	_streams["toast"] = _make(_blip([1175.0, 1568.0], 0.09, 0.6))
	_streams["deny"] = _make(_tone(0.16, 230.0, 170.0, 14.0, 0.7, 0.25))
	_streams["count"] = _make(_tone(0.03, 1900.0, 2100.0, 90.0, 0.55))


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


# --- 合成 ---

func _make(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _noise() -> float:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return float(_seed) / 1073741823.5 - 1.0


func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	return b


## 丸い音の玉: f0 → f1 へ音程が動く正弦波(+ 2 倍音を harm だけ)。decay が大きいほど早く消える。立ち上がりに 2ms かけて、プチッというノイズを避ける。
func _tone(dur: float, f0: float, f1: float, decay: float, amp: float, harm := 0.18) -> PackedFloat32Array:
	var b := _buf(dur)
	var phase := 0.0
	for i in range(b.size()):
		var t := float(i) / RATE
		var f := lerpf(f0, f1, clampf(t / dur, 0.0, 1.0))
		phase += TAU * f / RATE
		var env := exp(-t * decay) * minf(t / 0.002, 1.0)
		env *= clampf((dur - t) / 0.004, 0.0, 1.0)   # 終わりも 4ms でなめらかに閉じる
		b[i] = (sin(phase) + sin(phase * 2.0) * harm) * env * amp
	return b


## 同じ長さの玉をつなげた短い旋律(上がる / 下がる)。
func _blip(freqs: Array, each: float, amp: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in range(freqs.size()):
		var f: float = freqs[i]
		out.append_array(_tone(each * (1.7 if i == freqs.size() - 1 else 1.0), f, f * 1.01, 22.0, amp * 0.55))
	return out


func _hover() -> PackedFloat32Array:
	return _tone(0.04, 1900.0, 2150.0, 70.0, 0.55, 0.08)


func _click() -> PackedFloat32Array:
	var b := _tone(0.085, 980.0, 600.0, 32.0, 0.55, 0.3)
	# 触った瞬間のコツッという粒
	for i in range(int(0.006 * RATE)):
		b[i] += _noise() * exp(-float(i) / RATE * 700.0) * 0.18
	return b


func _select() -> PackedFloat32Array:
	return _tone(0.06, 1250.0, 1300.0, 55.0, 0.6, 0.12)


func _confirm() -> PackedFloat32Array:
	var b := _tone(0.07, 700.0, 740.0, 24.0, 0.5)
	b.append_array(_tone(0.07, 880.0, 920.0, 24.0, 0.5))
	b.append_array(_tone(0.2, 1175.0, 1190.0, 16.0, 0.55, 0.25))
	return b


func _back() -> PackedFloat32Array:
	return _tone(0.11, 820.0, 480.0, 26.0, 0.55, 0.2)


## 上がる / 下がる風切り音(ローパスをかけたノイズ + 薄い正弦波)。パネルの開閉用。
func _sweep(dur: float, f0: float, f1: float, amp: float) -> PackedFloat32Array:
	var b := _buf(dur)
	var y := 0.0
	var phase := 0.0
	for i in range(b.size()):
		var t := float(i) / RATE
		var k := t / dur
		var f := lerpf(f0, f1, k * k if f1 > f0 else sqrt(k))
		var env := sin(PI * clampf(k, 0.0, 1.0))
		y += clampf(f / 5200.0, 0.02, 0.9) * (_noise() - y)
		phase += TAU * f * 0.5 / RATE
		b[i] = (y * 0.9 + sin(phase) * 0.25) * env * amp
	return b


func _whoosh() -> PackedFloat32Array:
	var dur := 0.34
	var b := _buf(dur)
	var y := 0.0
	var y2 := 0.0
	for i in range(b.size()):
		var t := float(i) / RATE
		var k := t / dur
		var f := lerpf(250.0, 2600.0, k * k) if k < 0.55 else lerpf(2600.0, 500.0, (k - 0.55) / 0.45)
		var a := clampf(f / 6000.0, 0.01, 0.8)
		y += a * (_noise() - y)
		y2 += a * (y - y2)   # 2 段のローパス(角を丸める)
		b[i] = y2 * 2.2 * pow(sin(PI * k), 1.4) * 0.5
	return b


## スタンプ(ランクの確定): 低い胴鳴り(音程が落ちる)+ 短い衝撃 + 明るい 1 音。
func _stamp() -> PackedFloat32Array:
	var b := _tone(0.4, 130.0, 48.0, 9.0, 0.95, 0.3)
	for i in range(int(0.05 * RATE)):
		b[i] += _noise() * exp(-float(i) / RATE * 90.0) * 0.45
	var bell := _tone(0.3, 1320.0, 1320.0, 11.0, 0.3, 0.4)
	for i in range(bell.size()):
		b[i] += bell[i]
	return b
