# modules/database/main.tf
# Phase 5 — Database Tier
# RDS Aurora MySQL (Multi-AZ) + ElastiCache Redis

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. 랜덤 패스워드 생성
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# random_password: 코드에 패스워드를 직접 쓰지 않기 위한 핵심 패턴
# 생성된 값은 Terraform State에 저장됨 → S3 Backend의 encrypt=true가 필수인 이유
# lifecycle.ignore_changes로 매 apply마다 재생성되지 않게 함
resource "random_password" "rds" {
  length           = 16
  special          = true
  # RDS가 허용하지 않는 특수문자(/, @, ", space)를 제외
  # 허용하지 않으면 "InvalidParameterValue" 에러 발생
  override_special = "!#$%^&*()-_=+[]{}:?"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. Secrets Manager — RDS 자격증명
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 패턴: random_password 생성 → Secrets Manager에 저장 → RDS가 같은 패스워드 사용
# App 서버는 이 Secret을 SDK로 읽어 DB 접속 정보를 얻음 (하드코딩 금지)
resource "aws_secretsmanager_secret" "rds" {
  name                    = "${var.name}/rds/credentials"
  description             = "RDS Aurora MySQL 접속 자격증명 (Terraform auto-generated)"
  recovery_window_in_days = var.secret_recovery_window_days
  # recovery_window_in_days = 0 → 즉시 삭제 (dev 환경용)
  # prod 환경에서는 7~30일 설정 필수 — 실수로 삭제해도 복구 가능

  tags = merge(var.tags, { Name = "${var.name}/rds/credentials" })
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id
  # jsonencode: Terraform map을 JSON 문자열로 변환
  # App 서버는 이 JSON을 파싱해 각 필드를 추출 (AWS SDK GetSecretValue 사용)
  secret_string = jsonencode({
    username    = var.db_master_username
    password    = random_password.rds.result
    host        = aws_rds_cluster.aurora.endpoint        # Writer 엔드포인트
    reader_host = aws_rds_cluster.aurora.reader_endpoint # Reader 엔드포인트 (SELECT용)
    port        = 3306
    dbname      = var.db_name
    engine      = "mysql"
  })

  # secret_version 의존성:
  # random_password.rds → aws_rds_cluster.aurora 모두 생성 후 이 리소스가 생성됨
  # aurora.endpoint가 있어야 host 값을 채울 수 있으므로
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. RDS Subnet Group
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Subnet Group: RDS가 배치될 서브넷 풀을 AWS에 등록하는 메타데이터
# 최소 2개 AZ 서브넷이 필요한 이유:
# Multi-AZ 구성 시 장애 발생한 AZ에서 다른 AZ로 Failover 해야 하기 때문
resource "aws_db_subnet_group" "rds" {
  name        = "${var.name}-rds-subnet-group"
  description = "RDS Aurora MySQL용 Private DB 서브넷 그룹"
  subnet_ids  = var.db_subnet_ids
  # private_full_subnet_ids: NAT GW도 없는 완전 격리 서브넷
  # 인터넷 아웃바운드 없음 → RDS가 외부로 데이터를 보낼 수 없어 보안 강화

  tags = merge(var.tags, { Name = "${var.name}-rds-subnet-group" })
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. RDS Cluster Parameter Group
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Parameter Group: DB 엔진 동작을 제어하는 설정값 모음
# "클러스터 파라미터 그룹": 클러스터 전체에 적용 (문자셋, 바이너리 로그 등)
# "인스턴스 파라미터 그룹": 각 인스턴스별 적용 (max_connections 등)
# → 이 프로젝트에서는 클러스터 레벨만 설정 (인스턴스는 기본값 사용)
resource "aws_rds_cluster_parameter_group" "aurora" {
  name        = "${var.name}-aurora-mysql8-cluster-pg"
  family      = "aurora-mysql8.0" # Aurora MySQL 8.0 계열 → MySQL 8.0 호환
  description = "Aurora MySQL 8.0 클러스터 파라미터 그룹"

  # utf8mb4: 한글, 이모지 등 4바이트 문자 저장 가능
  # utf8(3바이트)은 이모지 저장 불가 → 실무에서 utf8mb4를 기본값으로 씀
  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  # slow_query_log: 실행 시간이 long_query_time을 초과한 쿼리를 기록
  # 성능 문제 진단의 첫 번째 도구. CloudWatch Logs로 전송해 분석 가능
  parameter {
    name         = "slow_query_log"
    value        = "1"
    apply_method = "immediate" # 재부팅 없이 즉시 적용
  }

  parameter {
    name         = "long_query_time"
    value        = "2" # 2초 이상 걸리는 쿼리를 slow query로 간주
    apply_method = "immediate"
  }

  tags = merge(var.tags, { Name = "${var.name}-aurora-mysql8-cluster-pg" })
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 5. RDS Aurora Cluster
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Cluster: 스토리지 계층 + 설정 + 엔드포인트를 관리하는 논리적 컨테이너
# 실제 컴퓨팅(CPU/RAM)은 aws_rds_cluster_instance가 담당
# Aurora의 스토리지는 3개 AZ에 6벌 복제 — 인스턴스와 분리된 구조
resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "${var.name}-aurora-cluster"

  engine         = "aurora-mysql"
  engine_version = "8.0.mysql_aurora.3.04.0"
  # Aurora MySQL 3.x = MySQL 8.0 호환 (CTE, 윈도우 함수, JSON 함수 지원)
  # Aurora MySQL 2.x = MySQL 5.7 호환 → 신규 프로젝트에서는 3.x 권장

  database_name   = var.db_name
  master_username = var.db_master_username
  master_password = random_password.rds.result
  # 패스워드를 직접 쓰지 않고 random_password에서 참조
  # Terraform State에는 평문으로 저장되므로 S3 encrypt=true가 반드시 필요

  db_subnet_group_name            = aws_db_subnet_group.rds.name
  vpc_security_group_ids          = [var.db_sg_id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name

  # 자동 백업: 매일 지정된 시간에 스냅샷 자동 생성
  # backup_retention_period: 보존 기간 (1~35일). 0으로 설정하면 자동 백업 비활성화
  backup_retention_period = var.backup_retention_period
  preferred_backup_window = "19:00-20:00" # KST 04:00-05:00 (새벽 트래픽 최저)

  # 유지보수 윈도우: 패치, 버전 업그레이드가 이 시간에 수행됨
  # 백업 윈도우와 겹치지 않게 설정해야 함
  preferred_maintenance_window = "sun:20:00-sun:21:00" # KST 일요일 05:00-06:00

  # 저장 데이터 암호화 (KMS 기본 키 사용)
  # false로 생성한 후 true로 변경 불가 — 반드시 처음부터 true로 설정
  storage_encrypted = true

  # CloudWatch Logs 내보내기
  # slowquery: 느린 쿼리 → 성능 튜닝
  # error: 에러 로그 → 장애 원인 분석
  # audit: 접속/쿼리 감사 → 보안 컴플라이언스
  enabled_cloudwatch_logs_exports = ["audit", "error", "slowquery"]

  # 삭제 보호: true이면 콘솔/CLI에서도 삭제 불가. prod는 반드시 true
  deletion_protection = var.deletion_protection

  # skip_final_snapshot: 클러스터 삭제 시 최종 스냅샷 생성 여부
  # prod에서는 false + final_snapshot_identifier를 설정해 마지막 상태를 보존
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-aurora-final-snapshot"

  tags = merge(var.tags, { Name = "${var.name}-aurora-cluster" })

  lifecycle {
    # Secrets Manager 자동 로테이션이 활성화되면 master_password가
    # Terraform 외부에서 변경될 수 있음 → ignore_changes로 drift 무시
    ignore_changes = [master_password]
  }
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 6. RDS Aurora 클러스터 인스턴스
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Aurora = Cluster(논리) + Instance(컴퓨팅)의 이중 구조
# count=2 → 인덱스 0이 Writer, 1이 Reader (Aurora가 자동으로 역할 결정)
#
# ⚠️ 주의: db.t3.micro는 Aurora를 지원하지 않음
# Aurora 최소 사양: db.t3.medium (2 vCPU, 4GB RAM)
# 일반 RDS는 db.t3.micro 가능하지만 Aurora는 불가
resource "aws_rds_cluster_instance" "aurora" {
  count = var.aurora_instance_count

  identifier         = "${var.name}-aurora-instance-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = var.aurora_instance_class

  # Cluster에서 설정한 엔진 정보를 그대로 상속
  engine         = aws_rds_cluster.aurora.engine
  engine_version = aws_rds_cluster.aurora.engine_version

  # publicly_accessible = false: 퍼블릭 IP 미할당 → 인터넷에서 직접 접근 불가
  # Subnet Group이 Private이어도 이 설정이 false여야 완전 차단
  publicly_accessible = false

  # Performance Insights: 쿼리별 DB 부하를 시각화하는 성능 분석 도구
  # 기본 7일 무료 보존, 유료로 최대 2년까지 가능
  performance_insights_enabled = true

  tags = merge(var.tags, {
    Name = "${var.name}-aurora-instance-${count.index + 1}"
    Role = count.index == 0 ? "writer" : "reader"
  })
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 7. ElastiCache Subnet Group
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# RDS Subnet Group과 동일한 개념 — ElastiCache가 배치될 서브넷 풀 등록
# RDS와 같은 Private DB 서브넷에 함께 배치 (동일 보안 계층)
resource "aws_elasticache_subnet_group" "redis" {
  name        = "${var.name}-redis-subnet-group"
  description = "ElastiCache Redis용 Private DB 서브넷 그룹"
  subnet_ids  = var.db_subnet_ids

  tags = merge(var.tags, { Name = "${var.name}-redis-subnet-group" })
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 8. ElastiCache Parameter Group
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
resource "aws_elasticache_parameter_group" "redis" {
  name        = "${var.name}-redis7-pg"
  family      = "redis7"
  description = "Redis 7.x 파라미터 그룹"

  # maxmemory-policy: 메모리가 꽉 찼을 때 기존 데이터 처리 방식
  # allkeys-lru: 모든 키 중 Least Recently Used(최근 미사용)부터 삭제
  # → TTL이 없는 세션 캐시, 인증 토큰 등에 적합
  # volatile-lru: TTL 있는 키만 LRU 삭제 → TTL 없는 중요 데이터를 보존하고 싶을 때
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  tags = merge(var.tags, { Name = "${var.name}-redis7-pg" })
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 9. ElastiCache Redis Security Group
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 기존 security 레이어의 db_sg는 MySQL(3306) 전용
# Redis는 6379 포트를 사용하므로 별도 SG를 database 모듈 내에서 생성
# App SG를 source로 지정 → ASG로 IP가 변경되어도 자동으로 허용
resource "aws_security_group" "cache_sg" {
  name        = "${var.name}-cache-sg"
  description = "ElastiCache Redis 접근 제어 Security Group (App SG에서만 허용)"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from app-sg"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.app_sg_id]
    # CIDR 대신 SG를 source로 쓰는 이유:
    # ASG로 동적 생성/삭제되는 App EC2의 IP를 일일이 관리 불가
    # SG는 "이 SG가 붙은 ENI에서 오는 트래픽" 을 의미 → 동적 대응 가능
  }

  tags = merge(var.tags, { Name = "${var.name}-cache-sg" })
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 10. ElastiCache Replication Group (Redis)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Replication Group: Redis의 Primary + Replica 구성 단위
#
# 클러스터 모드 비활성화 (이 프로젝트):
#   - 단일 샤드, Primary 1 + Replica N
#   - 앱에서 단순 연결 URL 사용 가능
#   - 최대 500GB 데이터, 대부분의 앱에 충분
#
# 클러스터 모드 활성화:
#   - 여러 샤드로 데이터를 분산 저장
#   - 데이터 용량 수평 확장 가능 (단, 앱이 클러스터 프로토콜 지원 필요)
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.name}-redis"
  description          = "Dev 환경 Redis 캐시 (Primary + Replica, 클러스터 모드 비활성화)"

  engine         = "redis"
  engine_version = "7.0"
  node_type      = var.redis_node_type
  # cache.t3.micro: 0.5GB RAM — dev 환경에만 사용
  # prod 권장: cache.r6g.large (13GB) 이상 — 메모리 최적화 인스턴스

  num_cache_clusters = var.redis_num_cache_clusters
  # 2 = Primary 1개 + Replica 1개
  # automatic_failover_enabled = true 이려면 num_cache_clusters >= 2 필수

  automatic_failover_enabled = true
  # Primary 노드 장애 시 Replica가 자동으로 Primary로 승격 (보통 60초 이내)
  # num_cache_clusters=1 이면 false로 설정해야 함

  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.cache_sg.id]
  parameter_group_name = aws_elasticache_parameter_group.redis.name

  # 저장 데이터 암호화 (AES-256)
  at_rest_encryption_enabled = true

  # 전송 중 암호화 (TLS)
  # true이면 App 코드에서 rediss:// (SSL) 프로토콜로 연결해야 함
  # redis:// (비암호화)로 연결하면 연결 거부됨
  transit_encryption_enabled = true

  # 스냅샷 (자동 백업)
  # 0이면 스냅샷 비활성화
  snapshot_retention_limit = var.redis_snapshot_retention_limit
  snapshot_window          = "20:00-21:00" # KST 05:00-06:00 (새벽)

  # 유지보수 윈도우 — 스냅샷 윈도우와 겹치지 않게 설정
  maintenance_window = "sun:21:00-sun:22:00" # KST 일요일 06:00-07:00

  tags = merge(var.tags, { Name = "${var.name}-redis" })
}