# AWS Batch

> 마지막 업데이트: 2026-03-01

---

## 1. 개념 설명

### AWS Batch란?

배치(Batch) 작업 — 사람이 기다리지 않아도 되는 **대규모 비동기 작업**을 클라우드에서 실행하는 완전 관리형 서비스다.

```
일반 웹 요청:  사용자 요청 → 서버 처리 (ms~s) → 즉시 응답
배치 작업:     작업 제출 → Batch가 알아서 처리 (분~시간) → 완료 통보
```

### 왜 필요한가?

- **Lambda**: 최대 15분 제한 — 장시간 작업 불가
- **EC2 직접 관리**: 항상 켜두면 낭비, 끄면 작업 못 함
- **Batch**: 작업이 있을 때만 서버를 켜고, 끝나면 알아서 끈다. 서버 용량도 작업량에 맞게 자동 조정.

### 핵심 구성 요소 4가지

```
① Job Definition (작업 명세)
   "이 컨테이너 이미지로, vCPU 4개, 메모리 8GB 써서, 이 커맨드 실행해"
        ↓
② Job Queue (대기열)
   제출된 작업들이 실행 순서를 기다리는 곳
        ↓
③ Compute Environment (실행 환경)
   실제로 작업을 돌릴 EC2(또는 Fargate) 서버 풀. Batch가 자동 관리.
        ↓
④ Job (실제 작업 인스턴스)
   Job Definition을 기반으로 실제 실행되는 단위
```

### 내부 동작 방식

```
Job 제출
    ↓
Job Queue에 적재 (PENDING 상태)
    ↓
Scheduler가 우선순위/리소스 기준으로 스케줄링
    ↓
Compute Environment에서 EC2 자동 시작 (없으면 Auto Scaling으로 띄움)
    ↓
Docker 컨테이너로 작업 실행 (RUNNING)
    ↓
완료 → EC2 자동 종료 (SUCCEEDED / FAILED)
    ↓
SNS/CloudWatch로 결과 알림
```

**핵심**: 작업이 없으면 서버 0개 → 비용 0. 작업이 밀리면 서버 자동 증가.

### 실무 사용 사례

| 사용 사례 | 예시 |
|---------|------|
| 데이터 처리 | S3에 올라온 로그 파일 파싱/집계 |
| 미디어 처리 | 동영상 인코딩, 이미지 리사이즈 |
| ML/AI | 모델 학습, 배치 추론 |
| 금융 | 야간 정산, 리스크 계산 |
| ETL | RDS → S3 데이터 이관 |

### 관련 서비스 비교

| 서비스 | 적합한 경우 | 제한 |
|------|-----------|------|
| **AWS Batch** | 장시간, 대규모, 자원 집약적 배치 | 컨테이너 기반 필요 |
| Lambda | 짧고 간단한 이벤트 처리 | 15분, 10GB 메모리 제한 |
| ECS | 상시 실행 컨테이너 서비스 | 직접 관리 부담 |
| Step Functions | 여러 단계의 워크플로우 조율 | Batch와 함께 사용 가능 |

### 실무에서 자주 하는 실수

1. **Compute Environment를 UNMANAGED로 설정** → EC2 직접 관리 필요. 특별한 이유 없으면 MANAGED 사용
2. **Job Definition의 메모리/vCPU를 너무 작게 설정** → Out of Memory로 작업 실패
3. **Job 실패 시 재시도 전략 미설정** → 일시적 오류로 작업 전체 영구 실패
4. **timeout 미설정** → 무한 루프 등으로 비용 폭탄 위험
5. **Fargate vs EC2 선택 오류** → GPU 작업은 Fargate 불가, EC2 필요

---

## 2. Terraform 구현 참고

→ [핵심 블록 & 모듈 구조](../terraform/core-blocks.md)

주요 Terraform 리소스:
- `aws_batch_compute_environment` — 서버 풀 정의
- `aws_batch_job_queue` — 작업 대기열
- `aws_batch_job_definition` — 작업 명세 (컨테이너 이미지, 리소스)

---

## 3. 이 프로젝트에서의 위치

이 프로젝트(3-Tier 웹 아키텍처)에는 **포함되지 않는** 서비스다. AWS Batch는 상시 웹 트래픽 처리 구조가 아닌, 데이터 처리 파이프라인/배치 잡 실행 구조에서 쓰인다.

3-Tier 아키텍처에 Batch를 연결하는 패턴:

```
사용자 요청 → ALB → EC2(App) → SQS Queue 적재
                                    ↓
                              Batch Job이 SQS 메시지를 읽어 처리
```

---

## 4. 직접 해볼 것

AWS 콘솔에서 순서대로 만들어보기:
1. Compute Environment (MANAGED, Fargate)
2. Job Queue (priority: 1)
3. Job Definition (type: container, image: `amazonlinux`)
4. Job 제출 — 커맨드 `echo "Hello Batch"` 실행

**AWS 공식 문서**:
- [AWS Batch 시작하기](https://docs.aws.amazon.com/batch/latest/userguide/what-is-batch.html)
- 검색 키워드: `aws_batch_compute_environment terraform`, `aws batch fargate vs ec2`
