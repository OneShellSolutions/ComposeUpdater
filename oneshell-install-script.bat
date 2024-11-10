@echo off
setlocal

:: Set PowerShell Execution Policy for the current session
echo Setting PowerShell Execution Policy for current session...
powershell -Command "Set-ExecutionPolicy RemoteSigned -Scope Process -Force"
if %errorlevel% neq 0 goto :EOF

:: Set base directory and variables
set "BASE_DIR=C:\"
set "REPO_URL=https://github.com/Manikanta-Reddy-Pasala/pos-deployment.git"
set "FOLDER_NAME=pos-deployment"
set "EXE_NAME=oneshell-print.exe"
set "EXE_URL=https://pos-download.oneshell.in/download/flavor/default/1.0.0/windows_32/oneshell-print-util-win.exe"
set "NSSM_URL=https://pos-download.oneshell.in/download/flavor/default/1.1.1/windows_32/nssm.exe"
set "NSSM_PATH=%BASE_DIR%%FOLDER_NAME%\nssm.exe"
set "EXE_PATH=%BASE_DIR%%FOLDER_NAME%\%EXE_NAME%"

:: Navigate to base directory and clone/pull repository
echo Navigating to base directory and setting up repository...
cd /d %BASE_DIR%
if not exist "%BASE_DIR%%FOLDER_NAME%" (
    echo Cloning repository...
    git clone %REPO_URL% %FOLDER_NAME%
) else (
    echo Pulling latest updates from repository...
    cd %FOLDER_NAME%
    git pull
    cd ..
)

:: Download NSSM if not present
if not exist "%NSSM_PATH%" (
    echo Downloading NSSM...
    powershell -Command "Invoke-WebRequest -Uri %NSSM_URL% -OutFile %NSSM_PATH%"
)

:: Download executable if not present
if not exist "%EXE_PATH%" (
    echo Downloading Oneshell executable...
    powershell -Command "Invoke-WebRequest -Uri %EXE_URL% -OutFile %EXE_PATH%"
)

:: Start Docker Compose
echo Starting Docker Compose services...
docker-compose up -d

:: Wait until all services are healthy
echo Waiting for all Docker services to be healthy...
:WAIT_LOOP
set "ALL_HEALTHY=true"
for /f "tokens=*" %%i in ('docker-compose ps -q') do (
    set "STATUS="
    for /f "tokens=*" %%j in ('docker inspect -f "{{.State.Health.Status}}" %%i') do set "STATUS=%%j"
    if /i not "%STATUS%"=="healthy" (
        set "ALL_HEALTHY=false"
        timeout /t 5 >nul
    )
)
if /i "%ALL_HEALTHY%"=="false" goto WAIT_LOOP

:: Remove existing service if it exists
echo Removing existing Oneshell service if present...
%NSSM_PATH% stop "OneShellPrinterUtilService" >nul 2>&1
%NSSM_PATH% remove "OneShellPrinterUtilService" confirm >nul 2>&1

:: Create and configure Windows service with NSSM
echo Creating and configuring Oneshell service with NSSM...
%NSSM_PATH% install "OneShellPrinterUtilService" "%EXE_PATH%"
%NSSM_PATH% set "OneShellPrinterUtilService" Start SERVICE_AUTO_START
%NSSM_PATH% set "OneShellPrinterUtilService" DisplayName "Oneshell Printer Background Service"
%NSSM_PATH% set "OneShellPrinterUtilService" Description "Service to run Oneshell printer in the background"
%NSSM_PATH% set "OneShellPrinterUtilService" AppPriority IDLE_PRIORITY_CLASS
%NSSM_PATH% set "OneShellPrinterUtilService" AppExit Default Restart
%NSSM_PATH% start "OneShellPrinterUtilService"

:: Check if service is running
echo Verifying if Oneshell service is running...
sc query "OneShellPrinterUtilService" | findstr /i "RUNNING" || goto :EOF

:: Script complete, wait before exiting
echo All tasks completed successfully. Script will exit in 10 minutes.
timeout /t 600
