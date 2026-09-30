extends SceneTree
## godot --headless --path . --script tests/test_parser.gd -- <path.osz>

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const Beatmap = preload("res://scripts/osu/beatmap.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var osz := args[0] if args.size() > 0 else "C:/Desktop/my_apps/DDA/320118 Reol - No title.osz"
	var loader := OszLoader.new()
	_check(loader.open(osz), "open: " + loader.error)
	print("difficulties: ", loader.difficulties.size())
	for bm in loader.difficulties:
		var n_c := 0
		var n_s := 0
		var n_sp := 0
		var kiai := 0
		var min_span := 1e9
		var max_span := 0.0
		var prev := -1.0
		var sorted := true
		for o in bm.hit_objects:
			match o.kind:
				Beatmap.KIND_CIRCLE: n_c += 1
				Beatmap.KIND_SLIDER:
					n_s += 1
					min_span = minf(min_span, o.span_duration)
					max_span = maxf(max_span, o.span_duration)
					_check(o.curve.total > 0.0 or o.length == 0.0, "slider path empty @%d" % o.time)
					_check(absf(o.curve.total - o.length) < 0.5, "slider length mismatch @%d: %f vs %f" % [o.time, o.curve.total, o.length])
					_check(o.span_duration > 0.0 and o.span_duration < 20000.0, "slider duration odd @%d: %f" % [o.time, o.span_duration])
				Beatmap.KIND_SPINNER: n_sp += 1
			if bm.kiai_at(o.time):
				kiai += 1
			if o.time < prev:
				sorted = false
			prev = o.time
			_check(o.end_time >= o.time, "end<start")
		_check(sorted, "objects not sorted")
		_check(bm.timing_points.size() > 0, "no timing points")
		print("%-28s circles=%4d sliders=%4d spinners=%d kiaiObjs=%4d density=%.2f/s AR=%.1f preempt=%.0fms slider span %.0f..%.0fms first=%.0f last=%.0f" % [
			bm.version, n_c, n_s, n_sp, kiai, bm.density(), bm.ar, bm.preempt_ms(),
			min_span if n_s > 0 else 0.0, max_span, bm.first_time(), bm.last_time()])
	if loader.difficulties.size() > 0:
		var bm0 = loader.difficulties[0]
		var audio := loader.load_audio(bm0.audio_filename)
		_check(audio != null, "audio load")
		if audio != null:
			print("audio: %s length=%.2fs" % [bm0.audio_filename, audio.get_length()])
		var bg := loader.load_image(bm0.background) if bm0.background != "" else null
		print("background: '%s' -> %s" % [bm0.background, str(bg)])
	loader.close()
	print("RESULT: ", "OK" if _fail == 0 else "%d FAILURES" % _fail)
	quit(1 if _fail > 0 else 0)
