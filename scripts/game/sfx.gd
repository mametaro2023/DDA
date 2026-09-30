extends Node
## 効果音。外部素材なしで波形をコードから合成し、ボイスプール経由で再生する。

const RATE := 22050
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

## 弾幕の発射音(風船が割れる音)。3 種類の波形からランダムに選び、さらに音程も少し揺らして、同じ音の繰り返しに聞こえないようにする。被弾・爆発は揺らさない
const BARRAGE := ["pop", "whistle", "clap", "boom", "tick"]
const VARIANTS := 3

## 効果音の音量(0..1)。設定値から反映する。
var volume := 0.8

## デバッグ用: 再生要求の履歴 [名前, 時刻(ms)]
var log: Array = []

var _streams := {}
var _variants := {}   # 名前 → [AudioStreamWAV, ...](発射音は VARIANTS 種類)
var _last := {}
var _players: Array = []
var _next := 0
var _seed := 12345


func _init() -> void:
	for nm in BARRAGE:
		var list: Array = []
		for k in range(VARIANTS):
			list.append(_make(call("_" + nm, k)))
		_variants[nm] = list
		_streams[nm] = list[0]
	_streams["hit"] = _make(_hit())
	_streams["explosion"] = _make(_explosion())


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


func play(sfx_name: String, gain := 1.0) -> void:
	log.append([sfx_name, Time.get_ticks_msec()])
	if volume <= 0.0 or not _streams.has(sfx_name) or _players.is_empty():
		return
	var spec: Array = SPECS[sfx_name]
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last.get(sfx_name, -10.0) < spec[0]:
		return
	_last[sfx_name] = now
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _variants[sfx_name].pick_random() if _variants.has(sfx_name) else _streams[sfx_name]
	p.volume_db = linear_to_db(maxf(volume * spec[1] * gain, 0.0001))
	p.pitch_scale = randf_range(0.94, 1.08) if BARRAGE.has(sfx_name) else 1.0
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


# --- 弾幕の発射音: 風船が割れる音 ---
# 風船の破裂 = (1) 極端に鋭い広帯域の衝撃 (2) ゴム膜が弾ける短いスナップ(ピッチが落ちる) (3) ラテックスの中高域の色付け
# (4) 空気の「ボッ」という低い胴鳴り (5) 破片がバラバラと鳴る短いクラックル。大きい風船ほど低く長く、小さい風船ほど高く短い。
# ノイズだけでは「ボフッ」とくぐもるので、(2) のピッチ降下を足して「ペチッ」「ポンッ」という弾け感にする。
# 高い音程のサイン波は長く使わない(伸ばすと「キュッ」になるので 10〜20ms で切る)。

var _hp_prev := 0.0


## 高域のノイズ(直前の値との差 = 簡単なハイパス)。
func _hnoise() -> float:
	var n := _noise()
	var d := n - _hp_prev
	_hp_prev = n
	return d * 0.6


## ノイズの破裂を t0 秒から足す。decay が大きいほど短く鋭い。lp が大きいほどこもった音、0 で白色ノイズ。
func _add_noise(b: PackedFloat32Array, dur: float, decay: float, amp: float, t0 := 0.0, lp := 0.0) -> void:
	var i0 := int(t0 * RATE)
	var y := 0.0
	for i in range(i0, mini(i0 + int(dur * RATE), b.size())):
		y = lp * y + (1.0 - lp) * _noise()
		b[i] += y * exp(-float(i - i0) / RATE * decay) * amp


## 中高域の広い響き: ノイズを共振フィルタ(周波数 freq、r が 1 に近いほど鋭い)に通す。低い r では音程は感じず「ペチッ」という音の色になる。
func _add_band(b: PackedFloat32Array, t0: float, dur: float, freq: float, r: float, decay: float, amp: float) -> void:
	var i0 := int(t0 * RATE)
	var a1 := 2.0 * r * cos(TAU * freq / RATE)
	var a2 := -r * r
	var y1 := 0.0
	var y2 := 0.0
	for i in range(i0, mini(i0 + int(dur * RATE), b.size())):
		var x := _noise() * exp(-float(i - i0) / RATE * decay)
		var y := x + a1 * y1 + a2 * y2
		y2 = y1
		y1 = y
		b[i] += y * (1.0 - r) * amp


## 破片のクラックル: まばらな短いクリックが、だんだん少なくなりながら鳴る。
func _add_crackle(b: PackedFloat32Array, t0: float, dur: float, rate_hz: float, decay: float, amp: float) -> void:
	var i0 := int(t0 * RATE)
	var env := 0.0
	for i in range(i0, mini(i0 + int(dur * RATE), b.size())):
		var t := float(i - i0) / RATE
		if _noise() * 0.5 + 0.5 < rate_hz * exp(-t * decay) / RATE:
			env = amp * (0.4 + 0.6 * (_noise() * 0.5 + 0.5))
		b[i] += _hnoise() * env
		env *= 0.72


## 低い胴鳴り(ボッ)を t0 秒から足す。周波数は freq × (1 + sweep × exp(-decay × t))(sweep > 0 で下がる)。低い音だけに使う。
func _add_thump(b: PackedFloat32Array, t0: float, freq: float, decay: float, amp: float, sweep := 0.0) -> void:
	var i0 := int(t0 * RATE)
	var phase := 0.0
	for i in range(i0, mini(i0 + int(5.0 / decay * RATE), b.size())):
		var t := float(i - i0) / RATE
		phase += TAU * freq * (1.0 + sweep * exp(-decay * t)) / RATE
		b[i] += sin(phase) * exp(-decay * t) * minf(t * 1500.0, 1.0) * amp


## ゴム膜が弾けるスナップ: 周波数が f0 → f1 へ指数的に落ちる短い音。「弾ける」感じの核。
## 長く鳴らすと「キュッ」という音程になるので dur(10〜20ms 程度)で切る。低い倍音を少し混ぜてゴムっぽくする。
func _add_snap(b: PackedFloat32Array, t0: float, f0: float, f1: float, dur: float, decay: float, amp: float) -> void:
	var i0 := int(t0 * RATE)
	var phase := 0.0
	var ratio := f1 / maxf(f0, 1.0)
	for i in range(i0, mini(i0 + int(dur * RATE), b.size())):
		var t := float(i - i0) / RATE
		var frac := t / maxf(dur, 1e-6)
		var freq := f0 * pow(ratio, frac)
		phase += TAU * freq / RATE
		var env := exp(-t * decay) * minf(t * 8000.0, 1.0)
		b[i] += (sin(phase) + 0.35 * sin(phase * 2.0)) * env * amp


## 風船 1 個の破裂を t0 秒から足す。sz = 風船の大きさ(1 が標準。小さいほど高く短く、大きいほど低く長い)、jit = 響きの高さの個体差。
func _add_balloon(b: PackedFloat32Array, t0: float, sz: float, amp: float, jit := 1.0) -> void:
	_add_noise(b, 0.004, 900.0, 1.7 * amp, t0)                                        # (1) 鋭い衝撃(短く強く)
	_add_snap(b, t0, 3000.0 * jit / sz, 750.0 / sz, 0.018 * sz, 220.0 / sz, 0.7 * amp)  # (2) 膜のスナップ(弾け感)
	_add_band(b, t0, 0.05 * sz, 2300.0 * jit / sz, 0.86, 140.0 / sz, 0.8 * amp)         # (3) ラテックスの色付け(短め・共振は弱く)
	_add_band(b, t0, 0.025 * sz, 4800.0 * jit / sz, 0.82, 250.0 / sz, 0.55 * amp)       #     同(高域)
	_add_thump(b, t0, 150.0 / sz, 55.0 / sz, 0.4 * amp, 1.0)                             # (4) 空気の胴鳴り(短く)
	_add_crackle(b, t0 + 0.003, 0.07 * sz, 1200.0, 55.0 / sz, 0.6 * amp)                # (5) 破片のクラックル
	_add_noise(b, 0.08 * sz, 22.0 / sz, 0.12 * amp, t0 + 0.005, 0.70)                   # (6) 空気が抜ける余韻(薄く短く)


## 部屋の響き: 少し遅れて小さくなる反射を足す。強くすると二度目の山ができて「ボワッ」とするので、発射音では薄く使う。
func _room(b: PackedFloat32Array, amount := 0.35) -> void:
	var src := b.duplicate()
	for echo in [[0.011, 0.25], [0.023, 0.16], [0.041, 0.10], [0.065, 0.06], [0.095, 0.035]]:
		var d := int(echo[0] * RATE)
		for i in range(d, b.size()):
			b[i] += src[i - d] * echo[1] * amount


## 最大振幅を peak に揃え、軽く飽和させて(tanh)音圧を上げる。飽和のあとで、もう一度 peak に揃える。
## 短い破裂は、ピークが同じでも聴感上は小さく聞こえるため、平均の大きさ(RMS)を稼ぐ。
## drive が大きいほど RMS は稼げるが、先頭の衝撃が潰れて「弾け感」が減るので、発射音では控えめにする。
func _norm(b: PackedFloat32Array, peak := 0.95, drive := 1.9) -> PackedFloat32Array:
	var m := 0.0001
	for v in b:
		m = maxf(m, absf(v))
	var m2 := 0.0001
	for i in range(b.size()):
		b[i] = tanh(b[i] / m * drive)
		m2 = maxf(m2, absf(b[i]))
	for i in range(b.size()):
		b[i] = b[i] / m2 * peak
	return b


## 基本の発射音: 標準の風船 1 個。k = バリエーション番号(響きの高さを少し変える)。
func _pop(k := 0) -> PackedFloat32Array:
	var b := _buf(0.26)
	_add_balloon(b, 0.0, 1.0, 1.0, 1.0 + 0.08 * (k - 1))
	_room(b, 0.35)
	return _norm(b)


## 小さく明るい風船「パチッ」。
func _whistle(k := 0) -> PackedFloat32Array:
	var b := _buf(0.20)
	_add_balloon(b, 0.0, 0.65, 1.0, 1.0 + 0.08 * (k - 1))
	_room(b, 0.25)
	return _norm(b)


## 2 個ほぼ同時に割れる「パンッパンッ」。
func _clap(k := 0) -> PackedFloat32Array:
	var b := _buf(0.28)
	_add_balloon(b, 0.0, 0.9, 1.0, 1.0 + 0.08 * (k - 1))
	_add_balloon(b, 0.017, 0.72, 0.8, 1.0 + 0.08 * (1 - k))
	_room(b, 0.35)
	return _norm(b)


## 大きな風船「バァン」+ 続けてパラパラ割れる小さな風船。
func _boom(k := 0) -> PackedFloat32Array:
	var b := _buf(0.65)
	_add_balloon(b, 0.0, 1.7, 1.0, 1.0 + 0.06 * (k - 1))
	for j in range(5):
		_add_balloon(b, 0.035 + 0.026 * j, 0.6 + 0.07 * float((j * 3 + k) % 4), 0.42 - 0.05 * j)
	_room(b, 0.7)
	return _norm(b)


## 細かい連射の音: ごく小さな風船「ペチッ」。
func _tick(k := 0) -> PackedFloat32Array:
	var b := _buf(0.16)
	_add_balloon(b, 0.0, 0.45, 0.9, 1.0 + 0.08 * (k - 1))
	_room(b, 0.2)
	return _norm(b)


func _hit() -> PackedFloat32Array:
	var b := _buf(0.4)
	var phase := 0.0
	var y := 0.0
	for i in range(b.size()):
		var t := float(i) / RATE
		phase += (60.0 + 260.0 * exp(-t * 9.0)) / RATE
		y = 0.5 * y + 0.5 * _noise()
		var saw := fposmod(phase, 1.0) * 2.0 - 1.0
		b[i] = (saw * 0.5 + y * 0.6) * exp(-t * 9.0)
	return b


func _explosion() -> PackedFloat32Array:
	var b := _buf(1.2)
	var phase := 0.0
	var y := 0.0
	for i in range(b.size()):
		var t := float(i) / RATE
		# 低音の胴鳴り + 徐々に暗くなるノイズ + 冒頭の破裂音
		phase += TAU * (28.0 + 60.0 * exp(-t * 3.0)) / RATE
		var c := 0.5 + 0.48 * (1.0 - exp(-t * 6.0))
		y = c * y + (1.0 - c) * _noise()
		var crack := _noise() * exp(-t * 60.0) * 0.8
		var body := sin(phase) * exp(-t * 3.5) * 0.9
		var rumble := y * exp(-t * 4.5) * 1.6
		b[i] = tanh(body + rumble + crack)
	return b
