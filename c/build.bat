@echo off
cl /c example.c /I.
link example.obj ..\mdz.lib /OUT:mdz_c.exe
echo Built mdz_c.exe
