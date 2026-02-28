# Terraform 전체 삭제 스크립트 생성 (destroy-all)

초기화된 모든 Terraform 모듈을 탐색하여 `terraform destroy`를 순서대로 실행하는 쉘 스크립트를 자동 생성한다.

---

## 실행 절차

### 1. 초기화된 모듈 탐색

프로젝트 루트부터 `.terraform/` 디렉토리가 존재하는 폴더를 모두 찾는다.
`.terraform/` 폴더가 있다는 것은 `terraform init`이 실행된 모듈임을 의미한다.

Glob 패턴: `**/.terraform`

### 2. 삭제 순서 결정

의존성이 높은 리소스부터 먼저 삭제해야 한다. 아래 우선순위 순서로 정렬한다.
경로에 아래 키워드가 포함된 순서대로 스크립트 상단에 배치한다:

1. `monitoring` / `observability` / `cloudwatch`
2. `database` / `db` / `rds` / `elasticache`
3. `app` / `asg` / `application`
4. `web` / `alb` / `cloudfront`
5. `security` / `sg` / `iam`
6. `vpc` / `network`

위 키워드에 해당하지 않는 디렉토리는 목록 맨 앞에 배치한다.

### 3. 스크립트 생성

아래 내용을 담은 쉘 스크립트를 `bootstrap/destroy-all.sh`에 작성한다.

#### 스크립트 구성 요소

- `#!/bin/bash` shebang
- `set -e` — 오류 발생 시 즉시 중단
- 각 모듈 디렉토리로 이동 후 `terraform destroy -auto-approve` 실행
- 각 단계마다 실행 전 로그 출력 (`echo "[DESTROY] 경로"`)
- 실패 시 어느 모듈에서 실패했는지 출력하는 trap 처리

#### 스크립트 생성 위치

`bootstrap/destroy-all.sh`

생성 후 실행 권한을 부여하는 안내를 출력한다:
```
chmod +x bootstrap/destroy-all.sh
```

### 4. 결과 보고

```
## destroy-all.sh 생성 완료

### 탐색된 모듈 (삭제 순서)
1. envs/dev/monitoring/   ← cloudwatch 키워드
2. envs/dev/database/     ← rds 키워드
3. envs/dev/vpc/          ← vpc 키워드

### 스크립트 위치
bootstrap/destroy-all.sh

### 실행 방법
chmod +x bootstrap/destroy-all.sh
./bootstrap/destroy-all.sh

### 주의사항
- 실행 전 반드시 AWS 프로파일/계정을 확인한다
- 삭제된 리소스는 복구할 수 없다
- 실행 전 `terraform plan -destroy`로 대상 리소스를 미리 확인하는 것을 권장한다
```

---

## 원칙

- 이 스킬은 스크립트를 **생성**만 하고 실행하지 않는다 — 실행은 사용자가 직접 한다
- 이미 `bootstrap/destroy-all.sh`가 존재하면 덮어쓰기 전에 사용자에게 확인한다
- 한국어로 답변한다