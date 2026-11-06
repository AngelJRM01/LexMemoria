import json
from pathlib import Path
import runpy
import pytest

helpers=runpy.run_path(str(Path(__file__).resolve().parents[2]/'scripts/firebase_config.py'))
validate=helpers['google_configuration'];api_url=helpers['public_api_url']

@pytest.fixture
def config(tmp_path):
    path=tmp_path/'google-services.json'
    value={'project_info':{'project_id':'lexmemoria-aa86a'},'client':[{
        'client_info':{'mobilesdk_app_id':'1:123:android:example','android_client_info':{'package_name':'es.lexmemoria.app.preview'}},
        'api_key':[{'current_key':'public-example-client-key-not-a-secret'}],
        'oauth_client':[{'client_type':3,'client_id':'123.apps.googleusercontent.com'},
            {'client_type':1,'client_id':'android.apps.googleusercontent.com','android_info':{
                'package_name':'es.lexmemoria.app.preview','certificate_hash':'a'*40}}]}]}
    path.write_text(json.dumps(value));return path,value

def test_public_android_config_matches_project_package_and_certificate(config):
    path,_=config;result=validate(path,'es.lexmemoria.app.preview')
    assert result['projectId']=='lexmemoria-aa86a' and result['sha1s']==['a'*40]
    assert 'api_key' not in result

@pytest.mark.parametrize('change',['project','package','web','certificate','admin'])
def test_incomplete_or_wrong_configuration_cannot_enable_google(config,change):
    path,value=config
    if change=='project':value['project_info']['project_id']='other-project'
    if change=='package':value['client'][0]['client_info']['android_client_info']['package_name']='es.lexmemoria.app'
    if change=='web':value['client'][0]['oauth_client']=[o for o in value['client'][0]['oauth_client'] if o['client_type']!=3]
    if change=='certificate':value['client'][0]['oauth_client']=[o for o in value['client'][0]['oauth_client'] if o['client_type']!=1]
    if change=='admin':value={'type':'service_account','private_key':'must-never-be-used'}
    path.write_text(json.dumps(value))
    with pytest.raises(ValueError) as error:validate(path,'es.lexmemoria.app.preview')
    assert 'must-never-be-used' not in str(error.value)

@pytest.mark.parametrize('value',['http://api.test','https://user:password@api.test','https://api.test/health','https://api.test?key=x'])
def test_api_configuration_rejects_credentials_cleartext_and_health_path(value):
    with pytest.raises(ValueError):api_url(value)

def test_public_https_api_url_is_normalized():assert api_url('https://api.test/')=='https://api.test'
