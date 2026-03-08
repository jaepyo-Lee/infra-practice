# AWS RDS Aurora

> 마지막 업데이트: 2026-03-08

---

## 1. 개념 설명

### RDS Aurora란?

Aurora는 AWS가 직접 개발한 클라우드 네이티브 관계형 데이터베이스 엔진이다.
MySQL/PostgreSQL 호환 API를 제공하면서도, 내부 스토리지 아키텍처를 완전히 재설계해 성능과 내구성을 크게 향상시켰다.

- **MySQL 대비 최대 5배 성능**
- **PostgreSQL 대비 최대 3배 성능**
- **스토리지 자동 확장**: 10GB ~ 128TB, 수동 관리 불필요

### Aurora의 혁신: 스토리지와 컴퓨팅의 분리

일반 RDS는 각 인스턴스가 자체 EBS 볼륨을 가지며 Primary → Replica로 데이터를 복제한다.
Aurora는 다르다. **스토리지 계층이 컴퓨팅과 완전히 분리**된다.

```
일반 RDS:
  Primary (EBS) ──복제──> Replica (EBS)
  스토리지가 인스턴스마다 독립적 → 복제 지연(replication lag) 발생

Aurora:
  Writer Instance ──쓰기──> [공유 분산 스토리지]
  Reader Instance ──읽기──> [공유 분산 스토리지]
  모든 인스턴스가 같은 스토리지를 바라봄 → 복제 지연 거의 없음
```

공유 스토리지는 **3개 AZ에 6벌 복제**된다.
2벌 이상 장애가 나지 않는 한 데이터를 잃지 않는다.

### Cluster + Instance 이중 구조

Aurora는 반드시 **Cluster**와 **Instance**를 따로 생성해야 한다.

| 구성요소 | Terraform 리소스 | 역할 |
|----------|-----------------|------|
| Cluster | `aws_rds_cluster` | 스토리지, 엔드포인트, 설정 관리 |
| Instance | `aws_rds_cluster_instance` | 실제 CPU/RAM 컴퓨팅 |

Cluster는 항상 두 종류의 엔드포인트를 제공한다:
- **Writer 엔드포인트**: 현재 Primary 인스턴스를 가리킴. 쓰기 전용
- **Reader 엔드포인트**: 모든 Reader 인스턴스에 라운드로빈 분산. 읽기 전용

Failover 발생 시 Writer 엔드포인트는 자동으로 새 Primary를 가리킨다 → **앱 코드 변경 불필요**

### Multi-AZ 구성과 Failover

```
AZ-a: Writer Instance ──┐
                         ├── 공유 스토리지 (6벌 복제)
AZ-b: Reader Instance ──┘
```

Writer에 장애 발생 시:
1. Aurora가 Reader 중 하나를 새 Writer로 자동 승격
2. Writer 엔드포인트가 새 Writer를 가리킴
3. 보통 60초 이내 완료

### Aurora MySQL 버전 체계

| Aurora MySQL | MySQL 호환 | 비고 |
|-------------|-----------|------|
| 1.x | MySQL 5.6 | EoL |
| 2.x | MySQL 5.7 | 지원 중 |
| 3.x | MySQL 8.0 | ✅ 신규 프로젝트 권장 |

이 프로젝트: `8.0.mysql_aurora.3.04.0` (Aurora MySQL 3.x = MySQL 8.0 호환)
MySQL 8.0 신기능: CTE(`WITH`), 윈도우 함수, JSON 함수 개선, utf8mb4 기본값

### 3-Tier 아키텍처에서의 위치

```
Internet → CloudFront → ALB → App EC2 (ASG) → Aurora (Private DB Subnet)
```

- **위치**: Private DB Subnet (10.0.21.0/24, 10.0.22.0/24)
- **접근 제어**: db_sg → app_sg에서만 3306 포트 인바운드 허용
- **외부 접근**: publicly_accessible=false, NAT GW 없음 → 인터넷과 완전 차단

### Parameter Group 종류

| 종류 | 리소스 | 적용 범위 |
|------|--------|----------|
| 클러스터 파라미터 그룹 | `aws_rds_cluster_parameter_group` | 클러스터 전체 (문자셋, 바이너리 로그 등) |
| 인스턴스 파라미터 그룹 | `aws_rds_db_parameter_group` | 각 인스턴스별 (max_connections 등) |

Aurora는 두 종류를 모두 지원하며, 클러스터 레벨 설정이 우선 적용된다.

---

## 2. 실무 주의사항

### ⚠️ db.t3.micro는 Aurora 미지원

일반 RDS는 db.t3.micro 사용 가능하지만, **Aurora는 db.t3.medium이 최소 사양**이다.
db.t3.micro로 설정하면 apply 시 에러 발생.

```
# 잘못된 예
instance_class = "db.t3.micro"   # ❌ Aurora 미지원

# 올바른 예
instance_class = "db.t3.medium"  # ✅ Aurora 최소 사양
```

### ⚠️ storage_encrypted는 나중에 바꿀 수 없다

`storage_encrypted = false`로 생성한 클러스터를 `true`로 변경하려면 스냅샷에서 새 클러스터를 복원해야 한다.
**반드시 처음부터 `true`로 설정**해야 한다.

### ⚠️ master_password와 ignore_changes

Secrets Manager 자동 로테이션을 활성화하면 AWS가 RDS 패스워드를 주기적으로 교체한다.
이때 Terraform State의 패스워드와 실제 RDS 패스워드가 달라져 drift가 발생한다.

```hcl
lifecycle {
  ignore_changes = [master_password]  # 외부 변경을 Terraform이 되돌리지 않도록
}
```

### ⚠️ 자동 백업과 유지보수 윈도우 겹침 방지

`preferred_backup_window`와 `preferred_maintenance_window`가 겹치면 AWS가 에러를 반환한다.
서로 다른 시간대로 설정해야 한다.

```hcl
preferred_backup_window      = "19:00-20:00"  # KST 04:00-05:00
preferred_maintenance_window = "sun:20:00-sun:21:00"  # KST 일요일 05:00-06:00
```

---

## 3. Terraform 핵심 파라미터

→ [Database Tier Terraform 파라미터](../terraform/database-resources.md)

---

## 4. 이 프로젝트에서의 위치

- **Phase**: 5 — Database Tier
- **레이어**: `envs/dev/database/`
- **모듈**: `modules/database/`

**의존 관계**:
```
network (vpc_id, private_full_subnet_ids)
    ↓
security (db_sg_id, app_sg_id)
    ↓
database (Aurora Cluster, Replication Group)
    ↓
monitoring (Phase 6 — CloudWatch 알람에서 cluster ARN 참조)
```

---

## 5. 참고 자료

- AWS 공식 문서: [Aurora MySQL 버전 호환성](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.AuroraMySQL.Overview.html)
- 검색 키워드: `Aurora MySQL Multi-AZ Failover`, `RDS Cluster Instance 차이`, `Aurora storage architecture`