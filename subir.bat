@echo off
setlocal enabledelayedexpansion
color 0b
title REPARAR Y SUBIR A GITHUB

echo ==========================================
echo    ^> REPARACION LIMPIA // GITHUB
echo ==========================================
echo.

:: 1. Eliminar la carpeta .git danada por completo
echo [+] Limpiando referencias corruptas de Git...
if exist ".git" (
    attrib -h -r -s .git /s /d >nul 2>&1
    rmdir /s /q .git
)

:: 2. Inicializar Git totalmente limpio
echo [+] Creando repositorio local nuevo...
git init
git branch -M main

:: 3. Configurar tu repositorio remoto
echo [+] Conectando con GitHub...
git remote add origin https://github.com/mariaelenabernia3-jpg/NullRoute.git

:: 4. Anadir todos tus archivos
echo [+] Preparando archivos locales...
git add -A

:: 5. Crear el commit
set /p "msg=Escribe mensaje (Enter para automatico): "
if "!msg!"=="" set "msg=Actualizacion v7 - %date% %time%"

echo [+] Creando commit...
git commit -m "!msg!"

:: 6. Subir forzando el reemplazo del main danado
echo.
echo [+] Subiendo a GitHub...
git push -u origin main --force

echo.
if %errorlevel% equ 0 (
    color 0a
    echo ==========================================
    echo [OK] Repositorio reparado y subido con exito.
    echo ==========================================
) else (
    color 0c
    echo ==========================================
    echo [ERROR] No se pudo subir. 
    echo Si te pide credenciales, usa tu Token de GitHub.
    echo ==========================================
)

pause