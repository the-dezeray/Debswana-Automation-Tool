import json
import os
import sys
import shutil
import subprocess
from typing import List, Dict, Any

def resource_path(relative_path):
    try:
        base_path = sys._MEIPASS
    except Exception:
        base_path = os.path.abspath(".")
    return os.path.join(base_path, relative_path)

class AppLogic:
    def __init__(self, apps_json_path: str = "apps.json"):
        if getattr(sys, 'frozen', False):
            base_dir = os.path.dirname(sys.executable)
            self.apps_json_path = os.path.join(base_dir, apps_json_path)
        else:
            self.apps_json_path = os.path.abspath(apps_json_path)
        self.apps: List[Dict[str, Any]] = []
        self.load_apps()

    def load_apps(self):
        if not os.path.exists(self.apps_json_path):
            self.apps = []
            return
        try:
            with open(self.apps_json_path, "r", encoding="utf-8") as f:
                self.apps = json.load(f)
        except Exception as e:
            print(f"Error loading apps.json: {e}")
            self.apps = []

    def save_apps(self):
        try:
            with open(self.apps_json_path, "w", encoding="utf-8") as f:
                json.dump(self.apps, f, indent=2)
        except Exception as e:
            print(f"Error saving apps.json: {e}")

    def get_categories(self) -> List[str]:
        return sorted({app["category"] for app in self.apps if "category" in app})

    def is_server_reachable(self, server: str = "\\\\10.50.93.5") -> bool:
        try:
            subprocess.check_output(
                ["net", "view", server],
                stderr=subprocess.STDOUT,
                timeout=4,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            return True
        except Exception:
            return False

    def check_wifi(self) -> Dict[str, Any]:
        try:
            output = subprocess.check_output(
                ["netsh", "wlan", "show", "interfaces"],
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            ssid = None
            for line in output.split("\n"):
                if "SSID" in line and ":" in line and "BSSID" not in line:
                    ssid = line.split(":", 1)[1].strip()
                    break
            if ssid:
                return {"connected": True, "ssid": ssid, "is_debs": "debs" in ssid.lower()}
        except Exception:
            pass
        return {"connected": False, "ssid": None, "is_debs": False}

    def install_app(self, app: Dict[str, Any], status_callback=None):
        name = app.get("name", "Unknown")
        path = app.get("path", "")
        app_type = app.get("type", "exe")
        args = app.get("args", "")
        working_dir = app.get("workingDir", "")
        dest_dir = app.get("destDir", "")
        exe_name = app.get("exeName", "")
        run_as_admin = app.get("runAsAdmin", False)

        def update(msg, color="white"):
            if status_callback:
                status_callback(msg, color)

        try:
            update("Checking network...", "orange")
            if not self.is_server_reachable():
                update("Server unreachable. Check your network connection.", "red")
                return False

            if app_type == "copy-then-run":
                update(f"Copying installation files for {name}...", "orange")
                os.makedirs(dest_dir, exist_ok=True)
                source = path.rstrip("*").rstrip("\\").rstrip("/") if path.endswith("*") else path
                if path.endswith("*"):
                    for item in os.listdir(source):
                        s = os.path.join(source, item)
                        d = os.path.join(dest_dir, item)
                        if os.path.isdir(s):
                            if os.path.exists(d): shutil.rmtree(d)
                            shutil.copytree(s, d)
                        else:
                            shutil.copy2(s, d)
                else:
                    if os.path.isdir(source):
                        shutil.copytree(source, dest_dir, dirs_exist_ok=True)
                    else:
                        shutil.copy2(source, dest_dir)
                path = os.path.join(dest_dir, exe_name)
                working_dir = dest_dir

            update(f"Launching installer: {name}...", "orange")

            if run_as_admin:
                ps_args = f'-FilePath "{path}"'
                if args:
                    ps_args += f' -ArgumentList "{args}"'
                if working_dir:
                    ps_args += f' -WorkingDirectory "{working_dir}"'
                subprocess.check_call(
                    ["powershell", "-Command", f'Start-Process {ps_args} -Verb RunAs -Wait'],
                    creationflags=subprocess.CREATE_NO_WINDOW
                )
            else:
                import shlex
                cmd = [path] + (shlex.split(args) if args else [])
                proc = subprocess.Popen(cmd, cwd=working_dir or None)
                proc.wait()
                if proc.returncode != 0:
                    update(f"{name} - Installer exited with error (code {proc.returncode}).", "red")
                    return False

            update(f"{name} - Installation completed.", "green")
            return True

        except Exception as e:
            if dest_dir and os.path.exists(dest_dir):
                shutil.rmtree(dest_dir, ignore_errors=True)
            update(f"Error installing {name}: {e}", "red")
            return False

    def add_app(self, name, path, args, working_dir, category, app_type="exe"):
        self.apps.append({
            "name": name,
            "path": path,
            "args": args,
            "workingDir": working_dir,
            "category": category,
            "type": app_type,
            "standard": category == "Standard"
        })
        self.save_apps()
