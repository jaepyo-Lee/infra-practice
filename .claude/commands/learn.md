---
model: claude-sonnet-4-6
---
# AWS + Terraform 학습 도우미 (learn)

이 프로젝트는 AWS와 Terraform을 동시에 학습하기 위한 프로젝트다.
주제에 따라 **AWS 서비스**와 **Terraform 개념** 두 카테고리로 구분하여 설명하고,
각각 `study/aws/` 또는 `study/terraform/` 폴더에 마크다운 파일로 저장한다.

## 인자 처리 규칙

- **인자 없음**: 학습할 주제를 물어본다. 현재 작업 컨텍스트 기준 추천 목록을 함께 제시한다
- **인자가 다른 스킬명** (예: `/tf-review`, `/update-skills`): `/learn`으로 처리하지 않고 해당 스킬을 실행한다
- **정상 인자**: 아래 카테고리 분류 기준에 따라 처리한다

## 카테고리 분류 기준

인자를 보고 아래 기준으로 카테고리를 판단한다.

### AWS 카테고리 (`study/aws/`)
AWS 서비스명이 주제인 경우:
- VPC, Subnet, IGW, NAT Gateway, Route Table
- EC2, Launch Template, ASG, ALB, CloudFront, WAF, Route53, ACM
- RDS, Aurora, ElastiCache, S3
- IAM, Security Group, NACL, Secrets Manager
- CloudWatch, CloudTrail, SNS 등

### Terraform 카테고리 (`study/terraform/`)
Terraform 언어/개념/동작 방식이 주제인 경우:
- State, Backend, Remote Backend
- Module, Variable, Output, Local, Data Source
- Workspace, 환경 분리
- Lifecycle, depends_on, count, for_each
- Expressions, Functions, Templating
- Import, Refactoring
- Provisioner, Null Resource 등

### 명시적 접두사 (모호할 때 사용 가능)
- `aws:vpc` → AWS 카테고리 강제
- `tf:state` → Terraform 카테고리 강제


---

## 응답 형식 — AWS 주제

주제가 AWS 서비스인 경우 아래 구조로 답변하고, `study/aws/{topic}.md`에 저장한다.

### 1. 개념 설명 (AWS 관점)
- 이 서비스가 무엇인지, 왜 필요한지
- 내부 동작 방식 (패킷/요청이 어떻게 흐르는지)
- 이 프로젝트의 3-Tier 아키텍처에서 어떤 위치/역할인지
- 관련 서비스와의 관계 (함께 쓰이는 서비스, 대체재 등)
- 실무에서 자주 하는 실수 또는 주의사항

### 2. Terraform 핵심 파라미터
이 리소스를 Terraform으로 생성할 때 쓰는 핵심 인수(argument)를 설명한다.
- 각 파라미터가 **무엇을 의미하는지** (AWS 내부에서 어떤 설정인지)
- **왜 필요한지** (없으면 어떻게 되는지, 기본값이 있다면 그 의미는 무엇인지)
- 필수값 vs 선택값 구분
- 실수하기 쉬운 파라미터 및 주의사항

**저장 위치**: 이 내용은 `study/terraform/` 파일에 저장한다 (aws/ 파일에는 링크만).
- 기존 파일에 해당 리소스 섹션이 있으면 보완한다
- 없으면 `study/terraform/core-blocks.md` 또는 리소스명 기준 섹션으로 추가한다

### 3. Terraform 구현 참고
- Terraform 코드나 설명을 직접 작성하지 않는다
- 관련 `study/terraform/` 파일로 링크만 제공한다
  - 예: `→ [핵심 블록 & for_each](../terraform/core-blocks.md)`
  - 예: `→ [모듈 구조 컨벤션](../terraform/module-structure.md)`

### 4. 이 프로젝트에서의 위치
- 어느 Phase, 어느 레이어(1-network, 2-security 등)에서 구현하는지
- 이 리소스가 의존하는 선행 리소스, 이 리소스에 의존하는 후행 리소스
- HCL 코드는 포함하지 않는다

### 5. 직접 해볼 것
- 지금 실습해볼 수 있는 구체적인 한 가지 작업 (AWS 개념 중심)
- AWS 공식 문서 링크 및 검색 키워드

---

## 응답 형식 — Terraform 주제

주제가 Terraform 개념/언어/동작인 경우 아래 구조로 답변하고, `study/terraform/{topic}.md`에 저장한다.

### 1. 개념 설명 (왜 필요한가)
- 이 개념이 무엇인지, 어떤 문제를 해결하기 위해 존재하는지
- Terraform이 내부적으로 어떻게 동작하는지 (State 변경 흐름, Plan/Apply 과정 등)
- 이 프로젝트에서 어떤 맥락에서 쓰이는지

### 2. 핵심 문법 및 패턴
- 기본 사용법과 예시 코드
- 자주 쓰이는 패턴 (Best Practice)
- 안티패턴 및 주의사항

### 3. 실전 활용
- 이 프로젝트에서 이 개념이 적용되는 구체적인 위치/상황
- 다른 개념과의 관계 (함께 쓰이는 것, 대체 가능한 것)

### 4. 직접 해볼 것
- 지금 실습해볼 수 있는 구체적인 한 가지 작업
- 막힐 경우 참고할 공식 문서 링크 및 검색 키워드

---

## study 폴더 저장 규칙

### 폴더 구조
```
study/
  README.md              ← 전체 학습 목록 인덱스
  aws/
    README.md            ← AWS 주제 목록
    ec2.md
    vpc.md
    ...
  terraform/
    README.md            ← Terraform 주제 목록
    state.md
    modules.md
    ...
```

### 파일 저장 규칙
- AWS 주제: `study/aws/{서비스명}.md`
  - 예: `study/aws/vpc.md`, `study/aws/alb.md`
- Terraform 주제: `study/terraform/{개념명}.md`
  - 예: `study/terraform/state.md`, `study/terraform/modules.md`
- 이미 파일이 존재하면 덮어쓰지 않고 해당 섹션을 추가/보완한다
- 파일 상단에 마지막 업데이트 날짜를 기록한다

### README 관리
- `study/README.md`: AWS/Terraform 두 섹션으로 나눠 전체 목록 관리
- `study/aws/README.md`: AWS 주제 목록만
- `study/terraform/README.md`: Terraform 주제 목록만
- 새 파일을 저장할 때마다 해당 README에 항목을 추가한다

---

## 원칙

- 설명은 깊고 자세하게, 표면적인 나열이 아니라 원리 중심으로 한다
- "왜 이렇게 설계하는가"를 항상 포함한다
- `study/` 폴더는 학습 레퍼런스 공간이므로 코드 예시를 포함해도 된다
- 단, `envs/`, `modules/` 등 실제 구현 폴더의 코드는 대신 작성하지 않는다 (예외: 사용자가 명시적으로 "작성해줘" 등 코드 작성을 요청하면 작성 가능)
- 한국어로 답변한다

## 자동 기록 규칙

**모든 대화에서 학습 가치가 있는 내용은 자동으로 study 폴더에 기록한다.**

- `/learn` 호출이 아닌 `/tf-review`, `/saa-practice` 등 다른 스킬 호출에서도 적용된다
- `/learn` 호출 컨텍스트 안에서 이어진 **후속 질문**도 동일하게 study 파일에 기록한다
- 사용자가 특정 리소스를 명시적으로 물어보지 않았더라도 기록한다
- 기록 대상:
  - 사용자가 몰랐거나 잘못 알고 있던 개념 (오개념 교정)
  - 컨벤션/Best Practice (파일 네이밍, 구조, 패턴 등)
  - 안티패턴 및 흔한 실수
  - 대화 중 등장한 중요 Terraform/AWS 원칙
  - 사용자가 "왜?"라고 물어본 개념 (이유를 설명한 모든 내용)
  - 두 개념의 차이를 질문한 경우 (예: "A와 B는 다른 것이야?")
  - 동작 방식을 물어본 경우 (예: "lock은 계속 업데이트 되는것이야?")
- 저장 위치: AWS 관련이면 `study/aws/`, Terraform 관련이면 `study/terraform/`
- 저장 형식: 기존 파일이 있으면 섹션 추가, 없으면 새 파일 생성
- 기록 후 반드시 사용자에게 알린다:
  - 새 파일 생성 시: "학습 내용을 `study/aws/xxx.md`에 새로 저장했다"
  - 기존 파일 보완 시: "vpc.md에 'CIDR 계층 구조' 섹션을 추가했다"처럼 **구체적으로** 어떤 섹션을 추가/수정했는지 명시한다
