# Hermes #58166 우회 패치 (미출시 업스트림 버그)
# 미인증 / 방문 시 auto-SSO 가 /auth/login?provider=basic 로 빠져 NotImplementedError(500).
# basic provider 는 password-only 라 OAuth redirect 없음 → _auto_sso_response 가
# None 을 반환해 /login 폼으로 폴백하도록 한다.
# #58166 머지/릴리스(fix 포함 이미지) 시 이 파일 + 관련 task 제거.
import pathlib

p = pathlib.Path('/opt/hermes/hermes_cli/dashboard_auth/middleware.py')
s = p.read_text()
marker = '# [workaround hermes#58166]'

if marker not in s:
    old = '    provider = providers[0]'
    assert old in s, 'anchor not found in middleware.py'
    inj = old + '\n    ' + marker + ' password-only (basic) has no OAuth redirect -> render /login'
    inj += "\n    if getattr(provider, 'name', '') == 'basic':"
    inj += '\n        return None'
    p.write_text(s.replace(old, inj, 1))
    print('PATCHED')
else:
    print('ALREADY')
