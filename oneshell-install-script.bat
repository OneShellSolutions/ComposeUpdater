@echo off
setlocal

:: Set PowerShell Execution Policy for the current session
echo Setting PowerShell Execution Policy to RemoteSigned for this process...
powershell -Command "Set-ExecutionPolicy RemoteSigned -Scope Process -Force"
if %errorlevel% neq 0 (
    echo Error: Failed to set execution policy. Exiting.
    exit /b 1
)

:: Set the base directory and other variables
set "BASE_DIR=C:\"
set "REPO_URL=https://github.com/Manikanta-Reddy-Pasala/pos-deployment.git"
set "FOLDER_NAME=pos-deployment"
set "EXE_NAME=oneshell-print.exe"
set "EXE_URL=https://pos-download.oneshell.in/download/flavor/default/1.0.0/windows_32/oneshell-printer-util.exe"

:: Log the start of the script
echo Starting script...

:: Navigate to the base directory
cd /d %BASE_DIR%
if %errorlevel% neq 0 (
    echo Error: Failed to navigate to %BASE_DIR%.
    exit /b 1
)

:: Clone the repository if it doesn't exist; otherwise, pull the latest changes
if not exist "%BASE_DIR%%FOLDER_NAME%" (
    echo Cloning the repository from %REPO_URL%...
    git clone %REPO_URL% %FOLDER_NAME%
    if %errorlevel% neq 0 (
        echo Error: Failed to clone the repository.
        exit /b 1
    )
) else (
    echo Pulling the latest changes for %FOLDER_NAME%...
    cd %FOLDER_NAME%
    git pull
    if %errorlevel% neq 0 (
        echo Error: Failed to pull latest changes.
        exit /b 1
    )
    cd ..
)

:: Navigate to the repository folder
cd %BASE_DIR%%FOLDER_NAME%
if %errorlevel% neq 0 (
    echo Error: Failed to navigate to the repository folder.
    exit /b 1
)

:: Check if the executable exists; if not, download it
if not exist "%EXE_NAME%" (
    echo Downloading the executable from %EXE_URL%...
    powershell -Command "Invoke-WebRequest -Uri %EXE_URL% -OutFile %EXE_NAME%"
    if %errorlevel% neq 0 (
        echo Error: Failed to download the executable.
        exit /b 1
    )
)

:: Start Docker Compose and wait for all services to start
echo Starting Docker Compose...
docker-compose up -d
if %errorlevel% neq 0 (
    echo Error: Failed to start Docker Compose.
    exit /b 1
)

:: Wait until all services are healthy
echo Waiting for services to be healthy...
:WAIT_LOOP
set "ALL_HEALTHY=true"
for /f "tokens=*" %%i in ('docker-compose ps -q') do (
    set "CONTAINER=%%i"
    set "STATUS="
    for /f "tokens=*" %%j in ('docker inspect -f "{{.State.Health.Status}}" %CONTAINER%') do set "STATUS=%%j"
    if /i not "%STATUS%"=="healthy" (
        echo Service %%i is not healthy yet...
        set "ALL_HEALTHY=false"
        timeout /t 5 >nul
    )
)
if /i "%ALL_HEALTHY%"=="false" goto WAIT_LOOP

echo All services are healthy.

:: Define the path to the executable
set "EXE_PATH=%BASE_DIR%%FOLDER_NAME%\%EXE_NAME%"

:: Create a Windows service to run the executable in the background
echo Creating a Windows service...
sc create "MyExecutableService" binPath="%EXE_PATH%" start=auto
if %errorlevel% neq 0 (
    echo Error: Failed to create Windows service.
    exit /b 1
)
sc description "MyExecutableService" "Service to run MyExecutable in the background continuously"
sc start "MyExecutableService"
if %errorlevel% neq 0 (
    echo Error: Failed to start Windows service.
    exit /b 1
)

:: Script complete
echo All tasks completed successfully.
exit /b 0
