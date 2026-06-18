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
        self.installed_apps_cache = []
        self.installed_services_cache = set()
        self.start_apps_cache = []
        self.app_status_cache = {}
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

    def refresh_installed_apps_cache(self):
        """Fetches Windows app status once so UI rendering stays fast."""
        installed_apps = []
        installed_services = set()
        start_apps = []

        try:
            ps_cmd = (
                "$paths = @("
                "'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*', "
                "'HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*', "
                "'HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*'); "
                "foreach ($path in $paths) { "
                "  Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | "
                "  Where-Object { $_.DisplayName } | Select-Object -ExpandProperty DisplayName"
                "}"
            )
            output = subprocess.check_output(["powershell", "-Command", ps_cmd], 
                                           stderr=subprocess.STDOUT, 
                                           universal_newlines=True,
                                           creationflags=subprocess.CREATE_NO_WINDOW)
            installed_apps = [line.strip().lower() for line in output.splitlines() if line.strip()]
        except Exception as e:
            print(f"Error caching installed apps: {e}")

        service_names = sorted({
            app.get("checkService", "").strip()
            for app in self.apps
            if app.get("checkType") == "Service" and app.get("checkService")
        })
        if service_names:
            try:
                quoted_services = ",".join(f"'{name}'" for name in service_names)
                ps_cmd = (
                    f"$names = @({quoted_services}); "
                    "Get-Service -Name $names -ErrorAction SilentlyContinue | "
                    "Select-Object -ExpandProperty Name"
                )
                output = subprocess.check_output(["powershell", "-Command", ps_cmd],
                                               stderr=subprocess.STDOUT,
                                               universal_newlines=True,
                                               creationflags=subprocess.CREATE_NO_WINDOW)
                installed_services = {line.strip().lower() for line in output.splitlines() if line.strip()}
            except Exception as e:
                print(f"Error caching installed services: {e}")

        try:
            output = subprocess.check_output(["powershell", "-Command", "Get-StartApps | Select-Object -ExpandProperty Name"],
                                           stderr=subprocess.STDOUT,
                                           universal_newlines=True,
                                           creationflags=subprocess.CREATE_NO_WINDOW)
            start_apps = [line.strip().lower() for line in output.splitlines() if line.strip()]
        except Exception as e:
            print(f"Error caching Start menu apps: {e}")

        self.installed_apps_cache = installed_apps
        self.installed_services_cache = installed_services
        self.start_apps_cache = start_apps
        self.app_status_cache = {
            self._app_cache_key(app): self._calculate_app_installed(app)
            for app in self.apps
        }

    def _app_cache_key(self, app: Dict[str, Any]) -> str:
        return app.get("name", "").strip().lower()

    def _contains_cached_name(self, names: List[str], needle: str) -> bool:
        needle = needle.strip().lower()
        return bool(needle) and any(needle in name for name in names)

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

        run_as_admin = app.get("runAsAdmin", False)

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
            
            if run_as_admin:
                # Use PowerShell Start-Process with -Verb RunAs for elevation
                # We wrap arguments carefully to ensure they reach the elevated process
                ps_args = f'-FilePath "{path}"'
                if args:
                    ps_args += f' -ArgumentList "{args}"'
                if working_dir:
                    ps_args += f' -WorkingDirectory "{working_dir}"'
                
                ps_cmd = f'Start-Process {ps_args} -Verb RunAs -Wait'
                subprocess.check_call(["powershell", "-Command", ps_cmd], 
                                    creationflags=subprocess.CREATE_NO_WINDOW)
            else:
                cmd = [path]
                if args:
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
        cache_key = self._app_cache_key(app)
        if cache_key in self.app_status_cache:
            return self.app_status_cache[cache_key]

        return self._calculate_app_installed(app)

    def _calculate_app_installed(self, app: Dict[str, Any]) -> bool:
        check_type = app.get("checkType")
        check_match = app.get("checkMatch")
        check_path = app.get("checkPath")
        check_service = app.get("checkService")
        app_name = app.get("name", "")

        try:
            # 1. Primary Check based on checkType
            if check_type == "Registry" and check_match:
                if self._contains_cached_name(self.installed_apps_cache, check_match):
                    return True
            
            elif check_type == "File" and check_path:
                if os.path.exists(check_path):
                    return True
            
            elif check_type == "Service" and check_service:
                if check_service.lower() in self.installed_services_cache:
                    return True

            # 2. Robust Fallback: Check Registry by App Name if not already found
            if self._contains_cached_name(self.installed_apps_cache, app_name):
                return True

            # 3. Final Fallback: Check cached Start Menu apps (Windows 10+)
            if self._contains_cached_name(self.start_apps_cache, app_name):
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

    def open_app_path(self, app: Dict[str, Any]):
        """Opens the file or folder path associated with the app."""
        path = app.get("path", "")
        if not path:
            return False
        
        # Remove wildcards if any (though usually for configs we won't have them)
        clean_path = path.replace("*", "")
        
        try:
            if os.path.exists(clean_path):
                os.startfile(clean_path)
                return True
            else:
                # If it's a network path that might not be mapped but accessible
                # os.startfile usually handles UNC paths fine on Windows.
                os.startfile(clean_path)
                return True
        except Exception as e:
            print(f"Error opening path {clean_path}: {e}")
            return False
