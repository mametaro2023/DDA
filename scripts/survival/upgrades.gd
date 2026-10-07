extends RefCounted
## サバイバルの強化(曲の間の 3 択)。docs/survival_plan.md の §5。
## 1 つの強化は辞書: id・名前・1 行の要点(short)・詳しい説明(desc)・種類(group: def = 守り / bet = 賭け / atk = 攻撃(S2))・
## 上限の段(max。0 = 上限なし)・重み(w)・絵(icon。LazerIcons の名前)・色。効果の量は SurvivalRun が段の数から決める。
## 強化を足すときは ALL に 1 件足し、効果を SurvivalRun.game_params / song_done に書く。

const ALL := [
	{
		"id": "max_gauge", "name": "最大ゲージ", "group": "def", "max": 3, "w": 10, "icon": "plus", "color": Color(0.4, 0.95, 0.8),
		"short": "体力の上限 +15%", "desc": "体力の上限が、初期の体力の 15% ぶん増える(体力バーも伸びる)。いまの体力と、回復の量は増えない",
	},
	{
		"id": "regen", "name": "自然回復", "group": "def", "max": 3, "w": 10, "icon": "repeat", "color": Color(0.55, 0.9, 0.45),
		"short": "自然回復 +0.25%/秒", "desc": "被弾していないときの回復が、毎秒 0.25% 速くなる(もとは毎秒 1%。初期の体力に対する量)",
	},
	{
		"id": "between_heal", "name": "曲の間の回復", "group": "def", "max": 3, "w": 10, "icon": "note", "color": Color(0.45, 0.8, 1.0),
		"short": "曲の間の回復 +5%", "desc": "曲が終わったときの回復が 5% 増える(もとは 25%。初期の体力に対する量)",
	},
	{
		"id": "guard", "name": "身代わり", "group": "def", "max": 1, "w": 3, "icon": "star", "color": Color(1.0, 0.85, 0.35), "rare": true,
		"short": "1 回だけ踏みとどまる", "desc": "ゲージが 0 になるとき 1 回だけ、いまの体力の上限の 40% で踏みとどまり、盤面の弾を消す(使うと、また選べるようになる)",
	},
	{
		"id": "bet", "name": "背水", "group": "bet", "max": 0, "w": 6, "icon": "alert", "color": Color(1.0, 0.42, 0.45),
		"short": "次の曲の Lv +0.5", "desc": "次の曲だけ、目標の Lv が 0.5 上がる(難しい曲ほど、点の倍率も上がる)",
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
