# syntax=docker/dockerfile:1
FROM python:3.12-alpine
WORKDIR /app
RUN adduser -D webuser && mkdir -p /data && chown webuser:webuser /data
COPY darts_schedule_web.html /app/index.html
COPY logo.webp /app/logo.webp
COPY manifest.json /app/manifest.json
COPY icon-180.png /app/icon-180.png
COPY icon-192.png /app/icon-192.png
COPY icon-512.png /app/icon-512.png
COPY <<'PY' /app/server.py
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json, os, hmac, hashlib

DATA='/data/state.json'
EDITOR_PASSWORD=os.environ.get('EDITOR_PASSWORD','').strip()
def make_token():
    return hmac.new(EDITOR_PASSWORD.encode(),b'editor-session',hashlib.sha256).hexdigest()
def get_cookie(handler,name):
    for part in handler.headers.get('Cookie','').split(';'):
        part=part.strip()
        if part.startswith(name+'='): return part[len(name)+1:]
    return None
def is_authed(handler):
    if not EDITOR_PASSWORD: return True
    token=get_cookie(handler,'session')
    return bool(token) and hmac.compare_digest(token,make_token())
def load():
    if not os.path.exists(DATA): return {'size':4,'names':[f'Speler {i}' for i in range(1,5)],'results':{},'date':'','history':[]}
    with open(DATA,encoding='utf-8') as f: return json.load(f)
def save(state):
    size=int(state.get('size',4))
    if size not in range(4,9): raise ValueError('Poulegrootte moet 4–8 zijn.')
    names=state.get('names',[])
    if not isinstance(names,list) or len(names)!=size or any(not isinstance(x,str) or len(x)>36 for x in names): raise ValueError('Geef een geldige naam op voor elke speler (maximaal 36 tekens).')
    results=state.get('results',{})
    if not isinstance(results,dict): raise ValueError('Ongeldige wedstrijduitslagen.')
    date=state.get('date','')
    if not isinstance(date,str) or len(date)>20: raise ValueError('Ongeldige datum.')
    history=state.get('history',[])
    if not isinstance(history,list) or len(history)>1000: raise ValueError('Ongeldige geschiedenis.')
    for h in history:
        if not isinstance(h,dict): raise ValueError('Ongeldig geschiedenisitem.')
        if not isinstance(h.get('date',''),str) or len(h.get('date',''))>20: raise ValueError('Ongeldige datum in geschiedenis.')
        if not isinstance(h.get('champion',''),str) or len(h.get('champion',''))>36: raise ValueError('Ongeldige kampioen in geschiedenis.')
        if not isinstance(h.get('runnerUp',''),str) or len(h.get('runnerUp',''))>36: raise ValueError('Ongeldige tweede plaats in geschiedenis.')
        if not isinstance(h.get('size',4),int) or h.get('size',4) not in range(4,9): raise ValueError('Ongeldige poulegrootte in geschiedenis.')
    clean={'size':size,'names':names,'results':results,'date':date,'history':history}
    tmp=DATA+'.tmp'
    with open(tmp,'w',encoding='utf-8') as f: json.dump(clean,f,ensure_ascii=False)
    os.replace(tmp,DATA)
    return clean
class Handler(BaseHTTPRequestHandler):
    def reply(self,status,obj,ctype='application/json; charset=utf-8',extra_headers=None):
        body=obj if isinstance(obj,bytes) else json.dumps(obj,ensure_ascii=False).encode()
        self.send_response(status);self.send_header('Content-Type',ctype);self.send_header('Content-Length',str(len(body)));self.send_header('X-Content-Type-Options','nosniff')
        for k,v in (extra_headers or {}).items(): self.send_header(k,v)
        self.end_headers();self.wfile.write(body)
    def do_GET(self):
        if self.path=='/' or self.path=='/index.html':
            with open('/app/index.html','rb') as f: return self.reply(200,f.read(),'text/html; charset=utf-8')
        if self.path=='/logo.webp':
            with open('/app/logo.webp','rb') as f: return self.reply(200,f.read(),'image/webp')
        if self.path=='/manifest.json':
            with open('/app/manifest.json','rb') as f: return self.reply(200,f.read(),'application/manifest+json')
        if self.path in ('/icon-180.png','/icon-192.png','/icon-512.png'):
            with open(f'/app{self.path}','rb') as f: return self.reply(200,f.read(),'image/png')
        if self.path=='/api/state': return self.reply(200,load())
        if self.path=='/api/auth': return self.reply(200,{'authed':is_authed(self),'loginRequired':bool(EDITOR_PASSWORD)})
        return self.reply(404,{'error':'Niet gevonden'})
    def do_POST(self):
        if self.path=='/api/login':
            try: body=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))))
            except json.JSONDecodeError: return self.reply(400,{'error':'Ongeldig verzoek'})
            password=str(body.get('password',''))
            if not EDITOR_PASSWORD or hmac.compare_digest(password,EDITOR_PASSWORD):
                return self.reply(200,{'authed':True},extra_headers={'Set-Cookie':f'session={make_token()}; Path=/; HttpOnly; SameSite=Strict; Max-Age=15552000'})
            return self.reply(401,{'error':'Onjuist wachtwoord'})
        if self.path=='/api/logout':
            return self.reply(200,{'authed':False},extra_headers={'Set-Cookie':'session=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0'})
        return self.reply(404,{'error':'Niet gevonden'})
    def do_PUT(self):
        if self.path!='/api/state': return self.reply(404,{'error':'Niet gevonden'})
        if not is_authed(self): return self.reply(401,{'error':'Log in om te bewerken.'})
        try:
            state=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))))
            return self.reply(200,save(state))
        except (ValueError,TypeError,KeyError,json.JSONDecodeError) as e: return self.reply(400,{'error':str(e) or 'Ongeldige status'})
    def log_message(self,*args): pass
ThreadingHTTPServer(('0.0.0.0',8080),Handler).serve_forever()
PY
EXPOSE 8080
VOLUME ["/data"]
USER webuser
CMD ["python", "/app/server.py"]

