# twenty-four-seven-three-sixty-five

Web Browser만으로 개발해야 하는 환경에서 OCI Free-Tier 인프라를 프로비저닝하기 위한 프로젝트. OpenTofu + SOPS(age) + GitHub Codespaces.

## Quick Start

```bash
# 1. Codespaces에서 열기 (SOPS_AGE_KEY 환경변수 필수)
# 2. 시크릿 복호화
source .env.local
dec        # .env.sops → .env

# 3. 인프라 배포
bash setup.sh
```

## 구조

```
.env.sops          # 암호화된 시크릿 (git 추적)
.env.local         # enc/dec/load alias
setup.sh           # 복호화 → tfvars 생성 → tofu apply
opentofu/          # OpenTofu 코드
.devcontainer/     # Codespaces 설정
```
