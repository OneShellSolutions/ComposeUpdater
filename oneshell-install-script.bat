@echo off
setlocal enableextensions enabledelayedexpansion

rem ======================
rem Configurable Variables
rem ======================
set "BASE_DIR=C:\"
set "REPO_URL=https://github.com/Manikanta-Reddy-Pasala/pos-deployment.git"
set "FOLDER_NAME=pos-deployment"
set "EXE_NAME=oneshell-print.exe"
set "EXE_URL=https://pos-download.oneshell.in/download/flavor/default/1.0.0/windows_32/oneshell-print-util-win.exe"
set "NSSM_URL=https://pos-download.oneshell.in/download/flavor/default/1.1.1/windows_32/nssm.exe"
set "SERVICE_NAME=OneShellPrinterUtilService"

rem ======================
rem Derived Paths
rem ======================
set "NSSM_PATH=%BASE_DIR%%FOLDER_NAME%\nssm.exe"
set "EXE_PATH=%BASE_DIR%%FOLDER_NAME%\%EXE_NAME%"

rem ======================
rem Helper Functions
rem ======================
:cleanup
    echo Cleaning up...
    if exist "%BASE_DIR%%FOLDER_NAME%" (
        rmdir /s /q "%BASE_DIR%%FOLDER_NAME%"
    )
    exit /b 1

goto :main

:main
rem ======================
rem Set PowerShell Execution Policy for the current session
rem ======================
echo Setting PowerShell Execution Policy for current session...
powershell -Command "Set-ExecutionPolicy RemoteSigned -Scope Process -Force"
if %errorlevel% neq 0 (
    echo Error: Failed to set PowerShell execution policy.
    goto :cleanup
)

rem ======================
rem Stop and remove existing service
rem ======================
echo Checking for existing Oneshell service...
sc query "%SERVICE_NAME%" | findstr /i "RUNNING" >nul 2>&1
if %errorlevel% equ 0 (
    echo Stopping existing service...
    %NSSM_PATH% stop "%SERVICE_NAME%" >nul 2>&1
    %NSSM_PATH% remove "%SERVICE_NAME%" confirm >nul 2>&1
    if %errorlevel% neq 0 (
        echo Error: Failed to stop and remove existing service.
        goto :cleanup
    )
    echo Service stopped and removed.
)

rem ======================
rem Prepare repository folder
rem ======================
echo Preparing repository folder...
cd /d %BASE_DIR%
if exist "%BASE_DIR%%FOLDER_NAME%" (
    echo Deleting existing pos-deployment directory...
    rmdir /s /q "%BASE_DIR%%FOLDER_NAME%"
    if %errorlevel% neq 0 (
        echo Error: Failed to delete the pos-deployment directory.
        goto :cleanup
    )
)

rem ======================
rem Clone the repository
rem ======================
echo Cloning repository...
git clone %REPO_URL% %FOLDER_NAME%
if %errorlevel% neq 0 (
    echo Error: Failed to clone the repository.
    goto :cleanup
)

rem ======================
rem Download NSSM if not present
rem ======================
if not exist "%NSSM_PATH%" (
    echo Downloading NSSM...
    powershell -Command "Invoke-WebRequest -Uri %NSSM_URL% -OutFile %NSSM_PATH%"
    if %errorlevel% neq 0 (
        echo Error: Failed to download NSSM.
        goto :cleanup
    )
)

rem ======================
rem Download executable if not present
rem ======================
if not exist "%EXE_PATH%" (
    echo Downloading Oneshell executable...
    powershell -Command "Invoke-WebRequest -Uri %EXE_URL% -OutFile %EXE_PATH%"
    if %errorlevel% neq 0 (
        echo Error: Failed to download Oneshell executable.
        goto :cleanup
    )
)

rem ======================
rem Start Docker Compose
rem ======================
echo Starting Docker Compose services...
docker-compose up -d
if %errorlevel% neq 0 (
    echo Error: Failed to start Docker Compose services.
    goto :cleanup
)

rem ======================
rem Wait for all Docker services to be healthy
rem ======================
echo Waiting for all Docker services to be healthy...
:WAIT_LOOP
set "ALL_HEALTHY=true"
for /f "tokens=*" %%i in ('docker-compose ps -q') do (
    set "STATUS="
    for /f "tokens=*" %%j in ('docker inspect -f "{{.State.Health.Status}}" %%i') do (
        set "STATUS=%%j"
        if /i "!STATUS!" NEQ "healthy" (
            set "ALL_HEALTHY=false"
        )
    )
)
if /i "!ALL_HEALTHY!"=="false" (
    timeout /t 5 >nul
    goto WAIT_LOOP
)

rem ======================
rem Create and configure Windows service with NSSM
rem ======================
echo Creating and configuring Oneshell service with NSSM...
%NSSM_PATH% install "%SERVICE_NAME%" "%EXE_PATH%"
if %errorlevel% neq 0 (
    echo Error: Failed to create service.
    goto :cleanup
)
%NSSM_PATH% set "%SERVICE_NAME%" Start SERVICE_AUTO_START
%NSSM_PATH% set "%SERVICE_NAME%" DisplayName "Oneshell Printer Background Service"
%NSSM_PATH% set "%SERVICE_NAME%" Description "Service to run Oneshell printer in the background"
%NSSM_PATH% set "%SERVICE_NAME%" AppPriority IDLE_PRIORITY_CLASS
%NSSM_PATH% set "%SERVICE_NAME%" AppExit Default Restart
%NSSM_PATH% start "%SERVICE_NAME%"
if %errorlevel% neq 0 (
    echo Error: Failed to start the service.
    goto :cleanup
)

rem ======================
rem Verify if service is running
rem ======================
echo Verifying if Oneshell service is running...
sc query "%SERVICE_NAME%" | findstr /i "RUNNING" >nul 2>&1
if %errorlevel% neq 0 (
    echo Error: Service is not running.
    goto :cleanup
)

echo All tasks completed successfully. Script will exit in 10 minutes.
timeout /t 600
exit /b 0
