import customtkinter as ctk
import tkinter as tk
from tkinter import messagebox, filedialog
from PIL import Image, ImageTk, ImageSequence
import os
import subprocess
import sys
import threading
from app_logic import AppLogic, resource_path

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
    "refresh": "refresh-cw.png",
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
    "wrench": "wrench.png",
    "info": "info.png",
    "computer": "computer.png",
    "folder": "folder.png",
}


class DesireeSoftwareCenter(ctk.CTk):
    def __init__(self):
        super().__init__()
        self.logic = AppLogic()
        self.title("Debswana Software Kit  v1.0.0")
        self.geometry("1000x680")
        self.after(0, lambda: self.state("zoomed"))
        self.configure(fg_color=PALETTE["app_bg"])
        self.icons = self._load_icons()
        self._selected_index = -1
        self._filtered_apps = []
        self._rendered_keys = []   # list of id(app) for current cards
        self._card_widgets = {}    # index -> card CTkFrame

        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(0, weight=1)

        self._build_sidebar()
        self._build_main()
        self._bind_shortcuts()

        # Show connection check before loading apps
        self.after(100, self._show_connection_check)

    # ── Startup connection check ───────────────────────────────────────────
    def _show_connection_check(self):
        self._conn_dlg = ctk.CTkToplevel(self)
        self._conn_dlg.title("Checking Connection")
        self._conn_dlg.geometry("380x320")
        self._conn_dlg.resizable(False, False)
        self._conn_dlg.grab_set()
        # block closing just the dialog
        self._conn_dlg.protocol("WM_DELETE_WINDOW", lambda: None)
        # allow closing the whole app
        self.protocol("WM_DELETE_WINDOW", self._on_close)

        # Center on parent
        self._conn_dlg.transient(self)

        self._conn_gif_frames = []
        self._conn_gif_job = None

        # Wifi animation
        gif_path = resource_path(os.path.join("assets", "wifi-animation.gif"))
        self._conn_gif_label = ctk.CTkLabel(self._conn_dlg, text="")
        self._conn_gif_label.pack(pady=(18, 6))
        if os.path.exists(gif_path):
            img = Image.open(gif_path)
            for frame in ImageSequence.Iterator(img):
                f = frame.copy().convert("RGBA")
                f.thumbnail((120, 120))
                self._conn_gif_frames.append(ImageTk.PhotoImage(f))
            self._conn_animate(0)

        self._conn_status = ctk.CTkLabel(self._conn_dlg, text="Checking network...",
                                         font=ctk.CTkFont(
                                             size=13, weight="bold"),
                                         text_color=PALETTE["warning"])
        self._conn_status.pack(pady=6)

        self._conn_detail = ctk.CTkLabel(self._conn_dlg, text="",
                                         font=ctk.CTkFont(size=11), text_color=PALETTE["muted"],
                                         wraplength=320)
        self._conn_detail.pack(pady=2)

        btn_row = ctk.CTkFrame(self._conn_dlg, fg_color="transparent")
        btn_row.pack(pady=14)

        self._conn_retry_btn = ctk.CTkButton(btn_row, text="Retry",
                                             fg_color=PALETTE["primary"],
                                             hover_color=PALETTE["primary_hover"],
                                             state="disabled",
                                             command=self._retry_connection)
        self._conn_retry_btn.grid(row=0, column=0, padx=6)

        self._conn_explore_btn = ctk.CTkButton(btn_row, text="Open \\\\10.50.93.5 in Explorer",
                                               fg_color=PALETTE["surface"],
                                               text_color=PALETTE["text"],
                                               border_width=1, border_color=PALETTE["border"],
                                               hover_color=PALETTE["sidebar_hover"],
                                               state="disabled",
                                               command=self._open_explorer_unc)
        self._conn_explore_btn.grid(row=0, column=1, padx=6)

        # Start check in background
        threading.Thread(target=self._do_connection_check, daemon=True).start()

    def _conn_animate(self, idx):
        if not self._conn_gif_frames:
            return
        self._conn_gif_label.configure(image=self._conn_gif_frames[idx])
        self._conn_gif_job = self._conn_dlg.after(
            50, self._conn_animate, (idx + 1) % len(self._conn_gif_frames))

    def _do_connection_check(self):
        status = self.logic.check_connection()
        self.after(0, lambda: self._handle_connection_result(status))

    def _handle_connection_result(self, status):
        if status["is_debs"] and status["server_ok"]:
            # All good — dismiss and load
            self._dismiss_conn_dlg()
            self._post_connection_ready(status)
        else:
            # Show problem and enable retry
            if not status["connected"]:
                msg = "No WiFi connection detected."
                detail = "Please connect to the DEBS corporate WiFi network."
            elif not status["is_debs"]:
                msg = f"Connected to '{status['ssid']}' — not DEBS WiFi."
                detail = "Please switch to the Debswana corporate WiFi (DEBS) network."
            else:
                msg = "DEBS WiFi connected but server unreachable."
                detail = (f"Cannot reach \\\\10.50.93.5.\n"
                          "Try opening the server in Explorer to authenticate, then retry.")
            self._conn_status.configure(text=msg, text_color=PALETTE["danger"])
            self._conn_detail.configure(text=detail)
            self._conn_retry_btn.configure(state="normal")
            self._conn_explore_btn.configure(state="normal")

    def _retry_connection(self):
        self._conn_status.configure(
            text="Checking network...", text_color=PALETTE["warning"])
        self._conn_detail.configure(text="")
        self._conn_retry_btn.configure(state="disabled")
        self._conn_explore_btn.configure(state="disabled")
        threading.Thread(target=self._do_connection_check, daemon=True).start()

    def _open_explorer_unc(self):
        self.logic.open_server_in_explorer()

    def _dismiss_conn_dlg(self):
        if self._conn_gif_job:
            try:
                self._conn_dlg.after_cancel(self._conn_gif_job)
            except Exception:
                pass
        self._conn_gif_frames = []
        try:
            self._conn_dlg.grab_release()
            self._conn_dlg.destroy()
        except Exception:
            pass

    def _post_connection_ready(self, status):
        """Called after successful connection check — load apps and set up UI."""
        self.update_wifi_status(status)
        threading.Thread(target=self._load_and_render, daemon=True).start()

    def _load_and_render(self):
        self.logic.load_apps()
        self.after(0, self.render_apps)

    # ── Icons ──────────────────────────────────────────────────────────────
    def _load_icons(self):
        icons = {}
        for name, filename in ICON_FILES.items():
            p = resource_path(os.path.join("assets", filename))
            if os.path.exists(p):
                img = Image.open(p)
                icons[name] = ctk.CTkImage(
                    light_image=img, dark_image=img, size=(18, 18))
        return icons

    def icon(self, name):
        return self.icons.get(name)

    # ── Sidebar ────────────────────────────────────────────────────────────
    def _build_sidebar(self):
        self.sidebar_frame = ctk.CTkFrame(self, width=180, corner_radius=18,
                                          fg_color=PALETTE["surface"],
                                          border_width=1, border_color=PALETTE["border"])
        self.sidebar_frame.grid(row=0, column=0, padx=(
            10, 0), pady=10, sticky="nsew")
        self.sidebar_frame.grid_rowconfigure(8, weight=1)

        self.category_buttons = []
        categories = ["All", "Standard", "Mining",
                      "Oil Processing", "IM", "Uninstallers"]
        for i, cat in enumerate(categories):
            btn = ctk.CTkButton(
                self.sidebar_frame, text=cat, corner_radius=10, height=34,
                border_spacing=8, fg_color="transparent", text_color=PALETTE["text"],
                hover_color=PALETTE["sidebar_hover"],
                image=self.icon(CATEGORY_ICONS[cat]), compound="left", anchor="w",
                command=lambda c=cat: self.select_category(c)
            )
            btn.grid(row=i, column=0, padx=8, pady=(
                8 if i == 0 else 2, 2), sticky="ew")
            self.category_buttons.append(btn)

        self.selected_category = "All"
        self.select_category("All")

        # Separator
        ctk.CTkFrame(self.sidebar_frame, height=1, fg_color=PALETTE["border"]).grid(
            row=6, column=0, padx=12, pady=8, sticky="ew")

        # Quick Tools
        self._proxy_enabled = None
        self.proxy_btn = None  # managed inside quick tools popup
        ctk.CTkButton(
            self.sidebar_frame, text=" Quick Tools", height=30, corner_radius=8,
            fg_color=PALETTE["surface"], text_color=PALETTE["text"],
            hover_color=PALETTE["sidebar_hover"],
            border_width=1, border_color=PALETTE["border"],
            image=self.icon("wrench"), compound="left",
            anchor="w", command=self._open_quick_tools
        ).grid(row=7, column=0, padx=8, pady=(0, 4), sticky="ew")
        threading.Thread(target=self._refresh_proxy_status,
                         daemon=True).start()

        # About
        ctk.CTkButton(
            self.sidebar_frame, text=" About", height=30, corner_radius=8,
            fg_color=PALETTE["surface"], text_color=PALETTE["text"],
            hover_color=PALETTE["sidebar_hover"],
            border_width=1, border_color=PALETTE["border"],
            image=self.icon("info"), compound="left",
            anchor="w", command=self._open_about
        ).grid(row=8, column=0, padx=8, pady=(0, 8), sticky="ew")

        # Shortcuts hint (compact)
        hints_frame = ctk.CTkFrame(self.sidebar_frame, fg_color=PALETTE["surface_alt"],
                                   corner_radius=8, border_width=1, border_color=PALETTE["border"])
        hints_frame.grid(row=9, column=0, padx=8, pady=(0, 6), sticky="ew")
        for r, (key, desc) in enumerate([
            ("Ctrl+F", "Search"), ("Ctrl+A", "Add App"),
            ("↑↓ / Enter", "Navigate"), ("Ctrl+I", "About"),
            ("Ctrl+R", "Rename PC"), ("Ctrl+L", "Installed Apps"),
            ("Ctrl+W", "Close"),
        ]):
            ctk.CTkLabel(hints_frame, text=key, font=ctk.CTkFont(size=10, weight="bold"),
                         text_color=PALETTE["primary"]).grid(row=r, column=0, padx=(8, 4), pady=1, sticky="w")
            ctk.CTkLabel(hints_frame, text=desc, font=ctk.CTkFont(size=10),
                         text_color=PALETTE["muted"]).grid(row=r, column=1, padx=(0, 8), pady=1, sticky="w")

        # GIF slot
        self._gif_frames = []
        self._gif_job = None
        self.gif_label = ctk.CTkLabel(self.sidebar_frame, text="")
        self.gif_label.grid(row=10, column=0, padx=14, pady=(0, 4))
        self.gif_label.grid_remove()

        # Logo
        logo_file = resource_path("image.png")
        if os.path.exists(logo_file):
            try:
                logo_img = Image.open(logo_file)
                w, h = logo_img.size
                self.sidebar_logo = ctk.CTkImage(light_image=logo_img, dark_image=logo_img,
                                                 size=(140, int(140 * h / w)))
                ctk.CTkLabel(self.sidebar_frame, image=self.sidebar_logo, text="").grid(
                    row=11, column=0, padx=14, pady=14)
            except Exception as e:
                print(f"Error loading logo: {e}")

    # ── Main panel ─────────────────────────────────────────────────────────
    def _build_main(self):
        self.main_frame = ctk.CTkFrame(
            self, corner_radius=18, fg_color=PALETTE["surface_alt"])
        self.main_frame.grid(row=0, column=1, padx=10, pady=10, sticky="nsew")
        self.main_frame.grid_columnconfigure(0, weight=1)
        self.main_frame.grid_rowconfigure(2, weight=1)

        # Header
        hdr = ctk.CTkFrame(self.main_frame, height=72,
                           corner_radius=16, fg_color=PALETTE["primary"])
        hdr.grid(row=0, column=0, padx=8, pady=8, sticky="ew")
        hdr.grid_columnconfigure(0, weight=1)
        ctk.CTkLabel(hdr, text="Debswana Software Kit", text_color="white",
                     font=ctk.CTkFont(size=22, weight="bold")).grid(row=0, column=0, padx=14, pady=14, sticky="w")
        self.wifi_status_label = ctk.CTkLabel(hdr, text="Checking connection...",
                                              text_color="white", font=ctk.CTkFont(weight="bold"))
        self.wifi_status_label.grid(
            row=0, column=1, padx=14, pady=14, sticky="e")

        # Actions row
        action = ctk.CTkFrame(self.main_frame, fg_color="transparent")
        action.grid(row=1, column=0, padx=14, pady=4, sticky="ew")

        ctk.CTkLabel(action, image=self.icon("search"),
                     text="").grid(row=0, column=0, padx=(0, 6))
        self.search_entry = ctk.CTkEntry(action, placeholder_text="Search applications...",
                                         width=350, fg_color=PALETTE["surface"],
                                         border_color=PALETTE["border"], text_color=PALETTE["text"])
        self.search_entry.grid(row=0, column=1, padx=(0, 12), pady=6)
        self.search_entry.bind(
            "<KeyRelease>", lambda e: self._on_search_change())

        btn_cfg = dict(fg_color=PALETTE["primary"],
                       hover_color=PALETTE["primary_hover"])
        self.install_all_btn = ctk.CTkButton(action, text="Install All Standard",
                                             image=self.icon("package_plus"), compound="left",
                                             command=self.show_install_all_dialog, **btn_cfg)
        self.install_all_btn.grid(row=0, column=2, padx=6, pady=6)

        self.add_app_btn = ctk.CTkButton(action, text="Add App", image=self.icon("plus"),
                                         compound="left", fg_color=PALETTE["surface"],
                                         text_color=PALETTE["text"], hover_color=PALETTE["sidebar_hover"],
                                         border_width=1, border_color=PALETTE["border"],
                                         command=self.show_add_app_dialog)
        self.add_app_btn.grid(row=0, column=3, padx=6, pady=6)

        # Dashboard
        self.dashboard_frame = ctk.CTkScrollableFrame(
            self.main_frame, fg_color="transparent")
        self.dashboard_frame.grid(
            row=2, column=0, padx=14, pady=6, sticky="nsew")
        self.dashboard_frame.grid_columnconfigure((0, 1), weight=1)

        # Status bar
        status_frame = ctk.CTkFrame(
            self.main_frame, height=52, corner_radius=0, fg_color="transparent")
        status_frame.grid(row=3, column=0, padx=14, pady=(0, 6), sticky="ew")
        self.status_label = ctk.CTkLabel(
            status_frame, text="Ready.", font=ctk.CTkFont(size=11, weight="bold"),
            text_color="white", fg_color="transparent")
        self.status_label.place(x=2, y=0)
        self.progress_bar = ctk.CTkProgressBar(
            status_frame, width=680, height=10, corner_radius=4,
            fg_color="#2e2e2e", border_color="#555", border_width=1,
            progress_color="#E8A020")
        self.set_progress(0)
        self.progress_bar.place(x=0, y=20)
        self.progress_bar.place_forget()

    # ── App close ──────────────────────────────────────────────────────────
    def _on_close(self):
        try:
            self._dismiss_conn_dlg()
        except Exception:
            pass
        self.destroy()

    # ── Keyboard shortcuts ─────────────────────────────────────────────────
    def _bind_shortcuts(self):
        self.bind_all("<Control-f>", lambda e: self._focus_search())
        self.bind_all("<Control-F>", lambda e: self._focus_search())
        self.bind_all("<Control-w>", lambda e: self._on_close())
        self.bind_all("<Control-W>", lambda e: self._on_close())
        self.bind_all("<Control-a>", lambda e: self.show_add_app_dialog())
        self.bind_all("<Control-A>", lambda e: self.show_add_app_dialog())
        self.bind_all("<Control-i>", lambda e: self._open_about())
        self.bind_all("<Control-I>", lambda e: self._open_about())
        self.bind_all(
            "<Control-r>", lambda e: subprocess.Popen("ms-settings:about", shell=True))
        self.bind_all(
            "<Control-R>", lambda e: subprocess.Popen("ms-settings:about", shell=True))
        self.bind_all(
            "<Control-l>", lambda e: subprocess.Popen("appwiz.cpl", shell=True))
        self.bind_all(
            "<Control-L>", lambda e: subprocess.Popen("appwiz.cpl", shell=True))
        self.bind_all("<Up>", lambda e: self._move_selection(-1))
        self.bind_all("<Down>", lambda e: self._move_selection(1))
        self.bind_all("<Return>", lambda e: self._install_selected())

    def _focus_search(self):
        self.search_entry.focus_set()

    def _on_search_change(self):
        self._selected_index = -1
        self.render_apps()

    def _move_selection(self, delta):
        if not self._filtered_apps:
            return
        self._selected_index = max(0, min(len(self._filtered_apps) - 1,
                                          self._selected_index + delta))
        self.render_apps()

    def _install_selected(self):
        # Don't fire if user is typing in an entry widget
        focused = self.focus_get()
        if isinstance(focused, (ctk.CTkEntry, tk.Entry)):
            return
        if 0 <= self._selected_index < len(self._filtered_apps):
            self.install_thread(self._filtered_apps[self._selected_index])

    # ── GIF helpers ────────────────────────────────────────────────────────
    def show_gif(self, gif_name):
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
        if self._gif_frames:
            self.gif_label.grid()
            self._animate_gif(0)

    def _animate_gif(self, idx):
        if not self._gif_frames:
            return
        self.gif_label.configure(image=self._gif_frames[idx])
        self._gif_job = self.after(
            50, self._animate_gif, (idx + 1) % len(self._gif_frames))

    def hide_gif(self):
        if self._gif_job:
            self.after_cancel(self._gif_job)
            self._gif_job = None
        self.gif_label.grid_remove()
        self._gif_frames = []

    # ── Category ───────────────────────────────────────────────────────────
    def select_category(self, category):
        self.selected_category = category
        for btn in self.category_buttons:
            cat = btn.cget("text").strip()
            icon_name = CATEGORY_ICONS[cat]
            if cat == category:
                btn.configure(fg_color=PALETTE["primary"], text_color="white",
                              hover_color=PALETTE["primary_hover"],
                              image=self.icon(f"{icon_name}_active"),
                              font=ctk.CTkFont(weight="bold"))
            else:
                btn.configure(fg_color="transparent", text_color=PALETTE["text"],
                              hover_color=PALETTE["sidebar_hover"],
                              image=self.icon(icon_name),
                              font=ctk.CTkFont(weight="normal"))
        if hasattr(self, 'dashboard_frame'):
            self._selected_index = -1
            self.render_apps()

    # ── WiFi header label ──────────────────────────────────────────────────
    def update_wifi_status(self, status):
        if status.get("is_debs") and status.get("server_ok"):
            self.wifi_status_label.configure(
                image=self.icon("wifi"), compound="left",
                text=f"● DEBS Connected ({status['ssid']})", text_color="#90EE90")
        elif status.get("is_debs"):
            self.wifi_status_label.configure(
                image=self.icon("warning"), compound="left",
                text=f"● DEBS WiFi — server unreachable", text_color="#FFB6C1")
        elif status.get("connected"):
            self.wifi_status_label.configure(
                image=self.icon("warning"), compound="left",
                text=f"● {status['ssid']} (Not DEBS)", text_color="#FFB6C1")
        else:
            self.wifi_status_label.configure(
                image=self.icon("wifi_off"), compound="left",
                text="● Not Connected", text_color="#FF6347")

    # ── Render ─────────────────────────────────────────────────────────────
    def render_apps(self):
        if threading.current_thread() != threading.main_thread():
            self.after(0, self.render_apps)
            return

        search = self.search_entry.get().lower()
        apps = self.logic.apps
        if self.selected_category != "All":
            apps = [a for a in apps if a.get(
                "category") == self.selected_category]
        if search:
            apps = [a for a in apps if search in a.get("name", "").lower()
                    or search in a.get("category", "").lower()]

        new_keys = [id(a) for a in apps]

        if new_keys != self._rendered_keys:
            # List changed — full rebuild
            for w in self.dashboard_frame.winfo_children():
                w.destroy()
            self._card_widgets = {}
            self._filtered_apps = apps
            self._rendered_keys = new_keys
            for i, app in enumerate(apps):
                self._create_app_card(
                    app, i, selected=(i == self._selected_index))
        else:
            # Only selection changed — recolor in place
            self._filtered_apps = apps
            prev_sel = getattr(self, "_prev_selected_index", -2)
            for idx in {prev_sel, self._selected_index}:
                card = self._card_widgets.get(idx)
                if card is None:
                    continue
                selected = (idx == self._selected_index)
                app = apps[idx]
                cat = app.get("category", "")
                bg = PALETTE["primary"] if selected else CATEGORY_COLORS.get(
                    cat, PALETTE["surface"])
                txt_color = "white" if selected else PALETTE["text"]
                muted_color = "#c8d7e6" if selected else PALETTE["muted"]
                bw = 2 if selected else 1
                bc = PALETTE["primary"] if selected else PALETTE["border"]
                card.configure(fg_color=bg, border_width=bw, border_color=bc)
                children = card.winfo_children()
                # name label, category label, install button
                if len(children) >= 2:
                    children[0].configure(text_color=txt_color)
                    children[1].configure(text_color=muted_color)

        self._prev_selected_index = self._selected_index

    def _create_app_card(self, app, index, selected=False):
        row, col = divmod(index, 2)
        cat = app.get("category", "")
        bg = PALETTE["primary"] if selected else CATEGORY_COLORS.get(
            cat, PALETTE["surface"])
        txt_color = "white" if selected else PALETTE["text"]
        muted_color = "#c8d7e6" if selected else PALETTE["muted"]

        card = ctk.CTkFrame(self.dashboard_frame, height=64, corner_radius=8,
                            border_width=2 if selected else 1,
                            border_color=PALETTE["primary"] if selected else PALETTE["border"],
                            fg_color=bg)
        card.grid(row=row, column=col, padx=6, pady=6, sticky="ew")
        card.grid_columnconfigure(0, weight=1)
        self._card_widgets[index] = card

        name_lbl = ctk.CTkLabel(card, text=app.get("name", ""),
                                font=ctk.CTkFont(size=13, weight="bold"), text_color=txt_color)
        name_lbl.grid(row=0, column=0, padx=10, pady=(7, 0), sticky="w")

        ctk.CTkLabel(card, text=cat, font=ctk.CTkFont(size=11),
                     text_color=muted_color).grid(row=1, column=0, padx=10, pady=(0, 7), sticky="w")

        ctk.CTkButton(card, text="Install", image=self.icon("download"), compound="left",
                      width=98, height=28,
                      fg_color=PALETTE["primary"], hover_color=PALETTE["primary_hover"],
                      command=lambda a=app: self.install_thread(a)).grid(
                          row=0, column=1, rowspan=2, padx=10, pady=7)

        # Click to select
        def on_click(e, idx=index):
            self._selected_index = idx
            self.render_apps()

        def on_right_click(e, a=app):
            self._show_card_menu(e, a)

        for w in (card, name_lbl):
            w.bind("<Button-1>", on_click)
            w.bind("<Button-3>", on_right_click)

    # ── Card context menu ──────────────────────────────────────────────────
    def _show_card_menu(self, event, app):
        menu = tk.Menu(self, tearoff=0, bg=PALETTE["surface"], fg=PALETTE["text"],
                       activebackground=PALETTE["sidebar_hover"], activeforeground=PALETTE["text"],
                       relief="flat", bd=1)
        menu.add_command(label="📂  Open Path",
                         command=lambda: self._open_app_path(app))
        menu.add_separator()
        menu.add_command(
            label="✏  Edit", command=lambda: self._edit_app_dialog(app))
        menu.tk_popup(event.x_root, event.y_root)

    def _open_app_path(self, app):
        path = app.get("path", "")
        folder = os.path.dirname(path)
        if folder and os.path.exists(folder):
            subprocess.Popen(f'explorer "{folder}"')
        else:
            messagebox.showwarning(
                "Open Path", f"Path not accessible:\n{folder or path}")

    def _edit_app_dialog(self, app):
        dlg = ctk.CTkToplevel(self)
        dlg.title(f"Edit — {app.get('name', '')}")
        dlg.geometry("460x280")
        dlg.grab_set()

        field_defs = [("Name:", "name"), ("Path:", "path"), ("Args:", "args")]
        entries = []
        for r, (lbl, key) in enumerate(field_defs):
            ctk.CTkLabel(dlg, text=lbl).grid(
                row=r, column=0, padx=14, pady=7, sticky="e")
            if key == "path":
                frm = ctk.CTkFrame(dlg, fg_color="transparent")
                frm.grid(row=r, column=1, padx=14, pady=7)
                e = ctk.CTkEntry(frm, width=220)
                e.insert(0, app.get(key, ""))
                e.pack(side="left", padx=(0, 6))

                def browse(entry=e):
                    f = filedialog.askopenfilename()
                    if f:
                        entry.delete(0, "end")
                        entry.insert(0, f)
                ctk.CTkButton(frm, text="Browse", width=70,
                              command=browse).pack(side="left")
            else:
                e = ctk.CTkEntry(dlg, width=300)
                e.insert(0, app.get(key, ""))
                e.grid(row=r, column=1, padx=14, pady=7)
            entries.append(e)

        ctk.CTkLabel(dlg, text="Category:").grid(
            row=3, column=0, padx=14, pady=7, sticky="e")
        cat_combo = ctk.CTkComboBox(dlg, values=[
                                    "Standard", "Mining", "Oil Processing", "IM", "Uninstallers"], width=300)
        cat_combo.set(app.get("category", "Standard"))
        cat_combo.grid(row=3, column=1, padx=14, pady=7)

        def save():
            app["name"] = entries[0].get()
            app["path"] = entries[1].get()
            app["args"] = entries[2].get()
            app["category"] = cat_combo.get()
            self.logic.save_apps()
            self.render_apps()
            dlg.destroy()

        btn_frame = ctk.CTkFrame(dlg, fg_color="transparent")
        btn_frame.grid(row=4, column=0, columnspan=2, pady=12)

        ctk.CTkButton(btn_frame, text="Save", command=save,
                      fg_color=PALETTE["primary"], hover_color=PALETTE["primary_hover"]).pack(side="left", padx=(0, 6))

        def delete_entry():
            if messagebox.askyesno("Delete", f"Delete '{app.get('name','this entry')}'?"):
                try:
                    self.logic.delete_app(app)
                except Exception:
                    pass
                self.render_apps()
                dlg.destroy()

        ctk.CTkButton(btn_frame, text="Delete", command=delete_entry,
                      fg_color=PALETTE["danger"], text_color="white").pack(side="left")

        dlg.bind("<Return>", lambda e: save())

    # ── Install ────────────────────────────────────────────────────────────
    def install_thread(self, app):
        threading.Thread(target=self._run_install,
                         args=(app,), daemon=True).start()

    def _run_install(self, app):
        self.after(0, lambda: self.progress_bar.place(x=0, y=20))
        self.set_progress(0.15)
        self.install_all_btn.configure(state="disabled")
        self.after(0, lambda: self.show_gif("file-transfer"))
        success = self.logic.install_app(
            app, status_callback=self.update_status)
        self.install_all_btn.configure(state="normal")
        if success:
            self.set_progress(1.0)
            self.after(0, lambda: self.show_gif("animated-download"))
            self.after(2500, self.hide_gif)
            self.after(2500, lambda: self._reset_progress())
        elif "cancelled" in (self.status_label.cget("text") or "").lower():
            # User cancelled the copy dialog — reset quietly
            self.after(0, self._reset_progress)
            self.after(0, self.hide_gif)
        else:
            self.set_progress(0)
            self.after(0, lambda: self.show_gif("error-animation"))
            self.after(3000, self.hide_gif)
            self.after(0, lambda: messagebox.showerror(
                "Installation Failed",
                f"Could not install {app.get('name', 'app')}.\n\nCheck your network or contact IT support."))

    def _reset_progress(self):
        self.set_progress(0)
        self.progress_bar.place_forget()
        self.update_status("Ready.", "white")

    # ── Bulk install ───────────────────────────────────────────────────────
    def show_install_all_dialog(self):
        standard = [a for a in self.logic.apps if a.get(
            "category") == "Standard"]
        if not standard:
            messagebox.showinfo("Info", "No standard applications found.")
            return

        dlg = ctk.CTkToplevel(self)
        dlg.title("Select Applications to Install")
        dlg.geometry("700x560")
        dlg.grab_set()

        ctk.CTkLabel(dlg, text="Select applications to install:",
                     font=ctk.CTkFont(size=15, weight="bold")).pack(pady=14)

        scroll = ctk.CTkScrollableFrame(dlg, width=620, height=350)
        scroll.pack(padx=14, pady=6)

        checkboxes = []
        for app in standard:
            var = tk.BooleanVar(value=True)
            ctk.CTkCheckBox(
                scroll, text=f"{app['name']} - {app['category']}", variable=var).pack(anchor="w", padx=14, pady=3)
            checkboxes.append((app, var))

        btn_row = ctk.CTkFrame(dlg, fg_color="transparent")
        btn_row.pack(pady=8)
        ctk.CTkButton(btn_row, text="Select All", command=lambda: [
                      v.set(True) for _, v in checkboxes]).grid(row=0, column=0, padx=6)
        ctk.CTkButton(btn_row, text="Deselect All", command=lambda: [
                      v.set(False) for _, v in checkboxes]).grid(row=0, column=1, padx=6)

        def start():
            selected = [a for a, v in checkboxes if v.get()]
            if not selected:
                messagebox.showwarning(
                    "No Selection", "Please select at least one application.")
                return
            dlg.destroy()
            threading.Thread(target=self._run_bulk_install,
                             args=(selected,), daemon=True).start()

        ctk.CTkButton(dlg, text="Install Selected",
                      fg_color=PALETTE["primary"], hover_color=PALETTE["primary_hover"],
                      command=start).pack(pady=6)

    def _run_bulk_install(self, apps):
        total = len(apps)
        self.install_all_btn.configure(state="disabled")
        self.after(0, lambda: self.progress_bar.place(x=0, y=20))
        self.after(0, lambda: self.show_gif("file-transfer"))
        failed = []
        for i, app in enumerate(apps):
            self.update_status(
                f"Installing ({i+1}/{total}): {app['name']}...", "orange")
            self.set_progress((i + 1) / total)
            if not self.logic.install_app(app, status_callback=self.update_status):
                failed.append(app['name'])
        self.after(0, self.render_apps)
        self.install_all_btn.configure(state="normal")
        if failed:
            self.after(0, lambda: self.show_gif("error-animation"))
            self.after(3000, self.hide_gif)
            self.after(3000, self._reset_progress)
            self.after(0, lambda: messagebox.showwarning(
                "Some Installations Failed",
                f"{len(failed)} app(s) failed:\n\n" + "\n".join(f"• {n}" for n in failed)))
        else:
            self.after(0, lambda: self.show_gif("animated-download"))
            self.after(2500, self.hide_gif)
            self.after(2500, self._reset_progress)
            self.update_status(
                f"Installation complete! ({total} applications)", "green")

    # ── Add App ────────────────────────────────────────────────────────────
    def show_add_app_dialog(self):
        dlg = ctk.CTkToplevel(self)
        dlg.title("Add Application")
        dlg.geometry("460x280")
        dlg.grab_set()

        fields = [("Name:", None), ("Path:", None), ("Args:", None)]
        entries = []
        for r, (lbl, _) in enumerate(fields):
            ctk.CTkLabel(dlg, text=lbl).grid(
                row=r, column=0, padx=14, pady=7, sticky="e")
            if lbl == "Path:":
                frm = ctk.CTkFrame(dlg, fg_color="transparent")
                frm.grid(row=r, column=1, padx=14, pady=7)
                e = ctk.CTkEntry(frm, width=220)
                e.pack(side="left", padx=(0, 6))

                def browse(entry=e):
                    f = filedialog.askopenfilename()
                    if f:
                        entry.delete(0, "end")
                        entry.insert(0, f)
                ctk.CTkButton(frm, text="Browse", width=70,
                              command=browse).pack(side="left")
            else:
                e = ctk.CTkEntry(dlg, width=300)
                e.grid(row=r, column=1, padx=14, pady=7)
            entries.append(e)

        ctk.CTkLabel(dlg, text="Category:").grid(
            row=3, column=0, padx=14, pady=7, sticky="e")
        cat_combo = ctk.CTkComboBox(dlg, values=[
                                    "Standard", "Mining", "Oil Processing", "IM", "Uninstallers"], width=300)
        cat_combo.grid(row=3, column=1, padx=14, pady=7)
        cat_combo.set("Standard")

        def save():
            self.logic.add_app(entries[0].get(), entries[1].get(
            ), entries[2].get(), "", cat_combo.get())
            self.render_apps()
            dlg.destroy()

        ctk.CTkButton(dlg, text="Save", command=save,
                      fg_color=PALETTE["primary"], hover_color=PALETTE["primary_hover"]).grid(
                          row=4, column=0, columnspan=2, pady=12)

        # Bind Enter in dialog to save
        dlg.bind("<Return>", lambda e: save())

    # ── Proxy toggle ───────────────────────────────────────────────────────
    def _refresh_proxy_status(self):
        try:
            out = subprocess.check_output(
                ["reg", "query",
                 r"HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings",
                 "/v", "ProxyEnable"],
                stderr=subprocess.STDOUT, universal_newlines=True,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            enabled = "0x1" in out
        except Exception:
            enabled = False
        self._proxy_enabled = enabled
        self.after(0, self._update_proxy_btn)

    def _update_proxy_btn(self):
        btn = getattr(self, "qt_proxy_btn", None)
        if btn is None:
            return
        if self._proxy_enabled:
            btn.configure(text="⚙ Proxy: ON", fg_color="#1f7a4d",
                          text_color="white", hover_color="#165c38", border_color="#1f7a4d")
        else:
            btn.configure(text="⚙ Proxy: OFF", fg_color=PALETTE["surface"],
                          text_color=PALETTE["text"], hover_color=PALETTE["sidebar_hover"],
                          border_color=PALETTE["border"])

    def _toggle_proxy(self):
        threading.Thread(target=self._do_toggle_proxy, daemon=True).start()

    def _do_toggle_proxy(self):
        try:
            if self._proxy_enabled:
                subprocess.check_call(
                    ["reg", "add",
                     r"HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings",
                     "/v", "ProxyEnable", "/t", "REG_DWORD", "/d", "0", "/f"],
                    creationflags=subprocess.CREATE_NO_WINDOW)
                self._proxy_enabled = False
            else:
                cmds = [
                    ["reg", "add",
                     r"HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings",
                     "/v", "ProxyEnable", "/t", "REG_DWORD", "/d", "1", "/f"],
                    ["reg", "add",
                     r"HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings",
                     "/v", "ProxyServer", "/t", "REG_SZ", "/d", "10.176.40.29:80", "/f"],
                    ["reg", "add",
                     r"HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings",
                     "/v", "ProxyOverride", "/t", "REG_SZ",
                     "/d", "activation-v2.sls.microsoft.com;*.microsoft.com;*.windowsupdate.com", "/f"],
                ]
                for cmd in cmds:
                    subprocess.check_call(
                        cmd, creationflags=subprocess.CREATE_NO_WINDOW)
                self._proxy_enabled = True
            self.after(0, self._update_proxy_btn)
        except Exception as e:
            self.after(0, lambda: messagebox.showerror("Proxy Error", str(e)))

    # ── About popup ────────────────────────────────────────────────────────
    def _open_about(self):
        dlg = ctk.CTkToplevel(self)
        dlg.title("About")
        dlg.geometry("380x450")
        dlg.resizable(False, False)
        dlg.grab_set()
        dlg.focus_force()

        logo_file = resource_path("image.png")
        if os.path.exists(logo_file):
            try:
                img = Image.open(logo_file)
                logo = ctk.CTkImage(
                    light_image=img, dark_image=img, size=(90, 90))
                ctk.CTkLabel(dlg, image=logo, text="").pack(pady=(18, 4))
            except Exception:
                pass

        ctk.CTkLabel(dlg, text="Debswana Software Kit",
                     font=ctk.CTkFont(size=16, weight="bold"),
                     text_color=PALETTE["primary"]).pack(pady=(0, 2))
        ctk.CTkLabel(dlg, text="Made by Desiree Chingwaru & Odirile Mathepeo",
                     font=ctk.CTkFont(size=11), text_color=PALETTE["muted"]).pack(pady=(0, 2))
        ctk.CTkLabel(dlg, text="Debswana IT Department",
                     font=ctk.CTkFont(size=11), text_color=PALETTE["muted"]).pack(pady=(0, 12))

        sep = ctk.CTkFrame(dlg, height=1, fg_color=PALETTE["border"])
        sep.pack(fill="x", padx=20, pady=(0, 10))

        shortcuts = [
            ("Ctrl+F", "Search"), ("Ctrl+A", "Add App"),
            ("Ctrl+I", "About"), ("Ctrl+R", "Rename PC"),
            ("Ctrl+L", "Installed Apps"), ("Ctrl+W", "Close"),
            ("↑↓ / Enter", "Navigate"),
        ]
        grid = ctk.CTkFrame(dlg, fg_color="transparent")
        grid.pack(padx=30, pady=(0, 16), fill="x")
        for r, (key, desc) in enumerate(shortcuts):
            ctk.CTkLabel(grid, text=key, font=ctk.CTkFont(size=11, weight="bold"),
                         text_color=PALETTE["primary"]).grid(row=r, column=0, sticky="w", pady=2, padx=(0, 16))
            ctk.CTkLabel(grid, text=desc, font=ctk.CTkFont(size=11),
                         text_color=PALETTE["text"]).grid(row=r, column=1, sticky="w", pady=2)

        ctk.CTkButton(dlg, text="Close", width=100,
                      fg_color=PALETTE["primary"], hover_color=PALETTE["primary_hover"],
                      command=dlg.destroy).pack(pady=(0, 16))

    # ── Quick Tools popup ──────────────────────────────────────────────────
    def _open_quick_tools(self):
        dlg = ctk.CTkToplevel(self)
        dlg.title("Quick Tools")
        dlg.geometry("280x200")
        dlg.resizable(False, False)
        dlg.grab_set()
        dlg.focus_force()

        ctk.CTkLabel(dlg, text="Quick Tools",
                     font=ctk.CTkFont(size=14, weight="bold"),
                     text_color=PALETTE["primary"]).pack(pady=(14, 8))

        btn_cfg = dict(height=34, corner_radius=8, border_width=1,
                       border_color=PALETTE["border"], anchor="w",
                       fg_color=PALETTE["surface"], text_color=PALETTE["text"],
                       hover_color=PALETTE["sidebar_hover"])

        # Proxy button (live state)
        proxy_label = "⚙ Proxy: ON" if self._proxy_enabled else "⚙ Proxy: OFF"
        proxy_fg = "#1f7a4d" if self._proxy_enabled else PALETTE["surface"]
        proxy_tc = "white" if self._proxy_enabled else PALETTE["text"]
        proxy_hc = "#165c38" if self._proxy_enabled else PALETTE["sidebar_hover"]
        proxy_bc = "#1f7a4d" if self._proxy_enabled else PALETTE["border"]

        self.qt_proxy_btn = ctk.CTkButton(
            dlg, text=proxy_label, fg_color=proxy_fg, text_color=proxy_tc,
            hover_color=proxy_hc, border_color=proxy_bc,
            height=34, corner_radius=8, border_width=1, anchor="w",
            command=self._toggle_proxy)
        self.qt_proxy_btn.pack(fill="x", padx=16, pady=(0, 4))

        ctk.CTkButton(dlg, text=" Rename this PC  (Ctrl+R)",
                      image=self.icon("computer"), compound="left",
                      command=lambda: subprocess.Popen(
                          "ms-settings:about", shell=True),
                      **btn_cfg).pack(fill="x", padx=16, pady=(0, 4))

        ctk.CTkButton(dlg, text=" Installed Apps  (Ctrl+L)",
                      image=self.icon("wrench"), compound="left",
                      command=lambda: subprocess.Popen(
                          "appwiz.cpl", shell=True),
                      **btn_cfg).pack(fill="x", padx=16, pady=(0, 4))

    # ── Status ─────────────────────────────────────────────────────────────
    def set_progress(self, value):
        """
        Set progress and adjust color when idle (value == 0) vs active (>0).
        """
        try:
            color = PALETTE["muted"] if value == 0 else PALETTE["primary"]
            try:
                self.progress_bar.configure(progress_color=color)
            except Exception:
                pass
            self.progress_bar.set(value)
        except Exception:
            pass

    def update_status(self, message, color="white"):
        if threading.current_thread() != threading.main_thread():
            self.after(0, lambda: self.update_status(message, color))
            return
        color_map = {"orange": PALETTE["warning"], "red": PALETTE["danger"],
                     "green": PALETTE["success"], "white": PALETTE["text"]}
        self.status_label.configure(
            text=message, text_color=color_map.get(color, PALETTE["text"]))
        if "completed" in message.lower():
            self.set_progress(1.0)


if __name__ == "__main__":
    REQUIRE_ADMIN = False  # set to True to enable UAC elevation prompt

    if REQUIRE_ADMIN:
        import ctypes
        if not ctypes.windll.shell32.IsUserAnAdmin():
            ctypes.windll.shell32.ShellExecuteW(
                None, "runas", sys.executable, " ".join(sys.argv), None, 1)
            sys.exit()

    app = DesireeSoftwareCenter()
    app.mainloop()
