#requires -Version 5.1
$ErrorActionPreference = "Stop"

$SourceCommit = "0380f57a9550c8e3e7895425096aa934a507c901"
$ArchiveSha256 = "b9778ffee98013789204e3793abbd9b3695a1626f364815d3623cf88d5e877b2"
$ArchiveUrl = "https://codeload.github.com/the-matter-lab/cdmx-radxa-flash/tar.gz/$SourceCommit"
$PublicSite = "https://cdmx-radxaflash.mantilla.ca/"
$AppDir = Join-Path $env:LOCALAPPDATA "CDMXRadxaFlash"
$SourceDir = Join-Path $AppDir "source-$SourceCommit"
$Launcher = Join-Path $SourceDir "host\imager_app.py"
$Marker = Join-Path $SourceDir ".source-verified"
$Venv = Join-Path $SourceDir ".venv-imager"
$VenvPython = Join-Path $Venv "Scripts\python.exe"

if ($env:OS -ne "Windows_NT") {
    throw "Este script es solo para Windows."
}

$CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = [Security.Principal.WindowsPrincipal]::new($CurrentUser)
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Abre PowerShell como Administrador y vuelve a pegar el comando."
}

Write-Host "`nCDMX Radxa Flasher · Matter Lab"
Write-Host "Código fijado: $($SourceCommit.Substring(0, 12))`n"

$Verified = (Test-Path $Launcher) -and (Test-Path $Marker) -and ((Get-Content $Marker -Raw).Trim() -eq $ArchiveSha256)
if (-not $Verified) {
    $WorkDir = Join-Path $env:TEMP "cdmx-radxa-flash-$([Guid]::NewGuid().ToString('N'))"
    $Archive = Join-Path $WorkDir "source.tar.gz"
    $Unpacked = Join-Path $WorkDir "source"
    New-Item -ItemType Directory -Force -Path $AppDir, $Unpacked | Out-Null
    try {
        Write-Host "Descargando el lector desde GitHub…"
        Invoke-WebRequest -UseBasicParsing -Uri $ArchiveUrl -OutFile $Archive
        $ActualSha256 = (Get-FileHash -Algorithm SHA256 $Archive).Hash.ToLowerInvariant()
        if ($ActualSha256 -ne $ArchiveSha256) {
            throw "La verificación SHA-256 del código fuente falló."
        }
        & tar.exe -xzf $Archive -C $Unpacked --strip-components=1
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $Unpacked "host\imager_app.py"))) {
            throw "El archivo descargado no contiene el lector esperado."
        }
        if (Test-Path $SourceDir) {
            Remove-Item -Recurse -Force $SourceDir
        }
        Move-Item $Unpacked $SourceDir
        Set-Content -NoNewline -Encoding ASCII -Path $Marker -Value $ArchiveSha256
    }
    finally {
        if (Test-Path $WorkDir) {
            Remove-Item -Recurse -Force $WorkDir
        }
    }
}

if (-not (Test-Path $VenvPython)) {
    $Py = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($Py) {
        & $Py.Source -3 -m venv $Venv
    }
    else {
        $Python = Get-Command python.exe -ErrorAction SilentlyContinue
        if (-not $Python) {
            throw "Instala Python 3 desde python.org y vuelve a ejecutar este comando."
        }
        & $Python.Source -m venv $Venv
    }
}

& $VenvPython -m pip install --disable-pip-version-check -q -r (Join-Path $SourceDir "host\requirements.txt")

try {
    $Existing = Invoke-WebRequest -UseBasicParsing -MaximumRedirection 0 -Uri "http://127.0.0.1:8766/" -ErrorAction Stop
    if ($Existing.StatusCode -eq 302) {
        $CurrentHelper = Get-CimInstance Win32_Process | Where-Object {
            $_.Name -in @("python.exe", "pythonw.exe") -and
            $_.CommandLine -like "*$SourceDir*host\imager_app.py*"
        }
        if ($CurrentHelper) {
            Start-Process $PublicSite
            Write-Host "El lector ya está abierto."
            exit 0
        }
        throw "Hay una versión anterior del lector abierta."
    }
}
catch {
    try {
        Invoke-RestMethod -UseBasicParsing -Uri "http://127.0.0.1:8766/api/state" -ErrorAction Stop | Out-Null
        Write-Host "Actualizando el lector anterior…"
        Get-CimInstance Win32_Process | Where-Object {
            $_.Name -in @("python.exe", "pythonw.exe") -and
            $_.CommandLine -like "*$AppDir*host\imager_app.py*"
        } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 1
    }
    catch {}
}

Start-Process $PublicSite
Write-Host "Mantén PowerShell abierto mientras grabas tarjetas.`n"
& $VenvPython $Launcher --no-browser
