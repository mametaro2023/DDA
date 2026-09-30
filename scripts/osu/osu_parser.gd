extends RefCounted
## .osu テキスト → Beatmap

const Beatmap = preload("res://scripts/osu/beatmap.gd")
const SliderPath = preload("res://scripts/osu/slider_path.gd")
const StarRating = preload("res://scripts/osu/star_rating.gd")


static func parse(text: String, source_file := "") -> Beatmap:
	var bm := Beatmap.new()
	bm.source_file = source_file
	var section := ""
	var raw_objects: Array = []
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2)
			continue
		match section:
			"General", "Metadata", "Difficulty":
				_parse_kv(bm, line)
			"Events":
				_parse_event(bm, line)
			"TimingPoints":
				_parse_timing(bm, line)
			"HitObjects":
				raw_objects.append(line)
	bm.timing_points = _sorted_points(bm.timing_points)
	_build_objects(bm, raw_objects)
	bm.stars = StarRating.estimate(bm)
	return bm


## 譜面の「中身」の識別子(MD5 の形の文字列)。プレイに関わる部分(難易度の数値・タイミング・ノーツ・休憩)だけから作り、
## 曲名・作者・ID・タグ・背景・ヒットサンプルなどは含めない。配布元や版が違って、ファイルが少し違っても、同じ譜面なら同じ値になる
## (マルチプレイで、参加者が同じ譜面を持っているかの照合に使う)。パースはせず、文字だけを見るので軽い。
static func play_key(text: String) -> String:
	var section := ""
	var parts := PackedStringArray()
	var d := {"AudioLeadIn": "0", "Mode": "0", "HPDrainRate": "5", "CircleSize": "5", "OverallDifficulty": "5", "SliderMultiplier": "1.4", "SliderTickRate": "1"}
	var ar := ""
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2)
			continue
		match section:
			"General", "Difficulty":
				var i := line.find(":")
				if i > 0:
					var k := line.substr(0, i).strip_edges()
					var v := line.substr(i + 1).strip_edges()
					if k == "ApproachRate":
						ar = v
					elif d.has(k):
						d[k] = v
			"Events":
				var p := line.split(",")
				if p.size() >= 3 and (p[0].strip_edges() == "2" or p[0].strip_edges() == "Break"):
					parts.append("E%d,%d" % [int(float(p[1])), int(float(p[2]))])
			"TimingPoints":
				parts.append("T" + ",".join(line.split(",").slice(0, 8)))
			"HitObjects":
				var p := line.split(",")
				# 円は 5 項目(x,y,時刻,種類,ヒットサウンド)、スピナーは 6、スライダーは 9(端ごとのサウンドまで)。その先はヒットサンプル(プレイに関係しない)
				var n := 5
				if p.size() > 3:
					var type := int(p[3])
					n = 9 if (type & 2) != 0 else (6 if (type & 8) != 0 else 5)
				parts.append("H" + ",".join(p.slice(0, n)))
	# 古い形式では AR が無く OD が AR を兼ねる(あとから AR が足された版と同じ扱いにする)
	var head := "%s|%s|%s|%s|%s|%s|%s|%s" % [d.Mode, d.AudioLeadIn, d.HPDrainRate.to_float(), d.CircleSize.to_float(), d.OverallDifficulty.to_float(),
		(ar if ar != "" else d.OverallDifficulty).to_float(), d.SliderMultiplier.to_float(), d.SliderTickRate.to_float()]
	return (head + "\n" + "\n".join(parts)).md5_text()


## 一覧に出すための簡単な読み取り(解析はしない): {mode, title, artist, objects(ノーツがあるか。0 か 1)}。
static func quick_info(text: String) -> Dictionary:
	var out := {"mode": 0, "title": "", "artist": "", "objects": 0}
	var section := ""
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2)
			continue
		if section == "HitObjects":
			if line.split(",").size() >= 5:
				out.objects = 1
				break
			continue
		var i := line.find(":")
		if i < 0:
			continue
		var k := line.substr(0, i).strip_edges()
		var v := line.substr(i + 1).strip_edges()
		if section == "General" and k == "Mode":
			out.mode = int(v)
		elif section == "Metadata":
			if k == "Title":
				out.title = v
			elif k == "Artist":
				out.artist = v
	return out


static func _parse_kv(bm: Beatmap, line: String) -> void:
	var i := line.find(":")
	if i < 0:
		return
	var k := line.substr(0, i).strip_edges()
	var v := line.substr(i + 1).strip_edges()
	match k:
		"AudioFilename": bm.audio_filename = v
		"AudioLeadIn": bm.audio_lead_in = int(v)
		"PreviewTime": bm.preview_time = int(v)
		"Mode": bm.mode = int(v)
		"Title": bm.title = v
		"TitleUnicode": pass
		"Artist": bm.artist = v
		"Version": bm.version = v
		"Creator": bm.creator = v
		"BeatmapID": bm.beatmap_id = int(v)
		"BeatmapSetID": bm.beatmapset_id = int(v)
		"HPDrainRate": bm.hp = float(v)
		"CircleSize": bm.cs = float(v)
		"OverallDifficulty":
			bm.od = float(v)
			# 古い形式では AR が無く OD が AR を兼ねる
			if not bm.ar_set:
				bm.ar = bm.od
		"ApproachRate":
			bm.ar = float(v)
			bm.ar_set = true
		"SliderMultiplier": bm.slider_multiplier = float(v)
		"SliderTickRate": bm.slider_tick_rate = float(v)


static func _parse_event(bm: Beatmap, line: String) -> void:
	var p := line.split(",")
	if p.size() < 3:
		return
	var t := p[0].strip_edges()
	if t == "2" or t == "Break":
		bm.breaks.append([float(p[1]), float(p[2])])
	elif (t == "0") and bm.background.is_empty():
		bm.background = p[2].strip_edges().trim_prefix("\"").trim_suffix("\"")


static func _parse_timing(bm: Beatmap, line: String) -> void:
	var p := line.split(",")
	if p.size() < 2:
		return
	var uninherited := true
	if p.size() > 6:
		uninherited = p[6].strip_edges() != "0"
	elif float(p[1]) < 0.0:
		uninherited = false
	var effects := int(p[7]) if p.size() > 7 else 0
	bm.timing_points.append({
		"time": float(p[0]),
		"beat_length": float(p[1]),
		"uninherited": uninherited,
		"kiai": (effects & 1) != 0,
		"meter": int(p[2]) if p.size() > 2 else 4,
		"_i": bm.timing_points.size(),
	})


static func _sorted_points(pts: Array) -> Array:
	# 同時刻は記述順を保つ(sort_custom は不安定)
	var out := pts.duplicate()
	out.sort_custom(func(a, b): return a.time < b.time if a.time != b.time else a._i < b._i)
	return out


static func _build_objects(bm: Beatmap, lines: Array) -> void:
	var combo := 0
	for line in lines:
		var p: PackedStringArray = line.split(",")
		if p.size() < 5:
			continue
		var type := int(p[3])
		var o := {
			"pos": Vector2(float(p[0]), float(p[1])),
			"time": float(p[2]),
			"hitsound": int(p[4]),
			"new_combo": (type & 4) != 0,
		}
		if o.new_combo:
			combo += 1
		o["combo_index"] = combo
		if (type & 1) != 0:
			o["kind"] = Beatmap.KIND_CIRCLE
			o["end_time"] = o.time
		elif (type & 2) != 0 and p.size() >= 8:
			_build_slider(bm, o, p)
		elif (type & 8) != 0 and p.size() >= 6:
			o["kind"] = Beatmap.KIND_SPINNER
			o["end_time"] = maxf(float(p[5]), o.time)
		else:
			continue
		bm.hit_objects.append(o)
	bm.hit_objects.sort_custom(func(a, b): return a.time < b.time)


static func _build_slider(bm: Beatmap, o: Dictionary, p: PackedStringArray) -> void:
	o["kind"] = Beatmap.KIND_SLIDER
	var curve_parts := p[5].split("|")
	var ctrl := PackedVector2Array()
	ctrl.append(o.pos)
	for i in range(1, curve_parts.size()):
		var xy := curve_parts[i].split(":")
		if xy.size() == 2:
			ctrl.append(Vector2(float(xy[0]), float(xy[1])))
	var repeats := maxi(int(p[6]), 1)
	var length := maxf(float(p[7]), 0.0)
	var curve := SliderPath.new()
	curve.setup(curve_parts[0], ctrl, length)
	var beat := bm.beat_length_at(o.time)
	var sv := bm.sv_at(o.time)
	var span := length / (bm.slider_multiplier * 100.0 * sv) * beat
	o["curve"] = curve
	o["repeats"] = repeats
	o["length"] = length
	o["span_duration"] = span
	o["end_time"] = o.time + span * repeats
	var edges: Array = []
	if p.size() > 8:
		for s in p[8].split("|"):
			edges.append(int(s))
	o["edge_sounds"] = edges
