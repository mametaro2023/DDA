extends SceneTree
## プレイ記録(records.gd)の確認: 残す条件・スコア順・上位 KEEP 件・新記録の判定・保存と読み込み。
## godot --headless --path . --script tests/test_records.gd

const Records = preload("res://scripts/records.gd")
const Replay = preload("res://scripts/replay.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _stats(score: float, hits: int, failed := false, extra := {}) -> Dictionary:
	var d := {"failed": failed, "score": score, "score_base": 1000000.0, "hits": hits, "graze": 100, "damage": 0.1, "mod_ids": ["rush"], "level": 5.0, "md5": "abc"}
	d.merge(extra, true)
	return d


func _init() -> void:
	Records.path = "user://test_records.json"
	if FileAccess.file_exists(Records.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Records.path))
	Records.reload()

	_check(Records.entry_from_stats(_stats(900000.0, 1, true)).is_empty(), "ゲームオーバーは残さない")
	_check(Records.entry_from_stats(_stats(900000.0, 1, false, {"mp": {}})).is_empty(), "マルチプレイは残さない")
	_check(Records.entry_from_stats(_stats(900000.0, 1, false, {"md5": ""})).is_empty(), "識別子のない結果は残さない")
	var e := Records.entry_from_stats(_stats(950000.0, 2))
	_check(int(e.score) == 950000 and e.rank == "S" and e.mods == ["rush"], "クリアは、スコア・ランク(95% で S)・MOD を残す")
	_check(Records.entry_from_stats(_stats(1013000.0, 0)).rank == "SS", "ノーミスは SS")

	_check(Records.record_stats(_stats(800000.0, 3)), "初めての記録は、新記録")
	_check(not Records.record_stats(_stats(700000.0, 3)), "低いスコアは、新記録ではない")
	_check(Records.record_stats(_stats(900000.0, 3)), "高いスコアは、新記録")
	var top := Records.top("abc", 5)
	_check(top.size() == 3 and int(top[0].score) == 900000 and int(top[2].score) == 700000, "スコアの高い順に並ぶ(3 件)")
	_check(int(Records.best("abc").score) == 900000, "最高の記録")
	_check(Records.best("none").is_empty() and Records.top("none").is_empty(), "記録のない譜面は空")

	for i in range(15):
		Records.record_stats(_stats(100000.0 + i * 1000.0, 5))
	_check(Records.top("abc", 99).size() == Records.KEEP, "上位 %d 件だけ残す" % Records.KEEP)

	_check(int(Records.best_of_song(["zzz", "abc"]).score) == 900000, "曲全体では、難易度のうち最高のもの")
	Records.add("def", Records.entry_from_stats(_stats(500000.0, 1, false, {"md5": "def"})))
	_check(int(Records.best_of_song(["abc", "def"]).score) == 900000 and Records.best_of_song(["x"]).is_empty(), "曲全体の最高・記録がなければ空")

	# リプレイとの紐付け: 記録はファイル名を持ち、記録から外れたものは、ファイルも消える(いま足したものは残す)
	Replay.dir = "user://test_records_replays"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Replay.dir))
	var touch := func(n: String):
		var f := FileAccess.open(Replay.dir.path_join(n), FileAccess.WRITE)
		f.store_string("x")
		f.close()
	for i in range(Records.KEEP):
		touch.call("r%d.rpl" % i)
		Records.add("rp", Records.entry_from_stats(_stats(500000.0 + i * 1000.0, 1, false, {"md5": "rp", "replay": "r%d.rpl" % i})))
	_check(Records.replay_names().size() >= Records.KEEP and Records.best("rp").replay == "r%d.rpl" % (Records.KEEP - 1), "記録がリプレイのファイル名を持つ")
	touch.call("high.rpl")
	Records.add("rp", Records.entry_from_stats(_stats(900000.0, 1, false, {"md5": "rp", "replay": "high.rpl"})))
	_check(not FileAccess.file_exists(Replay.dir.path_join("r0.rpl")) and FileAccess.file_exists(Replay.dir.path_join("r1.rpl")), "上位から外れた記録のリプレイは、消える")
	touch.call("low.rpl")
	Records.add("rp", Records.entry_from_stats(_stats(1000.0, 1, false, {"md5": "rp", "replay": "low.rpl"})))
	_check(FileAccess.file_exists(Replay.dir.path_join("low.rpl")) and not Records.replay_names().has("low.rpl"), "いま足したプレイは、記録に入らなくても、リプレイは残る(結果画面から見られる)")
	for n in DirAccess.get_files_at(Replay.dir):
		DirAccess.remove_absolute(Replay.dir.path_join(n))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Replay.dir))

	Records.reload()   # 保存したものを読み込み直しても同じ
	_check(Records.top("abc", 99).size() == Records.KEEP and int(Records.best("def").score) == 500000, "保存して読み込み直しても、同じ")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Records.path))
	print("test_records: ", "OK" if _fail == 0 else "%d FAIL" % _fail)
	quit(1 if _fail > 0 else 0)
