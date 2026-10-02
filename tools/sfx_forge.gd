extends SceneTree
## 効果音を作って、assets/sfx/ に書き出す(開発用。ゲームの実行には要らない)。
##   godot --headless --path . --script tools/sfx_forge.gd                  全部の音を書き出す
##   godot --headless --path . --script tools/sfx_forge.gd -- pop hit       名前を指定して書き出す
##   godot --headless --path . --script tools/sfx_forge.gd -- --verify      今の assets/sfx がレシピどおりか確かめる(書き出さない)
##   godot --headless --path . --script tools/sfx_forge.gd -- --preview     確認用の画像(スペクトログラム + 波形)と WAV を user://sfx_preview に出す
## 書き出すファイルは「中身が標準の WAV で、拡張子が .sfx」のもの(Godot のインポートに通さず、そのまま読めるようにするため)。
## 名前は <音>_<変種の番号>.sfx。ゲームは scripts/sfx_bank.gd で読む。

const D = preload("res://tools/dsp.gd")
const Recipes = preload("res://tools/sfx_recipes.gd")

const OUT_DIR := "res://assets/sfx"
const PREVIEW_DIR := "user://sfx_preview"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var verify := args.has("--verify")
	var preview := args.has("--preview")
	var names: Array = []
	for a in args:
		if not str(a).begins_with("--"):
			names.append(str(a))
	var all := names.is_empty()
	if all:
		names = Recipes.SPEC.keys()
	if not verify:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	if preview:
		DirAccess.make_dir_recursive_absolute(PREVIEW_DIR)
		if all:   # 全部を作り直すときは、前の確認用ファイルを消す(古い変種が残らないように)
			var d := DirAccess.open(PREVIEW_DIR)
			for f in d.get_files():
				if f.ends_with(".wav") or f.ends_with(".png"):
					d.remove(f)
	var stale := 0
	var total_bytes := 0
	var t0 := Time.get_ticks_msec()
	for nm in names:
		if not Recipes.SPEC.has(nm):
			printerr("知らない音: ", nm)
			continue
		var spec: Array = Recipes.SPEC[nm]
		if not verify:   # 変種の数を減らしたときの、古いファイルを消す
			for k in range(int(spec[0]), 16):
				var old := "%s/%s_%d.sfx" % [OUT_DIR, nm, k]
				if FileAccess.file_exists(old):
					DirAccess.remove_absolute(old)
		for k in range(int(spec[0])):
			var s: Dictionary = Recipes.render(nm, k)
			var bytes := D.wav_bytes(s.l, s.r)
			total_bytes += bytes.size()
			var path := "%s/%s_%d.sfx" % [OUT_DIR, nm, k]
			if verify:
				if not FileAccess.file_exists(path) or FileAccess.get_file_as_bytes(path) != bytes:
					stale += 1
					printerr("古い / ない: ", path)
				continue
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_buffer(bytes)
			f.close()
			if preview and k == 0:
				_preview(nm, s)
			if preview:
				var wf := FileAccess.open("%s/%s_%d.wav" % [PREVIEW_DIR, nm, k], FileAccess.WRITE)
				wf.store_buffer(bytes)
				wf.close()
		if not verify:
			var s0: Dictionary = Recipes.render(nm, 0)
			var probe: PackedFloat32Array = s0.l
			print("%-10s x%d  %4d ms%s  peak %.2f  loud %.1f dB  centroid %5d Hz" % [nm, int(spec[0]), probe.size() * 1000 / D.SR, " (stereo)" if not (s0.r as PackedFloat32Array).is_empty() else "         ",
				maxf(D.peak(probe), D.peak(s0.r)), D.loudness_db(probe), int(D.centroid_hz(probe))])
	print("%s: %d bytes, %d ms" % ["確認" if verify else "書き出し", total_bytes, Time.get_ticks_msec() - t0])
	if verify:
		print("verify: ", "OK" if stale == 0 else "%d 個が古い / ない" % stale)
	elif preview:
		print("確認用の画像・WAV: ", ProjectSettings.globalize_path(PREVIEW_DIR))
	quit(1 if stale > 0 else 0)


func _preview(nm: String, s: Dictionary) -> void:
	var x: PackedFloat32Array = s.l
	var img := D.spectrogram(x)
	img.save_png("%s/%s.png" % [PREVIEW_DIR, nm])
