# ============================================
# Terraform Backend (Cloudflare R2)
# ============================================
# S3-compatible backend using Cloudflare R2
# terraform-state bucket은 수동 생성 후 이 파일에서 참조만 함
# 생성: npx wrangler r2 bucket create terraform-state --location wnam
# ============================================


terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://e0924c382d21ac0f10aee606b82687ce.r2.cloudflarestorage.com"
    }
    bucket                      = "terraform-state"
    key                         = "twenty-four-seven-three-sixty-five/dev/terraform.tfstate"
    # 🎯 쉘 환경 변수 버그를 우회하기 위해 자격 증명을 100% 평문으로 직결 주입합니다.
    region                      = "auto"

    # AWS가 아니므로 아래의 검증 옵션들을 모두 true로 설정하여 우회해야 합니다.
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}
