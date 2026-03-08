terraform {
  backend "s3" {
    bucket         = "bootstrap-ljp-practice-terraform-state"
    key            = "dev/database/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
    # encrypt=true: State 파일을 S3에 저장할 때 AES-256으로 암호화
    # master_password, random_password 결과값이 State에 평문으로 저장되므로
    # 이 설정이 없으면 누구나 S3에서 패스워드를 읽을 수 있음
  }
}
