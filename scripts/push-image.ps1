# Builds app/ and pushes it to the ECR repository created by Terraform.
# Run from the repository root after terraform apply. Requires AWS credentials in the environment.
param(
    [string]$Tag = "v1",
    [string]$Region = "us-east-1"
)
$ErrorActionPreference = "Stop"

$repoUrl = (terraform output -raw ecr_repository_url).Trim()
$registry = $repoUrl.Split("/")[0]

aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin $registry
docker build -t "app:$Tag" app/
docker tag "app:$Tag" "${repoUrl}:$Tag"
docker push "${repoUrl}:$Tag"
