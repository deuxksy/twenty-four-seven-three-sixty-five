# GEMINI.md

This file provides guidance to Gemini CLI and Antigravity (AGY) when working with code in this repository.

@./.ai/RULES.md

## Gemini / Antigravity Specific Instructions

- 이 저장소는 OCI 인프라 및 Docker 서비스를 관리하므로 파괴적 변경(재부팅, 컨테이너 재생성) 전에는 변경 계획 및 대상을 먼저 명시합니다.
- 검증은 항상 기본 쉘 도구를 사용해 `ansible-playbook --syntax-check` 및 `tofu validate`를 수행합니다.

