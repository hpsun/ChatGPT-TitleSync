#!/usr/bin/env python3
"""ChatGPT-TitleSync: Windows-only ChatGPT caption monitor; Python 3, standard library only.
Run: python chatgpt_window_titles.py [--interval 2 --background-interval 5]; fresh foreground + cached background maintenance
Read-only validation: python chatgpt_window_titles.py --read-only --once
Stop normally: python chatgpt_window_titles.py --stop
Ctrl+C, --stop and normal exit restore captions still owned by this process.
Normal resident launch enables per-user sign-in startup by default. Native caption changes do not change taskbar grouping.
"""
import argparse
import ctypes as C
from ctypes import wintypes as W
import datetime as dt
import json
import math
import threading
import winreg
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid
from icon_preferences import IconPreferences

# Keep console/piped metadata Unicode-safe, including conversation emoji.
for _stream in (sys.stdout, sys.stderr):
    if _stream is not None and hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8", errors="backslashreplace")

MUTEX = r"Local\TdxChatGptTitleStandalone"  # Keep legacy shared IPC to prevent concurrent old/new writers.
STOP_EVENT = MUTEX + ".Stop"
PATH_CLASSES = ("RootView", "NonClientView", "ChromeNodeFrameView",
                "ChromeNodeClientView", "View", "Chrome_WidgetWin_1",
                "Chrome_RenderWidgetHostHWND")
LOCATOR = "RawView immediate children: " + "/".join(PATH_CLASSES) + "/Document[RootWebArea].Name"
PTR, DWORD, BOOL = C.c_void_p, W.DWORD, W.BOOL
HRESULT = C.c_long
u32 = C.WinDLL("user32", use_last_error=True)
k32 = C.WinDLL("kernel32", use_last_error=True)
ole32 = C.OleDLL("ole32")
oa = C.OleDLL("oleaut32")

def bind(dll, name, restype, *argtypes):
    fn = getattr(dll, name)
    fn.restype, fn.argtypes = restype, argtypes
    return fn

bind(u32, "GetForegroundWindow", W.HWND)
bind(u32, "GetWindowThreadProcessId", DWORD, W.HWND, C.POINTER(DWORD))
bind(u32, "GetClassNameW", C.c_int, W.HWND, W.LPWSTR, C.c_int)
bind(u32, "GetWindowTextW", C.c_int, W.HWND, W.LPWSTR, C.c_int)
bind(u32, "IsWindowVisible", BOOL, W.HWND)
bind(u32, "IsWindow", BOOL, W.HWND)
bind(u32, "SendMessageTimeoutW", C.c_ssize_t, W.HWND, W.UINT, W.WPARAM,
     W.LPARAM, W.UINT, W.UINT, C.POINTER(C.c_size_t))
bind(k32, "OpenProcess", W.HANDLE, DWORD, BOOL, DWORD)
bind(k32, "CloseHandle", BOOL, W.HANDLE)
bind(k32, "GetProcessTimes", BOOL, W.HANDLE, C.POINTER(C.c_ulonglong),
     C.POINTER(C.c_ulonglong), C.POINTER(C.c_ulonglong), C.POINTER(C.c_ulonglong))
bind(k32, "QueryFullProcessImageNameW", BOOL, W.HANDLE, DWORD, W.LPWSTR, C.POINTER(DWORD))
bind(k32, "CreateMutexW", W.HANDLE, PTR, BOOL, W.LPCWSTR)
bind(k32, "CreateEventW", W.HANDLE, PTR, BOOL, BOOL, W.LPCWSTR)
bind(k32, "OpenEventW", W.HANDLE, DWORD, BOOL, W.LPCWSTR)
bind(k32, "SetEvent", BOOL, W.HANDLE)
bind(k32, "ResetEvent", BOOL, W.HANDLE)
bind(k32, "WaitForSingleObject", DWORD, W.HANDLE, DWORD)
bind(oa, "SysFreeString", None, PTR)
bind(oa, "SysStringLen", W.UINT, PTR)

def utc():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds")

def caption(hwnd):
    text = C.create_unicode_buffer(4096)
    u32.GetWindowTextW(hwnd, text, len(text))
    return text.value

def identity(hwnd):
    if not u32.IsWindow(hwnd):
        return None
    pid = DWORD()
    u32.GetWindowThreadProcessId(hwnd, C.byref(pid))
    cls = C.create_unicode_buffer(256)
    u32.GetClassNameW(hwnd, cls, len(cls))
    handle = k32.OpenProcess(0x1000, False, pid.value)
    if not handle:
        return None
    try:
        created, ended, kernel, user = (C.c_ulonglong() for _ in range(4))
        if not k32.GetProcessTimes(handle, C.byref(created), C.byref(ended), C.byref(kernel), C.byref(user)):
            return None
        name, length = C.create_unicode_buffer(32768), DWORD(32768)
        if not k32.QueryFullProcessImageNameW(handle, 0, name, C.byref(length)):
            return None
        return {"Hwnd": int(hwnd), "Pid": pid.value, "CreatedFileTime": created.value,
                "ClassName": cls.value, "Path": name.value}
    finally:
        k32.CloseHandle(handle)

def key(info):
    return tuple(info.get(n) for n in ("Hwnd", "Pid", "CreatedFileTime", "ClassName", "Path")) if info else None

def is_active(info):
    return int(u32.GetForegroundWindow() or 0) == info["Hwnd"] and key(identity(info["Hwnd"])) == key(info)

def targets():
    # Native metadata only. No accessibility tree is enumerated here.
    found = []
    callback_type = C.WINFUNCTYPE(BOOL, W.HWND, W.LPARAM)
    @callback_type
    def visit(hwnd, unused):
        cls = C.create_unicode_buffer(256)
        u32.GetClassNameW(hwnd, cls, len(cls))
        if cls.value == "Chrome_WidgetWin_1" and u32.IsWindowVisible(hwnd):
            info = identity(hwnd)
            if info and Path(info["Path"]).name.lower() == "chatgpt.exe":
                found.append(info)
        return True
    enum = bind(u32, "EnumWindows", BOOL, callback_type, W.LPARAM)
    if not enum(visit, 0):
        raise C.WinError(C.get_last_error())
    return found

def set_caption(info, text):
    """Bounded WM_SETTEXT, both return values and readback checked."""
    hwnd = info["Hwnd"]
    if key(identity(hwnd)) != key(info):
        raise RuntimeError("window identity changed")
    if "\0" in text:
        raise ValueError("caption contains NUL")
    buffer, result = C.create_unicode_buffer(text), C.c_size_t()
    C.set_last_error(0)
    ok = u32.SendMessageTimeoutW(hwnd, 0x000C, 0, C.cast(buffer, PTR).value,
                                0x23, 500, C.byref(result))
    if not ok or not result.value:
        raise RuntimeError("WM_SETTEXT failed: winerror=" + str(C.get_last_error()))
    if key(identity(hwnd)) != key(info) or caption(hwnd) != text:
        raise RuntimeError("caption identity/readback mismatch")

class GUID(C.Structure):
    _fields_ = [("Data1", C.c_ulong), ("Data2", C.c_ushort),
                ("Data3", C.c_ushort), ("Data4", C.c_ubyte * 8)]
    @classmethod
    def parse(cls, value):
        return cls.from_buffer_copy(uuid.UUID(value).bytes_le)

bind(ole32, "CoInitializeEx", HRESULT, PTR, DWORD)
bind(ole32, "CoUninitialize", None)
bind(ole32, "CoCreateInstance", HRESULT, C.POINTER(GUID), PTR, DWORD, C.POINTER(GUID), C.POINTER(PTR))

def method(pointer, index, result, *args):
    table = C.cast(pointer, C.POINTER(C.POINTER(PTR))).contents
    return C.WINFUNCTYPE(result, PTR, *args)(table[index])

def check(hr):
    if hr < 0:
        raise OSError("UIA HRESULT 0x%08x" % (hr & 0xffffffff))

class UIA:
    """SDK UIAutomationClient.h vtables; no ValuePattern/TextPattern use."""
    def __init__(self):
        self.refs = []
        check(ole32.CoInitializeEx(None, 0))  # fresh worker, MTA
        self.initialized = True
        cls = GUID.parse("ff48dba4-60ef-4201-aa87-54103eef594e")
        iid = GUID.parse("30cbe57d-d9d0-452a-ab13-7ac5ac4825ee")
        self.api = PTR()
        check(ole32.CoCreateInstance(C.byref(cls), None, 1, C.byref(iid), C.byref(self.api)))
        self.refs.append(self.api)
        self.walker = self.out(self.api, 16)  # get_RawViewWalker
        self.cache = self.out(self.api, 20)   # CreateCacheRequest
        # TreeScope_Element. Cache attributes of native shell/document root only.
        check(method(self.cache, 7, HRESULT, C.c_int)(self.cache, 1))
        for prop in (30003, 30005, 30011, 30012, 30019):
            check(method(self.cache, 3, HRESULT, C.c_int)(self.cache, prop))
    def out(self, obj, index, argtypes=(), args=()):
        pointer = PTR()
        check(method(obj, index, HRESULT, *argtypes, C.POINTER(PTR))(obj, *args, C.byref(pointer)))
        if pointer:
            self.refs.append(pointer)
        return pointer
    def string(self, el, index):
        value = PTR()
        check(method(el, index, HRESULT, C.POINTER(PTR))(el, C.byref(value)))
        if not value:
            return ""
        try:
            return C.wstring_at(value, oa.SysStringLen(value))
        finally:
            oa.SysFreeString(value)
    def number(self, el, index):
        value = C.c_int()
        check(method(el, index, HRESULT, C.POINTER(C.c_int))(el, C.byref(value)))
        return value.value
    def children(self, el, limit=32):
        child = self.out(self.walker, 10, (PTR, PTR), (el, self.cache))
        count = 0
        while child:
            count += 1
            if count > limit:
                raise RuntimeError("direct-child limit exceeded")
            yield child
            child = self.out(self.walker, 12, (PTR, PTR), (child, self.cache))
    def read_title(self, hwnd):
        node = self.out(self.api, 10, (W.HWND, PTR), (hwnd, self.cache))
        for class_name in PATH_CLASSES:
            matches = [child for child in self.children(node) if self.string(child, 62) == class_name]
            if len(matches) != 1:
                raise RuntimeError("verified native path mismatch: " + class_name)
            node = matches[0]
        # Only direct document roots, never document descendants.
        docs = [child for child in self.children(node, 16)
                if self.number(child, 53) == 50030 and self.string(child, 61) == "RootWebArea"]
        if len(docs) != 1 or self.number(docs[0], 67):
            raise RuntimeError("expected one non-password RootWebArea")
        title = self.string(docs[0], 55)
        if not title.strip() or len(title) > 512:
            raise RuntimeError("empty or oversized document title")
        return title
    def close(self):
        for pointer in reversed(self.refs):
            method(pointer, 2, C.c_ulong)(pointer)
        self.refs.clear()
        if getattr(self, "initialized", False):
            ole32.CoUninitialize()
            self.initialized = False

def worker(hwnd, background=False):
    before, uia = identity(hwnd), None
    result = {"Success": False, "Identity": before, "ObservedUtc": utc(), "Locator": LOCATOR}
    try:
        if (not before or before["ClassName"] != "Chrome_WidgetWin_1"
                or Path(before["Path"]).name.lower() != "chatgpt.exe"):
            raise RuntimeError("target identity is not ChatGPT")
        if not background and not is_active(before):
            raise RuntimeError("ForegroundChanged")
        uia = UIA()
        title = uia.read_title(hwnd)
        if (not background and not is_active(before)) or (background and is_active(before)) or key(identity(hwnd)) != key(before):
            raise RuntimeError("target identity changed while reading")
        result.update(Success=True, Title=title)
    except Exception as error:
        result["Error"] = str(error)
    finally:
        if uia:
            uia.close()
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["Success"] else 3

MONITOR_STOP = None
CUSTOM_BACKOFF = {}

def worker_command(worker_args):
    """Frozen executables relaunch themselves; source mode uses interpreter + file."""
    executable = Path(sys.executable)
    if getattr(sys, "frozen", False):
        return [str(executable), *worker_args]
    if executable.name.lower() == "pythonw.exe":
        executable = executable.with_name("python.exe")
    return [str(executable), str(Path(__file__).resolve()), *worker_args]

def dispatch_smoke():
    token = str(os.getpid()) + "-" + str(time.monotonic_ns())
    result = subprocess.run(worker_command(["--_dispatch-smoke", token]),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, encoding="utf-8", timeout=4,
                            creationflags=0x08000000,
                            env=dict(os.environ, PYTHONIOENCODING="utf-8"))
    reply = json.loads(result.stdout)
    if result.returncode != 0 or reply.get("Token") != token or reply.get("Payload") != "中文😀":
        raise RuntimeError("owned worker dispatch failed")
    if reply.get("Frozen") != bool(getattr(sys, "frozen", False)):
        raise RuntimeError("owned worker runtime mode mismatch")

def read_title(info):
    started = time.monotonic()
    if not is_active(info):
        return {"Success": False, "Error": "ForegroundChanged", "Identity": info}
    try:
        with subprocess.Popen(worker_command(["--_read", str(info["Hwnd"])]),
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                              encoding="utf-8", creationflags=0x08000000,
                              env=dict(os.environ, PYTHONIOENCODING="utf-8")) as child:
            try:
                while True:
                    error = None
                    if not is_active(info):
                        error = "ForegroundChanged"
                    elif MONITOR_STOP and k32.WaitForSingleObject(MONITOR_STOP, 0) == 0:
                        error = "StopRequested"
                    elif time.monotonic() - started >= 4:
                        error = "UIA worker timeout (4000ms)"
                    if error:
                        child.kill()
                        child.communicate()
                        return {"Success": False, "Error": error, "Identity": info}
                    try:
                        stdout, stderr = child.communicate(timeout=0.05)
                        break
                    except subprocess.TimeoutExpired:
                        continue
            finally:
                if child.poll() is None:
                    child.kill()  # only this Popen-owned reader, including Ctrl+C cleanup
                    child.communicate()
        result = json.loads(stdout)
        if not is_active(info) or key(result.get("Identity")) != key(info):
            raise RuntimeError("ForegroundChanged")
        result["ElapsedMs"] = round((time.monotonic() - started) * 1000)
        return result
    except Exception as error:
        return {"Success": False, "Error": str(error), "Identity": info}

def restore(record, emit):
    info = record["Identity"]
    if key(identity(info["Hwnd"])) != key(info):
        emit("restore_skipped_identity", info)
    elif caption(info["Hwnd"]) != record["Last"]:
        emit("restore_skipped_external_change", info)
    else:
        try:
            set_caption(info, record["Original"])
            emit("restored", info)
            return True
        except Exception as error:
            emit("restore_failed", info, Error=str(error))
    return False

def update_caption(info, title, records, emit):
    """Acquire ownership only after verified write; relinquish external changes."""
    if not is_active(info):
        emit("inactive_result_discarded", info)
        return
    ident, current = key(info), caption(info["Hwnd"])
    previous = records.get(ident)
    if previous and current != previous["Last"]:
        records.pop(ident, None)
        previous = None
        if current.strip().casefold() != "chatgpt":
            CUSTOM_BACKOFF[ident] = float("inf")
            emit("external_custom_caption_protected", info)
            return
        CUSTOM_BACKOFF.pop(ident, None)
        emit("native_generic_caption_reset", info)
    if current.strip().casefold() == "chatgpt":
        CUSTOM_BACKOFF.pop(ident, None)
    if time.monotonic() < CUSTOM_BACKOFF.get(ident, 0):
        emit("external_custom_caption_protected", info)
        return
    if title.strip().casefold() == "chatgpt":
        if previous and is_active(info) and caption(info["Hwnd"]) == current and restore(previous, emit):
            records.pop(ident, None)
        emit("generic_page", info)
        return
    wanted = title + " — ChatGPT"
    if current == wanted:
        return
    try:
        if not is_active(info) or caption(info["Hwnd"]) != current:
            emit("stale_result_discarded", info)
            return
        set_caption(info, wanted)
        records[ident] = {"Identity": info,
                          "Original": previous["Original"] if previous else current,
                          "Last": wanted}
        emit("caption_updated", info, Caption=wanted)
    except Exception as error:
        emit("write_failed", info, Error=str(error))

def maintain_background(known, records, emit, readonly=False):
    """Restore only a generic native reset from a previously verified name."""
    for ident, item in list(known.items()):
        info = item["Identity"]
        if key(identity(info["Hwnd"])) != ident:
            known.pop(ident, None)
            records.pop(ident, None)
            CUSTOM_BACKOFF.pop(ident, None)
            emit("identity_cache_expired", info)
            continue
        if is_active(info) or readonly:
            continue
        title = item.get("Title", "")
        if not title or title.strip().casefold() == "chatgpt":
            continue
        current = caption(info["Hwnd"])
        previous = records.get(ident)
        if previous and current == previous["Last"]:
            continue
        if previous:
            records.pop(ident, None)
        if current.strip().casefold() != "chatgpt":
            CUSTOM_BACKOFF[ident] = float("inf")
            continue  # another owner or a custom caption; never overwrite it
        CUSTOM_BACKOFF.pop(ident,None)
        desired = title + " — ChatGPT"
        try:
            if is_active(info) or key(identity(info["Hwnd"])) != ident or caption(info["Hwnd"]) != current:
                continue
            set_caption(info, desired)
            records[ident] = {"Identity":info,"Original":current,"Last":desired}
            emit("background_cache_restored", info)
        except Exception as error:
            emit("background_write_failed", info, Error=str(error))

def apply_background(info, title, known, records, emit, readonly=False):
    ident = key(info)
    if key(identity(info["Hwnd"])) != ident or is_active(info):
        emit("background_stale_result_discarded", info)
        return
    known[ident] = {"Identity":info,"Title":title}
    if readonly:
        return
    current, previous = caption(info["Hwnd"]), records.get(ident)
    if title.strip().casefold() == "chatgpt":
        if previous:
            if restore(previous, emit):
                records.pop(ident,None)
        return
    if current.strip().casefold() != "chatgpt" and not (previous and current == previous["Last"]):
        if previous:
            records.pop(ident,None)
        CUSTOM_BACKOFF[ident] = float("inf")
        return
    CUSTOM_BACKOFF.pop(ident,None)
    desired = title + " — ChatGPT"
    if current == desired:
        return
    try:
        if is_active(info) or key(identity(info["Hwnd"])) != ident or caption(info["Hwnd"]) != current:
            return
        set_caption(info,desired)
        records[ident] = {"Identity":info,"Original":previous["Original"] if previous and current == previous["Last"] else current,"Last":desired}
        emit("background_source_updated",info)
    except Exception as error:
        emit("background_write_failed",info,Error=str(error))

class ReaderSlot:
    """One owned process per role; waiting never blocks the scheduler."""
    def __init__(self, info, background=False):
        self.info, self.background, self.started = info, background, time.monotonic()
        argv = ["--_read", str(info["Hwnd"])] + (["--_background"] if background else [])
        self.child = subprocess.Popen(worker_command(argv), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", creationflags=0x08000000,
            env=dict(os.environ,PYTHONIOENCODING="utf-8"))
    def cancel(self):
        if self.child.poll() is None:
            self.child.kill()  # only the Popen-owned child for this slot
        self.child.communicate()
    def poll(self):
        if key(identity(self.info["Hwnd"])) != key(self.info) or (is_active(self.info) if self.background else not is_active(self.info)):
            self.cancel()
            return {"Success":False,"Error":"ForegroundOrIdentityChanged"}
        if time.monotonic()-self.started >= 4:
            self.cancel()
            return {"Success":False,"Error":"UIAWorkerTimeout"}
        if self.child.poll() is None:
            return None
        stdout, unused = self.child.communicate()
        try:
            result = json.loads(stdout)
            if key(result.get("Identity")) != key(self.info):
                raise ValueError("ReaderIdentityMismatch")
            return result
        except Exception as error:
            return {"Success":False,"Error":str(error)}

def native_self_test():
    """Own hidden native STATIC window only; no ChatGPT caption modification."""
    bind(u32, "CreateWindowExW", W.HWND, DWORD, W.LPCWSTR, W.LPCWSTR, DWORD,
         C.c_int, C.c_int, C.c_int, C.c_int, W.HWND, W.HMENU, W.HINSTANCE, PTR)
    bind(u32, "DestroyWindow", BOOL, W.HWND)
    hwnd = u32.CreateWindowExW(0x80, "STATIC", "Python fixture original", 0,
                             -32000, -32000, 1, 1, None, None, None, None)
    if not hwnd:
        raise C.WinError(C.get_last_error())
    events = []
    try:
        info = identity(hwnd)
        set_caption(info, "Python fixture conversation — ChatGPT")
        record = {"Identity": info, "Original": "Python fixture original", "Last": caption(hwnd)}
        restore(record, lambda event, unused, **kw: events.append(event))
        assert caption(hwnd) == record["Original"]
        set_caption(info, "external fixture change")
        restore(record, lambda event, unused, **kw: events.append(event))
        assert caption(hwnd) == "external fixture change"
        dispatch_smoke()
        print(json.dumps({"Success": True, "Events": events, "OwnFixtureHwnd": int(hwnd),
                          "OwnedWorkerDispatch": True, "Frozen": bool(getattr(sys, "frozen", False))}))
        return 0
    finally:
        u32.DestroyWindow(hwnd)


class ScanSettings:
    """Validated, atomically persisted settings shared with the tray thread."""
    def __init__(self, path, foreground=2, background=5):
        self.path, self.lock = Path(path), threading.Lock()
        self.foreground, self.background = self.validate(foreground, background)
        self.revision = 0

    @staticmethod
    def validate(foreground, background):
        foreground, background = float(foreground), float(background)
        if not math.isfinite(foreground) or not 1 <= foreground <= 3600:
            raise ValueError("Foreground interval must be 1..3600 seconds.")
        if not math.isfinite(background) or not 5 <= background <= 3600:
            raise ValueError("Background interval must be 5..3600 seconds.")
        return foreground, background

    def load(self, foreground_explicit=False, background_explicit=False):
        try:
            data = json.loads(self.path.read_text(encoding="utf-8-sig"))
            first = self.foreground if foreground_explicit else data["ForegroundSeconds"]
            second = self.background if background_explicit else data["BackgroundSeconds"]
            self.foreground, self.background = self.validate(first, second)
        except (OSError, ValueError, TypeError, KeyError):
            pass

    def snapshot(self):
        with self.lock:
            return self.foreground, self.background, self.revision

    def update(self, foreground, background):
        foreground, background = self.validate(foreground, background)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_name(self.path.name + "." + uuid.uuid4().hex + ".tmp")
        try:
            temporary.write_text(json.dumps({"ForegroundSeconds":foreground,
                "BackgroundSeconds":background}, indent=2), encoding="utf-8")
            os.replace(temporary, self.path)
        finally:
            try: temporary.unlink(missing_ok=True)
            except OSError: pass
        with self.lock:
            self.foreground, self.background = foreground, background
            self.revision += 1


def startup_command(executable=None, script=None, frozen=None):
    """Build only executable + optional source; never retain test/interval/log arguments."""
    executable = str(Path(executable or sys.executable).resolve())
    script = str(Path(script or __file__).resolve())
    def quoted(path):
        if not Path(path).is_absolute() or '"' in path or '\x00' in path:
            raise ValueError("Startup paths must be valid absolute paths")
        return '"' + path + '"'
    if frozen is None: frozen = bool(getattr(sys, "frozen", False))
    return quoted(executable) if frozen else quoted(executable) + " " + quoted(script)


class AutoStart:
    """Shared per-user contract; injectable private subkeys support isolated tests."""
    RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
    PREF_KEY = r"Software\ChatGPT-TitleSync"
    RUN_VALUE = "ChatGPT-TitleSync"
    PREF_VALUE = "AutoStartEnabled"
    def __init__(self, run_key=None, pref_key=None, command=None):
        self.run_key = run_key or self.RUN_KEY
        self.pref_key = pref_key or self.PREF_KEY
        self.command = command or startup_command()
        self.enabled, self.last_error = None, None
        self.lock = threading.RLock()
    @staticmethod
    def _read_value(path, name):
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, path, 0, winreg.KEY_QUERY_VALUE) as key:
                return winreg.QueryValueEx(key, name)
        except FileNotFoundError:
            return None
    @staticmethod
    def _write_value(path, name, value):
        if value is None:
            try:
                with winreg.OpenKey(winreg.HKEY_CURRENT_USER, path, 0, winreg.KEY_SET_VALUE) as key:
                    try: winreg.DeleteValue(key, name)
                    except FileNotFoundError: pass
            except FileNotFoundError: pass
        else:
            data, kind = value
            with winreg.CreateKeyEx(winreg.HKEY_CURRENT_USER, path, 0, winreg.KEY_SET_VALUE) as key:
                winreg.SetValueEx(key, name, 0, kind, data)
    def initialize(self):
        preference = self._read_value(self.pref_key, self.PREF_VALUE)
        if preference is not None and (preference[1] != winreg.REG_DWORD or preference[0] not in (0, 1)):
            raise ValueError("AutoStartEnabled must be a DWORD containing 0 or 1")
        self.set_enabled(True if preference is None else bool(preference[0]))
    def set_enabled(self, enabled):
        if not isinstance(enabled, bool): raise ValueError("Startup state must be boolean")
        if enabled and len(self.command.encode("utf-16-le"))//2>260:
            raise ValueError("Start-at-sign-in command exceeds Windows Run's 260-character limit")
        with self.lock:
            old_run = self._read_value(self.run_key, self.RUN_VALUE)
            old_pref = self._read_value(self.pref_key, self.PREF_VALUE)
            new_run = (self.command, winreg.REG_SZ) if enabled else None
            new_pref = (int(enabled), winreg.REG_DWORD)
            try:
                if old_run != new_run: self._write_value(self.run_key, self.RUN_VALUE, new_run)
                if old_pref != new_pref: self._write_value(self.pref_key, self.PREF_VALUE, new_pref)
            except Exception as error:
                rollback_errors = []
                for path, name, value in [(self.run_key,self.RUN_VALUE,old_run),(self.pref_key,self.PREF_VALUE,old_pref)]:
                    try: self._write_value(path,name,value)
                    except Exception as rollback: rollback_errors.append(str(rollback))
                self.last_error = str(error)
                if rollback_errors:
                    self.enabled = None
                    raise RuntimeError("Startup update failed: " + str(error) + "; rollback failed: " + "; ".join(rollback_errors)) from error
                raise RuntimeError("Startup update failed; previous registration retained: " + str(error)) from error
            self.enabled, self.last_error = enabled, None
    def menu_flags(self):
        return 1 if self.enabled is None else (8 if self.enabled else 0)


def startup_error(message):
    bind(u32,"MessageBoxW",C.c_int,W.HWND,W.LPCWSTR,W.LPCWSTR,W.UINT)
    u32.MessageBoxW(None,str(message),"ChatGPT-TitleSync — Start at sign-in",0x10)


class NativeTray:
    """Standard-library Win32 tray. Its UI never blocks the monitor scheduler."""
    CALLBACK = 0x8000 + 81
    def __init__(self, settings, stop, visible=True, autostart=None, icons=None):
        self.settings, self.stop, self.visible = settings, stop, visible
        self.autostart, self.auto_checkbox = autostart, 0
        self.icons, self.theme_controls, self.last_settings_error = icons, [], None
        self.ready = threading.Event()
        self.error = None
        self.hwnd = self.dialog = 0
        self.thread = None

    def start(self):
        self.thread = threading.Thread(target=self.run, name="ChatGPT-TitleSync tray", daemon=True)
        self.thread.start()
        if not self.ready.wait(5): raise RuntimeError("Tray startup timed out")
        if self.error: raise RuntimeError(self.error)

    def tick_icon(self):
        if self.hwnd: u32.PostMessageW(self.hwnd,self.CALLBACK+2,0,0)

    def close(self):
        if self.hwnd: u32.PostMessageW(self.hwnd, 0x0010, 0, 0)
        if self.thread and self.thread is not threading.current_thread(): self.thread.join(3)

    def run(self):
        import traceback
        shell = C.WinDLL("shell32", use_last_error=True)
        LRESULT = C.c_ssize_t
        PROC = C.WINFUNCTYPE(LRESULT, W.HWND, W.UINT, W.WPARAM, W.LPARAM)
        class WC(C.Structure):
            _fields_ = [("style",W.UINT),("proc",PROC),("cls",C.c_int),("wnd",C.c_int),
                ("instance",W.HINSTANCE),("icon",W.HICON),("cursor",W.HANDLE),
                ("background",W.HBRUSH),("menu",W.LPCWSTR),("name",W.LPCWSTR)]
        class NID(C.Structure):
            _fields_ = [("size",DWORD),("hwnd",W.HWND),("id",W.UINT),("flags",W.UINT),
                ("callback",W.UINT),("icon",W.HICON),("tip",W.WCHAR*128),
                ("state",DWORD),("mask",DWORD),("info",W.WCHAR*256),("version",W.UINT),
                ("infoTitle",W.WCHAR*64),("infoFlags",DWORD),("guid",C.c_ubyte*16),("balloon",W.HICON)]
        bind(k32,"GetModuleHandleW",W.HMODULE,W.LPCWSTR)
        bind(u32,"RegisterClassW",W.WORD,C.POINTER(WC))
        bind(u32,"UnregisterClassW",BOOL,W.LPCWSTR,W.HINSTANCE)
        bind(u32,"CreateWindowExW",W.HWND,DWORD,W.LPCWSTR,W.LPCWSTR,DWORD,C.c_int,C.c_int,C.c_int,C.c_int,W.HWND,W.HMENU,W.HINSTANCE,PTR)
        bind(u32,"DefWindowProcW",LRESULT,W.HWND,W.UINT,W.WPARAM,W.LPARAM)
        bind(u32,"DestroyWindow",BOOL,W.HWND)
        bind(u32,"PostMessageW",BOOL,W.HWND,W.UINT,W.WPARAM,W.LPARAM)
        bind(u32,"GetMessageW",BOOL,C.POINTER(W.MSG),W.HWND,W.UINT,W.UINT)
        bind(u32,"TranslateMessage",BOOL,C.POINTER(W.MSG))
        bind(u32,"IsDialogMessageW",BOOL,W.HWND,C.POINTER(W.MSG))
        bind(u32,"DispatchMessageW",LRESULT,C.POINTER(W.MSG))
        bind(u32,"PostQuitMessage",None,C.c_int)
        bind(u32,"CreatePopupMenu",W.HMENU)
        bind(u32,"AppendMenuW",BOOL,W.HMENU,W.UINT,C.c_size_t,W.LPCWSTR)
        bind(u32,"DestroyMenu",BOOL,W.HMENU)
        bind(u32,"TrackPopupMenu",W.UINT,W.HMENU,W.UINT,C.c_int,C.c_int,C.c_int,W.HWND,PTR)
        bind(u32,"GetCursorPos",BOOL,C.POINTER(W.POINT))
        bind(u32,"SetForegroundWindow",BOOL,W.HWND)
        bind(u32,"ShowWindow",BOOL,W.HWND,C.c_int)
        bind(u32,"SetFocus",W.HWND,W.HWND)
        bind(u32,"EnableWindow",BOOL,W.HWND,BOOL)
        bind(u32,"SendMessageW",C.c_ssize_t,W.HWND,W.UINT,W.WPARAM,W.LPARAM)
        bind(u32,"SetWindowTextW",BOOL,W.HWND,W.LPCWSTR)
        bind(u32,"MessageBoxW",C.c_int,W.HWND,W.LPCWSTR,W.LPCWSTR,W.UINT)
        bind(u32,"LoadImageW",W.HANDLE,W.HINSTANCE,W.LPCWSTR,W.UINT,C.c_int,C.c_int,W.UINT)
        bind(u32,"LoadIconW",W.HICON,W.HINSTANCE,PTR)
        bind(u32,"DestroyIcon",BOOL,W.HICON)
        bind(shell,"Shell_NotifyIconW",BOOL,DWORD,C.POINTER(NID))
        bind(shell,"ExtractIconExW",W.UINT,W.LPCWSTR,C.c_int,C.POINTER(W.HICON),C.POINTER(W.HICON),W.UINT)
        instance = k32.GetModuleHandleW(None)
        cls = "ChatGPTTitlePython_" + str(os.getpid())  # Retain the internal class identifier for existing tooling.
        icon, icon_owned, icon_choice, tray_added = None, False, None, False
        nid = NID(); nid.size = C.sizeof(nid)
        self.controls = []

        def dismiss():
            if self.dialog: u32.DestroyWindow(self.dialog)
            self.dialog = 0
            self.controls = []
            self.auto_checkbox = 0
            self.theme_controls = []

        def sync_startup_checkbox():
            if self.auto_checkbox:
                usable = self.autostart is not None and self.autostart.enabled is not None
                u32.EnableWindow(self.auto_checkbox,usable)
                u32.SendMessageW(self.auto_checkbox,0xf1,1 if usable and self.autostart.enabled else 0,0)

        def toggle_startup():
            if self.autostart is None: return
            try: self.autostart.set_enabled(not bool(self.autostart.enabled))
            except Exception as error: u32.MessageBoxW(self.dialog or self.hwnd,str(error),"ChatGPT-TitleSync — Start at sign-in",0x10)
            sync_startup_checkbox()

        def load_theme(plan=None):
            if self.icons is None: return None
            choice = self.icons.current_id(plan)
            if choice == icon_choice: return None
            path = self.icons.assets / (str(choice)+".ico")
            loaded=u32.LoadImageW(None,str(path),1,32,32,0x10)
            if not loaded: raise OSError("Unable to load icon " + str(choice))
            return loaded

        def commit_icon(loaded, choice, release_previous=True):
            nonlocal icon, icon_owned, icon_choice
            if loaded is None: return
            previous,previous_owned=icon,icon_owned
            nid.icon=loaded
            if self.visible and tray_added and not shell.Shell_NotifyIconW(1,C.byref(nid)):
                nid.icon=previous
                raise C.WinError(C.get_last_error())
            for window in (self.hwnd,self.dialog):
                if window:
                    u32.SendMessageW(window,0x80,0,loaded)
                    u32.SendMessageW(window,0x80,1,loaded)
            icon,icon_owned,icon_choice=loaded,True,choice
            if release_previous and previous_owned and previous and previous!=loaded: u32.DestroyIcon(previous)

        def theme_fields_enabled():
            if not self.theme_controls: return
            mode=u32.SendMessageW(self.theme_controls[0],0x147,0,0)
            usable=self.icons is not None
            u32.EnableWindow(self.theme_controls[0],usable)
            u32.EnableWindow(self.theme_controls[1],usable and mode==0)
            u32.EnableWindow(self.theme_controls[2],usable and mode==1)

        def tick_theme():
            if self.icons is None: return
            if self.icons.tick():
                loaded=None
                try:
                    loaded=load_theme()
                    commit_icon(loaded,self.icons.current_id())
                    loaded=None
                except Exception as error:
                    self.icons.log("icon_load_failed",Error=type(error).__name__)
                finally:
                    if loaded: u32.DestroyIcon(loaded)

        def settings_dialog(show=True):
            if self.dialog:
                if show: u32.SetForegroundWindow(self.dialog)
                return
            foreground, background, _ = self.settings.snapshot()
            style = 0x00C80000 | 0x80000000 | (0x10000000 if show else 0)
            self.dialog = u32.CreateWindowExW(0x40000,cls,"ChatGPT 标题同步助手 — 扫描间隔设置",style,
                250,250,500,420,None,None,instance,None)
            if not self.dialog: raise C.WinError(C.get_last_error())
            for text,y in [("Foreground source (seconds, 1..3600)",20),
                           ("Background source (seconds, 5..3600)",65),
                           ("Cached-title repair remains every 1 second.",280)]:
                u32.CreateWindowExW(0,"STATIC",text,0x50000000,15,y,300 if y<100 else 400,24,self.dialog,None,instance,None)
            for value,x,y,cid in [(foreground,320,20,2101),(background,320,65,2102)]:
                edit=u32.CreateWindowExW(0x200,"EDIT",format(value,"g"),0x50810080,x,y,85,25,self.dialog,cid,instance,None)
                self.controls.append(edit)
            self.auto_checkbox=u32.CreateWindowExW(0,"BUTTON","开机自启动 / Start at sign-in",0x50010003,15,112,390,26,self.dialog,2103,instance,None)
            sync_startup_checkbox()
            u32.CreateWindowExW(0,"BUTTON","Save / 保存",0x50010001,280,330,90,28,self.dialog,2001,instance,None)
            u32.CreateWindowExW(0,"BUTTON","Cancel / 取消",0x50010000,380,330,90,28,self.dialog,2002,instance,None)
            state=self.icons.state if self.icons else IconPreferences.DEFAULT
            definitions=[("Icon mode / 图标模式",150,2110,["Fixed / 固定","Random / 随机"],0 if state["IconMode"]=="fixed" else 1),
                ("Fixed palette / 固定配色",190,2111,[str(i) for i in IconPreferences.IDS],state["FixedIcon"]-45),
                ("Random period / 随机周期",230,2112,["Daily / 每日","Hourly / 每小时","Every 5 minutes / 每5分钟"],("day","hour","5min").index(state["IconPeriod"]))]
            for label,y,cid,items,selected in definitions:
                u32.CreateWindowExW(0,"STATIC",label,0x50000000,15,y,240,26,self.dialog,None,instance,None)
                combo=u32.CreateWindowExW(0,"COMBOBOX","",0x50210003,265,y,210,180,self.dialog,cid,instance,None)
                for item in items:
                    value=C.create_unicode_buffer(item)
                    u32.SendMessageW(combo,0x143,0,C.cast(value,PTR).value)
                u32.SendMessageW(combo,0x14e,selected,0)
                self.theme_controls.append(combo)
            theme_fields_enabled()
            if icon:
                u32.SendMessageW(self.dialog,0x80,0,icon)
                u32.SendMessageW(self.dialog,0x80,1,icon)
            if show:
                u32.ShowWindow(self.dialog,5)
                u32.SetForegroundWindow(self.dialog)
                u32.SetFocus(self.controls[0])
        self.open_settings = settings_dialog
        self.dismiss_settings = dismiss

        def popup():
            menu=u32.CreatePopupMenu()
            try:
                u32.AppendMenuW(menu,0,1001,"扫描间隔设置… / Scan intervals…")
                u32.AppendMenuW(menu,self.autostart.menu_flags() if self.autostart else 1,1003,"开机自启动 / Start at sign-in")
                u32.AppendMenuW(menu,0x800,0,"ChatGPT 标题同步助手 — Python")
                u32.AppendMenuW(menu,0,1002,"退出并恢复标题 / Exit and restore")
                pt=W.POINT();u32.GetCursorPos(C.byref(pt));u32.SetForegroundWindow(self.hwnd)
                command=u32.TrackPopupMenu(menu,0x180,pt.x,pt.y,0,self.hwnd,None)
                if command==1001: settings_dialog()
                elif command==1003: toggle_startup()
                elif command==1002: k32.SetEvent(self.stop);u32.DestroyWindow(self.hwnd)
                u32.PostMessageW(self.hwnd,0,0,0)
            finally: u32.DestroyMenu(menu)

        @PROC
        def proc(hwnd,message,wparam,lparam):
            nonlocal icon_owned
            try:
                if message==self.CALLBACK and (lparam & 0xffff) in (0x205,0x202,0x7b):
                    popup();return 0
                if message==self.CALLBACK+2 and hwnd==self.hwnd:
                    tick_theme();return 0
                if message==self.CALLBACK+1 and hwnd==self.hwnd:
                    settings_dialog(bool(wparam));return 0
                if message==0x111 and hwnd==self.hwnd:
                    if (wparam & 0xffff)==1001: settings_dialog();return 0
                    if (wparam & 0xffff)==1003: toggle_startup();return 0
                    if (wparam & 0xffff)==1002:
                        k32.SetEvent(self.stop);u32.DestroyWindow(self.hwnd);return 0
                if message==0x111 and hwnd==self.dialog:
                    command=wparam & 0xffff
                    if command==2110 and (wparam>>16)==1: theme_fields_enabled();return 0
                    if command==2002: dismiss();return 0
                    if command==2001:
                        first,second=(caption(h) for h in self.controls)
                        prior = self.autostart.enabled if self.autostart else None
                        auto_changed = False
                        icon_checkpoint = self.icons.checkpoint() if self.icons else None
                        icon_changed,loaded,ui_changed = False,None,False
                        previous_icon=(icon,icon_owned,icon_choice)
                        try:
                            first,second=self.settings.validate(first,second)
                            plan=None
                            if self.icons:
                                selected=[u32.SendMessageW(h,0x147,0,0) for h in self.theme_controls]
                                if any(i<0 for i in selected): raise ValueError("Choose all icon settings")
                                plan=self.icons.prepare(("fixed","random")[selected[0]],45+selected[1],("day","hour","5min")[selected[2]])
                                loaded=load_theme(plan)
                                if loaded:
                                    commit_icon(loaded,self.icons.current_id(plan),False)
                                    ui_changed=True
                                    loaded=None
                            if self.autostart is not None:
                                desired=u32.SendMessageW(self.auto_checkbox,0xf0,0,0)==1
                                self.autostart.set_enabled(desired)
                                auto_changed=desired!=prior
                            if self.icons:
                                self.icons.commit(plan)
                                icon_changed=True
                            self.settings.update(first,second)
                            if ui_changed and previous_icon[1] and previous_icon[0]: u32.DestroyIcon(previous_icon[0])
                        except Exception as error:
                            if ui_changed:
                                try:
                                    commit_icon(previous_icon[0],previous_icon[2])
                                    # Preserve ownership for the shared stock-icon fallback.
                                    icon_owned=previous_icon[1]
                                except Exception as rollback: error=RuntimeError(str(error)+"; icon UI rollback failed: "+str(rollback))
                            if loaded: u32.DestroyIcon(loaded)
                            if icon_changed:
                                try: self.icons.restore(icon_checkpoint)
                                except Exception as rollback: error=RuntimeError(str(error)+"; "+str(rollback))
                            if auto_changed:
                                try: self.autostart.set_enabled(prior)
                                except Exception as rollback: error=RuntimeError(str(error)+"; startup rollback failed: "+str(rollback))
                            sync_startup_checkbox()
                            if not self.visible:
                                self.last_settings_error=str(error);return 0
                            u32.MessageBoxW(hwnd,str(error),"ChatGPT-TitleSync — Settings",0x10);return 0
                        dismiss();return 0
                if message==0x10:
                    if hwnd==self.dialog: dismiss()
                    else:
                        dismiss();k32.SetEvent(self.stop);u32.DestroyWindow(hwnd)
                    return 0
                if message==2 and hwnd==self.hwnd:
                    u32.PostQuitMessage(0);return 0
            except Exception:
                self.error=traceback.format_exc()
                k32.SetEvent(self.stop)
            return u32.DefWindowProcW(hwnd,message,wparam,lparam)
        wc=WC();wc.proc=proc;wc.instance=instance;wc.name=cls;wc.background=16
        try:
            if not u32.RegisterClassW(C.byref(wc)): raise C.WinError(C.get_last_error())
            self.hwnd=u32.CreateWindowExW(0,cls,"ChatGPT-TitleSync Python",0,0,0,0,0,None,None,instance,None)
            if not self.hwnd: raise C.WinError(C.get_last_error())
            large,small=W.HICON(),W.HICON()
            if getattr(sys,"frozen",False):
                shell.ExtractIconExW(sys.executable,0,C.byref(large),C.byref(small),1)
                icon=small.value or large.value;icon_owned=bool(icon)
                if large.value and large.value!=icon: u32.DestroyIcon(large)
            if not icon:
                bind(u32,"LoadImageW",W.HANDLE,W.HINSTANCE,W.LPCWSTR,W.UINT,C.c_int,C.c_int,W.UINT)
                icon_file=Path(__file__).resolve().parents[2]/"assets"/"chatgpt-titlesync.ico"
                if icon_file.exists(): icon=u32.LoadImageW(None,str(icon_file),1,32,32,0x10);icon_owned=bool(icon)
            if not icon: icon=u32.LoadIconW(None,C.c_void_p(32512))
            nid.hwnd=self.hwnd;nid.id=1;nid.flags=7;nid.callback=self.CALLBACK;nid.icon=icon
            nid.tip="ChatGPT-TitleSync / ChatGPT 标题同步助手 — Python: sync conversation names to window titles"
            if self.visible and not shell.Shell_NotifyIconW(0,C.byref(nid)): raise C.WinError(C.get_last_error())
            tray_added=self.visible
            if self.icons:
                loaded=None
                try:
                    loaded=load_theme()
                    commit_icon(loaded,self.icons.current_id())
                    loaded=None
                except Exception as error: self.icons.log("icon_load_failed",Error=type(error).__name__)
                finally:
                    if loaded: u32.DestroyIcon(loaded)
            self.ready.set()
            message=W.MSG()
            while u32.GetMessageW(C.byref(message),None,0,0)>0:
                if self.dialog and u32.IsDialogMessageW(self.dialog,C.byref(message)): continue
                u32.TranslateMessage(C.byref(message));u32.DispatchMessageW(C.byref(message))
        except Exception:
            self.error=traceback.format_exc();self.ready.set();k32.SetEvent(self.stop)
        finally:
            if self.visible: shell.Shell_NotifyIconW(2,C.byref(nid))
            if self.dialog: u32.DestroyWindow(self.dialog)
            if self.hwnd and u32.IsWindow(self.hwnd): u32.DestroyWindow(self.hwnd)
            self.hwnd=0
            if icon_owned and icon: u32.DestroyIcon(icon)
            u32.UnregisterClassW(cls,instance)


def autostart_self_test():
    """No real Run key, named controller IPC, user windows or normal resident."""
    import tempfile
    base=r"Software\ChatGPT-TitleSync-SelfTest"+"\\"+uuid.uuid4().hex
    first=AutoStart(base+r"\Run",base+r"\Preferences",'"C:\\Own app\\Helper.exe"')
    checks=[]
    try:
        first.initialize()
        assert first.enabled is True and first._read_value(first.run_key,first.RUN_VALUE)==(first.command,winreg.REG_SZ)
        checks.append("missing_default_on_registers")
        first.set_enabled(False)
        assert first._read_value(first.run_key,first.RUN_VALUE) is None and first._read_value(first.pref_key,first.PREF_VALUE)==(0,winreg.REG_DWORD)
        checks.append("off_deletes_only_product_run_and_persists_zero")
        second=AutoStart(first.run_key,first.pref_key,'"C:\\Own app\\Replacement.exe"');second.initialize()
        assert second.enabled is False and second._read_value(second.run_key,second.RUN_VALUE) is None
        checks.append("new_variant_preserves_explicit_zero")
        second.set_enabled(True)
        assert second._read_value(second.run_key,second.RUN_VALUE)==(second.command,winreg.REG_SZ)
        checks.append("on_updates_current_absolute_command")
        before_run=second._read_value(second.run_key,second.RUN_VALUE);before_pref=second._read_value(second.pref_key,second.PREF_VALUE)
        real_write=second._write_value;fault=[False]
        def fail_once(path,name,value):
            if path==second.pref_key and not fault[0]:fault[0]=True;raise OSError("Controlled private preference failure")
            real_write(path,name,value)
        second._write_value=fail_once
        try: second.set_enabled(False)
        except RuntimeError: pass
        else: raise AssertionError("failure accepted")
        second._write_value=real_write
        assert second.enabled is True and second._read_value(second.run_key,second.RUN_VALUE)==before_run and second._read_value(second.pref_key,second.PREF_VALUE)==before_pref
        checks.append("failed_preference_write_rolls_back_exact_values")
        source=startup_command(r"C:\Own app\pythonw.exe",r"C:\Own app\source.py",False)
        frozen=startup_command(r"C:\Own app\App.exe",r"C:\Own app\source.py",True)
        assert source=='"C:\\Own app\\pythonw.exe" "C:\\Own app\\source.py"' and frozen=='"C:\\Own app\\App.exe"'
        checks.append("source_and_frozen_commands_have_no_test_arguments")
        calls=[]
        def observe_write(path,name,value): calls.append((path,name));real_write(path,name,value)
        second._write_value=observe_write;second.initialize();second._write_value=real_write
        assert not calls
        checks.append("identical_startup_command_and_preference_do_not_write")
        normal_command=second.command;part=""
        while True:
            boundary=startup_command(r"C:\Own app\pythonw.exe","C:\\"+part+r"\source.py",False)
            if len(boundary.encode("utf-16-le"))//2>=260:break
            part+="x"
        assert len(boundary.encode("utf-16-le"))//2==260
        second.command=boundary;second.set_enabled(True)
        checks.append("source_command_at_260_is_accepted")
        before_run=second._read_value(second.run_key,second.RUN_VALUE);before_pref=second._read_value(second.pref_key,second.PREF_VALUE)
        second.command=startup_command(r"C:\Own app\pythonw.exe","C:\\"+part+"x"+r"\source.py",False)
        try: second.set_enabled(True)
        except ValueError: pass
        else: raise AssertionError("oversize startup command accepted")
        assert second._read_value(second.run_key,second.RUN_VALUE)==before_run and second._read_value(second.pref_key,second.PREF_VALUE)==before_pref
        checks.append("source_command_above_260_rejected_without_registry_change")
        second.set_enabled(False)
        assert second.enabled is False and second._read_value(second.run_key,second.RUN_VALUE) is None
        checks.append("off_remains_available_for_an_oversize_command")
        second.command=normal_command;second.set_enabled(True)
        with tempfile.TemporaryDirectory(prefix="titlesync_startup_") as directory:
            settings=ScanSettings(Path(directory)/"settings.json")
            stop=k32.CreateEventW(None,True,False,None);tray=NativeTray(settings,stop,visible=False,autostart=second)
            try:
                tray.start();u32.PostMessageW(tray.hwnd,tray.CALLBACK+1,0,0)
                due=time.monotonic()+2
                while (not tray.auto_checkbox) and time.monotonic()<due:time.sleep(.01)
                assert tray.auto_checkbox and u32.SendMessageW(tray.auto_checkbox,0xf0,0,0)==1
                checks.append("hidden_settings_checkbox_matches_live_state")
                u32.PostMessageW(tray.hwnd,0x111,1003,0)
                due=time.monotonic()+2
                while second.enabled is True and time.monotonic()<due:time.sleep(.01)
                assert second.enabled is False and u32.SendMessageW(tray.auto_checkbox,0xf0,0,0)==0 and second.menu_flags()==0
                checks.append("menu_toggle_updates_open_settings_checkbox")
                u32.SendMessageW(tray.auto_checkbox,0xf1,1,0)
                assert second.enabled is False
                u32.PostMessageW(tray.dialog,0x111,2002,0)
                due=time.monotonic()+2
                while tray.dialog and time.monotonic()<due:time.sleep(.01)
                assert second.enabled is False
                checks.append("checkbox_cancel_does_not_apply")
                u32.PostMessageW(tray.hwnd,tray.CALLBACK+1,0,0)
                due=time.monotonic()+2
                while not tray.auto_checkbox and time.monotonic()<due:time.sleep(.01)
                u32.SendMessageW(tray.auto_checkbox,0xf1,1,0);u32.PostMessageW(tray.dialog,0x111,2001,0)
                due=time.monotonic()+2
                while tray.dialog and time.monotonic()<due:time.sleep(.01)
                assert second.enabled is True and second.menu_flags()==8 and second._read_value(second.pref_key,second.PREF_VALUE)==(1,winreg.REG_DWORD)
                checks.append("settings_save_updates_menu_and_preference")
            finally:tray.close();k32.CloseHandle(stop)
        print(json.dumps({"Success":True,"Passed":len(checks),"Checks":checks,"RealRunKeyAccessed":False,"RealChatGptAccessed":False,"SharedIpcUsed":False,"CheckboxId":2103,"SaveId":2001,"CancelId":2002},ensure_ascii=True))
        return 0
    finally:
        for path in [first.run_key,first.pref_key,base]:
            try: winreg.DeleteKey(winreg.HKEY_CURRENT_USER,path)
            except FileNotFoundError: pass


def icon_asset_root():
    return (Path(getattr(sys,"_MEIPASS",Path(__file__).parent))/"assets"/"themes" if getattr(sys,"frozen",False) else Path(__file__).resolve().parents[2]/"assets"/"themes")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    # Preserve the legacy settings directory so existing user preferences continue to load.
    parser.add_argument("--settings", type=Path, default=Path(os.environ.get("LOCALAPPDATA",Path.home()))/"ChatGPT-title"/"python"/"settings.json", help="persisted tray interval settings")
    parser.add_argument("--icon-self-test", action="store_true", help="test themes with private registry and hidden owned controls only")
    parser.add_argument("--autostart-self-test", action="store_true", help="test startup on isolated temporary HKCU subkeys only")
    parser.add_argument("--no-tray", action="store_true", help="run without a tray icon")
    parser.add_argument("--interval", type=float, default=2, help="foreground check interval in seconds (default 2); a slow reader may take longer")
    parser.add_argument("--background-interval", type=float, default=5, help="per-window background source refresh, 5..3600 seconds (default 5)")
    parser.add_argument("--_background", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--hwnd", type=int, help="only monitor this native window (optional)")
    parser.add_argument("--once", action="store_true", help="scan once, exit; restore any captions this run wrote")
    parser.add_argument("--read-only", action="store_true", help="read titles without changing captions")
    parser.add_argument("--stop", action="store_true", help="ask the standalone monitor to restore and exit")
    parser.add_argument("--log", type=Path, default=Path(__file__).with_suffix(".jsonl"))
    parser.add_argument("--self-test", action="store_true", help="test caption write/restore on an own hidden fixture")
    parser.add_argument("--_dispatch-smoke", help=argparse.SUPPRESS)
    parser.add_argument("--_read", type=int, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args._dispatch_smoke:
        print(json.dumps({"Success": True, "Token": args._dispatch_smoke, "Payload": "中文😀",
                          "Frozen": bool(getattr(sys, "frozen", False))}, ensure_ascii=False))
        return 0
    if args._read:
        return worker(args._read, args._background)
    if args.icon_self_test:
        from icon_preferences import native_icon_self_test
        return native_icon_self_test(sys.modules[__name__],icon_asset_root())
    if args.autostart_self_test:
        return autostart_self_test()
    if args.self_test:
        return native_self_test()
    if args.stop:
        event = k32.OpenEventW(2, False, STOP_EVENT)
        if event:
            try:
                if not k32.SetEvent(event):
                    raise C.WinError(C.get_last_error())
            finally:
                k32.CloseHandle(event)
        return 0
    if not 5 <= args.background_interval <= 3600:
        parser.error("--background-interval must be 5..3600 seconds")
    if not math.isfinite(args.interval) or not 1 <= args.interval <= 3600:
        parser.error("--interval must be 1..3600 seconds")
    if not math.isfinite(args.background_interval):
        parser.error("--background-interval must be finite")
    C.set_last_error(0)
    mutex = k32.CreateMutexW(None, False, MUTEX)
    if not mutex:
        raise C.WinError(C.get_last_error())
    if C.get_last_error() == 183:
        k32.CloseHandle(mutex)
        parser.error("another AHK/PowerShell/Python standalone monitor is already running")
    stop = k32.CreateEventW(None, True, False, STOP_EVENT)
    if not stop:
        k32.CloseHandle(mutex)
        raise C.WinError(C.get_last_error())
    k32.ResetEvent(stop)
    global MONITOR_STOP
    MONITOR_STOP = stop
    records = {}
    def emit(event, info=None, **details):
        row = {"TimeUtc": utc(), "Event": event}
        if info:
            row["Identity"] = info
        row.update(details)
        args.log.parent.mkdir(parents=True, exist_ok=True)
        with args.log.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(row, ensure_ascii=False) + "\n")
        if sys.stdout:
            print(json.dumps(row, ensure_ascii=False), flush=True)
    settings=ScanSettings(args.settings,args.interval,args.background_interval)
    if not args.once:
        settings.load(any(a=="--interval" or a.startswith("--interval=") for a in sys.argv),
            any(a=="--background-interval" or a.startswith("--background-interval=") for a in sys.argv))
    args.interval,args.background_interval,settings_revision=settings.snapshot()
    autostart=AutoStart() if not args.once and not args.read_only else None
    asset_root=icon_asset_root()
    icons=IconPreferences(AutoStart._read_value,AutoStart._write_value,asset_root,log=emit) if autostart else None
    tray=NativeTray(settings,stop,autostart=autostart,icons=icons) if not args.once and not args.no_tray else None
    known, background_due = {}, {}
    fg, bg = None, None
    next_native = next_foreground = 0.0
    try:
        if autostart:
            try: autostart.initialize()
            except Exception as error:
                startup_error(error)
                raise
        if icons:
            try: icons.initialize()
            except Exception as error: emit("icon_preferences_failed",Error=type(error).__name__)
        if tray: tray.start()
        emit("started", IntervalSeconds=args.interval, BackgroundSeconds=args.background_interval, ReadOnly=args.read_only)
        live = []
        while k32.WaitForSingleObject(stop, 0) != 0:
            now = time.monotonic()
            foreground_interval,background_interval,current_revision=settings.snapshot()
            if current_revision != settings_revision:
                for slot in (fg,bg):
                    if slot: slot.cancel()
                fg=bg=None
                args.interval,args.background_interval=foreground_interval,background_interval
                settings_revision=current_revision
                next_foreground=0.0
                background_due.clear()
                emit("settings_changed",ForegroundSeconds=args.interval,BackgroundSeconds=args.background_interval)
            if now >= next_native:
                next_native = now + 1.0
                if tray: tray.tick_icon()
                elif icons: icons.tick()
                live = [i for i in targets() if not args.hwnd or i["Hwnd"] == args.hwnd]
                live_keys = {key(i) for i in live}
                for stale in list(background_due):
                    if stale not in live_keys:
                        background_due.pop(stale,None)
                maintain_background(known,records,emit,args.read_only)
            active = next((i for i in live if is_active(i)),None)
            if bg and is_active(bg.info):
                bg.cancel()
                bg = None
            for role in ("foreground","background"):
                slot = fg if role == "foreground" else bg
                if slot is None:
                    continue
                result = slot.poll()
                if result is None:
                    continue
                if role == "foreground":
                    fg = None
                else:
                    bg = None
                info = slot.info
                if result.get("Success"):
                    title = result["Title"]
                    if role == "foreground" and is_active(info):
                        known[key(info)] = {"Identity":info,"Title":title}
                        if not args.read_only:
                            update_caption(info,title,records,emit)
                    elif role == "background":
                        apply_background(info,title,known,records,emit,args.read_only)
                    emit("source_observed",info,Role=role)
                else:
                    emit("read_failed",info,Role=role,Error=result.get("Error"))
                if args.once and role == "foreground":
                    return 0
            if active and fg is None and (now >= next_foreground or getattr(main,"_active_key",None) != key(active)):
                main._active_key = key(active)
                next_foreground = now + args.interval
                fg = ReaderSlot(active)
                background_due[key(active)] = now + args.background_interval
            if not active:
                main._active_key = None
            if bg is None and not args.once:
                candidates = [i for i in live if not is_active(i) and now >= background_due.get(key(i),0)]
                if candidates:
                    info = min(candidates,key=lambda i:background_due.get(key(i),0))
                    background_due[key(info)] = now + args.background_interval
                    bg = ReaderSlot(info,True)
            if args.once and not active and fg is None:
                break
            k32.WaitForSingleObject(stop,50)
    except KeyboardInterrupt:
        pass
    finally:
        if tray: tray.close()
        for slot in (fg,bg):
            if slot:
                slot.cancel()
        for record in list(records.values()):
            restore(record, emit)
        emit("stopped")
        k32.CloseHandle(stop)
        k32.CloseHandle(mutex)
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        if sys.stderr:
            print(str(error), file=sys.stderr)
        raise SystemExit(1)
