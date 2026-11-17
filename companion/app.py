"""
ForeverAiCompanion.exe - one program that is the setup wizard, the background companion and its own uninstaller.

  First run (or --settings): a small window to paste your free Gemini key and pick options.
  Installed: runs quietly, wakes up only while WoW is open.
  --uninstall: removes everything it added (also reachable from Windows Settings > Apps).

What it changes on your PC, all in your own user account (no admin rights):
  %LOCALAPPDATA%\\Programs\\ForeverAi\\ForeverAiCompanion.exe   the program
  %APPDATA%\\ForeverAi\\                                        your key, log and chat history
  HKCU ...\\CurrentVersion\\Run\\ForeverAiCompanion             only if you tick "start with Windows"
  HKCU ...\\CurrentVersion\\Uninstall\\ForeverAiCompanion       so it shows up in Windows' Apps list
"""
import json
import os
import shutil
import subprocess
import sys
import threading
import time
import webbrowser

import foreverai_companion as core

VERSION = "1.0.0"
APP_NAME = "ForeverAi Companion"
EXE_NAME = "ForeverAiCompanion.exe"
REPO_URL = "https://github.com/OWNER/ForeverAi"   # filled in by the release build
KEY_URL = "https://aistudio.google.com/apikey"
INSTALL_DIR = os.path.join(os.environ.get("LOCALAPPDATA", os.path.expanduser("~")), "Programs", "ForeverAi")
INSTALLED_EXE = os.path.join(INSTALL_DIR, EXE_NAME)
RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
UNINST_KEY = r"Software\Microsoft\Windows\CurrentVersion\Uninstall\ForeverAiCompanion"
FROZEN = getattr(sys, "frozen", False)


def same(a, b):
    return os.path.normcase(os.path.abspath(a)) == os.path.normcase(os.path.abspath(b))


def launch_cmd(exe=None):
    """How Windows should start the companion."""
    if FROZEN:
        return f'"{exe or INSTALLED_EXE}"'
    pyw = os.path.join(os.path.dirname(sys.executable), "pythonw.exe")
    return f'"{pyw}" "{os.path.abspath(__file__)}"'


# --------------------------------------------------------------------------- registry (current user only)
def reg_set(path, values):
    import winreg
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, path) as k:
        for name, val in values.items():
            if isinstance(val, int):
                winreg.SetValueEx(k, name, 0, winreg.REG_DWORD, val)
            else:
                winreg.SetValueEx(k, name, 0, winreg.REG_SZ, val)


def reg_delete_value(path, name):
    import winreg
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, path, 0, winreg.KEY_SET_VALUE) as k:
            winreg.DeleteValue(k, name)
    except OSError:
        pass


def reg_delete_key(path):
    import winreg
    try:
        winreg.DeleteKey(winreg.HKEY_CURRENT_USER, path)
    except OSError:
        pass


def autostart_on():
    import winreg
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as k:
            winreg.QueryValueEx(k, "ForeverAiCompanion")
            return True
    except OSError:
        return False


# --------------------------------------------------------------------------- stop a running copy
def stop_running(wait=2.0):
    """Ask a running companion to exit (it watches for this flag file), then clear the flag."""
    os.makedirs(core.APP_DIR, exist_ok=True)
    open(core.STOP_FLAG, "w").close()
    time.sleep(wait)
    try:
        os.remove(core.STOP_FLAG)
    except OSError:
        pass


# --------------------------------------------------------------------------- install
def install(key, addon_dir, autostart):
    os.makedirs(core.APP_DIR, exist_ok=True)
    cfg = core.load_cfg()
    cfg["gemini_key"] = key
    if addon_dir:
        cfg["addon_dir"] = addon_dir
    json.dump(cfg, open(core.CONFIG, "w", encoding="utf-8"), indent=1)

    stop_running()
    exe = INSTALLED_EXE
    if FROZEN:
        if not same(sys.executable, INSTALLED_EXE):
            os.makedirs(INSTALL_DIR, exist_ok=True)
            shutil.copy2(sys.executable, INSTALLED_EXE)
    cmd = launch_cmd(exe)
    if autostart:
        reg_set(RUN_KEY, {"ForeverAiCompanion": cmd})
    else:
        reg_delete_value(RUN_KEY, "ForeverAiCompanion")
    if FROZEN:
        reg_set(UNINST_KEY, {
            "DisplayName": APP_NAME, "DisplayVersion": VERSION, "Publisher": "ForeverAi (open source)",
            "DisplayIcon": exe, "InstallLocation": INSTALL_DIR, "URLInfoAbout": REPO_URL,
            "UninstallString": f'"{exe}" --uninstall', "NoModify": 1, "NoRepair": 1, "EstimatedSize": 20000,
        })
    # start the companion now (detached, no window)
    flags = 0x00000008 | 0x00000200  # DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
    if FROZEN:
        subprocess.Popen([exe], creationflags=flags, close_fds=True)
    else:
        subprocess.Popen([os.path.join(os.path.dirname(sys.executable), "pythonw.exe"), os.path.abspath(__file__)],
                         creationflags=flags, close_fds=True)


def uninstall():
    from tkinter import messagebox, Tk
    root = Tk(); root.withdraw()
    if not messagebox.askyesno(APP_NAME, "Remove ForeverAi Companion from this PC?\n\n(The ForeverAi addon in WoW is not touched.)"):
        return
    stop_running()
    reg_delete_value(RUN_KEY, "ForeverAiCompanion")
    reg_delete_key(UNINST_KEY)
    if messagebox.askyesno(APP_NAME, "Also delete your saved Gemini key and chat history?"):
        shutil.rmtree(core.APP_DIR, ignore_errors=True)
    if FROZEN and os.path.isdir(INSTALL_DIR):
        # a running program can't delete itself: remove the folder a moment after we exit
        subprocess.Popen(f'cmd /c ping 127.0.0.1 -n 3 > nul & rmdir /s /q "{INSTALL_DIR}"',
                         creationflags=0x08000000, close_fds=True)
    messagebox.showinfo(APP_NAME, "ForeverAi Companion has been removed.")


# --------------------------------------------------------------------------- setup window
def wizard():
    import tkinter as tk
    from tkinter import filedialog, ttk

    cfg = core.load_cfg()
    root = tk.Tk()
    root.title(f"{APP_NAME} setup")
    root.resizable(False, False)
    pad = {"padx": 16, "pady": 4}
    bg = "#15151a"; fg = "#e8e8e8"; dim = "#9a9aa5"; gold = "#ffd100"
    root.configure(bg=bg)

    def label(text, color=fg, font=("Segoe UI", 10), **kw):
        l = tk.Label(root, text=text, bg=bg, fg=color, font=font, justify="left", wraplength=470, anchor="w", **kw)
        l.pack(fill="x", **pad)
        return l

    label("ForeverAi Companion", gold, ("Segoe UI", 15, "bold"))
    label("Gives ForeverAi live AI answers in game, using your own free Google Gemini key.", dim)
    label("What it does: while WoW is open, it reads only ForeverAi's small colored strip in the corner of its "
          "window (your question and character info), asks Gemini, and draws the answer over ForeverAi's panel. "
          "It never presses keys, never touches game files, and needs no admin rights.", fg, ("Segoe UI", 9))
    link = label("Open source: " + REPO_URL, "#66ccff", ("Segoe UI", 9, "underline"), cursor="hand2")
    link.bind("<Button-1>", lambda e: webbrowser.open(REPO_URL))

    label("1.  Get your free key (Google account, no card)", gold, ("Segoe UI", 11, "bold"))
    tk.Button(root, text="Open Google AI Studio", command=lambda: webbrowser.open(KEY_URL),
              bg="#2a2a33", fg=fg, relief="flat", padx=10, pady=4).pack(anchor="w", padx=16)
    label("Click 'Create API key', then 'Copy'.", dim, ("Segoe UI", 9))

    label("2.  Paste it here", gold, ("Segoe UI", 11, "bold"))
    key_var = tk.StringVar(value=cfg.get("gemini_key", ""))
    entry = tk.Entry(root, textvariable=key_var, show="•", width=56, bg="#22222a", fg=fg, insertbackground=fg, relief="flat")
    entry.pack(anchor="w", padx=16, ipady=4)
    status = label("", dim, ("Segoe UI", 9))

    label("3.  Options", gold, ("Segoe UI", 11, "bold"))
    auto_var = tk.BooleanVar(value=autostart_on() or not cfg.get("gemini_key"))
    tk.Checkbutton(root, text="Start quietly with Windows (it sleeps until WoW is open)", variable=auto_var,
                   bg=bg, fg=fg, selectcolor="#22222a", activebackground=bg, activeforeground=fg).pack(anchor="w", padx=12)
    addon = {"dir": core.find_addon_dir(cfg)}
    addon_lbl = label("", dim, ("Segoe UI", 9))

    def show_addon():
        addon_lbl.config(text=("ForeverAi addon found: " + addon["dir"]) if addon["dir"]
                         else "ForeverAi addon not found automatically (optional - live answers still work).")
    show_addon()

    def browse():
        d = filedialog.askdirectory(title="Pick your Interface\\AddOns\\ForeverAi folder")
        if d and os.path.exists(os.path.join(d, "Knowledge", "KB.lua")):
            addon["dir"] = os.path.normpath(d); show_addon()
        elif d:
            status.config(text="That folder isn't the ForeverAi addon (no Knowledge\\KB.lua inside).", fg="#ff8080")
    tk.Button(root, text="Choose addon folder...", command=browse, bg="#2a2a33", fg=fg, relief="flat", padx=8).pack(anchor="w", padx=16)

    label("Live answers need WoW in Windowed or Borderless (Windowed Fullscreen) mode.", dim, ("Segoe UI", 9))

    btn = tk.Button(root, text="Test key, install and start", bg=gold, fg="#111", relief="flat",
                    font=("Segoe UI", 10, "bold"), padx=14, pady=6)
    btn.pack(pady=(10, 16))

    def go():
        key = key_var.get().strip()
        if len(key) < 20:
            status.config(text="Paste your Gemini key first.", fg="#ff8080"); return
        btn.config(state="disabled"); status.config(text="Testing your key with Google...", fg=dim)

        def work():
            try:
                model = core.pick_model(key)
                core.gemini_post(key, model, {"contents": [{"role": "user", "parts": [{"text": "Reply with: ok"}]}]})
            except Exception as e:
                msg = str(e)
                if "API key" in msg or "400" in msg or "403" in msg:
                    msg = "Google rejected that key. Copy it again from AI Studio."
                root.after(0, lambda: (status.config(text="Key test failed: " + msg[:160], fg="#ff8080"), btn.config(state="normal")))
                return
            try:
                install(key, addon["dir"], auto_var.get())
            except Exception as e:
                root.after(0, lambda: (status.config(text="Install failed: " + str(e)[:160], fg="#ff8080"), btn.config(state="normal")))
                return

            def done():
                status.config(text="All set! ForeverAi Companion is running. In WoW type /fai and ask anything.", fg="#7CFC7C")
                btn.config(text="Close", state="normal", command=root.destroy)
            root.after(0, done)
        threading.Thread(target=work, daemon=True).start()

    btn.config(command=go)
    entry.focus_set()
    root.mainloop()


def main():
    args = sys.argv[1:]
    if os.name != "nt":
        print("ForeverAi Companion runs on Windows."); return
    if "--uninstall" in args:
        return uninstall()
    cfg = core.load_cfg()
    installed_here = (not FROZEN) or same(sys.executable, INSTALLED_EXE)
    if "--settings" in args or not cfg.get("gemini_key") or not installed_here:
        return wizard()
    core.run()


if __name__ == "__main__":
    main()
