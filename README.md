# AWS ECS Fargate Backend API

![Terraform CI](https://github.com/Adonitologist/aws-ecs-backend-api/actions/workflows/ci.yml/badge.svg)
![Terraform](https://img.shields.io/badge/IaC-Terraform_v1.5+-844FBA?logo=terraform)
![AWS](https://img.shields.io/badge/AWS-ECS_Fargate_%7C_RDS_%7C_ALB-232F3E?logo=amazon-aws)
![Security](https://img.shields.io/badge/Security-Secrets_Manager_%7C_KMS-success)

Terraform reference project: a small Python API on Amazon ECS Fargate behind an Application Load Balancer, backed by PostgreSQL on Amazon RDS, with database credentials injected from AWS Secrets Manager and CloudWatch alarms. CI is configured to validate the Terraform and to build and scan the container image. The stack is configured to be destroyed with one `terraform destroy`.

## Verified

Two deployments in us-east-1, each followed by `terraform destroy`: run 1 on 2026-10-20 (`docs/evidence-run1/`) and run 2 on 2026-10-21 (`docs/evidence/`). Each item states only what the linked file shows. Times are local (UTC+2).

- **Endpoints through the ALB:** `GET /health` and `GET /db-check` returned 200 in run 2 ([08-health.txt](docs/evidence/08-health.txt), [09-db-check.txt](docs/evidence/09-db-check.txt)), again after the alarm test ([08b-health-after.txt](docs/evidence/08b-health-after.txt), [09b-db-check-after.txt](docs/evidence/09b-db-check-after.txt)), and in run 1 ([08-health.txt](docs/evidence-run1/08-health.txt), [09-db-check.txt](docs/evidence-run1/09-db-check.txt)). `/db-check` read `DB_CREDENTIALS`, injected from Secrets Manager, and ran `SELECT 1`.
- **Service state:** the ECS service was ACTIVE with 1 of 1 tasks running in both runs ([run 2](docs/evidence/06-services-stable.txt), [run 1](docs/evidence-run1/06-services-stable.txt)). Run 1 also shows a healthy target ([07-target-health.txt](docs/evidence-run1/07-target-health.txt)).
- **Local container test:** the image ran as non-root (uid 999), `GET /health` returned 200 and `GET /db-check` returned 503 without a database, as expected ([00-local-docker.txt](docs/evidence-run1/00-local-docker.txt)).
- **Image push:** `push-image.ps1` pushed tag `v1` in run 2 ([04-push-image.txt](docs/evidence/04-push-image.txt)). A second push of `v1` was rejected because the tag is immutable ([04-push.txt](docs/evidence/04-push.txt)).
- **Apply, run 1 (interrupted):** the first apply failed with `ResourceAlreadyExistsException` on the log group `/aws/vpc/flow-log/production` ([03-apply.txt](docs/evidence-run1/03-apply.txt)). The remaining 3 resources, including that log group, were created in a later apply ([03c-apply.txt](docs/evidence-run1/03c-apply.txt)), so the pre-existing group had been removed before it. A note written on 2026-10-21, after the fact and from the operator's terminal output of 2026-10-20, records that the group was created 2026-09-20, held 167 bytes, had no tags and no flow log attached, and was deleted with `aws logs delete-log-group` before the apply was resumed ([03d-orphan-log-group-note.txt](docs/evidence-run1/03d-orphan-log-group-note.txt)). The deletion command itself is not captured.
- **Apply, run 2 (single run):** one apply, 51 added, no error ([03-apply.txt](docs/evidence/03-apply.txt)). The leftover check before the plan found no resources of this stack ([01b-leftovers-before.txt](docs/evidence/01b-leftovers-before.txt)).
- **Manual alarm tests (not detection):** `alb-unhealthy-hosts-production` was forced with `set-alarm-state`. Run 2: OK -> ALARM at 14:22:22 and back to OK at 14:23:00 ([10-alarm-manual-test.txt](docs/evidence/10-alarm-manual-test.txt)), and a second forced ALARM at 21:23:26 with state reason `manual test` ([05-alarm-history.txt](docs/evidence/05-alarm-history.txt)); that history was captured before the return to OK. Run 1: 14:27:14 to 14:28:05 ([10-alarm-manual-test.txt](docs/evidence-run1/10-alarm-manual-test.txt)). These show that the alarm exists and changes state. They do not show that it detects a failure.
- **Real trigger, run 2:** a bad health check path was set at about 14:24. The target became unhealthy at 14:28:45 and the alarm went OK -> ALARM at 14:31:00 with state reason "1 datapoint [1.0] was greater than the threshold (0.0)", without `set-alarm-state`. After `/health` was restored the alarm returned to OK at 14:45:00 and the loop ended with one healthy target ([11b-real-trigger-bad-path.txt](docs/evidence/11b-real-trigger-bad-path.txt), [05-alarm-history.txt](docs/evidence/05-alarm-history.txt)).
- **Real trigger, run 1:** the target became unhealthy at 14:42:43 and the alarm went OK -> ALARM at 14:45:05 on 2026-10-20. The return to OK was **not observed**: the file ends with the alarm still in ALARM ([11b-real-trigger-bad-path.txt](docs/evidence-run1/11b-real-trigger-bad-path.txt), [12-alarm-history.txt](docs/evidence-run1/12-alarm-history.txt)).
- **Other alarms:** the other four alarms exist and only went from INSUFFICIENT_DATA to OK in run 1; they were not triggered ([12-alarm-history.txt](docs/evidence-run1/12-alarm-history.txt)).
- **Destroy, run 1:** 51 resources destroyed ([13-destroy.txt](docs/evidence-run1/13-destroy.txt)), 0 in state afterwards ([13b-state-after-destroy.txt](docs/evidence-run1/13b-state-after-destroy.txt)). The leftover check found remains ([14-leftovers.txt](docs/evidence-run1/14-leftovers.txt)); they were cleaned manually ([14b-leftovers-after-cleanup.txt](docs/evidence-run1/14b-leftovers-after-cleanup.txt)).
- **Destroy, run 2:** 51 resources destroyed ([06-destroy-tail.txt](docs/evidence/06-destroy-tail.txt), copied from the terminal because a rerun overwrote the full log); a rerun found nothing to destroy ([06b-destroy-rerun-noop.txt](docs/evidence/06b-destroy-rerun-noop.txt)). The leftovers before the destroy are in [06a-leftovers-before-destroy.txt](docs/evidence/06a-leftovers-before-destroy.txt). After the destroy a log group `/aws/vpc/flow-log/production` existed again, not created by Terraform (see Limitations); once deleted by hand the check showed only an unrelated Lambda log group and 6 KMS keys in PendingDeletion ([07b-flowlog-group-recreated.txt](docs/evidence/07b-flowlog-group-recreated.txt), [07-leftovers-after-destroy.txt](docs/evidence/07-leftovers-after-destroy.txt)).
- **CI:** the validation and container-scan workflow (jobs: Validate & Security Scan, Docker Build & Trivy Scan) completed successfully on the commit that added the earlier version of this section ([15-ci-run.txt](docs/evidence-run1/15-ci-run.txt), [15-ci-runs.txt](docs/evidence-run1/15-ci-runs.txt)).

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

After `terraform destroy`, the KMS keys remain in `PendingDeletion` for 7 days. This is expected. Check for a re-created `/aws/vpc/flow-log/production` log group and delete it by hand (RUNBOOK step 9).

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

- **Terratest: NOT VERIFIED.** `tests/ecs_backend_test.go` runs a real `apply` and `destroy`, needs AWS credentials, has no `go.mod`, does not pass the required `allowed_ingress_cidrs` variable, and no CI job runs it.
- **Two runs only:** everything in "Verified" comes from two deployments. The alarm return to OK was observed in run 2 only, not in run 1.
- **Alarm evidence:** the manual `set-alarm-state` tests prove only that the alarm exists and changes state. Detection is shown only by the real triggers (run 2 in full, run 1 up to ALARM), for one alarm.
- **Deployment role:** the deployment used an assumable IAM role, created manually outside this repository, so it cannot be reproduced from the repo. It is scoped by service and by region (us-east-1), with IAM actions limited to this project's role and policy names. It is not scoped per resource: the service statement uses `Resource: "*"`. [docs/iam/deploy-policy.json](docs/iam/deploy-policy.json) is an export of its policy with the account id replaced by `ACCOUNT_ID`. One denial was recorded: `aws lambda list-functions` with this role failed with `AccessDeniedException` ([08-role-scope-denied.txt](docs/evidence/08-role-scope-denied.txt)); this is an operator observation of a single action, not a full permission test.
- **Immutable image tag:** ECR tags are immutable and `push-image.ps1` pushes `v1` by default. A second push of `v1` fails with "tag is immutable" ([04-push.txt](docs/evidence/04-push.txt)). A new image needs a new tag (`-Tag v2`, then `terraform apply -var image_tag=v2`).
- **Log group after destroy:** after `terraform destroy` (51 destroyed, nothing left in state), a log group `/aws/vpc/flow-log/production` existed again, created at 21:37 with no retention and no tags, so not by Terraform. The cause was not determined. It was deleted by hand; this is a post-destroy step in the runbook ([07b-flowlog-group-recreated.txt](docs/evidence/07b-flowlog-group-recreated.txt)).
- **Leftover script is name-based:** `check-leftovers.ps1` matches on the environment name, so it also lists `/aws/lambda/event-processor-production`, which is not part of this stack. Six KMS keys remain in PendingDeletion by design (7-day window, [07-leftovers-after-destroy.txt](docs/evidence/07-leftovers-after-destroy.txt)).
- **Not exercised:** autoscaling and the other four alarms.
- HTTP only, no TLS. The ALB is public.
- RDS is a single instance (`multi_az` is not set). Subnets span two AZs, but the service runs one task. No automated backups.
- The app connects to RDS over TLS without verifying the server certificate.
- Autoscaling policies exist in the code and have not been exercised.
- CI does not run `terraform apply` and has no AWS credentials. The Trivy scan runs only on the built image, not on the deployed one.
- Terraform state is local.
