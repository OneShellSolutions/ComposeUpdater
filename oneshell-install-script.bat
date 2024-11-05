@echo off
setlocal

:: Set the base directory to C:\
set "BASE_DIR=C:\"
set "REPO_URL=https://github.com/Manikanta-Reddy-Pasala/pos-deployment.git"
set "FOLDER_NAME=pos-deployment"  :: Replace with your repository name
set "EXE_NAME=oneshell-print.exe"  :: Replace with the actual filename
set "EXE_URL=https://drive.google.com/file/d/1q-xqNZqoFE_FX-zuo6MkndOh5uhwJIOV/view?usp=sharing"  :: Replace with the URL to download the .exe

:: Navigate to the base directory
cd /d %BASE_DIR%

:: Clone the repository if it doesn't exist, or pull the latest changes
if not exist "%BASE_DIR%%FOLDER_NAME%" (
    echo Cloning the repository...
    git clone %REPO_URL% %FOLDER_NAME%
) else (
    echo Pulling the latest changes...
    cd %FOLDER_NAME%
    git pull
    cd ..
)

:: Navigate to the repository folder in the base directory
cd %BASE_DIR%%FOLDER_NAME%

:: Check if the executable exists in the base directory; if not, download it
if not exist "%EXE_NAME%" (
    echo Downloading the executable...
    powershell -Command "Invoke-WebRequest -Uri %EXE_URL% -OutFile %EXE_NAME%"
)

:: Start Docker Compose and wait for all services to start
echo Starting Docker Compose...
docker-compose up -d

:: Wait until all services are healthy
echo Waiting for services to be healthy...
:WAIT_LOOP
for /f "tokens=*" %%i in ('docker-compose ps -q') do (
    set "CONTAINER=%%i"
    set "STATUS="
    for /f "tokens=*" %%j in ('docker inspect -f "{{.State.Health.Status}}" %CONTAINER%') do set "STATUS=%%j"
    if /i not "%STATUS%"=="healthy" (
        timeout /t 5 >nul
        goto WAIT_LOOP
    )
)

:: Define the path to the executable in the base directory
set "EXE_PATH=%BASE_DIR%%FOLDER_NAME%\%EXE_NAME%"

:: Create a Windows service to run the executable in the background
echo Creating a Windows service...
sc create "MyExecutableService" binPath= "%EXE_PATH%" start= auto
sc description "MyExecutableService" "Service to run MyExecutable in the background continuously"
sc start "MyExecutableService"

:: Script complete
echo All tasks completed.
