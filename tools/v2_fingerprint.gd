extends SceneTree
## 弾幕 v2 の調整用: 譜面ごとの指紋(クラスの割合・往復・広がりなど)と、区間ごとのモチーフの割り当てを表にして出す。
## godot --headless --path . --script tools/v2_fingerprint.gd -- [osz のパス ...] [sections]
##   引数なし: 手元の全 .osz の、各譜面(難易度)の指紋を 1 行ずつ。sections を付けると、区間ごとの割り当ても出す。

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const ChartProfile = preload("res://scripts/game/chart_profile.gd")
const PatternGenV2 = preload("res://scripts/game/pattern_gen_v2.gd")

const DIR := "C:/Desktop/my_apps/DDA/"


func _init() -> void:
	var paths: Array = []
	var show_sections := false
	for a in OS.get_cmdline_user_args():
		if a == "sections":
			show_sections = true
		else:
			paths.append(a)
	if paths.is_empty():
		var d := DirAccess.open(DIR)
		for f in d.get_files():
			if f.ends_with(".osz"):
				paths.append(DIR + f)
		paths.sort()
	print("%-34s %-22s %5s %4s | %s | dist  alt  fin  spr | motifs(区間数)" % ["set", "difficulty", "stars", "n", " ".join(ChartProfile.CLS_NAMES.map(func(s): return s.substr(0, 4)))])
	for path in paths:
		var l = OszLoader.new()
		if not l.open(path):
			print("open failed: ", path)
			continue
		for bm in l.difficulties:
			var prof := ChartProfile.analyze(bm)
			var m: Dictionary = prof.map
			var sh: Array = (m.share as Array).map(func(x): return "%.2f" % x)
			var asg := PatternGenV2.assign_motifs(bm, prof)
			var hist := {}
			for mt in asg.motifs:
				var nm: String = PatternGenV2.MOTIF_NAMES[mt]
				hist[nm] = int(hist.get(nm, 0)) + 1
			var hs := ""
			for k in hist:
				hs += "%s:%d " % [k, hist[k]]
			print("%-34s %-22s %5.2f %4d | %s | %4.0f %4.2f %4.2f %3.0f | sig=%s %s" % [
				path.get_file().left(34), bm.version.left(22), bm.stars, m.n, " ".join(sh), m.mean_dist, m.alt, m.finish, m.spread,
				PatternGenV2.MOTIF_NAMES[asg.signature], hs])
			if show_sections:
				for j in range(prof.sections.size()):
					var s: Dictionary = prof.sections[j]
					if s.n == 0:
						continue
					print("    %6.1f-%6.1f n=%3d rate=%4.1f str=%.2f jmp=%.2f sld=%.2f spr=%.2f alt=%.2f turn=%+.2f fin=%.2f %s -> %s" % [
						s.t0, s.t1, s.n, s.rate, s.share[0], s.share[1], s.share[2], s.share[4], s.alt, s.turn_mean, s.finish,
						"kiai" if s.kiai else "    ", PatternGenV2.MOTIF_NAMES[asg.motifs[j]]])
		l.close()
	quit()
