import customtkinter as ctk
import tkinter as tk
from tkinter import messagebox, filedialog
from PIL import Image, ImageTk
import os
import threading
from app_logic import AppLogic, resource_path

# Set appearance and theme
ctk.set_appearance_mode("light")
ctk.set_default_color_theme("blue")

class DesireeSoftwareCenter(ctk.CTk):
    def __init__(self):
        super().__init__()

        self.logic = AppLogic()
        self.title("Desiree Software Center")
        self.geometry("1100x750")

        # Layout configuration
        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(0, weight=1)

        # Sidebar
        self.sidebar_frame = ctk.CTkFrame(self, width=200, corner_radius=0)
        self.sidebar_frame.grid(row=0, column=0, sticky="nsew")
        self.sidebar_frame.grid_rowconfigure(8, weight=1)

        self.logo_label = ctk.CTkLabel(self.sidebar_frame, text="Desiree Software Center", font=ctk.CTkFont(size=20, weight="bold"))
        self.logo_label.grid(row=0, column=0, padx=20, pady=(20, 10))

        # Categories
        self.category_buttons = []
        categories = ["All", "Standard", "Mining", "Oil Processing", "IM", "Uninstallers"]
        for i, cat in enumerate(categories):
            btn = ctk.CTkButton(self.sidebar_frame, text=cat, corner_radius=0, height=40, border_spacing=10, 
                               fg_color="transparent", text_color=("gray10", "gray90"), hover_color=("gray70", "gray30"),
                               anchor="w", command=lambda c=cat: self.select_category(c))
            btn.grid(row=i+1, column=0, sticky="ew")
            self.category_buttons.append(btn)
        
        self.selected_category = "All"
        self.select_category("All")

        # Logo at bottom of sidebar
        logo_file = resource_path("image.png")
        if os.path.exists(logo_file):
            try:
                logo_image = Image.open(logo_file)
                # Maintain aspect ratio - 160 width
                w, h = logo_image.size
                new_h = int(160 * h / w)
                self.sidebar_logo = ctk.CTkImage(light_image=logo_image, dark_image=logo_image, size=(160, new_h))
                self.logo_display = ctk.CTkLabel(self.sidebar_frame, image=self.sidebar_logo, text="")
                self.logo_display.grid(row=9, column=0, padx=20, pady=20)
            except Exception as e:
                print(f"Error loading logo: {e}")

        # Main Content
        self.main_frame = ctk.CTkFrame(self, corner_radius=0, fg_color="#e6f0ff")
        self.main_frame.grid(row=0, column=1, sticky="nsew")
        self.main_frame.grid_columnconfigure(0, weight=1)
        self.main_frame.grid_rowconfigure(2, weight=1)

        # Header
        self.header_frame = ctk.CTkFrame(self.main_frame, height=100, corner_radius=0, fg_color="#4682B4")
        self.header_frame.grid(row=0, column=0, sticky="ew")
        self.header_frame.grid_columnconfigure(0, weight=1)

        self.header_title = ctk.CTkLabel(self.header_frame, text="Desiree Software Center", text_color="white", font=ctk.CTkFont(size=24, weight="bold"))
        self.header_title.grid(row=0, column=0, padx=20, pady=20, sticky="w")

        self.wifi_status_label = ctk.CTkLabel(self.header_frame, text="Checking connection...", text_color="white", font=ctk.CTkFont(weight="bold"))
        self.wifi_status_label.grid(row=0, column=1, padx=20, pady=20, sticky="e")

        # Search and Actions
        self.action_frame = ctk.CTkFrame(self.main_frame, fg_color="transparent")
        self.action_frame.grid(row=1, column=0, padx=20, pady=10, sticky="ew")

        self.search_entry = ctk.CTkEntry(self.action_frame, placeholder_text="Search applications...", width=350)
        self.search_entry.grid(row=0, column=0, padx=(0, 20), pady=10)
        self.search_entry.bind("<KeyRelease>", lambda e: self.render_apps())

        self.install_all_btn = ctk.CTkButton(self.action_frame, text="⚡ Install All Standard", fg_color="#4682B4", command=self.show_install_all_dialog)
        self.install_all_btn.grid(row=0, column=1, padx=10, pady=10)

        self.add_app_btn = ctk.CTkButton(self.action_frame, text="+ Add App", fg_color="white", text_color="black", border_width=1, command=self.show_add_app_dialog)
        self.add_app_btn.grid(row=0, column=2, padx=10, pady=10)

        self.refresh_btn = ctk.CTkButton(self.action_frame, text="↻ Refresh", width=100, fg_color="transparent", text_color=("gray10", "gray90"), border_width=1, command=self.manual_refresh)
        self.refresh_btn.grid(row=0, column=3, padx=10, pady=10)

        # Dashboard (Scrollable)
        self.dashboard_frame = ctk.CTkScrollableFrame(self.main_frame, fg_color="transparent")
        self.dashboard_frame.grid(row=2, column=0, padx=20, pady=10, sticky="nsew")
        self.dashboard_frame.grid_columnconfigure((0, 1), weight=1)

        # Status Bar
        self.status_frame = ctk.CTkFrame(self.main_frame, height=50, corner_radius=0, fg_color="transparent")
        self.status_frame.grid(row=3, column=0, padx=20, pady=(0, 10), sticky="ew")
        
        self.progress_bar = ctk.CTkProgressBar(self.status_frame, width=730)
        self.progress_bar.set(0)
        self.progress_bar.grid(row=0, column=0, pady=(0, 5))

        self.status_label = ctk.CTkLabel(self.status_frame, text="Ready.", font=ctk.CTkFont(weight="bold"))
        self.status_label.grid(row=1, column=0, sticky="w")

        self.refresh_wifi_status()
        self.render_apps()
        # Initial refresh in background to keep UI responsive
        self.after(100, self.manual_refresh)

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
            if btn.cget("text").strip() == category:
                btn.configure(fg_color="#34495e", font=ctk.CTkFont(weight="bold"))
            else:
                btn.configure(fg_color="transparent", font=ctk.CTkFont(weight="normal"))
        if hasattr(self, 'dashboard_frame'):
            self.render_apps()

    def refresh_wifi_status(self):
        threading.Thread(target=self._wifi_status_task, daemon=True).start()

    def _wifi_status_task(self):
        status = self.logic.check_wifi()
        self.after(0, lambda: self.update_wifi_status(status))

    def update_wifi_status(self, status):
        if status["is_debs"]:
            self.wifi_status_label.configure(text=f"● DEBS WiFi Connected ({status['ssid']})", text_color="#90EE90")
        elif status["connected"]:
            self.wifi_status_label.configure(text=f"● Connected to {status['ssid']} (Not DEBS)", text_color="#FFB6C1")
            self.show_wifi_warning(status['ssid'])
        else:
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

        card = ctk.CTkFrame(self.dashboard_frame, height=80, corner_radius=10, border_width=1)
        card.grid(row=row, column=col, padx=10, pady=10, sticky="ew")
        card.grid_columnconfigure(0, weight=1)

        # Set background color based on category
        cat = app.get("category", "")
        if cat == "Standard": card.configure(fg_color="#e1f0ff")
        elif cat == "Mining": card.configure(fg_color="#c8e6ff")
        elif cat == "IM": card.configure(fg_color="#d2ebff")
        elif cat == "Uninstallers": card.configure(fg_color="#b4dcff")
        else: card.configure(fg_color="white")

        name_label = ctk.CTkLabel(card, text=app.get("name", ""), font=ctk.CTkFont(size=14, weight="bold"), text_color="black")
        name_label.grid(row=0, column=0, padx=15, pady=(10, 0), sticky="w")

        cat_label = ctk.CTkLabel(card, text=app.get("category", ""), font=ctk.CTkFont(size=11), text_color="gray")
        cat_label.grid(row=1, column=0, padx=15, pady=(0, 10), sticky="w")

        is_installed = self.logic.is_app_installed(app)
        btn_text = "Installed" if is_installed else "Install"
        btn_color = "#2e7d32" if is_installed else "#4682B4" # Green if installed

        install_btn = ctk.CTkButton(card, text=btn_text, width=80, height=30, fg_color=btn_color, command=lambda a=app: self.install_thread(a))
        install_btn.grid(row=0, column=1, rowspan=2, padx=15, pady=10)

    def install_thread(self, app):
        threading.Thread(target=self.run_install, args=(app,), daemon=True).start()

    def run_install(self, app):
        self.progress_bar.set(0.2)
        self.install_all_btn.configure(state="disabled")
        success = self.logic.install_app(app, status_callback=self.update_status)
        self.progress_bar.set(1.0)
        self.install_all_btn.configure(state="normal")
        if success:
            self.logic.refresh_installed_apps_cache()
            self.render_apps() # Refresh to show "Installed"

    def update_status(self, message, color="white"):
        # Ensure this runs on main thread
        if threading.current_thread() != threading.main_thread():
            self.after(0, lambda: self.update_status(message, color))
            return

        # Map color names to hex if needed, but customtkinter labels handle some names
        color_map = {"orange": "#FF8C00", "red": "#FF0000", "green": "#008000", "white": "black"}
        self.status_label.configure(text=message, text_color=color_map.get(color, "black"))
        if "completed" in message.lower():
            self.progress_bar.set(1.0)

    def show_install_all_dialog(self):
        standard_apps = [app for app in self.logic.apps if app.get("standard") or app.get("category") == "Standard"]
        if not standard_apps:
            messagebox.showinfo("Info", "No standard applications found.")
            return

        dialog = ctk.CTkToplevel(self)
        dialog.title("Select Applications to Install")
        dialog.geometry("750x650")
        dialog.grab_set()

        label = ctk.CTkLabel(dialog, text="Select the standard applications you want to install:", font=ctk.CTkFont(size=16, weight="bold"))
        label.pack(pady=20)

        scroll_frame = ctk.CTkScrollableFrame(dialog, width=650, height=400)
        scroll_frame.pack(padx=20, pady=10)

        checkboxes = []
        for app in standard_apps:
            var = tk.BooleanVar(value=True)
            cb = ctk.CTkCheckBox(scroll_frame, text=f"{app['name']} - {app['category']}", variable=var)
            cb.pack(anchor="w", padx=20, pady=5)
            checkboxes.append((app, var))

        btn_frame = ctk.CTkFrame(dialog, fg_color="transparent")
        btn_frame.pack(pady=20)

        def select_all():
            for _, var in checkboxes: var.set(True)
        def deselect_all():
            for _, var in checkboxes: var.set(False)

        ctk.CTkButton(btn_frame, text="Select All", command=select_all).grid(row=0, column=0, padx=10)
        ctk.CTkButton(btn_frame, text="Deselect All", command=deselect_all).grid(row=0, column=1, padx=10)

        def start_bulk_install():
            selected = [app for app, var in checkboxes if var.get()]
            if not selected:
                messagebox.showwarning("No Selection", "Please select at least one application.")
                return
            dialog.destroy()
            threading.Thread(target=self.run_bulk_install, args=(selected,), daemon=True).start()

        ctk.CTkButton(dialog, text="Install Selected", fg_color="#4682B4", command=start_bulk_install).pack(pady=10)

    def run_bulk_install(self, apps):
        total = len(apps)
        self.install_all_btn.configure(state="disabled")
        for i, app in enumerate(apps):
            self.update_status(f"Installing ({i+1}/{total}): {app['name']}...", "orange")
            self.progress_bar.set((i + 1) / total)
            self.logic.install_app(app, status_callback=self.update_status)
        
        self.logic.refresh_installed_apps_cache()
        self.render_apps()
        self.update_status(f"Installation complete! ({total} applications)", "green")
        self.install_all_btn.configure(state="normal")

    def show_add_app_dialog(self):
        dialog = ctk.CTkToplevel(self)
        dialog.title("Add Application")
        dialog.geometry("500x400")
        dialog.grab_set()

        ctk.CTkLabel(dialog, text="Name:").grid(row=0, column=0, padx=20, pady=10, sticky="e")
        name_entry = ctk.CTkEntry(dialog, width=300)
        name_entry.grid(row=0, column=1, padx=20, pady=10)

        ctk.CTkLabel(dialog, text="Path:").grid(row=1, column=0, padx=20, pady=10, sticky="e")
        path_frame = ctk.CTkFrame(dialog, fg_color="transparent")
        path_frame.grid(row=1, column=1, padx=20, pady=10)
        path_entry = ctk.CTkEntry(path_frame, width=220)
        path_entry.pack(side="left", padx=(0, 10))
        
        def browse():
            f = filedialog.askopenfilename()
            if f:
                path_entry.delete(0, "end")
                path_entry.insert(0, f)
        ctk.CTkButton(path_frame, text="Browse", width=70, command=browse).pack(side="left")

        ctk.CTkLabel(dialog, text="Args:").grid(row=2, column=0, padx=20, pady=10, sticky="e")
        args_entry = ctk.CTkEntry(dialog, width=300)
        args_entry.grid(row=2, column=1, padx=20, pady=10)

        ctk.CTkLabel(dialog, text="Category:").grid(row=3, column=0, padx=20, pady=10, sticky="e")
        cat_combo = ctk.CTkComboBox(dialog, values=["Standard", "Mining", "Oil Processing", "IM", "Uninstallers"], width=300)
        cat_combo.grid(row=3, column=1, padx=20, pady=10)
        cat_combo.set("Standard")

        def save():
            self.logic.add_app(name_entry.get(), path_entry.get(), args_entry.get(), "", cat_combo.get())
            self.render_apps()
            dialog.destroy()

        ctk.CTkButton(dialog, text="Save", command=save).grid(row=4, column=0, columnspan=2, pady=20)

if __name__ == "__main__":
    app = DesireeSoftwareCenter()
    app.mainloop()
