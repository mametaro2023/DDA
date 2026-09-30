extends SceneTree
## 効果音(合成波形)の性質を測る。弾幕の発射音が「弾けるような」音になっているかの目安。
## godot --headless --path . --script tests/test_sfx.gd
##   attack   … 最大振幅の 50% に達するまでの時間(ms)。短いほど「パチッ」と立ち上がる
##   bright   … ゼロ交差率から見た明るさ(kHz 相当)。高いほど「シャリッ」とした音
##   front    … 最初の 15 ms の エネルギー ÷ 全体 (%)。高いほど破裂的(だらだら鳴らない)
##   bursts   … 包絡の山(粒)の数。多いほど、小さな粒が飛び散る感じ
##   noisy    … 波形の細かさ(1 サンプル差分のエネルギー比)。純音(サイン波)は 0.1 前後、白色ノイズは 2 近い。高いほど「パン」というノイズ主体の破裂、低いほど「キュー」という音程のある音

const Sfx = preload("res://scripts/game/sfx.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _samples(w: AudioStreamWAV) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := w.data.size() / 2
	out.resize(n)
	for i in range(n):
		out[i] = w.data.decode_s16(i * 2) / 32768.0
	return out


func _init() -> void:
	var s := Sfx.new()
	var names := ["pop", "whistle", "clap", "boom", "tick", "hit", "explosion"]
	var dump := OS.get_cmdline_user_args().has("wav")   # 引数 wav で、全部の音を WAV に書き出す(耳で確かめる用)
	if dump:
		DirAccess.make_dir_recursive_absolute("user://sfx_preview")
	for nm in names:
		var w: AudioStreamWAV = s._streams[nm]
		var x := _samples(w)
		if dump:
			w.save_to_wav("user://sfx_preview/%s.wav" % nm)
		var rate := float(w.mix_rate)
		var peak := 0.0
		for v in x:
			peak = maxf(peak, absf(v))
		var attack := 0.0
		for i in range(x.size()):
			if absf(x[i]) >= peak * 0.5:
				attack = i / rate * 1000.0
				break
		var zc := 0
		for i in range(1, x.size()):
			if (x[i] >= 0.0) != (x[i - 1] >= 0.0):
				zc += 1
		var bright := zc / 2.0 / (x.size() / rate) / 1000.0
		var e_all := 0.0
		var e_front := 0.0
		for i in range(x.size()):
			e_all += x[i] * x[i]
			if i < int(0.015 * rate):
				e_front += x[i] * x[i]
		# 包絡(2 ms ごとの最大)の山を数える
		var win := int(0.002 * rate)
		var env: Array = []
		for i in range(0, x.size() - win, win):
			var m := 0.0
			for j in range(win):
				m = maxf(m, absf(x[i + j]))
			env.append(m)
		var dsum := 0.0
		for i in range(1, x.size()):
			dsum += (x[i] - x[i - 1]) * (x[i] - x[i - 1])
		var noisy := dsum / maxf(e_all, 1e-9)
		var e60 := 0.0   # 最初の 60ms の平均の大きさ(RMS)。聴感上の音量の目安
		var n60 := mini(int(0.06 * rate), x.size())
		for i in range(n60):
			e60 += x[i] * x[i]
		var rms60_db := 10.0 * log(maxf(e60 / n60, 1e-12)) / log(10.0)
		var front := e_front / maxf(e_all, 1e-9)
		var bursts := 0
		for i in range(1, env.size() - 1):
			if env[i] > env[i - 1] * 1.25 and env[i] >= env[i + 1] and env[i] > peak * 0.08:
				bursts += 1
		print("%-10s dur=%3dms peak=%.2f attack=%4.1fms bright=%4.1fkHz front=%3d%% bursts=%2d noisy=%.2f rms60=%.1fdB" % [nm, int(x.size() / rate * 1000.0), peak, attack, bright, int(e_front / maxf(e_all, 1e-9) * 100.0), bursts, noisy, rms60_db])
		_check(peak > 0.3 and peak <= 1.0, "%s: 無音でも歪みでもない (peak %.2f)" % [nm, peak])
		if nm in ["pop", "whistle", "clap", "boom", "tick"]:
			_check(x.size() / rate >= 0.15, "%s: 聞き取れる長さがある (%dms)" % [nm, int(x.size() / rate * 1000.0)])
			_check(attack <= 3.0, "%s: 立ち上がりが速い (%.1fms)" % [nm, attack])
			_check(front >= 0.3, "%s: 最初の 15ms にエネルギーが集中している(破裂的、だらだら鳴らない) (%d%%)" % [nm, int(front * 100.0)])
			_check(noisy >= 0.4, "%s: ノイズ主体の破裂(音程のある「キュッ」ではない) (noisy %.2f)" % [nm, noisy])
	if dump:
		print("WAV を書き出しました: ", ProjectSettings.globalize_path("user://sfx_preview"))
	print("RESULT: ", "OK" if _fail == 0 else "%d FAILURES" % _fail)
	quit(1 if _fail > 0 else 0)
