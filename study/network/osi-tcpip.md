# OSI / TCP-IP 모델

> 마지막 업데이트: 2026-03-08
> Phase 1 — 기초 원리

---

## 1. 한 줄 핵심 요약

네트워크 통신을 계층으로 분리한 모델 — 장애가 발생했을 때 "어느 계층 문제인가"를 빠르게 판단하기 위해 존재한다.

---

## 2. 왜 SRE/DevOps 엔지니어에게 중요한가

서버가 응답하지 않는다. 원인은 무수히 많다:
- 물리 케이블 단선? (L1)
- ARP 테이블 오염? (L2)
- 라우팅 설정 오류? (L3)
- 방화벽이 TCP 포트를 막고 있는가? (L4)
- TLS 인증서 만료? (L6)
- 애플리케이션 버그? (L7)

모델을 모르면 L7(앱 로그)만 뒤지다가 실제로는 L3 라우팅 문제였다는 걸 한 시간 후에야 발견한다.
**계층 모델은 장애 진단의 사고 프레임**이다.

---

## 3. 원리 심층 설명

### 3-1. OSI 7계층 vs TCP/IP 4계층

```
OSI 7계층                      TCP/IP 4계층         실제 프로토콜 예시
─────────────────────          ──────────────────   ─────────────────────────
7. Application  ┐              Application          HTTP, gRPC, DNS, SMTP
6. Presentation ┤  (합쳐짐)   Application          TLS, MIME, JSON 인코딩
5. Session      ┘              Application          TLS Session, HTTP/2 Stream
─────────────────────          ──────────────────   ─────────────────────────
4. Transport                   Transport            TCP, UDP, QUIC
─────────────────────          ──────────────────   ─────────────────────────
3. Network                     Internet             IP, ICMP, BGP
─────────────────────          ──────────────────   ─────────────────────────
2. Data Link    ┐              Network Access       Ethernet, ARP, 802.11 Wi-Fi
1. Physical     ┘  (합쳐짐)   Network Access       광케이블, 전기 신호
─────────────────────          ──────────────────   ─────────────────────────
```

**왜 OSI는 7계층이고 TCP/IP는 4계층인가?**

OSI는 ISO가 1984년에 "이론적으로 완벽한 모델"로 만들었다. 현실에서는 TCP/IP가 먼저 널리 쓰였고, TCP/IP는 그 현실을 반영한 4계층 모델이다. 실무에서는 L4, L7 같은 OSI 번호를 쓰는 게 관행이고, "L7 로드밸런서"처럼 OSI 계층 번호로 대화한다.

---

### 3-2. 각 계층이 하는 일

#### L1 — Physical (물리 계층)
**역할**: 0과 1을 전기 신호, 빛, 전파로 변환해서 전송
**단위**: Bit
**장비**: NIC, 광케이블, 허브, 리피터

```
Host A          Cable         Host B
[NIC] ──────── 전기/광 신호 ──────── [NIC]
```

AWS에서는 이 계층이 추상화되어 있다. EC2 인스턴스의 "가상 NIC"(ENI)가 실제로는 Nitro Hypervisor 위에서 동작한다. 물리적 케이블은 AWS가 관리한다.

---

#### L2 — Data Link (데이터 링크 계층)
**역할**: 같은 로컬 네트워크(브로드캐스트 도메인) 안에서 장치 간 통신
**단위**: Frame
**주소**: MAC 주소 (48비트, 예: `aa:bb:cc:dd:ee:ff`)
**핵심 프로토콜**: Ethernet, ARP, 802.1Q VLAN

```
Frame 구조:
┌──────────┬──────────┬──────┬─────────────┬─────┐
│ Dest MAC │  Src MAC │ Type │   Payload   │ FCS │
│  6 bytes │  6 bytes │ 2B   │   (IP패킷)  │ 4B  │
└──────────┴──────────┴──────┴─────────────┴─────┘
```

**MAC 주소 vs IP 주소 — 왜 둘 다 필요한가?**

MAC은 같은 네트워크 세그먼트 안에서의 주소다. IP는 글로벌 라우팅 주소다. 집 내부에서 "옆방"을 찾을 때는 집 내부 번호(MAC)를 쓰고, 다른 집에 편지를 보낼 때는 도로명 주소(IP)를 쓰는 것과 같다.

---

#### L3 — Network (네트워크 계층)
**역할**: 서로 다른 네트워크 간 패킷 라우팅
**단위**: Packet
**주소**: IP 주소 (IPv4: 32비트, IPv6: 128비트)
**핵심 프로토콜**: IP, ICMP, BGP, OSPF

```
IP 패킷 구조 (IPv4):
┌────────┬──────┬─────┬─────┬──────────┬──────────┬─────────────┐
│Version │ IHL  │ TOS │ Len │   TTL    │ Protocol │   Payload   │
│  4bit  │ 4bit │ 8bit│16bit│  8bit    │  8bit    │  (TCP/UDP)  │
├────────────────────────────┼──────────┼──────────┤             │
│      Source IP (32bit)     │  Dest IP │          │             │
└────────────────────────────┴──────────┴──────────┴─────────────┘
```

**TTL(Time To Live)**: 패킷이 라우터를 하나 통과할 때마다 1씩 감소. 0이 되면 패킷 폐기 + ICMP Time Exceeded 메시지 발송. `traceroute`는 이 원리를 활용한다.

---

#### L4 — Transport (전송 계층)
**역할**: 프로세스 간 통신 (포트 번호로 구분), 신뢰성 / 흐름 제어
**단위**: Segment (TCP) / Datagram (UDP)
**핵심 프로토콜**: TCP, UDP, QUIC

```
TCP Segment:
┌──────────┬──────────┬────────┬────────┬─────────────┐
│ Src Port │ Dst Port │ Seq No │ Ack No │   Payload   │
│  16bit   │  16bit   │ 32bit  │ 32bit  │             │
└──────────┴──────────┴────────┴────────┴─────────────┘
```

**5-tuple**: 네트워크 연결을 식별하는 5가지 정보
```
(Source IP, Source Port, Dest IP, Dest Port, Protocol)
예: (10.0.1.10, 54321, 93.184.216.34, 443, TCP)
```
방화벽, 로드밸런서, NAT 모두 이 5-tuple을 기준으로 동작한다.

---

#### L5/L6/L7 — Session / Presentation / Application
실무에서는 보통 합쳐서 "L7"이라고 부른다.

**Session (L5)**: 연결 상태 유지 (TLS Session, HTTP/2 Stream)
**Presentation (L6)**: 데이터 인코딩/암호화 (TLS, MIME, JSON)
**Application (L7)**: 실제 사용자 데이터 (HTTP 요청/응답, DNS 쿼리, gRPC 호출)

---

### 3-3. 캡슐화 (Encapsulation)

데이터가 송신 측에서 아래 계층으로 내려갈 때 각 계층이 헤더를 붙인다.

```
송신 (Application → Physical):
─────────────────────────────────────────────────────────
L7: [HTTP Data]
L4: [TCP Header][HTTP Data]               ← TCP Segment
L3: [IP Header][TCP Header][HTTP Data]    ← IP Packet
L2: [ETH Header][IP Hdr][TCP Hdr][Data][FCS]  ← Frame
L1: 전기/광 신호로 변환
─────────────────────────────────────────────────────────

수신 (Physical → Application):
─────────────────────────────────────────────────────────
L1: 신호 수신
L2: ETH 헤더 제거 → IP Packet 추출
L3: IP 헤더 제거 → TCP Segment 추출
L4: TCP 헤더 제거 → HTTP Data 추출
L7: HTTP 파싱 → 응답 생성
─────────────────────────────────────────────────────────
```

**PDU (Protocol Data Unit)**: 각 계층의 데이터 단위 명칭
- L7: Message / Data
- L4: Segment (TCP) / Datagram (UDP)
- L3: Packet
- L2: Frame
- L1: Bit

---

### 3-4. 라우터는 어느 계층까지 보는가?

```
장비            처리 계층       동작
──────────────────────────────────────────────────────
허브(Hub)       L1              신호를 모든 포트에 브로드캐스트
스위치(Switch)  L2              MAC 주소 기준 프레임 전달
라우터(Router)  L3              IP 주소 기준 패킷 라우팅
L4 LB           L4              TCP/UDP 포트 기준 분산
L7 LB (ALB)     L7              HTTP 헤더/URL 기준 분산
방화벽           L3~L7           패킷 필터링 (규칙에 따라)
```

AWS Security Group은 **Stateful L4 방화벽**이다.
AWS NACL은 **Stateless L4 방화벽**이다.
AWS ALB는 **L7 로드밸런서**다.
AWS NLB는 **L4 로드밸런서**다.

---

## 4. AWS에서의 연결

### VPC 내부의 계층 처리

```
EC2 Instance A (10.0.1.10)          EC2 Instance B (10.0.2.20)
┌────────────────────────┐          ┌────────────────────────┐
│  Application (L7)      │          │  Application (L7)      │
│  TCP Stack (L4)        │          │  TCP Stack (L4)        │
│  IP Stack (L3)         │          │  IP Stack (L3)         │
│  ENI (L2/L1 가상화)    │          │  ENI (L2/L1 가상화)    │
└──────────┬─────────────┘          └─────────────┬──────────┘
           │                                       │
    ┌──────┴───────────────────────────────────────┴──────┐
    │              Nitro Hypervisor / AWS Fabric           │
    │  (물리 L1/L2는 여기서 처리, EC2에는 보이지 않음)     │
    └─────────────────────────────────────────────────────┘
```

**중요**: VPC 내부에서는 L2 브로드캐스트가 억제된다. 같은 서브넷 내 EC2끼리도 ARP 브로드캐스트를 실제로 뿌리지 않는다. AWS Fabric이 ARP를 프록시로 처리한다. → [arp-mac.md](./arp-mac.md)에서 상세 설명

### Security Group vs NACL — 계층 관점

```
인터넷 → [NACL] → [Security Group] → EC2

NACL:             L3/L4, Stateless, 서브넷 경계에서 동작
Security Group:   L4, Stateful, ENI 레벨에서 동작
```

Stateful vs Stateless 차이:
- **Stateful (SG)**: 인바운드를 허용하면 해당 연결의 아웃바운드는 자동 허용
- **Stateless (NACL)**: 인바운드와 아웃바운드를 각각 따로 설정해야 함

---

## 5. 실무 디버깅 — 계층별 접근법

장애 발생 시 L1 → L7 순서로 확인한다 (또는 증상에 따라 의심 계층부터).

### L1/L2 확인
```bash
# 네트워크 인터페이스 상태 확인
ip link show
ip link show eth0

# 인터페이스가 UP인가? RX/TX bytes가 증가하는가?
# AWS: ENI 상태는 EC2 콘솔 → 네트워킹 탭에서 확인
```

### L3 확인
```bash
# 라우팅 테이블 확인
ip route show
ip route get 8.8.8.8   # 특정 목적지로 가는 경로

# ICMP로 L3 도달성 확인
ping -c 3 10.0.2.20

# TTL 기반 경로 추적 (L3 문제 위치 파악)
traceroute 10.0.2.20
traceroute -n 8.8.8.8   # DNS 조회 없이 IP로만
```

### L4 확인
```bash
# TCP 연결 가능한가? (포트 열려있는가)
telnet 10.0.2.20 80
nc -zv 10.0.2.20 443    # netcat으로 포트 확인

# 현재 연결 상태 확인
ss -tnp                  # TCP 연결 전체 (netstat보다 빠름)
ss -tnp state established # established 상태만
ss -ltnp                 # listening 포트 확인

# 연결 수 카운트
ss -s
```

### L7 확인
```bash
# HTTP 응답 헤더 확인
curl -I https://example.com
curl -v https://example.com  # 전체 TLS handshake 포함

# DNS 조회 확인
dig example.com
dig @8.8.8.8 example.com    # 특정 DNS 서버에 질의
nslookup example.com
```

### 계층별 장애 증상 매핑

| 증상 | 의심 계층 | 첫 번째 확인 명령어 |
|------|----------|-------------------|
| ping도 안 됨 | L1~L3 | `ip link show`, `ip route show` |
| ping은 되는데 TCP 연결 안 됨 | L4 (방화벽) | `telnet`, `nc -zv`, SG/NACL 확인 |
| TCP 연결은 되는데 HTTP 응답 없음 | L7 | `curl -v`, 앱 로그 |
| TLS 오류 | L6 | `openssl s_client`, 인증서 만료 확인 |
| 간헐적 패킷 손실 | L1~L3 | `ping` 손실률, `mtr` |
| 연결 지연 (고레이턴시) | L3~L4 | `traceroute`, `mtr` |

---

## 6. 자주 하는 실수 / 오개념

### "L7 LB는 L4 기능도 한다?"
맞다. L7은 L4 위에서 동작하므로 TCP를 이해하고 종료한다. ALB는 클라이언트와 TCP 연결을 맺고, 백엔드와 별도로 TCP 연결을 맺는다 (TCP Termination). 반면 NLB는 TCP를 종료하지 않고 패킷을 그대로 전달한다 (이론상, 실제는 약간 다름).

### "같은 서브넷 안이면 L3 라우팅 없이 통신한다?"
맞다. 같은 서브넷의 호스트끼리는 L2 통신이다. 라우터 없이 스위치(L2)만으로 통신 가능. 하지만 AWS VPC에서는 서브넷이 달라도 VPC 라우터가 처리하므로 표면상 차이가 적다.

### "ICMP는 L3인가 L4인가?"
L3다. ICMP는 IP 프로토콜의 일부로, TCP/UDP처럼 포트 번호가 없다. ping과 traceroute가 ICMP를 사용한다. 방화벽에서 ICMP를 막으면 ping이 안 된다 (= L3 도달성을 확인할 수 없음).

### "OSI 모델대로 통신한다?"
현실은 다르다. TLS는 L6(Presentation)이지만 실제로는 L4 위에서 TCP 소켓을 감싸는 형태다. HTTP/2는 하나의 TCP 연결 위에 여러 Stream을 다중화하는데, 이건 L5(Session) 개념이다. 현실의 프로토콜은 계층을 넘나든다. 모델은 사고의 도구이지 엄격한 규칙이 아니다.

### "Security Group이 L7 방화벽이다?"
아니다. SG는 L4(포트/프로토콜) 기준으로만 필터링한다. HTTP URL이나 헤더로 필터링하려면 WAF(Web Application Firewall)가 필요하다. WAF는 L7 방화벽이다.

---

## 7. 연결 개념

이 주제를 이해했다면 다음을 학습한다:

```
osi-tcpip.md (현재)
     │
     ├── ip-cidr.md        L3 주소 체계 심층 (CIDR, 서브네팅)
     ├── arp-mac.md        L2 주소 체계 심층 (ARP, MAC, AWS ARP 처리)
     ├── tcp-deep.md       L4 TCP 심층 (상태 머신, 튜닝)
     └── routing-basics.md L3 라우팅 심층 (라우팅 테이블, LPM)
```

이 파일들을 통해 "패킷이 EC2에서 출발해서 인터넷에 도달하기까지" 전 과정을 계층별로 설명할 수 있게 된다.

→ [IP Addressing & CIDR](./ip-cidr.md)
→ [ARP & MAC](./arp-mac.md)
→ [TCP 심층](./tcp-deep.md)
→ [로드맵으로 돌아가기](./README.md)