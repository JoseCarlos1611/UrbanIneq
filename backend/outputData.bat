@echo off
setlocal enabledelayedexpansion

set "folder=%ProgramFiles%\R"
set "firstFolder="

rem Iterate through the subdirectories
for /d %%D in ("%folder%\*") do (
    rem Check if firstFolder is already set
    if not defined firstFolder (
        set "firstFolder=%%~nxD"
    )
)

rem Output the first folder found
if defined firstFolder (
    set "Rscriptexe=%folder%\!firstFolder!\bin\Rscript.exe"
    set "pppath=%~dp0outputData.R"
    "!Rscriptexe!" --encoding=UTF-8 "!pppath!"
    pause
) else (
    echo "I couldn't find an R installation in %folder%, please check whether R (64-bit) is installed in your system. Otherwise, you can run the "outputData.R" script inside R itself."
    pause
)

endlocal
