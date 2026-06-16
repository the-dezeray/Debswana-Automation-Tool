import json
import os
import sys
import shutil
import subprocess
import threading
from typing import List, Dict, Any, Optional

def resource_path(relative_path):
    """ Get absolute path to resource, works for dev and for PyInstaller """
    try:
        # PyInstaller creates a temp folder and stores path in _MEIPASS
        base_path = sys._MEIPASS
    except Exception:
        base_path = os.path.abspath(".")

    return os.path.join(base_path, relative_path)

class AppLogic:
    def __init__(self, apps_json_path: str = "apps.json"):
        # For apps.json, we want it to be external to the EXE
        # so users can edit it without rebuilding.
        if getattr(sys, 'frozen', False):
            # If running as EXE, look in the same folder as the EXE
            base_dir = os.path.dirname(sys.executable)
            self.apps_json_path = os.path.join(base_dir, apps_json_path)
        else:
            # If running as script, look in current folder
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
        categories = set()
        for app in self.apps:
            if "category" in app:
                categories.add(app["category"])
        return sorted(list(categories))

    def check_wifi(self) -> Dict[str, Any]:
        try:
            output = subprocess.check_output(["netsh", "wlan", "show", "interfaces"], 
                                           stderr=subprocess.STDOUT, 
                                           universal_newlines=True,
                                           creationflags=subprocess.CREATE_NO_WINDOW)
            ssid = None
            for line in output.split("\n"):
                if "SSID" in line and ":" in line:
                    ssid = line.split(":")[1].strip()
                    break
            
            if ssid:
                return {
                    "connected": True,
                    "ssid": ssid,
                    "is_debs": "debs" in ssid.lower()
                }
        except Exception:
            pass
        return {"connected": False, "ssid": None, "is_debs": False}

    def install_app(self, app: Dict[str, Any], status_callback=None):
        """
        app: dictionary from apps.json
        status_callback: function(message, color)
        """
        name = app.get("name", "Unknown")
        path = app.get("path", "")
        app_type = app.get("type", "exe")
        args = app.get("args", "")
        working_dir = app.get("workingDir", "")
        dest_dir = app.get("destDir", "")
        exe_name = app.get("exeName", "")

        def update_status(msg, color="white"):
            if status_callback:
                status_callback(msg, color)

        try:
            update_status(f"Checking path for {name}...", "orange")
            if not os.path.exists(path.replace("*", "")):
                update_status(f"Cannot access: {path}", "red")
                return False

            if app_type == "copy-then-run":
                update_status(f"Copying installation files for {name}...", "orange")
                if not os.path.exists(dest_dir):
                    os.makedirs(dest_dir, exist_ok=True)
                
                # If path ends with *, we copy contents
                source = path
                if source.endswith("*"):
                    source = source[:-1]
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
                        # Use a simpler way to copy directory contents if it already exists
                        # shutil.copytree requires destination to NOT exist in some python versions
                        # or has dirs_exist_ok in 3.8+
                        shutil.copytree(source, dest_dir, dirs_exist_ok=True)
                    else:
                        shutil.copy2(source, dest_dir)

                exe_path = os.path.join(dest_dir, exe_name)
                if not os.path.exists(exe_path):
                    update_status(f"Installation aborted - Files not copied correctly", "red")
                    return False
                
                path = exe_path
                working_dir = dest_dir

            update_status(f"Launching installer: {name}...", "orange")
            
            cmd = [path]
            if args:
                # This might be tricky if args is a single string with spaces
                # Powershell handles it differently. 
                # For simplicity, we'll try to split if it looks like multiple args
                import shlex
                cmd.extend(shlex.split(args))

            proc = subprocess.Popen(cmd, cwd=working_dir if working_dir else None)
            proc.wait()

            update_status(f"{name} - Installation completed.", "green")
            return True

        except Exception as e:
            update_status(f"Error installing {name}: {str(e)}", "red")
            return False

    def is_app_installed(self, app: Dict[str, Any]) -> bool:
        check_type = app.get("checkType")
        check_match = app.get("checkMatch")
        check_path = app.get("checkPath")
        check_service = app.get("checkService")

        if not check_type:
            # Fallback to name match in registry
            check_type = "Registry"
            check_match = app.get("name")

        try:
            if check_type == "Registry":
                ps_cmd = f'Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*, HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*, HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\* | Where-Object {{ $_.DisplayName -like "*{check_match}*" }}'
                output = subprocess.check_output(["powershell", "-Command", ps_cmd], 
                                               stderr=subprocess.STDOUT, 
                                               universal_newlines=True,
                                               creationflags=subprocess.CREATE_NO_WINDOW)
                return len(output.strip()) > 0
            
            elif check_type == "File":
                return os.path.exists(check_path) if check_path else False
            
            elif check_type == "Service":
                ps_cmd = f'Get-Service -Name "{check_service}"'
                subprocess.check_call(["powershell", "-Command", ps_cmd], 
                                    stderr=subprocess.STDOUT, 
                                    creationflags=subprocess.CREATE_NO_WINDOW)
                return True
        except Exception:
            pass
        return False

    def add_app(self, name, path, args, working_dir, category, app_type="exe"):
        new_app = {
            "name": name,
            "path": path,
            "args": args,
            "workingDir": working_dir,
            "category": category,
            "type": app_type,
            "standard": category == "Standard"
        }
        self.apps.append(new_app)
        self.save_apps()
