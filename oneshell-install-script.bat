@echo off
setlocal enableextensions enabledelayedexpansion

rem ======================
rem Configurable Variables
rem ======================
set "BASE_DIR=C:\"
set "DOWNLOAD_URL=https://codeload.github.com/Manikanta-Reddy-Pasala/pos-deployment/zip/refs/heads/master"
set "FOLDER_NAME=pos-deployment"
set "EXE_NAME=oneshell-print-util-win.exe"
set "NSSM_NAME=nssm.exe"
set "SERVICE_NAME=OneShellPrinterUtilService"

rem ======================
rem Derived Paths
rem ======================
set "ZIP_PATH=%BASE_DIR%pos-deployment.zip"
set "EXTRACTED_FOLDER_PATH=%BASE_DIR%%FOLDER_NAME%-master"
set "NSSM_PATH=%EXTRACTED_FOLDER_PATH%\%NSSM_NAME%"
set "EXE_PATH=%EXTRACTED_FOLDER_PATH%\%EXE_NAME%"

rem ======================
rem Helper Functions
rem ======================
:cleanup
    echo Cleaning up...
    if exist "%EXTRACTED_FOLDER_PATH%" (
        rmdir /s /q "%EXTRACTED_FOLDER_PATH%"
    )
    if exist "%ZIP_PATH%" (
        del "%ZIP_PATH%"
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
rem Download and Extract Files
rem ======================
echo Downloading deployment files...
powershell -Command "Invoke-WebRequest -Uri %DOWNLOAD_URL% -OutFile %ZIP_PATH%"
if %errorlevel% neq 0 (
    echo Error: Failed to download deployment files.
    goto :cleanup
)

rem Extracting downloaded files...
powershell -Command "Expand-Archive -Path %ZIP_PATH% -DestinationPath %BASE_DIR% -Force"
if %errorlevel% neq 0 (
    echo Error: Failed to extract deployment files.
    goto :cleanup
)

rem ======================
rem Start Docker Compose
rem ======================
echo Starting Docker Compose services...
docker-compose -f "%EXTRACTED_FOLDER_PATH%\docker-compose.yml" up -d
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
for /f "tokens=*" %%i in ('docker-compose -f "%EXTRACTED_FOLDER_PATH%\docker-compose.yml" ps -q') do (
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
