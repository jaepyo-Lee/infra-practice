# Study — 학습 레퍼런스

AWS + Terraform 학습 내용을 정리한 폴더입니다.
`/learn {주제}` 명령어로 학습하면 자동으로 여기에 추가됩니다.

## 폴더 구조

```
study/
  aws/        ← AWS 서비스 학습 (VPC, EC2, RDS 등)
  terraform/  ← Terraform 개념 학습 (State, Module, Workspace 등)
```

---

## AWS 주제 목록

| 주제 | 파일 | Phase | 마지막 업데이트 |
|------|------|-------|----------------|
| VPC (Virtual Private Cloud) | [aws/vpc.md](./aws/vpc.md) | Phase 1 — Network Foundation | 2026-02-28 |
| Subnet | [aws/subnet.md](./aws/subnet.md) | Phase 1 — Network Foundation | 2026-03-01 |
| Internet Gateway (IGW) | [aws/igw.md](./aws/igw.md) | Phase 1 — Network Foundation | 2026-03-01 |
| NAT Gateway | [aws/nat-gateway.md](./aws/nat-gateway.md) | Phase 1 — Network Foundation | 2026-03-01 |
| Route Table | [aws/route-table.md](./aws/route-table.md) | Phase 1 — Network Foundation | 2026-03-01 |
| ALB (Application Load Balancer) | [aws/alb.md](./aws/alb.md) | Phase 3 — Web Tier | 2026-03-01 |
| EC2 (Elastic Compute Cloud) | [aws/ec2.md](./aws/ec2.md) | Phase 4 — Application Tier | 2026-02-28 |
| AWS Batch | [aws/batch.md](./aws/batch.md) | 프로젝트 외 참고 | 2026-03-01 |

---

## Terraform 주제 목록

| 주제 | 파일 | 마지막 업데이트 |
|------|------|----------------|
| 모듈 구조 컨벤션 (파일 분리, provider 위치, outputs) | [terraform/module-structure.md](./terraform/module-structure.md) | 2026-02-28 |
| 핵심 블록: resource, variable, output, module 개념 및 데이터 흐름 | [terraform/core-blocks.md](./terraform/core-blocks.md) | 2026-02-28 |
| Data Source: 외부 리소스 읽기, aws_availability_zones, terraform_remote_state | [terraform/data-source.md](./terraform/data-source.md) | 2026-02-28 |
| tfvars 관리: .tfvars.example 패턴, gitignore, 민감값 처리, 우선순위 | [terraform/tfvars.md](./terraform/tfvars.md) | 2026-02-28 |
| Backend: State 원격 저장, S3+DynamoDB, State Lock, key 경로 설계 | [terraform/backend.md](./terraform/backend.md) | 2026-03-01 |
| Lifecycle & Import: prevent_destroy, State Drift, import, state mv | [terraform/lifecycle-and-import.md](./terraform/lifecycle-and-import.md) | 2026-03-01 |
| 쉘 단축키: alias 설정법, -parallelism 함수 대체, 단축키 목록 | [terraform/aliases.md](./terraform/aliases.md) | 2026-03-02 |
