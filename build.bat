@echo off
echo Preparing to build Desiree Software Center EXE...
echo.

:: Check for Python
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo Error: Python is not installed or not in PATH.
    pause
    exit /b 1
)

:: Install requirements
echo Installing dependencies...
pip install customtkinter Pillow pyinstaller

:: Run build script
echo.
echo Running build process...
python build_exe.py

echo.
if %errorlevel% eq 0 (
    echo Done! Check the 'dist' folder for DesireeSoftwareCenter.exe
) else (
    echo Build failed.
)
pause
