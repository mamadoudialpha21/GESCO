# GESCO - verification et construction de l'installateur Windows sur ce PC.
# Fichier volontairement en ASCII (PowerShell 5.1 lit mal l'UTF-8 sans BOM).
#
# Utilisation (PowerShell, depuis n'importe quel dossier) :
#   .\scripts\build_windows.ps1                 # tests du moteur + compilation + installateur
#   .\scripts\build_windows.ps1 -ToutesLesTests # lance aussi les tests de la base (voir README)
#
# Prerequis : Flutter (avec Windows desktop) et Visual Studio Build Tools
# ("Developpement Desktop en C++"). Inno Setup 6 pour creer le .exe d'installation.

param(
  [switch]$ToutesLesTests
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

function Executer {
  param([string]$Commande, [string[]]$Arguments)
  Write-Host ">> $Commande $($Arguments -join ' ')" -ForegroundColor Cyan
  & $Commande @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "ECHEC : $Commande $($Arguments -join ' ') (code $LASTEXITCODE)"
  }
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw "Flutter est introuvable. Installez Flutter et ajoutez-le au PATH (voir README.md)."
}

if (-not (Test-Path 'windows')) {
  Executer flutter @('create', '--platforms=windows', '--project-name', 'gesco', '--org', 'gn.gesco', '.')
}

Executer flutter @('pub', 'get')

# L'analyse signale les avertissements de style sans bloquer : ce sont les
# tests et la compilation qui decident du succes.
Write-Host ">> flutter analyze --no-fatal-infos (informatif)" -ForegroundColor Cyan
& flutter analyze --no-fatal-infos
if ($LASTEXITCODE -ne 0) {
  Write-Warning "L'analyse a signale des avertissements (non bloquant, voir ci-dessus)."
}

# Titre de la fenetre de l'application.
$mainCpp = 'windows\runner\main.cpp'
if (Test-Path $mainCpp) {
  $texte = Get-Content $mainCpp -Raw
  $texte = $texte.Replace('L"gesco"', 'L"GESCO - Gestion des notes scolaires"')
  Set-Content -Path $mainCpp -Value $texte -NoNewline -Encoding UTF8
}

if ($ToutesLesTests) {
  Executer flutter @('test', '--reporter', 'expanded')
} else {
  Executer flutter @('test', 'test/domain', '--reporter', 'expanded')
}

Executer flutter @('build', 'windows', '--release')

$exe = Get-ChildItem -Path 'build\windows' -Recurse -Filter 'gesco.exe' | Select-Object -First 1
if (-not $exe) { throw "gesco.exe introuvable apres la compilation." }
$dossier = $exe.DirectoryName
Write-Host "Application compilee dans : $dossier" -ForegroundColor Green

# DLL Visual C++ : permet de lancer l'application sur un PC qui ne les a pas.
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  $source = Join-Path $env:SystemRoot "System32\$dll"
  if (Test-Path $source) {
    Copy-Item $source $dossier -Force
  } else {
    Write-Warning "$dll introuvable dans System32 (non copiee)."
  }
}

$iscc = $null
foreach ($candidat in @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe")) {
  if (Test-Path $candidat) { $iscc = $candidat; break }
}

if ($iscc) {
  Executer $iscc @("/DBuildDir=$dossier", 'installer\gesco.iss')
  Write-Host "Installateur cree dans : installer\Output" -ForegroundColor Green
} else {
  Write-Warning "Inno Setup 6 n'est pas installe : l'installateur n'a pas ete cree."
  Write-Warning "Installez-le (https://jrsoftware.org/isdl.php) puis relancez ce script,"
  Write-Warning "ou lancez directement l'application : $($exe.FullName)"
}
