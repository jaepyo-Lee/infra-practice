output "rds_cluster_endpoint" {
  value       = module.database.rds_cluster_endpoint
  description = "Aurora Writer 엔드포인트. App 서버의 쓰기 연결 설정에 사용"
}

output "rds_cluster_reader_endpoint" {
  value       = module.database.rds_cluster_reader_endpoint
  description = "Aurora Reader 엔드포인트. 읽기 전용 연결, 부하 분산"
}

output "rds_cluster_id" {
  value       = module.database.rds_cluster_id
  description = "Aurora 클러스터 ID"
}

output "rds_cluster_arn" {
  value       = module.database.rds_cluster_arn
  description = "Aurora 클러스터 ARN. Phase 6 모니터링 알람 설정 시 참조"
}

output "rds_secret_arn" {
  value       = module.database.rds_secret_arn
  description = "RDS 자격증명 Secret ARN. Phase 6 모니터링 또는 추가 IAM 정책 설정 시 참조"
}

output "rds_secret_name" {
  value       = module.database.rds_secret_name
  description = "RDS 자격증명 Secret 이름. App 코드에서 AWS SDK로 조회할 때 사용"
}

output "redis_primary_endpoint" {
  value       = module.database.redis_primary_endpoint
  description = "Redis Primary 엔드포인트"
}

output "redis_reader_endpoint" {
  value       = module.database.redis_reader_endpoint
  description = "Redis Reader 엔드포인트"
}

output "redis_replication_group_id" {
  value       = module.database.redis_replication_group_id
  description = "Redis Replication Group ID. Phase 6 모니터링 알람 설정 시 참조"
}
