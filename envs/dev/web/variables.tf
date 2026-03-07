variable "name" {
  type        = string
  description = "리소스 네이밍 prefix (예: dev, prod)"
  default     = "dev"
}

variable "tags" {
  type        = map(string)
  description = "모든 리소스에 공통 적용할 태그"
  default = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
