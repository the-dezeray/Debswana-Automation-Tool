import customtkinter as ctk
import tkinter as tk
from tkinter import messagebox, filedialog
from PIL import Image, ImageTk, ImageSequence
import os
import subprocess
import threading
from app_logic import AppLogic, resource_path

# Set appearance and theme
ctk.set_appearance_mode("light")
ctk.set_default_color_theme("blue")

PALETTE = {
    "app_bg": "#eaf1f8",
    "surface": "#ffffff",
    "surface_alt": "#f5f8fc",
    "border": "#c8d7e6",
    "text": "#10233f",
    "muted": "#5f7188",
    "primary": "#003a70",
    "primary_hover": "#002c55",
    "sidebar_hover": "#e1ebf5",
    "success": "#1f7a4d",
    "warning": "#b96a00",
    "danger": "#c43f3f",
    "installed": "#247a4a",
}

CATEGORY_COLORS = {
    "Standard": "#eef6ff",
    "Mining": "#f3f7fb",
    "Oil Processing": "#e8f0fa",
    "IM": "#eaf4ff",
    "Uninstallers": "#f6f1f5",
}

CATEGORY_ICONS = {
    "All": "grid",
    "Standard": "standard",
    "Mining": "mining",
    "Oil Processing": "oil",
    "IM": "im",
    "Uninstallers": "uninstall",
}

ICON_FILES = {
    "search": "search.png",
    "download": "download.png",
    "package_plus": "package-plus.png",
    "check": "circle-check-big.png",
    "refresh": "refresh-cw(1).png",
    "plus": "plus.png",
    "wifi": "wifi.png",
    "wifi_off": "wifi-off.png",
    "warning": "triangle-alert.png",
    "grid": "grid-2x2.png",
    "grid_active": "grid-2x2-active.png",
    "standard": "badge-check.png",
    "standard_active": "badge-check-active.png",
    "mining": "pickaxe.png",
    "mining_active": "pickaxe-active.png",
    "oil": "droplets.png",
    "oil_active": "droplets-active.png",
    "im": "monitor-cog.png",
    "im_active": "monitor-cog-active.png",
    "uninstall": "trash-2.png",
    "uninstall_active": "trash-2-active.png",
}

class DesireeSoftwareCenter(ctk.CTk):
    def __init__(self):
        super().__init__()

        self.logic = AppLogic()
        self.title("Desiree Software Center")
        self.geometry("1000x680")
        self.configure(fg_color=PALETTE["app_bg"])
        self.icons = self.load_icons()

        # Layout configuration
        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(0, weight=1)

        # Sidebar
        self.sidebar_frame = ctk.CTkFrame(
            self,
            width=180,
            corner_radius=18,
            fg_color=PALETTE["surface"],
            border_width=1,
            border_color=PALETTE["border"],
        )
        self.sidebar_frame.grid(row=0, column=0, padx=(10, 0), pady=10, sticky="nsew")
        self.sidebar_frame.grid_rowconfigure(7, weight=1)

        # Categories
        self.category_buttons = []
        categories = ["All", "Standard", "Mining", "Oil Processing", "IM", "Uninstallers"]
        for i, cat in enumerate(categories):
            icon_name = CATEGORY_ICONS[cat]
            btn = ctk.CTkButton(self.sidebar_frame, text=cat, corner_radius=10, height=34, border_spacing=8, 
                               fg_color="transparent", text_color=PALETTE["text"], hover_color=PALETTE["sidebar_hover"],
                               image=self.icon(icon_name), compound="left",
                               anchor="w", command=lambda c=cat: self.select_category(c))
            btn.grid(row=i, column=0, padx=8, pady=(8 if i == 0 else 2, 2), sticky="ew")
            self.category_buttons.append(btn)
        
        self.selected_category = "All"
        self.select_category("All")

        # GIF display above logo
        self._gif_frames = []
        self._gif_job = None
        self.gif_label = ctk.CTkLabel(self.sidebar_frame, text="")
        self.gif_label.grid(row=7, column=0, padx=14, pady=(0, 4))
        self.gif_label.grid_remove()  # hidden by default

        # Logo at bottom of sidebar
        logo_file = resource_path("image.png")
        if os.path.exists(logo_file):
            try:
                logo_image = Image.open(logo_file)
                # Maintain aspect ratio - 140 width
                w, h = logo_image.size
                new_h = int(140 * h / w)
                self.sidebar_logo = ctk.CTkImage(light_image=logo_image, dark_image=logo_image, size=(140, new_h))
                self.logo_display = ctk.CTkLabel(self.sidebar_frame, image=self.sidebar_logo, text="")
                self.logo_display.grid(row=8, column=0, padx=14, pady=14)
            except Exception as e:
                print(f"Error loading logo: {e}")

        # Main Content
        self.main_frame = ctk.CTkFrame(self, corner_radius=18, fg_color=PALETTE["surface_alt"])
        self.main_frame.grid(row=0, column=1, padx=10, pady=10, sticky="nsew")
        self.main_frame.grid_columnconfigure(0, weight=1)
        self.main_frame.grid_rowconfigure(2, weight=1)

        # Header
        self.header_frame = ctk.CTkFrame(self.main_frame, height=72, corner_radius=16, fg_color=PALETTE["primary"])
        self.header_frame.grid(row=0, column=0, padx=8, pady=8, sticky="ew")
        self.header_frame.grid_columnconfigure(0, weight=1)

        self.header_title = ctk.CTkLabel(self.header_frame, text="Desiree Software Center", text_color="white", font=ctk.CTkFont(size=22, weight="bold"))
        self.header_title.grid(row=0, column=0, padx=14, pady=14, sticky="w")

        self.wifi_status_label = ctk.CTkLabel(self.header_frame, text="Checking connection...", text_color="white", font=ctk.CTkFont(weight="bold"))
        self.wifi_status_label.grid(row=0, column=1, padx=14, pady=14, sticky="e")

        # Search and Actions
        self.action_frame = ctk.CTkFrame(self.main_frame, fg_color="transparent")
        self.action_frame.grid(row=1, column=0, padx=14, pady=6, sticky="ew")

        self.search_icon_label = ctk.CTkLabel(self.action_frame, image=self.icon("search"), text="")
        self.search_icon_label.grid(row=0, column=0, padx=(0, 6), pady=6)

        self.search_entry = ctk.CTkEntry(
            self.action_frame,
            placeholder_text="Search applications...",
            width=350,
            fg_color=PALETTE["surface"],
            border_color=PALETTE["border"],
            text_color=PALETTE["text"],
        )
        self.search_entry.grid(row=0, column=1, padx=(0, 12), pady=6)
        self.search_entry.bind("<KeyRelease>", lambda e: self.render_apps())

        self.install_all_btn = ctk.CTkButton(self.action_frame, text="⚡ Install All Standard", fg_color="#4682B4", command=self.show_install_all_dialog)
        self.install_all_btn.configure(text="Install All Standard", image=self.icon("package_plus"), compound="left", fg_color=PALETTE["primary"], hover_color=PALETTE["primary_hover"])
        self.install_all_btn.grid(row=0, column=2, padx=6, pady=6)

        self.add_app_btn = ctk.CTkButton(self.action_frame, text="+ Add App", fg_color="white", text_color="black", border_width=1, command=self.show_add_app_dialog)
        self.add_app_btn.configure(
            text="Add App",
            image=self.icon("plus"),
            compound="left",
            fg_color=PALETTE["surface"],
            text_color=PALETTE["text"],
            hover_color=PALETTE["sidebar_hover"],
            border_color=PALETTE["border"],
        )
        self.add_app_btn.grid(row=0, column=3, padx=6, pady=6)

        self.refresh_btn = ctk.CTkButton(self.action_frame, text="↻ Refresh", width=100, fg_color="transparent", text_color=("gray10", "gray90"), border_width=1, command=self.manual_refresh)
        self.refresh_btn.configure(
            text="Refresh",
            image=self.icon("refresh"),
            compound="left",
            text_color=PALETTE["text"],
            hover_color=PALETTE["sidebar_hover"],
            border_color=PALETTE["border"],
        )
        self.refresh_btn.grid(row=0, column=4, padx=6, pady=6)

        # Dashboard (Scrollable)
        self.dashboard_frame = ctk.CTkScrollableFrame(self.main_frame, fg_color="transparent")
        self.dashboard_frame.grid(row=2, column=0, padx=14, pady=6, sticky="nsew")
        self.dashboard_frame.grid_columnconfigure((0, 1), weight=1)

        # Status Bar
        self.status_frame = ctk.CTkFrame(self.main_frame, height=42, corner_radius=0, fg_color="transparent")
        self.status_frame.grid(row=3, column=0, padx=14, pady=(0, 6), sticky="ew")
        
        self.progress_bar = ctk.CTkProgressBar(self.status_frame, width=730)
        self.progress_bar.set(0)
        self.progress_bar.grid(row=0, column=0, pady=(0, 3))

        self.status_label = ctk.CTkLabel(self.status_frame, text="Ready.", font=ctk.CTkFont(weight="bold"))
        self.status_label.grid(row=1, column=0, sticky="w")

        self.refresh_wifi_status()
        self.render_apps()
        # Initial refresh in background to keep UI responsive
        self.after(100, self.manual_refresh)

    def load_icons(self):
        icons = {}
        for name, filename in ICON_FILES.items():
            icon_path = resource_path(os.path.join("assets", filename))
            if not os.path.exists(icon_path):
                continue
            image = Image.open(icon_path)
            icons[name] = ctk.CTkImage(light_image=image, dark_image=image, size=(18, 18))
        return icons

    def icon(self, name):
        return self.icons.get(name)

    def show_gif(self, gif_name):
        """gif_name: 'file-transfer' | 'error-animation' | 'animated-download'"""
        if self._gif_job:
            self.after_cancel(self._gif_job)
            self._gif_job = None
        gif_path = resource_path(os.path.join("assets", f"{gif_name}.gif"))
        if not os.path.exists(gif_path):
            return
        img = Image.open(gif_path)
        self._gif_frames = []
        for frame in ImageSequence.Iterator(img):
            f = frame.copy().convert("RGBA")
            f.thumbnail((140, 140))
            self._gif_frames.append(ImageTk.PhotoImage(f))
        if not self._gif_frames:
            return
        self.gif_label.grid()
        self._animate_gif(0)

    def _animate_gif(self, idx):
        if not self._gif_frames:
            return
        self.gif_label.configure(image=self._gif_frames[idx])
        self._gif_job = self.after(50, self._animate_gif, (idx + 1) % len(self._gif_frames))

    def hide_gif(self):
        if self._gif_job:
            self.after_cancel(self._gif_job)
            self._gif_job = None
        self.gif_label.grid_remove()
        self._gif_frames = []

    def show_card_context_menu(self, event, app):
        menu = tk.Menu(self, tearoff=0)
        menu.add_command(label="📂  View Path", command=lambda: self.open_app_path_explorer(app))
        menu.add_command(label="⬇  Install", command=lambda: self.install_thread(app))
        try:
            menu.tk_popup(event.x_root, event.y_root)
        finally:
            menu.grab_release()

    def open_app_path_explorer(self, app):
        path = app.get("path", "").replace("*", "")
        if not path:
            return
        # Open the folder containing the path, or the path itself if it's a dir
        target = path if os.path.isdir(path) else os.path.dirname(path)
        try:
            subprocess.Popen(["explorer", target])
        except Exception as e:
            messagebox.showerror("Error", f"Could not open path:\n{target}\n\n{e}")

    def manual_refresh(self):
        self.update_status("Refreshing application status...", "orange")
        threading.Thread(target=self._refresh_task, daemon=True).start()

    def _refresh_task(self):
        self.logic.refresh_installed_apps_cache()
        self.after(0, self.render_apps)
        self.after(0, lambda: self.update_status("Ready.", "white"))

    def select_category(self, category):
        self.selected_category = category
        for btn in self.category_buttons:
            btn_category = btn.cget("text").strip()
            icon_name = CATEGORY_ICONS[btn_category]
            if btn_category == category:
                btn.configure(
                    fg_color=PALETTE["primary"],
                    text_color="white",
                    hover_color=PALETTE["primary_hover"],
                    image=self.icon(f"{icon_name}_active"),
                    font=ctk.CTkFont(weight="bold"),
                )
            else:
                btn.configure(
                    fg_color="transparent",
                    text_color=PALETTE["text"],
                    hover_color=PALETTE["sidebar_hover"],
                    image=self.icon(icon_name),
                    font=ctk.CTkFont(weight="normal"),
                )
        if hasattr(self, 'dashboard_frame'):
            self.render_apps()

    def refresh_wifi_status(self):
        threading.Thread(target=self._wifi_status_task, daemon=True).start()

    def _wifi_status_task(self):
        status = self.logic.check_wifi()
        self.after(0, lambda: self.update_wifi_status(status))

    def update_wifi_status(self, status):
        if status["is_debs"]:
            self.wifi_status_label.configure(image=self.icon("wifi"), compound="left")
            self.wifi_status_label.configure(text=f"● DEBS WiFi Connected ({status['ssid']})", text_color="#90EE90")
        elif status["connected"]:
            self.wifi_status_label.configure(image=self.icon("warning"), compound="left")
            self.wifi_status_label.configure(text=f"● Connected to {status['ssid']} (Not DEBS)", text_color="#FFB6C1")
            self.show_wifi_warning(status['ssid'])
        else:
            self.wifi_status_label.configure(image=self.icon("wifi_off"), compound="left")
            self.wifi_status_label.configure(text="● Not Connected", text_color="#FF6347")
            self.show_wifi_warning("No WiFi network detected")

    def show_wifi_warning(self, ssid):
        messagebox.showwarning("Corporate WiFi Required", 
                               f"You are currently connected to: {ssid}\n\n"
                               "This tool uses Debswana network locations. Accessing installers and shared paths will not work unless you are connected to the corporate DEBS WiFi.")

    def render_apps(self):
        # Ensure this runs on the main thread if called from a thread
        if threading.current_thread() != threading.main_thread():
            self.after(0, self.render_apps)
            return

        # Clear current dashboard
        for widget in self.dashboard_frame.winfo_children():
            widget.destroy()

        search_term = self.search_entry.get().lower()
        filtered_apps = self.logic.apps

        if self.selected_category != "All":
            filtered_apps = [app for app in filtered_apps if app.get("category") == self.selected_category]

        if search_term:
            filtered_apps = [app for app in filtered_apps if search_term in app.get("name", "").lower() or search_term in app.get("category", "").lower()]

        for i, app in enumerate(filtered_apps):
            self.create_app_card(app, i)

    def create_app_card(self, app, index):
        row = index // 2
        col = index % 2

        card = ctk.CTkFrame(
            self.dashboard_frame,
            height=64,
            corner_radius=8,
            border_width=1,
            border_color=PALETTE["border"],
        )
        card.grid(row=row, column=col, padx=6, pady=6, sticky="ew")
        card.grid_columnconfigure(0, weight=1)

        # Set background color based on category
        cat = app.get("category", "")
        card.configure(fg_color=CATEGORY_COLORS.get(cat, PALETTE["surface"]))

        name_label = ctk.CTkLabel(card, text=app.get("name", ""), font=ctk.CTkFont(size=13, weight="bold"), text_color=PALETTE["text"])
        name_label.grid(row=0, column=0, padx=10, pady=(7, 0), sticky="w")

        cat_label = ctk.CTkLabel(card, text=app.get("category", ""), font=ctk.CTkFont(size=11), text_color=PALETTE["muted"])
        cat_label.grid(row=1, column=0, padx=10, pady=(0, 7), sticky="w")

        is_installed = self.logic.is_app_installed(app)
        btn_text = "Installed" if is_installed else "Install"
        btn_color = PALETTE["installed"] if is_installed else PALETTE["primary"]
        btn_icon = self.icon("check" if is_installed else "download")

        install_btn = ctk.CTkButton(
            card,
            text=btn_text,
            image=btn_icon,
            compound="left",
            width=98,
            height=28,
            fg_color=btn_color,
            hover_color=PALETTE["primary_hover"],
            command=lambda a=app: self.install_thread(a),
        )
        install_btn.grid(row=0, column=1, rowspan=2, padx=10, pady=7)

        # Right-click context menu on the whole card
        for widget in (card, name_label, cat_label):
            widget.bind("<Button-3>", lambda e, a=app: self.show_card_context_menu(e, a))

    def install_thread(self, app):
        threading.Thread(target=self.run_install, args=(app,), daemon=True).start()

    def run_install(self, app):
        self.progress_bar.set(0.2)
        self.install_all_btn.configure(state="disabled")
        self.after(0, lambda: self.show_gif("file-transfer"))
        success = self.logic.install_app(app, status_callback=self.update_status)
        self.progress_bar.set(1.0)
        self.install_all_btn.configure(state="normal")
        if success:
            self.after(0, lambda: self.show_gif("animated-download"))
            self.after(2500, self.hide_gif)
            self.logic.refresh_installed_apps_cache()
            self.render_apps()
        else:
            self.after(0, lambda: self.show_gif("error-animation"))
            self.after(3000, self.hide_gif)
            self.after(0, lambda: messagebox.showerror(
                "Installation Failed",
                f"Could not install {app.get('name', 'app')}.\n\nCheck your network connection or contact IT support."
            ))

    def update_status(self, message, color="white"):
        # Ensure this runs on main thread
        if threading.current_thread() != threading.main_thread():
            self.after(0, lambda: self.update_status(message, color))
            return

        # Map color names to hex if needed, but customtkinter labels handle some names
        color_map = {
            "orange": PALETTE["warning"],
            "red": PALETTE["danger"],
            "green": PALETTE["success"],
            "white": PALETTE["text"],
        }
        self.status_label.configure(text=message, text_color=color_map.get(color, PALETTE["text"]))
        if "completed" in message.lower():
            self.progress_bar.set(1.0)

    def show_install_all_dialog(self):
        standard_apps = [app for app in self.logic.apps if app.get("standard") or app.get("category") == "Standard"]
        if not standard_apps:
            messagebox.showinfo("Info", "No standard applications found.")
            return

        dialog = ctk.CTkToplevel(self)
        dialog.title("Select Applications to Install")
        dialog.geometry("700x560")
        dialog.grab_set()

        label = ctk.CTkLabel(dialog, text="Select the standard applications you want to install:", font=ctk.CTkFont(size=15, weight="bold"))
        label.pack(pady=14)

        scroll_frame = ctk.CTkScrollableFrame(dialog, width=620, height=350)
        scroll_frame.pack(padx=14, pady=6)

        checkboxes = []
        for app in standard_apps:
            var = tk.BooleanVar(value=True)
            cb = ctk.CTkCheckBox(scroll_frame, text=f"{app['name']} - {app['category']}", variable=var)
            cb.pack(anchor="w", padx=14, pady=3)
            checkboxes.append((app, var))

        btn_frame = ctk.CTkFrame(dialog, fg_color="transparent")
        btn_frame.pack(pady=12)

        def select_all():
            for _, var in checkboxes: var.set(True)
        def deselect_all():
            for _, var in checkboxes: var.set(False)

        ctk.CTkButton(btn_frame, text="Select All", command=select_all).grid(row=0, column=0, padx=6)
        ctk.CTkButton(btn_frame, text="Deselect All", command=deselect_all).grid(row=0, column=1, padx=6)

        def start_bulk_install():
            selected = [app for app, var in checkboxes if var.get()]
            if not selected:
                messagebox.showwarning("No Selection", "Please select at least one application.")
                return
            dialog.destroy()
            threading.Thread(target=self.run_bulk_install, args=(selected,), daemon=True).start()

        ctk.CTkButton(
            dialog,
            text="Install Selected",
            fg_color=PALETTE["primary"],
            hover_color=PALETTE["primary_hover"],
            command=start_bulk_install,
        ).pack(pady=6)

    def run_bulk_install(self, apps):
        total = len(apps)
        self.install_all_btn.configure(state="disabled")
        self.after(0, lambda: self.show_gif("file-transfer"))
        failed = []
        for i, app in enumerate(apps):
            self.update_status(f"Installing ({i+1}/{total}): {app['name']}...", "orange")
            self.progress_bar.set((i + 1) / total)
            ok = self.logic.install_app(app, status_callback=self.update_status)
            if not ok:
                failed.append(app['name'])
        
        self.logic.refresh_installed_apps_cache()
        self.render_apps()
        self.install_all_btn.configure(state="normal")

        if failed:
            self.after(0, lambda: self.show_gif("error-animation"))
            self.after(3000, self.hide_gif)
            self.after(0, lambda: messagebox.showwarning(
                "Some Installations Failed",
                f"{len(failed)} app(s) failed to install:\n\n" + "\n".join(f"• {n}" for n in failed)
            ))
        else:
            self.after(0, lambda: self.show_gif("animated-download"))
            self.after(2500, self.hide_gif)
            self.update_status(f"Installation complete! ({total} applications)", "green")

    def show_add_app_dialog(self):
        dialog = ctk.CTkToplevel(self)
        dialog.title("Add Application")
        dialog.geometry("460x330")
        dialog.grab_set()

        ctk.CTkLabel(dialog, text="Name:").grid(row=0, column=0, padx=14, pady=7, sticky="e")
        name_entry = ctk.CTkEntry(dialog, width=300)
        name_entry.grid(row=0, column=1, padx=14, pady=7)

        ctk.CTkLabel(dialog, text="Path:").grid(row=1, column=0, padx=14, pady=7, sticky="e")
        path_frame = ctk.CTkFrame(dialog, fg_color="transparent")
        path_frame.grid(row=1, column=1, padx=14, pady=7)
        path_entry = ctk.CTkEntry(path_frame, width=220)
        path_entry.pack(side="left", padx=(0, 6))
        
        def browse():
            f = filedialog.askopenfilename()
            if f:
                path_entry.delete(0, "end")
                path_entry.insert(0, f)
        ctk.CTkButton(path_frame, text="Browse", width=70, command=browse).pack(side="left")

        ctk.CTkLabel(dialog, text="Args:").grid(row=2, column=0, padx=14, pady=7, sticky="e")
        args_entry = ctk.CTkEntry(dialog, width=300)
        args_entry.grid(row=2, column=1, padx=14, pady=7)

        ctk.CTkLabel(dialog, text="Category:").grid(row=3, column=0, padx=14, pady=7, sticky="e")
        cat_combo = ctk.CTkComboBox(dialog, values=["Standard", "Mining", "Oil Processing", "IM", "Uninstallers"], width=300)
        cat_combo.grid(row=3, column=1, padx=14, pady=7)
        cat_combo.set("Standard")

        def save():
            self.logic.add_app(name_entry.get(), path_entry.get(), args_entry.get(), "", cat_combo.get())
            self.render_apps()
            dialog.destroy()

        ctk.CTkButton(dialog, text="Save", command=save).grid(row=4, column=0, columnspan=2, pady=12)

if __name__ == "__main__":
    app = DesireeSoftwareCenter()
    app.mainloop()
