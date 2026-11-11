"""Policy-only tests: fake persistence/assets/clock; no registry, resident or native UI."""
import datetime as dt
from pathlib import Path
import sys
import tempfile
import unittest
import winreg
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from icon_preferences import IconPreferences


class IconPolicyTests(unittest.TestCase):
    def setUp(self):
        self.folder=tempfile.TemporaryDirectory(prefix="titlesync-icon-policy-")
        self.assets=Path(self.folder.name)
        # Header-only stubs exercise policy file validation, never native LoadImage.
        for number in IconPreferences.IDS:
            (self.assets/(str(number)+".ico")).write_bytes(b"\0\0\1\0\1\0")
        self.values={"AutoStartEnabled":(0,winreg.REG_DWORD),"UnrelatedValue":("keep",winreg.REG_SZ)}
        self.writes=[]
        self.fail_once=None
        self.now=dt.datetime(2026,11,11,12,4,59,tzinfo=dt.timezone(dt.timedelta(hours=8)))
        self.logs=[]
        self.policy=self.make()
        self.policy.initialize()

    def tearDown(self):
        self.folder.cleanup()

    def read(self,key,name):
        self.assertEqual(key,"private-fake-key")
        return self.values.get(name)

    def write(self,key,name,value):
        self.assertEqual(key,"private-fake-key")
        self.assertIn(name,IconPreferences.TYPES)
        if name==self.fail_once:
            self.fail_once=None
            raise PermissionError("injected owned-persistence failure")
        self.writes.append((name,value))
        if value is None:self.values.pop(name,None)
        else:self.values[name]=value

    def make(self,picker=None):
        return IconPreferences(self.read,self.write,self.assets,key="private-fake-key",
            clock=lambda:self.now,picker=picker or (lambda choices:choices[0]),
            log=lambda *args,**kwargs:self.logs.append((args,kwargs)))

    def save(self,mode="random",fixed=45,period="day"):
        self.policy.commit(self.policy.prepare(mode,fixed,period))

    def test_missing_defaults_do_not_write(self):
        self.assertEqual(self.policy.current_id(),45)
        self.assertFalse(self.writes)

    def test_all_eight_fixed_ids(self):
        for number in IconPreferences.IDS:
            self.save("fixed",number)
            self.assertEqual(self.policy.current_id(),number)

    def test_invalid_fields_leave_memory_and_storage(self):
        before=self.policy.checkpoint()
        for args in [("bad",45,"day"),("fixed",44,"day"),("fixed",53,"day"),("random",45,"week")]:
            with self.assertRaises(ValueError):self.policy.prepare(*args)
            self.assertEqual(self.policy.checkpoint(),before)

    def test_exact_cross_language_slots(self):
        self.assertEqual(IconPreferences.slot("day",self.now),"20261111")
        self.assertEqual(IconPreferences.slot("hour",self.now),"2026111112+0800")
        self.assertEqual(IconPreferences.slot("5min",self.now),"202611111200+0800")

    def test_hour_offset_disambiguates_dst_repeat(self):
        a=dt.datetime(2026,11,1,1,tzinfo=dt.timezone(dt.timedelta(hours=-4)))
        b=dt.datetime(2026,11,1,1,tzinfo=dt.timezone(dt.timedelta(hours=-5)))
        self.assertNotEqual(IconPreferences.slot("hour",a),IconPreferences.slot("hour",b))

    def test_enabling_random_selects_immediately(self):
        self.save()
        self.assertNotEqual(self.policy.current_id(),45)
        self.assertEqual(self.policy.state["IconSlot"],"20261111")

    def test_same_slot_restart_does_not_pick_or_write(self):
        self.save();before=dict(self.values);count=len(self.writes)
        def forbidden(choices):raise AssertionError("same-slot picker invoked")
        again=self.make(forbidden);again.initialize()
        self.assertEqual(again.state,self.policy.state)
        self.assertEqual(self.values,before)
        self.assertEqual(len(self.writes),count)

    def test_period_change_selects_immediately(self):
        self.save();prior=self.policy.current_id();self.save(period="hour")
        self.assertNotEqual(self.policy.current_id(),prior)
        self.assertEqual(self.policy.state["IconSlot"],"2026111112+0800")

    def test_daily_boundary(self):
        self.save();prior=self.policy.current_id();self.now+=dt.timedelta(days=1)
        self.assertTrue(self.policy.tick());self.assertNotEqual(self.policy.current_id(),prior)
        self.assertEqual(self.policy.state["IconSlot"],"20261112")

    def test_hourly_boundary(self):
        self.save(period="hour");prior=self.policy.current_id();self.now+=dt.timedelta(hours=1)
        self.assertTrue(self.policy.tick());self.assertNotEqual(self.policy.current_id(),prior)
        self.assertEqual(self.policy.state["IconSlot"],"2026111113+0800")

    def test_five_minute_boundary(self):
        self.save(period="5min");prior=self.policy.current_id();self.now+=dt.timedelta(seconds=1)
        self.assertTrue(self.policy.tick());self.assertNotEqual(self.policy.current_id(),prior)
        self.assertEqual(self.policy.state["IconSlot"],"202611111201+0800")

    def test_fixed_mode_never_rotates(self):
        self.save("fixed",51);before=self.policy.checkpoint();self.now+=dt.timedelta(days=10)
        self.assertFalse(self.policy.tick());self.assertEqual(self.policy.checkpoint(),before)

    def test_missing_asset_preserves_state_and_bounds_errors(self):
        self.save(period="hour");before=self.policy.checkpoint();(self.assets/"52.ico").unlink()
        self.now+=dt.timedelta(hours=1);self.assertFalse(self.policy.tick())
        self.assertFalse(self.policy.tick());self.assertEqual(len(self.logs),1)
        self.assertEqual(self.policy.checkpoint(),before)

    def test_failed_write_rolls_back_five_named_values(self):
        self.save();before=self.policy.checkpoint();self.fail_once="IconPeriod"
        with self.assertRaises(RuntimeError):self.save(period="hour")
        self.assertEqual(self.policy.checkpoint(),before)
        self.assertEqual(self.values["AutoStartEnabled"],(0,winreg.REG_DWORD))
        self.assertEqual(self.values["UnrelatedValue"],("keep",winreg.REG_SZ))

    def test_cancel_uncommitted_plan(self):
        before=self.policy.checkpoint();self.policy.prepare("random",50,"hour")
        self.assertEqual(self.policy.checkpoint(),before)

    def test_snapshot_restores_after_outer_settings_failure(self):
        self.save();before=self.policy.checkpoint();self.save("fixed",52,"5min")
        self.policy.restore(before);self.assertEqual(self.policy.checkpoint(),before)

    def test_invalid_saved_type_does_not_overwrite_preferences(self):
        self.values["IconMode"]=(1,winreg.REG_DWORD);before=dict(self.values)
        with self.assertRaises(ValueError):self.make().initialize()
        self.assertEqual(self.values,before)

    def test_field_enablement(self):
        self.assertEqual(self.policy.field_enabled("fixed"),(True,False))
        self.assertEqual(self.policy.field_enabled("random"),(False,True))

if __name__=="__main__":unittest.main()
