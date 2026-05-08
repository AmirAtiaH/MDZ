@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"
"D:\Programs\odin\odin.exe" build . -o:speed -microarch:native -no-bounds-check -disable-assert -lto:thin
