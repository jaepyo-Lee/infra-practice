# Kinesis

> 마지막 업데이트: 2026-03-08
> Phase: 프로젝트 외 참고 (스트리밍 데이터 개념 이해)

---

## 1. 개념 설명

### Kinesis란

**대용량 실시간 스트리밍 데이터 처리 서비스**다. 수백만 건의 이벤트를 실시간으로 수집하고, 여러 Consumer가 각자 독립적으로 읽을 수 있다.

```
Producer → [Kinesis Stream] → Consumer A (처음부터 읽음)
                            → Consumer B (다른 위치에서 읽음)
```

SQS와의 핵심 차이: 메시지를 꺼내도 **삭제되지 않는다**. 각 Consumer가 자신의 위치(offset)를 독립적으로 관리한다.

---

### SNS / SQS / Kinesis 비교

| 항목 | SNS | SQS | Kinesis |
|------|-----|-----|---------|
| 주 목적 | 알림/이벤트 전파 | 작업 큐 | 대용량 스트리밍 |
| 순서 보장 | X | FIFO 옵션 | **샤드 내 보장** |
| 데이터 보존 | 없음 | 최대 14일 | 최대 7일 |
| 재처리 | 불가 | 불가 | **가능** (커서 이동) |
| 처리량 | 제한 없음 | 높음 | **매우 높음** (GB/s) |
| 주 사용처 | 알림, 트리거 | 비동기 작업 | 로그, 클릭스트림, IoT |

#### 직관적 비유

| 서비스 | 비유 |
|--------|------|
| SNS | 단체 카톡 — 보내는 순간 모두에게 전달 |
| SQS | 창구 대기줄 — 직원이 하나씩 처리 |
| Kinesis | Netflix — 언제든 되감기 가능한 스트림 |

---

### 핵심 개념: Shard

Kinesis Stream은 **Shard** 단위로 파티셔닝된다.

```
Stream (Shard 3개)
├── Shard 1: [r1][r2][r3]...
├── Shard 2: [r4][r5][r6]...
└── Shard 3: [r7][r8][r9]...
```

- 각 Shard는 초당 1MB 쓰기, 2MB 읽기 처리 가능
- Partition Key로 어느 Shard에 들어갈지 결정
- **순서는 샤드 내에서만 보장**된다 (샤드 간 순서 미보장)

---

### Consumer 중복 처리 문제

Kinesis는 각 Consumer가 **어디까지 읽었는지(Shard Iterator)를 직접 관리**해야 한다.

**문제: ECS Task 여러 개가 같은 샤드를 읽으면?**

```
ECS Task 1 → Shard 읽기 시작 (record1부터)
ECS Task 2 → Shard 읽기 시작 (record1부터)  ← 중복 수신!
```

기본적으로 **중복 수신이 발생**한다.

---

### 중복 방지 방법

**방법 1: KCL (Kinesis Client Library) — 권장**

KCL이 DynamoDB에 각 Consumer의 체크포인트(어디까지 읽었는지)를 저장하고, 샤드를 Consumer들에게 자동으로 분배한다.

```
Stream (Shard 3개)
    ↓ KCL (DynamoDB에 체크포인트 저장)
ECS Task 1 → Shard 1 전담
ECS Task 2 → Shard 2 전담
ECS Task 3 → Shard 3 전담
```

- 같은 `applicationName`을 쓰는 Consumer끼리 샤드를 나눠서 처리
- Task가 재시작되어도 마지막 체크포인트부터 재개

**방법 2: Enhanced Fan-Out**

Consumer를 **명시적으로 등록** (RegisterStreamConsumer API)하여, 각 Consumer가 독립적인 스트림을 받는다.

- 같은 데이터를 **의도적으로** 여러 Consumer가 각자 전부 수신하고 싶을 때 사용
- 예: 분석팀과 ML팀이 동일한 클릭 스트림을 각자 독립적으로 처리

---

### Consumer 상황별 결과 요약

| 상황 | 결과 |
|------|------|
| ECS Task 여러 개, KCL 없이 같은 샤드 읽기 | **중복 수신 발생** |
| ECS Task 여러 개, KCL 사용 | 샤드 분배, 중복 없음 |
| Enhanced Fan-Out으로 다른 Consumer 등록 | **의도적 중복** (각자 전체 수신) |

KCL 없이 Kinesis를 쓰면 반드시 **애플리케이션 레벨에서 멱등성(idempotency) 구현**이 필요하다.

---

### Kinesis 서비스 종류

| 서비스 | 용도 |
|--------|------|
| **Kinesis Data Streams** | 직접 스트림 처리 (위에서 설명한 것) |
| **Kinesis Data Firehose** | 스트림 → S3/Redshift/ES로 자동 적재 (서버리스) |
| **Kinesis Data Analytics** | SQL/Flink로 스트림 실시간 분석 |

---

### 선택 기준

- 개별 작업 처리, 재시도 필요 → **SQS**
- 알림, 이벤트 전파 → **SNS**
- 대용량 로그/이벤트 스트림, 재처리 필요, 여러 Consumer → **Kinesis**

---

## 2. 이 프로젝트에서의 위치

현재 프로젝트에서는 Kinesis를 사용하지 않는다.
대용량 로그 수집이 필요해지면 CloudWatch Logs 대신 Kinesis Data Firehose → S3 패턴을 고려할 수 있다.

---

## 3. 직접 해볼 것

- 콘솔에서 Kinesis Data Stream 생성 → CLI로 레코드 전송 → GetRecords로 읽기
- KCL 기반 Consumer에서 DynamoDB에 체크포인트 저장되는 것 확인

**공식 문서**: [Amazon Kinesis Data Streams](https://docs.aws.amazon.com/streams/latest/dev/introduction.html)
**검색 키워드**: `Kinesis vs SQS`, `KCL checkpoint DynamoDB`, `Kinesis Enhanced Fan-Out`, `Kinesis shard iterator`
