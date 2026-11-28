import re,os,sys,json
frags={}
def add(piece,src):
    for part in re.split(r'<[^>]+>|%[-0-9.]*[sdfiq%]|\\n|\n|\{[a-z_]+\}', piece):
        t=part.strip()
        if re.search('[А-Яа-яЁё]',t):
            frags.setdefault(t,src)
roots=['src','tools/build','tools/build_place.luau']
files=[]
for r in roots:
    if os.path.isfile(r): files.append(r)
    else:
        for dp,_,fs in os.walk(r):
            files+= [os.path.join(dp,f) for f in fs if f.endswith(('.lua','.luau'))]
for f in files:
    s=open(f,encoding='utf8').read()
    # strip comments
    s=re.sub(r'--\[\[.*?\]\]','',s,flags=re.S)
    s=re.sub(r'--[^\n]*','',s)
    for m in re.finditer(r'"((?:[^"\\\n]|\\.)*)"|\'((?:[^\'\\\n]|\\.)*)\'|\[\[(.*?)\]\]',s,flags=re.S):
        piece=m.group(1) or m.group(2) or m.group(3) or ''
        add(piece,f)
print(len(frags))
json.dump(sorted(frags),open(sys.argv[1] if len(sys.argv)>1 else 'build/frags.json','w'),ensure_ascii=False,indent=0)
print(sum(len(k) for k in frags))
