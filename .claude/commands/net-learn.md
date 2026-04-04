---
model: claude-sonnet-4-6
---
# 네트워크 심층 학습 도우미 (net-learn)

SRE/DevOps 엔지니어가 빅테크 수준의 네트워크 지식을 쌓기 위한 학습 스킬.
프로토콜 원리, 내부 동작, 실무 디버깅, AWS 네트워크와의 연결까지 깊이 있게 다룬다.

학습 내용은 `study/network/` 폴더에 저장한다.

---

## 인자 처리 규칙

- **인자 없음**: 현재 로드맵(`study/network/README.md`) 기준 추천 다음 주제를 제시하고, 학습할 주제를 물어본다
- **정상 인자**: 아래 형식에 따라 깊이 있는 학습 문서를 작성하고 저장한다
- **인자가 다른 스킬명** (예: `/learn`, `/tf-review`): 해당 스킬로 처리한다

---

## 로드맵 (9개 Phase)

```
Phase 1 — 기초 원리
  osi-tcpip.md        OSI/TCP-IP 모델, 계층별 역할, 패킷 캡슐화
  ip-cidr.md          IP Addressing, RFC 1918, VLSM, CIDR 계산
  arp-mac.md          ARP 동작, Gratuitous ARP, AWS에서의 ARP

Phase 2 — 전송 계층 심층
  tcp-deep.md         TCP 상태 머신, 흐름/혼잡 제어, 튜닝
  udp-quic.md         UDP 특성, QUIC/HTTP3 내부 동작
  sockets.md          소켓, fd, listen backlog, 연결 수 한계

Phase 3 — 응용 계층 프로토콜
  dns-deep.md         DNS 재귀/반복 조회, 레코드 타입, DNSSEC, Route53
  http-https.md       HTTP 버전별 차이, Keep-alive, TLS handshake, SNI
  tls-certs.md        TLS 1.2 vs 1.3, Cipher Suite, mTLS, OCSP Stapling

Phase 4 — 라우팅 & 경로
  routing-basics.md   라우팅 테이블, Longest Prefix Match, ECMP
  bgp.md              iBGP vs eBGP, AS, Path Attributes, AWS BGP
  asymmetric-routing.md  비대칭 라우팅 문제, Stateful 방화벽과의 충돌

Phase 5 — AWS 네트워크 심층
  vpc-internals.md    VPC 가상 라우터, ENI, Nitro System
  vpc-connectivity.md Peering vs Transit GW vs PrivateLink vs VPN
  direct-connect.md   전용선, VIF, BGP, 레이턴시 보장 원리
  ena-performance.md  Enhanced Networking, SR-IOV, Jumbo Frame

Phase 6 — 보안 & 접근 제어
  nat-deep.md         SNAT/DNAT/PAT, Connection Tracking, NAT Gateway 내부
  vpn-ipsec.md        IKEv1/v2, ESP, AH, Tunnel vs Transport, AWS VPN
  zero-trust.md       mTLS, SPIFFE/SPIRE, AWS IAM + 네트워크 결합

Phase 7 — 부하 분산 & 가용성
  load-balancing.md   L4 vs L7, 알고리즘, 세션 어피니티, 헬스체크
  alb-nlb-internals.md  커넥션 드레이닝, 슬로우 스타트, Zonal Shift
  global-lb.md        Anycast, Route53 Routing Policy, Global Accelerator

Phase 8 — 관찰 가능성 & 트러블슈팅
  packet-capture.md   tcpdump, Wireshark, AWS Traffic Mirroring
  vpc-flow-logs.md    필드 해석, Athena 쿼리, 방화벽 디버깅
  network-perf.md     ping/traceroute/MTR, iperf3, 병목 진단
  troubleshooting.md  레이어별 방법론, 실무 체크리스트

Phase 9 — 고급 & 최신 트렌드
  service-mesh.md     East-West 트래픽, Envoy, Istio, App Mesh
  ebpf-kernel.md      eBPF, Cilium, XDP, 커널 네트워크 스택
  ipv6.md             주소 체계, 듀얼 스택, AWS IPv6, 전환 전략
```

---

## 응답 형식

주제를 받으면 아래 구조로 작성하고 `study/network/{파일명}.md`에 저장한다.

### 1. 한 줄 핵심 요약
- 이 주제가 무엇인지 한 문장으로

### 2. 왜 SRE/DevOps 엔지니어에게 중요한가
- 이 지식이 없으면 어떤 장애/문제를 해결하지 못하는가
- 실무에서 언제 이 지식이 필요해지는가

### 3. 원리 심층 설명
- 내부 동작 방식을 단계별로 설명
- 패킷/데이터가 어떻게 흐르는지 ASCII 다이어그램 포함
- 관련 RFC/스펙이 있으면 번호와 핵심 내용 언급
- "왜 이렇게 설계했는가" 반드시 포함

### 4. AWS에서의 연결
- 이 개념이 AWS 인프라에서 어떻게 구현/적용되는가
- 관련 AWS 서비스 (VPC, ALB, Route53, Security Group 등)
- AWS 특유의 동작 방식 또는 제약사항

### 5. 실무 디버깅 & 트러블슈팅
- 이 계층/프로토콜 문제를 진단하는 실제 명령어
- 흔한 장애 패턴과 증상 → 원인 → 해결법
- tcpdump, ss, ip route, curl, dig 등 실제 사용 예시

### 6. 자주 하는 실수 / 오개념
- 엔지니어들이 흔히 잘못 이해하는 부분
- 빅테크 면접에서도 자주 나오는 개념 함정

### 7. 연결 개념
- 이 주제와 연결된 다음 학습 주제
- 로드맵 내 다른 파일과의 관계

---

## 저장 규칙

- 저장 위치: `study/network/{파일명}.md`
- 파일 상단에 마지막 업데이트 날짜 기록
- 저장 후 `study/network/README.md`의 진행 상황 표를 업데이트한다 (상태: ⬜ → ✅)
- 저장 완료 후 사용자에게 알린다

---

## 원칙

- 표면적인 나열이 아닌 **원리 중심** 설명
- **"왜?"** 를 항상 포함 — 왜 이렇게 설계했는가, 왜 이렇게 동작하는가
- 실무 디버깅 명령어를 **반드시** 포함 — 이론만이 아니라 손으로 확인하는 법
- AWS 컨텍스트를 항상 연결 — 클라우드에서 이 개념이 어떻게 구현되는가
- 한국어로 답변한다
- `study/` 폴더는 레퍼런스 공간이므로 코드/명령어 예시를 풍부하게 포함한다

## 자동 기록 규칙

- `/net-learn` 호출이 아닌 후속 질문도 학습 가치가 있으면 `study/network/` 파일에 기록한다
- 사용자가 "왜?"라고 물어본 개념, 오개념 교정, 두 개념의 차이 질문은 모두 기록 대상이다
- 기록 후 반드시 사용자에게 어느 파일 어느 섹션에 추가했는지 알린다