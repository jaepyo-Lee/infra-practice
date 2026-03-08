# CloudWatch

> 마지막 업데이트: 2026-03-08 (Phase 6 구현 반영)
> Phase: Phase 6 — Observability

---

## 1. 개념 설명

### CloudWatch란

AWS 인프라와 애플리케이션의 **모니터링 + 관찰성(Observability) 플랫폼**이다. 크게 세 가지 기능으로 구성된다:

```
CloudWatch
  ├── Metrics    — 수치 데이터 (CPU 사용률, 요청 수, 응답시간 등)
  ├── Logs       — 텍스트 로그 (App 로그, Access 로그, VPC Flow 로그 등)
  └── Alarms     — Metric 임계값 초과 시 알림 또는 자동 조치
```

---

### Metrics — 수치 데이터

AWS 서비스들은 자동으로 Metric을 CloudWatch에 보낸다. EC2, ALB, RDS 등 대부분의 서비스가 기본 Metric을 무료로 제공한다.

```
Namespace / Metric 구조:

AWS/EC2
  └── CPUUtilization       (인스턴스별)
  └── NetworkIn/Out

AWS/ApplicationELB
  └── RequestCount
  └── TargetResponseTime
  └── HTTPCode_Target_5XX_Count

AWS/RDS
  └── DatabaseConnections
  └── FreeStorageSpace
  └── ReadLatency
```

**기본 Metric vs 상세 Metric:**
- 기본: 5분 간격 수집 (무료)
- 상세(Detailed Monitoring): 1분 간격 (EC2는 추가 요금)

**커스텀 Metric**: 앱에서 직접 보내는 데이터. CloudWatch Agent 또는 SDK로 메모리 사용률, JVM heap 등을 보낼 수 있다.

> **주의**: 기본 EC2 Metric에는 **메모리 사용률이 없다**. EC2 내부 데이터는 OS가 수집해서 직접 보내야 하므로 CloudWatch Agent 설치가 필요하다.

---

### Logs — 로그 수집

```
로그 구조:

Log Group (논리적 묶음)
  └── Log Stream (단일 소스의 로그 흐름)
        └── Log Event (개별 로그 라인)

예:
/aws/ec2/app-server          ← Log Group
  └── i-0abc123/app.log     ← Log Stream (인스턴스별)
        └── 2026-03-08 ...  ← Log Event
```

**로그 보존 기간**: 기본 무제한 → 비용이 계속 쌓인다. `retention_in_days`를 반드시 설정해야 한다.

**CloudWatch Logs Insights**: Log Group에 SQL-like 쿼리로 로그를 분석한다.

```
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 20
```

---

### Alarms — 임계값 알림

Metric이 특정 조건을 충족하면 동작하는 규칙이다.

```
Alarm 상태 3가지:
  OK                  — 정상
  ALARM               — 임계값 초과
  INSUFFICIENT_DATA   — 데이터 없음 (모니터링 시작 직후 등)
```

Alarm이 ALARM 상태가 되면 할 수 있는 것:
- **SNS 알림** → 이메일, Slack, PagerDuty 등
- **ASG 스케일링** → CPU 높으면 인스턴스 추가
- **EC2 재시작** → 인스턴스 헬스 체크 실패 시

---

### 실무에서 자주 모니터링하는 Metric

| 리소스 | Metric | 임계값 예시 |
|--------|--------|-------------|
| EC2 | CPUUtilization | > 80% |
| ALB | HTTPCode_Target_5XX_Count | > 10/분 |
| ALB | TargetResponseTime | > 1초 |
| RDS | DatabaseConnections | > 최대 연결수의 80% |
| RDS | FreeStorageSpace | < 10GB |

---

### ⚠️ Logs ≠ Metrics (자주 혼동하는 오개념)

```
CloudWatch Log Group 생성 = 로그(텍스트)를 볼 수 있음
                          ≠ 메트릭(숫자 지표)을 볼 수 있음
```

| 구분 | 대상 | 보는 방법 |
|------|------|---------|
| Metrics | CPU %, 연결 수, 응답시간 등 숫자 | CloudWatch → Metrics (자동 수집, 별도 설정 불필요) |
| Logs | 에러 메시지, 슬로우 쿼리 텍스트 | CloudWatch → Log Groups (Log Group 필요) |
| Alarms | 메트릭 임계값 초과 시 알림 | aws_cloudwatch_metric_alarm 리소스 별도 생성 |

**RDS 메트릭(CPU, 연결 수 등)은 Log Group 없이도 콘솔에서 확인 가능**하다. Log Group은 로그 텍스트 내용을 보기 위한 것이다.

### enabled_cloudwatch_logs_exports 자동 생성 동작

```hcl
enabled_cloudwatch_logs_exports = ["audit", "error", "slowquery"]
```

이 설정 시 AWS가 Log Group을 **자동 생성**한다:
```
/aws/rds/cluster/{cluster-name}/audit
/aws/rds/cluster/{cluster-name}/error
/aws/rds/cluster/{cluster-name}/slowquery
```

**문제**: 자동 생성된 Log Group은 **retention_in_days가 무제한**이다 → 비용 무한 증가 위험

**해결**: Terraform에서 같은 이름으로 `aws_cloudwatch_log_group`을 명시적으로 생성하면 retention을 제어할 수 있다.

```hcl
# 자동 생성되는 경로와 이름을 정확히 맞춰야 함
# 이름이 다르면 AWS가 새 그룹을 또 자동 생성해버림
resource "aws_cloudwatch_log_group" "rds_slowquery" {
  name              = "/aws/rds/cluster/${var.cluster_id}/slowquery"
  retention_in_days = 30
}
```

---

### 실무에서 자주 하는 실수

1. **`retention_in_days` 미설정** → 기본 무제한, 로그 비용 무한 증가
2. **`evaluation_periods = 1`** → 일시적 스파이크에도 즉시 ALARM 발동. 2~3으로 설정해 연속 초과 시에만 발동하도록 해야 함
3. **메모리 Metric 없음** → EC2 기본 Metric에는 메모리가 없다. CloudWatch Agent 설치 필요
4. **Alarm이 INSUFFICIENT_DATA 상태로 방치** → 모니터링이 동작하지 않는 것과 같다. 초기 설정 후 반드시 상태 확인

---

## 2. Terraform 핵심 파라미터

### `aws_cloudwatch_metric_alarm`

```hcl
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "dev-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_actions       = [aws_sns_topic.alert.arn]
  ok_actions          = [aws_sns_topic.alert.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
}
```

| 인수 | 필수 | 설명 |
|------|------|------|
| `alarm_name` | ✅ | 알람 이름 |
| `comparison_operator` | ✅ | `GreaterThanThreshold`, `LessThanThreshold` 등 |
| `evaluation_periods` | ✅ | 연속 N번 조건 충족 시 ALARM |
| `metric_name` | ✅ | 모니터링할 Metric 이름 |
| `namespace` | ✅ | `AWS/EC2`, `AWS/ApplicationELB` 등 |
| `period` | ✅ | 측정 주기(초). 최소 60 |
| `statistic` | ✅ | `Average`, `Sum`, `Maximum`, `Minimum`, `SampleCount` |
| `threshold` | ✅ | 임계값 |
| `alarm_actions` | 선택 | ALARM 진입 시 실행할 ARN 목록 (SNS, ASG Policy 등) |
| `ok_actions` | 선택 | OK 복귀 시 실행할 ARN 목록 |
| `dimensions` | 선택 | 특정 인스턴스/ALB/ASG 등 필터 |

### `aws_cloudwatch_log_group`

```hcl
resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/ec2/app-server"
  retention_in_days = 30  # 반드시 설정
}
```

| 인수 | 필수 | 설명 |
|------|------|------|
| `name` | ✅ | Log Group 이름. `/aws/` 접두사가 관례 |
| `retention_in_days` | 선택 | 보존 기간(일). **기본 무제한** → 반드시 명시 |
| `kms_key_id` | 선택 | 로그 암호화 KMS 키 |

---

## 3. 이 프로젝트에서의 위치

```
Phase 6 — Observability (envs/dev/6-monitoring/)
  ├── CloudWatch Metrics  — EC2, ALB, RDS 기본 Metric 자동 수집
  ├── CloudWatch Alarms   — CPU, 에러율, 응답시간 임계값
  ├── CloudWatch Logs     — App 로그, VPC Flow 로그
  └── CloudWatch Insights — 로그 쿼리 분석
```

**선행 리소스**: SNS Topic (Alarm이 알림을 보낼 대상)
**후행 리소스**: 없음 (최종 관찰 레이어)

---

## 4. 직접 해볼 것

Phase 6에서:
- ALB `HTTPCode_Target_5XX_Count` Alarm → SNS 이메일 알림 연결
- Log Group `retention_in_days = 30` 설정 후 콘솔에서 확인

**공식 문서**: [CloudWatch Metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/working_with_metrics.html)
**검색 키워드**: `aws_cloudwatch_metric_alarm terraform`, `CloudWatch namespace list`, `CloudWatch Logs Insights query`

---

## 5. CloudWatch 서비스(자동) vs Dashboard(수동 구성) 구분

CloudWatch 서비스 자체와 `aws_cloudwatch_dashboard` 리소스는 다른 것이다.

| 구분 | 주체 | 설명 |
|------|------|------|
| CloudWatch 메트릭 수집 | AWS 자동 | 별도 설정 없이 EC2, ALB, RDS 등 메트릭이 자동으로 쌓임 |
| CloudWatch 로그 수집 | 서비스 설정 필요 | RDS `enabled_cloudwatch_logs_exports`, CloudWatch Agent 등 |
| `aws_cloudwatch_dashboard` | 직접 생성 | 수집된 메트릭을 어떻게 시각화할지 레이아웃 정의 |

```
메트릭은 자동으로 쌓인다
    ↓
대시보드 = "그 메트릭들을 어떤 그래프로, 어떤 레이아웃으로 볼지" 를 정의하는 것
대시보드 없어도 메트릭은 존재한다 — 단지 한눈에 볼 수 없을 뿐
```

`aws_cloudwatch_dashboard`는 CloudWatch 기능을 켜는 게 아니라 **커스텀 뷰를 만드는 것**이다.

---

## 6. CloudWatch Dashboard

여러 메트릭을 한 화면에서 시각화하는 대시보드다.

### 구조

```
aws_cloudwatch_dashboard
  └── dashboard_body (JSON)
        └── widgets []
              ├── type: "metric" | "log" | "text"
              ├── x, y, width, height  ← 24컬럼 그리드 위치
              └── properties
                    ├── metrics []     ← [namespace, metric_name, dimension_key, dimension_value]
                    ├── region
                    ├── period
                    └── stat
```

### Terraform 예시

```hcl
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "dev-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB 5xx 에러"
          region = "ap-northeast-2"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count",
             "LoadBalancer", "app/dev-alb/abc123",
             { stat = "Sum", label = "5xx 에러" }]
          ]
          view   = "timeSeries"
          period = 60
        }
      }
    ]
  })
}
```

### ALB ARN suffix 추출 패턴

CloudWatch Dimension에는 전체 ARN이 아닌 suffix만 필요하다.

```hcl
# 전체 ARN을 받아서 suffix를 추출하는 패턴
locals {
  # ALB ARN: arn:aws:...:loadbalancer/app/dev-alb/abc123
  # suffix:  app/dev-alb/abc123
  alb_arn_suffix = regex("loadbalancer/(.*)", var.alb_arn)[0]

  # TG ARN: arn:aws:...:targetgroup/dev-tg/abc123
  # suffix: targetgroup/dev-tg/abc123
  tg_arn_suffix = regex(":(targetgroup/.*)", var.target_group_arn)[0]
}
```

이렇게 하면 `aws_lb.arn_suffix`를 별도 output으로 전달하지 않아도 된다.

### treat_missing_data 옵션

```
notBreaching  — 데이터 없으면 정상으로 간주 (새벽 트래픽 없는 시간대 오탐 방지)
breaching     — 데이터 없으면 알람으로 간주 (엄격한 모니터링)
ignore        — 데이터 없으면 현재 상태 유지
missing       — 기본값. 데이터 없으면 INSUFFICIENT_DATA
```

실무에서는 `notBreaching`을 가장 많이 쓴다.
