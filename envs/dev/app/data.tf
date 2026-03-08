# data "terraform_remote_state": 다른 레이어의 outputs 값을 읽어오는 방법
# 각 레이어는 독립된 State를 가지므로 직접 참조 대신 remote_state로 참조해야 함

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "bootstrap-ljp-practice-terraform-state"
    key    = "dev/network/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

data "terraform_remote_state" "security" {
  backend = "s3"
  config = {
    bucket = "bootstrap-ljp-practice-terraform-state"
    key    = "dev/security/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

data "terraform_remote_state" "web" {
  backend = "s3"
  config = {
    bucket = "bootstrap-ljp-practice-terraform-state"
    key    = "dev/web/terraform.tfstate"
    region = "ap-northeast-2"
  }
}
