import json,tempfile,subprocess,unittest,uuid,hashlib,os
from pathlib import Path
EXE=Path(os.environ.get('TITLE_RULES_EXE',str(Path(__file__).resolve().parents[1]/'ChatGPT-TitleSync.Rules.exe')))
def row(pattern,replacement,mode='regex',enabled=True):return dict(enabled=enabled,mode=mode,pattern=pattern,replacement=replacement)
@unittest.skipUnless(os.name=='nt','Windows Unicode companion')
class CliTests(unittest.TestCase):
 def invoke(self,rules,raw,enabled=True,missing=False,invalid=None,caption=False,extra=None,directory=False):
  with tempfile.TemporaryDirectory() as td:
   d=Path(td);cfg=d/'rules.json';source=d/'in.bin';out=d/'out.bin';status=d/'status.txt'
   config=dict(schema_version=1,enabled=enabled,revision=str(uuid.uuid4()),rules=rules);config.update(extra or {})
   if directory:cfg.mkdir()
   elif not missing:cfg.write_text(invalid if invalid is not None else json.dumps(config),encoding='utf-8')
   source.write_bytes(raw.encode('utf-16le'));proc=subprocess.run([str(EXE),'--format']+(['--caption'] if caption else [])+['--rules',str(cfg),'--input',str(source),'--output',str(out),'--status',str(status)],capture_output=True,timeout=3,creationflags=subprocess.CREATE_NO_WINDOW)
   self.assertEqual(proc.stdout,b'');self.assertEqual(proc.stderr,b'');result=(proc.returncode,out.read_bytes().decode('utf-16le'),status.read_text(encoding='ascii'));self.assertEqual(cfg.exists(),not missing or directory);return result
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
@unittest.skipUnless(os.name=='nt','Windows Unicode caption companion')
class CaptionCliTests(unittest.TestCase):
 invoke=CliTests.invoke
 def test_caption_missing_default(self):self.assertEqual(self.invoke([],'Example A',missing=True,caption=True),(0,'Example A — ChatGPT','ok'))
 def test_caption_legacy_config_default(self):self.assertEqual(self.invoke([],'Example A',caption=True),(0,'Example A — ChatGPT','ok'))
 def test_caption_false_empty(self):self.assertEqual(self.invoke([],'Example A',caption=True,extra={'append_chatgpt_suffix':False}),(0,'Example A','ok'))
 def test_caption_false_rules(self):self.assertEqual(self.invoke([row('A','B','literal')],'A',caption=True,extra={'append_chatgpt_suffix':False}),(0,'B','ok'))
 def test_caption_suffix_independent_of_enabled(self):self.assertEqual(self.invoke([row('A','B','literal')],'A',enabled=False,caption=True,extra={'append_chatgpt_suffix':False}),(0,'A','ok'))
 def test_caption_true_explicit(self):self.assertEqual(self.invoke([],'A',enabled=False,caption=True,extra={'append_chatgpt_suffix':True}),(0,'A — ChatGPT','ok'))
 def test_caption_bad_type(self):
  for value in ('false',0,None,[]):
   with self.subTest(value=value):self.assertEqual(self.invoke([],'A',caption=True,extra={'append_chatgpt_suffix':value}),(2,'A — ChatGPT','fallback:InvalidConfig'))
 def test_caption_bad_regex_false_fallback(self):self.assertEqual(self.invoke([row('(','x')],'A',caption=True,extra={'append_chatgpt_suffix':False}),(2,'A','fallback:InvalidPattern'))
 def test_caption_bad_regex_default_fallback(self):self.assertEqual(self.invoke([row('(','x')],'A',caption=True),(2,'A — ChatGPT','fallback:InvalidPattern'))
 def test_caption_pipeline_fallback_false(self):self.assertEqual(self.invoke([row('A','B','literal'),row('B','')],'A',caption=True,extra={'append_chatgpt_suffix':False}),(2,'A','fallback:InvalidOutput'))
 def test_caption_512_body_522_complete(self):self.assertEqual(self.invoke([],'A'*512,caption=True),(0,'A'*512+' — ChatGPT','ok'))
 def test_caption_512_body_false(self):self.assertEqual(self.invoke([],'A'*512,caption=True,extra={'append_chatgpt_suffix':False}),(0,'A'*512,'ok'))
 def test_caption_invalid_source_unchanged(self):
  for raw in ('A'*513,'A\nB'):
   with self.subTest(rawlen=len(raw)):self.assertEqual(self.invoke([],raw,caption=True),(2,raw,'fallback:InvalidSource'))
 def test_caption_bad_json_default(self):self.assertEqual(self.invoke([],'A',invalid='{',caption=True),(2,'A — ChatGPT','fallback:InvalidConfig'))
 def test_caption_rules_io_default(self):self.assertEqual(self.invoke([],'A',directory=True,caption=True),(3,'A — ChatGPT','fallback:RulesReadFailed'))
if __name__=='__main__':unittest.main()
