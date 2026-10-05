extends RefCounted
## リザルトの「ランクの文字を叩きつける」演出(classic も lazer も共通)。見た目の色は accent で決まり、場所は呼び出す側が決める。
##   溜め … 大きく薄い文字が一瞬浮かんで、少しだけ縮む(SS・S は、周りから光の輪が集まってくる)
##   着地 … 加速しながら縮んで着地。着地の瞬間に白く光り、横につぶれてから弾んで戻る
##   衝撃 … 衝撃波・粒・低い音・パネルがずんと沈む(ランクが高いほど大きい。SS・S は光の粒が舞い上がり、文字の後ろに淡い光が残る)
##   F    … 光らず、重く鈍く落ちる(灰色の砂ぼこりが下へ落ちる)
## 点滅・フラッシュはしない(着地の白い光は、1 回だけ元の色へなめらかに戻る)。

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const UiFx = preload("res://scripts/ui/ui_fx.gd")


## ランクの演出の強さ: 3 = SS / 2 = S / 1 = A・B / 0 = C・D / -1 = F。高いランクほど、溜め・衝撃・光の粒が大きくなる。
static func tier_of(rank: String) -> int:
	match rank:
		"SS":
			return 3
		"S":
			return 2
		"A", "B":
			return 1
		"C", "D":
			return 0
	return -1


## ランクの文字 big を叩きつける。host: 演出(輪・粒・タイマー)を載せる画面、panel: 着地でずんと沈むパネル、delay: 始まるまでの秒。
static func stamp(host: Control, big: Label, accent: Color, tier: int, panel: Control, delay: float = 0.0) -> void:
	big.pivot_offset = big.get_minimum_size() * 0.5
	if not UiStyle.animate or not host.is_inside_tree():
		big.modulate.a = 1.0
		return
	var top := tier >= 2
	big.modulate.a = 0.0
	big.scale = Vector2(2.8, 2.8)
	var t := host.create_tween()
	t.tween_interval(delay)
	# 溜め
	var hold := 0.22 if top else (0.14 if tier >= 0 else 0.08)
	t.tween_callback(func():
		if top:
			UiSfx.play("whoosh", 1.2 if tier == 3 else 1.0, 0.8)
			UiFx.ring(host, big.get_global_rect().get_center(), Color(accent.r, accent.g, accent.b, 0.55), 260.0, 70.0, hold + 0.12, 3.0)   # 周りから集まる輪
	)
	t.tween_property(big, "modulate:a", 0.32, hold * 0.6)
	t.parallel().tween_property(big, "scale", Vector2(2.5, 2.5), hold).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 着地
	var fall := 0.14 if top else (0.17 if tier >= 0 else 0.24)
	t.tween_property(big, "scale", Vector2.ONE, fall).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(big, "modulate:a", 1.0, fall)
	t.tween_callback(func(): impact(host, big, big.get_global_rect().get_center(), accent, tier, panel))   # 位置は着地の時点で(パネルが滑り込む途中でもずれない)


## 着地の瞬間の演出(ランクの強さ tier ごと)。
static func impact(host: Control, big: Label, at: Vector2, accent: Color, tier: int, panel: Control) -> void:
	var a := accent
	# 文字: 横につぶれてから、弾んで戻る。F 以外は、白く光ってから元の色へ
	var squash: Vector2 = [Vector2(1.06, 0.94), Vector2(1.1, 0.9), Vector2(1.14, 0.88), Vector2(1.18, 0.86), Vector2(1.2, 0.84)][tier + 1]
	big.scale = squash
	var ts := big.create_tween()
	ts.tween_property(big, "scale", Vector2.ONE, 0.5 if tier >= 0 else 0.3).set_trans(Tween.TRANS_ELASTIC if tier >= 2 else Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if tier >= 0:
		big.modulate = Color(2.4, 2.4, 2.4, 1.0)
		var tf := big.create_tween()
		tf.tween_property(big, "modulate", Color(1, 1, 1, 1), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 衝撃波と粒
	match tier:
		3, 2:
			var gold := Color(1.0, 0.9, 0.55) if tier == 2 else Color(0.85, 1.0, 1.0)
			UiFx.ring(host, at, a, 40.0, 380.0, 0.8, 5.0)
			UiFx.ring(host, at, Color(1, 1, 1, 0.65), 20.0, 240.0, 0.55, 2.5)
			UiFx.burst(host, at, a, 34 if tier == 3 else 28, 640.0, 1.0, 5.0, 160.0, 1.9)
			UiFx.burst(host, at, gold, 22 if tier == 3 else 14, 150.0, 1.8, 2.4, -70.0, 0.9)   # ゆっくり舞い上がる光の粒
			if tier == 3:
				var second := host.create_tween()   # host に結び付いた待ち(host が消えたら、一緒に消える)
				second.tween_interval(0.12)
				second.tween_callback(func(): UiFx.ring(host, at, gold, 30.0, 300.0, 0.9, 3.0))   # 2 つ目の衝撃波
			UiSfx.play("stamp", 1.0)
			UiSfx.play("confirm", 1.5 if tier == 3 else 1.3, 0.7)   # 明るい響き
			glow_behind(big, a, 0.55 if tier == 3 else 0.4)
		1:
			UiFx.ring(host, at, a, 40.0, 330.0, 0.7, 4.0)
			UiFx.ring(host, at, Color(1, 1, 1, 0.5), 20.0, 200.0, 0.5, 2.0)
			UiFx.burst(host, at, a, 24, 540.0, 0.9, 4.4, 160.0, 1.9)
			UiSfx.play("stamp")
		0:
			UiFx.ring(host, at, a, 36.0, 240.0, 0.6, 3.0)
			UiFx.burst(host, at, a, 12, 380.0, 0.75, 3.6, 220.0, 2.2)
			UiSfx.play("stamp", 0.88)
		_:
			UiFx.ring(host, at, Color(a.r, a.g, a.b, 0.6), 36.0, 180.0, 0.5, 3.0)
			UiFx.burst(host, at + Vector2(0, 40), Color(0.6, 0.6, 0.65, 0.8), 14, 220.0, 0.9, 3.0, 520.0, 2.6)   # 灰色の砂ぼこりが落ちる
			UiSfx.play("stamp", 0.7)
	# パネルが、ずんと沈んで戻る(ランクが高いほど深い)
	var dip: float = [0.99, 0.988, 0.985, 0.978, 0.97][tier + 1]
	panel.pivot_offset = panel.size * 0.5
	var th := panel.create_tween()
	th.tween_property(panel, "scale", Vector2(dip, dip), 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	th.tween_property(panel, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 文字の後ろに、淡い光を残す(SS・S)。ふわっと現れて、そのまま残る(点滅しない)。
static func glow_behind(big: Label, col: Color, strength: float) -> void:
	var g := Control.new()
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.show_behind_parent = true
	g.size = big.size
	g.draw.connect(func():
		var c := g.size * 0.5
		for k in range(7):
			g.draw_circle(c, 18.0 + 13.0 * k, Color(col.r, col.g, col.b, strength * 0.07)))
	big.add_child(g)
	g.modulate.a = 0.0
	UiStyle.tween(g, "modulate:a", 0.0, 1.0, 0.6)
