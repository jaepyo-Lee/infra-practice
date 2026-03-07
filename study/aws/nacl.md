# NACL (Network Access Control List)

마지막 업데이트: 2026-03-07 (NACL 필요 시나리오, SG Stateful 의미 보완)

---

## 1. 개념 설명

NACL은 **서브넷 수준**에서 트래픽을 필터링하는 방화벽이다.
Security Group이 EC2 인스턴스(ENI) 단위라면, NACL은 서브넷 경계에서 작동한다.

### Security Group vs NACL 핵심 차이

| 구분 | Security Group | NACL |
|------|---------------|------|
| 적용 범위 | ENI (EC2 인스턴스) | 서브넷 |
| 상태 | **Stateful** | **Stateless** |
| 규칙 방향 | Inbound + Outbound | Inbound + Outbound 모두 명시 |
| 규칙 평가 | 모든 규칙 동시 평가 | 번호 순서대로, 첫 매칭에서 종료 |
| 기본값 | 모두 차단 | 모두 허용 |
| 대상 지정 | SG 참조 가능 | CIDR만 가능 |

### Stateless가 핵심이다

SG는 **Stateful** — inbound를 허용하면 응답 트래픽은 자동으로 허용된다.
NACL은 **Stateless** — 요청을 허용해도 응답도 별도로 허용해야 한다.

SG Stateful의 진짜 의미는 "outbound 기본값이 전체 허용이라서"가 아니다.
outbound를 전부 차단해도, inbound로 들어온 연결의 응답은 자동으로 나간다.
즉, **연결 상태를 추적**해서 응답 패킷을 outbound 규칙 평가 없이 통과시킨다.

예: EC2가 외부 API를 호출하는 경우
- outbound 443 허용 → 요청은 나감
- 응답이 돌아올 때 사용하는 **임시 포트(Ephemeral Port: 1024-65535)** — inbound로도 허용해야 한다
- 이걸 빠뜨리면 응답 패킷이 차단됨

### 규칙 번호 순서 평가

```
100 → 허용: 10.0.1.0/24 inbound 80
200 → 거부: 0.0.0.0/0 inbound 80
*   → 거부: 모든 트래픽 (기본값, 수정 불가)
```

10.0.1.0/24에서 오는 80 트래픽 → 100번에서 허용, 평가 종료.
다른 IP의 80 트래픽 → 100번 통과 → 200번에서 거부.

### 이 프로젝트 3-Tier에서의 역할

```
인터넷
  ↓
[Public Subnet NACL]      — 80, 443 inbound 허용 / 임시포트 outbound 허용
  ↓ ALB
[Private App Subnet NACL] — ALB 서브넷에서 8080 inbound만 허용
  ↓ App Server
[Private DB Subnet NACL]  — App 서브넷에서 3306 inbound만 허용
```

NACL은 **서브넷 경계의 마지노선**이다. SG가 뚫려도 NACL이 막아준다.

---

### NACL이 실제로 필요한 경우

NACL은 없어도 기능상 문제없는 경우가 많다. 실제로 필요한 상황은 아래로 좁혀진다.

**1. 특정 IP를 완전히 차단해야 할 때**
SG는 `deny` 규칙이 없다. "이 IP는 절대 안 된다"는 NACL로만 가능하다.
예: DDoS 공격 IP, 악성 봇 IP 블랙리스트

**2. 서브넷 간 통신을 서브넷 단위로 제어할 때**
"App 서브넷 → DB 서브넷만 허용, 그 외 서브넷에서 DB 서브넷 접근 차단" 같은
서브넷 경계 격리는 NACL이 더 명확하다.

**3. 컴플라이언스/보안 인증 요구사항이 있을 때**
PCI-DSS, HIPAA 등에서 다중 방어 레이어(Defense in Depth)를 요구한다.
SG + NACL 둘 다 있어야 감사를 통과하는 경우가 있다.

**4. SG 실수에 대한 안전망이 필요할 때**
개발자가 SG에 `0.0.0.0/0`을 실수로 추가해도 NACL이 서브넷 단위로 막고 있으면 피해를 줄일 수 있다.

> 정리: NACL은 "없으면 안 되는" 것이 아니라 **"있으면 더 안전한" 추가 방어선**이다.
> SG가 1차 방어, NACL이 2차 방어. 규모가 클수록, 컴플라이언스가 있을수록 필수에 가까워진다.

---

### 실무 주의사항

- **임시 포트(Ephemeral Port) 누락**이 가장 흔한 실수
  - Linux: 32768-60999 / AWS 권장: 1024-65535
- 하나의 NACL을 여러 서브넷에 연결 가능하지만, 서브넷은 NACL 하나만 가짐
- SG에 세부 규칙, NACL은 큰 단위로 — 지나치게 세분화하면 관리가 복잡해짐

---

## 2. Terraform 핵심 파라미터

### `aws_network_acl`

| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `vpc_id` | ✅ | 어느 VPC에 속하는 NACL인지 |
| `subnet_ids` | 선택 | 이 NACL을 적용할 서브넷 목록 |
| `tags` | 선택 | 리소스 태그 |

`subnet_ids`를 여기 직접 쓰지 않고 `aws_network_acl_association`으로 분리하는 방식도 있다.
분리하면 서브넷 추가/제거 시 NACL 리소스 자체를 재생성하지 않아도 된다.

### `aws_network_acl_rule`

| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `network_acl_id` | ✅ | 어느 NACL에 붙는 규칙인지 |
| `rule_number` | ✅ | 평가 순서 (낮을수록 먼저 평가) |
| `egress` | ✅ | `true`=outbound, `false`=inbound |
| `protocol` | ✅ | `tcp`, `udp`, `-1`(전체) |
| `rule_action` | ✅ | `allow` 또는 `deny` |
| `cidr_block` | ✅* | 대상 IP 범위 (*ipv6는 `ipv6_cidr_block`) |
| `from_port` / `to_port` | 조건부 | protocol이 tcp/udp일 때 필수 |

**규칙 번호는 100 단위 간격 권장** — 나중에 중간 삽입 시 101, 150 등을 쓸 수 있도록.

→ [핵심 블록 & for_each](../terraform/core-blocks.md)

---

## 3. 이 프로젝트에서의 위치

- **Phase 2 — Security Layer** (`envs/dev/security/`)
- 선행 리소스: VPC, Subnet (network 레이어 apply 완료 필요)
- 후행 리소스: ALB, ASG (NACL 규칙이 트래픽 경로를 제어)
- `data.terraform_remote_state.network`로 서브넷 ID를 가져와 NACL에 연결

---

## 4. 직접 해볼 것

AWS 콘솔에서 기본 NACL 구조 확인:
1. VPC 콘솔 → Network ACLs
2. 현재 VPC의 기본 NACL 클릭
3. Inbound / Outbound rules 탭 확인
4. 기본값: `100: ALL Traffic ALLOW`, `*: ALL Traffic DENY` 구조 확인
5. 서브넷 연결 탭에서 어떤 서브넷이 이 NACL을 쓰는지 확인

검색 키워드: `AWS NACL ephemeral ports stateless`, `aws_network_acl_rule terraform`