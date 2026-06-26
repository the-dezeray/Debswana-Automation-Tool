import os
import subprocess
from PIL import Image

def make_ico():
    src = os.path.join("assets", "debswana-mini-logo.png")
    dst = os.path.join("assets", "debswana-mini-logo.ico")
    img = Image.open(src).convert("RGBA")
    img.save(dst, format="ICO", sizes=[(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)])
    return dst

def build():
    app_name = "debsSoft-kit"
    icon = make_ico()

    cmd = [
        "pyinstaller",
        "--noconfirm",
        "--onefile",
        "--windowed",
        f"--name={app_name}",
        f"--icon={icon}",
        "--add-data=assets;assets",
        "--collect-all=customtkinter",
        "main.py"
    ]

    print(f"Running: {' '.join(cmd)}")
    try:
        subprocess.check_call(cmd)
        print(f"\nBuild done! dist/{app_name}.exe")
    except subprocess.CalledProcessError as e:
        print(f"\nBuild failed: {e}")
    except FileNotFoundError:
        print("\nPyInstaller not found. Run: pip install pyinstaller")

if __name__ == "__main__":
    build()
