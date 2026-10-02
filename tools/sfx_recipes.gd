extends RefCounted
## 効果音のレシピ(開発用)。1 つの音は「部品を重ねて、フィルターをかけ、響きを足し、大きさをそろえる」関数で作る。
## render(名前, 番号) が { l: 左, r: 右(モノなら空) } を返す。番号は同じ音の変種(乱数の種と音色を少しずつ変える)。
##
## 音作りの方針(「気持ちいい」の目安):
##   - 正弦波を電子的に掃くより、「叩かれた物体」の音(モーダル合成: 木・ガラス・鉄琴・カリンバ)を使う。自然な倍音と、
##     ばちの硬さ(接している時間)で決まる明るさが出て、耳がなじむ
##   - 頭は鋭く(1〜2 ms で立ち上がる)、尾は短く。何度も鳴る音ほど、低い音を引きずらない(曲の低音とぶつからない)
##   - 響きは短く自然な部屋の残響(FDN)。金属的な鳴きの出る Freeverb は使わない
##   - 音程のある音は、曲と合いやすい音階(E のペンタトニック / E メジャー)の音を使う。曲のメロディと重なって続けて鳴る音(tick)は、音程を持たせない
##
## ## ゲームの音(osu! のヒットサウンドの役割に合わせる)
##   pop     … ふつうの弾(normal)    : 木の塊を叩いた「トッ」+ 短い胴の低音。約 80 ms
##   whistle … 口笛(whistle)         : ガラスのチャイム「ピン」。近い 2 つの振動がゆっくりうなって、きらめく
##   clap    … 手拍子(clap)          : 808 の手拍子(3 回のはじけ + 短い尾)+ 小さな部屋の響き
##   boom    … 大きな弾(finish)      : サブ低音の落ち込み「ドン」+ 芯 + シンバルのきらめき。ステレオ
##   tick    … 細かい弾(スライダーの途中) : 音程を感じない小さな粒「チッ」(メロディと重なっても音程がぶつからない)
##   hit     … 弾に触れた瞬間          : 重い打撃 + 金属的に落ちる FM + デジタルの粗さの「ザクッ」
##   hit_loop… 弾に触れている間(ループ): ざらついたノイズと、12 Hz で脈打つ低い唸り。継ぎ目のない 0.5 秒
##   explosion … ゲームオーバー      : 低い地鳴り + 暗くなるノイズ + 破片 + 大きな響き。ステレオ
## ## UI の音
##   カリンバ・マリンバ・鉄琴で統一(丸く短い)。決定は左→右へ広がるアルペジオ、画面切り替えの風切りは幕と同じく左→右へ動く

const D = preload("res://tools/dsp.gd")

## 名前 → [変種の数, 目標の大きさ(dBFS。最も大きい 100ms の平均)、ピークの上限, (任意)"loop" = ループ再生する音]
const SPEC := {
	"pop": [6, -15.0, 0.95],
	"whistle": [6, -18.0, 0.92],
	"clap": [6, -15.0, 0.92],
	"boom": [4, -13.0, 0.95],
	"tick": [6, -20.0, 0.95],
	"hit": [3, -13.0, 0.95],
	"hit_loop": [1, -19.0, 0.9, "loop"],
	"explosion": [1, -11.3, 0.97],
	"hover": [1, -20.0, 0.85],
	"click": [1, -16.5, 0.85],
	"select": [1, -17.0, 0.85],
	"confirm": [1, -16.5, 0.9],
	"back": [1, -17.0, 0.85],
	"open": [1, -20.0, 0.8],
	"close": [1, -20.0, 0.8],
	"on": [1, -17.0, 0.85],
	"off": [1, -17.5, 0.85],
	"tick_ui": [1, -19.0, 0.85],
	"stamp": [1, -14.0, 0.95],
	"whoosh": [1, -21.0, 0.8],
	"toast": [1, -19.0, 0.85],
	"deny": [1, -16.0, 0.85],
	"count": [1, -18.5, 0.85],
}

## 楽器のモード(振動の周波数比, 大きさ)。叩かれた物体の固有の振動。
## 木の塊(ウッドブロック): 倍音が整数比でない、詰まった響き
const WOOD := [[1.0, 1.0], [1.58, 0.5], [2.31, 0.32], [3.12, 0.18], [4.27, 0.1]]
## マリンバ(木の音板。2 番目が 4 倍・3 番目が 10 倍に調律されている)
const MARIMBA := [[1.0, 1.0], [3.99, 0.26], [9.95, 0.06]]
## 鉄琴(両端が自由な金属の棒: 1 : 2.76 : 5.40 : 8.93)
const GLOCK := [[1.0, 1.0], [2.76, 0.3], [5.40, 0.12], [8.93, 0.04]]
## カリンバ(金属の舌。基音が強く、高い倍音が短く鳴る)
const KALIMBA := [[1.0, 1.0], [2.0, 0.05], [5.95, 0.2], [12.6, 0.05]]
## ガラス(基音のすぐそばにもう 1 つの振動があり、ゆっくりうなる)
const GLASS := [[1.0, 1.0], [1.0035, 0.35], [2.32, 0.45], [4.25, 0.2], [6.63, 0.08]]


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
		"hit": out.l = _hit(r, k)
		"hit_loop": out.l = _hit_loop(r)
		"explosion": out = _explosion(r)
		"hover": out.l = _hover(r)
		"click": out.l = _click(r)
		"select": out.l = _select(r)
		"confirm": out = _confirm(r)
		"back": out.l = _back(r)
		"open": out = _panel(r, true)
		"close": out = _panel(r, false)
		"on": out.l = _on_off(r, true)
		"off": out.l = _on_off(r, false)
		"tick_ui": out.l = _tick_ui(r)
		"stamp": out = _stamp(r)
		"whoosh": out = _whoosh(r)
		"toast": out = _toast(r)
		"deny": out.l = _deny(r)
		"count": out.l = _count(r)
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

## 叩かれた物体の音(モーダル合成)。f: 基音、modes: [[周波数比, 大きさ], ...]、decay: 基音の減衰の速さ(1/秒)。
## 高いモードほど速く消える(周波数比の hf 乗の速さ)。contact: ばちが接している秒数(短いほど硬く明るい)、noise: 当たりのざらつき。
static func _struck(r: RandomNumberGenerator, dur: float, f: float, modes: Array, decay: float, contact: float, noise := 0.15, hf := 0.8) -> PackedFloat32Array:
	var freqs: Array = []
	var decs: Array = []
	var gains: Array = []
	for m in modes:
		freqs.append(f * float(m[0]))
		decs.append(decay * pow(float(m[0]), hf))
		gains.append(float(m[1]))
	return D.modal(D.mallet(contact, noise, r), dur, freqs, decs, gains)


## 減衰の速さから、音が -60 dB になるまでの秒数(+ 少しの余裕)。
static func _len_of(decay: float) -> float:
	return 6.9 / decay + 0.01


static func _kalimba(r: RandomNumberGenerator, f: float, decay: float, contact := 0.0006) -> PackedFloat32Array:
	return _struck(r, _len_of(decay), f, KALIMBA, decay, contact, 0.15, 0.9)


static func _marimba(r: RandomNumberGenerator, f: float, decay: float, contact := 0.0009) -> PackedFloat32Array:
	return _struck(r, _len_of(decay), f, MARIMBA, decay, contact, 0.1, 0.9)


static func _glock(r: RandomNumberGenerator, f: float, decay: float, contact := 0.0003) -> PackedFloat32Array:
	return _struck(r, _len_of(decay), f, GLOCK, decay, contact, 0.05, 0.7)


## 短いノイズの粒(帯域通過)。
static func _burst(r: RandomNumberGenerator, dur: float, f: float, q: float, decay: float, hp := 0.0) -> PackedFloat32Array:
	var n := D.white(dur, r)
	if hp > 0.0:
		n = D.biquad(n, "hp", hp, 0.7071)
	n = D.biquad(n, "bp", f, q)
	return D.env(n, 0.0003, decay)


## 808 のシンバル / ハイハットの素材: 比のずれた 6 つの周波数の帯域制限矩形波を重ねる(scale 倍の高さ)。
const METAL := [205.3, 304.4, 369.6, 522.7, 540.0, 800.0]


static func _metal(dur: float, scale: float) -> PackedFloat32Array:
	var out := D.buf(dur)
	for j in range(METAL.size()):
		D.mix_into(out, D.square(dur, float(METAL[j]) * scale, 0.13 * float(j)), 0.0, 0.2)
	return out


## シンバルのきらめき(金属の矩形波 + ノイズを、高域だけ通す)。
static func _shimmer(r: RandomNumberGenerator, dur: float, decay: float) -> PackedFloat32Array:
	var s := _metal(dur, 1.9)
	D.mix_into(s, D.white(dur, r), 0.0, 0.35)
	s = D.biquad(D.biquad(s, "hp", 5500.0, 0.7071), "bp", 8500.0, 0.6)
	s = D.biquad(s, "lp", 12000.0, 0.7071)
	return D.env(s, 0.0015, decay)


# --- ゲームの音 ---

## ふつうの弾: 木の塊を叩いた「トッ」。叩いた瞬間の硬い当たり + 詰まった木の響き + ごく短い胴の低音(重さ)。
## 低い音は約 50 ms で消し、尾を引かない(連打されても濁らず、曲の低音とぶつからない)。部屋の響きはごくわずか。
static func _pop(r: RandomNumberGenerator, k: int) -> PackedFloat32Array:
	var jit := 1.0 + 0.04 * (r.randf() * 2.0 - 1.0) + 0.015 * k
	var dur := 0.16
	var knock := _struck(r, dur, 760.0 * jit, WOOD, 70.0, 0.0002 + 0.00015 * r.randf(), 0.35, 0.8)
	var body := D.env(D.sine_sweep(0.07, 260.0 * jit, 170.0 * jit, 60.0), 0.0006, 70.0)
	var click := _burst(r, 0.004, 5200.0, 0.7, 1300.0, 2500.0)
	var s := D.buf(dur)
	D.mix_into(s, knock, 0.0, 1.0)
	D.mix_into(s, body, 0.0, 0.22 * D.peak(knock))
	D.mix_into(s, click, 0.0, 0.18 * D.peak(knock) / maxf(D.peak(click), 1e-6))
	s = D.saturate(s, 1.3)
	s = _mono_of(D.room(s, 0.35, 0.12, 0.5, 0.08))
	return D.biquad(s, "lp", 11000.0, 0.7071)


## 口笛: ガラスのチャイム「ピン」。硬いばちで叩いたガラスの響き(近い 2 つの振動のうなりで、きらめく)+ かすかな空気の粒。
static func _whistle(r: RandomNumberGenerator, k: int) -> PackedFloat32Array:
	var jit := 1.0 + 0.03 * (r.randf() * 2.0 - 1.0) + 0.012 * k
	var dur := 0.5
	var chime := _struck(r, dur, 1760.0 * jit, GLASS, 14.0, 0.00008, 0.05, 0.5)
	var air := D.biquad(D.white(0.05, r), "bp", 7000.0, 1.2)
	air = D.env(air, 0.0005, 60.0)
	var s := D.buf(dur)
	D.mix_into(s, chime, 0.0, 1.0)
	D.mix_into(s, air, 0.0, 0.06 * D.peak(chime) / maxf(D.peak(air), 1e-6))
	return _mono_of(D.room(s, 0.6, 0.45, 0.45, 0.14))


## 手拍子: 808 の手拍子。帯域ノイズが 3 回はじけ(手のひらが少しずつずれて当たる)、そのあと短い尾。小さな部屋の響き。
static func _clap(r: RandomNumberGenerator, k: int) -> PackedFloat32Array:
	var dur := 0.3
	var f := 1150.0 * (1.0 + 0.06 * (r.randf() * 2.0 - 1.0) + 0.015 * k)
	var n := D.biquad(D.white(dur, r), "hp", 700.0, 0.7071)
	var main := D.biquad(n, "bp", f, 1.3)
	var hi := D.biquad(n, "bp", f * 1.9, 1.5)
	var offs := [0.0, 0.0095 + 0.002 * r.randf(), 0.0185 + 0.003 * r.randf()]
	var tail_t := 0.026 + 0.002 * r.randf()
	var s := D.buf(dur)
	for i in range(s.size()):
		var t := float(i) / D.SR
		var e := 0.0
		for j in range(3):
			var u: float = t - float(offs[j])
			if u >= 0.0:
				e += minf(u / 0.0003, 1.0) * exp(-u * 380.0) * (1.0 - 0.1 * j)
		var ut := t - tail_t
		if ut >= 0.0:
			e += 0.7 * minf(ut / 0.001, 1.0) * exp(-ut * 26.0)
		s[i] = (main[i] + hi[i] * 0.4) * e
	s = D.biquad(s, "peak", 2600.0, 1.0, 3.0)
	return _mono_of(D.room(s, 0.5, 0.28, 0.4, 0.18))


## 大きな弾(フィニッシュ): サブ低音が落ち込む「ドン」+ 芯 + 硬い当たり + シンバルのきらめき。大きめの部屋の響きでステレオに広げる。
static func _boom(r: RandomNumberGenerator, k: int) -> Dictionary:
	var dur := 1.0
	var jit := 1.0 + 0.04 * (r.randf() * 2.0 - 1.0) + 0.01 * k
	var sub := D.env(D.sine_sweep(0.8, 155.0 * jit, 46.0, 26.0), 0.0008, 6.5)
	var punch := D.env(D.sine_sweep(0.2, 340.0 * jit, 150.0 * jit, 45.0), 0.0004, 26.0)
	var click := _burst(r, 0.006, 3500.0, 0.8, 900.0, 1500.0)
	var low := D.buf(dur)
	D.mix_into(low, sub, 0.0, 1.0)
	D.mix_into(low, punch, 0.0, 0.55)
	D.mix_into(low, click, 0.0, 0.35 / maxf(D.peak(click), 1e-6))
	low = D.saturate(low, 1.6)
	var sh := _shimmer(r, 0.9, 5.5)
	D.mix_into(low, sh, 0.004, 0.16 / maxf(D.peak(sh), 1e-6))
	var rv := D.room(low, 0.9, 0.9, 0.5, 0.2)
	return {"l": rv[0], "r": rv[1]}


## 細かい弾(スライダーの途中・スピナー): 音程を感じない小さな粒「チッ」。
## 曲のメロディと同じ時刻に続けて鳴りやすいので、はっきりした音程を持たせない(どの調の曲でも、メロディの音とぶつからない)。
## シェイカーのような帯域ノイズの短い粒 + 倍音が整数比でない小さな当たり(約 4 ms で止まるので、音程としては聞こえない)。
## 変種ごとに、粒の帯域と当たりの高さを少しずつ変える(続けて鳴っても、同じ音の繰り返しに聞こえない)。
static func _tick(r: RandomNumberGenerator, k: int) -> PackedFloat32Array:
	var dur := 0.09
	var fc := 2800.0 * (1.0 + 0.1 * (r.randf() * 2.0 - 1.0)) * (1.0 + 0.03 * (k - 2.5))
	var grain := D.biquad(D.biquad(D.white(dur, r), "hp", 1800.0, 0.7071), "bp", fc, 0.7)
	grain = D.env(grain, 0.0004, 85.0)
	var knock := _struck(r, dur, 1900.0 * (1.0 + 0.15 * (r.randf() * 2.0 - 1.0)),
		[[1.0, 1.0], [1.37, 0.8], [1.83, 0.7], [2.51, 0.5], [3.29, 0.35]], 260.0, 0.00012, 0.4, 0.5)
	var s := D.buf(dur)
	D.mix_into(s, grain, 0.0, 1.0 / maxf(D.peak(grain), 1e-6))
	D.mix_into(s, knock, 0.0, 0.6 / maxf(D.peak(knock), 1e-6))
	return D.biquad(s, "lp", 7000.0, 0.7071)


## 被弾の最初の「ザクッ」: 重い打撃(落ちる低音)+ 金属的に落ちる FM + サンプルホールドで粗くしたノイズ。
## 弾の音(木・ガラス)とはっきり違う、デジタルに壊れたような質感。触れている間の続く音は hit_loop が受け持つ。
static func _hit(r: RandomNumberGenerator, k: int) -> PackedFloat32Array:
	var dur := 0.2
	var jit := 1.0 + 0.05 * (r.randf() * 2.0 - 1.0) + 0.03 * k
	var thud := D.env(D.sine_sweep(0.16, 260.0 * jit, 75.0, 32.0), 0.0005, 24.0)
	var zap := D.fm(0.14, 900.0 * jit, 1.41, 4.0, 25.0, 30.0, 240.0 * jit, 35.0)
	var crunch := D.crush(D.biquad(D.white(0.08, r), "bp", 2000.0, 0.7), 5)
	crunch = D.env(crunch, 0.0003, 50.0)
	var s := D.buf(dur)
	D.mix_into(s, thud, 0.0, 0.4)
	D.mix_into(s, zap, 0.0, 0.45)
	D.mix_into(s, crunch, 0.0, 0.7 / maxf(D.peak(crunch), 1e-6))
	s = D.saturate(s, 2.2)
	return D.biquad(s, "lp", 9000.0, 0.7071)


## 弾に触れている間のダメージ音(ループ): ざらついたノイズに不規則な強弱と 12 Hz の脈を付け、まばらな粗い粒と、
## 同じ脈で揺れる低い唸り(少しずれた 2 つののこぎり波のうなり)を重ねる。継ぎ目のない 0.5 秒(脈はちょうど 6 回)。
static func _hit_loop(r: RandomNumberGenerator) -> PackedFloat32Array:
	var loop_len := 0.5
	var fade := 0.05
	var total := loop_len + fade
	var noise := D.biquad(D.biquad(D.white(total, r), "bp", 1700.0, 0.8), "hp", 500.0, 0.7071)
	var wob := D.biquad(D.white(total, r), "lp", 38.0, 0.7071)
	var wob_peak := maxf(D.peak(wob), 1e-6)
	for i in range(noise.size()):
		var t := float(i) / D.SR
		noise[i] *= 0.6 + 0.25 * (wob[i] / wob_peak) + 0.15 * (0.5 + 0.5 * sin(TAU * 12.0 * t))
	var crackle := D.buf(total)
	for j in range(int(total * 55.0)):
		D.mix_into(crackle, D.crush(_burst(r, 0.005, 3200.0, 1.0, 1000.0, 1500.0), 4), r.randf() * (total - 0.01), 0.5 + 0.5 * r.randf())
	var hum := D.saw(total, 110.0)
	D.mix_into(hum, D.saw(total, 110.9, 0.3), 0.0, 1.0)
	hum = D.biquad(hum, "lp", 700.0, 0.9)
	for i in range(hum.size()):
		hum[i] *= 0.65 + 0.35 * sin(TAU * 12.0 * float(i) / D.SR)
	var s := D.buf(total)
	D.mix_into(s, noise, 0.0, 0.7)
	D.mix_into(s, crackle, 0.0, 0.6)
	D.mix_into(s, hum, 0.0, 0.18)
	s = D.biquad(s, "lp", 5000.0, 0.7071)
	return D.loop_crossfade(s, loop_len, fade)


## ゲームオーバー: 低い地鳴り + 暗くなりながら鳴り続けるノイズ + 破裂 + 散らばる破片 + 大きな響き。ステレオ。
static func _explosion(r: RandomNumberGenerator) -> Dictionary:
	var dur := 1.5
	var sub := D.env(D.sine_sweep(dur, 96.0, 27.0, 2.6), 0.004, 2.5)
	var rumble := D.pink(dur, r)
	rumble = D.biquad_sweep(rumble, "lp", _rumble_freq, 0.9)
	rumble = D.env(rumble, 0.003, 3.0)
	var crack := D.biquad(D.white(0.09, r), "lp", 7000.0, 0.7071)
	crack = D.env(crack, 0.0003, 55.0)
	var body := _burst(r, 0.3, 380.0, 0.7, 11.0)
	var s := D.buf(dur)
	D.mix_into(s, sub, 0.0, 1.0)
	D.mix_into(s, rumble, 0.0, 2.2)
	D.mix_into(s, crack, 0.0, 1.0)
	D.mix_into(s, body, 0.0, 0.7)
	s = D.saturate(s, 1.5)
	var rv := D.room(s, 1.3, 1.8, 0.55, 0.3)
	# 破片: 左右のあちこちに散らばる(ステレオの広がり)
	var dl := D.buf(1.2)
	var dr := D.buf(1.2)
	for j in range(34):
		var t0 := 0.04 + pow(r.randf(), 1.7) * 0.8
		var g := 0.35 * exp(-t0 * 1.8)
		var lr := D.pan(_burst(r, 0.012, 1500.0 + 3000.0 * r.randf(), 1.1, 260.0, 700.0), r.randf() * 1.6 - 0.8)
		D.mix_into(dl, lr[0], t0, g)
		D.mix_into(dr, lr[1], t0, g)
	var out_l: PackedFloat32Array = rv[0]
	var out_r: PackedFloat32Array = rv[1]
	D.mix_into(out_l, dl, 0.0, 0.9)
	D.mix_into(out_r, dr, 0.0, 0.9)
	return {"l": out_l, "r": out_r}


# --- UI の音 ---

## ホバー: やわらかいばちのマリンバの小さな 1 音(B6)。目立たず、触れたことだけが分かる。
static func _hover(r: RandomNumberGenerator) -> PackedFloat32Array:
	return _marimba(r, 1975.5, 42.0, 0.0011)


## クリック: 良いボタンを押したときの「コクッ」。詰まった低めの当たり + 小さな高い当たり + ごく短い粒。
static func _click(r: RandomNumberGenerator) -> PackedFloat32Array:
	var press := _struck(r, 0.1, 380.0, [[1.0, 1.0], [2.65, 0.45], [4.1, 0.2]], 55.0, 0.0007, 0.3)
	var top := _struck(r, 0.05, 1900.0, [[1.0, 1.0], [2.4, 0.3]], 110.0, 0.0003)
	var snap := _burst(r, 0.003, 4200.0, 0.8, 1400.0, 2000.0)
	var s := D.buf(0.1)
	D.mix_into(s, press, 0.0, 1.0 / maxf(D.peak(press), 1e-6))
	D.mix_into(s, top, 0.0, 0.3 / maxf(D.peak(top), 1e-6))
	D.mix_into(s, snap, 0.0, 0.2 / maxf(D.peak(snap), 1e-6))
	return s


## 選択: カリンバの 1 音(E6)。実行時に音程を上下させて、音階として聞かせる。
static func _select(r: RandomNumberGenerator) -> PackedFloat32Array:
	return _mono_of(D.room(_kalimba(r, 1318.5, 24.0), 0.4, 0.2, 0.5, 0.06))


## スライダー・スクロールの目盛り: 小さな木の粒。
static func _tick_ui(r: RandomNumberGenerator) -> PackedFloat32Array:
	var s := _struck(r, 0.045, 3100.0, [[1.0, 1.0], [2.3, 0.3]], 160.0, 0.00015)
	D.mix_into(s, _burst(r, 0.004, 5000.0, 1.0, 1200.0, 2500.0), 0.0, 0.15 * D.peak(s))
	return s


## 数字のカウント: カリンバのごく短い 1 音(B6)。
static func _count(r: RandomNumberGenerator) -> PackedFloat32Array:
	return _kalimba(r, 1975.5, 80.0, 0.0004)


## 決定: カリンバの上がる 4 音(E5 G#5 B5 E6)が左から右へ広がり、最後の音が長く響く。上に鉄琴のきらめき(E7)。
static func _confirm(r: RandomNumberGenerator) -> Dictionary:
	var dur := 0.7
	var l := D.buf(dur)
	var rr := D.buf(dur)
	var notes := [659.3, 830.6, 987.8, 1318.5]
	var pans := [-0.35, -0.12, 0.12, 0.35]
	for j in range(4):
		var last := j == 3
		var note := _kalimba(r, float(notes[j]), 12.0 if last else 26.0)
		var lr := D.pan(note, float(pans[j]))
		var g := (0.9 if last else 0.7) / maxf(D.peak(note), 1e-6)
		D.mix_into(l, lr[0], 0.045 * j, g)
		D.mix_into(rr, lr[1], 0.045 * j, g)
	var spark := _glock(r, 2637.0, 10.0)
	var slr := D.pan(spark, 0.2)
	D.mix_into(l, slr[0], 0.135, 0.15 / maxf(D.peak(spark), 1e-6))
	D.mix_into(rr, slr[1], 0.135, 0.15 / maxf(D.peak(spark), 1e-6))
	var rv := D.room_stereo([l, rr], 0.7, 0.6, 0.45, 0.18)
	return {"l": rv[0], "r": rv[1]}


## 戻る: カリンバの下がる 2 音(A5 → E5)。少しやわらかいばちで、穏やかに。
static func _back(r: RandomNumberGenerator) -> PackedFloat32Array:
	var s := D.buf(0.3)
	var a := _kalimba(r, 880.0, 30.0, 0.0009)
	var b := _kalimba(r, 659.3, 26.0, 0.0009)
	D.mix_into(s, a, 0.0, 0.8 / maxf(D.peak(a), 1e-6))
	D.mix_into(s, b, 0.06, 0.85 / maxf(D.peak(b), 1e-6))
	return s


## トグル: 入れる = 上がる 2 音(E5 → B5)、切る = 下がる 2 音(B5 → E5。やわらかいばちで、こもった音)。
static func _on_off(r: RandomNumberGenerator, up: bool) -> PackedFloat32Array:
	var a := 659.3 if up else 987.8
	var b := 987.8 if up else 659.3
	var contact := 0.0005 if up else 0.0012
	var s := D.buf(0.28)
	var na := _kalimba(r, a, 32.0, contact)
	var nb := _kalimba(r, b, 24.0, contact)
	D.mix_into(s, na, 0.0, 0.8 / maxf(D.peak(na), 1e-6))
	D.mix_into(s, nb, 0.05, 0.9 / maxf(D.peak(nb), 1e-6))
	D.mix_into(s, _burst(r, 0.003, 3500.0, 0.8, 1400.0, 1500.0), 0.0, 0.08)
	return s


## パネルが開く / 閉じる: 明るくなる(暗くなる)やわらかい空気 + カリンバの 2 音の和音(開く: E5+B5 / 閉じる: B5 → E5)。
static func _panel(r: RandomNumberGenerator, up: bool) -> Dictionary:
	var dur := 0.3 if up else 0.22
	var air := D.pink(dur, r)
	air = D.biquad_sweep(air, "lp", _panel_freq.bind(500.0 if up else 4000.0, 4000.0 if up else 500.0, dur), 0.8)
	for i in range(air.size()):
		var u := float(i) / air.size()
		air[i] *= pow(sin(PI * (u * 0.8 + 0.1 if up else u * 0.7 + 0.3)), 1.5) * (1.0 - u * 0.3)
	var s := D.buf(dur + 0.25)
	D.mix_into(s, air, 0.0, 0.5 / maxf(D.peak(air), 1e-6))
	var freqs := [659.3, 987.8] if up else [987.8, 659.3]
	for j in range(2):
		var note := _kalimba(r, float(freqs[j]), 16.0 if up else 20.0, 0.0008)
		D.mix_into(s, note, (0.05 + 0.012 * j) if up else (0.02 + 0.05 * j), 0.4 / maxf(D.peak(note), 1e-6))
	var rv := D.room(s, 0.6, 0.4, 0.5, 0.15)
	return {"l": rv[0], "r": rv[1]}


## ランクのスタンプ: 重い「ドン」(落ちるサブ低音 + 大きな胴)+ 叩きつける破裂 + 鉄琴の和音(E6 + B6)+ きらめき。大きな部屋の響き。
static func _stamp(r: RandomNumberGenerator) -> Dictionary:
	var dur := 0.9
	var kick := D.env(D.sine_sweep(0.6, 150.0, 42.0, 18.0), 0.0008, 6.5)
	var body := _struck(r, 0.4, 180.0, [[1.0, 1.0], [1.5, 0.6], [2.2, 0.35]], 14.0, 0.002, 0.4)
	var slam := D.env(D.biquad(D.white(0.08, r), "lp", 2500.0, 0.7071), 0.0003, 70.0)
	var low := D.buf(dur)
	D.mix_into(low, kick, 0.0, 1.0)
	D.mix_into(low, body, 0.0, 0.5 / maxf(D.peak(body), 1e-6))
	D.mix_into(low, slam, 0.0, 0.45 / maxf(D.peak(slam), 1e-6))
	low = D.saturate(low, 1.4)
	for nf in [1318.5, 1975.5]:
		var bell := _glock(r, nf, 5.5)
		D.mix_into(low, bell, 0.03, 0.16 / maxf(D.peak(bell), 1e-6))
	var sh := _shimmer(r, 0.7, 7.0)
	D.mix_into(low, sh, 0.005, 0.08 / maxf(D.peak(sh), 1e-6))
	var rv := D.room(low, 1.0, 1.0, 0.5, 0.22)
	return {"l": rv[0], "r": rv[1]}


## 画面が変わる風切り音: 帯域が上がって下がるノイズ。幕と同じく、左から右へ動く。
static func _whoosh(r: RandomNumberGenerator) -> Dictionary:
	var dur := 0.38
	var n := D.pink(dur, r)
	n = D.biquad_sweep(n, "bp", _whoosh_freq.bind(dur), 1.1)
	var air := D.biquad(D.white(dur, r), "hp", 4000.0, 0.7071)
	for i in range(n.size()):
		var u := float(i) / n.size()
		var w := pow(sin(PI * u), 1.5)
		n[i] = (n[i] + air[i] * 0.04) * w
	var lr := D.pan_sweep(n, _whoosh_pan.bind(dur))
	return {"l": lr[0], "r": lr[1]}


## 通知: 鉄琴の 2 音が上がる(B5 → E6)。下にカリンバを薄く重ねて丸く。
static func _toast(r: RandomNumberGenerator) -> Dictionary:
	var s := D.buf(0.5)
	var notes := [987.8, 1318.5]
	for j in range(2):
		var g := _glock(r, float(notes[j]), 14.0 - 3.0 * j)
		var kl := _kalimba(r, float(notes[j]), 18.0)
		D.mix_into(s, g, 0.09 * j, 0.7 / maxf(D.peak(g), 1e-6))
		D.mix_into(s, kl, 0.09 * j, 0.35 / maxf(D.peak(kl), 1e-6))
	var rv := D.room(s, 0.6, 0.45, 0.5, 0.16)
	return {"l": rv[0], "r": rv[1]}


## 拒否: こもった低い「ボッ、ボッ」(やわらかいばちの木の 2 打。2 打目は少し低い)。責めない、軽い「だめ」。
static func _deny(r: RandomNumberGenerator) -> PackedFloat32Array:
	var s := D.buf(0.26)
	for j in range(2):
		var b := _struck(r, 0.15, 233.1 * (1.0 - 0.06 * j), [[1.0, 1.0], [2.7, 0.35], [5.1, 0.1]], 30.0, 0.0016, 0.2)
		D.mix_into(s, b, 0.1 * j, (0.9 - 0.1 * j) / maxf(D.peak(b), 1e-6))
	return s


# --- 時間で動く値 ---

static func _rumble_freq(t: float) -> float:
	return 150.0 + 1900.0 * exp(-t * 3.2)


static func _panel_freq(t: float, f0: float, f1: float, dur: float) -> float:
	return f0 * pow(f1 / f0, clampf(t / dur, 0.0, 1.0))


static func _whoosh_freq(t: float, dur: float) -> float:
	var u := t / dur
	return lerpf(260.0, 2500.0, u * u) if u < 0.55 else lerpf(2500.0, 480.0, (u - 0.55) / 0.45)


static func _whoosh_pan(t: float, dur: float) -> float:
	return lerpf(-0.7, 0.7, smoothstep(0.0, 1.0, t / dur))


# --- 補助 ---

## room / reverb の [左, 右] を、モノ 1 本にまとめる(連打される弾の音は、位相の干渉を避けてモノにする)。
static func _mono_of(lr: Array) -> PackedFloat32Array:
	var l: PackedFloat32Array = lr[0]
	var rr: PackedFloat32Array = lr[1]
	var out := PackedFloat32Array()
	out.resize(l.size())
	for i in range(l.size()):
		out[i] = (l[i] + rr[i]) * 0.5
	return out
