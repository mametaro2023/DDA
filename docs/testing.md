# テスト

## テスト(ヘッドレス)
```
godot --headless --path . --script tests/test_ui_contract.gd            # どの UI セットの画面・パネルも、決まりの signal・メソッド・kind を持つ
godot --headless --path . --script tests/test_ui_default.gd              # 既定の UI が lazer: 設定が無い人は lazer・旧版の既定のままの人は一度だけ lazer に引き継ぐ・自分で選んだ classic は残る(user://settings.cfg を一時的に書き換えて戻す)
godot --headless --path . --script tests/test_records.gd                # プレイ記録(残す条件・スコア順・上位 10 件・新記録・保存)
godot --headless --path . --script tests/test_song_view.gd              # 選曲の検索・並び替え
godot --headless --path . --script tests/test_howto.gd                  # 遊び方パネル(10 ページと 13 枚の挿絵が、classic・lazer 風の両方で作れる)
godot --headless --path . --script tests/test_chart_cache.gd            # 譜面の読み込み結果の保存(統計と発射の一覧の 2 段・全曲の準備・弾幕を変える MOD・ファイルが変わったら読まない・壊れた保存)
godot --path . -- --smoke-uiswitch                                      # 設定で UI の見た目を切り替えると、いまのタイトルが作り直される
godot --headless --path . --script tests/test_song_sources.gd          # osu! の譜面ページの URL から曲の ID を読む・osu! の Songs フォルダを勧める場所
godot --path . -- --ui lazer --smoke-fetch                             # 曲がないときの「osu! の曲を使う」「URL から取り込む」・Ctrl+V・検索欄への URL(手元のミラーから取り込んで選ぶ。--ui classic でも。node が要る)
godot --path . -- --ui lazer --smoke-osu-menu                          # osu! の Songs フォルダの曲が選曲画面に足され、選んで読める・弾幕 v2 で読み直しても難易度が保たれる(--ui classic でも)
godot --path . -- --ui lazer --smoke-player                                   # 上のプレイヤー: 線を押す・ドラッグして飛ぶ / プレイリストを流して、次へ・曲が終わって次へ(タイトルも選曲も)/ 外の曲を選ぶと止まる / プロフィールの保存(設定は元へ戻す)
godot --headless --path . --script tests/test_playlist.gd                # プレイリスト: 編集・順に進める・シャッフル・リピート・選曲で別の曲を選んだとき・保存
godot --path . -- --ui lazer --smoke-carousel                          # 選曲の一覧: 曲を移るときに行が跳ばない・読み込みで難易度の行を作り直さない・並び替えの動きが最初のフレームから始まる
godot --path . -- --ui lazer --prof-ui                                  # UI の操作ごとの、止まり(一番長いフレーム)を測る。どの確認にも --hitch 25 を足すと、25 ms を超えたフレームを記録する
godot --path . -- --ui lazer --smoke-ui                                 # (確認用の起動(`--smoke*` `--shot*` `--prof*`)の既定は classic。`--ui lazer` を足すと lazer 風で通せる。`--smoke-ui` `--smoke-title` `--smoke-mp-ui` `--smoke-clear` など。内部の変数を直接見る確認は、クラシックだけ)
godot --headless --path . --script tests/test_parser.gd
godot --headless --path . --script tests/test_star.gd                   # 推定★と公式値の比較
godot --headless --path . --script tests/test_rating.gd                 # 全 .osz の Lv を公式★と並べて表示(順位相関・イントロ非依存の確認つき)
godot --headless --path . --script tests/test_speed_study.gd            # 弾速の実験: 条件の選び方・記録の読み書き・集計・同じ Lv に合わせた弾幕
godot --headless --path . --script tests/test_grace.gd                  # 自機の近くで撃たれた弾の猶予(不意打ちは防ぐ・スピナーの中央に居座ると当たる)
godot --path . -- --smoke-speed-study                                 # 弾速の実験を実際のプレイ画面で通す(確認用の別ファイルに記録する)
godot --headless --path . --script tests/test_sim.gd -- Hard Extra    # 簡易ボットで全曲走行(推定値との比較つき。`hell` `storm` `giant` `rush` を足すと、その MOD を付けて走る。`1khz` を足すと 1 ms 刻みで走り、処理コストも表示する)
godot --headless --path . --script tests/test_collision.gd            # 当たり判定・マウス相対移動
godot --path . -- --smoke-ui                                          # 選曲 → 設定 → 開始 → ポーズ → メニューを、実際のキー入力で通しで確認(ウィンドウが開く)
godot --path . -- --smoke-clock                                       # 曲クロックの増分のばらつき(カクつき)と、音声クロックとのずれを測る(ウィンドウが開く)
godot --path . -- --ui lazer --smoke-preview                          # 選曲の試聴: 加速・減速で速さが変わる / 難易度ごとに音声が違う曲で、難易度を選ぶと音声が替わる、を確認(ウィンドウが開く)
godot --path . -- --ui lazer --smoke-loader                           # 選曲 →「プレイ」→ 開始前画面 → 自動 / Enter でプレイへ・Esc で選曲へ・リトライは通らない、を確認(ウィンドウが開く)
godot --path . -- --smoke-back                                        # 選曲 → プレイ → メニューへ戻ったとき、直前の難易度が選ばれていることを確認(ウィンドウが開く)
godot --path . -- --smoke-kiai                                        # キアイ中の光が拍に合わせて脈打つことを確認(ウィンドウが開く)
godot --path . -- --smoke-title                                       # タイトル(曲が流れる)→ 遊び方・設定の開閉(設定を開いている間、タイトルがキーに反応しないことも)→ プレイ → 選曲 → Esc → タイトル を、キー入力で通して確認(ウィンドウが開く)
godot --path . -- --smoke-clear                                       # 最後の弾幕のあとクリア → リザルトでも曲が流れ続け、メニューで消えることを確認(ウィンドウが開く)
godot --headless --path . --script tests/test_sfx.gd                  # 効果音のファイル(assets/sfx。ゲームの音も UI の音も)の性質。`-- wav` で WAV を書き出す
godot --headless --path . --script tools/sfx_forge.gd -- --verify     # assets/sfx がレシピどおりか(書き出し直しは `-- --preview` で確認用の画像つき)
godot --path . -- --smoke-sfx                                          # 効果音のファイルが読めて鳴ること(書き出した exe でも使える)
godot --headless --path . --script tests/test_special.gd               # 発生源の散らし(弾の通過密度の偏り)・曲がる弾
godot --headless --path . --script tests/test_skip.gd                  # マルチプレイのスキップ(人数を数える・全員が押したら飛ばす・去った人・重複した合図)
godot --path . -- --smoke-modscroll                                  # MOD の 6 枚がスクロールなしで収まる / パネルの上のホイールが後ろの一覧を動かさない / パネルの外のクリックと「✕」で閉じる(MOD・設定)/ 「すべて解除」を確認(ウィンドウが開く)
godot --path . -- --smoke-skip                                         # ひとりのスキップ(Space・READY 中・マウス操作のボタンと捕まえ直し)
godot --headless --path . --script tests/test_zones_v2.gd              # 特殊エリア(弾幕 v2。形・決定性・予告・休憩・系統と種類・中央に居続けられない・各効果・時の淀み・協力の報告)
godot --headless --path . --script tests/test_zones.gd                 # 危険エリア(数・種類・小節の頭・各デバフの効き方・休憩/練習・協力の報告)
godot --headless --path . --script tests/analyze_coverage.gd -- Insane  # 通過密度の地図と、居座るボットの比較(開発用)
godot --headless --path . --script tests/test_gauge.gd                # ゲージ・スコア・休憩地帯(一掃・カウントダウン)・クリア判定・MOD(効果・合成・適用後の Lv)・スキップ位置
godot --headless --path . --script tests/test_contact_dist.gd          # 弾を速く抜けてもダメージが減りすぎない(触れていた時間と、通った距離 ÷ 基準速度の長いほう)/ 止まっている自機に弾が通り過ぎるときは時間のまま / 協力の参加者は時間と追加ダメージに分けて送る
godot --headless --path . --script tests/test_net.gd                  # 招待コード(往復・誤り検出・読み替え・IP の直接入力・分類)
godot --headless --path . --script tests/test_coop.gd                 # 協力の共有ゲージ(人数で増える・報告・ホストの決定・自機狙いの配布・一掃・クリア)
godot --headless --path . -- --smoke-net                              # 通信層を、同じプロセス内のホストと参加者で確認(参加・名簿・時計合わせ・開始の段取り・切断。localhost)
godot --path . -- --smoke-mp coop                                     # 協力を、ボット 2 人で実時間で通して確認(ゲージ・弾の一致・クリア)。`versus` / `coop fail` / `hard`(最上位の譜面)/ `lag120`(遅延の再現)を足せる
godot --path . -- --smoke-mp-ui                                       # ホスト側の実際の画面操作(タイトル → 部屋を作る → 選曲 → ロビー → 開始 → プレイ中メニュー → 退出)
godot --path . -- --smoke-upnp                                        # UPnP で本番と同じ部屋作り(ルーターのポートを一時的に開けて閉じる)。招待コードの中身を表示
godot --headless --path . --script tests/test_import.gd                # .osz の取り込み・音量・ダウンロードリンク・アプリのバージョン比較
godot --headless --path . --script tests/test_osu_folder.gd           # osu! の Songs フォルダ(展開済みの曲)を、そのまま曲として読む
godot --headless --path . --script tests/test_options_pages.gd         # 設定パネルの全ページを、動きつきで開く(ページの中に画面の部品でないものがあると失敗)
godot --path . -- --smoke-volume                                      # ホイールの音量(メーターの表示・選択・消えたら戻る・保存)を、実際の入力で確認
godot --path . -- --smoke-open                                        # .osz を開く流れ(別のプロセスから渡す・選曲画面で選ぶ・プレイ中は画面を変えない)
godot --path . -- --smoke-new                                          # 音量バーのドラッグ・選曲の別スレッド読み込み・なめらかスクロール・独自カーソル・どの画面でも設定・songs の見張りを、実際の入力で確認(ウィンドウが開く)
node tests/fake_mirror_server.js 8766 "22699 Len - U.N. Owen was her.osz"   # 曲のダウンロードの確認用の、手元のミラー(下の test_download.gd と組み合わせる)
godot --headless --path . --script tests/test_download.gd               # 曲のダウンロード(失敗するミラーを飛ばす・曲でないものを断る・部屋の譜面と違う中身を断る・取り込む)
godot --headless --path . --script tests/prof_select.gd                # 曲を選ぶときの処理時間の内訳(開発用)
godot --headless --path . --script tests/prof_play.gd                  # PLAY を押してから自機が出るまでの処理時間の内訳(開発用)
godot --path . -- --prof-play RPG                                      # 実際の画面で、PLAY を押したあとのフレームの止まりを測る(開発用。`nocache` で、選曲で作ったものを使わない場合と比べられる)
godot --headless --path . --script tests/test_result.gd                # 結果画面の部品(体力の間引き・ランクの境目がゲームの表と一致)
godot --headless --path . --script tests/prof_close.gd                 # 部屋を立てた状態で閉じるのにかかる時間(開発用。`-- quit` で、探索中にアプリを終える場合)
node tests/fake_release_server.js 8765 <zip> [bad]                    # アプリ内アップデートの確認用の、手元のリリースサーバー(--smoke-update と組み合わせる)
```
