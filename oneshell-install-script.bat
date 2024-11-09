@echo off
setlocal

:: Set PowerShell Execution Policy for the current session
echo Setting PowerShell Execution Policy to RemoteSigned for this process...
powershell -Command "Set-ExecutionPolicy RemoteSigned -Scope Process -Force"
if %errorlevel% neq 0 (
    echo Error: Failed to set execution policy. Exiting.
    pause
    goto :EOF
)

:: Set the base directory and other variables
set "BASE_DIR=C:\"
set "REPO_URL=https://github.com/Manikanta-Reddy-Pasala/pos-deployment.git"
set "FOLDER_NAME=pos-deployment"
set "EXE_NAME=oneshell-print.exe"
set "EXE_URL=https://pos-download.oneshell.in/download/flavor/default/1.0.0/windows_32/oneshell-printer-util.exe"
set "NSSM_URL=https://pos-download.oneshell.in/download/flavor/default/1.1.1/windows_32/nssm.exe"

:: Define the path to the NSSM executable and the target executable
set "NSSM_PATH=%BASE_DIR%%FOLDER_NAME%\nssm.exe"
set "EXE_PATH=%BASE_DIR%%FOLDER_NAME%\%EXE_NAME%"

:: Log the start of the script
echo Starting script...

:: Navigate to the base directory
cd /d %BASE_DIR%
if %errorlevel% neq 0 (
    echo Error: Failed to navigate to %BASE_DIR%.
    pause
    goto :EOF
)

:: Clone the repository if it doesn't exist; otherwise, pull the latest changes
if not exist "%BASE_DIR%%FOLDER_NAME%" (
    echo Cloning the repository from %REPO_URL%...
    git clone %REPO_URL% %FOLDER_NAME%
    if %errorlevel% neq 0 (
        echo Error: Failed to clone the repository.
        pause
        goto :EOF
    )
) else (
    echo Pulling the latest changes for %FOLDER_NAME%...
    cd %FOLDER_NAME%
    git pull
    if %errorlevel% neq 0 (
        echo Error: Failed to pull latest changes.
        pause
        goto :EOF
    )
    cd ..
)

:: Navigate to the repository folder
cd %BASE_DIR%%FOLDER_NAME%
if %errorlevel% neq 0 (
    echo Error: Failed to navigate to the repository folder.
    pause
    goto :EOF
)

:: Download NSSM if it doesn't exist
if not exist "%NSSM_PATH%" (
    echo Downloading NSSM from %NSSM_URL%...
    powershell -Command "Invoke-WebRequest -Uri %NSSM_URL% -OutFile %NSSM_PATH%"
    if %errorlevel% neq 0 (
        echo Error: Failed to download NSSM.
        pause
        goto :EOF
    )
)

:: Check if the executable exists; if not, download it
if not exist "%EXE_NAME%" (
    echo Downloading the executable from %EXE_URL%...
    powershell -Command "Invoke-WebRequest -Uri %EXE_URL% -OutFile %EXE_NAME%"
    if %errorlevel% neq 0 (
        echo Error: Failed to download the executable.
        pause
        goto :EOF
    )
)
:: Start Docker Compose and wait for all services to start
echo Starting Docker Compose...
docker-compose up -d
if %errorlevel% neq 0 (
    echo Error: Failed to start Docker Compose.
    pause
    goto :EOF
)

:: Wait until all services are healthy
echo Waiting for services to be healthy...
:WAIT_LOOP
set "ALL_HEALTHY=true"
for /f "tokens=*" %%i in ('docker-compose ps -q') do (
    set "CONTAINER=%%i"
    for /f %%j in ('docker inspect -f "{{.State.Health.Status}}" %%i') do set "STATUS=%%j"
    if /i not "%STATUS%"=="healthy" (
        echo Service %%i is not healthy yet...
        set "ALL_HEALTHY=false"
        timeout /t 5 >nul
    )
)
if /i "%ALL_HEALTHY%"=="false" goto WAIT_LOOP

echo All services are healthy

:: Remove existing service if it exists
%NSSM_PATH% stop "OneShellPrinterUtilService" >nul 2>&1
%NSSM_PATH% remove "OneShellPrinterUtilService" confirm >nul 2>&1

:: Create a Windows service to run the executable in the background using NSSM
echo Creating a Windows service with NSSM...
%NSSM_PATH% install "OneShellPrinterUtilService" "%EXE_PATH%"
%NSSM_PATH% set "OneShellPrinterUtilService" Start SERVICE_AUTO_START
%NSSM_PATH% set "OneShellPrinterUtilService" DisplayName "Oneshell printer Background Service"
%NSSM_PATH% set "OneShellPrinterUtilService" Description "Service to run oneshell printer continuously in the background"

:: Set the correct process priority
%NSSM_PATH% set "OneShellPrinterUtilService" AppPriority IDLE_PRIORITY_CLASS
if %errorlevel% neq 0 (
    echo Error: Failed to set process priority.
    pause
    goto :EOF
)

%NSSM_PATH% set "OneShellPrinterUtilService" AppExit Default Restart

:: Start the service and check the status
%NSSM_PATH% start "OneShellPrinterUtilService"
if %errorlevel% neq 0 (
    echo Error: Failed to start Windows service.
    pause
    goto :EOF
)

:: Check if the service is running
sc query "OneShellPrinterUtilService" | findstr /i "RUNNING"
if %errorlevel% neq 0 (
    echo Error: Service did not start successfully.
    pause
    goto :EOF
)

:: Script complete
echo All tasks completed successfully.
echo The terminal will remain open for 10 minutes. Press Ctrl+C to stop the script manually.
timeout /t 600
