# SQS (Simple Queue Service)

> 마지막 업데이트: 2026-03-08
> Phase: 프로젝트 외 참고 (메시지 큐 개념 이해)

---

## 1. 개념 설명

### SQS란

**완전 관리형 메시지 큐 서비스**다. Producer가 메시지를 큐에 넣으면, Consumer가 꺼낼 때까지 보관한다.

```
Producer → [Queue] → Consumer가 꺼냄 → 처리 완료 후 삭제
```

SNS와의 핵심 차이: 메시지를 **저장**한다. Consumer가 준비되지 않아도 메시지가 사라지지 않는다.

---

### SNS vs SQS 비교

| 항목 | SNS | SQS |
|------|-----|-----|
| 모델 | Pub/Sub (발행-구독) | Queue (대기열) |
| 방향 | 1 → N (동시 전달) | 1 → 1 (순서대로 처리) |
| 메시지 저장 | 없음 (전달 후 소멸) | 있음 (최대 14일) |
| Consumer 수 | 여러 구독자 동시 수신 | 여러 Consumer가 **나눠서** 처리 |
| 주 목적 | 알림, 이벤트 전파 | 작업 대기열, 비동기 처리 |
| 재처리 | 불가 | DLQ로 실패 메시지 보존 가능 |

#### 직관적 비유

| 서비스 | 비유 |
|--------|------|
| SNS | 단체 카톡 — 보내는 순간 모두에게 전달, 이후 삭제 |
| SQS | 창구 대기줄 — 직원이 한 명씩 호출해서 처리 |

---

### DLQ (Dead Letter Queue)

처리에 실패한 메시지를 별도 큐로 이동시키는 장치다.

```
[원본 Queue] → Consumer 처리 실패 (n회) → [DLQ]
                                              ↑
                                        나중에 재처리 or 분석
```

- `maxReceiveCount`: 몇 번 실패하면 DLQ로 이동할지 설정
- 메시지 유실 없이 실패 원인을 분석할 수 있다

---

### Queue 타입

| 타입 | 특징 |
|------|------|
| **Standard Queue** | 최소 1회 전달 보장, 순서 미보장, 처리량 무제한 |
| **FIFO Queue** | 정확히 1회 전달, 순서 보장, 초당 300 TPS 제한 |

---

### 실무 사용 패턴

**SQS만 사용**
- 이미지 업로드 후 리사이징 작업 큐
- 이메일 발송 작업 비동기 처리
- 처리 속도가 다른 두 시스템 사이 버퍼

**SNS + SQS (Fan-out 패턴)**
- 주문 완료 이벤트 → SNS → 여러 SQS 큐로 분산
- 각 서비스(재고, 배송, 알림)가 독립적으로 처리

**Kinesis vs SQS 선택 기준**
- 개별 작업 처리, 재시도 필요 → **SQS**
- 대용량 스트림, 순서 중요, 재처리 필요 → **Kinesis**

→ Kinesis와의 차이는 [kinesis.md](./kinesis.md) 참고

---

## 2. 이 프로젝트에서의 위치

현재 프로젝트에서는 SQS를 직접 사용하지 않는다.
SNS는 Phase 6 모니터링 알림 용도로만 사용 (이메일 구독).

SNS Fan-out이 필요한 경우 SQS를 추가 구독자로 연결할 수 있다.

---

## 3. 직접 해볼 것

- 콘솔에서 Standard Queue 생성 → 메시지 전송 → 폴링으로 수신 확인
- DLQ 연결 후 의도적으로 처리 실패 → DLQ에서 메시지 확인

**공식 문서**: [Amazon SQS](https://docs.aws.amazon.com/sqs/latest/dg/welcome.html)
**검색 키워드**: `aws_sqs_queue terraform`, `SQS DLQ`, `SNS SQS fan-out pattern`
