extends SceneTree
## PLAY を押してから自機が出るまでに、主スレッドで行う処理の時間の内訳(開発用)。godot --headless --path . --script tests/prof_play.gd
## 各曲の一番難しい譜面で、プレイ画面の _ready と同じ処理を測る。

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")
const BulletField = preload("res://scripts/game/bullet_field.gd")
const Mods = preload("res://scripts/mods.gd")
const SongLibrary = preload("res://scripts/song_library.gd")


func _init() -> void:
	for p in SongLibrary.find_all():
		var l := OszLoader.new()
		if not l.open(p):
			continue
		var bm = l.difficulties[l.difficulties.size() - 1]
		var t0 := Time.get_ticks_usec()
		var img = l.load_image(bm.background) if bm.background != "" else null
		var t1 := Time.get_ticks_usec()
		var a = l.load_audio(bm.audio_filename)
		var t2 := Time.get_ticks_usec()
		var gen := PatternGen.generate(bm, {"density_mul": 1.0})
		var t3 := Time.get_ticks_usec()
		var mp := Mods.params([])
		var g2 := Mods.apply(gen, mp)
		var t4 := Time.get_ticks_usec()
		var field := BulletField.new()
		var sim := GameSim.new()
		sim.setup(field, g2, bm.last_time() / 1000.0 + 2.0, false, mp)
		var t5 := Time.get_ticks_usec()
		print("%-34s image %4d ms | audio %4d ms | generate %4d ms | Mods.apply %4d ms | sim.setup %4d ms | events %d" % [
			str(p).get_file().left(34), (t1 - t0) / 1000, (t2 - t1) / 1000, (t3 - t2) / 1000, (t4 - t3) / 1000, (t5 - t4) / 1000, gen.events.size()])
	quit()
