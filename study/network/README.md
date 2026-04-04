# Network 학습 로드맵

SRE/DevOps 엔지니어가 빅테크 수준의 네트워크 지식을 쌓기 위한 로드맵.
`/net-learn {주제}` 명령어로 학습하면 자동으로 각 파일에 추가된다.

---

## 학습 진행 현황

### Phase 1 — 기초 원리
| 상태 | 주제 | 파일 | 핵심 키워드 |
|------|------|------|------------|
| ✅ | OSI / TCP-IP 모델 | [osi-tcpip.md](./osi-tcpip.md) | 캡슐화, PDU, 계층별 디버깅 |
| ⬜ | IP Addressing & CIDR | [ip-cidr.md](./ip-cidr.md) | RFC 1918, VLSM, Longest Prefix Match |
| ⬜ | ARP & MAC | [arp-mac.md](./arp-mac.md) | Gratuitous ARP, ARP Spoofing, AWS ARP |

### Phase 2 — 전송 계층 심층
| 상태 | 주제 | 파일 | 핵심 키워드 |
|------|------|------|------------|
| ⬜ | TCP 심층 | [tcp-deep.md](./tcp-deep.md) | 상태 머신, TIME_WAIT, 혼잡 제어, 튜닝 |
| ⬜ | UDP & QUIC | [udp-quic.md](./udp-quic.md) | 비연결형, Head-of-Line Blocking, HTTP3 |
| ⬜ | 소켓 & 연결 관리 | [sockets.md](./sockets.md) | fd, listen backlog, accept queue, ss |

### Phase 3 — 응용 계층 프로토콜
| 상태 | 주제 | 파일 | 핵심 키워드 |
|------|------|------|------------|
| ⬜ | DNS 심층 | [dns-deep.md](./dns-deep.md) | 재귀/반복 조회, DNSSEC, Split-horizon |
| ⬜ | HTTP/HTTPS | [http-https.md](./http-https.md) | HTTP/1.1 vs 2 vs 3, Keep-alive, SNI |
| ⬜ | TLS & 인증서 | [tls-certs.md](./tls-certs.md) | TLS 1.3, mTLS, OCSP Stapling |

### Phase 4 — 라우팅 & 경로
| 상태 | 주제 | 파일 | 핵심 키워드 |
|------|------|------|------------|
| ⬜ | 라우팅 기초 | [routing-basics.md](./routing-basics.md) | 라우팅 테이블, LPM, Static vs Dynamic, ECMP |
| ⬜ | BGP | [bgp.md](./bgp.md) | iBGP vs eBGP, AS, Path Attributes |
| ⬜ | 비대칭 라우팅 | [asymmetric-routing.md](./asymmetric-routing.md) | Stateful 방화벽 충돌, ECMP 문제 |

### Phase 5 — AWS 네트워크 심층
| 상태 | 주제 | 파일 | 핵심 키워드 |
|------|------|------|------------|
| ⬜ | VPC Internals | [vpc-internals.md](./vpc-internals.md) | 가상 라우터, ENI, Nitro System |
| ⬜ | VPC 연결 패턴 | [vpc-connectivity.md](./vpc-connectivity.md) | Peering vs Transit GW vs PrivateLink |
| ⬜ | Direct Connect | [direct-connect.md](./direct-connect.md) | VIF, BGP, 레이턴시 보장 |
| ⬜ | ENA & 고성능 네트워킹 | [ena-performance.md](./ena-performance.md) | SR-IOV, Jumbo Frame, Placement Group |

### Phase 6 — 보안 & 접근 제어
| 상태 | 주제 | 파일 | 핵심 키워드 |
|------|------|------|------------|
| ⬜ | NAT 심층 | [nat-deep.md](./nat-deep.md) | SNAT/DNAT/PAT, Connection Tracking |
| ⬜ | VPN & IPSec | [vpn-ipsec.md](./vpn-ipsec.md) | IKEv1/v2, ESP, AH, Tunnel vs Transport |
| ⬜ | Zero Trust Networking | [zero-trust.md](./zero-trust.md) | mTLS, SPIFFE/SPIRE, IAM + 네트워크 |

### Phase 7 — 부하 분산 & 가용성
| 상태 | 주제 | 파일 | 핵심 키워드 |
|------|------|------|------------|
| ⬜ | L4 vs L7 부하 분산 | [load-balancing.md](./load-balancing.md) | 알고리즘, 세션 어피니티, 헬스체크 |
| ⬜ | ALB/NLB 내부 동작 | [alb-nlb-internals.md](./alb-nlb-internals.md) | 커넥션 드레이닝, Zonal Shift |
| ⬜ | 글로벌 부하 분산 | [global-lb.md](./global-lb.md) | Anycast, Route53 Routing Policy |

### Phase 8 — 관찰 가능성 & 트러블슈팅
| 상태 | 주제 | 파일 | 핵심 키워드 |
|------|------|------|------------|
| ⬜ | 패킷 캡처 & 분석 | [packet-capture.md](./packet-capture.md) | tcpdump, Wireshark, Traffic Mirroring |
| ⬜ | VPC Flow Logs | [vpc-flow-logs.md](./vpc-flow-logs.md) | 필드 해석, Athena 쿼리 |
| ⬜ | 네트워크 성능 측정 | [network-perf.md](./network-perf.md) | ping/MTR/iperf3, 병목 진단 |
| ⬜ | 트러블슈팅 방법론 | [troubleshooting.md](./troubleshooting.md) | 레이어별 접근법, 실무 체크리스트 |

### Phase 9 — 고급 & 최신 트렌드
| 상태 | 주제 | 파일 | 핵심 키워드 |
|------|------|------|------------|
| ⬜ | Service Mesh | [service-mesh.md](./service-mesh.md) | East-West 트래픽, Envoy, Istio |
| ⬜ | eBPF & 커널 네트워킹 | [ebpf-kernel.md](./ebpf-kernel.md) | eBPF, Cilium, XDP |
| ⬜ | IPv6 | [ipv6.md](./ipv6.md) | 듀얼 스택, AWS IPv6, 전환 전략 |

---

## 학습 방법

1. 위 순서대로 진행하되, 급한 주제가 있으면 건너뛰어도 된다
2. 각 파일을 읽은 후 궁금한 점은 질문 — 대화 내용은 해당 파일에 자동 추가된다
3. `/net-learn {주제}` 로 새 주제를 학습하거나 기존 주제를 심화할 수 있다

---

## 학습 후기 & 메모

> 여기에 학습하며 느낀 점, 실무에서 확인한 내용, 추가로 파고들고 싶은 주제를 기록한다