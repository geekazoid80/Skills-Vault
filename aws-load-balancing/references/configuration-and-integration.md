# AWS load-balancer configuration and integration

The working configuration: ALB listener rules and actions, target types, health-check parameters, ACM/TLS, AWS WAF, Cognito auth, NLB TLS and PrivateLink, sticky sessions, and the Terraform. Internals are in `elb-architecture.md`; selection and operations in `operations.md`.

## ALB listener rules

| Match type | Description | Example |
|---|---|---|
| Path-based | URL path pattern | `/api/*` -> API target group |
| Host-based | Host header | `api.example.com` -> API targets |
| Header-based | HTTP header | `X-Version: v2` -> v2 targets |
| Query string | URL parameters | `?version=2` -> v2 targets |
| Source IP | Client CIDR | `10.0.0.0/8` -> internal targets |
| HTTP method | Request method | `POST` -> write targets |

Actions: forward, redirect, fixed-response, authenticate-cognito, authenticate-oidc. Rules are priority-ordered (low first); conditions AND, values OR.

### Weighted target groups (canary / blue-green)

```
Listener rule action: forward
  blue-tg:  weight 90
  green-tg: weight 10
```

Shifts traffic without DNS changes. Available on ALB and (Nov 2025) NLB.

## Target types

| Type | Use case |
|---|---|
| Instance | Standard EC2 |
| IP | On-prem via VPN/DX, ECS tasks, EKS pods, containers |
| Lambda | Serverless backends (ALB only) |
| ALB | An ALB behind an NLB (static IP + L7 routing) |

## Health checks

Use a dedicated `/healthz` (not the homepage), healthy threshold 2 (fast recovery), unhealthy threshold 3 (tolerate transients), and match expected codes explicitly. For NLB TCP checks, verify both the port and application readiness. Mind NLB's 10s minimum interval (see the timing maths in `elb-architecture.md`).

## ACM and TLS

ACM provides free, auto-renewed certificates deployed to the load balancer. The certificate must be in the same region as the ALB/NLB (us-east-1 for CloudFront). Use a modern TLS policy, e.g. `ELBSecurityPolicy-TLS13-1-2-2021-06`. Non-ACM certificates and private-key handling: see `cert-manager`/`lets-encrypt` and `secrets-hygiene`.

## AWS WAF v2

Attaches directly to an ALB: AWS Managed Rules (OWASP), Bot Control, Account Takeover Prevention; custom IP-set, geo-match, regex, and rate-based rules; actions allow/block/count/CAPTCHA/challenge; logging to CloudWatch, S3, or Kinesis Firehose. Place WAF on the ALB after TLS termination so it inspects plaintext.

## Cognito / OIDC authentication

```
Client -> ALB -> Cognito User Pool
  unauthenticated: redirect to the Cognito login page
  authenticated:   ALB validates the JWT, forwards to the target,
                   adding x-amzn-oidc-identity and x-amzn-oidc-data
```

## NLB TLS and PrivateLink

TLS termination (NLB terminates, plaintext to targets) or passthrough (target owns TLS); mTLS is ALB-only. PrivateLink requires NLB: expose the service on the NLB, the consumer creates an interface VPC endpoint; traffic stays on the AWS backbone, cross-account and cross-region. QUIC pass-through forwards UDP 443 unmodified.

## Sticky sessions

Target-group attributes: `stickiness.enabled`, `stickiness.type` = `lb_cookie` (ALB-generated `AWSALB`, 1s-7d) or `app_cookie` (application cookie). Prefer stateless backends where possible (see `load-balancer-selection`).

## Terraform

```hcl
resource "aws_lb" "app" {
  name               = "app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_target_group" "app" {
  name     = "app-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  health_check {
    path                = "/healthz"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
    matcher             = "200"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.app.arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
  condition {
    path_pattern { values = ["/api/*"] }
  }
}
```

The security group on the ALB is mandatory; an NLB takes none, so the target security groups must admit the client or LB subnet. CloudFormation and CDK follow the same resource shapes (`aws_lb`, `aws_lb_target_group`, `aws_lb_listener`).
