# EC2 / Launch Template / Auto Scaling Group

> 마지막 업데이트: 2026-03-08
> Phase: Phase 4 — Application Tier

---

## 1. 개념 설명

### EC2와 Auto Scaling의 차이

단순히 EC2를 하나 띄우면 트래픽이 급증할 때 서버가 다운되고, 인스턴스가 죽으면 수동으로 다시 올려야 한다.
Auto Scaling Group(ASG)은 이 문제를 해결하는 서비스다.

```
트래픽 급증 → CPU 80% → Scaling Policy 감지 → 인스턴스 자동 추가
트래픽 감소 → CPU 30% → Scaling Policy 감지 → 인스턴스 자동 제거
인스턴스 장애 → 헬스 체크 실패 → ASG가 자동으로 새 인스턴스 교체
```

ASG의 3가지 핵심 역할:
1. **탄력성(Elasticity)**: 트래픽에 따라 인스턴스 수 자동 조절
2. **고가용성(HA)**: Multi-AZ 배치로 AZ 장애 시에도 서비스 유지
3. **자동 복구(Self-healing)**: 불건강한 인스턴스를 자동으로 교체

---

### Launch Template

**EC2 인스턴스 생성 청사진**이다. ASG가 새 인스턴스를 추가할 때마다 이 설정을 기반으로 생성한다.

이전에는 Launch Configuration을 사용했지만, Launch Template이 후속 개념이다:

| 항목 | Launch Configuration | Launch Template |
|------|---------------------|-----------------|
| 버전 관리 | 없음 (수정 불가, 새로 생성) | 버전 관리 지원 |
| 인스턴스 교체 | 수동 | Instance Refresh 자동 롤링 |
| 스팟 인스턴스 | 제한적 | 완전 지원 |
| 권장 여부 | ❌ (Deprecated 예정) | ✅ 권장 |

---

### AMI (Amazon Machine Image)

EC2 인스턴스를 만들 때 사용하는 **운영체제 + 초기 설정 이미지**다.

```
AMI → EC2 인스턴스 생성 시 적용
      운영체제(Amazon Linux, Ubuntu 등)
      사전 설치된 소프트웨어
      기본 설정
```

**AMI ID 하드코딩의 문제점:**
- AMI ID는 리전마다 다르다 (`ap-northeast-2`와 `us-east-1`의 ID가 다름)
- AWS가 새 버전을 출시하면 기존 ID는 유효하지 않게 됨

**해결책: data source로 동적 참조**
```hcl
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
```
`data.aws_ami.amazon_linux.id`가 실행 시점의 최신 AMI ID를 자동 반환한다.

---

### User Data

EC2 인스턴스가 **최초 부팅할 때 딱 한 번** cloud-init이 실행하는 스크립트.

- 인스턴스 기동 후 nginx/nginx 설치, 앱 배포 등에 사용
- Launch Template의 `user_data`는 base64로 인코딩된 값이어야 함
- Terraform에서는 `base64encode()` 함수로 변환

```
인스턴스 시작 → cloud-init 실행 → user_data 스크립트 실행
                                   (dnf install, systemctl start 등)
```

User Data 실행에는 시간이 걸리므로, ASG `health_check_grace_period`를 충분히 설정해야 한다.

---

### IMDSv2 (Instance Metadata Service v2)

EC2는 `http://169.254.169.254`에 접근하면 자신의 IAM 자격증명, 인스턴스 ID 등 메타데이터를 조회할 수 있다.

**IMDSv1 취약점:**
```
공격자 서버 → SSRF로 앱을 조작 → curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
             → IAM 임시 자격증명 탈취 → AWS 리소스 무제한 접근
```

**IMDSv2 해결책:**
```
1. PUT /latest/api/token 요청으로 토큰 발급 (TTL 설정)
2. 이후 모든 메타데이터 요청에 토큰 헤더 필요
→ 단순 SSRF로는 PUT 요청을 위조할 수 없어 방어
```

`http_tokens = "required"` 설정이 IMDSv2를 강제한다.

---

### Scaling Policy 종류

| 타입 | 동작 방식 | 적합한 상황 |
|------|-----------|------------|
| Simple Scaling | 알람 발생 시 고정 수량 추가/제거 | 단순한 경우 |
| Step Scaling | CPU 70%→+1, CPU 90%→+3 등 단계별 | 세밀한 제어 필요 시 |
| Target Tracking | 목표값 유지 (CPU 60%), AWS가 자동 결정 | **가장 권장** |
| Scheduled Scaling | 특정 시간에 인스턴스 수 변경 | 트래픽 패턴이 예측 가능한 경우 |

Target Tracking이 권장되는 이유:
- CloudWatch Alarm을 AWS가 자동으로 생성/관리
- Scale In/Out 결정을 AWS 알고리즘이 최적화
- 설정이 단순하고 오동작 가능성이 낮음

---

### 헬스 체크 타입 (EC2 vs ELB)

ASG `health_check_type`의 두 가지 옵션:

| 타입 | 판단 기준 | 문제 |
|------|----------|------|
| `EC2` | EC2 인스턴스 상태 (Running/Stopped) | 앱이 죽어도 EC2가 Running이면 통과 |
| `ELB` | ALB Target Group 헬스 체크 결과 | 앱 레벨 장애까지 감지 |

실무에서는 ALB와 함께 쓸 때 항상 `ELB` 타입을 사용한다.

---

### Instance Refresh

Launch Template을 새 버전으로 업데이트했을 때, 기존 인스턴스를 **무중단으로 교체**하는 기능.

```
기존 인스턴스: v1 (2개)
↓ LT v2로 업데이트
Instance Refresh 시작
↓ 인스턴스 1개 종료 → 새 인스턴스(v2) 시작 → 헬스 체크 통과
↓ 나머지 1개 종료 → 새 인스턴스(v2) 시작 → 헬스 체크 통과
완료: v2 인스턴스 2개
```

`min_healthy_percentage = 50`: 교체 중 최소 50%는 정상 상태 유지.

---

### 배포 방식 비교 (Rolling / Blue-Green / Canary / In-Place)

**Rolling (순차 교체)** — ASG Instance Refresh 방식

```
Before: [v1] [v1] [v1] [v1]
Step 1: [v2] [v1] [v1] [v1]
Step 2: [v2] [v2] [v1] [v1]
After:  [v2] [v2] [v2] [v2]
```

기존 인스턴스를 하나씩 교체하므로 총 인스턴스 수가 유지된다 → 추가 인프라 비용 없음.
단점: 교체 중간에 v1과 v2가 동시에 서비스됨. API 응답 구조가 바뀌면 클라이언트 혼란 가능.

**Blue/Green (환경 전환)**

```
현재:  Blue(v1)  → ALB → 서비스 중
준비:  Green(v2) → 별도 구축 (인프라 2배!)
전환:  ALB 타겟을 Blue → Green으로 스위칭 (즉각적)
롤백:  ALB를 다시 Blue로 스위칭 (즉시)
```

추가 인프라가 필요한 이유: v1과 v2가 동시에 존재해야 하므로 전환 중 서버가 2배.
장점: 전환이 즉각적, v1/v2 혼재 없음, 롤백이 ALB 스위칭 한 번으로 즉시 가능.
단점: 일시적으로 비용 2배.

**Canary (점진적 트래픽 이동)**

```
초기:  v1 → 100%
1단계: v1 → 95%, v2 → 5%   ← 소수 사용자로 검증
2단계: v1 → 70%, v2 → 30%
완료:  v1 → 0%,  v2 → 100%
```

ALB 가중치 라우팅(Weighted Target Group)으로 구현.
장점: 문제 발생 시 소수 사용자만 영향. 실 트래픽으로 안전하게 검증 가능.
단점: 모니터링 체계 필요, 설정 복잡.

**In-Place (제자리 교체)**

```
v1 서버에서 직접: stop v1 → 코드 교체 → start v2
```

장점: 추가 인프라 없음, 가장 단순.
단점: 배포 중 다운타임 발생. 롤백 어려움.

| 방식 | 다운타임 | 추가 비용 | 롤백 속도 | v1/v2 혼재 |
|------|---------|---------|---------|-----------|
| In-Place | 있음 | 없음 | 느림 | 없음 |
| Rolling | 없음 | 없음 | 느림 | 있음 |
| Blue/Green | 없음 | 있음 (일시적) | 즉시 | 없음 |
| Canary | 없음 | 부분 | 빠름 | 있음 |

> 이 프로젝트: ASG `instance_refresh` = Rolling 방식.
> prod 환경에서는 `min_healthy_percentage = 90`으로 올려 한 번에 하나씩만 교체 권장.

---

### Session Manager (Bastion 없이 접속)

기존에는 Private 서브넷 EC2에 접근하려면 Bastion Host(점프 서버)가 필요했다:
```
외부 → SSH → Bastion(Public Subnet) → SSH → App EC2(Private Subnet)
```

**Bastion의 문제점:**
- 관리 포인트 추가 (보안 패치, 비용)
- SSH 키 관리 부담
- SG에서 22 포트를 열어야 함 (공격 표면)

**Session Manager 해결책:**
```
AWS Console / CLI → SSM Session Manager → App EC2 (Private Subnet)
                    (HTTPS/443 사용, SSH 키 불필요)
```

SSM Session Manager가 동작하는 조건:
1. EC2 IAM Role에 `AmazonSSMManagedInstanceCore` 정책 연결
2. EC2에서 SSM 엔드포인트로 HTTPS 아웃바운드 가능 (NAT GW 또는 VPC Endpoint)
3. SSM Agent 설치 (Amazon Linux 2023은 기본 포함)

→ 이 프로젝트에서는 security 레이어에서 `app_role`에 이미 해당 정책이 연결되어 있고,
  Private NAT 서브넷은 NAT GW를 통해 443 아웃바운드가 가능하므로 SSM이 동작한다.

---

## 2. 이 프로젝트에서의 위치

```
Phase 4 — Application Tier (envs/dev/app/)
  ├── modules/app/main.tf
  │   ├── data "aws_ami"          ← 최신 Amazon Linux 2023 자동 참조
  │   ├── aws_launch_template     ← EC2 청사진 (AMI, 타입, SG, IAM, User Data)
  │   ├── aws_autoscaling_group   ← Multi-AZ 배치, Target Group 연결
  │   └── aws_autoscaling_policy  ← CPU 60% Target Tracking
  └── envs/dev/app/
      ├── data.tf  ← network/security/web 레이어 remote state 참조
      └── main.tf  ← module "app" 호출
```

**선행 리소스 (다른 레이어에서 가져오는 값):**
- `network.outputs.vpc_id` — Launch Template에서 직접 사용하지 않지만 모듈 인터페이스용
- `network.outputs.private_nat_subnet_ids` — ASG가 인스턴스를 배치할 서브넷
- `security.outputs.sg_ids["app_sg"]` — App 서버 SG
- `security.outputs.iam_instance_profile_arns["app_role"]` — SSM/CW/SM 접근 권한
- `web.outputs.target_group_arn` — ASG가 등록할 ALB Target Group

**후행 리소스 (다음 Phase에서 이 레이어를 참조):**
- Phase 6 Monitoring: `asg_name`으로 CloudWatch Alarm 연결

---

## 3. 실무 주의사항

1. **`ignore_changes = [desired_capacity]`** — 없으면 Scaling Policy가 늘린 인스턴스를 Terraform apply마다 초기화
2. **`health_check_grace_period`** — User Data 실행 시간보다 짧으면 멀쩡한 인스턴스가 종료됨
3. **Launch Template `name_prefix`** — `name` 대신 사용해야 교체 시 충돌 없이 create_before_destroy 동작
4. **User Data 수정** — 기존 인스턴스에는 적용 안 됨, Instance Refresh로 교체 필요
5. **target_group_arns** — ALB 없이 ASG만 있으면 헬스 체크 타입을 `EC2`로 변경 필요

---

## 4. 참고

- Launch Template 공식 문서: https://docs.aws.amazon.com/autoscaling/ec2/userguide/launch-templates.html
- ASG 공식 문서: https://docs.aws.amazon.com/autoscaling/ec2/userguide/what-is-amazon-ec2-auto-scaling.html
- Session Manager: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html
- 검색 키워드: `aws_launch_template terraform`, `aws_autoscaling_group target_tracking`, `IMDSv2 terraform`
