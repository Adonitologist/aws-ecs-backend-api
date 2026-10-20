# Read-only listing of resources that should not exist after terraform destroy. Prints ids/names only.
# Every section should print nothing. Run with AWS credentials in the environment.
# Expected leftover: KMS keys stay in "PendingDeletion" for 7 days after destroy. That is not a failure.
param(
    [string]$Environment = "production",
    [string]$Region = "us-east-1"
)
$r = @("--region", $Region)
$tag = "Name=tag:Project,Values=ecs-backend-api"

function Show($title, $items) {
    Write-Output "== $title"
    $items | Where-Object { $_ } | ForEach-Object { Write-Output $_ }
}

Show "ECS clusters" (aws ecs list-clusters @r --query "clusterArns[?contains(@, 'app-cluster-$Environment')]" --output text)
Show "ECS services" (aws ecs list-services @r --cluster "app-cluster-$Environment" --query "serviceArns" --output text 2>$null)
Show "Load balancers" (aws elbv2 describe-load-balancers @r --query "LoadBalancers[?contains(LoadBalancerName, 'app-alb-$Environment')].LoadBalancerName" --output text)
Show "Target groups" (aws elbv2 describe-target-groups @r --query "TargetGroups[?contains(TargetGroupName, 'app-tg-$Environment')].TargetGroupName" --output text)
Show "RDS instances" (aws rds describe-db-instances @r --query "DBInstances[?contains(DBInstanceIdentifier, 'ecs-backend-db-$Environment')].DBInstanceIdentifier" --output text)
Show "RDS snapshots" (aws rds describe-db-snapshots @r --query "DBSnapshots[?contains(DBInstanceIdentifier, 'ecs-backend-db-$Environment')].DBSnapshotIdentifier" --output text)
Show "ECR repositories" (aws ecr describe-repositories @r --query "repositories[?repositoryName=='app-$Environment'].repositoryName" --output text 2>$null)
Show "Secrets" (aws secretsmanager list-secrets @r --include-planned-deletion --query "SecretList[?contains(Name, 'rds-db-credentials-$Environment')].Name" --output text)
Show "Log groups" (aws logs describe-log-groups @r --query "logGroups[?contains(logGroupName, '$Environment')].logGroupName" --output text)
Show "NAT gateways (not deleted)" (aws ec2 describe-nat-gateways @r --filter $tag --query "NatGateways[?State!='deleted'].NatGatewayId" --output text)
Show "Elastic IPs" (aws ec2 describe-addresses @r --filters $tag --query "Addresses[].AllocationId" --output text)
Show "VPCs" (aws ec2 describe-vpcs @r --filters $tag --query "Vpcs[].VpcId" --output text)
Show "SNS topics" (aws sns list-topics @r --query "Topics[?contains(TopicArn, 'alarms-$Environment')].TopicArn" --output text)
Show "CloudWatch alarms" (aws cloudwatch describe-alarms @r --query "MetricAlarms[?contains(AlarmName, '-$Environment')].AlarmName" --output text)
Show "IAM roles" (aws iam list-roles --query "Roles[?contains(RoleName, '-$Environment')].RoleName" --output text)
$kms = foreach ($id in (aws kms list-keys @r --query "Keys[].KeyId" --output text) -split "\s+") {
    if ($id) {
        aws kms describe-key @r --key-id $id --query "KeyMetadata.[KeyId,KeyState,Description]" --output text
    }
}
Show "KMS keys of this project (PendingDeletion is expected for 7 days)" ($kms | Where-Object { $_ -match "RDS and Secrets|CloudWatch Log Group|alarms SNS" })
