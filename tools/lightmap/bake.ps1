# Bakes the Mansion's lighting (AAA phase 3) end to end, from the repo root:  .\tools\lightmap\bake.ps1
# 1. builds collection/level/lightmap/mansion_bake.scn from the game's own code (make_bake_scene.gd, headless)
# 2. opens the editor once with the lightmap_bake plugin switched on, which presses Bake Lightmaps and quits
# 3. switches the plugin off again (project.godot is put back exactly as it was)
# Output: collection/level/lightmap/mansion_bake.lmbake and mansion_bake.exr (commit both, and the .exr's .import).
# Close the Godot editor first: it rewrites project.godot.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$proj = Join-Path $repo 'collection'
$godot = (Get-Command Godot_v4.7.2-stable_win64.exe).Source
$console = (Get-Command Godot_v4.7.2-stable_win64_console.exe).Source
if (Get-Process | Where-Object { $_.ProcessName -like 'Godot*' -and $_.MainWindowTitle -like '*imok Collection*' }) {
  throw 'The Collection project is open in the Godot editor: close it first.'
}
$log = Join-Path $proj 'level\lightmap\bake.log'
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null

& $console --headless --path $proj --script (Join-Path $PSScriptRoot 'make_bake_scene.gd') | Select-String 'BAKE SCENE|ERROR'

$pg = Join-Path $proj 'project.godot'
$orig = [IO.File]::ReadAllText($pg)
$result = Join-Path $proj 'level\lightmap\bake_result.txt'
Remove-Item $result -ErrorAction SilentlyContinue
try {
  $on = $orig.TrimEnd() + "`n`n[editor_plugins]`n`nenabled=PackedStringArray(`"res://addons/lightmap_bake/plugin.cfg`")`n"
  [IO.File]::WriteAllText($pg, $on, (New-Object Text.UTF8Encoding $false))
  $env:COLLECTION_BAKE = '1'
  $p = Start-Process -FilePath $godot -ArgumentList '-e', '--path', "`"$proj`"", 'res://level/lightmap/mansion_bake.scn', '--log-file', "`"$log`"" -PassThru
  if (-not $p.WaitForExit(1800000)) { $p.Kill(); Write-Output 'TIMED OUT after 30 minutes' }
} finally {
  $env:COLLECTION_BAKE = $null
  [IO.File]::WriteAllText($pg, $orig, (New-Object Text.UTF8Encoding $false))
}
if (Test-Path $result) { Get-Content $result } else { Write-Output 'no result written; see bake.log' }
Get-ChildItem (Split-Path $log) | Select-Object Name, @{n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } }
