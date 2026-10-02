extends RefCounted
## 効果音を作るための信号処理の部品(開発用。ゲーム本体は読み込まない)。tools/sfx_forge.gd が使う。
## 音は 44.1 kHz の PackedFloat32Array(モノ)。ステレオが要るときは [左, 右] の 2 本で持つ。
## 方針: エイリアシングが出る波形は帯域制限して作る(PolyBLEP)。フィルターは RBJ の biquad。残響は Freeverb 型。
## すべて決まった乱数の種から作るので、同じ入力なら必ず同じ波形になる(ビット単位で再現できる)。

const SR := 44100
const FFT_N := 512

# --- 基本 ---

static func buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(maxi(int(dur * SR), 1))
	return b


static func rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


## dst の t0 秒の位置に src を足す(長さが足りなければ、はみ出た分は捨てる)。
static func mix_into(dst: PackedFloat32Array, src: PackedFloat32Array, t0 := 0.0, gain := 1.0) -> void:
	var o := int(round(t0 * SR))
	for i in range(src.size()):
		var j := o + i
		if j < 0:
			continue
		if j >= dst.size():
			break
		dst[j] += src[i] * gain


## 長さを dur 秒に伸ばす(後ろを無音で埋める)。
static func padded(x: PackedFloat32Array, dur: float) -> PackedFloat32Array:
	var out := x.duplicate()
	out.resize(maxi(int(dur * SR), x.size()))
	return out


static func scaled(x: PackedFloat32Array, g: float) -> PackedFloat32Array:
	var out := x.duplicate()
	for i in range(out.size()):
		out[i] *= g
	return out


static func peak(x: PackedFloat32Array) -> float:
	var m := 0.0
	for v in x:
		m = maxf(m, absf(v))
	return m


static func db(v: float) -> float:
	return 20.0 * log(maxf(v, 1e-9)) / log(10.0)


# --- 発振 ---

## 周波数が f0 から f1 へ指数的に近づく正弦波(f(t) = f1 + (f0 - f1) e^(-k t))。k が大きいほど速く落ちる。
static func sine_sweep(dur: float, f0: float, f1: float, k: float, phase0 := 0.0) -> PackedFloat32Array:
	var b := buf(dur)
	var ph := phase0
	for i in range(b.size()):
		var t := float(i) / SR
		ph += TAU * (f1 + (f0 - f1) * exp(-k * t)) / SR
		b[i] = sin(ph)
	return b


## 加法合成。ratios[i] 倍の倍音を amps[i] の大きさで、decays[i] の速さ(1/秒)で減衰させる。f0 → f1 の音程の動き(k)つき。
static func additive(dur: float, f0: float, f1: float, k: float, ratios: Array, amps: Array, decays: Array, vib_hz := 0.0, vib_depth := 0.0) -> PackedFloat32Array:
	var b := buf(dur)
	var n := ratios.size()
	var ph: Array = []
	for j in range(n):
		ph.append(0.0)
	for i in range(b.size()):
		var t := float(i) / SR
		var f := f1 + (f0 - f1) * exp(-k * t)
		if vib_hz > 0.0:
			f *= 1.0 + vib_depth * sin(TAU * vib_hz * t)
		var s := 0.0
		for j in range(n):
			ph[j] += TAU * f * float(ratios[j]) / SR
			if f * float(ratios[j]) < SR * 0.45:   # ナイキスト付近の倍音は入れない
				s += sin(ph[j]) * float(amps[j]) * exp(-float(decays[j]) * t)
		b[i] = s
	return b


## FM 合成(ベル・木琴・弦をはじく音の元)。fc: 搬送波、ratio: 変調波の周波数比、index0: 最初の変調の深さ、index_decay: 深さが減る速さ。
static func fm(dur: float, fc: float, ratio: float, index0: float, index_decay: float, amp_decay: float, f_end := 0.0, f_k := 0.0) -> PackedFloat32Array:
	var b := buf(dur)
	var pc := 0.0
	var pm := 0.0
	for i in range(b.size()):
		var t := float(i) / SR
		var f := fc if f_end <= 0.0 else f_end + (fc - f_end) * exp(-f_k * t)
		pc += TAU * f / SR
		pm += TAU * f * ratio / SR
		b[i] = sin(pc + index0 * exp(-index_decay * t) * sin(pm)) * exp(-amp_decay * t)
	return b


static func _polyblep(t: float, dt: float) -> float:
	if t < dt:
		var x := t / dt
		return x + x - x * x - 1.0
	if t > 1.0 - dt:
		var x2 := (t - 1.0) / dt
		return x2 * x2 + x2 + x2 + 1.0
	return 0.0


## 帯域制限した矩形波(PolyBLEP)。金属的な音(シンバル・ハイハット)の素材。
static func square(dur: float, freq: float, phase0 := 0.0) -> PackedFloat32Array:
	var b := buf(dur)
	var dt := freq / SR
	var ph := phase0
	for i in range(b.size()):
		var y := 1.0 if ph < 0.5 else -1.0
		y += _polyblep(ph, dt)
		y -= _polyblep(fposmod(ph + 0.5, 1.0), dt)
		b[i] = y
		ph = fposmod(ph + dt, 1.0)
	return b


## 帯域制限したのこぎり波(PolyBLEP)。
static func saw(dur: float, freq: float, phase0 := 0.0) -> PackedFloat32Array:
	var b := buf(dur)
	var dt := freq / SR
	var ph := phase0
	for i in range(b.size()):
		b[i] = 2.0 * ph - 1.0 - _polyblep(ph, dt)
		ph = fposmod(ph + dt, 1.0)
	return b


static func white(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := buf(dur)
	for i in range(b.size()):
		b[i] = r.randf() * 2.0 - 1.0
	return b


## ピンクノイズ(Paul Kellet の近似)。
static func pink(dur: float, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b := buf(dur)
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var b3 := 0.0
	var b4 := 0.0
	var b5 := 0.0
	var b6 := 0.0
	for i in range(b.size()):
		var w := r.randf() * 2.0 - 1.0
		b0 = 0.99886 * b0 + w * 0.0555179
		b1 = 0.99332 * b1 + w * 0.0750759
		b2 = 0.96900 * b2 + w * 0.1538520
		b3 = 0.86650 * b3 + w * 0.3104856
		b4 = 0.55000 * b4 + w * 0.5329522
		b5 = -0.7616 * b5 - w * 0.0168980
		b[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.11
		b6 = w * 0.115926
	return b


# --- 包絡 ---

## 立ち上がり attack 秒(なめらかな S 字)のあと、hold 秒そのままで、decay_k の速さ(1/秒)で指数的に減る。
static func env(x: PackedFloat32Array, attack: float, decay_k: float, hold := 0.0) -> PackedFloat32Array:
	var out := x.duplicate()
	for i in range(out.size()):
		var t := float(i) / SR
		var a := 1.0
		if attack > 0.0 and t < attack:
			var u := t / attack
			a = u * u * (3.0 - 2.0 * u)
		var d := 1.0 if t < hold else exp(-decay_k * (t - hold))
		out[i] *= a * d
	return out


## 頭と末尾をなめらかに閉じる(プチッというノイズを避ける)。
static func fade(x: PackedFloat32Array, in_s: float, out_s: float) -> PackedFloat32Array:
	var out := x.duplicate()
	var ni := int(in_s * SR)
	var no := int(out_s * SR)
	for i in range(mini(ni, out.size())):
		var u := float(i) / maxf(ni, 1)
		out[i] *= 0.5 - 0.5 * cos(PI * u)
	for i in range(mini(no, out.size())):
		var u2 := float(i) / maxf(no, 1)
		out[out.size() - 1 - i] *= 0.5 - 0.5 * cos(PI * u2)
	return out


# --- フィルター ---

## RBJ biquad。kind: lp / hp / bp(ピークゲイン 1)/ notch / peak / lshelf / hshelf。gain_db は peak と shelf のとき使う。
static func biquad(x: PackedFloat32Array, kind: String, f: float, q := 0.7071, gain_db := 0.0) -> PackedFloat32Array:
	var c := _coef(kind, f, q, gain_db)
	var out := PackedFloat32Array()
	out.resize(x.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in range(x.size()):
		var xn := x[i]
		var y: float = c[0] * xn + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
		x2 = x1
		x1 = xn
		y2 = y1
		y1 = y
		out[i] = y
	return out


## 周波数が時間で動く biquad(freq_fn(t 秒) -> Hz)。係数は 16 サンプルごとに更新する。
static func biquad_sweep(x: PackedFloat32Array, kind: String, freq_fn: Callable, q := 0.7071, gain_db := 0.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(x.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var c := _coef(kind, float(freq_fn.call(0.0)), q, gain_db)
	for i in range(x.size()):
		if i % 16 == 0:
			c = _coef(kind, float(freq_fn.call(float(i) / SR)), q, gain_db)
		var xn := x[i]
		var y: float = c[0] * xn + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
		x2 = x1
		x1 = xn
		y2 = y1
		y1 = y
		out[i] = y
	return out


## 係数 [b0, b1, b2, a1, a2](a0 で割り済み)。
static func _coef(kind: String, f: float, q: float, gain_db: float) -> Array:
	f = clampf(f, 20.0, SR * 0.49)
	var w0 := TAU * f / SR
	var cs := cos(w0)
	var sn := sin(w0)
	var alpha := sn / (2.0 * maxf(q, 0.05))
	var A := pow(10.0, gain_db / 40.0)
	var b0 := 1.0
	var b1 := 0.0
	var b2 := 0.0
	var a0 := 1.0
	var a1 := 0.0
	var a2 := 0.0
	match kind:
		"lp":
			b0 = (1.0 - cs) * 0.5
			b1 = 1.0 - cs
			b2 = b0
			a0 = 1.0 + alpha
			a1 = -2.0 * cs
			a2 = 1.0 - alpha
		"hp":
			b0 = (1.0 + cs) * 0.5
			b1 = -(1.0 + cs)
			b2 = b0
			a0 = 1.0 + alpha
			a1 = -2.0 * cs
			a2 = 1.0 - alpha
		"bp":
			b0 = alpha
			b1 = 0.0
			b2 = -alpha
			a0 = 1.0 + alpha
			a1 = -2.0 * cs
			a2 = 1.0 - alpha
		"notch":
			b0 = 1.0
			b1 = -2.0 * cs
			b2 = 1.0
			a0 = 1.0 + alpha
			a1 = -2.0 * cs
			a2 = 1.0 - alpha
		"peak":
			b0 = 1.0 + alpha * A
			b1 = -2.0 * cs
			b2 = 1.0 - alpha * A
			a0 = 1.0 + alpha / A
			a1 = -2.0 * cs
			a2 = 1.0 - alpha / A
		"lshelf":
			var sa := 2.0 * sqrt(A) * alpha
			b0 = A * ((A + 1.0) - (A - 1.0) * cs + sa)
			b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cs)
			b2 = A * ((A + 1.0) - (A - 1.0) * cs - sa)
			a0 = (A + 1.0) + (A - 1.0) * cs + sa
			a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cs)
			a2 = (A + 1.0) + (A - 1.0) * cs - sa
		"hshelf":
			var sb := 2.0 * sqrt(A) * alpha
			b0 = A * ((A + 1.0) + (A - 1.0) * cs + sb)
			b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cs)
			b2 = A * ((A + 1.0) + (A - 1.0) * cs - sb)
			a0 = (A + 1.0) - (A - 1.0) * cs + sb
			a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cs)
			a2 = (A + 1.0) - (A - 1.0) * cs - sb
	return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]


# --- 歪み・響き ---

## tanh の飽和。drive が大きいほど潰れる。ピークは元と同じに戻す。
static func saturate(x: PackedFloat32Array, drive: float) -> PackedFloat32Array:
	var m := maxf(peak(x), 1e-6)
	var out := PackedFloat32Array()
	out.resize(x.size())
	var m2 := 1e-6
	for i in range(x.size()):
		out[i] = tanh(x[i] / m * drive)
		m2 = maxf(m2, absf(out[i]))
	for i in range(out.size()):
		out[i] = out[i] / m2 * m
	return out


## Freeverb 型の残響。モノの入力から [左, 右] を返す。room: 0..1(広さ)、damp: 0..1(高域の吸収)、wet: 残響の混ぜ具合、tail: 余韻のために伸ばす秒数。
static func reverb(x: PackedFloat32Array, room: float, damp: float, wet: float, tail: float) -> Array:
	var n := x.size() + int(tail * SR)
	var comb_t := [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
	var ap_t := [556, 441, 341, 225]
	var fb := 0.70 + 0.28 * clampf(room, 0.0, 1.0)
	var dp := 0.4 * clampf(damp, 0.0, 1.0)
	var chans: Array = []
	for ch in range(2):
		var out := PackedFloat32Array()
		out.resize(n)
		var spread := 23 * ch
		for c in range(8):
			var len: int = comb_t[c] + spread
			var line := PackedFloat32Array()
			line.resize(len)
			var idx := 0
			var store := 0.0
			for i in range(n):
				var inp := (x[i] if i < x.size() else 0.0) * 0.015
				var o := line[idx]
				store = o * (1.0 - dp) + store * dp
				line[idx] = inp + store * fb
				idx += 1
				if idx >= len:
					idx = 0
				out[i] += o
		for a in range(4):
			var len2: int = ap_t[a] + spread
			var line2 := PackedFloat32Array()
			line2.resize(len2)
			var idx2 := 0
			for i in range(n):
				var bufout := line2[idx2]
				var input := out[i]
				out[i] = -input + bufout
				line2[idx2] = input + bufout * 0.5
				idx2 += 1
				if idx2 >= len2:
					idx2 = 0
		chans.append(out)
	var dry := x.duplicate()
	dry.resize(n)
	var l: PackedFloat32Array = chans[0]
	var r: PackedFloat32Array = chans[1]
	for i in range(n):
		var d := dry[i]
		l[i] = d + l[i] * wet * 3.0
		r[i] = d + r[i] * wet * 3.0
	return [l, r]


# --- 仕上げ ---

## 末尾の、ピークの -48 dB を下回る部分を切り落とす(残響の長い無音を、ファイルに残さない)。keep 秒は残す。
static func trim_tail(x: PackedFloat32Array, keep := 0.02) -> PackedFloat32Array:
	var m := peak(x)
	var last := x.size() - 1
	while last > 0 and absf(x[last]) < m * 0.004:
		last -= 1
	var out := x.duplicate()
	out.resize(mini(last + 1 + int(keep * SR), x.size()))
	return out


## ループ用: 定常な音 x(長さ loop_len + fade 秒以上)から、継ぎ目のない loop_len 秒の音を作る。
## 末尾の fade 秒ぶんを、先頭へ等パワーで重ねる(つなぎ目の前後が連続する)。
static func loop_crossfade(x: PackedFloat32Array, loop_len: float, fade: float) -> PackedFloat32Array:
	var n := int(loop_len * SR)
	var f := int(fade * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		out[i] = x[i]
	for i in range(f):
		var u := float(i) / float(f)
		out[i] = x[i] * sin(PI * 0.5 * u) + x[n + i] * cos(PI * 0.5 * u)
	return out


## 直流成分と超低域を除く。
static func remove_dc(x: PackedFloat32Array) -> PackedFloat32Array:
	return biquad(x, "hp", 25.0, 0.7071)


## 先読みリミッター: ピークが ceiling を超えるところだけ、少し前から滑らかに音量を下げ、そのあと release 秒で戻す。
## (tanh のように波形そのものを歪ませないので、ピークの高い音(破裂音)でも、大きさを稼ぎやすい)。
## channels は同じ倍率を掛けたい複数のチャンネル(ステレオ)。倍率は全チャンネルの最大から決める。
static func limit(channels: Array, ceiling: float, lookahead := 0.0015, release := 0.06) -> Array:
	var n: int = (channels[0] as PackedFloat32Array).size()
	var la := maxi(int(lookahead * SR), 1)
	# 各サンプルで必要な倍率(1 以下)
	var need := PackedFloat32Array()
	need.resize(n)
	for i in range(n):
		var m := 0.0
		for c in channels:
			m = maxf(m, absf((c as PackedFloat32Array)[i]))
		need[i] = 1.0 if m <= ceiling else ceiling / m
	# 先読みの窓での最小値(単調な両端キュー)
	var gmin := PackedFloat32Array()
	gmin.resize(n)
	var dq := PackedInt32Array()
	dq.resize(n + la + 2)
	var head := 0
	var tail := 0
	for i in range(n + la):
		if i < n:
			while tail > head and need[dq[tail - 1]] >= need[i]:
				tail -= 1
			dq[tail] = i
			tail += 1
		var out_i := i - la
		if out_i >= 0:
			while dq[head] < out_i:
				head += 1
			gmin[out_i] = need[dq[head]]
	# 窓の最小値を、過去へ向かう移動平均でなめらかに(ピークに着くころに、ちょうど必要な倍率まで下がる)
	var sm := PackedFloat32Array()
	sm.resize(n)
	var acc := 0.0
	for i in range(n):
		acc += gmin[i]
		if i > la:
			acc -= gmin[i - la - 1]
		sm[i] = acc / float(mini(i, la) + 1)
	# 戻りはゆっくり(release)、下がるのは即座
	var coef := 1.0 - exp(-1.0 / (release * SR))
	var g := 1.0
	var gain := PackedFloat32Array()
	gain.resize(n)
	for i in range(n):
		g = minf(sm[i], g + (1.0 - g) * coef)
		gain[i] = g
	var out: Array = []
	for c in channels:
		var src: PackedFloat32Array = c
		var dst := PackedFloat32Array()
		dst.resize(n)
		for i in range(n):
			dst[i] = src[i] * gain[i]
		out.append(dst)
	return out


## 最も大きい窓(win 秒)の平均の大きさ(dBFS)。耳に近づけるため、150 Hz 以下を落としてから測る。
static func loudness_db(x: PackedFloat32Array, win := 0.1) -> float:
	var f := biquad(x, "hp", 150.0, 0.7071)
	var w := maxi(int(win * SR), 1)
	var step := maxi(int(0.01 * SR), 1)
	var best := 0.0
	var i := 0
	while i < f.size():
		var e := 0.0
		var n := mini(w, f.size() - i)
		for j in range(n):
			e += f[i + j] * f[i + j]
		best = maxf(best, e / float(w))
		i += step
	return 10.0 * log(maxf(best, 1e-12)) / log(10.0)


## 聴感上の大きさ(loudness_db)を target_db にそろえる。ピークが ceiling を超えるぶんは、やわらかく丸める。
static func normalize(x: PackedFloat32Array, target_db: float, ceiling := 0.95) -> PackedFloat32Array:
	var cur := loudness_db(x)
	var g := pow(10.0, (target_db - cur) / 20.0)
	var out := scaled(x, g)
	var p := peak(out)
	if p > ceiling:
		# ceiling で tanh に近づける(ceiling 以下はほぼそのまま)。丸めたあと、また大きさを合わせ直す
		for pass_i in range(3):
			for i in range(out.size()):
				out[i] = ceiling * tanh(out[i] / ceiling)
			var c2 := loudness_db(out)
			var g2 := pow(10.0, (target_db - c2) / 20.0)
			if absf(c2 - target_db) < 0.15:
				break
			out = scaled(out, g2)
			if peak(out) <= ceiling:
				break
		var p2 := peak(out)
		if p2 > ceiling:
			out = scaled(out, ceiling / p2)
	return out


# --- 書き出し ---

## 16 bit PCM の WAV(RIFF)にする。right が空ならモノ。
static func wav_bytes(left: PackedFloat32Array, right := PackedFloat32Array()) -> PackedByteArray:
	var ch := 1 if right.is_empty() else 2
	var n := left.size()
	var data_len := n * ch * 2
	var b := PackedByteArray()
	b.resize(44 + data_len)
	b.encode_u32(0, 0x46464952)   # "RIFF"
	b.encode_u32(4, 36 + data_len)
	b.encode_u32(8, 0x45564157)   # "WAVE"
	b.encode_u32(12, 0x20746d66)  # "fmt "
	b.encode_u32(16, 16)
	b.encode_u16(20, 1)
	b.encode_u16(22, ch)
	b.encode_u32(24, SR)
	b.encode_u32(28, SR * ch * 2)
	b.encode_u16(32, ch * 2)
	b.encode_u16(34, 16)
	b.encode_u32(36, 0x61746164)  # "data"
	b.encode_u32(40, data_len)
	var o := 44
	for i in range(n):
		b.encode_s16(o, int(round(clampf(left[i], -1.0, 1.0) * 32767.0)))
		o += 2
		if ch == 2:
			b.encode_s16(o, int(round(clampf(right[i], -1.0, 1.0) * 32767.0)))
			o += 2
	return b


# --- 解析(確認用) ---

## 簡易 FFT(基数 2)。re / im を直接書き換える。
static func fft(re: PackedFloat32Array, im: PackedFloat32Array) -> void:
	var n := re.size()
	var j := 0
	for i in range(1, n):
		var bit := n >> 1
		while j & bit:
			j ^= bit
			bit >>= 1
		j ^= bit
		if i < j:
			var tr := re[i]
			re[i] = re[j]
			re[j] = tr
			var ti := im[i]
			im[i] = im[j]
			im[j] = ti
	var len := 2
	while len <= n:
		var ang := -TAU / float(len)
		var wr := cos(ang)
		var wi := sin(ang)
		var i2 := 0
		while i2 < n:
			var cr := 1.0
			var ci := 0.0
			for k in range(len >> 1):
				var a := i2 + k
				var b2 := i2 + k + (len >> 1)
				var xr := re[b2] * cr - im[b2] * ci
				var xi := re[b2] * ci + im[b2] * cr
				re[b2] = re[a] - xr
				im[b2] = im[a] - xi
				re[a] += xr
				im[a] += xi
				var ncr := cr * wr - ci * wi
				ci = cr * wi + ci * wr
				cr = ncr
			i2 += len
		len <<= 1


## スペクトル重心(Hz。エネルギーの重み付き平均周波数)。音の明るさの目安。
static func centroid_hz(x: PackedFloat32Array) -> float:
	var num := 0.0
	var den := 1e-12
	var hop := FFT_N / 2
	var i := 0
	while i + FFT_N <= x.size():
		var re := PackedFloat32Array()
		var im := PackedFloat32Array()
		re.resize(FFT_N)
		im.resize(FFT_N)
		for k in range(FFT_N):
			re[k] = x[i + k] * (0.5 - 0.5 * cos(TAU * k / FFT_N))
		fft(re, im)
		for k in range(1, FFT_N / 2):
			var m := re[k] * re[k] + im[k] * im[k]
			num += m * float(k) * SR / FFT_N
			den += m
		i += hop
	return num / den


## スペクトログラム(縦: 周波数 40 Hz〜16 kHz の対数軸、横: 時間)と、その下に波形を 1 枚の画像にする。確認用。
## 末尾の無音に近い部分は省く(ピークの -60 dB を下回ったところまで)。
static func spectrogram(x: PackedFloat32Array, width := 720, height := 260) -> Image:
	var n_fft := 1024
	var m := maxf(peak(x), 1e-6)
	var last := x.size() - 1
	while last > 0 and absf(x[last]) < m * 0.001:
		last -= 1
	var len := mini(last + int(0.01 * SR), x.size())
	var hop := maxi((len - n_fft) / maxi(width - 1, 1), 1)
	var cols := mini((len - n_fft) / hop + 1, width) if len > n_fft else 1
	var img := Image.create(width, height + 60, false, Image.FORMAT_RGB8)
	img.fill(Color(0.02, 0.02, 0.05))
	var cells: Array = []
	var top := -200.0
	var bin_hz := float(SR) / n_fft
	var rows := PackedInt32Array()   # 画像の行 → FFT のビン(対数軸)
	rows.resize(height)
	for py in range(height):
		var f := 40.0 * pow(16000.0 / 40.0, float(height - 1 - py) / float(height - 1))
		rows[py] = clampi(int(round(f / bin_hz)), 1, n_fft / 2 - 1)
	for c in range(cols):
		var re := PackedFloat32Array()
		var im := PackedFloat32Array()
		re.resize(n_fft)
		im.resize(n_fft)
		for k in range(n_fft):
			var idx := c * hop + k
			re[k] = (x[idx] if idx < x.size() else 0.0) * (0.5 - 0.5 * cos(TAU * k / n_fft))
		fft(re, im)
		var col := PackedFloat32Array()
		col.resize(n_fft / 2)
		for k in range(1, n_fft / 2):
			var mag := db(sqrt(re[k] * re[k] + im[k] * im[k]) / n_fft * 4.0)
			col[k] = mag
			top = maxf(top, mag)
		cells.append(col)
	for c in range(cols):
		var x0 := int(float(c) / cols * width)
		var x1 := maxi(int(float(c + 1) / cols * width), x0 + 1)
		var col: PackedFloat32Array = cells[c]
		for py in range(height):
			var v := clampf((col[rows[py]] - (top - 75.0)) / 75.0, 0.0, 1.0)
			var color := Color.from_hsv(0.72 - 0.72 * v, 0.85, v * 0.95)
			for px in range(x0, mini(x1, width)):
				img.set_pixel(px, py, color)
	# 周波数の目盛り(100 / 1k / 10k Hz)
	for f2 in [100.0, 1000.0, 10000.0]:
		var py2 := int(round((1.0 - log(f2 / 40.0) / log(16000.0 / 40.0)) * float(height - 1)))
		for px2 in range(0, 12):
			img.set_pixel(px2, clampi(py2, 0, height - 1), Color(1, 1, 1, 1))
	# 波形
	var mid := height + 30
	for px in range(width):
		var a2 := int(float(px) / width * len)
		var b2 := mini(int(float(px + 1) / width * len) + 1, len)
		var lo := 0.0
		var hi := 0.0
		for i in range(a2, b2):
			lo = minf(lo, x[i])
			hi = maxf(hi, x[i])
		for py in range(mid - int(hi / m * 28.0), mid - int(lo / m * 28.0) + 1):
			img.set_pixel(px, clampi(py, height, height + 59), Color(0.5, 0.9, 1.0))
	return img
