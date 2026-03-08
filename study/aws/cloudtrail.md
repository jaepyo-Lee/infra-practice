# CloudTrail

> 마지막 업데이트: 2026-03-08
> Phase: Phase 6 — Observability

---

## 1. 개념 설명

### CloudTrail이란

AWS 계정에서 발생한 **모든 API 호출을 기록하는 감사 로그 서비스**다.

```
"누가(Who) / 언제(When) / 어디서(Where) / 무엇을(What) 했는가"

예시:
- jaepyo IAM 유저가
- 2026-03-08 14:22:03 UTC에
- ap-northeast-2 리전에서
- ec2:TerminateInstances API를 호출했다
```

---

### CloudWatch Logs vs CloudTrail

| 구분 | CloudWatch Logs | CloudTrail |
|------|----------------|------------|
| 목적 | 애플리케이션/시스템 로그 | AWS API 호출 감사 |
| 기록 대상 | App 로그, RDS 로그, VPC Flow | IAM 변경, 리소스 생성/삭제 등 |
| 주 사용 | 장애 디버깅, 성능 분석 | 보안 감사, 규정 준수 |

---

### 왜 CloudTrail이 필요한가?

**사고 발생 시 "누가 했는지" 추적 불가능**이 가장 큰 위험이다.

```
시나리오:
- 운영 DB가 갑자기 삭제됨
- CloudTrail이 없으면 → 범인 불명, 원인 불명
- CloudTrail이 있으면 → "arn:aws:iam::123:user/dev-kim이 DeleteDBCluster 호출"
```

규정 준수(Compliance)에서도 필수다: SOC2, ISO27001, PCI-DSS는 API 감사 로그 보존을 요구한다.

---

### 핵심 개념

**Trail**: CloudTrail 설정 단위. 어떤 이벤트를 어디에 저장할지 정의한다.

```
Trail 설정 옵션:
  include_global_service_events  — IAM, STS, Route53 등 글로벌 서비스 포함
  is_multi_region_trail          — 모든 리전의 이벤트 수집 여부
  enable_log_file_validation     — 로그 파일 무결성 해시 생성
```

**log_file_validation**: 로그가 생성된 후 변조됐는지 확인하는 SHA-256 해시를 생성한다. 보안 감사(Forensics)에서 "이 로그가 진짜다"를 증명할 때 필수다.

---

### S3 버킷 정책이 필수인 이유

CloudTrail은 S3에 로그를 쓸 때 두 단계를 거친다:
1. `s3:GetBucketAcl` — 버킷 ACL 확인 (권한 체크)
2. `s3:PutObject` — 실제 로그 파일 저장

이 두 권한을 버킷 정책으로 명시적으로 허용해야 한다. 없으면 CloudTrail 생성 시 `InsufficientS3BucketPolicyException` 에러가 발생한다.

```hcl
# terraform에서는 depends_on으로 순서를 보장해야 함
resource "aws_cloudtrail" "main" {
  depends_on = [aws_s3_bucket_policy.cloudtrail]
  # S3 정책 없이 CloudTrail을 만들면 에러 발생
}
```

---

### 실무에서 자주 하는 실수

1. **is_multi_region_trail = false** → 다른 리전에서 일어난 IAM 변경이 누락됨
2. **force_destroy = true (prod)** → 감사 로그가 삭제될 수 있음. prod는 반드시 false
3. **S3 버킷 정책 없이 Trail 생성** → `depends_on` 누락으로 에러 발생
4. **로그 보존 기간 미설정** → S3 비용 무한 증가

---

## 2. Terraform 핵심 파라미터

### `aws_cloudtrail`

```hcl
resource "aws_cloudtrail" "main" {
  name           = "dev-cloudtrail"
  s3_bucket_name = aws_s3_bucket.cloudtrail.id
  depends_on     = [aws_s3_bucket_policy.cloudtrail]

  include_global_service_events = true  # IAM, STS 등 글로벌 이벤트 포함
  is_multi_region_trail         = false # dev는 단일 리전. prod는 true
  enable_log_file_validation    = true  # 로그 무결성 해시 생성
}
```

| 인수 | 필수 | 설명 |
|------|------|------|
| `name` | ✅ | Trail 이름 |
| `s3_bucket_name` | ✅ | 로그를 저장할 S3 버킷 이름 |
| `include_global_service_events` | 선택 | IAM, STS 등 글로벌 서비스 포함 여부. 기본 true |
| `is_multi_region_trail` | 선택 | 모든 리전 이벤트 수집. prod는 true 권장 |
| `enable_log_file_validation` | 선택 | 로그 무결성 검증 해시 생성. 보안 필수 |
| `cloud_watch_logs_group_arn` | 선택 | CloudWatch Logs로도 전송 시 설정 |

---

## 3. 이 프로젝트에서의 위치

```
Phase 6 — monitoring 레이어
  aws_s3_bucket.cloudtrail          ← 로그 저장소
  aws_s3_bucket_policy.cloudtrail   ← CloudTrail 쓰기 권한
  aws_cloudtrail.main               ← API 감사 활성화
```

**선행 리소스**: S3 버킷 + 버킷 정책 (depends_on 필수)
**후행 리소스**: 없음

---

## 4. 직접 해볼 것

- apply 후 AWS 콘솔 → CloudTrail → Event History에서 방금 apply한 Terraform API 호출 확인
- `terraform apply`가 어떤 AWS API를 호출하는지 직접 볼 수 있음
- S3 버킷에서 실제 로그 파일 위치: `AWSLogs/{account_id}/CloudTrail/{region}/{year}/{month}/{day}/`

**공식 문서**: [AWS CloudTrail](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-user-guide.html)
**검색 키워드**: `aws_cloudtrail terraform`, `CloudTrail S3 bucket policy required`
