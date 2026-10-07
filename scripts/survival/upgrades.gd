extends RefCounted
## サバイバルの強化(曲の間の 3 択)。docs/survival_plan.md の §5。
## 1 つの強化は辞書: id・名前・1 行の要点(short)・詳しい説明(desc)・種類(group: def = 守り / bet = 賭け / atk = 攻撃(S2))・
## 上限の段(max。0 = 上限なし)・重み(w)・絵(icon。LazerIcons の名前)・色。効果の量は SurvivalRun が段の数から決める。
## 強化を足すときは ALL に 1 件足し、効果を SurvivalRun.game_params / song_done に書く。

## 1 段の効果は小さく、レベルは頻繁に上がる(段を重ねて育てる)。
const ALL := [
	{
		"id": "max_gauge", "name": "最大ゲージ", "group": "def", "max": 10, "w": 10, "icon": "plus", "color": Color(0.4, 0.95, 0.8),
		"short": "体力の上限 +3%", "desc": "体力の上限が、初期の体力の 3% ぶん増える(体力バーも伸びる)。いまの体力と、回復の量は増えない",
	},
	{
		"id": "regen", "name": "自然回復", "group": "def", "max": 10, "w": 10, "icon": "repeat", "color": Color(0.55, 0.9, 0.45),
		"short": "自然回復 +0.025%/秒", "desc": "被弾していないときの回復が、もとの 10% ずつ速くなる(毎秒 0.25 → 0.275 → 0.3 …%)",
	},
	{
		"id": "between_heal", "name": "曲の間の回復", "group": "def", "max": 10, "w": 10, "icon": "note", "color": Color(0.45, 0.8, 1.0),
		"short": "曲の間の回復 +2%", "desc": "曲が終わったときの回復が 2% 増える(もとは 10%。初期の体力に対する量)",
	},
	{
		"id": "guard", "name": "身代わり", "group": "def", "max": 1, "w": 3, "icon": "star", "color": Color(1.0, 0.85, 0.35), "rare": true,
		"short": "1 回だけ踏みとどまる", "desc": "ゲージが 0 になるとき 1 回だけ、いまの体力の上限の 20% で踏みとどまり、盤面の弾を消す(使うと、また選べるようになる)",
	},
	{
		"id": "small", "name": "小型化", "group": "def", "max": 5, "w": 8, "icon": "mod_shrink", "color": Color(0.6, 0.85, 1.0),
		"short": "当たり判定 −2%", "desc": "自機と当たり判定が、もとの大きさの 2% ずつ小さくなる",
	},
	{
		"id": "graze_heal", "name": "かすり回復", "group": "def", "max": 5, "w": 8, "icon": "mod_heaven", "color": Color(0.7, 1.0, 0.85),
		"short": "グレイズで +0.03% 回復", "desc": "弾をかすめる(グレイズ)たびに、体力が 0.03% ずつ多く回復する(初期の体力に対する量)。弾に近づくほど得をする",
	},
	{
		"id": "bet", "name": "背水", "group": "bet", "max": 0, "w": 6, "icon": "alert", "color": Color(1.0, 0.42, 0.45),
		"short": "次の曲の Lv +0.5・経験値 2 倍", "desc": "次の曲だけ、目標の Lv が 0.5 上がり、取った経験値が 2 倍になる(難しい曲ほど、点の倍率も上がる)",
	},
	{
		"id": "glass", "name": "ガラスの体", "group": "bet", "max": 1, "w": 4, "icon": "mod_hell", "color": Color(0.75, 0.95, 1.0),
		"short": "体力の上限 −20%・点 ×1.15", "desc": "これからずっと、体力の上限が初期の体力の 20% ぶん減るかわりに、曲の点の倍率が 1.15 倍になる",
	},
	{
		"id": "power", "name": "攻撃力", "group": "atk", "max": 15, "w": 10, "icon": "up", "color": Color(1.0, 0.5, 0.45),
		"short": "弾の攻撃力 +6%", "desc": "自機の弾 1 発の攻撃力が、もとの 6% ずつ上がる(雑魚を早く倒せる)",
	},
	{
		"id": "rate", "name": "連射", "group": "atk", "max": 10, "w": 10, "icon": "clock", "color": Color(0.5, 0.75, 1.0),
		"short": "連射の速さ +8%", "desc": "自機の弾を撃つ速さが、もとの 8% ずつ上がる(もとは毎秒 7.5 発)",
	},
	{
		"id": "wide", "name": "ワイド", "group": "atk", "max": 5, "w": 8, "icon": "list", "color": Color(0.55, 1.0, 0.6),
		"short": "弾の列 +1", "desc": "自機の弾の列が 1 つ増える(もとは 1 列。最大 6 列)。雑魚の真下にいなくても当たりやすくなる",
	},
	{
		"id": "magnet", "name": "吸い寄せ", "group": "atk", "max": 8, "w": 7, "icon": "download", "color": Color(0.95, 0.8, 1.0),
		"short": "吸い寄せる範囲 +15%", "desc": "落ちた経験値の玉が、自機に寄ってくる範囲が、もとの 15% ずつ広がる",
	},
	{
		"id": "homing", "name": "追尾弾", "group": "atk", "max": 3, "w": 6, "icon": "retry", "color": Color(1.0, 0.7, 0.4),
		"short": "弾が雑魚へ少し曲がる", "desc": "自機の弾が、前にいる近くの雑魚へ向かって、少しだけ曲がる(段を上げると、よく曲がる)",
	},
	{
		"id": "pierce", "name": "貫通", "group": "atk", "max": 9, "w": 7, "icon": "play", "color": Color(0.85, 0.75, 1.0),
		"short": "弾が雑魚を通り抜ける", "desc": "弾が雑魚を通り抜けて、後ろの雑魚にも当たる。通り抜けるとダメージが減る(1 段目は 35% 残る。1 段ごとに +7%)。3 段ごとに、通り抜ける数 +1",
	},
	{
		"id": "chain", "name": "誘爆", "group": "atk", "max": 8, "w": 6, "icon": "mod_storm", "color": Color(1.0, 0.6, 0.3),
		"short": "倒した雑魚が爆発する", "desc": "倒した雑魚が爆発して、まわりの雑魚にダメージを与える(爆発で倒れた雑魚も爆発する)。段を上げると、広く(半径 42px から +6px ずつ)強くなる",
	},
]


## id から定義を引く(なければ空の辞書)。
static func find(id: String) -> Dictionary:
	for u in ALL:
		if u.id == id:
			return u
	return {}


## いま選べる強化か。levels: id → いまの段。excluded: 選べない id(MOD「無回復」のときの自然回復など)。
static func available(u: Dictionary, levels: Dictionary, excluded: Array = []) -> bool:
	if excluded.has(u.id):
		return false
	var mx := int(u.max)
	return mx <= 0 or int(levels.get(u.id, 0)) < mx


## 3 択(n 個)を、重みつきの乱数で選ぶ。同じものは 2 つ出さない。上限に届いたものは出さない。選べるものが n 個より少なければ、あるだけ。
## rare_boost: レアなもの(rare)の重みの倍率(ボスを倒したあと。S3)。戻り値: id の配列。
static func roll(rng: RandomNumberGenerator, levels: Dictionary, n := 3, excluded: Array = [], rare_boost := 1.0) -> Array:
	var pool: Array = []
	for u in ALL:
		if available(u, levels, excluded):
			pool.append(u)
	var out: Array = []
	while out.size() < n and not pool.is_empty():
		var total := 0.0
		for u in pool:
			total += _weight(u, rare_boost)
		var r := rng.randf() * total
		var pick: Dictionary = pool.back()
		for u in pool:
			r -= _weight(u, rare_boost)
			if r <= 0.0:
				pick = u
				break
		out.append(pick.id)
		pool.erase(pick)
	return out


static func _weight(u: Dictionary, rare_boost: float) -> float:
	return float(u.w) * (rare_boost if bool(u.get("rare", false)) else 1.0)
