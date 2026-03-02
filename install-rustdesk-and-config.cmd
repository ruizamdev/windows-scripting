@echo off
setlocal

set "BASE_DIR=%~dp0"
set "INSTALLER=%BASE_DIR%instalador-rustdesk.exe"
set "CONFIG_PS1=%BASE_DIR%rd-config.ps1"

echo [1/3] Verificando archivos...
if not exist "%INSTALLER%" (
  echo ERROR: No se encontro el instalador: "%INSTALLER%"
  timeout /t 7 /nobreak >nul
  exit /b 1
)
if not exist "%CONFIG_PS1%" (
  echo ERROR: No se encontro el script: "%CONFIG_PS1%"
  timeout /t 7 /nobreak >nul
  exit /b 1
)

echo [2/3] Ejecutando instalador RustDesk...
REM Ajusta parametros silenciosos segun tu instalador (ej: --silent-install, /S, /quiet).
start /wait "" "%INSTALLER%"
if errorlevel 1 (
  echo ERROR: El instalador termino con codigo %errorlevel%.
  timeout /t 7 /nobreak >nul
  exit /b %errorlevel%
)

echo [3/3] Aplicando configuracion post-instalacion...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CONFIG_PS1%"
if errorlevel 1 (
  echo ERROR: Fallo la configuracion post-instalacion.
  timeout /t 7 /nobreak >nul
  exit /b %errorlevel%
)

echo EXITO: Instalacion y configuracion completadas.
timeout /t 7 /nobreak >nul
exit /b 0
