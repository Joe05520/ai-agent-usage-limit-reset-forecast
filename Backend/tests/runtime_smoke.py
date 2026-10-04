"""Exercise real local Worker + D1; never send fixtures to a deployed backend."""
import json
import time
import urllib.request
import urllib.error
import uuid
BASE='http://127.0.0.1:8787'

def call(path,body=None,method=None,headers=None):
    req=urllib.request.Request(BASE+path,data=json.dumps(body).encode() if body is not None else None,method=method,headers={'Content-Type':'application/json',**(headers or {})})
    try:
        with urllib.request.urlopen(req,timeout=10) as response:return response.status,json.load(response),response.headers
    except urllib.error.HTTPError as error:return error.code,json.load(error),error.headers

assert call('/health')[0]==200
assert call('/admin/stats')[0]==401
clients=[str(uuid.uuid4()) for _ in range(10)]
day=time.strftime('%Y-%m-%d',time.gmtime())
for client in clients:
    report=dict(schema=1,consent=True,client=client,day=day,kind='app',platform='macOS',version='1.5.0',agent='codex',quotaBand='20-49',activityBand='1-5',reminders=5)
    assert call('/v1/report',report)[0]==202
    assert call('/v1/report',report)[0]==202
assert call('/v1/report',dict(report,country='TW'))[0]==400
assert call('/v1/report',dict(report,token='secret'))[0]==400
status,data,_=call('/public/stats');assert status==200;assert data['minimumContributors']==10;assert data['usage']['agents'][0]['count']==10
status,data,headers=call('/admin/login',{'password':'local-testing-admin-0000000000000000000000000000000'},headers={'Origin':BASE});assert status==200
cookie=headers['Set-Cookie'].split(';')[0]
assert call('/admin/stats',headers={'Cookie':cookie})[0]==200
for client in clients:assert call('/v1/report',{'client':client},method='DELETE')[0]==200
assert call('/admin/stats',headers={'Cookie':cookie})[1]['usage']['agents']==[]
print('Worker runtime + D1: ingestion, deduplication, rejection, suppression, authenticated admin and deletion passed. Local fixtures deleted.')
