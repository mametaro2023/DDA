extends SceneTree
## 効果音(assets/sfx のファイル)の性質を測る。tools/sfx_forge.gd で作った音が、目的に合っているかの目安。
## godot --headless --path . --script tests/test_sfx.gd           全部の音を測る(表を出して、基準に合うか確かめる)
## godot --headless --path . --script tests/test_sfx.gd -- wav    読み込んだ音を WAV に書き出す(耳で確かめる用)
##
##   attack  … 最大振幅の 50% に達するまでの時間(ms)。短いほど立ち上がりが鋭い
##   centroid… スペクトル重心(Hz)。高いほど明るい
##   loud    … 最も大きい 100ms の平均の大きさ(dBFS。150Hz 以下を落として測る)。聴感上の音量の目安
##   crest   … ピーク ÷ 平均の大きさ(dB)。大きいほど「ピークだけ高くて小さく聞こえる」音
##   edge    … 先頭・末尾のサンプルの大きさ(プチッというノイズの目安。0 に近いほどよい)
##   dc      … 直流成分

const SfxBank = preload("res://scripts/sfx_bank.gd")
const D = preload("res://tools/dsp.gd")
const Recipes = preload("res://tools/sfx_recipes.gd")

## ゲームの発射音 5 種(耳に刺さらない・連打されても疲れない)の基準
const BARRAGE := ["pop", "whistle", "clap", "boom", "tick"]

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _channels(w: AudioStreamWAV) -> Array:
	var n := w.data.size() / (4 if w.stereo else 2)
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(n)
	if w.stereo:
		r.resize(n)
	for i in range(n):
		if w.stereo:
			l[i] = w.data.decode_s16(i * 4) / 32768.0
			r[i] = w.data.decode_s16(i * 4 + 2) / 32768.0
		else:
			l[i] = w.data.decode_s16(i * 2) / 32768.0
	return [l, r]


func _mono_of(w: AudioStreamWAV) -> PackedFloat32Array:
	var ch := _channels(w)
	var l: PackedFloat32Array = ch[0]
	var r: PackedFloat32Array = ch[1]
	var out := l.duplicate()
	if not r.is_empty():
		for i in range(out.size()):
			out[i] = (l[i] + r[i]) * 0.5
	return out


## 音程のはっきりさ(0..1): 500 Hz〜10 kHz のエネルギーのうち、いちばん強い周波数の ±3% に集まっている割合。純音に近いほど 1、ノイズに近いほど 0。
func _tonality(x: PackedFloat32Array) -> float:
	var n := 8192
	var re := PackedFloat32Array()
	var im := PackedFloat32Array()
	re.resize(n)
	im.resize(n)
	for i in range(mini(n, x.size())):
		re[i] = x[i]
	D.fft(re, im)
	var pw := PackedFloat32Array()
	pw.resize(n / 2)
	var total := 1e-12
	var best := 1
	for k in range(1, n / 2):
		var f := float(k) * D.SR / n
		if f < 500.0 or f > 10000.0:
			continue
		pw[k] = re[k] * re[k] + im[k] * im[k]
		total += pw[k]
		if pw[k] > pw[best]:
			best = k
	var near := 0.0
	for k in range(1, n / 2):
		if absf(float(k - best)) <= best * 0.03:
			near += pw[k]
	return near / total


func _init() -> void:
	var dump := OS.get_cmdline_user_args().has("wav")
	if dump:
		DirAccess.make_dir_recursive_absolute("user://sfx_loaded")
	var info := {}
	for nm in Recipes.SPEC:
		var spec: Array = Recipes.SPEC[nm]
		var list := SfxBank.variants(nm)
		_check(list.size() == int(spec[0]), "%s: ファイルが %d 個そろっている(%d)" % [nm, int(spec[0]), list.size()])
		if list.is_empty():
			continue
		var is_loop: bool = spec.size() > 3 and spec[3] == "loop"
		var worst_edge := 0.0
		var worst_peak := 0.0
		var loud_min := 99.0
		var loud_max := -99.0
		var dc := 0.0
		var first_mono: PackedFloat32Array
		for k in range(list.size()):
			var w: AudioStreamWAV = list[k]
			if dump:
				w.save_to_wav("user://sfx_loaded/%s_%d.wav" % [nm, k])
			var ch := _channels(w)
			var l: PackedFloat32Array = ch[0]
			var r: PackedFloat32Array = ch[1]
			var mono := l.duplicate()
			if not r.is_empty():
				for i in range(mono.size()):
					mono[i] = (l[i] + r[i]) * 0.5
			if k == 0:
				first_mono = mono
			# ループの音は、頭と末尾がつながる(段差がない)。それ以外は、0 から始まって 0 で終わる
			if is_loop:   # つなぎ目の段差が、ふだんの隣り合うサンプルの差(の 4 倍)に収まる
				var dsum := 0.0
				for i in range(1, l.size()):
					dsum += (l[i] - l[i - 1]) * (l[i] - l[i - 1])
				var typical := sqrt(dsum / l.size())
				worst_edge = maxf(worst_edge, absf(l[0] - l[l.size() - 1]) / maxf(typical * 4.0, 1e-6) * 0.01)
			else:
				worst_edge = maxf(worst_edge, maxf(absf(l[0]), absf(l[l.size() - 1])))
			worst_peak = maxf(worst_peak, maxf(D.peak(l), D.peak(r)))
			var ld := D.loudness_db(mono)
			loud_min = minf(loud_min, ld)
			loud_max = maxf(loud_max, ld)
			var s := 0.0
			for v in mono:
				s += v
			dc = maxf(dc, absf(s / mono.size()))
		_check(worst_peak <= float(spec[2]) + 0.01 and worst_peak > 0.25, "%s: ピークが範囲内で、歪んでいない・小さすぎない (%.2f)" % [nm, worst_peak])
		_check(worst_edge < 0.01, "%s: %s (%.4f)" % [nm, "ループの継ぎ目に段差がない" if is_loop else "先頭と末尾が 0 から始まり 0 で終わる(プチッと鳴らない)", worst_edge])
		if is_loop:
			var wl: AudioStreamWAV = list[0]
			_check(wl.loop_mode == AudioStreamWAV.LOOP_FORWARD and wl.loop_end > 0, "%s: ループ再生の設定がされている" % nm)
		_check(dc < 0.004, "%s: 直流成分がない (%.4f)" % [nm, dc])
		_check(absf((loud_min + loud_max) * 0.5 - float(spec[1])) < 1.2 and loud_max - loud_min < 1.5, "%s: 大きさが目標 %.1f dB にそろっている(%.1f〜%.1f)" % [nm, float(spec[1]), loud_min, loud_max])
		var x := first_mono
		var peak_v := D.peak(x)
		var attack := 0.0
		for i in range(x.size()):
			if absf(x[i]) >= peak_v * 0.5:
				attack = i / float(D.SR) * 1000.0
				break
		var cen := D.centroid_hz(x)
		var rms := pow(10.0, D.loudness_db(x) / 20.0)
		var crest := D.db(peak_v / maxf(rms, 1e-6))
		info[nm] = {"cen": cen, "dur": x.size() / float(D.SR) * 1000.0, "attack": attack}
		print("%-10s x%d  dur=%4dms  attack=%4.1fms  centroid=%5dHz  loud=%.1f〜%.1fdB  crest=%.1fdB  edge=%.4f" % [nm, list.size(), int(info[nm].dur), attack, int(cen), loud_min, loud_max, crest, worst_edge])
		if nm in BARRAGE:
			_check(attack <= 3.0, "%s: 立ち上がりが速い (%.1fms)" % [nm, attack])
			_check(x.size() / float(D.SR) >= 0.07, "%s: 聞き取れる長さがある (%dms)" % [nm, int(info[nm].dur)])
			_check(list.size() >= 4, "%s: 同じ音の繰り返しに聞こえないよう、変種が 4 個以上ある" % nm)
		# 変種どうしが、実際に違う波形になっている
		if list.size() >= 2:
			var a: AudioStreamWAV = list[0]
			var b: AudioStreamWAV = list[1]
			_check(a.data != b.data, "%s: 変種が同じ波形ではない" % nm)
	# 音の役割どうしの関係(キットとして区別がつく)
	if info.has("tick") and info.has("pop") and info.has("hit") and info.has("boom"):
		_check(info.pop.dur < 220.0 and info.pop.cen > 350.0 and info.pop.cen < 4000.0, "pop は短い打撃音(%dms / 重心 %d Hz)" % [info.pop.dur, info.pop.cen])
		_check(info.tick.dur < 150.0 and info.tick.cen > 1200.0 and info.tick.cen < 5000.0, "tick は短く、耳に刺さらない高さ(%dms / 重心 %d Hz)" % [info.tick.dur, info.tick.cen])
		_check(info.boom.dur > info.pop.dur * 2.0 and info.boom.cen < info.pop.cen, "boom は pop より長く低い重い衝撃(%dms, %d Hz)" % [info.boom.dur, info.boom.cen])
		_check(info.hit.dur < 350.0 and info.hit.cen > 600.0, "hit は触れた瞬間の短い合図で、小さなスピーカーでも聞こえる(%dms / 重心 %d Hz)" % [info.hit.dur, info.hit.cen])
		_check(info.hit_loop.cen > 600.0 and info.hit_loop.cen < 4500.0, "hit_loop は聞き取りやすい中高域の持続音(重心 %d Hz)" % info.hit_loop.cen)
		_check(info.explosion.cen < 600.0 and info.explosion.dur > 1000.0, "爆発は低く長い(%d Hz / %dms)" % [info.explosion.cen, info.explosion.dur])
		# tick は曲のメロディと重なって続けて鳴るので、はっきりした音程を持たない(どの変種も)。比べのため、音程のある whistle も測る
		var worst_tone := 0.0
		for w in SfxBank.variants("tick"):
			worst_tone = maxf(worst_tone, _tonality(_mono_of(w)))
		var whistle_tone := _tonality(_mono_of(SfxBank.variants("whistle")[0]))
		_check(worst_tone < 0.25 and whistle_tone > worst_tone * 2.0, "tick ははっきりした音程を持たない(メロディとぶつからない): 音程の強さ 最大 %.2f(whistle %.2f)" % [worst_tone, whistle_tone])
	# UI の音: 耳に刺さらない(スペクトル重心 4 kHz 未満)・長すぎない
	for nm in ["hover", "click", "select", "back", "on", "off", "tick_ui", "count", "toast"]:
		if info.has(nm):
			_check(info[nm].cen < 4000.0 and info[nm].dur < 800.0, "%s: UI の音は高すぎず・長すぎない (%d Hz / %dms)" % [nm, info[nm].cen, info[nm].dur])
	# 書き出したファイルが、レシピから作り直したものと同じ(レシピを直して書き出し忘れていない)
	var stale := 0
	for nm in ["pop", "hover", "explosion"]:
		var rendered: Dictionary = Recipes.render(nm, 0)
		var bytes := D.wav_bytes(rendered.l, rendered.r)
		if FileAccess.get_file_as_bytes("%s%s_0.sfx" % [SfxBank.DIR, nm]) != bytes:
			stale += 1
	_check(stale == 0, "ファイルがレシピどおり(古くない)。違うときは tools/sfx_forge.gd で書き出し直す")
	if dump:
		print("WAV を書き出しました: ", ProjectSettings.globalize_path("user://sfx_loaded"))
	print("RESULT: ", "OK" if _fail == 0 else "%d FAILURES" % _fail)
	quit(1 if _fail > 0 else 0)
