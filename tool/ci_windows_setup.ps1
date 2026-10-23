$ErrorActionPreference = 'Stop'
& dotnet tool install --global wix --version 6.0.2
if ($LASTEXITCODE -ne 0) { throw 'WiX installation failed' }
Join-Path $env:USERPROFILE '.dotnet/tools' | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
$compiler = Get-ChildItem "${env:ProgramFiles(x86)}\Inno Setup*\ISCC.exe", "$env:ProgramFiles\Inno Setup*\ISCC.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $compiler) { throw 'Runner must provide Inno Setup 6.3+ (ISCC.exe)' }
$version = $compiler.VersionInfo.FileVersionRaw
if ($version.Major -lt 6 -or ($version.Major -eq 6 -and $version.Minor -lt 3)) { throw 'Inno Setup 6.3+ required for ARM64' }
"ISCC=$($compiler.FullName)" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
