# count / for_each / dynamic 심층 정리
> 마지막 업데이트: 2026-04-04

세 가지 모두 "반복"을 다루지만 동작하는 레이어가 다르다.

```
count    → 리소스/모듈 자체를 N개 만들기 (숫자 기반)
for_each → 리소스/모듈 자체를 map/set 기반으로 만들기 (키 기반)
dynamic  → 리소스 내부의 중첩 블록을 반복 생성
```

---

## 1. count

### 기본 동작

```hcl
resource "aws_instance" "web" {
  count = 3
  ami           = "ami-xxx"
  instance_type = "t3.micro"
  tags = {
    Name = "web-${count.index}"  # 0, 1, 2
  }
}
```

- `count.index` — 현재 반복 인덱스 (0부터 시작)
- 생성된 리소스 주소: `aws_instance.web[0]`, `aws_instance.web[1]`, `aws_instance.web[2]`

### count = 0 패턴 (조건부 리소스)

가장 자주 쓰이는 count 패턴. "이 리소스를 만들거냐 안 만들거냐"를 결정한다.

```hcl
variable "enable_bastion" {
  type    = bool
  default = false
}

resource "aws_instance" "bastion" {
  count         = var.enable_bastion ? 1 : 0
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
}

# 참조 시 주의: 리스트로 관리됨
output "bastion_ip" {
  value = length(aws_instance.bastion) > 0 ? aws_instance.bastion[0].public_ip : null
  # 또는
  value = one(aws_instance.bastion[*].public_ip)  # count 0이면 null
}
```

### count의 치명적 약점: 중간 삭제 시 재생성

```hcl
# 3개 생성 상태
# [0] = "web-a", [1] = "web-b", [2] = "web-c"

# 중간 항목(web-b)을 제거하면?
variable "instances" {
  default = ["web-a", "web-c"]  # web-b 제거
}
resource "aws_instance" "web" {
  count = length(var.instances)
  tags  = { Name = var.instances[count.index] }
}
```

```
# plan 결과:
~ aws_instance.web[1]  # web-b → web-c로 수정 (기존 web-b 인스턴스 변경)
- aws_instance.web[2]  # web-c 삭제
```

인덱스 순서로 관리되므로 중간 항목 삭제 시 뒤의 것들이 재생성된다. **이게 count의 가장 큰 문제.** 이 때문에 복수 리소스 관리는 for_each를 권장한다.

### count가 적합한 경우

| 상황 | 이유 |
|------|------|
| 리소스를 만들거나 안 만들거나 (0 or 1) | 단순 조건부 생성 |
| 순서가 의미 있는 경우 (예: AZ 인덱스 기반) | count.index 활용 |
| 수가 절대 줄어들지 않는 경우 | 재정렬 위험 없음 |

---

## 2. for_each

### 기본 동작

```hcl
# map 사용
resource "aws_subnet" "public" {
  for_each = {
    "ap-northeast-2a" = "10.0.1.0/24"
    "ap-northeast-2c" = "10.0.2.0/24"
  }

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value           # 10.0.1.0/24
  availability_zone = each.key             # ap-northeast-2a
}
```

- `each.key` — 맵의 키 (또는 set의 값)
- `each.value` — 맵의 값
- 리소스 주소: `aws_subnet.public["ap-northeast-2a"]`, `aws_subnet.public["ap-northeast-2c"]`

### map vs set 차이

```hcl
# set: 값 자체가 키. each.key == each.value
for_each = toset(["ap-northeast-2a", "ap-northeast-2c"])
# → each.key = "ap-northeast-2a", each.value = "ap-northeast-2a"

# map: 키와 값이 다름. 더 많은 정보를 담을 수 있음 (권장)
for_each = {
  "ap-northeast-2a" = { cidr = "10.0.1.0/24", tier = "public" }
  "ap-northeast-2c" = { cidr = "10.0.2.0/24", tier = "public" }
}
# → each.value.cidr, each.value.tier 접근 가능
```

**set은 순서가 없다.** 값이 바뀌면 키가 바뀌는 것과 같아서 리소스 재생성 위험이 있다. **map을 쓰는 게 안전하다.**

### 복잡한 객체 map 패턴

```hcl
# variables.tf
variable "subnets" {
  type = map(object({
    cidr = string
    tier = string
    az   = string
  }))
  default = {
    "public-2a"  = { cidr = "10.0.1.0/24",  tier = "public",  az = "ap-northeast-2a" }
    "public-2c"  = { cidr = "10.0.2.0/24",  tier = "public",  az = "ap-northeast-2c" }
    "private-2a" = { cidr = "10.0.11.0/24", tier = "private", az = "ap-northeast-2a" }
    "private-2c" = { cidr = "10.0.12.0/24", tier = "private", az = "ap-northeast-2c" }
  }
}

# main.tf
resource "aws_subnet" "this" {
  for_each = var.subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  tags = {
    Name = each.key
    Tier = each.value.tier
  }
}
```

### for 표현식으로 for_each 입력 가공

```hcl
# 전체 서브넷 중 public만 필터링
resource "aws_route_table_association" "public" {
  for_each = {
    for k, v in var.subnets : k => v
    if v.tier == "public"
  }

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public.id
}
```

### for_each 결과 참조

```hcl
# 단일 키 참조
aws_subnet.this["public-2a"].id

# 전체 ID 목록 (values() 필수)
output "subnet_ids" {
  value = [for s in aws_subnet.this : s.id]
  # 또는
  value = values(aws_subnet.this)[*].id
}

# 특정 티어의 ID만
output "private_subnet_ids" {
  value = [
    for k, s in aws_subnet.this : s.id
    if var.subnets[k].tier == "private"
  ]
}
```

### for_each key 변경 = destroy + recreate

```hcl
# 변경 전
for_each = { "web-server" = ... }  # aws_instance.app["web-server"]

# 변경 후 (이름만 바꿨는데)
for_each = { "application" = ... }  # aws_instance.app["application"]
```

```
# plan 결과:
- aws_instance.app["web-server"]   # 삭제
+ aws_instance.app["application"]  # 새로 생성
```

**키는 리소스의 고유 식별자다. 한번 정하면 바꾸기 어렵다.** 변경이 필요하면 `moved` 블록 사용.

### for_each와 depends_on

```hcl
# for_each로 만든 리소스에 의존할 때
resource "aws_route_table_association" "private" {
  for_each = aws_subnet.this  # 리소스 맵 자체를 for_each에 전달 가능!

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
```

`for_each = aws_subnet.this` — 다른 for_each 리소스를 직접 입력으로 쓰면 키가 자동으로 매핑된다. 같은 키로 순회하므로 AZ별 1:1 매핑이 자연스럽게 성립.

---

## 3. dynamic

### 왜 필요한가

리소스 내부의 중첩 블록(nested block)은 일반 `if`로 제어할 수 없다.

```hcl
# ❌ 이런 코드는 불가능
resource "aws_security_group" "web" {
  if var.allow_ssh {
    ingress {  # 블록 자체를 조건부로 넣을 수 없음
      from_port = 22
    }
  }
}

# ✅ dynamic 사용
resource "aws_security_group" "web" {
  dynamic "ingress" {
    for_each = var.allow_ssh ? [1] : []
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
}
```

### 기본 문법

```hcl
dynamic "블록이름" {
  for_each = 반복할_컬렉션
  content {
    # 블록 내용
    # each.key, each.value 사용 가능
  }
}
```

### iterator 커스텀 (중첩 dynamic일 때 유용)

기본적으로 `each`를 쓰지만, `iterator`로 이름을 바꿀 수 있다.

```hcl
dynamic "ingress" {
  for_each = var.ingress_rules
  iterator = rule  # each 대신 rule 사용

  content {
    from_port   = rule.value.from_port
    to_port     = rule.value.to_port
    protocol    = rule.value.protocol
    cidr_blocks = rule.value.cidr_blocks
    description = rule.key  # 맵 키를 설명으로 사용
  }
}
```

### 실전 패턴 1: Security Group 규칙 동적 생성

```hcl
variable "ingress_rules" {
  type = map(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = {
    "http"  = { from_port = 80,  to_port = 80,  protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }
    "https" = { from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }
  }
}

resource "aws_security_group" "web" {
  name   = "web-sg"
  vpc_id = aws_vpc.main.id

  dynamic "ingress" {
    for_each = var.ingress_rules
    iterator = rule
    content {
      description = rule.key
      from_port   = rule.value.from_port
      to_port     = rule.value.to_port
      protocol    = rule.value.protocol
      cidr_blocks = rule.value.cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### 실전 패턴 2: ALB Listener Rule 조건부 추가

```hcl
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.certificate_arn != null ? "redirect" : "forward"

    # HTTPS 리다이렉트 블록 조건부 생성
    dynamic "redirect" {
      for_each = var.certificate_arn != null ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    # forward 블록 조건부 생성
    dynamic "forward" {
      for_each = var.certificate_arn == null ? [1] : []
      content {
        target_group {
          arn = aws_lb_target_group.app.arn
        }
      }
    }
  }
}
```

### 실전 패턴 3: 중첩 dynamic

```hcl
# WAF 규칙처럼 깊이 중첩된 블록
resource "aws_wafv2_web_acl" "main" {
  dynamic "rule" {
    for_each = var.waf_rules
    content {
      name     = rule.key
      priority = rule.value.priority

      dynamic "statement" {
        for_each = [rule.value.statement]
        content {
          # statement 내용
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.key
        sampled_requests_enabled   = true
      }
    }
  }
}
```

---

## 4. 세 가지 비교 정리

| 구분 | count | for_each | dynamic |
|------|-------|----------|---------|
| 대상 | 리소스/모듈 전체 | 리소스/모듈 전체 | 리소스 내부 블록 |
| 식별자 | 인덱스 (숫자) | 키 (문자열) | each.key/value |
| 참조 | `resource[0]` | `resource["key"]` | 해당 없음 |
| 중간 삭제 | 위험 (재정렬) | 안전 (키 기반) | 해당 없음 |
| 주 용도 | 0 or 1 (조건부) | 복수 리소스 관리 | 블록 조건부 생성 |

### 선택 기준 요약

```
Q: 리소스 자체를 여러 개 만드는가?
  → Yes: for_each (키 기반, 안전)
         단, "만들거나 안 만들거나" → count = 0 or 1

Q: 리소스 내부의 블록을 조건부로/반복 생성하는가?
  → Yes: dynamic

Q: 인덱스 번호가 의미 있는 경우(예: count.index로 AZ 매핑)?
  → count (단, 나중에 for_each로 전환 고려)
```

---

## 5. count → for_each 마이그레이션

기존 count 기반 리소스를 for_each로 전환할 때는 반드시 `moved` 블록 사용.

```hcl
# 기존 (count 기반)
# resource "aws_subnet" "public" { count = 2 }
# → aws_subnet.public[0], aws_subnet.public[1]

# 신규 (for_each 기반)
resource "aws_subnet" "public" {
  for_each = {
    "ap-northeast-2a" = "10.0.1.0/24"
    "ap-northeast-2c" = "10.0.2.0/24"
  }
}

# moved 블록으로 state 마이그레이션
moved {
  from = aws_subnet.public[0]
  to   = aws_subnet.public["ap-northeast-2a"]
}
moved {
  from = aws_subnet.public[1]
  to   = aws_subnet.public["ap-northeast-2c"]
}
```

---

## 6. 직접 해볼 것

1. `for_each`에 map을 넣고 Security Group 규칙을 변수로 관리해보기
2. `dynamic`으로 ingress 규칙 블록을 조건부로 추가/제거해보기
3. `count = 0`으로 bastion 인스턴스를 선택적으로 생성해보기
4. for 표현식으로 map을 필터링해서 for_each에 넣어보기

공식 문서:
- count: https://developer.hashicorp.com/terraform/language/meta-arguments/count
- for_each: https://developer.hashicorp.com/terraform/language/meta-arguments/for_each
- dynamic: https://developer.hashicorp.com/terraform/language/expressions/dynamic-blocks

검색 키워드: `terraform for_each map object`, `terraform dynamic block nested`, `terraform count to for_each migration`

---

## 관련 파일
- `study/terraform/core-blocks.md` — for_each 모듈 적용, for 표현식
- `study/terraform/functions-and-expressions.md` — toset, values, one 함수
- `study/terraform/state-management.md` — count→for_each 마이그레이션 시 moved 블록