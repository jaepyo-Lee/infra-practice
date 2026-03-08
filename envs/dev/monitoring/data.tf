# data "terraform_remote_state": 다른 레이어의 outputs 값을 읽어오는 방법
# monitoring은 web / app / database 세 레이어의 출력값이 필요

data "terraform_remote_state" "web" {
  backend = "s3"
  config = {
    bucket = "bootstrap-ljp-practice-terraform-state"
    key    = "dev/web/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

data "terraform_remote_state" "app" {
  backend = "s3"
  config = {
    bucket = "bootstrap-ljp-practice-terraform-state"
    key    = "dev/app/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

data "terraform_remote_state" "database" {
  backend = "s3"
  config = {
    bucket = "bootstrap-ljp-practice-terraform-state"
    key    = "dev/database/terraform.tfstate"
    region = "ap-northeast-2"
  }
}
