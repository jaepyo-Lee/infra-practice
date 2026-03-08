data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "bootstrap-ljp-practice-terraform-state"
    key    = "dev/network/terraform.tfstate"
    region = "ap-northeast-2"
  }
}
