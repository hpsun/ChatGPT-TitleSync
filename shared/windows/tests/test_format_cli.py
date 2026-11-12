import json,tempfile,subprocess,unittest,uuid,hashlib,os
from pathlib import Path
EXE=Path(os.environ.get('TITLE_RULES_EXE',str(Path(__file__).resolve().parents[1]/'ChatGPT-TitleSync.Rules.exe')))
def row(pattern,replacement,mode='regex',enabled=True):return dict(enabled=enabled,mode=mode,pattern=pattern,replacement=replacement)
@unittest.skipUnless(os.name=='nt','Windows Unicode companion')
class CliTests(unittest.TestCase):
 def invoke(self,rules,raw,enabled=True,missing=False,invalid=None):
  with tempfile.TemporaryDirectory() as td:
   d=Path(td);cfg=d/'rules.json';source=d/'in.bin';out=d/'out.bin';status=d/'status.txt'
   if not missing:cfg.write_text(invalid if invalid is not None else json.dumps(dict(schema_version=1,enabled=enabled,revision=str(uuid.uuid4()),rules=rules)),encoding='utf-8')
   source.write_bytes(raw.encode('utf-16le'));proc=subprocess.run([str(EXE),'--format','--rules',str(cfg),'--input',str(source),'--output',str(out),'--status',str(status)],capture_output=True,timeout=3,creationflags=subprocess.CREATE_NO_WINDOW)
   self.assertEqual(proc.stdout,b'');self.assertEqual(proc.stderr,b'');result=(proc.returncode,out.read_bytes().decode('utf-16le'),status.read_text(encoding='ascii'));self.assertEqual(cfg.exists(),not missing);return result
 def test_identity_missing(self):self.assertEqual(self.invoke([],'示例😀',missing=True),(0,'示例😀','ok'))
 def test_identity_empty(self):self.assertEqual(self.invoke([],'Example A'),(0,'Example A','ok'))
 def test_master_off(self):self.assertEqual(self.invoke([row('A','B','literal')],'A',enabled=False),(0,'A','ok'))
 def test_literal_ordinal_global(self):self.assertEqual(self.invoke([row('A','$1','literal')],'AaA'),(0,'$1a$1','ok'))
 def test_order(self):self.assertEqual(self.invoke([row('A','B','literal'),row('B','C','literal')],'A'),(0,'C','ok'))
 def test_numeric_groups_unicode(self):self.assertEqual(self.invoke([row(r'(资料)(😀)',r'${2}$$$1:$0')],'资料😀'),(0,'😀$资料:资料😀','ok'))
 def test_unmatched_optional(self):self.assertEqual(self.invoke([row(r'(A)(B)?',r'$1-$2')],'A'),(0,'A-','ok'))
 def test_no_match(self):self.assertEqual(self.invoke([row('Z','Q')],'A'),(0,'A','ok'))
 def test_disabled_invalid_pattern(self):self.assertEqual(self.invoke([row('(','x',enabled=False)],'A'),(0,'A','ok'))
 def test_invalid_pattern(self):self.assertEqual(self.invoke([row('(','x')],'A'),(2,'A','fallback:InvalidPattern'))
 def test_surrogate_result_falls_back(self):self.assertEqual(self.invoke([row(r'^.','')],'😀'),(2,'😀','fallback:InvalidOutput'))
 def test_unknown_group(self):self.assertEqual(self.invoke([row('(A)','$2')],'A'),(2,'A','fallback:UnknownGroup'))
 def test_invalid_templates(self):
  for value in ['$x','$','${x}','${1','$123','${123}']:
   with self.subTest(value=value):self.assertEqual(self.invoke([row('(A)',value)],'A'),(2,'A','fallback:InvalidReplacement'))
 def test_entire_pipeline_fallback(self):self.assertEqual(self.invoke([row('A','B','literal'),row('B','')],'A'),(2,'A','fallback:InvalidOutput'))
 def test_generic_output(self):self.assertEqual(self.invoke([row('A','ChatGPT','literal')],'A'),(2,'A','fallback:InvalidOutput'))
 def test_control_output(self):self.assertEqual(self.invoke([row('A','A\n','literal')],'A'),(2,'A','fallback:InvalidOutput'))
 def test_overlong_output(self):self.assertEqual(self.invoke([row('A','X'*512,'literal')],'AA'),(2,'AA','fallback:InvalidOutput'))
 def test_empty_enabled_pattern(self):self.assertEqual(self.invoke([row('','X','literal')],'A'),(2,'A','fallback:EmptyPattern'))
 def test_bad_json(self):self.assertEqual(self.invoke([],'A',invalid='{'),(2,'A','fallback:InvalidConfig'))
 def test_fractional_schema_rejected(self):self.assertEqual(self.invoke([],'A',invalid=json.dumps(dict(schema_version=1.2,enabled=True,revision=str(uuid.uuid4()),rules=[]))),(2,'A','fallback:InvalidConfig'))
 def test_33_rules_rejected(self):self.assertEqual(self.invoke([row('A','B','literal')]*33,'A'),(2,'A','fallback:InvalidConfig'))
 def test_match_timeout(self):
  code,name,status=self.invoke([row(r'^(a+)+$','x')],'a'*240+'!');self.assertEqual(code,2);self.assertEqual(name,'a'*240+'!');self.assertIn(status,('fallback:MatchTimeout','fallback:AggregateTimeout'))
if __name__=='__main__':unittest.main()
