# Terraform CLI 명령어 & 옵션 레퍼런스

> 마지막 업데이트: 2026-03-08

---

## 기본 흐름

```
init → validate → fmt → plan → apply
                              ↓
                         state 확인/조작 필요 시 → state 명령어
```

---

## 공통 옵션 (대부분 명령어에서 사용)

| 옵션 | 의미 | 예시 상황 |
|------|------|-----------|
| `-var="key=val"` | 변수 직접 지정 | `plan -var="region=ap-northeast-2"` |
| `-var-file=파일` | 변수 파일 지정 | 환경별 `.tfvars` 파일 분리 운영 시 |
| `-target=리소스` | 특정 리소스만 대상 | 전체 말고 VPC 하나만 먼저 만들 때 |
| `-lock=false` | State 잠금 해제 | 이전 작업이 비정상 종료돼 lock 걸렸을 때 |
| `-lock-timeout=60s` | lock 대기 시간 설정 | CI/CD에서 동시 실행 충돌 방지 |
| `-no-color` | 색상 출력 제거 | CI 로그에 ANSI 코드 안 섞이게 할 때 |
| `-compact-warnings` | 경고 요약 출력 | 경고가 너무 많아 출력이 길 때 |
| `-json` | JSON 형식 출력 | 스크립트/자동화 파이프라인 연계 시 |

---

## terraform init

프로바이더 플러그인 다운로드 + 백엔드 초기화

| 옵션 | 의미 | 언제 쓰는가 |
|------|------|-------------|
| `-upgrade` | 프로바이더 최신 버전으로 업그레이드 | `required_providers`의 버전 범위 내 최신화 |
| `-reconfigure` | 백엔드 설정 강제 재초기화 | S3 백엔드 bucket/key 등을 바꿨을 때 |
| `-migrate-state` | 기존 state를 새 백엔드로 이전 | local → remote backend로 전환할 때 |
| `-backend=false` | 백엔드 초기화 스킵 | 로컬 테스트용, CI에서 lint만 할 때 |
| `-backend-config=파일` | 백엔드 설정을 외부 파일로 전달 | 민감한 정보(bucket명, token)를 코드에서 분리할 때 |

```bash
# 예: S3 백엔드 bucket 이름을 코드에 하드코딩 안 하고 싶을 때
terraform init -backend-config="bucket=my-tfstate-bucket"
```

> 언제: 처음 시작할 때, 모듈/프로바이더 추가했을 때, 백엔드 변경했을 때

---

## terraform plan

실제 변경 없이 무엇이 바뀔지 미리 확인

| 옵션 | 의미 | 언제 쓰는가 |
|------|------|-------------|
| `-out=파일명` | 플랜 결과를 파일로 저장 | CI/CD에서 plan → apply를 분리 실행할 때 |
| `-destroy` | 삭제 플랜 미리 보기 | destroy 전에 뭐가 지워지는지 확인할 때 |
| `-refresh=false` | 실제 인프라 상태 조회 스킵 | plan 속도 높일 때 (state 기준으로만 비교) |
| `-refresh-only` | state만 현실에 맞게 업데이트 (변경 없음) | 콘솔에서 수동 변경된 내용을 state에 반영할 때 |
| `-replace=리소스` | 특정 리소스 강제 재생성 플랜 | EC2가 오염됐을 때 destroy+create 강제 실행 |
| `-parallelism=숫자` | 동시 작업 수 조정 (기본 10) | API rate limit 걸릴 때 낮추고, 빠르게 하려면 높임 |

```bash
# CI/CD 패턴 (plan 결과를 저장해서 그대로 apply)
terraform plan -out=tfplan
terraform apply tfplan
```

> 언제: apply 전 반드시 실행 — 예상치 못한 삭제/변경 방지

---

## terraform apply

실제 인프라 생성/변경

| 옵션 | 의미 | 언제 쓰는가 |
|------|------|-------------|
| `-auto-approve` | 확인 프롬프트 없이 바로 적용 | CI/CD 자동화, 스크립트 실행 시 |
| `-replace=리소스` | 특정 리소스 강제 재생성 | taint 대신 사용 (taint는 deprecated) |
| `-refresh=false` | 상태 새로고침 스킵 | 변경 없음을 알 때 빠른 apply |

```bash
# EC2 인스턴스 강제 재생성 (재배포 시)
terraform apply -replace=aws_instance.web
```

> `-target`은 부분 배포 시 사용 가능하지만 남용 주의 — state 불일치 유발 가능

---

## terraform destroy

리소스 전체 삭제

| 옵션 | 의미 | 언제 쓰는가 |
|------|------|-------------|
| `-auto-approve` | 확인 없이 삭제 | 실습 환경 자동 정리 스크립트 |
| `-target=리소스` | 특정 리소스만 삭제 | 전체 삭제 말고 특정 리소스만 제거 |

---

## terraform fmt

코드 포맷 자동 정렬

| 옵션 | 의미 | 언제 쓰는가 |
|------|------|-------------|
| `-recursive` | 하위 디렉토리 전체 포맷 | 모노레포 전체 정리할 때 |
| `-check` | 포맷 안 맞으면 exit 1 (파일 수정 안 함) | CI에서 포맷 검사용 |
| `-diff` | 변경 내용 diff로 출력 | 어디가 바뀌는지 미리 확인 |
| `-write=false` | 파일 수정 없이 확인만 | dry-run |

---

## terraform validate

문법 오류 검사 (API 호출 없음, 빠름)

```bash
terraform validate
```

> 언제: plan 실행 전 빠른 문법 체크, CI 파이프라인 첫 단계

---

## terraform state

State 파일 직접 조작

| 서브명령 | 의미 | 언제 쓰는가 |
|----------|------|-------------|
| `list` | 관리 중인 리소스 목록 | 현재 뭐가 state에 있는지 확인 |
| `show 리소스` | 특정 리소스 상세 속성 | 실제 배포된 값 확인 (IP, ARN 등) |
| `mv A B` | state 내 리소스 이름 변경 | 모듈 리팩토링 / 이름 변경 시 재생성 방지 |
| `rm 리소스` | state에서 제거 (실제 리소스 유지) | Terraform 관리에서 제외할 때 |
| `pull` | 원격 state를 stdout으로 출력 | 현재 state 내용 JSON으로 확인 |
| `push` | 로컬 state를 원격에 강제 업로드 | state 수동 복구 시 (위험, 신중하게) |

---

## terraform import

기존 리소스를 Terraform 관리 하에 편입

```bash
terraform import aws_vpc.main vpc-xxxxxxxx
```

> 언제: 콘솔에서 수동으로 만든 리소스를 IaC로 전환할 때

---

## terraform output

output 값 확인

```bash
terraform output                  # 전체 output
terraform output vpc_id           # 특정 output
terraform output -json            # JSON 형식 (스크립트 연계용)
```

---

## terraform workspace

환경(dev/staging/prod) 분리

```bash
terraform workspace list
terraform workspace new dev
terraform workspace select prod
terraform workspace show          # 현재 워크스페이스
```

> 주의: `envs/` 디렉토리 분리 방식이 더 권장됨. workspace는 state만 분리하고 코드는 공유하므로 환경별 차이가 클수록 관리가 어려워짐

---

## 실전 시나리오 요약

| 상황 | 명령어 |
|------|--------|
| 처음 시작 | `init → validate → plan → apply` |
| 백엔드 bucket 바꿈 | `init -reconfigure` |
| CI에서 자동 배포 | `plan -out=tfplan` → `apply tfplan` |
| 특정 리소스만 재생성 | `apply -replace=리소스` |
| 모듈 이름 바꿨는데 재생성 막고 싶음 | `state mv 이전이름 새이름` |
| 콘솔에서 수동 변경한 걸 state에 반영 | `plan -refresh-only` → `apply -refresh-only` |
| API rate limit 걸림 | `apply -parallelism=3` |
| 실습 끝내고 전체 삭제 | `destroy -auto-approve` |
| state lock 해제 안 됨 | `apply -lock=false` (주의: 실제 작업 없을 때만) |

---

## 참고

- [aliases.md](./aliases.md) — zsh 단축키 설정
- [backend.md](./backend.md) — 원격 백엔드 설정
- [lifecycle-and-import.md](./lifecycle-and-import.md) — import, state mv 상세