# Test de demarrage de GESCO sur Windows.
# Lance gesco.exe, verifie qu'il reste ouvert, puis controle la base creee.
# (Fichier volontairement sans accents : lisible par toutes les versions de PowerShell.)
#
# Usage : ./scripts/test_demarrage_windows.ps1 -Dossier <dossier contenant gesco.exe>
param(
    [Parameter(Mandatory = $true)][string]$Dossier
)

$ErrorActionPreference = 'Stop'
$marque = 'SMOKE_TEST:'

$exe = Join-Path $Dossier 'gesco.exe'
if (-not (Test-Path $exe)) { throw "gesco.exe introuvable : $exe" }

# Base neuve : on retire toute base laissee par une execution precedente.
Get-ChildItem -Path $env:APPDATA -Recurse -Filter gesco.db -ErrorAction SilentlyContinue |
    Remove-Item -Force

$p = Start-Process -FilePath $exe -PassThru
Start-Sleep -Seconds 12
$p.Refresh()

if ($p.HasExited) {
    "$marque ECHEC - l'application s'est arretee (code de sortie $($p.ExitCode))"
    exit 1
}
"$marque l'application tourne apres 12 secondes (PID $($p.Id))"
"$marque titre de la fenetre = '$($p.MainWindowTitle)' | repond = $($p.Responding)"

$db = Get-ChildItem -Path $env:APPDATA -Recurse -Filter gesco.db -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $db) {
    "$marque ECHEC - la base gesco.db n'a pas ete creee"
    Stop-Process -Id $p.Id -Force
    exit 1
}
"$marque base creee : $($db.FullName) ($($db.Length) octets)"

$controle = @'
import pathlib, sqlite3, sys
uri = pathlib.Path(sys.argv[1]).as_uri() + '?mode=ro'
c = sqlite3.connect(uri, uri=True)
tables = [r[0] for r in c.execute("select name from sqlite_master where type='table' and name not like 'sqlite_%' order by name")]
triggers = [r[0] for r in c.execute("select name from sqlite_master where type='trigger'")]
integrite = c.execute('pragma integrity_check').fetchone()[0]
print('SMOKE_TEST: user_version =', c.execute('pragma user_version').fetchone()[0])
print('SMOKE_TEST: tables (%d) = %s' % (len(tables), ', '.join(tables)))
print('SMOKE_TEST: triggers = %d | inscription_classe_verrouillee = %s' % (len(triggers), 'inscription_classe_verrouillee' in triggers))
print('SMOKE_TEST: integrity_check =', integrite)
attendues = {'etablissement', 'parametre', 'annee_scolaire', 'config_resultats', 'classe', 'matiere_classe', 'eleve', 'inscription', 'note'}
manquantes = sorted(attendues - set(tables))
if manquantes or integrite != 'ok' or 'inscription_classe_verrouillee' not in triggers:
    print('SMOKE_TEST: ECHEC - schema incomplet ou base abimee, manquantes =', manquantes)
    sys.exit(1)
'@
$fichierPython = Join-Path $env:RUNNER_TEMP 'controle_base.py'
Set-Content -Path $fichierPython -Value $controle -Encoding ascii
python $fichierPython $db.FullName
$codePython = $LASTEXITCODE

Stop-Process -Id $p.Id -Force

if ($codePython -ne 0) {
    "$marque ECHEC - controle de la base"
    exit 1
}
"$marque OK - l'application demarre, la base est creee avec le schema complet"
exit 0
