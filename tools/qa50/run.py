import json,time,uuid,sys,datetime,os
from pathlib import Path
from client import Client,ADB,SERIAL
ROOT=Path(os.environ['QA50_OUTPUT']).expanduser()
ROOT.mkdir(parents=True,exist_ok=True,mode=0o700)
TERMINAL={'done','failed','cancelled'}
def stamp():return datetime.datetime.now().isoformat()
def save(p,v):
 tmp=p.with_suffix('.tmp');tmp.write_text(json.dumps(v,ensure_ascii=False,indent=2));tmp.replace(p)
def run(case):
 p=ROOT/(case['id']+'.json')
 if p.exists():
  old=json.loads(p.read_text())
  if old.get('finished'):print(case['id'],'SKIP existing',flush=True);return
  raise RuntimeError('Incomplete existing case; inspect before resuming: '+case['id'])
 c=Client();rid=str(uuid.uuid4());r={'case':case,'request_id':rid,'started':stamp(),'events':[],'turns':[]};save(p,r)
 def event(kind,data):r['events'].append(dict(time=stamp(),kind=kind,data=data));save(p,r)
 def req(path='',body=None):
  code,v=c.req(path,body)
  if code>=400:raise RuntimeError(str(code)+' '+json.dumps(v,ensure_ascii=False))
  return v
 goal=case['prompt'];conv=None
 for turn in range(1+len(case.get('followups',[]))):
  body={'goal':goal,'request_id':rid if turn==0 else str(uuid.uuid4())}
  if conv:body['conversation']=conv
  t=req('/tasks',body);event('created',t);tid=t['task_id'];conv=t['conversation'];beg=time.monotonic();last=None;answers=iter(case.get('answers',[]));answered=0;controlled=False
  if turn==0 and case.get('control')=='duplicate':
   duplicate=req('/tasks',body);event('duplicate',{'same_task':duplicate['task_id']==tid,'same_conversation':duplicate['conversation']==conv,'task_id':duplicate['task_id']});controlled=True
  print(case['id'],'START',tid,case['title'],flush=True)
  while True:
   t=req('/tasks/'+tid);state=t.get('status');key=(state,t.get('step'),t.get('progress'),t.get('question'))
   if key!=last:event('status',t);last=key
   elapsed=time.monotonic()-beg
   if state in TERMINAL:break
   if state=='waiting_for_answer':
    answer=next(answers,None)
    if answer is None:
     event('unexpected_question',t);req('/tasks/'+tid+'/cancel',{});event('cancel_reason','unexpected_question')
    else:
     event('answer_sent',answer);event('answer_receipt',req('/tasks/'+tid+'/answer',{'text':answer}));answered+=1
   elif state=='waiting_on_phone':
    event('phone_gate',t);req('/tasks/'+tid+'/cancel',{});event('cancel_reason','phone_confirmation_required')
   if turn==0 and not controlled and elapsed>=case.get('control_after',5) and state=='running':
    control=case.get('control')
    if control=='cancel':event('cancel_receipt',req('/tasks/'+tid+'/cancel',{}));controlled=True
    if control=='steer':
     code,receipt=c.req('/tasks/'+tid+'/steer',{'text':case['steer']});event('steer_receipt',{'http':code,**receipt});controlled=True
   if elapsed>180:
    event('cancel_reason','180s_test_deadline');req('/tasks/'+tid+'/cancel',{})
    for _ in range(10):
     time.sleep(1);t=req('/tasks/'+tid)
     if t.get('status') in TERMINAL:break
    if t.get('status') not in TERMINAL:raise RuntimeError('Task did not stop '+tid)
    break
   time.sleep(2)
  r['turns'].append({'task_id':tid,'conversation':conv,'elapsed_s':round(time.monotonic()-beg,2),'result':t});save(p,r)
  print(case['id'],'END',t.get('status'),round(time.monotonic()-beg,1),str(t.get('answer',t.get('reason','')))[:160].replace('\n',' '),flush=True)
  if t.get('status')!='done':break
  if turn<len(case.get('followups',[])):goal=case['followups'][turn]
 r['finished']=stamp();save(p,r)
if __name__=='__main__':
 cases=json.loads((Path(__file__).parent/'cases.json').read_text());lo=int(sys.argv[1]) if len(sys.argv)>1 else 1;hi=int(sys.argv[2]) if len(sys.argv)>2 else 50
 for case in cases[lo-1:hi]:
  try:run(case)
  except Exception as e:
   print('RUNNER_STOP',case['id'],type(e).__name__,str(e),flush=True);sys.exit(1)
