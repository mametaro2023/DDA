extends SceneTree
## 推定星評価(基準用)を公式値(サンプル譜面セット 320118)と比較する。
## godot --headless --path . --script tests/test_star.gd

const OszLoader = preload("res://scripts/osu/osz_loader.gd")

const OFFICIAL := {
	"Irre's Beginner": 1.42, "Celsius' Easy": 2.11, "Misuzu's Normal": 2.48,
	"byfaR's Hard": 3.67, "Light Insane": 4.38, "toybot's Insane": 4.72,
	"Insane": 5.25, "Celsius' Extra": 5.53, "deetz' Expert": 5.64,
	"Nathan's Extra": 5.71, "Lust's Insane": 5.72, "Leader's Light Extra": 5.88,
	"Fast's Expert": 5.94, "jieusieu's Lemur": 6.64,
}


func _init() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var sum_err := 0.0
	var max_err := 0.0
	for bm in loader.difficulties:
		var off: float = OFFICIAL.get(bm.version, -1.0)
		var err: float = bm.stars - off
		sum_err += absf(err)
		max_err = maxf(max_err, absf(err))
		print("%-24s official=%.2f est=%.2f diff=%+.2f" % [bm.version, off, bm.stars, err])
	print("mean|err|=%.3f max|err|=%.3f" % [sum_err / loader.difficulties.size(), max_err])
	quit()
