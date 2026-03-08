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
| Security Group | [aws/security-group.md](./aws/security-group.md) | Phase 2 — Security Layer | 2026-03-07 |
| NACL (Network Access Control List) | [aws/nacl.md](./aws/nacl.md) | Phase 2 — Security Layer | 2026-03-07 |
| IAM (Identity and Access Management) | [aws/iam.md](./aws/iam.md) | Phase 2 — Security Layer | 2026-03-07 |
| Secrets Manager | [aws/secrets-manager.md](./aws/secrets-manager.md) | Phase 2 — Security Layer | 2026-03-07 |
| ACM (AWS Certificate Manager) | [aws/acm.md](./aws/acm.md) | Phase 2 — Security Layer | 2026-03-07 |
| Route53 (DNS, Hosted Zone, Public/Private) | [aws/route53.md](./aws/route53.md) | Phase 3 — Web Tier | 2026-03-07 |
| ALB (Application Load Balancer) | [aws/alb.md](./aws/alb.md) | Phase 3 — Web Tier | 2026-03-01 |
| S3 (Simple Storage Service) | [aws/s3.md](./aws/s3.md) | Phase 2 — Security Layer | 2026-03-07 |
| CloudFront | [aws/cloudfront.md](./aws/cloudfront.md) | Phase 3 — Web Tier | 2026-03-08 |
| WAF (Web Application Firewall) | [aws/waf.md](./aws/waf.md) | Phase 3 — Web Tier | 2026-03-08 |
| EC2 (Elastic Compute Cloud) | [aws/ec2.md](./aws/ec2.md) | Phase 4 — Application Tier | 2026-02-28 |
| ASG (Auto Scaling Group) & Launch Template | [aws/asg.md](./aws/asg.md) | Phase 4 — Application Tier | 2026-03-08 |
| ECS (Elastic Container Service) | [aws/ecs.md](./aws/ecs.md) | Phase 4 — Application Tier | 2026-03-07 |
| CloudWatch | [aws/cloudwatch.md](./aws/cloudwatch.md) | Phase 6 — Observability | 2026-03-08 |
| RDS Aurora (Aurora MySQL, Multi-AZ, Cluster 구조, Failover) | [aws/rds-aurora.md](./aws/rds-aurora.md) | Phase 5 — Database Tier | 2026-03-08 |
| ElastiCache Redis (Replication Group, Failover, 암호화) | [aws/elasticache.md](./aws/elasticache.md) | Phase 5 — Database Tier | 2026-03-08 |
| EC2 + ASG + Launch Template (통합 정리) | [aws/ec2-asg.md](./aws/ec2-asg.md) | Phase 4 — Application Tier | 2026-03-08 |
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
| 인프라 테스트 전략: plan 리뷰, tfsec/checkov, Terratest, AST 정적 분석 원리 | [terraform/testing.md](./terraform/testing.md) | 2026-03-07 |
| Remote State: terraform_remote_state, 멀티 State 아키텍처, _shared 패턴 | [terraform/remote-state.md](./terraform/remote-state.md) | 2026-03-07 |
| 함수 & 표현식: coalesce, try, dynamic block, for 표현식, jsonencode, validation | [terraform/functions-and-expressions.md](./terraform/functions-and-expressions.md) | 2026-03-07 |
| 안티패턴 & 개선 포인트: 실무 코드에서 발견한 잘못된 패턴들 | [terraform/anti-patterns.md](./terraform/anti-patterns.md) | 2026-03-07 |
| Provider: alias, 왜 variable 불가, module에 전달하는 법, us-east-1 패턴 | [terraform/providers.md](./terraform/providers.md) | 2026-03-08 |
| CLI 명령어 & 옵션: init/plan/apply/destroy/state/import 옵션 전체, 실전 시나리오 | [terraform/cli-commands.md](./terraform/cli-commands.md) | 2026-03-08 |
| Database Tier 리소스: random_password, aws_rds_cluster, aws_elasticache_replication_group 핵심 파라미터 | [terraform/database-resources.md](./terraform/database-resources.md) | 2026-03-08 |
