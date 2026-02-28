terraform {
  backend "s3" {
    bucket = "bootstrap-ljp-practice-terraform-state"
    key = "dev/vpc/terraform.tfstate"
    region = "ap-northeast-2"
    dynamodb_table = "terraform-state-lock"
    encrypt = true
  }
}