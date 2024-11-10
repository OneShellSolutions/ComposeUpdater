@echo off
setlocal

:: Check if Git is installed
echo Checking for Git installation...
git --version >nul 2>&1
if %errorlevel% neq 0 (
    echo Git is not installed. Downloading and installing Git...
    set "GIT_URL=https://github.com/git-for-windows/git/releases/download/v2.42.0.windows.1/Git-2.42.0-64-bit.exe"
    set "GIT_INSTALLER=%temp%\GitInstaller.exe"
    powershell -Command "Invoke-WebRequest -Uri %GIT_URL% -OutFile %GIT_INSTALLER%"
    start /wait "" "%GIT_INSTALLER%" /VERYSILENT /NORESTART
    del "%GIT_INSTALLER%"
)

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
set "SERVICE_NAME=OneShellPrinterUtilService"

:: Stop and remove the service if it exists
echo Checking for existing Oneshell service...
sc query "%SERVICE_NAME%" | findstr /i "RUNNING" >nul 2>&1
if %errorlevel% equ 0 (
    echo Stopping existing service...
    %NSSM_PATH% stop "%SERVICE_NAME%" >nul 2>&1
    %NSSM_PATH% remove "%SERVICE_NAME%" confirm >nul 2>&1
    echo Service stopped and removed.
)

:: Navigate to base directory and clean up any existing repository folder
echo Preparing repository folder...
cd /d %BASE_DIR%
if exist "%BASE_DIR%%FOLDER_NAME%" (
    echo Deleting existing pos-deployment directory...
    rmdir /s /q "%BASE_DIR%%FOLDER_NAME%"
    if %errorlevel% neq 0 (
        echo Error: Failed to delete the pos-deployment directory.
        pause
        goto :EOF
    )
)

:: Clone the repository
echo Cloning repository...
git clone %REPO_URL% %FOLDER_NAME%
if %errorlevel% neq 0 (
    echo Error: Failed to clone the repository.
    pause
    goto :EOF
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

:: Create and configure Windows service with NSSM
echo Creating and configuring Oneshell service with NSSM...
%NSSM_PATH% install "%SERVICE_NAME%" "%EXE_PATH%"
%NSSM_PATH% set "%SERVICE_NAME%" Start SERVICE_AUTO_START
%NSSM_PATH% set "%SERVICE_NAME%" DisplayName "Oneshell Printer Background Service"
%NSSM_PATH% set "%SERVICE_NAME%" Description "Service to run Oneshell printer in the background"
%NSSM_PATH% set "%SERVICE_NAME%" AppPriority IDLE_PRIORITY_CLASS
%NSSM_PATH% set "%SERVICE_NAME%" AppExit Default Restart
%NSSM_PATH% start "%SERVICE_NAME%"

:: Check if service is running
echo Verifying if Oneshell service is running...
sc query "%SERVICE_NAME%" | findstr /i "RUNNING" || goto :EOF

:: Script complete, wait before exiting
echo All tasks completed successfully. Script will exit in 10 minutes.
timeout /t 600
