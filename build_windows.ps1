$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw 'Flutter SDK and Visual Studio Desktop C++ workload are required.' }
function Run-Flutter { & flutter @args; if ($LASTEXITCODE -ne 0) { throw "flutter $args failed" } }
Run-Flutter pub get
Run-Flutter gen-l10n
Run-Flutter analyze
Run-Flutter test
New-Item -ItemType Directory -Force dist | Out-Null
foreach ($arch in @('x64','arm64')) {
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  $component = if ($arch -eq 'arm64') { 'Microsoft.VisualStudio.Component.VC.Tools.ARM64' } else { 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64' }
  if (-not (Test-Path $vswhere)) { throw 'Visual Studio Installer vswhere.exe is required to verify installed C++ toolchains.' }
  $toolchain = & $vswhere -latest -products '*' -requires $component -property installationPath
  if (-not $toolchain) { Write-Warning "Skipping $arch: install Visual Studio component $component, then run flutter build windows --release --target-platform windows-$arch. No output is fabricated."; continue }
  & flutter build windows --release --target-platform "windows-$arch"
  if ($LASTEXITCODE -ne 0) { throw "Windows $arch build failed; install the matching MSVC C++ toolchain." }
  Compress-Archive -Path "build/windows/$arch/runner/Release/*" -DestinationPath "dist/Sirb-windows-$arch.zip" -Force
}
Write-Output 'macOS requires Xcode/CocoaPods on macOS. Linux requires a Linux host. ARMv7 and x86-32 desktop are unsupported by Flutter.'
