@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"
"D:\Programs\odin\odin.exe" build ..\ffi -build:shared -out:..\mdz.dll -o:speed -no-bounds-check -disable-assert
echo Built mdz.dll
