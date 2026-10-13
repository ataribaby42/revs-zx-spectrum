@echo off
rem Revs for the ZX Spectrum 48K: build with z88dk (z88dk-z80asm and
rem z88dk-appmake in PATH).
rem
rem z88dk-z80asm assembles the modules listed in src\revs.lst (the main
rem program, the BASIC loader and the six track modules) and links them:
rem build\revs.bin (the program from LOAD_START), build\revs_loader.bin (the
rem loader's two tape blocks), build\revs_track_<track>.bin (the track
rem files) and build\revs_trackcode_<track>.bin (their track code).
rem z88dk-appmake makes the other tape blocks:
rem   output\revs.tap         the BASIC loader (src\loader.asm), the loading
rem                           screen (src\gfx\loading.scr) and the program
rem   output\revs_tracks.tap  each track file and its track code
rem and build\revs.sna (a snapshot of the program, for the tests).

setlocal
cd /d "%~dp0"

where z88dk-z80asm >nul 2>nul || (echo z88dk-z80asm not found: add the z88dk bin directory to PATH & exit /b 1)
rem appmake finds its snapshot template through ZCCCFG
if not defined ZCCCFG for %%i in (z88dk-appmake.exe) do set "ZCCCFG=%%~dp$PATH:i..\lib\config\"

rem addresses (src\memmap.asm): LOAD_START, the track slot TRACK, TRACKCODE
set LOAD_START=24576
set TRACK=49152
set TRACKCODE=64864
set TRACKS=brandshatch doningtonpark nurburgring oultonpark silverstone snetterton
set SECTIONS=loader
for %%t in (%TRACKS%) do call set "SECTIONS=%%SECTIONS%% track_%%t trackcode_%%t"

if not exist build mkdir build
if not exist output mkdir output

echo Assembling
z88dk-z80asm -b -m -l -mz80 -Isrc -Obuild -orevs.bin @src\revs.lst || goto failed

echo Tapes
z88dk-appmake +zx --noloader --blockname REVSSCREEN --org 16384 -b src\gfx\loading.scr -o build\screen.tap >nul || goto failed
z88dk-appmake +zx --noloader --blockname REVSCODE --org %LOAD_START% -b build\revs.bin --exclude-sections "%SECTIONS%" -o build\code.tap >nul || goto failed
copy /b build\revs_loader.bin + build\screen.tap + build\code.tap output\revs.tap >nul || goto failed
z88dk-appmake +zx --sna --org %LOAD_START% -b build\revs.bin --exclude-sections "%SECTIONS%" -o build\revs.sna >nul || goto failed

call :track brandshatch "BRANDS HATCH" || goto failed
call :track doningtonpark "DONINGTON PARK" || goto failed
call :track nurburgring "NURBURGRING" || goto failed
call :track oultonpark "OULTON PARK" || goto failed
call :track silverstone "SILVERSTONE" || goto failed
call :track snetterton "SNETTERTON" || goto failed
copy /b build\tape_brandshatch.tap + build\tape_doningtonpark.tap + build\tape_nurburgring.tap + build\tape_oultonpark.tap + build\tape_silverstone.tap + build\tape_snetterton.tap output\revs_tracks.tap >nul || goto failed

echo Done: output\revs.tap, output\revs_tracks.tap
exit /b 0

rem :track key "NAME": the track file (for TRACK) and the track code (for
rem TRACKCODE) as two CODE blocks named after the track
:track
z88dk-appmake +zx --noloader --blockname %2 --org %TRACK% -b build\revs_track_%1.bin -o build\track_%1.tap >nul || exit /b 1
z88dk-appmake +zx --noloader --blockname %2 --org %TRACKCODE% -b build\revs_trackcode_%1.bin -o build\trackcode_%1.tap >nul || exit /b 1
copy /b build\track_%1.tap + build\trackcode_%1.tap build\tape_%1.tap >nul || exit /b 1
exit /b 0

:failed
echo Build failed
exit /b 1
