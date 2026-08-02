@echo off
rem Sated deploy: one-way copy repo -> AddOns\Sated. Never edit in the AddOns dir.
set "TARGET=E:\World of Warcraft\_retail_\Interface\AddOns\Sated"

robocopy "%~dp0." "%TARGET%" Sated.toc config.lua core.lua announce.lua /NJH /NJS /NDL

if %ERRORLEVEL% GEQ 8 (
  echo DEPLOY FAILED - robocopy exit code %ERRORLEVEL%
  exit /b 1
)
echo Deployed Sated to %TARGET%
exit /b 0
