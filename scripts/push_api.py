# -*- coding: utf-8 -*-
"""通过 api.github.com Git Data 接口提交文件（绕开被干扰的 github.com:443）"""
import base64, json, os, sys, urllib.request, urllib.error

TOKEN = json.load(open('D:/dev/tools/gh_token.json'))['access_token']
REPO = 'shangjie-dz/shangjie-ios-app'
BRANCH = 'main'
ROOT = 'D:/WorkBuddy/shangjie-ios-app'
API = 'https://api.github.com'

DELETE = ['.github/workflows/probe.yml']


def call(method, path, payload=None):
    url = API + path if path.startswith('/') else path
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header('Authorization', 'token ' + TOKEN)
    req.add_header('Accept', 'application/vnd.github+json')
    if data:
        req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            body = r.read().decode()
            return json.loads(body) if body.strip() else {}
    except urllib.error.HTTPError as e:
        print('HTTP %s on %s %s' % (e.code, method, url))
        print(e.read().decode()[:800])
        raise


def main():
    files = sys.argv[1:]
    ref = call('GET', '/repos/%s/git/ref/heads/%s' % (REPO, BRANCH))
    base_commit = ref['object']['sha']
    base = call('GET', '/repos/%s/git/commits/%s' % (REPO, base_commit))
    base_tree = base['tree']['sha']
    print('base', base_commit[:8])

    entries = []
    for rel in files:
        full = os.path.join(ROOT, rel)
        raw = open(full, 'rb').read()
        blob = call('POST', '/repos/%s/git/blobs' % REPO,
                    {'content': base64.b64encode(raw).decode(), 'encoding': 'base64'})
        entries.append({'path': rel, 'mode': '100644', 'type': 'blob', 'sha': blob['sha']})
        print('  blob', rel, len(raw), 'bytes')
    for rel in DELETE:
        entries.append({'path': rel, 'mode': '100644', 'type': 'blob', 'sha': None})
        print('  delete', rel)

    tree = call('POST', '/repos/%s/git/trees' % REPO, {'base_tree': base_tree, 'tree': entries})
    msg = os.environ.get('COMMIT_MSG', 'update via api')
    commit = call('POST', '/repos/%s/git/commits' % REPO,
                  {'message': msg, 'tree': tree['sha'], 'parents': [base_commit]})
    call('PATCH', '/repos/%s/git/refs/heads/%s' % (REPO, BRANCH), {'sha': commit['sha'], 'force': False})
    print('NEW_COMMIT', commit['sha'])
    return commit['sha']


if __name__ == '__main__':
    main()
