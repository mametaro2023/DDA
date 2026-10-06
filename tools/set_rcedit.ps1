# Godot の書き出しで exe にアイコン・版情報を埋め込むため、エディタ設定の export/windows/rcedit を tools/rcedit-x64.exe に向ける。
# (build.bat が書き出しの前に呼ぶ。設定が無ければ作り、あれば書き換える)
$rc = (Resolve-Path (Join-Path $PSScriptRoot 'rcedit-x64.exe')).Path.Replace([string][char]92, '/')
$dir = Join-Path $env:APPDATA 'Godot'
$file = Join-Path $dir 'editor_settings-4.7.tres'
$line = 'export/windows/rcedit = "' + $rc + '"'
if (-not (Test-Path $file)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [IO.File]::WriteAllText($file, "[gd_resource type=`"EditorSettings`" format=3]`n`n[resource]`n$line`n")
    exit 0
}
$text = [IO.File]::ReadAllText($file)
if ($text -match '(?m)^export/windows/rcedit\s*=.*$') {
    $text = [regex]::Replace($text, '(?m)^export/windows/rcedit\s*=.*$', $line)
} else {
    $text = [regex]::Replace($text, '(?m)^\[resource\]\s*$', "[resource]`n$line", 1)
}
[IO.File]::WriteAllText($file, $text)
