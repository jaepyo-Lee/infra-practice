# 네임스페이스 (Namespace)

> 마지막 업데이트: 2026-03-08

---

## 1. 개념

**"이름 충돌을 막기 위한 논리적 그룹 공간"**

같은 이름이라도 네임스페이스가 다르면 완전히 다른 대상이다. AWS에서는 두 가지 맥락에서 나온다.

---

## 2. CloudWatch 네임스페이스

### 문제

```
EC2도 CPUUtilization 메트릭이 있다
RDS도  CPUUtilization 메트릭이 있다
→ 어떻게 구분하지?
```

### 해결: Namespace가 소속을 구분한다

```
AWS/EC2             → CPUUtilization  (EC2 CPU)
AWS/RDS             → CPUUtilization  (RDS CPU)
AWS/ElastiCache     → CPUUtilization  (Redis CPU)
```

### 메트릭 조회 구조

```
Namespace
  └── Metric Name
        └── Dimension (세부 필터)

예:
AWS/ApplicationELB
  └── HTTPCode_Target_5XX_Count
        └── LoadBalancer = "app/dev-alb/abc123"  ← 특정 ALB로 좁힘
```

### 주요 AWS 네임스페이스 목록

| 네임스페이스 | 대상 서비스 |
|-------------|-----------|
| `AWS/EC2` | EC2 인스턴스 |
| `AWS/ApplicationELB` | ALB |
| `AWS/RDS` | RDS / Aurora |
| `AWS/ElastiCache` | ElastiCache |
| `AWS/ECS` | ECS 클러스터/서비스 |
| `AWS/Lambda` | Lambda 함수 |
| `CWAgent` | CloudWatch Agent 커스텀 메트릭 |

### 커스텀 네임스페이스

앱에서 직접 메트릭을 보낼 때 네임스페이스를 직접 정한다:

```python
cloudwatch.put_metric_data(
    Namespace='MyApp/Orders',   # AWS/ 접두사는 예약어 — 사용 금지
    MetricName='ProcessedCount',
    Value=42
)
```

---

## 3. ECS 네임스페이스 (Cloud Map Service Discovery)

### 문제

```
ECS 컨테이너는:
  - 배포마다 IP가 바뀜
  - 스케일 아웃 시 여러 개가 됨
  - 내려가면 다른 IP로 새로 뜸

→ 앱 컨테이너가 DB 컨테이너의 IP를 어떻게 알지?
```

### 해결: Cloud Map 네임스페이스 = 내부 DNS 도메인

```
네임스페이스: dev.local  ← DNS 도메인처럼 작동
  ├── 서비스: api      → api.dev.local
  ├── 서비스: backend  → backend.dev.local
  └── 서비스: redis    → redis.dev.local
```

컨테이너가 뜨면 자신의 IP를 `backend.dev.local`로 자동 등록한다. 앱 컨테이너는 IP 대신 DNS 이름으로 접속한다.

### 동작 흐름

```
1. ECS가 backend 컨테이너를 172.31.10.5에 시작
2. Cloud Map에 자동 등록: backend.dev.local → 172.31.10.5
3. app이 backend.dev.local로 요청
4. Route53 Resolver → 172.31.10.5 반환

5. backend 컨테이너 장애 → 새 컨테이너 172.31.10.8에 시작
6. Cloud Map 자동 갱신: backend.dev.local → 172.31.10.8
7. app은 여전히 backend.dev.local로 접속 (IP 몰라도 됨)
```

### 네임스페이스 종류

| 타입 | 범위 | 용도 |
|------|------|------|
| `private` | VPC 내부에서만 조회 가능 | 컨테이너 간 내부 통신 |
| `public` | 인터넷에서도 조회 가능 | 외부 노출 (드물게 사용) |

실무에서는 거의 항상 `private`를 사용한다.

---

## 4. 두 맥락 비교

| | CloudWatch 네임스페이스 | Cloud Map 네임스페이스 |
|---|---|---|
| 역할 | 메트릭의 소속 구분 | 서비스의 DNS 도메인 |
| 예시 | `AWS/EC2` | `dev.local` |
| 목적 | 같은 이름 메트릭 구분 | 동적 IP 추적 |
| 공통점 | 이름 충돌 방지 + 논리적 그룹화 |

---

## 5. 참고

- CloudWatch 네임스페이스 → [cloudwatch.md](./cloudwatch.md)
- ECS Service Discovery → [ecs.md](./ecs.md)
- **검색 키워드**: `CloudWatch namespace list`, `AWS Cloud Map service discovery`, `ECS service discovery namespace`
