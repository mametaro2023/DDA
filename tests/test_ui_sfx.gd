extends SceneTree
## UI 効果音(合成波形)の性質を測る。耳に刺さらない・プチッというノイズが出ない・長すぎない・無音でない、を確かめる。
## godot --headless --path . --script tests/test_ui_sfx.gd
##   引数 wav を付けると、全部の音を user://ui_sfx_preview/*.wav に書き出す(耳で確かめる用)

const UiSfx = preload("res://scripts/ui/ui_sfx.gd")

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
	var s := UiSfx.new()
	var dump := OS.get_cmdline_user_args().has("wav")
	if dump:
		DirAccess.make_dir_recursive_absolute("user://ui_sfx_preview")
	# SPECS にある音は、すべて波形がある
	for nm in UiSfx.SPECS:
		_check(s._streams.has(nm), "%s: 波形がある" % nm)
	for nm in s._streams:
		var w: AudioStreamWAV = s._streams[nm]
		var x := _samples(w)
		if dump:
			w.save_to_wav("user://ui_sfx_preview/%s.wav" % nm)
		var rate := float(w.mix_rate)
		var dur := x.size() / rate
		var peak := 0.0
		var sq := 0.0
		for v in x:
			peak = maxf(peak, absf(v))
			sq += v * v
		var rms := sqrt(sq / maxf(x.size(), 1))
		var first := absf(x[0])
		var last := absf(x[x.size() - 1])
		print("%-8s %4.0f ms  peak %.2f  rms %.3f  first %.4f  last %.4f" % [nm, dur * 1000.0, peak, rms, first, last])
		_check(dur >= 0.02 and dur <= 0.6, "%s: 長さが 20〜600 ms(%.0f ms)" % [nm, dur * 1000.0])
		_check(peak > 0.15, "%s: 無音ではない(最大振幅 %.2f)" % [nm, peak])
		_check(peak < 0.98, "%s: 割れない(最大振幅 %.2f。16bit に収めるとき上限に張り付かない)" % [nm, peak])
		_check(first < 0.02 and last < 0.02, "%s: 始まりと終わりがゼロから(プチッというノイズが出ない)" % nm)
	# 音量: 設定の「UI の音」を切ると鳴らさない(ログには残る)
	UiSfx.inst = s
	UiSfx.enabled = false
	var before := s.log.size()
	UiSfx.play("click")
	_check(s.log.size() == before + 1, "再生要求は記録される")
	UiSfx.enabled = true
	# 音階: 0..1 を昇順の音程にする
	var prev := 0.0
	var inc := true
	for i in range(11):
		var p := UiSfx.scale_pitch(i / 10.0, 1.0)
		if p < prev:
			inc = false
		prev = p
	_check(inc, "scale_pitch は 0→1 で下がらない")
	_check(is_equal_approx(UiSfx.scale_pitch(0.0), 1.0), "scale_pitch(0) は基準の音程")
	_check(UiSfx.scale_pitch(1.0, 1.0) > 1.9 and UiSfx.scale_pitch(1.0, 1.0) < 2.1, "scale_pitch(1, 1 オクターブ) は約 2 倍")
	UiSfx.inst = null
	print("RESULT: ", "OK" if _fail == 0 else "%d FAILURES" % _fail)
	quit(1 if _fail > 0 else 0)
