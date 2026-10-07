extends RefCounted
## ゲーム進行(自機・イベント発射・被弾・ゲージ・スコア)。描画/音声に依存しないのでヘッドレスでも回せる。
##
## ## ゲージ制
## 弾に当たっている間は継続ダメージ。ゲージ満タンは GAUGE_DRAIN_TIME(250ms)ぶんの被弾に相当する。
## ゲージが GAUGE_LOW_THRESHOLD(20%。MOD「天国」は 35%)以下のときは被ダメージが半分になる(連続被弾で 0 になるまで合計約 300ms。MOD「地獄」では半減しない)。
## ゲージが 0 になったらゲームオーバー(練習モードでは 0 でも続行)。
## 当たっていないときは、ごくわずかに回復する(GAUGE_REGEN /秒。MOD「無回復」では回復しない)。
##
## ## 危険エリア(デバフ)
## 盤面を 3×3 の 9 マスに分け、特定の小節ごとに、いくつかのマス(1〜8)が「危険エリア」になる(PatternGen が譜面から決めて、gen.zones で渡す。
## 数・種類は難易度などに応じて変わる)。入っている間、そのマスのデバフを受ける:
##   鈍足(slow): 移動が ZONE_SLOW 倍 / 脆弱(fragile): 被ダメージが ZONE_FRAGILE 倍 / 毒(poison): ゲージが ZONE_POISON_DRAIN(/秒)で減る / 巨大(big): 自機の当たり判定が ZONE_BIG 倍
## 弾幕には手を入れない(自機が受けるものだけ)。休憩地帯では効かない。練習モードでは、毒のゲージ減少だけ効かない。
##
## ## 特殊エリア(MOD「弾幕 v2」)
## gen.zones の各要素が areas(形 + 種類のリスト。形は zone_area.gd)を持つとき(= 弾幕 v2)は、3×3 のマスではなく、その形が特殊エリアになる。種類は 3 系統:
##   試練(自機が不利): 鈍足・脆弱・毒(+ v1 の巨大)。中でグレイズすると、ボーナス用のグレイズが ZONE_GRAZE_TRIAL 倍ぶん、上乗せされる(リスクの見返り)
##   恩恵(自機が有利): 癒し(heal: 自然回復に上乗せして、ゲージが ZONE_HEAL_RATE(/秒)で回復)/ 精密(precise: 当たり判定 ZONE_PRECISE_HIT 倍・移動 ZONE_PRECISE_SPEED 倍)/ 稼ぎ(bonus: グレイズの上乗せ ZONE_GRAZE_BONUS 倍 + グレイズごとに、失った被ダメージ係数を ZONE_GRAZE_REFUND の割合ずつ取り戻す)
##   変質(弾に作用): 時の淀み(warp: エリアの中の弾が ZONE_WARP 倍の速さで進む)/ 時の急流(haste: ZONE_HASTE 倍。試練)。弾の位置だけで決まるので、協力でも全員が同じ弾を見る。
##     弾の速さの倍率は、目標へなめらかに近づく(入るときは速く、出たあとはゆっくり戻る。BulletField.WARP_ENTER / WARP_EXIT)ので、エリアが消えても弾が急に元の速さへ戻らない。
##   流れ(flow: 試練): 自機が、エリアごとの向き(area.dir)へ、入力に関係なく ZONE_FLOW_SPEED で押される。
##
## ## 小型化・撃破(MOD)
## 小型化: 自機が動ける範囲(move_rect)が、盤面の中央の縦横 field_scale 倍になる。発射位置は変わらない。危険エリアの 3×3 のマスも、この範囲を分ける。
## 撃破: ボス(scripts/game/boss.gd)を倒すまで、譜面を loop_len 秒ごとに繰り返す(周回ごとに、時刻をずらした弾幕を足していく)。
##   1 周 = 繰り返しの始まり loop_from(最初のノーツの LOOP_LEAD 秒前)〜 最後のノーツ loop_end + ボーナスタイム(Boss.BONUS_TIME 秒)。
##   1 周目だけは、時刻 0(曲の頭)から始まる。ボーナスタイムの間は弾が来ず、ボスは止まる(曲は game_screen が、その間に次の周の頭へ早送りする)。
##   ボスに当てるとゲージが回復する(1 発 HIT_HEAL。速さは毎秒 HIT_HEAL_MAX まで。強化で当たる数が増えても強くなりすぎないように)。
## ボスを倒したら弾を消し、BOSS_CLEAR_DELAY 秒の演出のあとクリア。ゲージが 0 ならゲームオーバー(今までどおり)。危険エリアは出さない。
## スコア(撃破だけ、曲の繰り返しに合わせて変える。ベーススコア・グレイズ・被ダメージ係数・ランクの仕組みは同じ):
##   進行率 = ボスに与えたダメージの割合(1 − 残り HP ÷ 最大 HP)。削るほど伸び、倒した時点で最終点(1 周で止まらない)
##   被ダメージ係数の時定数 = 想定の戦いの長さ(Boss.HP_CHASE_SECONDS)で決める(1 周の長さではなく。長い戦いで、普通の曲より下がりすぎない)
##   撃破タイムボーナス = SCORE_BOSS_TIME × exp(−倒すまでの秒 ÷ BOSS_TIME_TAU)(最大 3 万点。想定の 240 秒で約 1 万点。倒したときに入る)
##     グレイズのボーナスと同じく、MOD の倍率はかからず、被ダメージ係数はかかる

const BulletField = preload("res://scripts/game/bullet_field.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const Boss = preload("res://scripts/game/boss.gd")
const ZoneArea = preload("res://scripts/game/zone_area.gd")

const ARENA := PatternGen.ARENA
const PLAYER_SPEED := 380.0      # キーボード
const PLAYER_SLOW := 160.0
## ダメージの基準速度(px/s)。弾に触れているとき、触れていた「時間」と、弾の中を「通った距離 ÷ この速度」のうち長いほうを、ダメージの時間として使う。
## 速く動いて弾を抜けても、キーボードで同じ距離を抜けるのと同じダメージになる(マウスの素早い動きで、被弾を実質的に減らせない)。これ以下の速さでは、触れていた時間のまま。
const CONTACT_SPEED_REF := PLAYER_SPEED
const MOUSE_SLOW_FACTOR := 0.3   # マウスの低速時に移動量へ掛ける倍率
const PLAYER_HIT_R := 3.5
const PLAYER_MARGIN := 8.0
const SAFE_RADIUS := 100.0       # 発射点にこの距離以内に自機がいたら弾は一時無害
const SAFE_GRACE_PX := 140.0
## 猶予は「不意打ち」を防ぐためのもの。同じ場所(スピナーの中央・重なったノーツ・スライダーの発射点など)で待ち続けて、近くから撃たれ続ける間は、
## 猶予は最初の GRACE_STREAK_MAX 秒ぶんの発射にだけつける(それより後に近くで撃たれた弾は、ふつうに当たる)。近くでの発射が GRACE_STREAK_GAP 秒より空いたら、数え直す。
## (猶予がずっと続くと、スピナーの間は中央に居座るだけで、すべて避けられてしまう)
const GRACE_STREAK_MAX := 0.6
const GRACE_STREAK_GAP := 0.5

const GAUGE_DRAIN_TIME := 0.25   # ゲージ満タンぶんの被弾時間(通常時の被ダメージ速度)
const GAUGE_LOW_THRESHOLD := 0.2 # ゲージがこれ以下のとき、
const GAUGE_LOW_FACTOR := 0.5    # 被ダメージはこの倍率になる
const GAUGE_REGEN := 0.015       # 被弾していないときの回復(ゲージ全体に対する割合 / 秒)
## 実際の弾・自機の大きさの倍率(見た目と当たり判定)。値は PatternGen が持つ(Lv の計算の危険半径と、同じ値を使うため)。
const BULLET_SIZE_MUL := PatternGen.BULLET_SIZE_MUL
const PLAYER_SIZE_MUL := PatternGen.PLAYER_SIZE_MUL
const CLEAR_TIMEOUT := 8.0       # 最後の弾を撃ってからこの秒数たっても弾が残っていたら、消してクリアにする
## 自機の周りが「落ち着いている」とみなす範囲(休憩の一掃・クリア判定): 近くの弾は SAFE_NEAR_R 以内、接近中の弾は SAFE_LOOK_T 秒以内に自機から SAFE_APPROACH_R 以内を通る弾
const SAFE_NEAR_R := 120.0
const SAFE_APPROACH_R := 50.0
const SAFE_LOOK_T := 3.0
const EPISODE_GAP := 0.15       # これ以上被弾が途切れたら、次の被弾は「別の被弾」として数える
const ZONE_SLOW := 0.45            # 鈍足: 移動の倍率
const ZONE_FRAGILE := 2.0          # 脆弱: 被ダメージの倍率
const ZONE_BIG := 1.8              # 巨大: 自機の当たり判定の倍率(見た目の当たり判定の点も大きくなる)
const ZONE_POISON_DRAIN := 0.10    # 毒: ゲージの減る速さ(ゲージ全体に対する割合 / 秒)
const ZONE_HEAL_RATE := 0.01       # 癒し: 自然回復に上乗せする、ゲージの増える速さ(ゲージ全体に対する割合 / 秒。協力では 1 人ぶんのゲージに対して)。強すぎたので 5% から 1% にした
const ZONE_PRECISE_HIT := 0.6      # 精密: 自機の当たり判定の倍率
const ZONE_PRECISE_SPEED := 0.75   # 精密: 移動の倍率
const ZONE_WARP := 0.55            # 時の淀み: エリアの中の弾の速さの倍率
const ZONE_HASTE := 1.5            # 時の急流: エリアの中の弾の速さの倍率
const ZONE_FLOW_SPEED := 110.0     # 流れ: 自機を押す速さ(px/s。自機の移動 380 の約 3 割)
const ZONE_GRAZE_TRIAL := 0.5      # 試練エリアの中のグレイズに、上乗せする割合(1 回のグレイズが 1.5 回ぶん)
const ZONE_GRAZE_BONUS := 1.0      # 稼ぎ(恩恵)エリアの中のグレイズに、上乗せする割合(1 回が 2 回ぶん)
const ZONE_GRAZE_REFUND := 0.001   # 稼ぎエリアの中のグレイズ 1 回ごとに、失っている被ダメージ係数(1 − damage_factor)を、この割合だけ取り戻す(失うほど、戻る量も大きい)

const SCORE_BASE := 1000000.0
## ランク(クリアしたときだけ)。被弾 0 回なら SS。それ以外は「達成率 = 最終点 ÷ ベーススコア(MOD の倍率を含む)」で決める。
## MOD の倍率を打ち消した率なので、練習(×0.5)や +6% の MOD でランクが上下しない。達成率 = 被ダメージ係数 + グレイズのボーナス分。
const RANK_TABLE := [["S", 0.95], ["A", 0.85], ["B", 0.70], ["C", 0.55], ["D", 0.40]]   # これ未満は F
## 発射地点の印(暗闇 MOD 用)を残す秒数
const FIRE_MARK_TIME := 0.9
## 被ダメージ係数の減衰の時定数(累計ダメージ = この値で係数が 1/e ≒ 0.37 になる。ゲージ満タン = 1)
const DAMAGE_TAU := 3.0
## damage_tau を伸ばし始める、弾が飛んでいる時間の基準(秒)。これ以下の譜面の τ は DAMAGE_TAU のまま
const DAMAGE_REF_TIME := 120.0
const SCORE_GRAZE := 30000.0     # グレイズのボーナスの最大(3%)
## 撃破: 倒すまでの時間のボーナスの最大(3%)と、その減り方の時定数(秒。想定の戦いの長さで 1/3 = 約 1 万点になる)
const SCORE_BOSS_TIME := 30000.0
const BOSS_TIME_TAU := 240.0 / 1.0986123   # 240 ÷ ln 3
## グレイズのボーナスの立ち上がりの目安 graze_tau = 発射イベント数 × この係数(下限 GRAZE_TAU_MIN)。
## グレイズ数が graze_tau で最大の約 63%、2 倍で約 86%、3 倍で約 95%(3 万点には漸近するだけで届かない)
const GRAZE_TAU_PER_EVENT := 0.15
const GRAZE_TAU_MIN := 10.0

## 結果画面の体力グラフ用の記録: 曲の時刻 0 から GAUGE_LOG_STEP 秒ごとのゲージ(0..1)。i 番目は i × GAUGE_LOG_STEP 秒のとき
const GAUGE_LOG_STEP := 0.25
## 撃破: ボスを倒してから、クリアにするまでの秒(撃破の演出を見せる)
const BOSS_CLEAR_DELAY := 2.4
## 撃破: 次の周は、最初のノーツのこの秒数前から始まる(予兆と、ボスの移動が間に合うように)
const LOOP_LEAD := 1.0
## 撃破: ボスに当てたときの回復(1 発あたり)と、その回復の速さの上限(/秒。どちらもゲージ全体に対する割合)
const HIT_HEAL := 0.001
const HIT_HEAL_MAX := 0.03

## 判定の計算(_update)を行った回数の通算(FPS 表示の「判定 /s」用)
static var steps_total := 0

var field: Node2D
var events: Array = []
var gizmos: Array = []
var breaks: Array = []          # [[開始秒, 終了秒], ...] 休憩地帯
var warn_lead := 0.6
var practice := false
var zones: Array = []              # 危険エリアの予定(gen.zones。時刻順)
var zone_debuff := ""              # いま自機が受けているエリアの種類("" = なし。名前はデバフのままだが、恩恵の種類も入る)
var zone_area_type := ""           # いま自機がいるエリアの種類(時の淀み・急流のような、自機には効かないものも入る)。グレイズの上乗せの判定に使う
var zone_push := Vector2.ZERO      # 流れのエリアの中で、自機が押されている速度(px/s)
var hit_mult := 1.0                # 巨大・精密のエリア中の、当たり判定の倍率(描画の点の大きさにも使う)
var contact_extra := 0.0           # 参加者: まだホストへ送っていない、デバフによる追加ダメージ(被弾時間に換算した秒)
var contact_heal := 0.0            # 参加者: まだホストへ送っていない、癒しによる回復(被弾時間に換算した秒)
var contact_gbonus := 0.0          # 参加者: まだホストへ送っていない、エリアでのグレイズの上乗せ
var contact_grefund := 0           # 参加者: まだホストへ送っていない、稼ぎエリアの中のグレイズの数(被ダメージ係数の回復に使う)
var graze_bonus := 0.0             # エリアでのグレイズの上乗せ(ボーナス点にだけ入る。表示するグレイズ数には入れない)
var damage_refund := 0.0           # 稼ぎエリアのグレイズで取り戻した分(damage_total と同じ単位。被ダメージ係数にだけ効き、damage_total・DAMAGE 表示は変えない)
var _zone_i := 0
var _warp_t := -1.0                # 時の淀み・急流の形を最後に作った時刻と、そのときのエリアの番号(作り直しは WARP_REFRESH ごと)
var _warp_zi := -1
const WARP_REFRESH := 0.008
var last_fire_time := -1.0        # 最後のノーツ(発射)の時刻。結果画面の体力グラフの右端
## 発射地点の印を記録するか(暗闇 MOD。弾が見えなくても、どこから撃ったかを表示するため)
var track_fires := false
var recent_fires: Array = []     # {pos, t, color}: 発射から FIRE_MARK_TIME 秒だけ残る
## 開発用: true なら被弾しない(テスト用。スコア表示の検証などで、ダメージの影響を除きたいときに使う)
var debug_invincible := false
var end_time := 0.0
## MOD で変わる設定(既定は MOD なし)
var drain_time := GAUGE_DRAIN_TIME    # ゲージ満タンぶんの被弾時間(秒)
var low_protect := true               # ゲージが low_threshold 以下で被ダメージが半分になるか
var low_threshold := GAUGE_LOW_THRESHOLD   # その境目(MOD「天国」で 35%)
var regen := true                     # 被弾していないときの自然回復(MOD「無回復」で false)
var regen_rate := GAUGE_REGEN         # その回復の速さ(初期の体力に対する割合 / 秒。サバイバルは 1% + 強化)
## 初期の体力 ÷ いまの体力(サバイバルの「最大ゲージ」の強化で 1 より小さくなる)。回復(自然回復・癒し)と、被ダメージ半減の境目は、初期の体力に対する量で決めるので、
## ゲージ(いまの体力に対する割合)へは、これを掛けて換算する(体力を増やしても、回復の絶対量は増えない)。ふつうのプレイは 1
var gauge_unit := 1.0
var regen_wait_first := false         # true なら、最初の弾幕が飛ぶまで自然回復しない(サバイバル: 曲の間の回復のあと、イントロで回復しないように)
var guard := 0                        # サバイバルの「身代わり」の残り: ゲージが 0 になるとき、guard_gauge で踏みとどまり、盤面の弾を消す
var guard_gauge := 0.4
var guard_t := -1.0                   # 最後に身代わりを使った時刻(-1 = 使っていない。画面が演出に使う)
var fail_score := 0.0                 # ゲームオーバーになる直前の表示点数(サバイバルは、倒れた曲もそこまでの点を数える)
var score_base := SCORE_BASE          # ベーススコア(MOD で増える)
var player_scale := 1.0                # 自機サイズの倍率(MOD)
var player_r := PLAYER_HIT_R          # 自機の当たり判定半径(= PLAYER_HIT_R × player_scale)
var move_rect := Rect2(Vector2.ZERO, ARENA)   # 自機が動ける範囲(小型化 MOD で中央の長方形になる)
var boss = null                       # 撃破 MOD のボス(Boss。なければ null)
var loop_len := 0.0                   # > 0 なら、譜面をこの秒ごとに繰り返す(撃破 MOD)
var loop_from := 0.0                  # 撃破: 2 周目以降の、周の始まり(1 周目の時刻で。最初のノーツの LOOP_LEAD 秒前)
var loop_end := 0.0                   # 撃破: 周の最後のノーツ(1 周目の時刻で)。ここからボーナスタイム
var _heal_pool := 0.0                 # 撃破: まだゲージに足していない、当てたぶんの回復
var _hits_seen := 0
var loops_added := 1                  # 弾幕に足してある周の数(1 = 1 周目だけ)
var _base_events: Array = []          # 1 周目の弾幕(周回で、時刻をずらして足す元)
var _base_gizmos: Array = []
var _base_breaks: Array = []
var _pick_i := 0                      # boss.pick_events をどこまで反映したか
var _boss_cleared := false            # 撃破のあと、弾を消した
## 最初に弾を撃つイベントの時刻(なければ -1)。イントロのスキップ先の基準
var first_fire_time := -1.0

var player_pos := Vector2(ARENA.x * 0.5, ARENA.y * 0.85)
var slow := false
var gauge := 1.0                # 0..1
var hit_now := false            # 今このステップで弾に当たっているか
var hit_time := 0.0             # 累計被弾時間(秒)
var damage_total := 0.0         # 累計ダメージ(ゲージ満タン = 1。回復は差し引かない)
var hits := 0                   # 被弾の回数(連続した被弾は 1 回)
var graze := 0                  # スコアに数えたグレイズ(休憩地帯のぶんは数えない)
var score := 0.0                # 今の表示点数 = score_potential × score_progress(ゲームオーバーなら 0)
var score_potential := 0.0      # 今クリアした場合の最終点(= score_gross × damage_factor)
var progress := 0.0             # 曲の進行率 0..1(時間。休憩地帯でも進む)
var score_progress := 0.0       # スコア用の進行率 0..1(= 発射した弾数 / 全弾数)
var bullets_fired := 0          # ここまでに発射した弾数(休憩地帯の発射は数えない)
var bullets_total := 0          # 曲全体で発射する弾数(同上)
var score_gross := 0.0          # 被ダメージ係数を掛ける前の点数(score_base + グレイズのボーナス)
var score_graze := 0.0          # グレイズのボーナス
var score_boss_time := 0.0      # 撃破: 倒すまでの時間のボーナス(倒したときに決まる)
var damage_factor := 1.0        # 被ダメージ係数(1 → 0 に漸近)
var damage_tau := DAMAGE_TAU   # 被ダメージ係数の時定数(曲の長さに応じて伸びる。setup で決まる)
var active_time := 0.0          # 弾が飛んでいる時間(秒)= 最初〜最後の発射の間から休憩地帯を除いたもの
var finished := false
var failed := false
## 休憩中に弾を一掃した時刻と、その休憩の終わりの時刻(一掃していないとき break_clear_t = -1)
var break_clear_t := -1.0
var break_end_t := 0.0
var death_pos := Vector2.ZERO
var death_time := 0.0
var gauge_log := PackedFloat32Array()   # ゲージの推移(GAUGE_LOG_STEP 秒ごと)
var hit_log := PackedFloat32Array()     # 自分が新しく被弾した時刻(秒)
var log_end_t := 0.0                    # 最後に記録した時刻(秒)
var _log_i := 0                         # 次に記録するサンプルの番号

## このステップで起きたこと(描画/音声側が読む)
var sfx_queue: Array = []
var sfx_pan: Array = []          # sfx_queue と同じ順の、音の左右の位置(-1 = 左端 〜 1 = 右端。弾の発生源の横の位置)
var just_hit := false           # 新しい被弾が始まったステップ

var active_warns: Array = []
var active_gizmos: Array = []

## --- マルチプレイ(協力モード。setup_coop で有効になる) ---
var net_mode := ""               # "" = ひとり(対戦も、各自が自分の GameSim を回すので "")/ "coop"
var authority := true            # false = 協力の参加者(ホスト以外): ゲージ・スコア・クリア・ゲームオーバーはホストが決めて、apply_net_* で受け取る
var players_n := 1
var graze_div := 1.0             # グレイズのボーナスは、全員の合計を人数で割って(平均で)数える
var aim_targets := {}            # イベント番号 → 自機狙いの目標位置の一覧(スロット順。ホストが決めて全員へ配る。全員で同じ弾になる)
var slot_positions: Array = []   # スロット順の全員の位置(協力: 自機狙いの相手の選び方・休憩/クリアの判定)。自分の位置も入る
var net_events: Array = []       # ホストが全員へ配る出来事 {k: "wipe" / "clear" / "fail", ...}
var contact_dt := 0.0            # 参加者: まだホストへ送っていない、自分の被弾時間・グレイズ・被弾回数
var contact_graze := 0
var contact_hits := 0
var own_graze := 0                # 自分ひとりぶんの成績(協力では、graze・hits・hit_time は全員の合計になるので、結果画面の個人別の表示に使う)
var own_hits := 0
var own_hit_time := 0.0
var own_damage := 0.0             # 自分ひとりぶんのダメージ量(ゲージ満タン = 1.0。回復は引かない。協力では、damage_total は全員の合計)

var _prev_pos := Vector2.ZERO  # このステップ開始時の自機位置(移動経路上の当たり判定用)
var _ext_hit_t := 0.0          # ホスト: 他の人が被弾した直後は、ゲージが回復しない(秒)
var _ev_idx := 0
var _warn_idx := 0
var _near_start := -100.0   # 近くでの発射が続いている区間の始まり(GRACE_STREAK_*)
var _near_last := -100.0    # 最後に近くで撃たれた時刻
var _giz_idx := 0
var _no_hit_time := 1.0        # 最後に被弾してからの経過秒
var _graze_tau := GRAZE_TAU_MIN
var _all_fired_t := -1.0       # 最後の弾幕を撃ち終えた時刻(まだなら -1)


func setup(bullet_field: Node2D, gen: Dictionary, end_t: float, practice_mode: bool, mods := {}) -> void:
	field = bullet_field
	field.clear()
	events = gen.events
	gizmos = gen.gizmos
	zones = gen.get("zones", [])
	breaks = gen.get("breaks", [])
	warn_lead = gen.warn_lead
	end_time = end_t
	practice = practice_mode or bool(mods.get("practice", false))
	track_fires = bool(mods.get("dark", false))
	drain_time = float(mods.get("drain_time", GAUGE_DRAIN_TIME))
	low_protect = bool(mods.get("low_protect", true))
	low_threshold = float(mods.get("low_threshold", GAUGE_LOW_THRESHOLD))
	regen = bool(mods.get("regen", true))
	score_base = SCORE_BASE * float(mods.get("score_mul", 1.0))
	player_scale = float(mods.get("player_scale", 1.0)) * PLAYER_SIZE_MUL
	player_r = PLAYER_HIT_R * player_scale
	var fs := clampf(float(mods.get("field_scale", 1.0)), 0.1, 1.0)
	move_rect = Rect2(ARENA * (1.0 - fs) * 0.5, ARENA * fs)
	player_pos = Vector2(move_rect.get_center().x, move_rect.position.y + move_rect.size.y * 0.85)
	_graze_tau = maxf(GRAZE_TAU_MIN, GRAZE_TAU_PER_EVENT * events.size())
	bullets_total = 0
	first_fire_time = -1.0
	last_fire_time = -1.0
	var last_fire := -1.0
	for e in events:
		if e.shots.is_empty():
			continue
		if first_fire_time < 0.0:
			first_fire_time = e.t
		last_fire = e.t
		last_fire_time = e.t
		if not in_break(e.t):
			for s in e.shots:
				bullets_total += int(s.n)
	# 弾が飛んでいる時間 → 被ダメージ係数の時定数
	active_time = 0.0
	if first_fire_time >= 0.0 and last_fire > first_fire_time:
		active_time = last_fire - first_fire_time
		for b in breaks:
			active_time -= maxf(minf(float(b[1]), last_fire) - maxf(float(b[0]), first_fire_time), 0.0)
	damage_tau = DAMAGE_TAU * maxf(active_time / DAMAGE_REF_TIME, 1.0)
	boss = null
	loop_len = 0.0
	if bool(mods.get("boss", false)):
		zones = []   # 撃破では危険エリアを出さない
		# 周回で足していくので、元の弾幕(選曲画面が覚えているもの)を書き換えないよう、写しを使う
		events = events.duplicate()
		gizmos = gizmos.duplicate()
		breaks = breaks.duplicate()
		_base_events = events.duplicate()
		_base_gizmos = gizmos.duplicate()
		_base_breaks = breaks.duplicate()
		loops_added = 1
		loop_end = maxf(last_fire, 0.0)
		for g in gizmos:
			loop_end = maxf(loop_end, float(g.end))
		loop_from = maxf(first_fire_time - LOOP_LEAD, 0.0)
		loop_len = maxf(loop_end - loop_from + Boss.BONUS_TIME, 1.0)
		damage_tau = DAMAGE_TAU * maxf(Boss.HP_CHASE_SECONDS / DAMAGE_REF_TIME, 1.0)   # 1 周ではなく、想定の戦いの長さで
		boss = Boss.new()
		boss.setup(events, gizmos, breaks, move_rect, first_fire_time, last_fire)
	_update_score()


## 最初の弾幕を待っていて、自然回復が止まっているか(regen_wait_first のとき、最初の発射まで)。
func regen_paused(now: float) -> bool:
	return regen_wait_first and (first_fire_time < 0.0 or now < first_fire_time)


## 撃破: 時刻 now が何周目か(0 = 1 周目。ボーナスタイムは、その周に入る)。
func loop_index(now: float) -> int:
	if loop_len <= 0.0:
		return 0
	return maxi(int(floor((now - loop_from) / loop_len)), 0)


## 撃破: ボーナスタイムの残り秒(ボーナスタイムでなければ -1)。
func bonus_left(now: float) -> float:
	if loop_len <= 0.0:
		return -1.0
	var b0 := float(loop_index(now)) * loop_len + loop_end
	if now >= b0 and now < b0 + Boss.BONUS_TIME:
		return b0 + Boss.BONUS_TIME - now
	return -1.0


## 撃破: 次の周の弾幕を足しておく(いまの周が始まったら、次の周を足す。いつも 1 周先まである)。
func _extend_loop(now: float) -> void:
	while now >= float(loops_added - 1) * loop_len and loops_added < 100000:
		var off := float(loops_added) * loop_len
		var ev: Array = []
		for e in _base_events:
			var e2: Dictionary = e.duplicate()
			e2.t = float(e.t) + off
			ev.append(e2)
		var gz: Array = []
		for g in _base_gizmos:
			var g2: Dictionary = g.duplicate()
			g2.t = float(g.t) + off
			g2.end = float(g.end) + off
			gz.append(g2)
		events.append_array(ev)
		gizmos.append_array(gz)
		for b in _base_breaks:
			breaks.append([float(b[0]) + off, float(b[1]) + off])
		boss.append_loop(ev, gz)
		loops_added += 1


## 協力モードにする(setup のあとに呼ぶ)。体力は全員で 1 本を共有し、人数に応じて増える(満タン = 1 人ぶんの被弾時間 × 人数)。
## 全員の被弾時間を足して減るので、1 人あたりの負担は、ひとりで遊ぶときと同じになる。
func setup_coop(n: int, is_host: bool) -> void:
	net_mode = "coop"
	players_n = maxi(n, 1)
	authority = is_host
	drain_time *= float(players_n)
	graze_div = float(players_n)
	_update_score()


## ホスト: 参加者から届いた被弾の報告(被弾時間・グレイズ・被弾回数)を、共有のゲージとスコアに反映する。
func ext_report(contact_s: float, graze_n: int, hit_n: int, extra_s := 0.0, heal_s := 0.0, gbonus := 0.0, refund_n := 0) -> void:
	if not authority or finished:
		return
	if extra_s > 0.0:   # 参加者のデバフ(脆弱・毒)による追加ダメージ
		var sdmg := extra_s / drain_time
		damage_total += sdmg
		gauge -= sdmg
	if heal_s > 0.0:   # 参加者の癒しによる回復(累計ダメージからは引かない)
		gauge = minf(gauge + heal_s / drain_time, 1.0)
	graze_bonus += maxf(gbonus, 0.0)
	graze += maxi(graze_n, 0)
	hits += maxi(hit_n, 0)
	if contact_s > 0.0:
		hit_time += contact_s
		var factor := GAUGE_LOW_FACTOR if (low_protect and gauge <= low_threshold) else 1.0
		var dmg := contact_s / drain_time * factor
		damage_total += dmg
		gauge -= dmg
		_ext_hit_t = 0.3
	_apply_graze_refund(refund_n)
	_update_score()


## 稼ぎエリアの中のグレイズ n 回ぶん、失っている被ダメージ係数(1 − damage_factor)を ZONE_GRAZE_REFUND の割合ずつ取り戻す。
## 失った分が大きいほど、1 回で戻る量も大きく、失った分が 0 なら何も戻らない(係数は 1 を超えない)。damage_total は変えず、damage_refund に積む。
func _apply_graze_refund(n: int) -> void:
	if n <= 0 or damage_refund >= damage_total:
		return
	var lost := 1.0 - exp(-(damage_total - damage_refund) / damage_tau)
	if lost <= 0.0:
		return
	lost *= pow(1.0 - ZONE_GRAZE_REFUND, float(n))
	damage_refund = damage_total + damage_tau * log(1.0 - lost)


## 参加者: ホストから届いた共有の状態(ゲージ・累計ダメージ・グレイズ・被弾回数・被弾時間)を反映する。
func apply_net_state(d: Dictionary) -> void:
	gauge = clampf(float(d.get("g", gauge)), 0.0, 1.0)
	damage_total = float(d.get("d", damage_total))
	damage_refund = float(d.get("r", damage_refund))
	graze = int(d.get("z", graze))
	hits = int(d.get("h", hits))
	hit_time = float(d.get("ht", hit_time))
	_update_score()


## 参加者: ホストが決めた出来事(休憩の一掃・クリア・ゲームオーバー)を反映する。
func apply_net_event(e: Dictionary, now: float) -> void:
	match str(e.get("k", "")):
		"wipe":
			field.clear()
			break_clear_t = now
			break_end_t = float(e.get("end", now))
		"clear":
			if e.has("st"):
				apply_net_state(e.st)
			field.clear()
			finished = true
			progress = 1.0
			score_progress = 1.0
			break_clear_t = -1.0
			_update_score()
		"fail":
			if e.has("st"):
				apply_net_state(e.st)
			failed = true
			finished = true
			death_pos = player_pos
			death_time = now
			_update_score()


## 参加者: まだ送っていない被弾の報告を取り出す(取り出すと 0 に戻る)。何もなければ空の辞書。
func take_contact() -> Dictionary:
	if contact_dt <= 0.0 and contact_graze == 0 and contact_hits == 0 and contact_extra <= 0.0 and contact_heal <= 0.0 and contact_gbonus <= 0.0 and contact_grefund == 0:
		return {}
	var out := {"c": contact_dt, "z": contact_graze, "h": contact_hits, "s": contact_extra, "hl": contact_heal, "zb": contact_gbonus, "zr": contact_grefund}
	contact_dt = 0.0
	contact_extra = 0.0
	contact_heal = 0.0
	contact_gbonus = 0.0
	contact_grefund = 0
	contact_graze = 0
	contact_hits = 0
	return out


## ホスト: 今の共有の状態(参加者へ配る)。
func net_state() -> Dictionary:
	return {"g": gauge, "d": damage_total, "r": damage_refund, "z": graze, "h": hits, "ht": hit_time}


## 自機狙いの目標位置の一覧。協力では、全員を 1 発ずつ(全員が同じ頻度で狙われる)。ホストが決めて配った位置があればそれ、
## なければ(届く前に撃つ場合)いま分かっている全員の位置(スロット順)。ひとり・対戦では、自分だけ。
func aim_targets_for(idx: int) -> Array:
	if aim_targets.has(idx):
		return aim_targets[idx]
	if net_mode == "coop" and slot_positions.size() > 1:
		return slot_positions
	return [player_pos]


## 休憩地帯の中か。
func in_break(now: float) -> bool:
	for b in breaks:
		if now >= b[0] and now <= b[1]:
			return true
	return false


## キーボード操作。now: 曲時間(秒)、dt: 経過秒、move: 入力方向(未正規化可)
func step(now: float, dt: float, move: Vector2, slow_mode: bool) -> void:
	if finished:
		return
	slow = slow_mode
	_prev_pos = player_pos
	_update_zone_debuff(now)
	if move != Vector2.ZERO:
		var spd := PLAYER_SLOW if slow else PLAYER_SPEED
		spd *= zone_speed_mul()
		_move_player(player_pos + move.normalized() * spd * dt)
	if zone_push != Vector2.ZERO:
		_move_player(player_pos + zone_push * dt)
	_update(now, dt)


## マウス操作。delta_px: このフレームのカーソル移動量(アリーナ座標系、感度・低速の倍率は適用済み)。
func step_relative(now: float, dt: float, delta_px: Vector2, slow_mode: bool) -> void:
	if finished:
		return
	slow = slow_mode
	_prev_pos = player_pos
	_update_zone_debuff(now)
	delta_px *= zone_speed_mul()
	_move_player(player_pos + delta_px + zone_push * dt)
	_update(now, dt)


func _move_player(p: Vector2) -> void:
	var m := Vector2.ONE * PLAYER_MARGIN * player_scale
	player_pos = p.clamp(move_rect.position + m, move_rect.end - m)


func _update(now: float, dt: float) -> void:
	steps_total += 1
	sfx_queue.clear()
	sfx_pan.clear()
	just_hit = false
	if loop_len > 0.0:
		_extend_loop(now)
	var quiet: bool = boss != null and boss.defeated   # 撃破のあとは、もう撃たない
	# 予兆の開始
	while _warn_idx < events.size() and events[_warn_idx].t - warn_lead <= now:
		var e: Dictionary = events[_warn_idx]
		if e.warn and e.t > now and not quiet:
			active_warns.append(e)
		_warn_idx += 1
	# ギズモ(スライダー軌道/スピナー)の開始
	while _giz_idx < gizmos.size() and gizmos[_giz_idx].t - warn_lead <= now:
		if not quiet:
			active_gizmos.append(gizmos[_giz_idx])
		_giz_idx += 1
	# 発射
	while _ev_idx < events.size() and events[_ev_idx].t <= now:
		if not quiet:
			_fire(events[_ev_idx], now)
		_ev_idx += 1
	# 発射地点の印の掃除
	if not recent_fires.is_empty():
		recent_fires = recent_fires.filter(func(f): return now - f.t < FIRE_MARK_TIME)
	# 掃除
	if not active_warns.is_empty():
		active_warns = active_warns.filter(func(e): return e.t > now)
	if not active_gizmos.is_empty():
		active_gizmos = active_gizmos.filter(func(g): return g.end + 0.3 > now)

	# 弾(当たっている間は毎ステップダメージ。弾は消えない)
	field.update(dt, player_pos, player_r * hit_mult, true, _prev_pos)
	var resting := in_break(now)  # 休憩地帯: スコアは上がらず、ゲージも回復しない
	if authority:
		_update_break_wipe(now, resting)
	elif not resting:
		break_clear_t = -1.0
	if not resting:
		own_graze += field.graze_count
		if authority:
			graze += field.graze_count
		else:
			contact_graze += field.graze_count   # 協力の参加者: ホストへ報告する
		var gmul := zone_graze_mul()
		if gmul > 0.0 and field.graze_count > 0:
			if authority:
				graze_bonus += float(field.graze_count) * gmul
			else:
				contact_gbonus += float(field.graze_count) * gmul
		if zone_area_type == "bonus" and field.graze_count > 0:
			if authority:
				_apply_graze_refund(field.graze_count)
			else:
				contact_grefund += field.graze_count
	hit_now = field.hit and not debug_invincible
	_ext_hit_t = maxf(_ext_hit_t - dt, 0.0)
	if hit_now:
		if _no_hit_time >= EPISODE_GAP:
			own_hits += 1
			if authority:
				hits += 1
			else:
				contact_hits += 1
			just_hit = true
			hit_log.append(now)
		_no_hit_time = 0.0
		own_hit_time += dt
		# ダメージは「触れていた時間」と「弾の中を通った距離 ÷ 基準速度」の長いほう(速く動いて抜けても、減りすぎない)
		var eff_dt := maxf(dt, field.hit_dist / CONTACT_SPEED_REF)
		var fragile := ZONE_FRAGILE if zone_debuff == "fragile" else 1.0
		# ゲージが少ないとき(20% 以下。MOD「天国」は 35%)は被ダメージが半分(MOD「地獄」で無効になる)
		var factor := GAUGE_LOW_FACTOR if (low_protect and gauge <= low_threshold) else 1.0
		var dmg := eff_dt / drain_time * factor * fragile
		own_damage += dmg
		if authority:
			hit_time += dt
			damage_total += dmg
			gauge -= dmg
		else:
			contact_dt += dt
			var extra := eff_dt * fragile - dt   # 脆弱と、速く動いた分の追加(ホストへは追加ダメージとして送る)
			if extra > 0.0:
				contact_extra += extra
	else:
		_no_hit_time += dt
		if regen and not resting and authority and _ext_hit_t <= 0.0 and not regen_paused(now):
			gauge = minf(gauge + regen_rate * gauge_unit * dt, 1.0)

	_update_poison(dt, resting)
	_update_heal(dt, resting)
	_record_gauge(now)
	if boss != null:
		boss.update(now, dt, player_pos, resting)
		_apply_boss_picks()
		_heal_by_hits(dt)

	# 進行率: 曲の進行(時間)とは別に、スコア用の進行率は「発射した弾数」で進める
	progress = clampf(now / maxf(end_time, 0.001), 0.0, 1.0)
	score_progress = clampf(float(bullets_fired) / float(maxi(bullets_total, 1)), 0.0, 1.0) if bullets_total > 0 else 0.0
	if boss != null:   # 撃破: 進行率はボスに与えたダメージの割合
		score_progress = clampf(1.0 - float(boss.hp) / maxf(float(boss.max_hp), 1.0), 0.0, 1.0)
	_update_score()

	if not authority:
		return   # 協力の参加者: ゲームオーバー・クリアはホストが決める(apply_net_event)

	if gauge <= 0.000001 and guard > 0 and not practice:   # サバイバルの身代わり: 1 回だけ踏みとどまり、盤面の弾を消す
		guard -= 1
		gauge = guard_gauge
		guard_t = now
		field.clear()
		active_warns.clear()
	if gauge <= 0.000001:
		gauge = 0.0
		if not practice:
			fail_score = score
			failed = true
			finished = true
			death_pos = player_pos
			death_time = now
			_update_score()  # ゲームオーバーは 0 点
			if net_mode == "coop":
				net_events.append({"k": "fail", "st": net_state()})
			return
	if boss != null:   # 撃破: ボスを倒したら弾を消し、少し待ってクリア(倒すまでは、曲が繰り返すので終わらない)
		if boss.defeated:
			if not _boss_cleared:
				_boss_cleared = true
				field.clear()
				active_warns.clear()
				score_boss_time = SCORE_BOSS_TIME * exp(-maxf(float(boss.defeat_t) - maxf(first_fire_time, 0.0), 0.0) / BOSS_TIME_TAU)
				_update_score()
			if now - float(boss.defeat_t) >= BOSS_CLEAR_DELAY:
				finished = true
				progress = 1.0
				score_progress = 1.0
				break_clear_t = -1.0
				_update_score()
		return
	if _check_clear(now):
		field.clear()
		finished = true
		progress = 1.0
		score_progress = 1.0  # クリア: 表示点数が最終点になる
		break_clear_t = -1.0
		_update_score()
		if net_mode == "coop":
			net_events.append({"k": "clear", "st": net_state()})


## ゲージの推移を GAUGE_LOG_STEP 秒ごとに記録する(曲の時刻が 0 になってから。時刻が飛んだときは、その間は同じ値で埋める)。
func _record_gauge(now: float) -> void:
	if now < 0.0:
		return
	log_end_t = now
	while float(_log_i) * GAUGE_LOG_STEP <= now and _log_i < 20000:
		gauge_log.append(clampf(gauge, 0.0, 1.0))
		_log_i += 1


## いまの時刻・自機の位置で受けるエリアの効果を決める(動く前に呼ぶ。休憩では効かない)。弾に作用する時の淀みも、ここで弾の側へ渡す。
func _update_zone_debuff(now: float) -> void:
	zone_debuff = ""
	zone_area_type = ""
	zone_push = Vector2.ZERO
	hit_mult = 1.0
	if zones.is_empty() or in_break(now):
		_clear_warp()
		return
	while _zone_i < zones.size() and float(zones[_zone_i].end) <= now:
		_zone_i += 1
	if _zone_i >= zones.size() or float(zones[_zone_i].t) > now:
		_clear_warp()
		return
	var z: Dictionary = zones[_zone_i]
	if z.has("areas"):
		if _warp_zi != _zone_i or now < _warp_t or now - _warp_t >= WARP_REFRESH:   # 淀み・急流の形は、数 ms ごとに作り直せば足りる(1ms 刻みで毎回作らない)
			_update_warp(z, now)
			_warp_t = now
			_warp_zi = _zone_i
	var a := _area_at(z, player_pos, now)
	zone_area_type = str(a.get("type", ""))
	if zone_area_type != "warp" and zone_area_type != "haste":   # 弾に作用するだけのエリアは、自機には何も効かない
		zone_debuff = zone_area_type
	if zone_debuff == "flow":
		zone_push = (a.dir as Vector2).normalized() * ZONE_FLOW_SPEED
	hit_mult = _hit_mult_of(zone_debuff)


## 時刻 now に、点 p にいる人がいるエリア(z = 時刻が合っている zones の要素。形式は、v1 のマス・v2 の形の両方)。なければ空の辞書。
func _area_at(z: Dictionary, p: Vector2, now: float) -> Dictionary:
	if z.has("areas"):
		return ZoneArea.area_at(z, p, now, move_rect)
	var cell := cell_of(p)
	for c in z.cells:
		if int(c.c) == cell:
			return c
	return {}


func _type_at(z: Dictionary, p: Vector2, now: float) -> String:
	return str(_area_at(z, p, now).get("type", ""))


static func _hit_mult_of(type: String) -> float:
	match type:
		"big":
			return ZONE_BIG
		"precise":
			return ZONE_PRECISE_HIT
	return 1.0


## いま受けているエリアの、移動の倍率(鈍足・精密)。
func zone_speed_mul() -> float:
	match zone_debuff:
		"slow":
			return ZONE_SLOW
		"precise":
			return ZONE_PRECISE_SPEED
	return 1.0


## いま受けているエリアの、グレイズの上乗せの割合(試練 = ZONE_GRAZE_TRIAL / 稼ぎ = ZONE_GRAZE_BONUS / それ以外 0)。
func zone_graze_mul() -> float:
	if zone_area_type == "bonus":
		return ZONE_GRAZE_BONUS
	if ZoneArea.family_of(zone_area_type) == "trial":   # 時の急流のように、自機には効かない試練も含む
		return ZONE_GRAZE_TRIAL
	return 0.0


## 時の淀み: 効いている間、弾の側へ、淀みの形(世界の座標)を渡す。
func _clear_warp() -> void:
	_warp_zi = -1
	if not field.warp.is_empty():
		field.warp = []


func _update_warp(z: Dictionary, now: float) -> void:
	field.warp = []
	var u := ZoneArea.progress(z, now)
	for a in z.areas:
		if str(a.type) != "warp" and str(a.type) != "haste":
			continue
		var sh: Dictionary = a.shape
		var w := {"f": ZONE_WARP if str(a.type) == "warp" else ZONE_HASTE}
		if str(sh.k) == ZoneArea.RECT:
			w["rect"] = ZoneArea.bounds(sh, move_rect, u)
		else:
			w["c"] = move_rect.position + (sh.c as Vector2) * move_rect.size
			w["r2"] = pow(ZoneArea.world_radius(sh, move_rect), 2.0)
		field.warp.append(w)


## 自機が動ける範囲(小型化 MOD なら中央の長方形)を 3×3 に分けたマス番号(0..8。左上から横に数える)。危険エリアはこのマス。
func cell_of(p: Vector2) -> int:
	var q := p - move_rect.position
	return clampi(int(q.y / (move_rect.size.y / 3.0)), 0, 2) * 3 + clampi(int(q.x / (move_rect.size.x / 3.0)), 0, 2)


## 自機が動ける範囲の、マス c(0..8)の長方形。
func cell_rect(c: int) -> Rect2:
	var cs := move_rect.size / 3.0
	return Rect2(move_rect.position + Vector2(float(c % 3) * cs.x, float(c / 3) * cs.y), cs)


## 位置 p にいる人の、当たり判定の倍率(巨大のデバフ)。状態は変えない。
## 描画用: マルチプレイで、他の人の当たり判定の点を、その人の実際の大きさで描く(デバフは位置と時刻だけで決まる)。
func hit_mult_at(p: Vector2, now: float) -> float:
	if zones.is_empty() or in_break(now):
		return 1.0
	for i in range(_zone_i, zones.size()):
		var z: Dictionary = zones[i]
		if float(z.t) > now:
			break
		if float(z.end) <= now:
			continue
		return _hit_mult_of(_type_at(z, p, now))   # 小型化では、動ける範囲に対するエリア
	return 1.0


## 盤面全体の 3×3 のマス番号(0..8。左上から横に数える)。
static func zone_cell(p: Vector2) -> int:
	return clampi(int(p.y / (ARENA.y / 3.0)), 0, 2) * 3 + clampi(int(p.x / (ARENA.x / 3.0)), 0, 2)


## デバフの名前と色(表示用)。
static func zone_name(type: String) -> String:
	return {"slow": "鈍足", "fragile": "脆弱", "poison": "毒", "big": "巨大", "heal": "癒し", "precise": "精密", "bonus": "稼ぎ", "warp": "時の淀み", "haste": "時の急流", "flow": "流れ"}.get(type, "")


static func zone_color(type: String) -> Color:
	return {"slow": Color(0.35, 0.68, 1.0), "fragile": Color(1.0, 0.62, 0.25), "poison": Color(0.62, 0.9, 0.35), "big": Color(0.92, 0.45, 0.92),
		"heal": Color(1.0, 0.55, 0.75), "precise": Color(0.4, 0.95, 0.9), "bonus": Color(1.0, 0.85, 0.3), "warp": Color(0.6, 0.55, 1.0), "haste": Color(1.0, 0.4, 0.35), "flow": Color(0.88, 0.92, 1.0)}.get(type, Color.WHITE)


## 左のパネルに出す、エリアの系統の名前(試練 = デバフ / 恩恵)。
static func zone_family_name(type: String) -> String:
	return {"trial": "デバフ", "boon": "恩恵", "warp": "変質"}.get(ZoneArea.family_of(type), "")


## 撃破: ボスに当てた数に応じて、ゲージを回復する(速さは毎秒 HIT_HEAL_MAX まで。ためすぎない)。
func _heal_by_hits(dt: float) -> void:
	var n: int = boss.hits_total - _hits_seen
	_hits_seen = boss.hits_total
	_heal_pool = minf(_heal_pool + float(n) * HIT_HEAL, HIT_HEAL_MAX * 0.5)
	var take := minf(_heal_pool, HIT_HEAL_MAX * dt)
	_heal_pool -= take
	if authority and take > 0.0:
		gauge = minf(gauge + take, 1.0)


## 撃破: 取ったアイテムのうち、回復(ゲージ)とボム(弾を消す)を反映する。
func _apply_boss_picks() -> void:
	while _pick_i < boss.pick_events.size():
		var k: String = boss.pick_events[_pick_i].kind
		_pick_i += 1
		if k == "heal" and authority:
			gauge = minf(gauge + Boss.HEAL_AMOUNT, 1.0)
		elif k == "bomb":
			field.clear()
			active_warns.clear()


## 癒し: ゲージが増える(休憩では増えない)。協力の参加者は、被弾時間に換算してホストへ報告する(累計ダメージからは引かない)。
func _update_heal(dt: float, resting: bool) -> void:
	if zone_debuff != "heal" or resting:
		return
	var hs := ZONE_HEAL_RATE * gauge_unit * drain_time / float(players_n) * dt   # 1 人ぶんのゲージに対する割合を、被弾時間に換算
	if authority:
		gauge = minf(gauge + hs / drain_time, 1.0)
	else:
		contact_heal += hs


## 毒: ゲージが減る(休憩・練習では減らない)。協力の参加者は、被弾時間に換算してホストへ報告する。
func _update_poison(dt: float, resting: bool) -> void:
	if zone_debuff != "poison" or resting or practice:
		return
	var sd := ZONE_POISON_DRAIN * GAUGE_DRAIN_TIME * dt
	if authority:
		var dmg := sd / drain_time
		damage_total += dmg
		gauge -= dmg
	else:
		contact_extra += sd


## 休憩中、残った弾が当たりえない状態になったら一掃して、カウントダウンを始める。休憩が終わったら状態を戻す。
func _update_break_wipe(now: float, resting: bool) -> void:
	if not resting:
		break_clear_t = -1.0
		return
	if break_clear_t >= 0.0:
		return
	if _all_safe():
		field.clear()
		break_clear_t = now
		for b in breaks:
			if now >= b[0] and now <= b[1]:
				break_end_t = b[1]
				break
		if net_mode == "coop":
			net_events.append({"k": "wipe", "end": break_end_t})


## クリアの条件: 最後の弾幕を撃ち終え(予兆も終わり)、弾が当たりえない状態になった(または撃ち終えて CLEAR_TIMEOUT 秒たった)。
func _check_clear(now: float) -> bool:
	if events.is_empty():
		return now >= end_time
	if _ev_idx < events.size() or not active_warns.is_empty():
		return false
	if _all_fired_t < 0.0:
		_all_fired_t = now
	return now - _all_fired_t >= CLEAR_TIMEOUT or _all_safe()


## 残った弾がどれも「当たらない」か: 自機の近くに弾がなく、自機に接近している弾もない(BulletField.is_calm)。
func _all_safe() -> bool:
	if net_mode == "coop" and slot_positions.size() > 1:   # 協力: 全員の周りが落ち着いているとき
		for p in slot_positions:
			if not field.is_calm(p, player_r, SAFE_NEAR_R, SAFE_APPROACH_R, SAFE_LOOK_T):
				return false
		return true
	return field.is_calm(player_pos, player_r, SAFE_NEAR_R, SAFE_APPROACH_R, SAFE_LOOK_T)


## 今の点数を計算し直す。ゲームオーバーなら 0。
func _update_score() -> void:
	damage_factor = exp(-maxf(damage_total - damage_refund, 0.0) / damage_tau)
	if failed:
		score_gross = 0.0
		score_graze = 0.0
		score_boss_time = 0.0
		score_potential = 0.0
		score = 0.0
		return
	score_graze = SCORE_GRAZE * (1.0 - exp(-(float(graze) + graze_bonus) / graze_div / _graze_tau))   # 3 万点に漸近(届かない)
	score_gross = score_base + score_graze + score_boss_time
	score_potential = score_gross * damage_factor
	score = score_potential * score_progress


func _fire(e: Dictionary, now: float) -> void:
	var late := maxf(now - e.t, 0.0)
	var pos: Vector2 = e.pos
	var grace := 0.0
	if not e.shots.is_empty() and player_pos.distance_to(pos) < SAFE_RADIUS:   # 自機の近くで撃たれた: 続けて撃たれている間は、最初の GRACE_STREAK_MAX 秒だけ猶予
		if float(e.t) - _near_last > GRACE_STREAK_GAP:
			_near_start = float(e.t)
		_near_last = float(e.t)
		if float(e.t) - _near_start <= GRACE_STREAK_MAX:
			grace = SAFE_GRACE_PX
	var aims: Array = aim_targets_for(_ev_idx)   # 自機狙いの相手(協力では全員。ひとりでは自機)
	aim_targets.erase(_ev_idx)
	for s in e.shots:
		# 弾幕 v2 の任意キー: off = 発射位置のずれ / beh = 弾の挙動 {k, a, b, c}(BulletField.BEH_*)。v1 の shot にはない
		var src: Vector2 = pos + (s.off as Vector2) if s.has("off") else pos
		var g := grace
		if s.has("off") and player_pos.distance_to(src) < SAFE_RADIUS:   # 発射位置がずれている弾(壁・縁からの弾)が、自機のすぐそばに出るとき: 発射点の近くと同じ猶予
			g = maxf(g, SAFE_GRACE_PX)
		var bk := 0
		var ba := 0.0
		var bb := 0.0
		var bc := 0.0
		if s.has("beh"):
			var bh: Dictionary = s.beh
			bk = int(bh.k)
			ba = float(bh.a)
			bb = float(bh.b)
			bc = float(bh.c)
		for at in (aims if s.aim else [Vector2.ZERO]):
			var base: float = s.a0
			if s.aim:
				base += (at - src).angle()
			for i in range(s.n):
				var v: Vector2 = Vector2.from_angle(PatternGen.shot_angle(s, base, i)) * s.speed
				field.add(src + v * late, v, s.size * BULLET_SIZE_MUL, s.color, g, s.turn, bk, ba, bb, bc, late)
	if track_fires and not e.shots.is_empty():
		recent_fires.append({"pos": pos, "t": e.t, "color": e.shots[0].color})
	if not e.shots.is_empty():
		break_clear_t = -1.0   # 休憩中に新しい弾が撃たれたら、安全になるまで一掃を待ち直す
	if not in_break(e.t):
		for s in e.shots:
			bullets_fired += int(s.n) * (aims.size() if s.aim else 1)
	if e.sfx != "":
		sfx_queue.append(e.sfx)
		sfx_pan.append(clampf(pos.x / ARENA.x * 2.0 - 1.0, -1.0, 1.0))


## ランク。failed(ゲームオーバー)なら "-"(ランクなし)。ノーミス(hits == 0)は SS、それ以外は達成率(score / score_base)で S〜F。
static func rank_of(failed: bool, hits: int, score: float, score_base: float) -> String:
	if failed:
		return "-"
	if hits == 0:
		return "SS"
	var ratio := score / maxf(score_base, 1.0)
	for r in RANK_TABLE:
		if ratio >= float(r[1]):
			return r[0]
	return "F"


## ギズモ上のエミッタ位置(スライダーは往復を考慮)。
static func slider_emitter(g: Dictionary, now: float) -> Vector2:
	var pts: PackedVector2Array = g.points
	var span: float = g.span
	var u := 0.0 if span <= 0.0 else clampf((now - g.t) / span, 0.0, float(g.repeats))
	var slide := int(floor(u))
	var frac := u - slide
	if slide >= g.repeats:
		slide = g.repeats - 1
		frac = 1.0
	if slide % 2 == 1:
		frac = 1.0 - frac
	return _polyline_at(pts, frac)


static func _polyline_at(pts: PackedVector2Array, frac: float) -> Vector2:
	if pts.size() == 1:
		return pts[0]
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	var target := total * frac
	var acc := 0.0
	for i in range(1, pts.size()):
		var seg := pts[i].distance_to(pts[i - 1])
		if acc + seg >= target and seg > 0.0:
			return pts[i - 1].lerp(pts[i], (target - acc) / seg)
		acc += seg
	return pts[pts.size() - 1]
