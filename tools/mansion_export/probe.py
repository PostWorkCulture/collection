import asyncio, json, sys, subprocess, time, os
HERE=os.path.dirname(os.path.abspath(__file__))
from playwright.async_api import async_playwright
ROOT=os.environ['ROOT']                      # a checkout of PostWorkCulture/1v1 at collection-v1 (76738cc)
PATCH=os.environ.get('PATCH',os.path.join(HERE,'index_patched.html'))
THREE=os.environ['THREE']                    # three@0.158.0 build/three.min.js
srv=subprocess.Popen(['python3','-m','http.server','8765','--bind','127.0.0.1'],cwd=ROOT,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
time.sleep(1)
async def main():
    async with async_playwright() as p:
        b=await p.chromium.launch(executable_path='/usr/bin/google-chrome',headless=True,args=['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist','--autoplay-policy=no-user-gesture-required'])
        pg=await b.new_page(viewport={'width':1280,'height':720})
        logs=[]
        pg.on('console',lambda m: logs.append(m.text))
        pg.on('pageerror',lambda e: logs.append('PAGEERROR '+str(e)))
        async def route(r):
            u=r.request.url
            if 'three@0.158.0/build/three.min.js' in u:
                await r.fulfill(path=THREE,content_type='application/javascript')
            elif u.split('?')[0].endswith('/index.html'):
                await r.fulfill(path=PATCH,content_type='text/html')
            elif u.startswith('http://127.0.0.1:8765/__export/'):
                await r.fulfill(path=os.path.join(HERE,u.split('/__export/')[1]),content_type='application/javascript')
            elif u.startswith('http://127.0.0.1:8765'):
                await r.continue_()
            else:
                await r.abort()
        await pg.route('**/*',route)
        await pg.goto('http://127.0.0.1:8765/index.html',wait_until='load',timeout=120000)
        try:
            await pg.wait_for_function('window.__X && typeof __X.buildMap==="function"',timeout=40000)
        except Exception as e:
            print('WAIT FAIL', await pg.evaluate('[typeof THREE, typeof buildMap, document.readyState, document.title]'))
            print('\n'.join(logs[:40]))
            await b.close(); return
        await asyncio.sleep(2)
        exec_js=sys.argv[1] if len(sys.argv)>1 else '1'
        res=await pg.evaluate(exec_js)
        out=os.environ.get('OUT')
        if out: open(out,'w').write(json.dumps(res))
        print(json.dumps(res)[:3000])
        print('\n'.join(l for l in logs if 'ERROR' in l.upper())[:3000])
        await b.close()
asyncio.run(main())
srv.terminate()
