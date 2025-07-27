REM @echo off
REM setlocal enabledelayedexpansion

REM set "dossier_source=A:\RetroBat6\emulationstation\.emulationstation\themes\_BobMedia\_SystemMedia\_charasyst\Hmaxchar"
REM set "fichier_source=A:\RetroBat6\emulationstation\.emulationstation\themes\_BobMedia\_SystemMedia\VideoSyst\Hyperspin\_Hsystheme.xml"
REM set "dossier_destination=A:\RetroBat6\emulationstation\.emulationstation\themes\_BobMedia\_SystemMedia\VideoSyst\Hyperspin"

REM if not exist "%fichier_source%" (
    REM echo Le fichier source "%fichier_source%" n'a pas été trouvé.
    REM exit /b
REM )

REM for %%i in ("%dossier_source%\*") do (
    REM set "nom_fichier=%%~ni"
    REM copy "%fichier_source%" "%dossier_destination%\!nom_fichier!.xml"
    REM echo Fichier XML dupliqué pour le fichier !nom_fichier!
REM )

REM echo Duplication terminée.
REM pause

@echo off
setlocal enabledelayedexpansion

set "dossier_source=.\"
set "dossier_destination=.\"
set "fichier_source=.\_Hsystheme.xml"
set "liste_fichiers=_dossiers.txt"

if not exist "%fichier_source%" (
    echo Le fichier source "%fichier_source%" n'a pas été trouvé.
    exit /b
)

if not exist "%liste_fichiers%" (
    echo Le fichier de liste "%liste_fichiers%" n'a pas été trouvé.
    exit /b
)

for /F %%a in (%liste_fichiers%) do (
    set "nom_fichier=%%a"
    copy "%fichier_source%" "%dossier_destination%\!nom_fichier!.xml"
    echo Fichier XML dupliqué pour le fichier !nom_fichier!
)

echo Duplication terminée.
pause