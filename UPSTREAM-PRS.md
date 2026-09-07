# Upstream pull requests and issues: review status

Upstream: `aws-solutions-library-samples/guidance-for-multi-provider-generative-ai-gateway-on-aws`,
reviewed against `main` at `122b72d` on 2026-09-07. Each open PR was merge-tested against that
commit in a throwaway worktree and the non-trivial ones were independently re-verified.

Legend: **Merge** = fine as is. **Merge with changes** = worth merging after the listed fixes.
**Superseded** = the useful part exists elsewhere. "For us" = what this fork does with it.

## Open pull requests

| PR | Title (short) | Recommendation | Applies cleanly to main | For us |
|----|---------------|----------------|-------------------------|--------|
| [#155](https://github.com/aws-solutions-library-samples/guidance-for-multi-provider-generative-ai-gateway-on-aws/pull/155) | Separate CloudFront certificate + ap-northeast-2 models + middleware streaming fix | **Merge with changes** | yes | middleware hunk adopted (`fix/middleware-streaming-done`) |
| [#151](https://github.com/aws-solutions-library-samples/guidance-for-multi-provider-generative-ai-gateway-on-aws/pull/151) | Remove Service Catalog AppRegistry (with comment) | **Merge** (prefer over #149) | yes | adopted verbatim (`fix/remove-appregistry`) |
| [#150](https://github.com/aws-solutions-library-samples/guidance-for-multi-provider-generative-ai-gateway-on-aws/pull/150) | Dependabot: scripts litellm 1.83.7 to 1.93.0 | **Merge with changes** | yes | superseded by our pin to 1.100.0 (`chore/litellm-v1.100.0`) |
| [#149](https://github.com/aws-solutions-library-samples/guidance-for-multi-provider-generative-ai-gateway-on-aws/pull/149) | Remove Service Catalog AppRegistry | **Merge** (duplicate of #151) | yes | see #151 |
| [#147](https://github.com/aws-solutions-library-samples/guidance-for-multi-provider-generative-ai-gateway-on-aws/pull/147) | EKS without Route53 / custom domain | **Merge with changes** | yes (duplicate `requests` line) | not applicable (ECS) |
| [#146](https://github.com/aws-solutions-library-samples/guidance-for-multi-provider-generative-ai-gateway-on-aws/pull/146) | Fix hard-coded VPC ID in delete-fake-llm script | **Merge** | yes | not applicable (load-testing stack unused) |
| [#139](https://github.com/aws-solutions-library-samples/guidance-for-multi-provider-generative-ai-gateway-on-aws/pull/139) | ALB security group: CloudFront prefix list; LiteLLM 1.81.12 | **Merge with changes** | **no** (`.env.template`) | not adopted; our allow-list covers the non-CloudFront case |
| [#135](https://github.com/aws-solutions-library-samples/guidance-for-multi-provider-generative-ai-gateway-on-aws/pull/135) | Postgres 17 + LiteLLM 1.76.1 | **Merge with changes** | **no** (`.env.template`) | Postgres part adopted with fixes (`fix/rds-postgres17`) |

### Details

**#155** (hmkim). Three unrelated changes in one commit. Terraform plumbing for
`CLOUDFRONT_CERTIFICATE_ARN` is complete and consistent (validation regex forces us-east-1). The
middleware hunk fixes two real bugs: a KeyError/IndexError on stream chunks without `choices`
(usage-only chunks, error chunks) and the swallowed `data: [DONE]` terminator. Asks before merge:
split into three PRs; add a fail-fast in `deploy.sh` for CloudFront + Route53 outside us-east-1 with
no CloudFront certificate (the failure it documents is still not guarded); export the new variable in
`undeploy.sh` too; the ap-northeast-2 entries route gpt-oss to us-west-2, which moves data out of the
Region and breaks with `DISABLE_OUTBOUND_NETWORK_ACCESS=true`, so document or drop them.

**#151 / #149** (abhilash225 / limmike). Identical 13-line deletion; #151 adds an explanatory
comment with the AWS reference. AppRegistry is closed to new accounts since 2026-07-30 (verified on
AWS docs), so any fresh account fails `terraform apply` without one of these. Merge exactly one;
optional cleanup: the now unused `SolutionNameKeySatisfyingRestrictions` local and root-module
`aws_caller_identity`/`aws_region` data sources.

**#150** (dependabot). Harmless (the file only serves `scripts/benchmark.py`), but 1.93.0 has no
pricing for Claude Opus 5 or Bedrock GPT-5.6. Better: pin to the same version as the gateway and add
the missing direct dependencies `tqdm`, `openai`, `click`.

**#147** (chhavi). Correct count guards for the EKS Route53 lookup, but: the `requests` line is
already on main (PR #148), the no-certificate path downgrades a public ALB to plaintext HTTP while
the output still says `https://`, a `moved` block is missing for the newly counted A record, and it
gates on `hosted_zone_name` instead of `use_route53` like the ECS module.

**#146** (watashi0222). Trivial, correct; nothing to change.

**#139** (siuwons). Good idea (CloudFront origin-facing prefix list instead of 0.0.0.0/0) with three
problems: the `.env.template` hunk downgrades LiteLLM below several 2026 CVE fix lines and conflicts
with main; removing inline `ingress` blocks does not delete the old 0.0.0.0/0 rules on existing
stacks (attributes-as-blocks), so upgraded deployments keep the open rule while the plan looks
hardened; the comment at the top of `security-groups.tf` contradicts the new design. Rebase, drop the
version bump, migrate `alb_sg` fully to standalone rule resources, document the migration.

**#135** (athewsey). Postgres 17 is right for new deployments (support to Feb 2030 vs Feb 2028), but
as written it breaks `terraform apply` on existing stacks (fixed-name parameter group without
`create_before_destroy`, no `allow_major_version_upgrade`), and the LiteLLM bump to 1.76.1 is a CVE
regression against main. Our `fix/rds-postgres17` carries the Postgres part with those fixes.

## Open issues that matter for this deployment

| Issue | Status here |
|-------|-------------|
| [#123](https://github.com/aws-solutions-library-samples/guidance-for-multi-provider-generative-ai-gateway-on-aws/issues/123) Guardrails + Converse "must start with a user message" | Root cause confirmed: `convert_messages_to_openai` drops every content block without a top-level `text` key (guardContent, image, tool blocks) and `guardrailConfig` is ignored, so text-only requests silently run unguarded. Only the middleware's `/bedrock/model/*` path is affected; OpenAI-compatible clients and server-side guardrails are not. Patch + tests prepared (see `fix/middleware-converse-guardcontent` when pushed); this deployment disables the middleware. |
| [#136](https://github.com/aws-solutions-library-samples/guidance-for-multi-provider-generative-ai-gateway-on-aws/issues/136) hard-coded DEBUG log level | Fixed in `fix/configurable-log-level` (`LITELLM_LOG_LEVEL`, default INFO). |
| [#137](https://github.com/aws-solutions-library-samples/guidance-for-multi-provider-generative-ai-gateway-on-aws/issues/137) plaintext ALB to task hop | Not changed (in-VPC hop). The plaintext HTTP:80 *listener* is removed when CloudFront is off (`feat/alb-ip-allowlist`). |
| [#140](https://github.com/aws-solutions-library-samples/guidance-for-multi-provider-generative-ai-gateway-on-aws/issues/140) pin LiteLLM <= 1.82.4 | The pin is now below the fix lines of CVE-2026-35030 (1.83.0), CVE-2026-42208 (1.83.7), CVE-2026-47101 (1.83.14), CVE-2026-49468 (1.84.0), verified on GitHub advisories. `chore/litellm-v1.100.0` moves to the current release and adds optional cosign verification. |

## Branches in this fork (each a candidate upstream PR, all based on `122b72d`)

| Branch | Purpose | Upstream-ready |
|--------|---------|----------------|
| `fix/remove-appregistry` | PR #151 verbatim | yes (already open upstream) |
| `fix/bedrock-agent-endpoint-optional` | `CREATE_BEDROCK_AGENT_ENDPOINT`; Regions without Agents for Bedrock (eu-north-1) failed the apply | yes |
| `chore/litellm-v1.100.0` | LiteLLM v1.100.0, cosign verification option, tag format docs, scripts pin | yes |
| `fix/middleware-streaming-done` | middleware hunk of PR #155 | yes (credit @hmkim) |
| `fix/configurable-log-level` | `LITELLM_LOG_LEVEL`, stop forcing DEBUG (issue #136) | yes |
| `fix/deploy-sh-mask-secrets` | deploy.sh no longer echoes API keys | yes |
| `fix/rds-postgres17` | Postgres 17 with upgrade-safety fixes (from PR #135) | yes (credit @athewsey) |
| `fix/rds-backups-and-protection` | 7-day backups, optional deletion protection, DDL-only statement logging | yes |
| `fix/config-key-typos` | `enable_pre_call_checks`, remove `service_callback` | yes |
| `feat/eu-region-claude5-models` | Claude Opus 5 / Sonnet 5 / Haiku 4.5 via `eu.` profiles in all EU Region configs | yes |
| `feat/guardrail-env-injection` | `BEDROCK_GUARDRAIL_ID` in .env enforces a guardrail on every request | yes |
| `fix/redis-password-secret` | Redis auth token via Secrets Manager | yes |
| `fix/separate-ui-password` | Admin UI password distinct from the master key | yes |
| `fix/ecs-health-checks-and-timeouts` | real container health check, `/health/readiness`, ALB idle timeout, memory ratio | yes |
| `feat/alb-ip-allowlist` | `ALB_ALLOWED_CIDRS` (security group + WAF IP set), no HTTP:80 listener without CloudFront | yes |
| `feat/acm-certificate-auto` | ACM certificate requested and DNS-validated automatically | yes |
| `feat/optional-middleware` | `ENABLE_MIDDLEWARE=false` runs LiteLLM alone (ECS) | yes |
| `deploy/eu-north-1` | all of the above plus deployment-specific config (this file, runbook, model list, IAM narrowing) | no (deployment branch) |

Suggested order for upstream PRs, smallest and least controversial first: #151 (already open),
`fix/config-key-typos`, `fix/deploy-sh-mask-secrets`, `fix/bedrock-agent-endpoint-optional`,
`fix/configurable-log-level`, `chore/litellm-v1.100.0`, then the ECS hardening branches.
