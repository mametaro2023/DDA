extends SceneTree
## 弾速の実験(scripts/speed_study.gd)の記録を集計する(開発用)。
##   godot --headless --path . --script tools/speed_study_report.gd                 user://speed_study.csv を集計する
##   godot --headless --path . --script tools/speed_study_report.gd -- <CSV のパス>   別の記録(書き出した版の記録など)を集計する
##
## 見方:
##   - 条件ごとの「被弾 /分」(遊んだ 1 分あたりの被弾秒数)。slow・base・fast は同じ Lv に合わせてあるので、計算が正しければほぼ同じになる
##   - fast / slow が 1 より大きい → 速い弾は、計算より難しい(SPEED_EXP を上げる)。1 より小さい → 計算より易しい(下げる)
##   - dense / base は物差し(難易度が 25% 上がったときの被弾の増え方)。これで fast / slow の差を SPEED_EXP の値に直す

const SpeedStudy = preload("res://scripts/speed_study.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")

const NAMES := {"slow": "slow  (弾速 ×0.8・同じ Lv)", "base": "base  (ふだんどおり)", "fast": "fast  (弾速 ×1.25・同じ Lv)", "dense": "dense (難易度 ×1.25)"}


func _init() -> void:
	var path := SpeedStudy.path
	for a in OS.get_cmdline_user_args():
		path = str(a)
	var rows := SpeedStudy.read_rows(path)
	print("記録: %s(%d プレイ)" % [ProjectSettings.globalize_path(path) if path.begins_with("user://") else path, rows.size()])
	if rows.is_empty():
		print("まだ記録がありません。設定の「その他」で「弾速の実験に参加する」を入れて、ひとりで遊んでください。")
		quit()
		return
	var s := SpeedStudy.summarize(rows)
	print("")
	print("%-30s %5s %8s %10s %8s %8s" % ["条件", "回数", "遊んだ分", "被弾 /分", "失敗率", "到達度"])
	for c in SpeedStudy.ORDER:
		var d: Dictionary = s.conditions[c]
		print("%-30s %5d %8.1f %9.3fs %7.0f%% %7.0f%%" % [NAMES[c], d.n, d.minutes, d.rate, d.fail_rate * 100.0, d.progress * 100.0])
	print("")
	print("比(両方の条件を遊んだ譜面だけで比べる):")
	for key in ["slow", "fast", "dense"]:
		var r: Dictionary = s.ratios[key]
		print("  %-6s / base = %s  (譜面 %d)" % [key, "-" if r.ratio == null else "%.2f" % r.ratio, r.maps])
	var fs: Dictionary = s.ratios["fast/slow"]
	print("  fast / slow = %s  (譜面 %d)" % ["-" if fs.ratio == null else "%.2f" % fs.ratio, fs.maps])
	print("")
	print("今の SPEED_EXP = %.2f" % PatternGen.SPEED_EXP)
	if s.estimate != null:
		print("推定した SPEED_EXP = %.2f  (物差し β = %.2f。4 条件をすべて遊んだ譜面 %d)" % [s.estimate, s.beta, s.maps_all])
		print("  ※ 譜面の数・被弾が少ないうちは、大きくぶれます。プレイを重ねて、値が落ち着くかを見てください")
	else:
		print("推定: " + s.note)
	quit()
