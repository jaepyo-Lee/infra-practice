# Terraform — Database Tier 핵심 리소스

> 마지막 업데이트: 2026-03-08

Phase 5 (Database Tier)에서 사용하는 Terraform 리소스의 핵심 파라미터 정리.

---

## random_password

```hcl
resource "random_password" "rds" {
  length           = 16
  special          = true
  override_special = "!#$%^&*()-_=+[]{}:?"
}
```

| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `length` | ✅ | 생성할 패스워드 길이 |
| `special` | - | 특수문자 포함 여부 |
| `override_special` | - | 허용할 특수문자 목록. 미설정 시 모든 특수문자 포함 → RDS 제약(`/`, `@`, `"`, 공백 불허)으로 에러 발생 가능 |

**왜 `override_special`이 필요한가?**
RDS는 패스워드에 `/`, `@`, `"`, 공백을 허용하지 않는다.
`special=true`만 쓰면 이 문자들이 포함될 수 있어 "InvalidParameterValue" 에러가 발생한다.
허용할 문자를 명시적으로 지정해야 안전하다.

**State 보안 주의**:
`random_password`의 결과값은 Terraform State에 평문으로 저장된다.
S3 Backend의 `encrypt = true`가 반드시 필요한 이유다.

---

## aws_db_subnet_group

```hcl
resource "aws_db_subnet_group" "rds" {
  name       = "${var.name}-rds-subnet-group"
  subnet_ids = var.db_subnet_ids
}
```

| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `name` | ✅ | 서브넷 그룹 이름. 소문자, 숫자, 하이픈만 허용 |
| `subnet_ids` | ✅ | RDS가 배치될 서브넷 ID 목록. 최소 2개 AZ의 서브넷 필요 (Multi-AZ 구성 조건) |

**왜 최소 2개 AZ가 필요한가?**
RDS Multi-AZ 구성에서 AZ 장애 시 다른 AZ로 Failover 해야 하기 때문이다.
1개 AZ만 있으면 서브넷 그룹을 만들 수 있지만, Multi-AZ 구성 자체가 불가능하다.

---

## aws_rds_cluster_parameter_group

```hcl
resource "aws_rds_cluster_parameter_group" "aurora" {
  name   = "${var.name}-aurora-mysql8-cluster-pg"
  family = "aurora-mysql8.0"

  parameter {
    name         = "slow_query_log"
    value        = "1"
    apply_method = "immediate"
  }
}
```

| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `family` | ✅ | DB 엔진 계열. Aurora MySQL 8.0 → `aurora-mysql8.0`, Aurora MySQL 5.7 → `aurora-mysql5.7` |
| `parameter.name` | ✅ | DB 파라미터 이름 |
| `parameter.value` | ✅ | 파라미터 값 |
| `parameter.apply_method` | - | `immediate`: 재부팅 없이 즉시 적용. `pending-reboot`: 다음 재부팅 시 적용 |

**`family` 값 선택 실수 주의**:
Aurora MySQL 3.x (MySQL 8.0 호환)는 `family = "aurora-mysql8.0"`
일반 RDS MySQL 8.0은 `family = "mysql8.0"`
Aurora와 일반 RDS의 family 값이 다르다 → 혼동 주의

---

## aws_rds_cluster

```hcl
resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "${var.name}-aurora-cluster"
  engine             = "aurora-mysql"
  engine_version     = "8.0.mysql_aurora.3.04.0"

  database_name   = var.db_name
  master_username = var.db_master_username
  master_password = random_password.rds.result

  db_subnet_group_name            = aws_db_subnet_group.rds.name
  vpc_security_group_ids          = [var.db_sg_id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name

  backup_retention_period      = 1
  preferred_backup_window      = "19:00-20:00"
  preferred_maintenance_window = "sun:20:00-sun:21:00"

  storage_encrypted                = true
  enabled_cloudwatch_logs_exports  = ["audit", "error", "slowquery"]
  deletion_protection              = false
  skip_final_snapshot              = true

  lifecycle {
    ignore_changes = [master_password]
  }
}
```

| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `cluster_identifier` | ✅ | 클러스터 이름. 리전 내 유일해야 함 |
| `engine` | ✅ | `aurora-mysql` 또는 `aurora-postgresql` |
| `engine_version` | - | Aurora MySQL 버전. 미지정 시 AWS 기본값 사용 (예상치 못한 버전으로 생성될 수 있음) |
| `master_username` | ✅ | 마스터 계정명. `admin`, `root` 등 예약어 불가 |
| `master_password` | ✅ | 마스터 패스워드. random_password 결과를 참조하는 것이 Best Practice |
| `db_subnet_group_name` | ✅ | 배치될 서브넷 그룹 |
| `vpc_security_group_ids` | - | 연결할 SG 목록. 미설정 시 VPC 기본 SG 사용 → 보안 위험 |
| `storage_encrypted` | - | 저장 데이터 암호화. 기본 `false` → **반드시 `true`로 설정** (나중에 변경 불가) |
| `deletion_protection` | - | `true`이면 Terraform destroy도 불가. prod 필수 |
| `skip_final_snapshot` | - | `false`이면 `final_snapshot_identifier`도 같이 설정해야 함 |
| `backup_retention_period` | - | 1-35일. 0으로 설정 시 자동 백업 완전 비활성화 |
| `preferred_backup_window` | - | UTC 기준. 유지보수 윈도우와 **겹치면 에러** |
| `enabled_cloudwatch_logs_exports` | - | 내보낼 로그 타입. `["audit", "error", "slowquery"]` 권장 |

---

## aws_rds_cluster_instance

```hcl
resource "aws_rds_cluster_instance" "aurora" {
  count = var.aurora_instance_count

  identifier         = "${var.name}-aurora-instance-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = var.aurora_instance_class
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  publicly_accessible          = false
  performance_insights_enabled = true
}
```

| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `cluster_identifier` | ✅ | 속할 클러스터 ID |
| `instance_class` | ✅ | 인스턴스 타입. **Aurora 최소 사양: `db.t3.medium`** (db.t3.micro 불가) |
| `engine` / `engine_version` | ✅ | 클러스터와 동일하게 설정. 클러스터 참조 권장 |
| `publicly_accessible` | - | 기본 `false`. 명시적으로 선언해야 실수 방지 |
| `performance_insights_enabled` | - | 쿼리별 DB 부하 분석. 기본 7일 무료 |

**count를 사용하는 이유**:
Writer와 Reader 인스턴스는 동일한 설정을 가진다.
차이는 Aurora가 자동으로 첫 번째(index=0)를 Writer로 지정하는 것뿐이다.
`count`로 중복 코드 없이 여러 인스턴스를 생성할 수 있다.

---

## aws_elasticache_subnet_group

```hcl
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.name}-redis-subnet-group"
  subnet_ids = var.db_subnet_ids
}
```

RDS Subnet Group과 동일한 개념. 파라미터 구조도 거의 같다.

---

## aws_elasticache_parameter_group

```hcl
resource "aws_elasticache_parameter_group" "redis" {
  name   = "${var.name}-redis7-pg"
  family = "redis7"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }
}
```

| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `family` | ✅ | Redis 버전. `redis7`, `redis6.x`, `redis5.0` 등 |

---

## aws_elasticache_replication_group

```hcl
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.name}-redis"
  description          = "..."

  engine         = "redis"
  engine_version = "7.0"
  node_type      = var.redis_node_type

  num_cache_clusters         = 2
  automatic_failover_enabled = true

  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.cache_sg.id]
  parameter_group_name = aws_elasticache_parameter_group.redis.name

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  snapshot_retention_limit = 1
  snapshot_window          = "20:00-21:00"
  maintenance_window       = "sun:21:00-sun:22:00"
}
```

| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `replication_group_id` | ✅ | Replication Group 이름. 리전 내 유일해야 함 |
| `description` | ✅ | 설명 (빈 문자열도 허용하지만 의미 있는 설명 권장) |
| `node_type` | ✅ | 노드 타입. dev: `cache.t3.micro`, prod: `cache.r6g.large` 이상 |
| `num_cache_clusters` | - | 총 노드 수(Primary 포함). `automatic_failover_enabled=true`이면 **최소 2** |
| `automatic_failover_enabled` | - | `num_cache_clusters >= 2` 조건 필요. 미충족 시 에러 |
| `at_rest_encryption_enabled` | - | 저장 데이터 암호화. 생성 후 변경 불가 → 처음부터 true 설정 |
| `transit_encryption_enabled` | - | TLS 연결 강제. true이면 앱에서 `rediss://` 프로토콜 사용 필요 |
| `snapshot_retention_limit` | - | 0=스냅샷 비활성화, 1-35=보존 일수 |

---

## lifecycle { ignore_changes } 패턴

```hcl
# RDS에서 Secrets Manager 자동 로테이션을 사용할 때 필수
resource "aws_rds_cluster" "aurora" {
  # ...
  lifecycle {
    ignore_changes = [master_password]
  }
}
```

**왜 필요한가?**
Secrets Manager가 패스워드를 자동으로 교체하면, RDS의 실제 패스워드가 State와 달라진다.
다음 `terraform plan` 실행 시 Terraform이 "패스워드가 바뀌었으니 되돌리겠다"고 판단해 불필요한 변경을 시도한다.
`ignore_changes`로 외부 변경을 무시하면 이 문제를 방지할 수 있다.
