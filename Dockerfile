# syntax=docker/dockerfile:1
FROM python:3.12-alpine
WORKDIR /app
RUN adduser -D webuser && mkdir -p /data && chown webuser:webuser /data
COPY darts_schedule_web.html /app/index.html
COPY <<'PY' /app/server.py
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json, os

DATA='/data/state.json'
def load():
    if not os.path.exists(DATA): return {'size':4,'names':[f'Player {i}' for i in range(1,5)],'results':{},'date':'','history':[]}
    with open(DATA,encoding='utf-8') as f: return json.load(f)
def save(state):
    size=int(state.get('size',4))
    if size not in range(4,9): raise ValueError('Group size must be 4–8.')
    names=state.get('names',[])
    if not isinstance(names,list) or len(names)!=size or any(not isinstance(x,str) or len(x)>36 for x in names): raise ValueError('Please provide a valid name for each player (maximum 36 characters).')
    results=state.get('results',{})
    if not isinstance(results,dict): raise ValueError('Invalid match results.')
    date=state.get('date','')
    if not isinstance(date,str) or len(date)>20: raise ValueError('Invalid date.')
    history=state.get('history',[])
    if not isinstance(history,list) or len(history)>1000: raise ValueError('Invalid history.')
    for h in history:
        if not isinstance(h,dict): raise ValueError('Invalid history entry.')
        if not isinstance(h.get('date',''),str) or len(h.get('date',''))>20: raise ValueError('Invalid history date.')
        if not isinstance(h.get('champion',''),str) or len(h.get('champion',''))>36: raise ValueError('Invalid history champion.')
        if not isinstance(h.get('runnerUp',''),str) or len(h.get('runnerUp',''))>36: raise ValueError('Invalid history runner-up.')
        if not isinstance(h.get('size',4),int) or h.get('size',4) not in range(4,9): raise ValueError('Invalid history size.')
    clean={'size':size,'names':names,'results':results,'date':date,'history':history}
    tmp=DATA+'.tmp'
    with open(tmp,'w',encoding='utf-8') as f: json.dump(clean,f,ensure_ascii=False)
    os.replace(tmp,DATA)
    return clean
class Handler(BaseHTTPRequestHandler):
    def reply(self,status,obj,ctype='application/json; charset=utf-8'):
        body=obj if isinstance(obj,bytes) else json.dumps(obj,ensure_ascii=False).encode()
        self.send_response(status);self.send_header('Content-Type',ctype);self.send_header('Content-Length',str(len(body)));self.send_header('X-Content-Type-Options','nosniff');self.end_headers();self.wfile.write(body)
    def do_GET(self):
        if self.path=='/' or self.path=='/index.html':
            with open('/app/index.html','rb') as f: return self.reply(200,f.read(),'text/html; charset=utf-8')
        if self.path=='/api/state': return self.reply(200,load())
        return self.reply(404,{'error':'Not found'})
    def do_PUT(self):
        if self.path!='/api/state': return self.reply(404,{'error':'Not found'})
        try:
            state=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))))
            return self.reply(200,save(state))
        except (ValueError,TypeError,KeyError,json.JSONDecodeError) as e: return self.reply(400,{'error':str(e) or 'Invalid state'})
    def log_message(self,*args): pass
ThreadingHTTPServer(('0.0.0.0',8080),Handler).serve_forever()
PY
EXPOSE 8080
VOLUME ["/data"]
USER webuser
CMD ["python", "/app/server.py"]

