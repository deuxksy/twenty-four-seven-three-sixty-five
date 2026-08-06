---
name: cross-verify
description: 인프라 변경/설계를 codex(gpt-5.5)로 교차 검증 — Blocker/Risk/Assumption/Test 포맷
disable-model-invocation: true
---

# Codex 교차 검증

복잡한 인프라 변경/설계를 codex(gpt-5.5)로 독립 검증. 자기 편향 방지.

## 호출 패턴

```bash
codex exec -m gpt-5.5 -c sandbox_mode=workspace-write -c approval_policy=never - << 'PROMPT' 2>&1
You are a verification agent. Review the plan/code below. Analysis ONLY — do NOT modify files. Respond in Korean.

[컨텍스트: 현재 상태, 관련 파일/서비스, 제약사항]

[목표 + 제안 계획 단계]

VERIFY:
- [검증 항목: 정확성, 순서, 보안, 멱등성, 롤백]

OUTPUT strict format:
- [Blocker] must fix before proceeding
- [Risk] be aware
- [Assumption] verified
- [Test] recommended test cases
PROMPT
```

## 파라미터

| 항목 | 값 | 비고 |
| :--- | :--- | :--- |
| 모델 | `gpt-5.5` | 복잡 분석/설계. 표준 코딩 `gpt-5.4`, 경량 `gpt-5.4-mini` |
| 샌드박스 | `workspace-write` | 파일 읽기 허용, 수정 안 함 (검증) |
| 승인 | `never` | non-interactive 자동 승인 |
| 입력 | `-` (stdin) | heredoc으로 프롬프트 전달 |

## 검증 프롬프트 필수 요소

1. **컨텍스트**: 현재 인프라 상태, 관련 파일/서비스, 제약 (UID, 포트, 마운트 등)
2. **목표**: 무엇을 변경/설계하는지
3. **제안 계획**: 단계별 (번호)
4. **VERIFY 항목**: 구체적 검증 포인트
5. **출력 포맷**: Blocker / Risk / Assumption / Test

## 적용 기준 (CLAUDE.md 05-multi-agent.md)

| 티어 | 조건 | 검증 |
| :--- | :--- | :--- |
| 경량 | 문서/설정/minor 의존성 | Codex 단일 |
| 표준 | 기능 개발/버그 수정/리팩토링 | Antigravity(spec) / Codex(code) |
| 고위험 | 인증/데이터/배포/API 호환/대규모 삭제 | Codex + Antigravity 병렬 |

## 제한

- Antigravity(`agy`): MCP 미지원, Bash 호출. 인증/quota 이슈 시 Codex 단일 폴백
- sgpt(ModelArk): 비활성 (구독 종료) — 현재 Codex 단일 또는 2-way

## 실적

- Docker data-root 마이그레이션 계획 검증 → Blocker 4건 식별 (daemon.json 배포 순서, handler 위험, /data/docker 권한, rollback 누락) → containerd image store 데이터 누락까지 사전 포착 → 마이그레이션 성공. commit `5d8efb8`
