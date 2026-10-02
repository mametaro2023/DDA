extends RefCounted
## 効果音のレシピ(開発用)。1 つの音は「部品を重ねて、フィルターをかけ、響きを足し、大きさをそろえる」関数で作る。
## render(名前, 番号) が { l: 左, r: 右(モノなら空) } を返す。番号は同じ音の変種(乱数の種と音色を少しずつ変える)。
##
## ## ゲームの音(osu! のヒットサウンドの役割に合わせつつ、気持ちよさを優先して作った)
##   pop     … ふつうの弾(normal)    : 打撃音「タッ」。鋭く立ち上がり、約 60 ms で消える。響きなし(連打しても濁らない)
##   whistle … 口笛(whistle)         : 明るい口笛「ピッ」。上がって伸びる。頭に小さな打音
##   clap    … 手拍子(clap)          : 4 つの短いノイズ粒が重なる「パッ」。部屋の響きつき
##   boom    … 大きな弾(finish)      : 重い衝撃「ドンッ」。深いサブ + 芯のある打撃 + 乾いた破裂 + きらめき。ステレオ
##   tick    … 細かい弾(スライダーの途中) : 木の小さな粒「コッ」。E マイナーペンタトニックの 6 音を変種ごとに鳴らす(きらきらした粒)
##   hit     … 弾に触れた瞬間          : 短く鋭い電気的な「ツッ」(上から落ちる音程 + ぱちっという粒)
##   hit_loop… 弾に触れている間(ループ): 電気が焼けるような「ジジジ…」。継ぎ目のない 0.5 秒。ダメージが続く間、鳴り続ける
##   explosion … ゲームオーバー      : 低い地鳴り + 暗くなるノイズ + 大きな響き。ステレオ
## ## UI の音(hover / click / ...)
##   木琴・カリンバ・ベルのような、丸くて短い音。耳に刺さる高い音・長い余韻は使わない。音程は実行時に pitch で上下させる

const D = preload("res://tools/dsp.gd")

## 名前 → [変種の数, 目標の大きさ(dBFS。最も大きい 100ms の平均)、ピークの上限, (任意)"loop" = ループ再生する音]
const SPEC := {
	"pop": [6, -14.0, 0.95],
	"whistle": [6, -17.0, 0.92],
	"clap": [6, -14.0, 0.92],
	"boom": [4, -13.0, 0.95],
	"tick": [6, -19.0, 0.9],
	"hit": [3, -13.0, 0.95],
	"hit_loop": [1, -19.0, 0.9, "loop"],
	"explosion": [1, -11.3, 0.97],
	"hover": [1, -18.0, 0.8],
	"click": [1, -16.5, 0.85],
	"select": [1, -17.0, 0.85],
	"confirm": [1, -16.5, 0.9],
	"back": [1, -17.0, 0.85],
	"open": [1, -20.0, 0.8],
	"close": [1, -20.0, 0.8],
	"on": [1, -17.0, 0.85],
	"off": [1, -17.0, 0.85],
	"tick_ui": [1, -17.5, 0.85],
	"stamp": [1, -14.0, 0.95],
	"whoosh": [1, -21.0, 0.8],
	"toast": [1, -19.0, 0.85],
	"deny": [1, -15.0, 0.85],
	"count": [1, -18.0, 0.85],
}


## 名前と番号から、音を作る。
static func render(sfx_name: String, k: int) -> Dictionary:
	var seed_value: int = hash(sfx_name) + k * 7919 + 12345
	var r := D.rng(seed_value)
	var out: Dictionary = {"l": PackedFloat32Array(), "r": PackedFloat32Array()}
	match sfx_name:
		"pop": out.l = _pop(r, k)
		"whistle": out.l = _whistle(r, k)
		"clap": out.l = _clap(r, k)
		"boom": out = _boom(r, k)
		"tick": out.l = _tick(r, k)
		"hit": out = _hit(r, k)
		"hit_loop": out.l = _hit_loop(r)
		"explosion": out = _explosion(r)
		"hover": out.l = _hover()
		"click": out.l = _click(r)
		"select": out.l = _select()
		"confirm": out = _confirm()
		"back": out.l = _back()
		"open": out = _open(r)
		"close": out = _close(r)
		"on": out.l = _on_off(true)
		"off": out.l = _on_off(false)
		"tick_ui": out.l = _tick_ui(r)
		"stamp": out = _stamp(r)
		"whoosh": out = _whoosh(r)
		"toast": out = _toast()
		"deny": out.l = _deny()
		"count": out.l = _count()
		_:
			push_error("知らない音: " + sfx_name)
	return _finish(sfx_name, out)


## 仕上げ: 直流と超低域を除き、頭と末尾を閉じ、大きさをそろえる(左右は同じ倍率)。
static func _finish(sfx_name: String, s: Dictionary) -> Dictionary:
	var spec: Array = SPEC[sfx_name]
	var is_loop: bool = spec.size() > 3 and spec[3] == "loop"
	var l: PackedFloat32Array = D.remove_dc(s.l) if not is_loop else (s.l as PackedFloat32Array).duplicate()
	var rr: PackedFloat32Array = D.remove_dc(s.r) if not (s.r as PackedFloat32Array).is_empty() else PackedFloat32Array()
	# 左右とも、同じ長さで末尾の無音を切り落とす(ループの音は、継ぎ目のためそのまま)
	var longest := 0
	for ch in ([l, rr] if not rr.is_empty() else [l]):
		var t2: PackedFloat32Array = D.trim_tail(ch) if not is_loop else ch
		longest = maxi(longest, t2.size())
	l.resize(mini(longest, l.size()))
	if not rr.is_empty():
		rr.resize(mini(longest, rr.size()))
	var tail := 0.012 if l.size() < D.SR * 0.5 else 0.06
	if not is_loop:
		l = D.fade(l, 0.0004, tail)
		if not rr.is_empty():
			rr = D.fade(rr, 0.0004, tail)
	# 大きさは左右を足した形で測り、同じ倍率を両方にかける。ピークが上限を超えるところは、リミッターで押さえる
	# (押さえると少し小さくなるので、目標の大きさになるまで倍率を合わせ直す)
	var ceil_v: float = spec[2]
	var chans: Array = [l] if rr.is_empty() else [l, rr]
	var g := 1.0
	var out_ch: Array = chans
	for pass_i in range(5):
		var scaled_ch: Array = []
		for c in chans:
			scaled_ch.append(D.scaled(c, g))
		out_ch = D.limit(scaled_ch, ceil_v)
		var probe := (out_ch[0] as PackedFloat32Array).duplicate()
		if out_ch.size() == 2:
			for i in range(probe.size()):
				probe[i] = (out_ch[0][i] + out_ch[1][i]) * 0.5
		var cur := D.loudness_db(probe)
		var diff := float(spec[1]) - cur
		if absf(diff) < 0.1:
			break
		g *= pow(10.0, diff / 20.0)
	return {"l": out_ch[0], "r": out_ch[1] if out_ch.size() == 2 else PackedFloat32Array()}


# --- 部品 ---

## 短いノイズの粒(帯域通過)。
static func _burst(r: RandomNumberGenerator, dur: float, f: float, q: float, decay: float, hp := 0.0) -> PackedFloat32Array:
	var n := D.white(dur, r)
	if hp > 0.0:
		n = D.biquad(n, "hp", hp, 0.7071)
	n = D.biquad(n, "bp", f, q)
	return D.env(n, 0.0003, decay)


## 808 のシンバル / ハイハットの素材: 比のずれた 6 つの周波数の帯域制限矩形波を重ねる(scale 倍の高さ)。
const METAL := [205.3, 304.4, 369.6, 522.7, 540.0, 800.0]


static func _metal(dur: float, scale: float, picks: Array) -> PackedFloat32Array:
	var out := D.buf(dur)
	for j in picks:
		D.mix_into(out, D.square(dur, float(METAL[j]) * scale, 0.13 * float(j)), 0.0, 0.2)
	return out


# --- ゲームの音 ---

## ふつうの弾: 打撃音。立ち上がりが鋭く、約 60 ms で消える「タッ」。
## 素早く落ちる音程の胴(正弦波)+ 上乗せの短い芯 + 先頭の硬い打撃音(クリック)+ 短い帯域ノイズ。飽和で芯を太くする。響きは足さない(連打しても濁らない)。
static func _pop(r: RandomNumberGenerator, k: int) -> PackedFloat32Array:
	var jit := 1.0 + 0.08 * (r.randf() * 2.0 - 1.0) + 0.012 * k
	var dur := 0.11
	var body := D.sine_sweep(dur, 820.0 * jit, 255.0 * jit, 170.0)
	body = D.env(body, 0.0002, 62.0)
	var snap := D.sine_sweep(0.05, 1700.0 * jit, 450.0 * jit, 220.0)
	snap = D.env(snap, 0.0002, 110.0)
	var click := _burst(r, 0.005, 4800.0, 0.8, 1100.0, 2000.0)
	var crack := _burst(r, 0.05, 2600.0 * jit, 0.9, 85.0, 700.0)
	var s := D.buf(dur)
	D.mix_into(s, body, 0.0, 0.7)
	D.mix_into(s, snap, 0.0, 0.65)
	D.mix_into(s, click, 0.0, 1.0)
	D.mix_into(s, crack, 0.0, 0.55)
	s = D.saturate(s, 2.0)
	return D.biquad(s, "lp", 10000.0, 0.7071)


## 口笛: 音程が上がって落ち着く純音(+ 2 倍音・かすかな息のノイズ・ゆるいビブラート)。頭に小さな打音。
static func _whistle(r: RandomNumberGenerator, k: int) -> PackedFloat32Array:
	var jit := 1.0 + 0.07 * (r.randf() * 2.0 - 1.0) + 0.015 * k
	var dur := 0.26
	var tone := D.additive(dur, 1900.0 * jit, 2550.0 * jit, 38.0, [1.0, 2.0, 3.0], [1.0, 0.16, 0.04], [20.0, 30.0, 40.0], 22.0, 0.006)
	tone = D.env(tone, 0.0035, 0.0)
	tone = D.env(tone, 0.0, 19.0, 0.015)
	var breath := D.biquad(D.white(0.14, r), "bp", 3000.0 * jit, 2.5)
	breath = D.env(breath, 0.004, 26.0)
	var tap := _burst(r, 0.02, 2600.0, 1.0, 320.0, 1200.0)
	var s := D.buf(dur)
	D.mix_into(s, tone, 0.0, 0.62)
	D.mix_into(s, breath, 0.0, 0.16)
	D.mix_into(s, tap, 0.0, 0.22)
	s = D.biquad(s, "lp", 8500.0, 0.7071)
	return _mono_of(D.reverb(s, 0.35, 0.6, 0.1, 0.12))


## 手拍子: 数ミリ秒ずつずれた 4 つの帯域ノイズの粒が重なり、そのあとに短い余韻。部屋の響きで「パッ」と広がる。
static func _clap(r: RandomNumberGenerator, k: int) -> PackedFloat32Array:
	var dur := 0.34
	var s := D.buf(dur)
	var f := 1250.0 * (1.0 + 0.08 * (r.randf() * 2.0 - 1.0) + 0.02 * k)
	var offs := [0.0, 0.0105, 0.0225, 0.0335]
	for j in range(4):
		var t0: float = float(offs[j]) + 0.002 * r.randf()
		var amp := 0.85 - 0.08 * j
		D.mix_into(s, _burst(r, 0.02, f * (1.0 + 0.06 * j), 1.1, 230.0, 500.0), t0, amp)
	D.mix_into(s, _burst(r, 0.22, f * 0.95, 0.9, 24.0, 450.0), 0.03, 0.42)
	s = D.biquad(s, "peak", 2400.0, 1.0, 3.0)
	return _mono_of(D.reverb(s, 0.55, 0.55, 0.16, 0.25))


## 大きな弾(フィニッシュ): 重い衝撃。深い胴の落ち込み(サブ)+ 芯のある打撃 + 乾いた破裂(スネアのような)+ きらめき。ステレオ。
static func _boom(r: RandomNumberGenerator, k: int) -> Dictionary:
	var dur := 0.9
	var jit := 1.0 + 0.05 * (r.randf() * 2.0 - 1.0)
	var sub := D.sine_sweep(0.7, 125.0 * jit, 38.0, 13.0)
	sub = D.env(sub, 0.002, 5.5)
	var punch := D.sine_sweep(0.22, 270.0 * jit, 92.0, 38.0)
	punch = D.env(punch, 0.0006, 20.0)
	var crack := D.biquad(D.biquad(D.white(0.22, r), "hp", 700.0, 0.7071), "bp", 2300.0 * jit, 0.6)
	crack = D.env(crack, 0.0004, 34.0)
	var click := _burst(r, 0.008, 3200.0, 0.8, 700.0, 1500.0)
	var sparkle := D.additive(0.6, 1760.0 * jit, 1760.0 * jit, 0.0, [1.0, 2.76, 5.4], [1.0, 0.5, 0.25], [8.0, 13.0, 22.0])
	sparkle = D.env(sparkle, 0.001, 0.0)
	var s := D.buf(dur)
	D.mix_into(s, sub, 0.0, 1.0)
	D.mix_into(s, punch, 0.0, 0.85)
	D.mix_into(s, crack, 0.0, 0.9)
	D.mix_into(s, click, 0.0, 0.4)
	D.mix_into(s, sparkle, 0.012, 0.1)
	s = D.saturate(s, 1.7)
	var rv := D.reverb(s, 0.55, 0.6, 0.2, 0.3)
	return {"l": rv[0], "r": rv[1]}


## 細かい弾(スライダーの途中): 木の小さな音。5 音階(E マイナーペンタトニック)のうちの 1 音を、変種ごとに鳴らす。
## 連続して鳴っても、きらきらした粒のように聞こえ、音楽の調と大きくぶつかりにくい(短く、基音のあとすぐ消える)。
static func _tick(r: RandomNumberGenerator, k: int) -> PackedFloat32Array:
	var notes := [1318.5, 1568.0, 1760.0, 1975.5, 2349.3, 2637.0]
	var f: float = float(notes[k % 6]) * (1.0 + 0.004 * (r.randf() * 2.0 - 1.0))
	var dur := 0.09
	var tone := D.additive(dur, f, f, 0.0, [1.0, 2.4, 4.1], [1.0, 0.32, 0.1], [75.0, 125.0, 210.0])
	tone = D.env(tone, 0.0004, 0.0)
	var click := _burst(r, 0.004, f * 1.6, 1.0, 900.0, 900.0)
	var s := D.buf(dur)
	D.mix_into(s, tone, 0.0, 1.0)
	D.mix_into(s, click, 0.0, 0.28)
	return s


## 被弾の最初の「ツッ」: 弾に触れた瞬間の、短く鋭い電気的な音(上から落ちる音程 + ぱちっという粒 + 薄い低音)。
## 触れている間の続くダメージは、hit_loop(ジジジ…)が受け持つ。ここは、触れた合図だけの軽い音。
static func _hit(r: RandomNumberGenerator, k: int) -> Dictionary:
	var dur := 0.2
	var jit := 1.0 + 0.07 * (r.randf() * 2.0 - 1.0) + 0.03 * k
	var zap := D.sine_sweep(0.12, 2300.0 * jit, 520.0 * jit, 38.0)
	zap = D.env(zap, 0.0004, 30.0)
	var zap2 := D.sine_sweep(0.1, 1150.0 * jit, 260.0 * jit, 38.0)   # 1 オクターブ下を重ねて厚みを出す
	zap2 = D.env(zap2, 0.0004, 34.0)
	var crackle := _burst(r, 0.05, 2800.0, 0.8, 70.0, 900.0)
	var thump := D.sine_sweep(0.12, 150.0, 68.0, 30.0)
	thump = D.env(thump, 0.0008, 24.0)
	var s := D.buf(dur)
	D.mix_into(s, zap, 0.0, 0.7)
	D.mix_into(s, zap2, 0.0, 0.5)
	D.mix_into(s, crackle, 0.0, 0.7)
	D.mix_into(s, thump, 0.0, 0.25)
	s = D.saturate(s, 1.8)
	return {"l": s, "r": PackedFloat32Array()}


## 弾に触れている間のダメージ音(ループ): 電気がジジジと焼けるような持続音。
## ざらついたノイズに不規則な強弱を付け、まばらなぱちぱちという粒と、低い唸りを重ねる。継ぎ目のない 0.5 秒。
static func _hit_loop(r: RandomNumberGenerator) -> PackedFloat32Array:
	var loop_len := 0.5
	var fade := 0.05
	var total := loop_len + fade
	var noise := D.biquad(D.biquad(D.white(total, r), "bp", 2100.0, 0.7), "hp", 600.0, 0.7071)
	# 不規則な強弱(低い周波数のノイズ + 速い震え)
	var wob := D.biquad(D.white(total, r), "lp", 38.0, 0.7071)
	var wob_peak := maxf(D.peak(wob), 1e-6)
	for i in range(noise.size()):
		var t := float(i) / D.SR
		var am := 0.55 + 0.35 * (wob[i] / wob_peak) + 0.1 * sin(TAU * 61.0 * t)
		noise[i] *= am
	var crackle := D.buf(total)
	var n_clicks := int(total * 70.0)
	for j in range(n_clicks):
		D.mix_into(crackle, _burst(r, 0.004, 3600.0, 1.0, 1200.0, 1500.0), r.randf() * (total - 0.01), 0.5 + 0.5 * r.randf())
	var hum := D.biquad(D.saw(total, 96.0), "lp", 420.0, 0.8)
	for i in range(hum.size()):
		hum[i] *= 0.7 + 0.3 * sin(TAU * 7.0 * float(i) / D.SR)
	var s := D.buf(total)
	D.mix_into(s, noise, 0.0, 0.8)
	D.mix_into(s, crackle, 0.0, 0.7)
	D.mix_into(s, hum, 0.0, 0.28)
	s = D.biquad(s, "lp", 8000.0, 0.7071)
	return D.loop_crossfade(s, loop_len, fade)


## ゲームオーバー: 低い地鳴り + 暗くなりながら鳴り続けるノイズ + 破裂 + 大きな響き。ステレオ。
static func _explosion(r: RandomNumberGenerator) -> Dictionary:
	var dur := 1.5
	var sub := D.sine_sweep(dur, 96.0, 27.0, 2.6)
	sub = D.env(sub, 0.004, 2.5)
	var rumble := D.pink(dur, r)
	rumble = D.biquad_sweep(rumble, "lp", _rumble_freq, 0.9)
	rumble = D.env(rumble, 0.003, 3.0)
	var crack := D.biquad(D.white(0.09, r), "lp", 7000.0, 0.7071)
	crack = D.env(crack, 0.0003, 55.0)
	var body := _burst(r, 0.3, 380.0, 0.7, 11.0)
	var debris := D.buf(1.0)
	for j in range(34):
		var t0 := 0.04 + pow(r.randf(), 1.7) * 0.8
		D.mix_into(debris, _burst(r, 0.012, 1500.0 + 3000.0 * r.randf(), 1.1, 260.0, 700.0), t0, 0.35 * exp(-t0 * 1.8))
	var s := D.buf(dur)
	D.mix_into(s, sub, 0.0, 1.0)
	D.mix_into(s, rumble, 0.0, 2.2)
	D.mix_into(s, crack, 0.0, 1.0)
	D.mix_into(s, body, 0.0, 0.7)
	D.mix_into(s, debris, 0.0, 0.9)
	s = D.saturate(s, 1.5)
	var rv := D.reverb(s, 0.85, 0.5, 0.28, 0.6)
	return {"l": rv[0], "r": rv[1]}


# --- UI の音 ---

## 木琴ふうの 1 音: 基音 + 4 倍音前後(木の響き)。高い倍音ほど速く消える。
static func _marimba(dur: float, f: float, decay: float, bright := 0.35) -> PackedFloat32Array:
	var s := D.additive(dur, f, f, 0.0, [1.0, 3.9, 9.2], [1.0, bright, bright * 0.25], [decay, decay * 2.6, decay * 5.0])
	return D.env(s, 0.0008, 0.0)


## ベルふうの 1 音(FM)。
static func _bell(dur: float, f: float, decay: float, idx := 1.8) -> PackedFloat32Array:
	return D.env(D.fm(dur, f, 3.5, idx, decay * 1.4, decay), 0.001, 0.0)


static func _hover() -> PackedFloat32Array:
	return _marimba(0.08, 1760.0, 55.0, 0.18)


static func _click(r: RandomNumberGenerator) -> PackedFloat32Array:
	var s := D.sine_sweep(0.1, 640.0, 360.0, 38.0)
	s = D.env(s, 0.0008, 34.0)
	var tap := _burst(r, 0.008, 3000.0, 1.0, 600.0, 1500.0)
	var out := D.buf(0.1)
	D.mix_into(out, s, 0.0, 1.0)
	D.mix_into(out, tap, 0.0, 0.22)
	return out


static func _select() -> PackedFloat32Array:
	return _marimba(0.12, 1318.5, 42.0, 0.3)


static func _tick_ui(r: RandomNumberGenerator) -> PackedFloat32Array:
	var s := D.sine_sweep(0.04, 2800.0, 2500.0, 40.0)
	s = D.env(s, 0.0005, 130.0)
	var out := D.buf(0.04)
	D.mix_into(out, s, 0.0, 1.0)
	D.mix_into(out, _burst(r, 0.006, 4500.0, 1.0, 900.0, 2000.0), 0.0, 0.16)
	return out


static func _count() -> PackedFloat32Array:
	return _marimba(0.05, 1975.5, 85.0, 0.2)


## 上がる 4 音(E5 G#5 B5 E6)の最後が長く響く。
static func _confirm() -> Dictionary:
	var s := D.buf(0.62)
	var notes := [659.3, 830.6, 987.8, 1318.5]
	for j in range(4):
		D.mix_into(s, _marimba(0.4 if j == 3 else 0.14, float(notes[j]), 14.0 if j == 3 else 28.0, 0.32), 0.058 * j, 0.7 if j < 3 else 0.9)
	D.mix_into(s, _bell(0.5, 1318.5 * 2.0, 9.0, 1.0), 0.17, 0.12)
	return {"l": _mono_of(D.reverb(s, 0.5, 0.55, 0.14, 0.3)), "r": PackedFloat32Array()}


static func _back() -> PackedFloat32Array:
	var s := D.buf(0.2)
	D.mix_into(s, _marimba(0.14, 880.0, 30.0, 0.25), 0.0, 0.8)
	D.mix_into(s, _marimba(0.16, 587.3, 28.0, 0.25), 0.07, 0.8)
	return s


## 上がる / 下がる 2 音(on / off)。
static func _on_off(up: bool) -> PackedFloat32Array:
	var a := 622.3 if up else 740.0
	var b := 932.3 if up else 494.0
	var s := D.buf(0.24)
	D.mix_into(s, _marimba(0.1, a, 34.0, 0.3), 0.0, 0.8)
	D.mix_into(s, _marimba(0.16, b, 26.0, 0.3), 0.065, 0.9)
	return s


## パネルが開く / 閉じる: 帯域が上がる(下がる)風と、やわらかい 2 音の和音。
static func _open(r: RandomNumberGenerator) -> Dictionary:
	return _panel(r, true)


static func _close(r: RandomNumberGenerator) -> Dictionary:
	return _panel(r, false)


static func _panel(r: RandomNumberGenerator, up: bool) -> Dictionary:
	var dur := 0.26 if up else 0.2
	var n := D.white(dur, r)
	var f0 := 350.0 if up else 1900.0
	var f1 := 2100.0 if up else 320.0
	n = D.biquad_sweep(n, "bp", _panel_freq.bind(f0, f1, dur), 1.6)
	n = D.env(n, 0.04 if up else 0.015, 0.0)
	n = D.env(n, 0.0, 9.0 if up else 14.0, 0.06)
	var chord := D.buf(dur)
	var freqs := [440.0, 659.3] if up else [587.3, 392.0]
	for j in range(2):
		D.mix_into(chord, D.env(D.sine_sweep(dur, float(freqs[j]), float(freqs[j]), 0.0), 0.02, 12.0), 0.0 if up else 0.03 * j, 0.25)
	var s := D.buf(dur)
	D.mix_into(s, n, 0.0, 1.0)
	D.mix_into(s, chord, 0.0, 0.8)
	var rv := D.reverb(s, 0.45, 0.6, 0.12, 0.15)
	return {"l": rv[0], "r": rv[1]}


## ランクのスタンプ: 低い衝撃(音程が落ちる)+ 短い破裂 + 高いベルの 1 音。
static func _stamp(r: RandomNumberGenerator) -> Dictionary:
	var dur := 0.7
	var kick := D.sine_sweep(0.5, 135.0, 40.0, 16.0)
	kick = D.env(kick, 0.001, 7.0)
	var hit := D.biquad(D.white(0.06, r), "lp", 2200.0, 0.7071)
	hit = D.env(hit, 0.0004, 80.0)
	var bell := _bell(0.6, 1318.5, 6.0, 1.6)
	var s := D.buf(dur)
	D.mix_into(s, kick, 0.0, 1.0)
	D.mix_into(s, hit, 0.0, 0.5)
	D.mix_into(s, bell, 0.04, 0.22)
	s = D.saturate(s, 1.3)
	var rv := D.reverb(s, 0.65, 0.5, 0.2, 0.4)
	return {"l": rv[0], "r": rv[1]}


## 画面が変わる風切り音: 帯域が上がって下がるノイズ。左右で少しずらしてステレオの広がりをつける。
static func _whoosh(r: RandomNumberGenerator) -> Dictionary:
	var dur := 0.36
	var chans: Array = []
	for ch in range(2):
		var n := D.pink(dur, r)
		var sh := 1.0 + 0.12 * (ch * 2 - 1)
		n = D.biquad_sweep(n, "bp", _whoosh_freq.bind(dur, sh), 1.1)
		n = D.env(n, 0.07, 0.0)
		for i in range(n.size()):
			var u2 := float(i) / n.size()
			n[i] *= pow(sin(PI * u2), 1.5)
		chans.append(n)
	return {"l": chans[0], "r": chans[1]}


## 通知: 軽いベルが 2 つ上がる。
static func _toast() -> Dictionary:
	var s := D.buf(0.5)
	D.mix_into(s, _bell(0.3, 1174.7, 13.0, 1.2), 0.0, 0.7)
	D.mix_into(s, _bell(0.4, 1568.0, 11.0, 1.2), 0.1, 0.8)
	return {"l": _mono_of(D.reverb(s, 0.5, 0.55, 0.14, 0.25)), "r": PackedFloat32Array()}


## 拒否: 低い 2 音の短い唸り(のこぎり波をなだらかに濁らせる)。
static func _deny() -> PackedFloat32Array:
	var dur := 0.2
	var a := D.biquad(D.saw(dur, 196.0), "lp", 700.0, 0.8)
	var b := D.biquad(D.saw(dur, 146.8), "lp", 700.0, 0.8)
	var s := D.buf(dur)
	D.mix_into(s, a, 0.0, 0.5)
	D.mix_into(s, b, 0.09, 0.55)
	for i in range(s.size()):   # 小さな震え
		s[i] *= 0.78 + 0.22 * sin(TAU * 24.0 * float(i) / D.SR)
	return D.env(s, 0.004, 9.0, 0.08)


# --- 時間で動くフィルター周波数 ---

static func _rumble_freq(t: float) -> float:
	return 150.0 + 1900.0 * exp(-t * 3.2)


static func _panel_freq(t: float, f0: float, f1: float, dur: float) -> float:
	return lerpf(f0, f1, clampf(t / dur, 0.0, 1.0))


static func _whoosh_freq(t: float, dur: float, sh: float) -> float:
	var u := t / dur
	return (lerpf(260.0, 2500.0, u * u) if u < 0.55 else lerpf(2500.0, 480.0, (u - 0.55) / 0.45)) * sh


# --- 補助 ---

## reverb の [左, 右] を、モノ 1 本にまとめる(連打される弾の音は、位相の干渉を避けてモノにする)。
static func _mono_of(lr: Array) -> PackedFloat32Array:
	var l: PackedFloat32Array = lr[0]
	var rr: PackedFloat32Array = lr[1]
	var out := PackedFloat32Array()
	out.resize(l.size())
	for i in range(l.size()):
		out[i] = (l[i] + rr[i]) * 0.5
	return out
