@echo off
setlocal
rem Sated is exposed to WoW through a junction; repo edits are already live.
set "TARGET=C:/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns/Sated"

powershell -NoProfile -Command "$expected=(Resolve-Path -LiteralPath '%~dp0.').Path; $link=Get-Item -LiteralPath '%TARGET%' -Force -ErrorAction Stop; if ($link.LinkType -ne 'Junction' -or $link.Target -notcontains $expected) { Write-Error ('Expected junction {0} to target {1}' -f '%TARGET%', $expected); exit 1 }; Write-Host ('Sated junction verified: {0} -> {1}' -f '%TARGET%', $expected)"
exit /b %ERRORLEVEL%
