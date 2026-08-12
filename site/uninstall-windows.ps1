#requires -Version 5.1
$ErrorActionPreference = "Stop"

$AppDir = Join-Path $env:LOCALAPPDATA "CDMXRadxaFlash"

if ($env:OS -ne "Windows_NT") {
    throw "Este script es solo para Windows."
}

$CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = [Security.Principal.WindowsPrincipal]::new($CurrentUser)
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Abre PowerShell como Administrador y vuelve a pegar el comando."
}

Write-Host "`nDesinstalando CDMX Radxa Flasher…"
$Processes = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -in @("python.exe", "pythonw.exe") -and
    $_.CommandLine -like "*$AppDir*host\imager_app.py*"
}
foreach ($Process in $Processes) {
    Stop-Process -Id $Process.ProcessId -Force -ErrorAction SilentlyContinue
}

if (Test-Path $AppDir) {
    Remove-Item -Recurse -Force $AppDir
}
Write-Host "Listo. El lector y la imagen en caché fueron eliminados."
Write-Host "No se modificó ninguna tarjeta SD."
