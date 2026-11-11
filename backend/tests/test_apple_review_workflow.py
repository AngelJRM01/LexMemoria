"""GITHUB_ENV exports apply to later steps, not the current simulator boot."""
from pathlib import Path
import json,os,subprocess
import yaml


def test_simulator_boot_gets_current_step_id_and_exports_future_steps(tmp_path):
    root=Path(__file__).resolve().parents[2]
    workflow=yaml.load((root/'.github/workflows/apple-review-assets.yml').read_text(),Loader=yaml.BaseLoader)
    step=next(s for s in workflow['jobs']['screenshots']['steps'] if s.get('name')=='Select and boot iPhone simulator')
    uuid='00000000-1111-2222-3333-444444444444'
    fixture=tmp_path/'devices.json';fixture.write_text(json.dumps({'devices':{'com.apple.CoreSimulator.SimRuntime.iOS-26-1':[{'name':'iPhone Pro Max','udid':uuid,'isAvailable':True,'state':'Shutdown'}]}}))
    tools=tmp_path/'tools';tools.mkdir();xcrun=tools/'xcrun'
    xcrun.write_text('#!/bin/bash\nif [ "$2" = "list" ]; then cat "$FIXTURE"; elif [ "$2" = "bootstatus" ]; then test "$3" = "$EXPECTED_UUID"; else exit 3; fi\n');xcrun.chmod(0o700)
    environment={**os.environ,'PATH':str(tools)+os.pathsep+os.environ['PATH'],'FIXTURE':str(fixture),'EXPECTED_UUID':uuid,'GITHUB_ENV':str(tmp_path/'github-env')}
    environment.pop('IOS_SIMULATOR_ID',None)
    subprocess.run(['bash','-e','-c',step['run']],cwd=tmp_path,env=environment,check=True,capture_output=True,text=True)
    assert (tmp_path/'github-env').read_text()=='IOS_SIMULATOR_ID='+uuid+'\n'
    assert json.loads((tmp_path/'apple-review-assets/simulator.json').read_text())['udid']==uuid
