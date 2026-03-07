# Terraform 학습 목록

| 주제 | 파일 | 마지막 업데이트 |
|------|------|----------------|
| 모듈 구조 컨벤션 (파일 분리, provider 위치, outputs) | [module-structure.md](./module-structure.md) | 2026-02-28 |
| 핵심 블록: resource, variable, output, module 개념 및 데이터 흐름 | [core-blocks.md](./core-blocks.md) | 2026-02-28 |
| Data Source: 외부 리소스 읽기, aws_availability_zones, terraform_remote_state | [data-source.md](./data-source.md) | 2026-02-28 |
| tfvars 관리: .tfvars.example 패턴, gitignore, 민감값 처리, 우선순위 | [tfvars.md](./tfvars.md) | 2026-02-28 |
| Backend: State 원격 저장, S3+DynamoDB, State Lock, key 경로 설계 | [backend.md](./backend.md) | 2026-03-01 |
| Lifecycle & Import: prevent_destroy, State Drift, import, state mv | [lifecycle-and-import.md](./lifecycle-and-import.md) | 2026-03-01 |
| 쉘 단축키: alias 설정법, -parallelism 함수 대체, 단축키 목록 | [aliases.md](./aliases.md) | 2026-03-02 |
| 인프라 테스트 전략: plan 리뷰, tfsec/checkov, Terratest, AST 정적 분석 원리 | [testing.md](./testing.md) | 2026-03-07 |
