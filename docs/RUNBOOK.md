# Runbook (operator)

Run these commands yourself from the repository root in PowerShell, with AWS credentials in the environment.
Every output goes to `docs/evidence/<name>.txt`. Do not commit raw outputs: they can contain ARNs and the account id.
Step 11 redacts 12-digit numbers; read the files before committing anyway.

Region is `us-east-1` and the environment name is `production` (the defaults). Adjust the names if you override `environment`.

## 0. One-time setup

```powershell
New-Item -ItemType Directory -Force docs/evidence | Out-Null
$env:AWS_DEFAULT_REGION = "us-east-1"
$env:AWS_PROFILE = "your-profile-name"
aws sts get-caller-identity --query Arn --output text > $null; "sts exit $LASTEXITCODE"
Copy-Item terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: replace the placeholder CIDR with your public IP as x.x.x.x/32. Never commit this file.
```

Set `$env:AWS_PROFILE` to your own profile (replace `your-profile-name`); do not use another operator's profile. The credentials check must print `sts exit 0`. Do not paste its output anywhere: the check redirects the ARN to `$null` on purpose, so only the exit code is shown.

Local tfsec scan:

```powershell
tfsec . --no-colour | Tee-Object docs/evidence/16-tfsec.txt
```

This file also goes through the redaction of step 11.

## 1. Init, plan, apply

```powershell
terraform init -no-color 2>&1 | Tee-Object docs/evidence/01-init.txt
./scripts/check-leftovers.ps1 2>&1 | Tee-Object docs/evidence/01b-leftovers-before.txt
```

Every section of the leftovers check must be empty, except KMS keys in `PendingDeletion` and log groups unrelated to this project. If anything else is listed, clean it first and rerun the check. It runs before the plan so the saved plan stays valid.

```powershell
terraform plan -no-color -out tfplan 2>&1 | Tee-Object docs/evidence/02-plan.txt
terraform apply -no-color tfplan 2>&1 | Tee-Object docs/evidence/03-apply.txt
terraform output -no-color 2>&1 | Tee-Object docs/evidence/03-outputs.txt
```

Run the apply once, as a single run saved as `03-apply.txt`. Do not split it across files.

The ECS service is created before the image exists, so its first tasks fail to pull. This is expected until step 2.

## Session variables

Run this block after the apply and before any AWS step. Re-run it in every new terminal: the variables do not survive a closed session. It aborts if any value is empty.

```powershell
$cluster = terraform output -raw cluster_name
$service = terraform output -raw service_name
$tgArn = aws elbv2 describe-target-groups --names app-tg-production --query "TargetGroups[0].TargetGroupArn" --output text
$alb = terraform output -raw alb_dns_name
foreach ($n in "cluster","service","tgArn","alb") {
  $v = Get-Variable $n -ValueOnly
  if (-not $v -or $v -eq "None") { throw "session variable `$$n is empty" }
}
```

## 2. Push the image and roll the service

Preflight: Docker must be running. If this throws, start Docker Desktop and retry.

```powershell
docker info --format '{{.ServerVersion}}'
if ($LASTEXITCODE -ne 0) { throw "docker is not available" }
./scripts/push-image.ps1 2>&1 | Tee-Object docs/evidence/04-push-image.txt
aws ecs update-service --cluster $cluster --service $service --force-new-deployment --query "service.deployments[].[status,rolloutState,runningCount]" --output text 2>&1 | Tee-Object docs/evidence/05-force-deployment.txt
```

ECR tags are immutable. Never push `v1` twice. To ship a new image, push a new tag and apply it as a new plan: `./scripts/push-image.ps1 -Tag v2`, then `terraform apply -var image_tag=v2`.

## 3. Wait for the service to be stable

```powershell
aws ecs wait services-stable --cluster $cluster --services $service 2>&1 | Tee-Object docs/evidence/06-services-stable.txt
aws ecs describe-services --cluster $cluster --services $service --query "services[0].[serviceName,status,desiredCount,runningCount]" --output text 2>&1 | Tee-Object -Append docs/evidence/06-services-stable.txt
aws elbv2 describe-target-health --target-group-arn $tgArn --query "TargetHealthDescriptions[].TargetHealth.State" --output text 2>&1 | Tee-Object docs/evidence/07-target-health.txt
```

## 4. Application checks through the ALB

```powershell
curl.exe -s -i --max-time 10 "http://$alb/health" 2>&1 | Tee-Object docs/evidence/08-health.txt
curl.exe -s -i --max-time 10 "http://$alb/db-check" 2>&1 | Tee-Object docs/evidence/09-db-check.txt
```

`/health` must return 200. `/db-check` must return 200 if the container reached RDS with the injected credentials; a 503 means it did not. Keep the output either way.

## 5. Alarm test with set-alarm-state (manual, not a real failure)

```powershell
aws cloudwatch set-alarm-state --alarm-name alb-unhealthy-hosts-production --state-value ALARM --state-reason "manual test"
Start-Sleep -Seconds 90
aws cloudwatch describe-alarm-history --alarm-name alb-unhealthy-hosts-production --history-item-type StateUpdate --max-items 5 --query "AlarmHistoryItems[].[Timestamp,HistorySummary]" --output text 2>&1 | Tee-Object docs/evidence/10-alarm-manual-test.txt
```

The alarm returns to OK by itself at its next evaluation (within about a minute), so the history should show ALARM and then OK. The file is written once.
If OK is not there yet, rerun only the `describe-alarm-history` command after a minute; it overwrites the file, so no entries are duplicated.
This proves the alarm exists and changes state. It does not prove the metric detects a failure.

## 6. Real trigger

Primary: make the health check fail. The health check runs every 30 seconds (`interval = 30`, `timeout = 5` and `matcher = "200"` are set in `modules/networking/main.tf`) and the target becomes unhealthy after 10 failed checks (`unhealthy_threshold = 10`), so about 300 seconds (10 x 30 s). The matcher is HTTP 200. Then `UnHealthyHostCount` reaches 1 and the alarm can fire.

```powershell
$f = "docs/evidence/11b-real-trigger-bad-path.txt"
"== set bad path" | Tee-Object $f
aws elbv2 modify-target-group --target-group-arn $tgArn --health-check-path /does-not-exist --query "TargetGroups[0].HealthCheckPath" --output text 2>&1 | Tee-Object -Append $f
1..24 | ForEach-Object {
  Get-Date -Format s | Tee-Object -Append $f
  aws elbv2 describe-target-health --target-group-arn $tgArn --query "TargetHealthDescriptions[].TargetHealth.State" --output text 2>&1 | Tee-Object -Append $f
  aws ecs describe-services --cluster $cluster --services $service --query "services[0].[runningCount,pendingCount]" --output text 2>&1 | Tee-Object -Append $f
  aws cloudwatch describe-alarms --alarm-names alb-unhealthy-hosts-production --query "MetricAlarms[].[AlarmName,StateValue]" --output text 2>&1 | Tee-Object -Append $f
  Start-Sleep -Seconds 30
}
```

The loop runs to completion (12 minutes), or press Ctrl+C once the target shows `unhealthy` and the alarm shows `ALARM`; in both cases run the restore block next. Note: ECS replaces tasks that fail ELB health checks, so the target can alternate between `unhealthy`, `initial` and `healthy`; keep the output either way. If neither happens in 12 minutes, that is a valid result: do not claim the alarm fired.

Restore the path and wait until exactly one target is registered and healthy and the alarm is back to OK. This is part of the evidence, do not skip it.

```powershell
"== restore /health" | Tee-Object -Append $f
aws elbv2 modify-target-group --target-group-arn $tgArn --health-check-path /health --query "TargetGroups[0].HealthCheckPath" --output text 2>&1 | Tee-Object -Append $f
foreach ($i in 1..40) {
  Get-Date -Format s | Tee-Object -Append $f
  $states = @((aws elbv2 describe-target-health --target-group-arn $tgArn --query "TargetHealthDescriptions[].TargetHealth.State" --output text) -split '\s+' | Where-Object { $_ })
  $alarm = aws cloudwatch describe-alarms --alarm-names alb-unhealthy-hosts-production --query "MetricAlarms[0].StateValue" --output text
  "targets=$($states -join ',') alarm=$alarm" | Tee-Object -Append $f
  aws ecs describe-services --cluster $cluster --services $service --query "services[0].[runningCount,pendingCount]" --output text 2>&1 | Tee-Object -Append $f
  if ($states.Count -eq 1 -and $states[0] -eq "healthy" -and $alarm -eq "OK") { "== restored" | Tee-Object -Append $f; break }
  Start-Sleep -Seconds 30
}
```

The loop runs up to 40 iterations of 30 s (20 minutes) and stops by itself as soon as both conditions hold. `deregistration_delay = 300` keeps the old target draining, and the alarm in ALARM, for about 5 more minutes after the path is restored, so several iterations with 2 targets or `ALARM` are normal. If `== restored` is not the last line of the file after 40 iterations, rerun the loop.

Then capture the application state after the restore:

```powershell
curl.exe -s -i --max-time 10 "http://$alb/health" 2>&1 | Tee-Object docs/evidence/08b-health-after.txt
curl.exe -s -i --max-time 10 "http://$alb/db-check" 2>&1 | Tee-Object docs/evidence/09b-db-check-after.txt
```

Continue to step 7 only after `== restored` appears.

Fallback (only if the primary trigger is not possible): stop the running task.

```powershell
$task = aws ecs list-tasks --cluster $cluster --service-name $service --query "taskArns[0]" --output text
aws ecs stop-task --cluster $cluster --task $task --reason "alarm test" --query "task.lastStatus" --output text 2>&1 | Tee-Object docs/evidence/11-real-trigger.txt
1..12 | ForEach-Object {
  Get-Date -Format s | Tee-Object -Append docs/evidence/11-real-trigger.txt
  aws elbv2 describe-target-health --target-group-arn $tgArn --query "TargetHealthDescriptions[].TargetHealth.State" --output text 2>&1 | Tee-Object -Append docs/evidence/11-real-trigger.txt
  aws cloudwatch describe-alarms --alarm-names alb-unhealthy-hosts-production alb-target-5xx-production --query "MetricAlarms[].[AlarmName,StateValue]" --output text 2>&1 | Tee-Object -Append docs/evidence/11-real-trigger.txt
  Start-Sleep -Seconds 30
}
```

A stopped task is replaced by the service, and the ALB can drain it without ever reporting it as unhealthy, so UnHealthyHostCount may stay at 0.

## 7. Capture alarm history

```powershell
& { foreach ($a in "alb-unhealthy-hosts-production","alb-target-5xx-production","ecs-cpu-high-production","rds-cpu-high-production","rds-free-storage-low-production") {
  "== $a"
  aws cloudwatch describe-alarm-history --alarm-name $a --history-item-type StateUpdate --query "AlarmHistoryItems[].[Timestamp,HistorySummary]" --output text
} } 2>&1 | Tee-Object docs/evidence/12-alarm-history.txt
```

## 8. Destroy

```powershell
terraform destroy -no-color -auto-approve 2>&1 | Tee-Object docs/evidence/13-destroy.txt
$state = terraform state list 2>&1; $rc = $LASTEXITCODE
if ($rc -ne 0) { throw "terraform state list failed (exit $rc): $state" }
"terraform state list exit $rc, lines: $(@($state | Where-Object { $_ }).Count)" | Tee-Object docs/evidence/13b-state-after-destroy.txt
if (@($state | Where-Object { $_ }).Count -gt 0) { $state | Tee-Object -Append docs/evidence/13b-state-after-destroy.txt }
```

After a complete destroy, `13b-state-after-destroy.txt` must contain only `terraform state list exit 0, lines: 0`. If it lists resources, the destroy is incomplete. If destroy fails or times out, rerun `terraform destroy -no-color -auto-approve` (append to the same file) until it succeeds, then run step 9 anyway. Never leave the stack half destroyed.

## 9. Check leftovers

```powershell
./scripts/check-leftovers.ps1 2>&1 | Tee-Object docs/evidence/14-leftovers.txt
```

Every section should be empty. The one expected exception: the KMS keys stay in `PendingDeletion` for 7 days after destroy (the configured deletion window). That is not a failure.

After the check, look again for the VPC flow log group. In run 2 it reappeared after a complete destroy, created by something other than Terraform (no retention, no tags):

```powershell
aws logs describe-log-groups --log-group-name-prefix /aws/vpc/flow-log/production --query "logGroups[].[logGroupName,retentionInDays,storedBytes]" --output text
```

If it is listed and `terraform state list` is empty, delete it by hand and rerun the check:

```powershell
aws logs delete-log-group --log-group-name /aws/vpc/flow-log/production
./scripts/check-leftovers.ps1 2>&1 | Tee-Object docs/evidence/14b-leftovers-after-cleanup.txt
```

The leftover script matches by name, so it also lists `/aws/lambda/event-processor-production`. That log group is not part of this stack: do not delete it.

## 10. Local state

`terraform.tfstate` is local and holds the generated database password. It is git-ignored; do not copy it anywhere.

## 11. Redact before committing

`Tee-Object` writes UTF-16 in Windows PowerShell 5.1, which breaks the replacements and the search. Convert first:

```powershell
Get-ChildItem docs/evidence -File | ForEach-Object { $t = Get-Content $_.FullName -Raw; Set-Content -Path $_.FullName -Value $t -Encoding utf8 }
```

Redact 12-digit numbers (the `-Encoding utf8` is a deliberate small deviation from the plain one-liner, to keep the files UTF-8):

```powershell
Get-ChildItem docs/evidence -File | ForEach-Object { $f = $_.FullName; (Get-Content $f) -replace '\b\d{12}\b','111111111111' | Set-Content -Encoding utf8 $f }
```

Second pass for IPv4. Plan and apply output contain your public IP from `allowed_ingress_cidrs`:

```powershell
Get-ChildItem docs/evidence -File | ForEach-Object { $f = $_.FullName; (Get-Content $f) -replace '\b(?!10\.|0\.0\.0\.0|127\.|172\.17\.|203\.0\.113\.)\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b','203.0.113.1' | Set-Content -Encoding utf8 $f }
```

Final check. It prints only file name and line number; every list must be empty:

```powershell
$files = Get-ChildItem docs/evidence -File
$files | Select-String -Pattern '\b(?!10\.|0\.0\.0\.0|127\.|172\.17\.|203\.0\.113\.)\d{1,3}(\.\d{1,3}){3}\b' | ForEach-Object { "$($_.Filename):$($_.LineNumber) ipv4" }
$files | Select-String -Pattern 'arn:aws[a-z-]*:[^:\s]+:[^:\s]*:(?!111111111111(:|$)|aws:)[^:\s]+:' | ForEach-Object { "$($_.Filename):$($_.LineNumber) arn" }
$files | Select-String -Pattern 'AKIA' -CaseSensitive | ForEach-Object { "$($_.Filename):$($_.LineNumber) akia" }
```

Rule: ARNs may stay only with the placeholder account id `111111111111`. Fix every reported line by hand, then repeat the check.

## 12. CI evidence

Run this after the redaction and after CI has finished on the commit that contains these changes:

```powershell
gh run list --limit 5 | Tee-Object docs/evidence/15-ci-runs.txt
```

Pick the run id of that commit from the list yourself (the operator chooses it, not Claude), then replace RUN_ID with the number from the list; never paste the angle brackets:

```powershell
gh run view "RUN_ID" | Tee-Object docs/evidence/15-ci-run.txt
```

Both files go through the same redaction as step 11 (UTF-8 conversion, 12-digit numbers, IPv4, final check).
