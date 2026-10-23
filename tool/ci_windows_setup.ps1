$ErrorActionPreference = 'Stop'
& dotnet tool install --global wix --version 6.0.2
if ($LASTEXITCODE -ne 0) { throw 'WiX installation failed' }
Join-Path $env:USERPROFILE '.dotnet/tools' | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
# Hosted images can contain Inno 6.2, which does not understand ARM64 targets.
# Install a fixed, hash-verified compiler into runner-local temporary storage.
$installer = Join-Path $env:RUNNER_TEMP 'innosetup-6.7.3.exe'
Invoke-WebRequest 'https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-6.7.3.exe' -OutFile $installer
if ((Get-FileHash $installer -Algorithm SHA256).Hash.ToLowerInvariant() -ne '9c73c3bae7ed48d44112a0f48e66742c00090bdb5bef71d9d3c056c66e97b732') { throw 'Inno Setup checksum mismatch' }
$directory = Join-Path $env:RUNNER_TEMP 'inno-setup'
$process = Start-Process $installer -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/CURRENTUSER',"/DIR=`"$directory`"" -PassThru -Wait
if ($process.ExitCode -ne 0) { throw "Inno Setup installation failed: $($process.ExitCode)" }
$compiler = Join-Path $directory 'ISCC.exe'
if (-not (Test-Path $compiler)) { throw 'Inno Setup compiler missing after installation' }
"ISCC=$compiler" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
