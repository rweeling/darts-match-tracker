# syntax=docker/dockerfile:1
FROM python:3.12-alpine AS gitinfo
RUN apk add --no-cache git
WORKDIR /src
COPY . .
RUN VERSION=$(cat VERSION 2>/dev/null || echo '0.0.0') && \
    COMMIT=$(git log -1 --format='%h' 2>/dev/null || echo unknown) && \
    DATE=$(git log -1 --format='%ad' --date=format:'%Y-%m-%d' 2>/dev/null || echo unknown) && \
    printf '{"version":"%s","commit":"%s","date":"%s"}' "$VERSION" "$COMMIT" "$DATE" > /version.json

FROM python:3.12-alpine
WORKDIR /app
RUN adduser -D webuser && mkdir -p /data && chown webuser:webuser /data
COPY darts_schedule_web.html /app/index.html
COPY darts_display.html /app/display.html
COPY manifest.json /app/manifest.json
COPY favicon.svg /app/favicon.svg
COPY --from=gitinfo /version.json /app/version.json
COPY <<'PY' /app/server.py
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json, os, shutil, hmac, hashlib, re

DATA='/data/state.json'
EDITOR_PASSWORD=os.environ.get('EDITOR_PASSWORD','').strip()
MATCH_ID_RE=re.compile(r'^\d+-\d+$')
def seed_order(n):
    if n==1: return [1]
    h=seed_order(n//2)
    out=[]
    for s in h:
        out.append(s); out.append(n+1-s)
    return out
def next_pow2(n):
    p=1
    while p<n: p*=2
    return p
def round_name_for_size(sz):
    return 'final' if sz==2 else 'sf' if sz==4 else 'qf' if sz==8 else f'r{sz}'
def bracket_round_names(pc):
    bs=next_pow2(2*pc)
    names=[]
    sz=bs
    while sz>=2:
        names.append(round_name_for_size(sz)); sz//=2
    return names
def elim_round_names(n):
    bs=next_pow2(n)
    names=[]
    sz=bs
    while sz>=2:
        names.append(round_name_for_size(sz)); sz//=2
    return names
def elim_result_keys_for(n):
    names=elim_round_names(n)
    non_final=names[:-1]
    keys=set()
    if non_final:
        bs=next_pow2(n)
        order=seed_order(bs)
        r0name=non_final[0]
        for i in range(bs//2):
            if order[2*i]<=n and order[2*i+1]<=n: keys.add(f'{r0name}-{i}')
        num_prev=bs//2
        for r in range(1,len(non_final)):
            num_cur=num_prev//2
            for j in range(num_cur): keys.add(f'{non_final[r]}-{j}')
            num_prev=num_cur
    keys.add('final')
    return keys
def cross_keys_for(pool_count):
    if pool_count==1: return set()
    if pool_count==2: return {'sf-0','sf-1','final'}
    if pool_count==4: return {'qf-0','qf-1','qf-2','qf-3','sf-0','sf-1','final'}
    bs=next_pow2(2*pool_count)
    n=2*pool_count
    order=seed_order(bs)
    names=bracket_round_names(pool_count)
    non_final=names[:-1]
    keys=set()
    r0name=non_final[0]
    for i in range(bs//2):
        if order[2*i]<=n and order[2*i+1]<=n: keys.add(f'{r0name}-{i}')
    num_prev=bs//2
    for r in range(1,len(non_final)):
        num_cur=num_prev//2
        for j in range(num_cur): keys.add(f'{non_final[r]}-{j}')
        num_prev=num_cur
    keys.add('final')
    return keys
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
def default_pool(size):
    return {'names':[f'Player {i}' for i in range(1,size+1)],'results':{},'bullOrder':{}}
def default_elim(size):
    return {'names':[f'Player {i}' for i in range(1,size+1)],'order':list(range(size)),'results':{}}
def default_state():
    return {'poolCount':1,'size':4,'pools':[default_pool(4)],'cross':{},'date':'','history':[],'tally180':{},'finishes':[],'format':'pools','elimSize':4,'elim':default_elim(4)}
def migrate(data):
    if not isinstance(data,dict): return default_state()
    if 'pools' in data:
        data.setdefault('tally180',{})
        data.setdefault('finishes',[])
        data.setdefault('format','pools')
        data.setdefault('elimSize',4)
        data.setdefault('elim',default_elim(4))
        return data
    size=data.get('size',4)
    if not isinstance(size,int) or size not in range(4,9): size=4
    return {'poolCount':1,'size':size,'pools':[{'names':data.get('names',[]),'results':data.get('results',{}),'bullOrder':data.get('bullOrder',{})}],'cross':{},'date':data.get('date',''),'history':data.get('history',[]),'tally180':{},'finishes':[],'format':'pools','elimSize':4,'elim':default_elim(4)}
def load():
    if not os.path.exists(DATA): return default_state()
    with open(DATA,encoding='utf-8') as f: return migrate(json.load(f))
def validate_bull_order(bo,size):
    if not isinstance(bo,dict) or len(bo)>20: raise ValueError('Invalid bull-off data.')
    for k,v in bo.items():
        if not isinstance(k,str) or len(k)>40: raise ValueError('Invalid bull-off key.')
        if not isinstance(v,list) or len(v)>size: raise ValueError('Invalid bull-off order.')
        for x in v:
            if x!='' and not (isinstance(x,int) and not isinstance(x,bool) and 0<=x<size): raise ValueError('Invalid bull-off player.')
def validate_pool_results(results,size,allow_bracket):
    if not isinstance(results,dict): raise ValueError('Invalid match results.')
    allowed_keys={'semi-0','semi-1','final'} if allow_bracket else set()
    for k,v in results.items():
        if not isinstance(k,str): raise ValueError('Invalid match result.')
        if not (MATCH_ID_RE.match(k) or k in allowed_keys): raise ValueError('Invalid match result.')
        if MATCH_ID_RE.match(k):
            a,b=(int(x) for x in k.split('-'))
            if not (0<=a<size and 0<=b<size and a<b): raise ValueError('Invalid match result.')
        if not (isinstance(v,int) and not isinstance(v,bool) and 0<=v<size): raise ValueError('Invalid winner.')
def validate_cross(cross,pool_count,size):
    if not isinstance(cross,dict): raise ValueError('Invalid cross-final data.')
    allowed=cross_keys_for(pool_count)
    for k,v in cross.items():
        if k not in allowed: raise ValueError('Invalid cross-final key.')
        if not isinstance(v,str): raise ValueError('Invalid cross-final winner.')
        parts=v.split(':')
        if len(parts)!=2 or not all(p.isdigit() for p in parts): raise ValueError('Invalid cross-final winner.')
        p,i=int(parts[0]),int(parts[1])
        if not (0<=p<pool_count and 0<=i<size): raise ValueError('Invalid cross-final winner.')
def validate_elim(elim,elim_size):
    if not isinstance(elim,dict): raise ValueError('Invalid elimination data.')
    names=elim.get('names',[])
    if not isinstance(names,list) or len(names)!=elim_size or any(not isinstance(x,str) or len(x)>36 for x in names): raise ValueError('Enter a valid name for each player (36 characters max).')
    order=elim.get('order',[])
    if not isinstance(order,list) or sorted(order)!=list(range(elim_size)): raise ValueError('Invalid elimination draw order.')
    results=elim.get('results',{})
    if not isinstance(results,dict) or len(results)>2*elim_size: raise ValueError('Invalid elimination results.')
    allowed=elim_result_keys_for(elim_size)
    for k,v in results.items():
        if k not in allowed: raise ValueError('Invalid elimination match key.')
        if not (isinstance(v,int) and not isinstance(v,bool) and 0<=v<elim_size): raise ValueError('Invalid elimination winner.')
def validate_tally180(tally):
    if not isinstance(tally,dict) or len(tally)>200: raise ValueError('Invalid 180 tally.')
    for k,v in tally.items():
        if not isinstance(k,str) or not k or len(k)>36: raise ValueError('Invalid player name for 180 tally.')
        if not (isinstance(v,int) and not isinstance(v,bool) and 0<=v<=100000): raise ValueError('Invalid 180 count.')
IMPOSSIBLE_FINISHES={159,162,163,165,166,168,169}
def validate_finishes(finishes):
    if not isinstance(finishes,list) or len(finishes)>2000: raise ValueError('Invalid list of high finishes.')
    for e in finishes:
        if not isinstance(e,dict): raise ValueError('Invalid high finish.')
        if not isinstance(e.get('date',''),str) or len(e.get('date',''))>20: raise ValueError('Invalid date for high finish.')
        if not isinstance(e.get('player',''),str) or not e.get('player','') or len(e.get('player',''))>36: raise ValueError('Invalid player name for high finish.')
        score=e.get('score')
        if not (isinstance(score,int) and not isinstance(score,bool) and 50<=score<=170 and score not in IMPOSSIBLE_FINISHES): raise ValueError('Invalid high finish: not a possible 3-dart checkout from 50-170.')
def save(state):
    pool_count=int(state.get('poolCount',1))
    if pool_count not in (1,2,4,6,8,10): raise ValueError('Number of pools must be 1, 2, 4, 6, 8, or 10.')
    size=int(state.get('size',4))
    if size not in range(4,9): raise ValueError('Pool size must be 4-8.')
    pools_in=state.get('pools',[])
    if not isinstance(pools_in,list) or len(pools_in)!=pool_count: raise ValueError('Invalid number of pools.')
    pools=[]
    for pl in pools_in:
        if not isinstance(pl,dict): raise ValueError('Invalid pool.')
        names=pl.get('names',[])
        if not isinstance(names,list) or len(names)!=size or any(not isinstance(x,str) or len(x)>36 for x in names): raise ValueError('Enter a valid name for each player (36 characters max).')
        results=pl.get('results',{})
        validate_pool_results(results,size,pool_count==1)
        bull_order=pl.get('bullOrder',{})
        validate_bull_order(bull_order,size)
        pools.append({'names':names,'results':results,'bullOrder':bull_order})
    cross=state.get('cross',{})
    validate_cross(cross,pool_count,size)
    date=state.get('date','')
    if not isinstance(date,str) or len(date)>20: raise ValueError('Invalid date.')
    history=state.get('history',[])
    if not isinstance(history,list) or len(history)>1000: raise ValueError('Invalid history.')
    for h in history:
        if not isinstance(h,dict): raise ValueError('Invalid history item.')
        if not isinstance(h.get('date',''),str) or len(h.get('date',''))>20: raise ValueError('Invalid date in history.')
        if not isinstance(h.get('champion',''),str) or len(h.get('champion',''))>36: raise ValueError('Invalid champion in history.')
        if not isinstance(h.get('runnerUp',''),str) or len(h.get('runnerUp',''))>36: raise ValueError('Invalid runner-up in history.')
        if not isinstance(h.get('size',4),int) or h.get('size',4) not in (2,4,5,6,7,8,16): raise ValueError('Invalid pool size in history.')
    tally180=state.get('tally180',{})
    validate_tally180(tally180)
    finishes=state.get('finishes',[])
    validate_finishes(finishes)
    fmt=state.get('format','pools')
    if fmt not in ('pools','elim'): raise ValueError('Invalid tournament format.')
    elim_size=int(state.get('elimSize',4))
    if elim_size<2 or elim_size>64 or elim_size%2!=0: raise ValueError('Elimination player count must be an even number from 2 to 64.')
    elim=state.get('elim',default_elim(elim_size))
    validate_elim(elim,elim_size)
    clean={'poolCount':pool_count,'size':size,'pools':pools,'cross':cross,'date':date,'history':history,'tally180':tally180,'finishes':finishes,'format':fmt,'elimSize':elim_size,'elim':elim}
    if os.path.exists(DATA):
        try: shutil.copyfile(DATA,DATA+'.bak')
        except OSError: pass
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
        path=self.path.split('?',1)[0]
        if path=='/' or path=='/index.html':
            with open('/app/index.html','rb') as f: return self.reply(200,f.read(),'text/html; charset=utf-8')
        if path=='/display' or path=='/display.html':
            with open('/app/display.html','rb') as f: return self.reply(200,f.read(),'text/html; charset=utf-8')
        if path=='/manifest.json':
            with open('/app/manifest.json','rb') as f: return self.reply(200,f.read(),'application/manifest+json')
        if path=='/favicon.svg':
            with open('/app/favicon.svg','rb') as f: return self.reply(200,f.read(),'image/svg+xml')
        if path=='/api/state': return self.reply(200,load())
        if path=='/api/version':
            try:
                with open('/app/version.json','rb') as f: return self.reply(200,f.read())
            except OSError: return self.reply(200,{'commit':'unknown','date':'unknown'})
        if path=='/api/auth': return self.reply(200,{'authed':is_authed(self),'loginRequired':bool(EDITOR_PASSWORD)})
        return self.reply(404,{'error':'Not found'})
    def do_POST(self):
        if self.path=='/api/login':
            try: body=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))))
            except json.JSONDecodeError: return self.reply(400,{'error':'Invalid request'})
            password=str(body.get('password',''))
            if not EDITOR_PASSWORD or hmac.compare_digest(password,EDITOR_PASSWORD):
                return self.reply(200,{'authed':True},extra_headers={'Set-Cookie':f'session={make_token()}; Path=/; HttpOnly; SameSite=Strict; Max-Age=15552000'})
            return self.reply(401,{'error':'Incorrect password'})
        if self.path=='/api/logout':
            return self.reply(200,{'authed':False},extra_headers={'Set-Cookie':'session=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0'})
        return self.reply(404,{'error':'Not found'})
    def do_PUT(self):
        if self.path!='/api/state': return self.reply(404,{'error':'Not found'})
        if not is_authed(self): return self.reply(401,{'error':'Log in to edit.'})
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

