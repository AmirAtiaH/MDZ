@echo off
set "VS_PATH=%~1"
if "%VS_PATH%"=="" set "VS_PATH=C:\Program Files\Microsoft Visual Studio\18\Community"
if exist "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat" (
    call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat"
) else (
    echo Warning: vcvars64.bat not found at expected path.
    echo Set VS_PATH environment variable or pass as first argument.
)

set "ODIN=%ODIN%"
if "%ODIN%"=="" set "ODIN=odin"
%ODIN% build ..\ffi -build-mode:dll -out:..\mdz.dll -o:aggressive -no-bounds-check -disable-assert
echo Built mdz.dll
