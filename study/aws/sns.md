# SNS (Simple Notification Service)

> 마지막 업데이트: 2026-03-08
> Phase: Phase 6 — Observability

---

## 1. 개념 설명

### SNS란

**발행-구독(Pub/Sub) 방식의 메시지 버스**다. 발행자(Publisher)가 토픽에 메시지를 보내면, 토픽을 구독(Subscribe)한 모든 수신자에게 동시에 전달된다.

```
CloudWatch Alarm ──┐
Lambda Function ───┼──→ SNS Topic ──→ 이메일
API Gateway ───────┘              ├──→ Slack (Lambda)
                                  ├──→ SQS Queue
                                  └──→ HTTP Webhook
```

이 프로젝트에서는 **CloudWatch Alarm → SNS → 이메일** 흐름으로 사용하지만, SNS는 이메일 전송 전용 서비스가 아니다.

---

### SNS 구독 프로토콜 (전체)

| 프로토콜 | 사용 예 |
|---------|--------|
| **Email** | 알림 메일 발송 |
| **SQS** | 큐에 메시지 전달 — 실무에서 가장 많이 씀 |
| **Lambda** | 이벤트 트리거로 함수 실행 |
| **HTTP/HTTPS** | 웹훅으로 외부 서버에 전달 |
| **SMS** | 문자 메시지 발송 |
| **Mobile Push** | iOS/Android 푸시 알림 |

---

### Fan-out 패턴 (SNS + SQS)

하나의 이벤트를 여러 시스템에 동시에 전달할 때 사용한다.

```
주문 완료 이벤트 → SNS Topic
                   ├── SQS A → 재고 서비스가 꺼내서 처리
                   ├── SQS B → 배송 서비스가 꺼내서 처리
                   └── Lambda → 이메일 발송
```

각 Consumer(SQS)가 독립적인 속도로 처리할 수 있고, 하나가 실패해도 다른 큐에 영향 없다.

→ SQS와의 차이는 [sqs.md](./sqs.md) 참고

---

### 왜 SNS가 필요한가?

CloudWatch Alarm이 직접 이메일을 보내지 않는다. Alarm은 "어딘가에 알려야 해"라는 이벤트를 발생시키고, 그 대상이 SNS Topic이다.

SNS를 중간에 두는 이유:
- **1:N 알림**: 하나의 알람이 이메일 + Slack + SQS 등 여러 곳에 동시 전송 가능
- **유연한 변경**: 알람 코드를 바꾸지 않고 구독자만 추가/제거 가능
- **프로토콜 추상화**: HTTP, Lambda, SQS, SMS, 이메일 등 다양한 수신 방식 지원

---

### 구독 확인 (Subscription Confirmation)

이메일 구독 생성 시 AWS가 확인 이메일을 보낸다.

```
⚠️ terraform apply 후 반드시 해야 할 일:
1. 등록한 이메일로 확인 메일 수신
2. "Confirm subscription" 링크 클릭
3. 클릭 전까지는 알림이 전달되지 않음
```

---

### 실무에서 자주 하는 실수

1. **구독 확인 미클릭** → 알람이 울려도 이메일 미수신
2. **SNS Topic을 환경별로 분리 안 함** → dev 알람이 prod 팀에게 발송
3. **이메일만 구독** → 담당자 부재 시 알림 유실. PagerDuty/Opsgenie 연동 권장

---

## 2. Terraform 핵심 파라미터

### `aws_sns_topic`

```hcl
resource "aws_sns_topic" "alarms" {
  name = "dev-alarm-topic"
  # FIFO 토픽이 필요하면 name이 .fifo로 끝나야 함
}
```

| 인수 | 필수 | 설명 |
|------|------|------|
| `name` | ✅ | 토픽 이름 |
| `kms_master_key_id` | 선택 | 메시지 암호화 KMS 키 |
| `fifo_topic` | 선택 | 순서 보장 FIFO 토픽 여부 |

### `aws_sns_topic_subscription`

```hcl
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = "alert@example.com"
}
```

| 인수 | 필수 | 설명 |
|------|------|------|
| `topic_arn` | ✅ | 구독할 SNS 토픽 ARN |
| `protocol` | ✅ | `email`, `lambda`, `sqs`, `http`, `https`, `sms` |
| `endpoint` | ✅ | 수신 대상. 이메일 주소, Lambda ARN, SQS ARN 등 |

---

## 3. 이 프로젝트에서의 위치

```
Phase 6 — monitoring 레이어
  aws_sns_topic.alarms          ← 알림 허브
  aws_sns_topic_subscription    ← 이메일 구독
    ↑
  aws_cloudwatch_metric_alarm   ← alarm_actions = [sns_topic.arn]
```

**선행 리소스**: 없음 (독립 리소스)
**후행 리소스**: CloudWatch Alarm (alarm_actions에서 이 ARN을 참조)

---

## 4. 직접 해볼 것

- apply 후 이메일 확인 → "Confirm subscription" 클릭
- 콘솔: SNS → Topics → dev-alarm-topic → Subscriptions에서 상태 확인
- `Pending confirmation` → 클릭 후 `Confirmed`로 변경되는지 확인

**공식 문서**: [Amazon SNS](https://docs.aws.amazon.com/sns/latest/dg/welcome.html)
**검색 키워드**: `aws_sns_topic terraform`, `aws_sns_topic_subscription protocol`
