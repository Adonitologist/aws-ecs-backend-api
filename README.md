# AWS ECS Fargate Backend API

![Terraform CI](https://github.com/Adonitologist/aws-ecs-backend-api/actions/workflows/ci.yml/badge.svg)
![Terraform](https://img.shields.io/badge/IaC-Terraform_v1.5+-844FBA?logo=terraform)
![AWS](https://img.shields.io/badge/AWS-ECS_Fargate_%7C_RDS_%7C_ALB-232F3E?logo=amazon-aws)
![Security](https://img.shields.io/badge/Security-Secrets_Manager_%7C_KMS-success)

Terraform reference project: a small Python API on Amazon ECS Fargate behind an Application Load Balancer, backed by PostgreSQL on Amazon RDS, with database credentials injected from AWS Secrets Manager and CloudWatch alarms. CI is configured to validate the Terraform and to build and scan the container image. The stack is configured to be destroyed with one `terraform destroy`.

## System Architecture

```mermaid
flowchart TD
    Client([User Browser]) -->|HTTP| ALB[Application Load Balancer\nPublic Subnets]
    ALB -->|Port 8080, health check /health| ECS[ECS Fargate Service\nPrivate Subnets]
    ECS -->|DB_CREDENTIALS secret injection| SM[AWS Secrets Manager]
    ECS -->|SQL Port 5432| RDS[(RDS PostgreSQL\nPrivate Subnets)]
    ECR[ECR repository] -->|image pull| ECS
    ALB -.->|metrics| CW[CloudWatch alarms] -.-> SNS[SNS topic]

    subgraph CI
        GA[GitHub Actions] --> V[fmt, validate, tflint, tfsec]
        GA --> D[docker build + Trivy scan]
    end
```

## What is in the repository

| Path | Content |
|---|---|
| `modules/networking` | VPC, 2 public and 2 private subnets, NAT gateway, ALB, target group, security groups, VPC flow logs |
| `modules/database` | RDS PostgreSQL 15 (single instance), KMS key, Secrets Manager secret with a generated password |
| `modules/ecs` | ECR repository, ECS cluster, task definition, service, IAM roles, log group, autoscaling (present in code, not exercised) |
| `modules/monitoring` | SNS topic and 5 CloudWatch alarms: unhealthy hosts, target 5xx, ECS CPU, RDS CPU, RDS free storage |
| `app/` | Python service (standard library plus `pg8000`): `GET /health`, `GET /db-check` |
| `scripts/` | `push-image.ps1`, `check-leftovers.ps1` |
| `docs/RUNBOOK.md` | Ordered commands to deploy, test, destroy and check leftovers |
| `tests/` | Terratest (see Limitations) |

How it works in the code:

- **Secrets:** the task definition has a `secrets` block with `valueFrom` pointing to the Secrets Manager secret. The container receives the JSON in one environment variable, `DB_CREDENTIALS`. The execution role can read that secret and decrypt it with the KMS key.
- **Endpoints:** `/health` returns 200 without touching the database. `/db-check` connects to RDS, runs `SELECT 1` and returns 200 or 503. It does not log the password.
- **Destroyability:** ECR `force_delete`, RDS without final snapshot, deletion protection and backups, secret without recovery window, Container Insights off (it would create a log group Terraform does not manage).

## Usage

Everything is run by the operator; see [docs/RUNBOOK.md](docs/RUNBOOK.md) for the exact order.

```text
cp terraform.tfvars.example terraform.tfvars   # set allowed_ingress_cidrs to your IP; the file is git-ignored
terraform init
terraform apply
./scripts/push-image.ps1
terraform destroy
```

Terraform state is local (no remote backend) and contains the generated database password. The state file is git-ignored.

After `terraform destroy`, the KMS keys remain in `PendingDeletion` for 7 days. This is expected.

## Security notes (tfsec)

CI runs `tfsec` as a single gate. These findings are suppressed inline, on purpose:

*   `aws-elb-http-not-used`: the ALB listens on HTTP port 80. HTTPS needs an ACM certificate and a domain, which this project does not use.
*   `aws-elb-alb-not-public`: the ALB is public so the service can be reached from a browser without a VPN or bastion. Access is limited by the `allowed_ingress_cidrs` variable.
*   `aws-ec2-no-public-ingress-sgr`: the ALB security group ingress comes from a variable; if you set a public range, the finding applies.
*   `aws-ec2-no-public-egress-sgr`: ECS tasks have egress on 443 to `0.0.0.0/0` (ECR, Secrets Manager and CloudWatch through the NAT gateway).
*   `aws-cloudwatch-log-group-customer-key`: the VPC flow log group uses the default AWS encryption.
*   `aws-iam-no-policy-wildcards`: the flow log policy uses a trailing `:*` on its own log group ARN, required for log streams.
*   `aws-ecs-enable-container-insight`: Container Insights is off so no unmanaged log group survives destroy.
*   `aws-ecr-repository-customer-key`: the ECR repository uses default AWS encryption.
*   `aws-rds-enable-deletion-protection`, `aws-rds-specify-backup-retention`: off so the stack can be destroyed completely.

Credentials: no credentials are in the source files. The generated database password does exist in the Terraform state.

`allowed_ingress_cidrs` has no default; set it in `terraform.tfvars`.

## Limitations

- **Not deployed or verified yet:** nothing in this repository has been applied from the current code. See the "Verified" section once evidence exists.
- **Terratest: NOT VERIFIED.** `tests/ecs_backend_test.go` runs a real `apply` and `destroy`, needs AWS credentials, has no `go.mod`, does not pass the required `allowed_ingress_cidrs` variable, and no CI job runs it.
- HTTP only, no TLS. The ALB is public.
- RDS is a single instance (`multi_az` is not set). Subnets span two AZs, but the service runs one task. No automated backups.
- The app connects to RDS over TLS without verifying the server certificate.
- Autoscaling policies exist in the code and have not been exercised.
- CI does not run `terraform apply` and has no AWS credentials. The Trivy scan runs only on the built image, not on the deployed one.
- Terraform state is local.
