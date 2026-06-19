import os
import subprocess
import sys

def build():
    # Application name
    app_name = "DesireeSoftwareCenter"
    
    # Files to include
    # Format: "source;destination" for Windows (PyInstaller uses ; as separator on Windows)
    # But since we're writing the script, we'll let PyInstaller handle it or use the platform separator
    sep = os.pathsep
    
    # CustomTkinter usually needs its data files bundled
    # We'll use the --collect-all flag which is simpler in newer PyInstaller versions
    
    cmd = [
        "pyinstaller",
        "--noconfirm",
        "--onefile",
        "--windowed",
        f"--name={app_name}",
        "--icon=image.png",  # Set application icon
        "--add-data=image.png:.",
        "--add-data=assets;assets",  # Include all icon assets
        "--collect-all=customtkinter",
        "main.py"
    ]
    
    print(f"Running command: {' '.join(cmd)}")
    
    try:
        subprocess.check_call(cmd)
        print("\nBuild completed successfully!")
        print(f"The executable can be found in the 'dist' folder as {app_name}.exe")
    except subprocess.CalledProcessError as e:
        print(f"\nBuild failed with error: {e}")
    except FileNotFoundError:
        print("\nError: PyInstaller not found. Please install it with 'pip install pyinstaller'.")

if __name__ == "__main__":
    build()
