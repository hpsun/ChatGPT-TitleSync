"""Independent requirements simulation only: no AppKit, AX, UserDefaults or native build.

The three Mac frontends remain uncompiled/unverified on this Windows host. This
model checks the shared state/transaction contract, not the Objective-C bridge,
Swift type checker, NSImage lifetime, UI pixels or login-item behavior.
"""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path
import argparse
import json
import unittest

NAMES=("IconMode","FixedIcon","IconPeriod","RandomIcon","IconSlot")
DEFAULT=dict(zip(NAMES,("fixed",45,"day",45,"")))
IDS=tuple(range(45,53))

class Preferences(dict):
    def __init__(self):
        super().__init__(AutoStartEnabled=False,Unrelated="keep")
        self.writes=[]
        self.fail=None
    def put(self,key,value):
        if key==self.fail:
            self.fail=None
            raise OSError("injected private persistence failure")
        self.writes.append(key)
        self[key]=value

class IconModel:
    def __init__(self,store,clock,picker):
        self.store,self.clock,self.picker=store,clock,picker
        self.state=dict(DEFAULT)
        self.assets=set(IDS)
        self.failed_slot=None
        self.errors=[]
        self.image=45
        self.startup={"enabled":False,"plist":b"original owned plist"}
        self.scan={"fg":2,"bg":5,"unknown":"preserve"}
    @staticmethod
    def slot(period,date):
        if period=="day":return date.strftime("%Y%m%d")
        if period=="hour":return date.strftime("%Y%m%d%H%z")
        if period=="5min":return date.strftime("%Y%m%d%H")+f"{date.minute//5:02d}"+date.strftime("%z")
        raise ValueError("bad period")
    def validate(self,state):
        if state["IconMode"] not in ("fixed","random"):raise ValueError("bad mode")
        if type(state["FixedIcon"]) is not int or state["FixedIcon"] not in IDS:raise ValueError("bad fixed")
        if state["IconPeriod"] not in ("day","hour","5min"):raise ValueError("bad period")
        if type(state["RandomIcon"]) is not int or state["RandomIcon"] not in IDS:raise ValueError("bad random")
        if not isinstance(state["IconSlot"],str):raise ValueError("bad slot")
        needed=set(IDS) if state["IconMode"]=="random" else {state["FixedIcon"]}
        if not needed<=self.assets:raise OSError("owned image asset missing")
    @staticmethod
    def number(state):return state["FixedIcon"] if state["IconMode"]=="fixed" else state["RandomIcon"]
    def prepare(self,mode,fixed,period):
        plan=dict(self.state,IconMode=mode,FixedIcon=fixed,IconPeriod=period)
        self.validate(plan)
        if mode=="random":
            slot=self.slot(period,self.clock())
            if self.state["IconMode"]!=mode or self.state["IconPeriod"]!=period or self.state["IconSlot"]!=slot:
                choices=[i for i in IDS if i!=self.state["RandomIcon"]]
                selected=self.picker(choices)
                if selected not in choices:raise ValueError("invalid/repeated picker result")
                plan.update(RandomIcon=selected,IconSlot=slot)
        return plan
    def snapshot(self):return ({key:deepcopy(self.store[key]) for key in NAMES if key in self.store},dict(self.state))
    def restore(self,before):
        values,state=before
        for key in NAMES:
            if key in values:self.store[key]=deepcopy(values[key])
            else:self.store.pop(key,None)
        self.state=dict(state)
    def commit(self,plan):
        self.validate(plan);before=self.snapshot()
        try:
            for key in NAMES:
                if key not in self.store or self.store[key]!=plan[key]:self.store.put(key,plan[key])
        except Exception:
            self.restore(before)
            raise
        self.state=dict(plan);self.failed_slot=None
    def initialize(self):
        loaded=dict(DEFAULT)
        for key in NAMES:
            if key in self.store:loaded[key]=self.store[key]
        self.validate(loaded);self.state=loaded
        if loaded["IconMode"]=="random":
            plan=self.prepare(loaded["IconMode"],loaded["FixedIcon"],loaded["IconPeriod"])
            if plan!=loaded:self.commit(plan)
        self.image=self.number(self.state)
    def tick(self,paused=False):
        # paused belongs to title work and intentionally does not gate this path.
        if self.state["IconMode"]!="random":return False
        slot=self.slot(self.state["IconPeriod"],self.clock())
        if slot in (self.state["IconSlot"],self.failed_slot):return False
        try:
            plan=self.prepare("random",self.state["FixedIcon"],self.state["IconPeriod"])
            self.commit(plan);self.image=self.number(plan);return True
        except Exception:
            self.failed_slot=slot;self.errors.append(slot);return False
    def save(self,mode,fixed,period,enabled,fg=2,bg=5,fail=None):
        if type(fg)is not int or not 1<=fg<=3600 or type(bg)is not int or not 5<=bg<=3600:raise ValueError("bad intervals")
        plan=self.prepare(mode,fixed,period) # Assets validated before startup changes.
        before=self.snapshot();startup=deepcopy(self.startup);scan=deepcopy(self.scan);image=self.image
        try:
            if fail=="startup":raise OSError("startup save")
            self.startup={"enabled":enabled,"plist":b"new owned plist" if enabled else None}
            self.commit(plan)
            if fail=="interval":raise OSError("interval save")
            self.scan={"fg":fg,"bg":bg}
            self.image=self.number(plan)
        except Exception:
            self.restore(before);self.startup=startup;self.scan=scan;self.image=image
            raise

class MacIconContractTests(unittest.TestCase):
    def setUp(self):
        self.now=datetime(2026,11,11,12,4,59,tzinfo=timezone(timedelta(hours=8)))
        self.store=Preferences();self.model=IconModel(self.store,lambda:self.now,lambda choices:choices[0]);self.model.initialize()
    def random(self,period="day"):
        self.model.commit(self.model.prepare("random",45,period));self.model.image=self.model.number(self.model.state)
    def test_missing_defaults_are_read_only(self):
        self.assertEqual(self.model.state,DEFAULT);self.assertFalse(self.store.writes)
    def test_all_eight_fixed_palettes(self):
        for i in IDS:self.model.save("fixed",i,"day",False);self.assertEqual(self.model.image,i)
    def test_all_eight_random_choices_possible(self):
        for i in IDS:
            self.model.state["RandomIcon"]=45 if i!=45 else 46
            self.model.state["IconMode"]="fixed"
            self.model.picker=lambda choices,wanted=i:wanted
            self.assertEqual(self.model.prepare("random",45,"day")["RandomIcon"],i)
    def test_invalid_values_do_not_write(self):
        before=deepcopy(dict(self.store))
        for args in [("bad",45,"day"),("fixed",44,"day"),("random",53,"hour"),("fixed",45,"week")]:
            with self.assertRaises(ValueError):self.model.save(*args,True)
            self.assertEqual(dict(self.store),before)
    def test_invalid_saved_type_does_not_overwrite(self):
        self.store["FixedIcon"]="45";before=dict(self.store)
        with self.assertRaises(ValueError):self.model.initialize()
        self.assertEqual(dict(self.store),before)
    def test_enabling_random_selects_immediately(self):
        self.random();self.assertNotEqual(self.model.image,45)
    def test_changing_period_selects_immediately(self):
        self.random();old=self.model.state["RandomIcon"];self.random("hour");self.assertNotEqual(self.model.state["RandomIcon"],old)
    def test_same_slot_restart_reuses_selection(self):
        self.random();count=len(self.store.writes)
        def forbidden(choices):raise AssertionError("same-slot repick")
        again=IconModel(self.store,lambda:self.now,forbidden);again.initialize()
        self.assertEqual(again.state,self.model.state);self.assertEqual(len(self.store.writes),count)
    def test_daily_boundary(self):
        self.random();old=self.model.image;self.now+=timedelta(days=1)
        self.assertTrue(self.model.tick());self.assertNotEqual(self.model.image,old);self.assertEqual(self.model.state["IconSlot"],"20261112")
    def test_hourly_boundary(self):
        self.random("hour");self.now+=timedelta(hours=1);self.assertTrue(self.model.tick());self.assertEqual(self.model.state["IconSlot"],"2026111113+0800")
    def test_five_minute_boundary(self):
        self.random("5min");self.now+=timedelta(seconds=1);self.assertTrue(self.model.tick());self.assertEqual(self.model.state["IconSlot"],"202611111201+0800")
    def test_offset_disambiguates_repeated_hour(self):
        a=datetime(2026,11,1,1,tzinfo=timezone(timedelta(hours=-4)));b=a.replace(tzinfo=timezone(timedelta(hours=-5)))
        self.assertNotEqual(IconModel.slot("hour",a),IconModel.slot("hour",b))
    def test_fixed_timer_does_no_persistence(self):
        before=self.model.snapshot();self.now+=timedelta(days=30);self.assertFalse(self.model.tick());self.assertEqual(self.model.snapshot(),before)
    def test_no_adjacent_repeats(self):
        self.random("hour")
        for i in range(20):old=self.model.image;self.now+=timedelta(hours=1);self.assertTrue(self.model.tick());self.assertNotEqual(self.model.image,old)
    def test_pause_does_not_stop_icon_timer(self):
        self.random("hour");self.now+=timedelta(hours=1);self.assertTrue(self.model.tick(paused=True))
    def test_missing_asset_keeps_old_image_and_bounds_error(self):
        self.random("hour");old=self.model.image;before=self.model.snapshot();self.model.assets.remove(52);self.now+=timedelta(hours=1)
        self.assertFalse(self.model.tick());self.assertFalse(self.model.tick());self.assertEqual(len(self.model.errors),1);self.assertEqual(self.model.image,old);self.assertEqual(self.model.snapshot(),before)
    def test_asset_return_allows_later_slot(self):
        self.random("hour");self.model.assets.remove(52);self.now+=timedelta(hours=1);self.model.tick();self.model.assets.add(52);self.now+=timedelta(hours=1);self.assertTrue(self.model.tick())
    def test_cancel_prepared_plan_changes_nothing(self):
        before=self.model.snapshot();self.model.prepare("random",50,"hour");self.assertEqual(self.model.snapshot(),before)
    def test_named_value_failure_restores_only_icon_values(self):
        self.random();before=self.model.snapshot();self.store.fail="IconPeriod"
        with self.assertRaises(OSError):self.model.commit(self.model.prepare("random",45,"hour"))
        self.assertEqual(self.model.snapshot(),before);self.assertEqual(self.store["Unrelated"],"keep");self.assertFalse(self.store["AutoStartEnabled"])
    def test_interval_failure_restores_theme_startup_and_config(self):
        before=self.model.snapshot();startup=deepcopy(self.model.startup);scan=deepcopy(self.model.scan);image=self.model.image
        with self.assertRaises(OSError):self.model.save("random",50,"hour",True,3,10,fail="interval")
        self.assertEqual(self.model.snapshot(),before);self.assertEqual(self.model.startup,startup);self.assertEqual(self.model.scan,scan);self.assertEqual(self.model.image,image)
    def test_startup_failure_leaves_theme_and_intervals(self):
        before=self.model.snapshot();scan=deepcopy(self.model.scan)
        with self.assertRaises(OSError):self.model.save("random",50,"hour",True,3,10,fail="startup")
        self.assertEqual(self.model.snapshot(),before);self.assertEqual(self.model.scan,scan)
    def test_asset_validation_precedes_startup_changes(self):
        startup=deepcopy(self.model.startup);self.model.assets.remove(52)
        with self.assertRaises(OSError):self.model.save("random",45,"day",True)
        self.assertEqual(self.model.startup,startup);self.assertFalse(self.store.writes)
    def test_applescript_companion_still_requires_eleven_arguments(self):
        source=Path(__file__).with_name("TraySettings.applescript").read_text(encoding="utf-8")
        self.assertIn("if (count argv) is not 11",source);self.assertIn("set launchExecutable to item 11 of argv",source)
        self.assertIn("baseImagePath",source);self.assertIn('"/themes"',source)

if __name__=="__main__":
    parser=argparse.ArgumentParser();parser.add_argument("--report",type=Path);args=parser.parse_args()
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(MacIconContractTests))
    report={"kind":"MAC ICON REQUIREMENTS SIMULATION ONLY","success":result.wasSuccessful(),"testsRun":result.testsRun,"failures":len(result.failures),"errors":len(result.errors),"nativeMacCompiled":False,"nativeUserDefaultsVerified":False,"nativeAppKitOrAppleScriptVerified":False,"realAXCalls":False,"realMacPixels":False}
    if args.report:args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2),encoding="utf-8")
    raise SystemExit(0 if result.wasSuccessful() else 1)
