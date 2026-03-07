output "vpc_id" {
  value       = module.main.vpc_id                                          # The actual value to be outputted
  description = "생성한 vpc의 id" # Description of what this output represents
}
