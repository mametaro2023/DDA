extends SceneTree
## 曲を選んだときの処理時間の内訳(開発用)。godot --headless --path . --script tests/prof_select.gd

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const SongLibrary = preload("res://scripts/song_library.gd")


func _init() -> void:
	for p in SongLibrary.find_all():
		var t0 := Time.get_ticks_usec()
		var l := OszLoader.new()
		if not l.open(p):
			continue
		var t1 := Time.get_ticks_usec()
		var first = l.difficulties[0]
		var img = l.load_image(first.background) if first.background != "" else null
		var t2 := Time.get_ticks_usec()
		for bm in l.difficulties:
			PatternGen.generate(bm, {"density_mul": 1.0})
		var t3 := Time.get_ticks_usec()
		var a = l.load_audio(first.audio_filename)
		var t4 := Time.get_ticks_usec()
		print("%-40s open %4d ms | image %4d ms | gen(%d) %4d ms | audio %4d ms" % [str(p).get_file().left(40), (t1 - t0) / 1000, (t2 - t1) / 1000, l.difficulties.size(), (t3 - t2) / 1000, (t4 - t3) / 1000])
	quit()
