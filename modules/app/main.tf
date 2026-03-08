# modules/app/main.tf
# Phase 4 — Application Tier
# Launch Template + Auto Scaling Group + Scaling Policy

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. AMI Data Source
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# data source: 이미 존재하는 AWS 리소스를 읽어오는 방법
# aws_ami: 실행 시점의 최신 AMI ID를 동적으로 가져옴
# 하드코딩을 피하는 이유: AMI ID는 리전마다 다르고, 업데이트되면 변경되므로
# data source로 항상 최신 AMI를 참조하는 것이 Best Practice
data "aws_ami" "amazon_linux" {
  most_recent = true    # 필터 결과 중 가장 최신 AMI를 선택
  owners      = ["amazon"] # AWS 공식 AMI만 사용 (서드파티 악성 AMI 방지)

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"] # Amazon Linux 2023 이름 패턴
    # al2023: Amazon Linux 2023 (최신 LTS, 5년 지원)
    # x86_64: Intel/AMD 아키텍처 (arm64는 Graviton 전용)
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"] # HVM(Hardware Virtual Machine): 현재 표준, PV보다 성능 우수
  }
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. Launch Template
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Launch Template: EC2 인스턴스 생성 청사진
# ASG가 새 인스턴스를 추가할 때마다 이 템플릿을 기반으로 생성함
# Launch Configuration의 후속 개념 — 버전 관리(versioning) 지원
resource "aws_launch_template" "app" {
  name_prefix = "${var.name}-app-lt-"
  # name_prefix: Terraform이 유니크 suffix를 자동으로 붙임
  # 예: dev-app-lt-20240101120000 → 새 버전 생성 시 충돌 없이 교체 가능

  description   = "App 서버 Launch Template"
  image_id      = data.aws_ami.amazon_linux.id # 위에서 동적으로 가져온 AMI ID
  instance_type = var.instance_type            # t3.micro, t3.small 등 환경별로 다름

  # IAM Instance Profile: EC2가 AWS API를 호출할 수 있는 권한 부여
  # 없으면 EC2에서 AWS CLI 명령어 실행 불가, SSM Session Manager 접속 불가
  iam_instance_profile {
    arn = var.iam_instance_profile_arn # security 레이어에서 생성한 profile ARN
  }

  # Security Group 연결
  # vpc_security_group_ids: 기본 네트워크 인터페이스(eth0)에 SG를 적용하는 방법
  # network_interfaces 블록을 쓰면 이 속성은 사용 불가 (중복 설정 불허)
  vpc_security_group_ids = [var.security_group_id]

  # EBS 루트 볼륨 설정
  block_device_mappings {
    device_name = "/dev/xvda" # Amazon Linux의 루트 디바이스 이름

    ebs {
      volume_size           = var.volume_size
      volume_type           = "gp3"  # gp3: gp2보다 3,000 IOPS 기본 제공, 20% 저렴
      encrypted             = true   # EBS 암호화: 보안 규정 준수 필수
      delete_on_termination = true   # 인스턴스 종료 시 볼륨 자동 삭제 (비용 절감)
    }
  }

  # IMDSv2 강제 (Instance Metadata Service v2)
  # 배경: EC2 메타데이터(http://169.254.169.254)에는 IAM 임시 자격증명이 포함됨
  # IMDSv1 취약점: SSRF 공격으로 curl 한 줄이면 자격증명 탈취 가능
  # IMDSv2 해결책: 먼저 PUT 요청으로 토큰을 받고, 그 토큰으로만 메타데이터 조회 허용
  # → 단순 SSRF로는 PUT 요청을 위조할 수 없어 방어 가능
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # required = IMDSv2 강제 / optional = v1 허용
    http_put_response_hop_limit = 1           # TTL 1: 컨테이너 내부에서 메타데이터 접근 차단
  }

  # User Data: 인스턴스 최초 부팅 시 cloud-init이 실행하는 스크립트
  # base64encode(): Launch Template은 base64 인코딩된 값을 요구함
  # <<-EOF ... EOF: HCL heredoc — 들여쓰기 허용, 멀티라인 문자열
  user_data = base64encode(<<-EOF
    #!/bin/bash
    # 패키지 업데이트
    dnf update -y

    # nginx 설치
    dnf install -y nginx

    # nginx를 ${var.app_port} 포트로 실행하도록 설정
    # ALB Target Group 헬스 체크 경로(/health)를 처리하는 서버 블록 추가
    cat > /etc/nginx/conf.d/app.conf << 'NGINXCONF'
    server {
        listen ${var.app_port};

        # ALB Target Group 헬스 체크 경로
        # ALB가 30초마다 이 경로를 HTTP GET으로 호출해 200 응답을 기대함
        location /health {
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }

        location / {
            root /usr/share/nginx/html;
            index index.html;
        }
    }
    NGINXCONF

    # 기본 nginx 설정(80 포트)을 비활성화
    # 기본 conf에서 80 포트 server 블록이 있으면 위 설정과 충돌
    rm -f /etc/nginx/conf.d/default.conf

    # nginx 시작 및 부팅 시 자동 실행 등록
    systemctl start nginx
    systemctl enable nginx

    # 인스턴스 식별용 페이지 (로드밸런서 동작 확인용)
    echo "<h1>Hello from $(hostname -f)</h1><p>Instance is healthy</p>" > /usr/share/nginx/html/index.html
  EOF
  )

  # tag_specifications: Launch Template으로 생성되는 리소스에 자동으로 태그 부여
  # resource_type "instance": EC2 인스턴스에 태그
  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name}-app" })
  }

  # resource_type "volume": EBS 볼륨에도 동일하게 태그 (비용 분석 시 필요)
  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { Name = "${var.name}-app-vol" })
  }

  tags = merge(var.tags, { Name = "${var.name}-lt" })

  # create_before_destroy: name_prefix 사용 시 새 리소스를 먼저 만들고 이전 것을 삭제
  # 이렇게 해야 ASG가 이전 LT를 참조하는 동안 삭제되지 않음
  lifecycle {
    create_before_destroy = true
  }
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. Auto Scaling Group
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ASG: 트래픽에 따라 EC2 인스턴스 수를 자동으로 조절하는 서비스
# Scale Out (인스턴스 추가) ← 트래픽 급증 대응
# Scale In  (인스턴스 제거) ← 비용 절감
resource "aws_autoscaling_group" "app" {
  name_prefix = "${var.name}-app-asg-"

  min_size         = var.min_size     # 항상 유지할 최소 인스턴스 수 (0이면 HA 불가)
  max_size         = var.max_size     # Scale Out 최대 한도 (비용 상한선)
  desired_capacity = var.desired_size # 최초 배포 시 목표 인스턴스 수

  # Private NAT 서브넷에 배치
  # Multi-AZ: AZ-a, AZ-c 두 AZ에 분산 → 하나의 AZ 장애 시에도 서비스 유지
  # ASG는 자동으로 인스턴스를 여러 AZ에 균등 배분함
  vpc_zone_identifier = var.subnet_ids

  # ALB Target Group 연결
  # ASG가 새 인스턴스를 시작하면 → 자동으로 Target Group에 등록
  # ASG가 인스턴스를 종료하면 → 자동으로 Target Group에서 제거
  target_group_arns = [var.target_group_arn]

  # 헬스 체크 타입
  # "EC2":  인스턴스 상태(Running/Stopped)만 확인 → 앱이 죽어도 Running이면 통과
  # "ELB":  ALB Target Group 헬스 체크 결과 기준 → 앱이 503 반환하면 불건강으로 판정
  # ELB 타입이 더 안전: 애플리케이션 레벨 장애까지 감지하고 인스턴스 교체
  health_check_type         = "ELB"
  health_check_grace_period = 300
  # grace_period: 인스턴스 시작 후 헬스 체크를 시작하기까지의 유예 시간(초)
  # User Data 실행(dnf install) + nginx 기동 시간을 고려해 300초로 설정
  # 너무 짧으면: 아직 기동 중인 인스턴스를 불건강으로 판정해 바로 종료

  # Launch Template 연결
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest" # 항상 최신 버전 사용
    # "$Latest": Launch Template 변경 시 다음 인스턴스 교체부터 새 버전 적용
    # 특정 버전 고정 예: "3" → 안정성 중시 시 사용 (신중한 롤아웃)
  }

  # Instance Refresh: Launch Template 변경 시 기존 인스턴스를 새 버전으로 롤링 교체
  # 없으면: LT를 변경해도 기존 인스턴스는 그대로 유지 (수동으로 하나씩 교체해야 함)
  instance_refresh {
    strategy = "Rolling" # 순차적으로 교체 (Blue/Green과 달리 추가 인프라 불필요)
    preferences {
      min_healthy_percentage = 50
      # 롤링 중 최소 50%는 정상 상태 유지
      # 예: 인스턴스 2개 → 1개씩 교체 (한 번에 절반까지 동시 교체)
      # prod 환경: 90%로 높여서 서비스 영향 최소화 권장
    }
  }

  # ASG가 생성하는 EC2 인스턴스에 태그를 전파하는 방법
  # 일반 tags 블록과 달리 propagate_at_launch 옵션이 있어서 dynamic 블록 사용
  dynamic "tag" {
    for_each = merge(var.tags, { Name = "${var.name}-app" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true # true: ASG가 시작하는 EC2 인스턴스에도 이 태그 적용
    }
  }

  lifecycle {
    create_before_destroy = true

    # ignore_changes: Scaling Policy가 desired_capacity를 변경해도 Terraform이 원복하지 않음
    # 배경: Terraform apply 시 desired_capacity = 1로 항상 초기화하면
    #       Scaling Policy로 2→3으로 늘어난 인스턴스가 다음 apply 때 1로 줄어버림
    # ignore_changes에 추가하면 Terraform이 이 값을 관리하지 않고 AWS에게 맡김
    ignore_changes = [desired_capacity]
  }
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. Scaling Policy — CPU Target Tracking
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Scaling Policy 종류:
# 1) Simple Scaling    : 특정 이벤트 발생 시 고정 수량 추가/제거 (구형)
# 2) Step Scaling      : CPU 70%→+1, CPU 90%→+3 등 단계별 대응 (세밀한 제어)
# 3) Target Tracking   : 목표값(CPU 60%)을 유지하도록 AWS가 자동으로 Scale In/Out 결정
#                        → 가장 권장, CloudWatch Alarm도 AWS가 자동 생성/관리
resource "aws_autoscaling_policy" "cpu_target" {
  name                   = "${var.name}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    # 사전 정의된 메트릭 (커스텀 메트릭 대신 AWS 제공 메트릭 사용)
    # ASGAverageCPUUtilization: ASG 전체 인스턴스의 평균 CPU 사용률
    # 다른 옵션: ALBRequestCountPerTarget (요청 수 기반), ASGAverageNetworkIn/Out
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = var.cpu_target_value
    # CPU가 60%를 넘으면 → AWS가 인스턴스 추가 (Scale Out)
    # CPU가 60%보다 낮으면 → AWS가 인스턴스 제거 (Scale In)
    # Scale In 쿨다운: 기본 300초 — 급격한 축소를 방지해 안정성 확보

    # scale_in_cooldown  = 300 # Scale In 최소 간격(초) — 기본값 사용
    # scale_out_cooldown = 300 # Scale Out 최소 간격(초) — 기본값 사용
  }
}
