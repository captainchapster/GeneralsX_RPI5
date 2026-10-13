#!/usr/bin/env python3
# GeneralsX @build rpi5 12/10/2026
# Setup wizard for Command & Conquer Generals Zero Hour on the Raspberry Pi 5.
#
# A classic Back/Next installer (GTK 3, so it follows the desktop theme) that drives
# install-pi5-zh.sh next to it: it finds or asks for the game folders, installs the system
# components with the user's password when needed, copies everything with a progress bar and
# offers to start the game. The Setup script in the package opens it.
#
# Usage:
#   ./setup-pi5-zh.py              install or update
#   ./setup-pi5-zh.py --uninstall  remove the game program, launcher and shortcuts
import html
import os
import platform
import signal
import subprocess
import sys
import threading

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
INSTALLER = os.path.join(HERE, "install-pi5-zh.sh")
ICON = os.path.join(HERE, "generalsx-zh.png")
LICENSE = os.path.join(HERE, "LICENSE.txt")
README = os.path.join(HERE, "README-PI5.txt")
HOME = os.path.expanduser("~")
BASE_DIR = os.path.join(HOME, "GeneralsX")
ZH_DIR = os.path.join(BASE_DIR, "GeneralsZH")
GENERALS_DIR = os.path.join(BASE_DIR, "Generals")
LOG_FILE = os.path.join(BASE_DIR, "logs", "setup.log")
LAUNCHER = os.path.join(HOME, ".local", "bin", "generalsx-zh")

PRODUCT = "Command & Conquer Generals Zero Hour"
TITLE = PRODUCT + " Setup"

CSS = b"""
.wizard-page { background-color: @theme_base_color; }
.wizard-header { background-color: @theme_base_color; padding: 10px 14px; }
.wizard-banner { background-image: linear-gradient(to bottom, #0a246a, #3a6ea5); }
.wizard-banner label { color: #ffffff; }
"""


def esc(text):
    return GLib.markup_escape_text(text)


def has_file(folder, name):
    try:
        return any(entry.lower() == name.lower() for entry in os.listdir(folder))
    except OSError:
        return False


def is_zh_dir(folder):
    return bool(folder) and has_file(folder, "INIZH.big")


def is_generals_dir(folder):
    return bool(folder) and has_file(folder, "INI.big") and not is_zh_dir(folder)


def same_dir(a, b):
    return bool(a) and os.path.realpath(a) == os.path.realpath(b)


def run_installer(*args, env=None):
    result = subprocess.run(["bash", INSTALLER, *args], capture_output=True, text=True, env=env)
    return result.stdout


def sudo_needs_password():
    return subprocess.run(["sudo", "-n", "true"], capture_output=True).returncode != 0


def sudo_password_ok(password):
    result = subprocess.run(["sudo", "-S", "-k", "-p", "", "true"], input=password + "\n",
                            capture_output=True, text=True)
    return result.returncode == 0


def ask(parent, text, secondary):
    dialog = Gtk.MessageDialog(transient_for=parent, modal=True, message_type=Gtk.MessageType.QUESTION,
                               buttons=Gtk.ButtonsType.YES_NO, text=text)
    dialog.format_secondary_text(secondary)
    dialog.set_title(TITLE)
    answer = dialog.run() == Gtk.ResponseType.YES
    dialog.destroy()
    return answer


def tell(parent, text, secondary, kind=Gtk.MessageType.INFO):
    dialog = Gtk.MessageDialog(transient_for=parent, modal=True, message_type=kind,
                               buttons=Gtk.ButtonsType.OK, text=text)
    dialog.format_secondary_text(secondary)
    dialog.set_title(TITLE)
    dialog.run()
    dialog.destroy()


def banner():
    """The blue strip with the game icon on the Welcome and Finish pages."""
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
    box.get_style_context().add_class("wizard-banner")
    box.set_size_request(164, -1)
    if os.path.exists(ICON):
        icon = Gtk.Image.new_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_scale(ICON, 132, 132, True))
        icon.set_margin_top(28)
        box.pack_start(icon, False, False, 0)
    caption = Gtk.Label()
    caption.set_markup("<span size='x-large' weight='bold'>GeneralsX</span>\nfor Raspberry Pi 5")
    caption.set_justify(Gtk.Justification.CENTER)
    caption.set_margin_bottom(24)
    box.pack_end(caption, False, False, 0)
    return box


def label(markup="", wrap=True, xalign=0.0):
    widget = Gtk.Label()
    widget.set_markup(markup)
    widget.set_line_wrap(wrap)
    widget.set_xalign(xalign)
    widget.set_max_width_chars(60)
    return widget


class Wizard(Gtk.Window):
    def __init__(self):
        super().__init__(title=TITLE)
        self.set_default_size(580, 430)
        self.set_resizable(False)
        self.set_position(Gtk.WindowPosition.CENTER)
        if os.path.exists(ICON):
            self.set_icon_from_file(ICON)
        self.connect("delete-event", self.on_close)

        self.zh_found = ""
        self.generals_found = ""
        self.packages = []
        self.password = None
        self.process = None
        self.installing = False
        self.succeeded = False
        self.log_lines = []

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(outer)
        self.stack = Gtk.Stack()
        self.stack.set_vexpand(True)
        outer.pack_start(self.stack, True, True, 0)
        outer.pack_start(Gtk.Separator(), False, False, 0)

        buttons = Gtk.Box(spacing=6, margin=10)
        self.back = Gtk.Button.new_with_mnemonic("< _Back")
        self.next = Gtk.Button.new_with_mnemonic("_Next >")
        self.cancel = Gtk.Button.new_with_mnemonic("_Cancel")
        self.back.connect("clicked", self.on_back)
        self.next.connect("clicked", self.on_next)
        self.cancel.connect("clicked", lambda _b: self.on_close())
        for button in (self.back, self.next, self.cancel):
            button.set_size_request(86, -1)
        buttons.pack_end(self.cancel, False, False, 0)
        buttons.pack_end(Gtk.Box(), False, False, 6)
        buttons.pack_end(self.next, False, False, 0)
        buttons.pack_end(self.back, False, False, 0)
        outer.pack_start(buttons, False, False, 0)

        self.pages = ["welcome", "license", "folders", "options", "ready", "installing", "finish"]
        self.build_welcome()
        self.build_license()
        self.build_folders()
        self.build_options()
        self.build_ready()
        self.build_installing()
        self.build_finish()
        self.index = 0
        self.show_page()

        threading.Thread(target=self.detect, daemon=True).start()

    # --- Page frames ---------------------------------------------------------------------------
    def banner_page(self, name, title):
        box = Gtk.Box()
        box.get_style_context().add_class("wizard-page")
        box.pack_start(banner(), False, False, 0)
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin=20)
        content.pack_start(label(f"<span size='x-large' weight='bold'>{esc(title)}</span>"), False, False, 0)
        box.pack_start(content, True, True, 0)
        self.stack.add_named(box, name)
        return content

    def interior_page(self, name, title, subtitle):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        header = Gtk.Box(spacing=10)
        header.get_style_context().add_class("wizard-header")
        texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        texts.pack_start(label(f"<b>{esc(title)}</b>"), False, False, 0)
        subtitle_label = label(esc(subtitle))
        subtitle_label.set_margin_start(14)
        texts.pack_start(subtitle_label, False, False, 0)
        header.pack_start(texts, True, True, 0)
        if os.path.exists(ICON):
            header.pack_end(Gtk.Image.new_from_pixbuf(
                GdkPixbuf.Pixbuf.new_from_file_at_scale(ICON, 48, 48, True)), False, False, 0)
        box.pack_start(header, False, False, 0)
        box.pack_start(Gtk.Separator(), False, False, 0)
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=18)
        content.set_margin_start(36)
        content.set_margin_end(36)
        box.pack_start(content, True, True, 0)
        self.stack.add_named(box, name)
        return content

    # --- Pages ---------------------------------------------------------------------------------
    def build_welcome(self):
        content = self.banner_page("welcome", f"Welcome to the {PRODUCT} Setup Wizard")
        content.pack_start(label(
            f"This will install {esc(PRODUCT)} on your Raspberry Pi 5.\n\n"
            "You need your own copy of <b>Generals</b> and <b>Zero Hour</b>, for example copied from a "
            "Windows PC onto a USB stick. If your game files are on a USB stick, plug it in now.\n\n"
            "Click Next to continue, or Cancel to exit Setup."), False, False, 0)
        self.machine_ok = platform.machine() == "aarch64" or os.environ.get("GENERALSX_SETUP_ANY_ARCH") == "1"
        warning = ""
        if not self.machine_ok:
            warning = ("<b>This computer can't run the game.</b> It needs the 64-bit version of Raspberry Pi OS "
                       f"(this system reports {esc(platform.machine())}).")
        else:
            try:
                with open("/proc/device-tree/model", encoding="utf-8", errors="replace") as f:
                    model = f.read().strip("\0\n ")
            except OSError:
                model = ""
            if "Raspberry Pi 5" not in model:
                which = f"this computer is a “{esc(model)}”" if model else "this computer isn't one"
                warning = f"<b>Note:</b> this was made for the Raspberry Pi 5, and {which}. It may not work."
        if warning:
            content.pack_start(label(warning), False, False, 0)

    def build_license(self):
        content = self.interior_page("license", "License Agreement",
                                     "Please read the following license agreement carefully.")
        content.pack_start(label("Press Page Down to see the rest of the agreement."), False, False, 0)
        view = Gtk.TextView(editable=False, cursor_visible=False, wrap_mode=Gtk.WrapMode.WORD, monospace=True)
        try:
            with open(LICENSE, encoding="utf-8", errors="replace") as f:
                view.get_buffer().set_text(html.unescape(f.read()))
        except OSError:
            view.get_buffer().set_text("GeneralsX is free software under the GNU General Public License v3.")
        scroll = Gtk.ScrolledWindow(shadow_type=Gtk.ShadowType.IN)
        scroll.set_vexpand(True)
        scroll.add(view)
        content.pack_start(scroll, True, True, 0)
        self.accept = Gtk.RadioButton.new_with_mnemonic(None, "I _accept the agreement")
        decline = Gtk.RadioButton.new_with_mnemonic_from_widget(self.accept, "I _do not accept the agreement")
        decline.set_active(True)
        self.accept.connect("toggled", lambda _b: self.update_buttons())
        content.pack_start(self.accept, False, False, 0)
        content.pack_start(decline, False, False, 0)

    def folder_row(self, grid, row, caption):
        grid.attach(label(caption, wrap=False), 0, row, 1, 1)
        chooser = Gtk.FileChooserButton(title=caption.rstrip(":"), action=Gtk.FileChooserAction.SELECT_FOLDER)
        chooser.set_hexpand(True)
        chooser.connect("selection-changed", lambda _c: self.check_folders())
        grid.attach(chooser, 1, row, 1, 1)
        status = label("", wrap=True)
        status.set_margin_bottom(8)
        grid.attach(status, 1, row + 1, 1, 1)
        return chooser, status

    def build_folders(self):
        content = self.interior_page("folders", "Game Files",
                                     "Where are your Generals and Zero Hour game files?")
        self.search_box = Gtk.Box(spacing=8)
        spinner = Gtk.Spinner()
        spinner.start()
        self.search_box.pack_start(spinner, False, False, 0)
        self.search_box.pack_start(label("Looking for your game files on USB sticks and in your home folder…"),
                                   False, False, 0)
        content.pack_start(self.search_box, False, False, 0)
        content.pack_start(label("Choose each game's folder, the one with the <b>.big</b> files in it."),
                           False, False, 0)
        grid = Gtk.Grid(column_spacing=10, row_spacing=4)
        self.zh_chooser, self.zh_status = self.folder_row(grid, 0, "Zero Hour folder:")
        self.generals_chooser, self.generals_status = self.folder_row(grid, 2, "Generals folder:")
        content.pack_start(grid, False, False, 0)
        content.pack_start(label(
            "<small>With the EA app they are the <i>Command and Conquer Generals Zero Hour</i> and "
            "<i>Command and Conquer Generals</i> folders inside the game's install folder.</small>"),
            False, False, 0)

    def build_options(self):
        content = self.interior_page("options", "Select Additional Tasks",
                                     "Which additional tasks should Setup perform?")
        content.pack_start(label("Select the additional tasks you would like Setup to perform, then click Next."),
                           False, False, 0)
        self.desktop_icon = Gtk.CheckButton.new_with_mnemonic("Create a _desktop shortcut")
        self.desktop_icon.set_active(True)
        content.pack_start(self.desktop_icon, False, False, 0)
        menu = Gtk.CheckButton(label="Add the game to the Games menu")
        menu.set_active(True)
        menu.set_sensitive(False)
        content.pack_start(menu, False, False, 0)
        content.pack_start(label(f"\nSetup will install the game into:\n<tt>{esc(BASE_DIR)}</tt>"), False, False, 0)

    def build_ready(self):
        content = self.interior_page("ready", "Ready to Install",
                                     f"Setup is now ready to begin installing {PRODUCT} on your Raspberry Pi.")
        content.pack_start(label("Click Install to continue, or click Back to review or change any settings."),
                           False, False, 0)
        self.summary = Gtk.TextView(editable=False, cursor_visible=False, wrap_mode=Gtk.WrapMode.WORD)
        scroll = Gtk.ScrolledWindow(shadow_type=Gtk.ShadowType.IN)
        scroll.set_vexpand(True)
        scroll.add(self.summary)
        content.pack_start(scroll, True, True, 0)
        self.password_box = Gtk.Box(spacing=8)
        self.password_box.pack_start(label("Your password, to install system components:", wrap=False),
                                     False, False, 0)
        self.password_entry = Gtk.Entry(visibility=False, activates_default=True)
        self.password_entry.set_hexpand(True)
        self.password_box.pack_start(self.password_entry, True, True, 0)
        content.pack_start(self.password_box, False, False, 0)

    def build_installing(self):
        content = self.interior_page("installing", "Installing",
                                     f"Please wait while Setup installs {PRODUCT} on your Raspberry Pi.")
        self.status = label("Preparing to install…")
        content.pack_start(self.status, False, False, 0)
        self.bar = Gtk.ProgressBar()
        content.pack_start(self.bar, False, False, 0)
        self.details = Gtk.TextView(editable=False, cursor_visible=False, monospace=True,
                                    wrap_mode=Gtk.WrapMode.CHAR)
        scroll = Gtk.ScrolledWindow(shadow_type=Gtk.ShadowType.IN)
        scroll.set_size_request(-1, 170)
        scroll.add(self.details)
        self.details_scroll = scroll
        expander = Gtk.Expander.new_with_mnemonic("Show _details")
        expander.add(scroll)
        content.pack_start(expander, True, True, 0)

    def build_finish(self):
        self.finish_content = self.banner_page("finish", f"Completing the {PRODUCT} Setup Wizard")
        self.finish_text = label("")
        self.finish_content.pack_start(self.finish_text, False, False, 0)
        self.launch = Gtk.CheckButton.new_with_mnemonic(f"_Launch {PRODUCT}")
        self.launch.set_active(True)
        self.readme = Gtk.CheckButton.new_with_mnemonic("View the _Readme file")
        self.finish_content.pack_start(self.launch, False, False, 0)
        self.finish_content.pack_start(self.readme, False, False, 0)

    # --- Game folder search --------------------------------------------------------------------
    def detect(self):
        found = {}
        for line in run_installer("--detect").splitlines():
            key, _, value = line.partition("=")
            found[key] = value
        packages = run_installer("--missing-packages").split()
        GLib.idle_add(self.detected, found.get("zh", ""), found.get("generals", ""), packages)

    def detected(self, zh, generals, packages):
        self.packages = packages
        self.search_box.hide()
        self.search_box.set_no_show_all(True)
        self.zh_found, self.generals_found = zh, generals
        if zh and not self.zh_chooser.get_filename():
            self.zh_chooser.set_filename(zh)
        if generals and not self.generals_chooser.get_filename():
            self.generals_chooser.set_filename(generals)
        self.check_folders()
        return False

    def check_folders(self):
        def describe(folder, ok, installed, marker):
            if not folder:
                return "<span foreground='#b00000'>✖ Not found yet. Choose the folder above.</span>"
            if not ok:
                return f"<span foreground='#b00000'>✖ This folder has no {marker}.</span>"
            if same_dir(folder, installed):
                return "<span foreground='#006000'>✔ Already installed</span>"
            return f"<span foreground='#006000'>✔ Game files found</span> <small>in {esc(folder)}</small>"

        zh = self.zh_chooser.get_filename() or ""
        generals = self.generals_chooser.get_filename() or ""
        self.zh_status.set_markup(describe(zh, is_zh_dir(zh), ZH_DIR, "INIZH.big"))
        self.generals_status.set_markup(describe(generals, is_generals_dir(generals), GENERALS_DIR, "INI.big"))
        self.update_buttons()

    # --- Navigation ----------------------------------------------------------------------------
    def page(self):
        return self.pages[self.index]

    def show_page(self):
        name = self.page()
        self.stack.set_visible_child_name(name)
        if name == "ready":
            self.fill_summary()
        self.update_buttons()

    def update_buttons(self):
        name = self.page()
        self.back.set_sensitive(name not in ("welcome", "installing", "finish"))
        self.cancel.set_sensitive(name != "finish")
        self.next.set_label({"ready": "_Install", "finish": "_Finish"}.get(name, "_Next >"))
        self.next.set_use_underline(True)
        enabled = True
        if name == "welcome":
            enabled = self.machine_ok
        elif name == "license":
            enabled = self.accept.get_active()
        elif name == "folders":
            enabled = (is_zh_dir(self.zh_chooser.get_filename() or "")
                       and is_generals_dir(self.generals_chooser.get_filename() or ""))
        elif name == "installing":
            enabled = False
        self.next.set_sensitive(enabled)
        self.next.set_can_default(True)
        self.next.grab_default()

    def on_back(self, _button):
        if self.index > 0:
            self.index -= 1
            self.show_page()

    def on_next(self, _button):
        name = self.page()
        if name == "ready":
            if not self.start_install():
                return
        elif name == "finish":
            self.finish()
            return
        self.index += 1
        self.show_page()

    def on_close(self, *_args):
        if self.page() == "finish":
            Gtk.main_quit()
            return False
        if self.installing:
            if not ask(self, "Stop the installation?",
                       "The game may not start until you run Setup again."):
                return True
            if self.process and self.process.poll() is None:
                os.killpg(self.process.pid, signal.SIGTERM)
            Gtk.main_quit()
            return False
        if ask(self, "Exit Setup?", "Setup is not complete. If you exit now, the game will not be installed.\n\n"
                                    "You can run Setup again at another time to complete the installation."):
            Gtk.main_quit()
            return False
        return True

    # --- Ready page ----------------------------------------------------------------------------
    def fill_summary(self):
        zh = self.zh_chooser.get_filename() or ""
        generals = self.generals_chooser.get_filename() or ""
        lines = ["Install location:", f"      {BASE_DIR}", "", "Game files:"]
        for caption, folder, installed in (("Zero Hour", zh, ZH_DIR), ("Generals", generals, GENERALS_DIR)):
            lines.append(f"      {caption}: " + ("already installed" if same_dir(folder, installed)
                                                 else f"copy from {folder}"))
        lines += ["", "Additional tasks:", "      Add the game to the Games menu"]
        if self.desktop_icon.get_active():
            lines.append("      Create a desktop shortcut")
        if self.packages:
            lines += ["", "System components to install:", "      " + " ".join(self.packages)]
        self.summary.get_buffer().set_text("\n".join(lines))
        self.needs_password = bool(self.packages) and sudo_needs_password()
        self.password_box.set_visible(self.needs_password)
        self.password_box.set_no_show_all(not self.needs_password)
        if self.needs_password:
            self.password_box.show_all()
            self.password_entry.grab_focus()

    def start_install(self):
        self.password = None
        if self.needs_password:
            password = self.password_entry.get_text()
            if not password or not sudo_password_ok(password):
                tell(self, "That password is not correct.",
                     "Setup needs the password you log in with to install system components.",
                     Gtk.MessageType.ERROR)
                self.password_entry.grab_focus()
                return False
            self.password = password
        self.installing = True
        args = ["--gui"]
        zh = self.zh_chooser.get_filename() or ""
        generals = self.generals_chooser.get_filename() or ""
        if not same_dir(zh, ZH_DIR):
            args += ["--zh-data", zh]
        if not same_dir(generals, GENERALS_DIR):
            args += ["--generals-data", generals]
        if not self.desktop_icon.get_active():
            args.append("--no-desktop-icon")
        threading.Thread(target=self.install, args=(args,), daemon=True).start()
        return True

    # --- Installing ----------------------------------------------------------------------------
    def log(self, text):
        self.log_lines.append(text)
        buffer = self.details.get_buffer()
        buffer.insert(buffer.get_end_iter(), text + "\n")
        adjustment = self.details_scroll.get_vadjustment()
        adjustment.set_value(adjustment.get_upper())
        return False

    def set_progress(self, fraction, text):
        if fraction is None:
            self.bar.pulse()
        else:
            self.bar.set_fraction(fraction)
        if text:
            self.status.set_text(text)
        return False

    def stream(self, command, env=None, stdin_text=None):
        """Run a command, sending its output to the details log; returns the exit code."""
        self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, text=True, bufsize=1, env=env,
                                        start_new_session=True)
        if stdin_text is not None:
            self.process.stdin.write(stdin_text)
        self.process.stdin.close()
        for raw in self.process.stdout:
            line = raw.rstrip("\n")
            if line.startswith("@@ "):
                _, pct, message = (line.split(" ", 2) + [""])[:3]
                GLib.idle_add(self.set_progress, min(int(pct), 100) / 100.0, message + "…")
            else:
                GLib.idle_add(self.log, line)
        return self.process.wait()

    def install(self, args):
        code = 0
        if self.packages:
            GLib.idle_add(self.set_progress, 0.0, "Installing system components…")
            pulsing = [True]

            def pulse():
                if pulsing[0]:
                    self.bar.pulse()
                return pulsing[0]

            GLib.timeout_add(120, pulse)
            sudo = ["sudo", "-S", "-p", ""] if self.password else ["sudo", "-n"]
            script = "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y " + " ".join(self.packages)
            code = self.stream(sudo + ["sh", "-c", script],
                               stdin_text=(self.password + "\n") if self.password else None)
            pulsing[0] = False
        self.password = None
        if code == 0:
            env = dict(os.environ, SKIP_APT="1")
            code = self.stream(["bash", INSTALLER, *args], env=env)
        GLib.idle_add(self.installed, code)

    def installed(self, code):
        self.installing = False
        self.succeeded = code == 0
        try:
            os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
            with open(LOG_FILE, "w", encoding="utf-8") as f:
                f.write("\n".join(self.log_lines) + "\n")
        except OSError:
            pass
        if self.succeeded:
            self.finish_text.set_markup(
                f"Setup has finished installing {esc(PRODUCT)} on your Raspberry Pi. Start the game from the "
                "desktop shortcut or the Games menu.\n\nClick Finish to exit Setup.")
        else:
            self.finish_content.get_children()[0].set_markup(
                "<span size='x-large' weight='bold'>Setup was not completed</span>")
            self.finish_text.set_markup(
                f"Something went wrong, and {esc(PRODUCT)} was not installed.\n\n"
                f"The details are saved in <tt>{esc(LOG_FILE)}</tt>. Run Setup again to retry.")
            self.launch.set_active(False)
            self.launch.hide()
            self.readme.hide()
        self.index = self.pages.index("finish")
        self.show_page()
        return False

    def finish(self):
        if self.succeeded and self.readme.get_active() and os.path.exists(README):
            subprocess.Popen(["xdg-open", README], start_new_session=True)
        if self.succeeded and self.launch.get_active() and os.path.exists(LAUNCHER):
            subprocess.Popen([LAUNCHER], start_new_session=True)
        Gtk.main_quit()


def uninstall():
    window = Gtk.Window(title=TITLE)
    if os.path.exists(ICON):
        window.set_icon_from_file(ICON)
    if not ask(window, f"Remove {PRODUCT}?",
               "This removes the game program, its shortcuts and the graphics driver it uses. Your game "
               "files from the CDs or EA app, your saved games and your settings are kept."):
        return 0
    result = subprocess.run(["bash", INSTALLER, "--uninstall"], capture_output=True, text=True)
    if result.returncode == 0:
        tell(window, f"{PRODUCT} was removed from your computer.",
             f"Your game files are still in {BASE_DIR}. Delete that folder to remove them too.")
    else:
        tell(window, "The game could not be removed.", (result.stdout + result.stderr).strip()[-600:],
             Gtk.MessageType.ERROR)
    return result.returncode


def main():
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                             Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    if "--uninstall" in sys.argv[1:]:
        return uninstall()
    wizard = Wizard()
    wizard.show_all()
    wizard.password_box.set_visible(False)
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
