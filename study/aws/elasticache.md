# AWS ElastiCache (Redis)

> 마지막 업데이트: 2026-03-08

---

## 1. 개념 설명

### ElastiCache란?

ElastiCache는 AWS가 관리하는 인메모리 캐시 서비스다.
Redis와 Memcached 두 엔진을 지원하며, 이 프로젝트에서는 **Redis**를 사용한다.

**왜 캐시가 필요한가?**

```
매 요청마다 RDS에서 데이터를 읽으면:
  App Server → RDS → 데이터 반환 (수십 ms ~ 수백 ms)

자주 읽히는 데이터를 Redis에 캐싱하면:
  App Server → Redis → 데이터 반환 (< 1 ms)
```

- **세션 저장**: 로그인 세션 토큰 (여러 App 서버 간 공유)
- **캐싱**: 자주 조회되는 DB 결과 (상품 목록, 사용자 정보 등)
- **Rate Limiting**: API 호출 횟수 제한
- **Pub/Sub**: 실시간 메시지 브로드캐스팅

### Redis vs Memcached 선택 기준

| 기능 | Redis | Memcached |
|------|-------|-----------|
| 데이터 구조 | String, Hash, List, Set, SortedSet 등 다양 | String만 |
| 영속성(Persistence) | AOF, RDB 스냅샷 지원 | ❌ |
| Replication/HA | ✅ | ❌ |
| Pub/Sub | ✅ | ❌ |
| 멀티스레드 | 6.0부터 I/O 멀티스레드 | ✅ 네이티브 멀티스레드 |

→ **대부분의 신규 프로젝트에서 Redis 선택** (기능이 압도적으로 풍부)

### Replication Group 구조

ElastiCache Redis의 핵심 리소스는 `aws_elasticache_replication_group`이다.

```
클러스터 모드 비활성화 (이 프로젝트):
  ┌─────────────────────────────────┐
  │      Replication Group          │
  │  ┌──────────┐  ┌─────────────┐  │
  │  │ Primary  │→ │  Replica    │  │
  │  │ (쓰기+읽기)│  │ (읽기 전용) │  │
  │  └──────────┘  └─────────────┘  │
  │      AZ-a            AZ-b       │
  └─────────────────────────────────┘
  - 단일 샤드, Primary 1 + Replica N
  - Primary 엔드포인트 + Reader 엔드포인트 제공
  - Primary 장애 시 Replica가 자동으로 Primary 승격 (automatic_failover)

클러스터 모드 활성화:
  - 여러 샤드(shard)로 데이터 분산
  - 대용량 데이터(500GB+)에 적합
  - 앱에서 Redis Cluster 프로토콜 지원 필요
```

### automatic_failover 동작 방식

```
정상 상태:
  Primary(AZ-a) ──replication──> Replica(AZ-b)
  App → Primary 엔드포인트 → Primary

Primary 장애:
  1. ElastiCache가 Primary 응답 없음 감지
  2. Replica를 새 Primary로 자동 승격
  3. 엔드포인트가 새 Primary를 가리킴
  4. 기존 Primary가 복구되면 Replica로 재합류
  → 보통 30~60초 이내 완료
```

### 암호화 설정

| 설정 | 의미 |
|------|------|
| `at_rest_encryption_enabled = true` | 저장 데이터 AES-256 암호화 (디스크 레벨) |
| `transit_encryption_enabled = true` | 전송 중 TLS 암호화 |

`transit_encryption_enabled = true`이면 App 코드에서 반드시 `rediss://` (TLS) 프로토콜 사용:
```
# 잘못된 연결 (비암호화)
redis://my-redis.xxxxx.cache.amazonaws.com:6379

# 올바른 연결 (TLS)
rediss://my-redis.xxxxx.cache.amazonaws.com:6379
```

### maxmemory-policy 선택 가이드

| 정책 | 설명 | 적합한 사용 사례 |
|------|------|-----------------|
| `allkeys-lru` | 모든 키 중 LRU 삭제 | 세션 캐시, 범용 캐시 |
| `volatile-lru` | TTL 있는 키만 LRU 삭제 | 영속 데이터 + 캐시 혼용 |
| `allkeys-lfu` | 모든 키 중 LFU 삭제 | 접근 빈도 기반 캐시 |
| `noeviction` | 꽉 차면 에러 반환 | 데이터 손실 허용 불가 |

### 3-Tier 아키텍처에서의 위치

```
App EC2 (ASG) → Redis (Private DB Subnet)
              → RDS Aurora (Private DB Subnet)
```

- **위치**: Private DB Subnet (RDS와 같은 서브넷)
- **포트**: 6379
- **접근 제어**: cache_sg → app_sg에서만 6379 인바운드 허용

---

## 2. 실무 주의사항

### ⚠️ num_cache_clusters와 automatic_failover 조건

```hcl
# 잘못된 설정
num_cache_clusters         = 1
automatic_failover_enabled = true  # ❌ num_cache_clusters=1이면 설정 불가, 에러 발생

# 올바른 설정
num_cache_clusters         = 2     # Primary + Replica
automatic_failover_enabled = true  # ✅ 2개 이상이어야 활성화 가능
```

### ⚠️ 스냅샷 윈도우와 유지보수 윈도우 겹침 방지

RDS와 동일하게, 두 윈도우가 겹치면 에러가 발생한다.

### ⚠️ cache.t3.micro는 dev 전용

`cache.t3.micro`(0.5GB)는 prod에서 너무 작아 OOM(Out of Memory)이 발생할 수 있다.
prod 최소 사양: `cache.r6g.large` (13GB, 메모리 최적화 인스턴스)

### ⚠️ 클러스터 모드 변경 불가

클러스터 모드(비활성화 ↔ 활성화)는 생성 후 변경이 불가하다.
변경하려면 새 Replication Group을 생성하고 마이그레이션해야 한다.

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
security (app_sg_id)
    ↓
database (cache_sg 생성 → Replication Group)
    ↓
monitoring (Phase 6 — CacheHits, CacheMisses 알람)
```

---

## 5. 참고 자료

- AWS 공식 문서: [ElastiCache for Redis](https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/WhatIs.html)
- 검색 키워드: `ElastiCache Redis vs Memcached`, `Redis maxmemory-policy`, `ElastiCache cluster mode`
