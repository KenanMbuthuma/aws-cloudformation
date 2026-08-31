# Python CDK multi-environment delivery pipeline

This directory contains a CloudFormation-defined CI/CD pipeline for an existing
Python AWS CDK application. It implements this fixed promotion path:

```text
GitHub -> Validate/Build/Synth -> Deploy Dev -> Deploy Test
       -> Manual approval -> Deploy Production
```

## Repository inspection result

At generation time, this directory contained only `.claude`; no `cdk.json`,
`requirements.txt`, Python CDK entry point, stack definitions, or existing
environment configuration were present. Consequently, the template does not
invent an application path or stack name. `CdkAppPath` and `CdkStackNames` must
be set to match the connected GitHub repository. The existing CDK application
itself is not modified.

## Architecture

- A GitHub source action uses an existing AWS CodeConnections connection. No
  OAuth token is stored in CloudFormation.
- One CodeBuild project uses the AWS-managed Ubuntu 24.04 standard 8.0 image,
  Python 3.12, Node.js 22, and `buildspec.yml`.
- The validation action installs dependencies, byte-compiles Python, runs
  `pytest` when `tests/test_*.py` exists, and runs `cdk synth`.
- Dev, Test, and Production actions each start a clean CodeBuild run, install
  dependencies, synthesize with the target context, and run `cdk deploy`.
- Separate pipeline stages make deployments sequential. A CodePipeline manual
  approval action gates Production.
- An encrypted, versioned, private S3 bucket stores artifacts and is retained if
  the pipeline stack is deleted, protecting build evidence from accidental loss.

The pipeline is deployed in a central tools/pipeline account. CodeBuild remains
in that account and the CDK CLI assumes the standard modern-bootstrap roles in
each target account. The target accounts therefore do not need access to the
CodePipeline artifact bucket.

## Prerequisites

1. AWS CLI credentials able to deploy IAM, S3, CodeBuild, and CodePipeline
   resources in the pipeline account.
2. A GitHub CodeConnections connection created in the same account and Region
   as the pipeline. Complete its GitHub authorization so its status is
   `AVAILABLE`; connections created by CloudFormation or CLI start as `PENDING`.
3. AWS CDK v2 and AWS CLI available on the workstation used to bootstrap.
4. Each target account/Region bootstrapped with the modern CDK bootstrap stack.
5. The GitHub repository contains `buildspec.yml` at its root. Copy the file from
   this directory into the application repository if this directory is not that
   repository.
6. The CDK app accepts context such as `-c environment=dev` and uses the passed
   account/Region (see **Application integration** below).

## Required parameters

| Parameter | Meaning |
|---|---|
| `ConnectionArn` | Existing, `AVAILABLE` GitHub CodeConnections ARN |
| `RepositoryOwner` / `RepositoryName` | Case-sensitive GitHub owner and repository |
| `RepositoryBranch` | Source branch; defaults to `main` |
| `DevAccountId`, `TestAccountId`, `ProductionAccountId` | 12-digit target account IDs |
| `DevRegion`, `TestRegion`, `ProductionRegion` | Target AWS Regions |
| `CdkAppPath` | Path from repository root to the directory containing `cdk.json`; defaults to `.` |
| `CdkStackNames` | Space-separated stack IDs/patterns, or `--all` (default) |
| `EnvironmentContextKey` | Context key receiving `dev`, `test`, or `prod`; defaults to `environment` |
| `BootstrapQualifier` | Bootstrap qualifier; defaults to `hnb659fds` |
| `CdkCliVersion` | `latest` by default; pin an exact CDK 2.x version for reproducibility |

`PipelineName` is optional and defaults to `python-cdk-multi-environment`.

## Cross-account bootstrapping

First determine the pipeline account ID—the account where this CloudFormation
stack will run:

```bash
aws sts get-caller-identity --query Account --output text
```

Using administrator credentials for each target account, bootstrap every
account/Region pair and trust the pipeline account. Run from the CDK application
directory so CDK can evaluate any application-specific bootstrap requirements:

```bash
cdk bootstrap aws://DEV_ACCOUNT_ID/DEV_REGION \
  --trust PIPELINE_ACCOUNT_ID \
  --cloudformation-execution-policies arn:aws:iam::aws:policy/AdministratorAccess \
  --termination-protection

cdk bootstrap aws://TEST_ACCOUNT_ID/TEST_REGION \
  --trust PIPELINE_ACCOUNT_ID \
  --cloudformation-execution-policies arn:aws:iam::aws:policy/AdministratorAccess \
  --termination-protection

cdk bootstrap aws://PRODUCTION_ACCOUNT_ID/PRODUCTION_REGION \
  --trust PIPELINE_ACCOUNT_ID \
  --cloudformation-execution-policies arn:aws:iam::aws:policy/AdministratorAccess \
  --termination-protection
```

`AdministratorAccess` is only an example bootstrap execution policy. For least
privilege, replace it with one or more customer-managed policies containing only
the AWS actions and resources that the application stacks provision. The
pipeline's own IAM role is narrowly limited to assuming the named deploy,
lookup, file-publishing, and image-publishing roles for the configured
account/Region pairs. If using a non-default qualifier, add the same
`--qualifier` value to every bootstrap command and set `BootstrapQualifier`.

When all environments share the pipeline account, bootstrap them normally; the
same role mechanism works for same-account deployments. `--trust` may be omitted
for the pipeline account itself, but the execution policy is still required if
you supply `--trust`.

## Deploy the pipeline stack

Keep `codepipeline-cdk.yaml` locally, and ensure `buildspec.yml` is committed at
the GitHub repository root. Then deploy in the pipeline account/Region:

```bash
aws cloudformation deploy \
  --template-file codepipeline-cdk.yaml \
  --stack-name python-cdk-pipeline \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    ConnectionArn=arn:aws:codestar-connections:REGION:PIPELINE_ACCOUNT_ID:connection/CONNECTION_ID \
    RepositoryOwner=GITHUB_OWNER \
    RepositoryName=GITHUB_REPOSITORY \
    RepositoryBranch=main \
    CdkAppPath=path/to/cdk-app \
    CdkStackNames=MyApplicationStack \
    DevAccountId=111111111111 DevRegion=af-south-1 \
    TestAccountId=222222222222 TestRegion=af-south-1 \
    ProductionAccountId=333333333333 ProductionRegion=af-south-1
```

For multiple stack names, quote the entire override value according to your
shell. Using `CdkStackNames=--all` avoids shell-specific handling.

## Deployment behavior

The Build/Synth stage validates against the Dev account and context. This lets
CDK context lookups run before promotion. Dev deploys first; only success starts
Test. After Test succeeds, the execution waits for approval in the CodePipeline
console (or API). Approval starts Production; rejection or expiry stops it.

Each environment receives these values:

```text
-c <EnvironmentContextKey>=dev|test|prod
-c target_account=<configured account ID>
-c target_region=<configured Region>
CDK_DEFAULT_ACCOUNT=<configured account ID>
CDK_DEFAULT_REGION=<configured Region>
```

The source revision is packaged once by Build/Synth and that exact `BuildOutput`
artifact is used by all three deployment actions.

## Application integration

A common Python CDK entry point can consume the values as follows (adapt to the
existing app rather than replacing it):

```python
deployment_environment = app.node.try_get_context("environment")
account = app.node.try_get_context("target_account")
region = app.node.try_get_context("target_region")

MyStack(
    app,
    f"my-application-{deployment_environment}",
    env=cdk.Environment(account=account, region=region),
    deployment_environment=deployment_environment,
)
```

If the app already uses a key such as `stage`, set `EnvironmentContextKey=stage`.
The fixed `target_account` and `target_region` context values are also available.
If configuration comes from `cdk.json`, `cdk.context.json`, or another checked-in
file, map the three environment names there. If stack IDs differ by environment,
prefer a stable selector/pattern accepted by `cdk deploy`, or use `--all`.

The build expects `requirements.txt` or `pyproject.toml` in `CdkAppPath`. Tests
are run only when files matching `tests/test_*.py` exist; ensure `pytest` is then
included in the application's development/build dependencies. Docker is disabled
for least privilege. If the CDK app builds Docker image assets, set
`PrivilegedMode: true` in `CdkCodeBuildProject` and review that security tradeoff.

## Values still required before deployment

- An authorized, `AVAILABLE` connection ARN.
- Repository owner, repository name, and the correct branch.
- All three target account IDs and Regions.
- The actual CDK application path and stack selector(s), because no app was
  present in this workspace to discover them.
- Target-account bootstrap execution policies appropriate for the resources the
  CDK stacks create.
- Confirmation that the app consumes the supplied context names, or matching
  customization of `buildspec.yml` / `EnvironmentContextKey`.
