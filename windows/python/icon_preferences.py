"""Shared HKCU icon policy. No window access, title reads or normal startup side effects.

Only the resident controller creates this object. Injected persistence, local clock,
asset validation and random selection make policy/rollback tests independent of Run.
"""
import datetime as dt
from pathlib import Path
import random
import threading
import winreg


class IconPreferences:
    KEY = r"Software\ChatGPT-TitleSync"
    TYPES = {"IconMode": winreg.REG_SZ, "FixedIcon": winreg.REG_DWORD,
             "IconPeriod": winreg.REG_SZ, "RandomIcon": winreg.REG_DWORD,
             "IconSlot": winreg.REG_SZ}
    DEFAULT = {"IconMode": "fixed", "FixedIcon": 45, "IconPeriod": "day",
               "RandomIcon": 45, "IconSlot": ""}
    IDS = tuple(range(45, 53))

    def __init__(self, read, write, assets, key=None, clock=None, picker=None, log=None):
        self.read, self.write = read, write
        self.assets, self.key = Path(assets), key or self.KEY
        self.clock = clock or (lambda: dt.datetime.now().astimezone())
        self.picker = picker or random.SystemRandom().choice
        self.log = log or (lambda event, **details: None)
        self.state = dict(self.DEFAULT)
        self.lock = threading.RLock()
        self.last_error_slot = None

    @staticmethod
    def slot(period, now):
        if now.tzinfo is None: now = now.astimezone()
        if period == "day": return now.strftime("%Y%m%d")
        if period == "hour": return now.strftime("%Y%m%d%H%z")
        if period == "5min": return now.strftime("%Y%m%d%H") + f"{now.minute//5:02d}" + now.strftime("%z")
        raise ValueError("Icon period must be day, hour or 5min")

    @classmethod
    def validate_values(cls, mode, fixed, period):
        if mode not in ("fixed", "random"): raise ValueError("Icon mode must be fixed or random")
        if type(fixed) is not int or fixed not in cls.IDS: raise ValueError("Fixed icon must be 45..52")
        if period not in ("day", "hour", "5min"): raise ValueError("Icon period must be day, hour or 5min")

    def validate_assets(self, mode, fixed):
        for number in self.IDS if mode == "random" else (fixed,):
            path = self.assets / (str(number) + ".ico")
            # Validate the ICO directory before making any settings/registry changes.
            with path.open("rb") as file: header = file.read(6)
            if len(header) != 6 or header[:4] != b"\x00\x00\x01\x00" or int.from_bytes(header[4:], "little") < 1:
                raise ValueError("Invalid icon asset: " + path.name)

    def checkpoint(self):
        with self.lock:
            return ({name: self.read(self.key, name) for name in self.TYPES}, dict(self.state))

    def restore(self, checkpoint):
        values, state = checkpoint
        failures = []
        with self.lock:
            for name, value in values.items():
                try:
                    if self.read(self.key, name) != value: self.write(self.key, name, value)
                except Exception as error: failures.append(str(error))
            if failures: raise RuntimeError("Icon rollback failed: " + "; ".join(failures))
            self.state = dict(state)

    def current_id(self, plan=None):
        state = self.state if plan is None else plan
        return state["FixedIcon"] if state["IconMode"] == "fixed" else state["RandomIcon"]

    def field_enabled(self, mode):
        return mode == "fixed", mode == "random"

    def prepare(self, mode, fixed, period):
        """Choose at most once, before saving; the returned plan can be validated/loaded first."""
        self.validate_values(mode, fixed, period)
        self.validate_assets(mode, fixed)
        with self.lock:
            plan = dict(self.state, IconMode=mode, FixedIcon=fixed, IconPeriod=period)
            if mode == "random":
                slot = self.slot(period, self.clock())
                if (self.state["IconMode"] != mode or self.state["IconPeriod"] != period
                        or self.state["IconSlot"] != slot or self.state["RandomIcon"] not in self.IDS):
                    choices = tuple(i for i in self.IDS if i != self.state["RandomIcon"])
                    chosen = self.picker(choices)
                    if chosen not in choices: raise ValueError("Icon picker returned an invalid or repeated choice")
                    plan["RandomIcon"], plan["IconSlot"] = chosen, slot
            return plan

    def commit(self, plan):
        """Update only the five named icon values; exact snapshots support outer Save rollback."""
        self.validate_values(plan["IconMode"], plan["FixedIcon"], plan["IconPeriod"])
        if plan["RandomIcon"] not in self.IDS or not isinstance(plan["IconSlot"], str):
            raise ValueError("Invalid random icon state")
        self.validate_assets(plan["IconMode"], plan["FixedIcon"])
        with self.lock:
            before = self.checkpoint()
            try:
                for name, kind in self.TYPES.items():
                    value = (plan[name], kind)
                    if before[0][name] != value: self.write(self.key, name, value)
            except Exception as error:
                try: self.restore(before)
                except Exception as rollback: raise RuntimeError(str(error) + "; " + str(rollback)) from error
                raise RuntimeError("Icon update failed; previous values retained: " + str(error)) from error
            self.state = dict(plan)
            self.last_error_slot = None
        return self.current_id()

    def initialize(self):
        loaded = dict(self.DEFAULT)
        for name, kind in self.TYPES.items():
            value = self.read(self.key, name)
            if value is not None:
                if value[1] != kind: raise ValueError("Invalid registry type for " + name)
                loaded[name] = value[0]
        self.validate_values(loaded["IconMode"], loaded["FixedIcon"], loaded["IconPeriod"])
        if loaded["RandomIcon"] not in self.IDS or not isinstance(loaded["IconSlot"], str):
            raise ValueError("Invalid persisted random icon state")
        self.validate_assets(loaded["IconMode"], loaded["FixedIcon"])
        self.state = loaded
        if loaded["IconMode"] == "random":
            plan = self.prepare(loaded["IconMode"], loaded["FixedIcon"], loaded["IconPeriod"])
            if plan != loaded: self.commit(plan)
        return self.current_id()

    def tick(self):
        """Called on the existing metadata timer; same-slot checks perform no registry/file I/O."""
        with self.lock:
            if self.state["IconMode"] != "random": return False
            slot = self.slot(self.state["IconPeriod"], self.clock())
            if slot == self.state["IconSlot"] or slot == self.last_error_slot: return False
            try:
                self.commit(self.prepare("random", self.state["FixedIcon"], self.state["IconPeriod"]))
                return True
            except Exception as error:
                self.last_error_slot = slot
                self.log("icon_rotation_failed", Error=type(error).__name__, Slot=slot)
                return False


def native_icon_self_test(m, assets_root):
    """Private HKCU and hidden owned controls; never normal IPC, real Run or GPT."""
    import tempfile,shutil,json,time,uuid
    tray,stop=None,None
    base=r'Software\ChatGPT-TitleSync-SelfTest\themes_'+uuid.uuid4().hex;key=base+r'\Preferences';checks=[]
    def check(n,v):
     assert v,n
     checks.append(n)
    def wait(f):
     due=time.monotonic()+3
     while not f():
      if time.monotonic()>due:raise AssertionError('Own hidden UI timed out')
      time.sleep(.01)
    try:
     with tempfile.TemporaryDirectory(prefix='titlesync-own-icons-') as d:
      assets=Path(d)/'themes';assets.mkdir()
      for i in range(45,53):shutil.copyfile(Path(assets_root)/(str(i)+'.ico'),assets/(str(i)+'.ico'))
      now=[dt.datetime(2026,11,11,12,4,59,tzinfo=dt.timezone(dt.timedelta(hours=8)))];writes=[];logs=[]
      def write(k,n,v):writes.append((n,v));m.AutoStart._write_value(k,n,v)
      seq=[45]
      def pick(choices):
       target=45+(seq[0]-44)%8;seq[0]=target
       return target if target in choices else choices[0]
      prefs=IconPreferences(m.AutoStart._read_value,write,assets,key=key,clock=lambda:now[0],picker=pick,log=lambda *a,**k:logs.append((a,k)))
      prefs.initialize();check('defaults_are_fixed_45_and_read_only',prefs.current_id()==45 and prefs.state['IconMode']=='fixed' and not writes)
      for i in range(45,53):prefs.commit(prefs.prepare('fixed',i,'day'));check('fixed_id_'+str(i),prefs.current_id()==i)
      for args in [('bad',45,'day'),('fixed',44,'day'),('random',53,'hour'),('fixed',45,'week')]:
       before=prefs.checkpoint()
       try:prefs.prepare(*args)
       except ValueError:pass
       else:raise AssertionError('invalid selection accepted')
       check('invalid_unchanged_'+str(args),prefs.checkpoint()==before)
      before=prefs.checkpoint();plan=prefs.prepare('random',45,'day');check('cancel_prepared_plan_is_uncommitted',prefs.checkpoint()==before)
      prefs.commit(plan);check('random_enable_immediate_nonrepeat',prefs.current_id()!=before[1]['RandomIcon'] and prefs.state['IconSlot']=='20261111')
      count=len(writes);again=IconPreferences(m.AutoStart._read_value,write,assets,key=key,clock=lambda:now[0],picker=lambda x:(_ for _ in ()).throw(AssertionError('same slot picked')));again.initialize();check('restart_same_slot_keeps_id_and_does_not_write',again.state==prefs.state and len(writes)==count)
      for period,prior,after,expected in [('hour',dt.datetime(2026,11,11,12,59,59,tzinfo=now[0].tzinfo),dt.datetime(2026,11,11,13,0,0,tzinfo=now[0].tzinfo),'2026111113+0800'),('5min',dt.datetime(2026,11,11,13,4,59,tzinfo=now[0].tzinfo),dt.datetime(2026,11,11,13,5,0,tzinfo=now[0].tzinfo),'202611111301+0800'),('day',dt.datetime(2026,11,11,23,59,59,tzinfo=now[0].tzinfo),dt.datetime(2026,11,12,0,0,0,tzinfo=now[0].tzinfo),'20261112')]:
       now[0]=prior;prefs.commit(prefs.prepare('random',45,period));old=prefs.current_id();now[0]=after;check(period+'_boundary_nonrepeat',prefs.tick() and prefs.current_id()!=old and prefs.state['IconSlot']==expected)
      prefs.commit(prefs.prepare('fixed',45,'day'));before=prefs.checkpoint();now[0]+=dt.timedelta(days=1);check('fixed_mode_never_rotates',not prefs.tick() and prefs.checkpoint()==before)
      prefs.commit(prefs.prepare('random',45,'hour'));before=prefs.checkpoint();now[0]+=dt.timedelta(hours=1);removed=assets/'52.ico';old=removed.read_bytes();removed.unlink();check('missing_asset_keeps_state',not prefs.tick() and prefs.checkpoint()==before);prefs.tick();check('missing_asset_error_bounded_per_slot',len(logs)==1);removed.write_bytes(old);now[0]+=dt.timedelta(hours=1);check('later_slot_recovers_after_asset_restored',prefs.tick())
      before=prefs.checkpoint();bad=[True]
      def failed_write(k,n,v):
       if n=='IconPeriod' and bad[0]:bad[0]=False;raise PermissionError('own injected registry failure')
       write(k,n,v)
      prefs.write=failed_write
      try:prefs.commit(prefs.prepare('random',45,'5min'))
      except RuntimeError:pass
      else:raise AssertionError('write failure was not raised')
      check('registry_failure_rolls_back_all_five_exact_values',prefs.checkpoint()==before);prefs.write=write
      check('exact_offset_disambiguates_repeated_local_hour',IconPreferences.slot('hour',dt.datetime(2026,11,1,1,tzinfo=dt.timezone(dt.timedelta(hours=-4))))!=IconPreferences.slot('hour',dt.datetime(2026,11,1,1,tzinfo=dt.timezone(dt.timedelta(hours=-5)))))
      # Only hidden self-created native controls are used below; no real tray entry exists.
      settings=m.ScanSettings(Path(d)/'settings.json');auto=m.AutoStart(base+r'\Run',key,'"C:\\Own app\\Helper.exe"');auto.initialize();stop=m.k32.CreateEventW(None,True,False,None);tray=m.NativeTray(settings,stop,visible=False,autostart=auto,icons=prefs);tray.start()
      m.bind(m.u32,'IsWindowEnabled',m.BOOL,m.W.HWND);m.bind(m.u32,'CopyIcon',m.W.HICON,m.W.HICON)
      m.u32.PostMessageW(tray.hwnd,tray.CALLBACK+1,0,0);wait(lambda:bool(tray.dialog) and len(tray.theme_controls)==3)
      check('only_two_native_numeric_edit_controls_preserved',len(tray.controls)==2)
      check('three_combos_are_noneditable_and_ids_stable',[m.u32.SendMessageW(h,0x147,0,0) for h in tray.theme_controls]==[1,0,1])
      mode,fixed,period=tray.theme_controls;check('random_fields_enabled_only',not m.u32.IsWindowEnabled(fixed) and m.u32.IsWindowEnabled(period))
      before=prefs.checkpoint();m.u32.SendMessageW(mode,0x14e,0,0);m.u32.PostMessageW(tray.dialog,0x111,(1<<16)|2110,mode);wait(lambda:bool(m.u32.IsWindowEnabled(fixed)));check('fixed_fields_enabled_only',not m.u32.IsWindowEnabled(period));m.u32.PostMessageW(tray.dialog,0x111,2002,0);wait(lambda:not tray.dialog);check('native_cancel_preserves_committed_theme',prefs.checkpoint()==before)
      m.u32.PostMessageW(tray.hwnd,tray.CALLBACK+1,0,0);wait(lambda:bool(tray.dialog) and len(tray.theme_controls)==3)
      for h,v in zip(tray.theme_controls,[0,5,2]):m.u32.SendMessageW(h,0x14e,v,0)
      m.u32.SetWindowTextW(tray.controls[0],'3');m.u32.SetWindowTextW(tray.controls[1],'10');m.u32.SendMessageW(tray.auto_checkbox,0xf1,0,0);m.u32.PostMessageW(tray.dialog,0x111,2001,0);wait(lambda:not tray.dialog or tray.last_settings_error)
      check('native_save_commits_icon_intervals_and_startup',not tray.dialog and prefs.current_id()==50 and settings.snapshot()[:2]==(3,10) and not auto.enabled)
      m.u32.PostMessageW(tray.hwnd,tray.CALLBACK+1,0,0);wait(lambda:bool(tray.dialog) and len(tray.theme_controls)==3);before=prefs.checkpoint();old_icon=m.u32.SendMessageW(tray.dialog,0x7f,0,0)
      original_update=settings.update
      def fail_intervals(*a):raise OSError('own injected interval save failure')
      settings.update=fail_intervals
      m.u32.SendMessageW(tray.theme_controls[1],0x14e,0,0);m.u32.SendMessageW(tray.auto_checkbox,0xf1,1,0);m.u32.PostMessageW(tray.dialog,0x111,2001,0);wait(lambda:tray.last_settings_error is not None)
      check('failed_save_restores_theme_startup_and_interval_state',prefs.checkpoint()==before and not auto.enabled and settings.snapshot()[:2]==(3,10))
      current=m.u32.SendMessageW(tray.dialog,0x7f,0,0);duplicate=m.u32.CopyIcon(current);check('rollback_restores_live_previous_own_icon',current==old_icon and bool(duplicate));m.u32.DestroyIcon(duplicate);settings.update=original_update
      prefs.commit(prefs.prepare('random',50,'hour'));now[0]+=dt.timedelta(hours=1);expected_slot=prefs.slot('hour',now[0]);tray.tick_icon();wait(lambda:prefs.state['IconSlot']==expected_slot);check('existing_metadata_timer_callback_rotates_without_source_read',prefs.state['IconSlot']==expected_slot)
      tray.close();check('normal_hidden_ui_exit_disposes_owned_window',not tray.thread.is_alive() and not tray.error);m.k32.CloseHandle(stop);stop=None
    finally:
     if tray is not None:tray.close()
     if stop:m.k32.CloseHandle(stop)
     for name in ('Run','Preferences'):
      try:winreg.DeleteKey(winreg.HKEY_CURRENT_USER,base+'\\'+name)
      except FileNotFoundError:pass
     try:winreg.DeleteKey(winreg.HKEY_CURRENT_USER,base)
     except FileNotFoundError:pass
    result={'Success':True,'Passed':len(checks),'Checks':checks,'RealRunAccessed':False,'RealPreferenceAccessed':False,'RealWindowsAccessed':False,'TrayShown':False,'NormalResidentStarted':False,'NewComboIds':[2110,2111,2112]}
    print(json.dumps(result))
    return 0
