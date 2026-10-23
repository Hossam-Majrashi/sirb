param([ValidateSet('x64','arm64')][string]$Arch = '')
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (-not $Arch) { $Arch = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') { 'arm64' } else { 'x64' } }
function Run-Checked([string]$Command, [string[]]$Arguments) {
  & $Command @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$Command failed with exit code $LASTEXITCODE" }
}
# Flutter 3.47 chooses Windows architecture from the Dart host ABI. Its Windows
# command has NO --target-platform option. Never rename an x64 payload to ARM64.
$dartVersion = (& dart --version 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $dartVersion -notmatch "windows_$Arch") { throw "Need native Windows $Arch Dart/Flutter SDK; got $dartVersion" }
Run-Checked flutter @('pub','get')
Run-Checked flutter @('gen-l10n')
Run-Checked flutter @('build','windows','--release')
$bundle = "build/windows/$Arch/runner/Release"
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products '*' -property installationPath
if (-not $vs) { throw 'Visual Studio C++ installation not found' }
$redist = Get-ChildItem "$vs\VC\Redist\MSVC\*\$Arch\Microsoft.VC*.CRT" -Directory | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $redist) { throw "Missing redistributable app-local $Arch MSVC CRT" }
Copy-Item "$($redist.FullName)\*.dll" $bundle -Force
Copy-Item LICENSE "$bundle/Sirb-LICENSE" -Force
Run-Checked python @('tool/release.py','binary','windows',$Arch,"$bundle/vcruntime140.dll")
New-Item -ItemType Directory -Force dist | Out-Null
Run-Checked python @('tool/release.py','windows','--arch',$Arch,'--bundle',$bundle)
