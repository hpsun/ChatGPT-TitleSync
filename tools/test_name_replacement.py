"""Controlled name-replacement CLI tests. Never starts an editor or AX monitor."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import time

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", required=True, type=Path)
    parser.add_argument("--cases", type=Path, default=Path(__file__).parent/"tests"/"name-replacement-cases.json")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    worker = args.worker.resolve()
    cases = json.loads(args.cases.read_text(encoding="utf-8"))["cases"]
    results = []
    with tempfile.TemporaryDirectory(prefix="titlesync-rules-fixture-") as temporary:
        root = Path(temporary)
        for index, case in enumerate(cases):
            directory = root / str(index)
            directory.mkdir()
            rules, source = directory/"rules.json", directory/"input.utf16"
            output, status = directory/"output.utf16", directory/"status.txt"
            if not case.get("missing_rules_file"):
                rules.write_text(json.dumps(case["config"], ensure_ascii=False), encoding="utf-8")
            source.write_bytes(case["raw"].encode("utf-16-le"))
            start = time.monotonic()
            try:
                # Explicit private paths bypass all personal default preferences.
                child = subprocess.run([str(worker),"--format","--rules",str(rules),
                    "--input",str(source),"--output",str(output),"--status",str(status)],
                    capture_output=True, timeout=3, check=False)
                actual = output.read_bytes().decode("utf-16-le")
                state = status.read_text(encoding="ascii").strip()
                passed = child.returncode == case["exit_code"] and actual == case["expected"]
                passed = passed and ((state == "ok") if case["exit_code"] == 0 else state.startswith("fallback:"))
                result = {"id":case["id"],"passed":passed,"exit_code":child.returncode,
                    "status":state,"elapsed_ms":round((time.monotonic()-start)*1000,2)}
                if not passed:
                    result.update(expected_exit=case["exit_code"],actual=actual,expected=case["expected"],
                                  stderr=child.stderr.decode("utf-8",errors="replace")[:2048])
                # Identity reads must not materialize a rule preference.
                if case.get("missing_rules_file") and rules.exists():
                    result.update(passed=False,error="Missing rule preference was created by --format")
            except Exception as error:
                result = {"id":case["id"],"passed":False,"error":type(error).__name__+": "+str(error)}
            results.append(result)
    report = {"scope":"Private CLI format fixtures; no UI/AX/autostart or personal preferences",
              "worker":str(worker),"passed":all(item["passed"] for item in results),
              "checks":len(results),"results":results}
    if args.report:
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps({"passed":report["passed"],"checks":len(results),
                      "failures":[item for item in results if not item["passed"]]},ensure_ascii=True))
    return 0 if report["passed"] else 1

if __name__ == "__main__":
    raise SystemExit(main())
