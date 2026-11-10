import subprocess,json,urllib.request,urllib.error,os
ADB=os.environ.get('ADB', 'adb')
SERIAL=os.environ['ANDROID_SERIAL']
class Client:
 def __init__(self):
  raw=subprocess.check_output([ADB,'-s',SERIAL,'shell','cat',os.environ.get('QA50_CONFIG', '/sdcard/Android/data/io.woowtech.agent/files/mcp-usb.json')])
  v=json.loads(raw);self.headers=v.get('headers') or {'Authorization':'Bearer '+v['token']}
 def req(self,path='',body=None):
  headers=dict(self.headers,Accept='application/json');data=None
  if body is not None:headers['Content-Type']='application/json';data=json.dumps(body,ensure_ascii=False).encode()
  req=urllib.request.Request(os.environ.get('QA50_BASE_URL', 'http://127.0.0.1:18765/api/v1')+path,data=data,headers=headers)
  try:
   with urllib.request.urlopen(req,timeout=25) as r:return r.status,json.load(r)
  except urllib.error.HTTPError as e:return e.code,json.load(e)
