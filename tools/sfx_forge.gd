extends SceneTree
## 効果音を作って、assets/sfx/ に書き出す(開発用。ゲームの実行には要らない)。
##   godot --headless --path . --script tools/sfx_forge.gd                  全部の音を書き出す
##   godot --headless --path . --script tools/sfx_forge.gd -- pop hit       名前を指定して書き出す
##   godot --headless --path . --script tools/sfx_forge.gd -- --verify      今の assets/sfx がレシピどおりか確かめる(書き出さない)
##   godot --headless --path . --script tools/sfx_forge.gd -- --preview     書き出したうえで、確認用の WAV・画像(スペクトログラム + 波形)と
##                                                                        聴き比べのページ(sfx_preview/index.html)をプロジェクト直下の sfx_preview/ に出す
##   godot --headless --path . --script tools/sfx_forge.gd -- --snapshot    今の assets/sfx を「前の音」として sfx_preview/before/ に取っておく
##                                                                        (レシピを直す前に取っておくと、index.html で前と今を並べて聴ける)
## 書き出すファイルは「中身が標準の WAV で、拡張子が .sfx」のもの(Godot のインポートに通さず、そのまま読めるようにするため)。
## 名前は <音>_<変種の番号>.sfx。ゲームは scripts/sfx_bank.gd で読む。

const D = preload("res://tools/dsp.gd")
const Recipes = preload("res://tools/sfx_recipes.gd")

const OUT_DIR := "res://assets/sfx"
const PREVIEW_DIR := "res://sfx_preview"   # .gitignore 済み。.gdignore を置いて、Godot のインポートから外す
const BEFORE_DIR := "res://sfx_preview/before"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var verify := args.has("--verify")
	var preview := args.has("--preview")
	if args.has("--snapshot"):
		_snapshot()
		quit(0)
		return
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
		_touch_gdignore()
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
		_write_index()
		print("聴き比べのページ: ", ProjectSettings.globalize_path(PREVIEW_DIR + "/index.html"))
	quit(1 if stale > 0 else 0)


func _preview(nm: String, s: Dictionary) -> void:
	var x: PackedFloat32Array = s.l
	var img := D.spectrogram(x)
	img.save_png("%s/%s.png" % [PREVIEW_DIR, nm])


## 確認用のフォルダを、Godot のインポートから外す(WAV がリソースとして取り込まれないように)。
func _touch_gdignore() -> void:
	var p := PREVIEW_DIR + "/.gdignore"
	if not FileAccess.file_exists(p):
		FileAccess.open(p, FileAccess.WRITE).close()


## 今の assets/sfx(中身は WAV)を、sfx_preview/before/ に .wav として写す。
func _snapshot() -> void:
	DirAccess.make_dir_recursive_absolute(BEFORE_DIR)
	_touch_gdignore()
	var d := DirAccess.open(BEFORE_DIR)
	for f in d.get_files():
		if f.ends_with(".wav"):
			d.remove(f)
	var n := 0
	for f in DirAccess.get_files_at(OUT_DIR):
		if f.ends_with(".sfx"):
			var bytes := FileAccess.get_file_as_bytes("%s/%s" % [OUT_DIR, f])
			var wf := FileAccess.open("%s/%s" % [BEFORE_DIR, f.get_basename() + ".wav"], FileAccess.WRITE)
			wf.store_buffer(bytes)
			wf.close()
			n += 1
	print("前の音として %d 個を取っておきました: %s" % [n, ProjectSettings.globalize_path(BEFORE_DIR)])


## 聴き比べのページ(ブラウザで開く)。音ごとに、今の変種・前の変種(あれば)・スペクトログラムを並べる。
## 「連打」ボタンは、ゲーム中のように変種をランダムに(同じものを続けずに)短い間隔で 8 回鳴らす。
func _write_index() -> void:
	var rows := ""
	for nm in Recipes.SPEC:
		var count := int(Recipes.SPEC[nm][0])
		var now_files: Array = []
		var before_files: Array = []
		for k in range(16):
			if k < count and FileAccess.file_exists("%s/%s_%d.wav" % [PREVIEW_DIR, nm, k]):
				now_files.append("%s_%d.wav" % [nm, k])
			if FileAccess.file_exists("%s/%s_%d.wav" % [BEFORE_DIR, nm, k]):
				before_files.append("before/%s_%d.wav" % [nm, k])
		rows += "<tr><th>%s</th><td>%s</td><td>%s</td><td><img src=\"%s.png\" loading=\"lazy\"></td></tr>\n" % [
			nm, _cell(now_files), _cell(before_files) if not before_files.is_empty() else "<span class=dim>なし</span>", nm]
	var html := """<!doctype html><html lang="ja"><meta charset="utf-8"><title>DDA 効果音の聴き比べ</title>
<style>
body{background:#0b0d16;color:#dde;font:14px/1.5 system-ui,sans-serif;margin:24px}
table{border-collapse:collapse}td,th{border-bottom:1px solid #223;padding:8px 10px;vertical-align:top;text-align:left}
th{font-size:16px;color:#9cf;white-space:nowrap}img{width:360px;border-radius:4px}
button{background:#1b2440;color:#dde;border:1px solid #345;border-radius:6px;padding:3px 9px;margin:2px;cursor:pointer}
button:hover{background:#263257}.dim{color:#667}.rap{background:#2a2050}
</style>
<h1>DDA 効果音の聴き比べ</h1>
<p class=dim>「今」= assets/sfx(tools/sfx_forge.gd -- --preview で作り直した音)/「前」= sfx_preview/before(-- --snapshot で取っておいた音)。
数字のボタンで変種を 1 つずつ、「連打」でゲーム中のように変種をランダムに 8 回鳴らします。</p>
<table><tr><th>音</th><th>今</th><th>前</th><th>スペクトログラム(今の 0 番)</th></tr>
%s</table>
<script>
function play(src){const a=new Audio(src);a.play();}
function rapid(list,gap){let last=-1;for(let i=0;i<8;i++){let k=Math.floor(Math.random()*list.length);if(list.length>1&&k===last)k=(k+1)%%list.length;last=k;const s=list[k];setTimeout(()=>play(s),i*gap);}}
</script></html>
""" % rows
	var f := FileAccess.open(PREVIEW_DIR + "/index.html", FileAccess.WRITE)
	f.store_string(html)
	f.close()


func _cell(files: Array) -> String:
	if files.is_empty():
		return ""
	var s := ""
	for i in range(files.size()):
		s += "<button onclick=\"play('%s')\">%d</button>" % [files[i], i]
	var list := JSON.stringify(files).replace("\"", "'")
	s += "<br><button class=rap onclick=\"rapid(%s,170)\">連打(170ms)</button><button class=rap onclick=\"rapid(%s,90)\">速く(90ms)</button>" % [list, list]
	return s
