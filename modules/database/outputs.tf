# ── RDS Aurora ──────────────────────────────────────────────

output "rds_cluster_endpoint" {
  value       = aws_rds_cluster.aurora.endpoint
  description = "Aurora Writer 엔드포인트. 쓰기 작업(INSERT/UPDATE/DELETE)에 사용. 장애 시 자동으로 새 Writer를 가리킴"
}

output "rds_cluster_reader_endpoint" {
  value       = aws_rds_cluster.aurora.reader_endpoint
  description = "Aurora Reader 엔드포인트. 읽기(SELECT) 전용. 여러 Reader 인스턴스에 자동 부하 분산"
}

output "rds_cluster_id" {
  value       = aws_rds_cluster.aurora.id
  description = "Aurora 클러스터 ID. 다른 리소스에서 참조 시 사용"
}

output "rds_cluster_arn" {
  value       = aws_rds_cluster.aurora.arn
  description = "Aurora 클러스터 ARN. IAM 정책의 리소스 지정, CloudWatch 알람 설정 시 사용"
}

# ── Secrets Manager ──────────────────────────────────────────

output "rds_secret_arn" {
  value       = aws_secretsmanager_secret.rds.arn
  description = "RDS 자격증명 Secret ARN. App 서버 IAM 정책에서 이 ARN에 대한 GetSecretValue 권한 필요"
}

output "rds_secret_name" {
  value       = aws_secretsmanager_secret.rds.name
  description = "RDS 자격증명 Secret 이름. App 코드에서 AWS SDK로 조회할 때 사용"
}

# ── ElastiCache Redis ─────────────────────────────────────────

output "redis_primary_endpoint" {
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
  description = "Redis Primary 엔드포인트. 읽기/쓰기 모두 가능. App에서 일반 연결에 사용"
}

output "redis_reader_endpoint" {
  value       = aws_elasticache_replication_group.redis.reader_endpoint_address
  description = "Redis Reader 엔드포인트. 읽기 전용. 여러 Replica가 있을 때 부하 분산"
}

output "redis_replication_group_id" {
  value       = aws_elasticache_replication_group.redis.id
  description = "Redis Replication Group ID. CloudWatch 알람, 모니터링 대시보드 설정 시 사용"
}

output "cache_sg_id" {
  value       = aws_security_group.cache_sg.id
  description = "Redis 전용 Security Group ID. 향후 보안 규칙 추가 시 참조"
}