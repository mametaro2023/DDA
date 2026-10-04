# 書き出したアプリを起動して、少し待ってからウィンドウの ✕(WM_CLOSE)を送り、終了までの時間を測る(開発用)。
# 使い方: powershell -File tests/close_time.ps1 -Exe build/Danmaku_beta/Danmaku.exe -Wait 6 [-ArgLine "-- --smoke"]
param([string]$Exe, [int]$Wait = 6, [string]$ArgLine = "")
if ($ArgLine -ne "") { $p = Start-Process -FilePath $Exe -ArgumentList $ArgLine -PassThru } else { $p = Start-Process -FilePath $Exe -PassThru }
Start-Sleep -Seconds $Wait
$sw = [Diagnostics.Stopwatch]::StartNew()
$null = $p.CloseMainWindow()
if ($p.WaitForExit(20000)) { "closed in {0} ms" -f $sw.ElapsedMilliseconds } else { "STILL RUNNING after 20 s (hang)"; $p.Kill() }
