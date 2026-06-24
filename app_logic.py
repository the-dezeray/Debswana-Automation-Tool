import json
import os
import sys
import subprocess
from typing import List, Dict, Any

APPS_JSON_NETWORK = r"\\10.50.93.5\g\DebswanaAutomationProject\apps.json"
SERVER = r"\\10.50.93.5"

def resource_path(relative_path):
    try:
        base_path = sys._MEIPASS
    except Exception:
        base_path = os.path.abspath(".")
    return os.path.join(base_path, relative_path)

class AppLogic:
    def __init__(self):
        self.apps_json_path = APPS_JSON_NETWORK
        self.apps: List[Dict[str, Any]] = []

    def load_apps(self):
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

    def is_server_reachable(self) -> bool:
        """Try net view first, then a simple path existence check."""
        try:
            subprocess.check_output(
                ["net", "view", SERVER],
                stderr=subprocess.STDOUT,
                timeout=5,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            return True
        except Exception:
            pass
        # Fallback: try to list the UNC path directly
        try:
            os.listdir(SERVER)
            return True
        except Exception:
            pass
        return False

    def open_server_in_explorer(self):
        """Open the server in Explorer as a last-resort connectivity prompt."""
        try:
            subprocess.Popen(["explorer", SERVER])
        except Exception:
            pass

    def check_wifi(self) -> Dict[str, Any]:
        try:
            output = subprocess.check_output(
                ["powershell", "-NoProfile", "-Command", "(Get-NetConnectionProfile).Name"],
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                creationflags=subprocess.CREATE_NO_WINDOW
            ).strip()
            if output:
                return {"connected": True, "ssid": output, "is_debs": output.strip() == "debs.debswana.bw"}
        except Exception:
            pass
        return {"connected": False, "ssid": None, "is_debs": False}

    def check_connection(self) -> Dict[str, Any]:
        """Returns wifi status + server reachability in one call."""
        wifi = self.check_wifi()
        wifi["server_ok"] = self.is_server_reachable()
        return wifi

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
                source = path.rstrip("*\\/ ") if path.endswith("*") else path
                # Use SHFileOperation — shows native Windows copy progress dialog, no PowerShell
                import ctypes, ctypes.wintypes
                class SHFILEOPSTRUCT(ctypes.Structure):
                    _fields_ = [
                        ("hwnd",   ctypes.wintypes.HWND),
                        ("wFunc",  ctypes.c_uint),
                        ("pFrom",  ctypes.c_wchar_p),
                        ("pTo",    ctypes.c_wchar_p),
                        ("fFlags", ctypes.c_ushort),
                        ("fAnyOperationsAborted", ctypes.wintypes.BOOL),
                        ("hNameMappings",         ctypes.c_void_p),
                        ("lpszProgressTitle",     ctypes.c_wchar_p),
                    ]
                FO_COPY  = 0x0002
                FOF_NOCONFIRMMKDIR = 0x0200  # auto-create dest, no prompt
                op = SHFILEOPSTRUCT()
                op.wFunc  = FO_COPY
                op.pFrom  = source + "\0\0"   # double-null terminated
                op.pTo    = dest_dir + "\0\0"
                op.fFlags = FOF_NOCONFIRMMKDIR
                result = ctypes.windll.shell32.SHFileOperationW(ctypes.byref(op))
                if result != 0:
                    raise RuntimeError(f"SHFileOperationW failed with code {result}")
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

    def delete_app(self, app):
        """
        Remove an app entry and persist. Try direct object removal first, fall back to
        matching by name and path.
        """
        try:
            self.apps.remove(app)
        except ValueError:
            name = app.get("name")
            path = app.get("path")
            for existing in list(self.apps):
                if existing.get("name") == name and existing.get("path") == path:
                    try:
                        self.apps.remove(existing)
                        break
                    except ValueError:
                        pass
        self.save_apps()
