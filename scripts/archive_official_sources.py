#!/usr/bin/env python3
"""Archive official entry pages and their directly linked documents, with provenance.

This is an initial source discovery pass, never a claim of historical coverage.
Redirects stay within the environment's allowed domains. Robots exclusions apply
before fetching pages and documents. Provider challenges are not bypassed.
"""
import argparse
import gzip
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import sys
import time
from urllib.parse import urljoin, urlsplit, urlunsplit
from urllib.robotparser import RobotFileParser
from datetime import datetime, timezone
import httpx

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--retry-network-blocked',action='store_true',help='Revisit only sources redirected to previously unallowed domains')
args=parser.parse_args()
REPO = Path(__file__).resolve().parents[1]
ROOT = Path('/workspace/lexmemoria-additional-sources')
ROOT.mkdir(exist_ok=True)
(ROOT/'objects').mkdir(exist_ok=True)
policy = json.loads(Path('/etc/codex/network-policy.json').read_text())
allowed = {r['host'] for r in policy['http_network_policy']['egress_rules']}
sources = json.loads((REPO/'docs/fuentes-oficiales.json').read_text())['items']
report = {'scope': 'Entry pages and directly linked documents only; historical catalogues not complete',
          'sources': [], 'started_at': datetime.now(timezone.utc).isoformat()}
client = httpx.Client(timeout=httpx.Timeout(30, connect=15), follow_redirects=False,
                      headers={'User-Agent': 'LexMemoria/0.2 official-source-archive', 'Accept': '*/*'})

def checkpoint():
    temporary = ROOT/'status.json.tmp'
    temporary.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    temporary.replace(ROOT/'status.json')

def fetch(url):
    for _ in range(6):
        if urlsplit(url).hostname not in allowed:
            return {'url': url, 'state': 'redirect_domain_not_allowed'}
        time.sleep(.6)
        try:
            with client.stream('GET', url) as response:
                if response.is_redirect:
                    url = urljoin(url, response.headers.get('location', ''))
                    continue
                chunks=[]; size=0
                for chunk in response.iter_bytes():
                    size += len(chunk)
                    if size > 32*1024*1024:
                        return {'url': url, 'state': 'response_size_limit'}
                    chunks.append(chunk)
                raw=b''.join(chunks); digest=hashlib.sha256(raw).hexdigest()
                path=ROOT/'objects'/(digest+'.gz')
                if not path.exists():path.write_bytes(gzip.compress(raw,mtime=0))
                state='archived' if response.status_code==200 and raw else 'provider_response_without_document'
                if response.status_code in (401,403,429):state='provider_access_restricted'
                result={'url':url,'state':state,'http_status':response.status_code,'bytes':len(raw),
                        'sha256':digest,'object':str(path.relative_to(ROOT)),
                        'content_type':response.headers.get('content-type',''),
                        'fetched_at':datetime.now(timezone.utc).isoformat()}
                return result
        except httpx.HTTPError as exc:
            return {'url':url,'state':'network_error','error':type(exc).__name__}
    return {'url':url,'state':'redirect_limit'}

def raw(result):
    return gzip.decompress((ROOT/result['object']).read_bytes()) if result.get('object') else b''

class Links(HTMLParser):
    def __init__(self):super().__init__();self.links=[]
    def handle_starttag(self, tag, attrs):
        if tag=='a':
            href=dict(attrs).get('href')
            if href:self.links.append(href)

robots={}
old=ROOT/'status.json'
if old.exists():
    report=json.loads(old.read_text())
if args.retry_network_blocked:
    retry=[r for r in report['sources'] if any(r.get(k,{}).get('state')=='redirect_domain_not_allowed' for k in ('robots','entry_page'))]
    report.setdefault('previous_attempts',[]).extend(retry)
    retry_urls={r['source_url'] for r in retry}
    report['sources']=[r for r in report['sources'] if r['source_url'] not in retry_urls]
done={r['source_url'] for r in report['sources']}
for source in sources:
    if source['url'] in done:continue
    parsed=urlsplit(source['url']);url=urlunsplit(('https',parsed.netloc,parsed.path,parsed.query,''))
    origin='https://'+parsed.netloc
    entry={'title':source['title'],'source_url':source['url'],'coverage_complete':False,'documents':[]}
    if origin not in robots:
        response=fetch(origin+'/robots.txt')
        parser=RobotFileParser()
        if response.get('http_status')==200:
            parser.parse(raw(response).decode('utf-8',errors='replace').splitlines())
        elif response.get('http_status')==404:parser.parse([])
        else:parser=None
        robots[origin]=(parser,response)
    parser,rule=robots[origin];entry['robots']=rule
    if parser is None:
        entry['state']='robots_unavailable_requires_review'
    elif not parser.can_fetch('LexMemoria',url):
        entry['state']='robots_excluded'
    else:
        page=fetch(url);entry['entry_page']=page;entry['state']=page['state']
        if page['state']=='archived' and 'html' in page['content_type']:
            links=Links();links.feed(raw(page).decode('utf-8',errors='replace'))
            urls=sorted({urljoin(page['url'],href) for href in links.links})
            entry['discovered_links']=urls
            for document in urls:
                path=urlsplit(document).path.lower()
                if not path.endswith(('.pdf','.xml')):continue
                if urlsplit(document).hostname!=urlsplit(page['url']).hostname:continue
                if not parser.can_fetch('LexMemoria',document):continue
                result=fetch(document);entry['documents'].append(result)
                if result.get('http_status') in (401,403,429):break
    report['sources'].append(entry);checkpoint()
    print(json.dumps({'source':source['title'],'state':entry['state'],
                      'documents':len(entry['documents']),'processed':len(report['sources']),'total':len(sources)},ensure_ascii=False),flush=True)
report['finished_at']=datetime.now(timezone.utc).isoformat();checkpoint()
