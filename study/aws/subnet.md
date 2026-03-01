# Subnet

> 마지막 업데이트: 2026-03-01

---

## 핵심 개념

### VPC와의 관계

Subnet은 VPC IP 공간의 일부를 잘라낸 구획이다.
- VPC `10.0.0.0/16` 안에서 `10.0.1.0/24`를 잘라내면 그게 서브넷 하나
- 리소스(EC2, RDS 등)는 반드시 특정 서브넷 안에 배치된다
- 서브넷은 하나의 AZ에만 속한다 (AZ 장애 대비 → 같은 역할의 서브넷을 여러 AZ에)

### Public vs Private 구분 기준

| 구분 | map_public_ip_on_launch | Route Table |
|------|------------------------|-------------|
| Public | true | 0.0.0.0/0 → IGW |
| Private | false (생략 가능) | 0.0.0.0/0 → NAT (or 없음) |

Public IP 할당 여부와 Route Table이 함께 결정한다.
`map_public_ip_on_launch = true`만으로는 인터넷이 안 된다. Route Table에 IGW 경로가 있어야 한다.

### AWS가 예약하는 5개 IP

`/24` 서브넷(256개)에서 실제 사용 가능한 IP는 **251개**다.

```
10.0.1.0   → 네트워크 주소
10.0.1.1   → AWS VPC 라우터
10.0.1.2   → AWS DNS 서버
10.0.1.3   → AWS 미래 예약
10.0.1.255 → 브로드캐스트
```

---

## Terraform 구현 참고

서브넷 반복 생성 패턴(`count`, `for_each`), outputs 작성 방법은 아래를 참고한다:
- [핵심 블록 & for_each/each.key/each.value](../terraform/core-blocks.md)
- [lifecycle & State 관리 (count→for_each 전환)](../terraform/lifecycle-and-import.md)

---

## 실무 주의사항

1. **cidr과 az 리스트 길이를 반드시 맞춰야 한다** — 다르면 index out of range 오류
2. **서브넷 CIDR은 생성 후 변경 불가** — 잘못 설계하면 삭제 후 재생성
3. **AZ는 최소 2개** — 하나면 그 AZ 장애 시 전체 서비스 중단
