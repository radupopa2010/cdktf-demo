---
name: cdktf
description: Safely run `cdktf` / `terraform` commands in this demo. Always pipe output to a tier-local log file. Never interrupt. Use this skill for ANY cdktf or terraform invocation.
---

## Why this skill exists

CDKTF/Terraform commands can take 10–30+ minutes (VPC, EKS). Interrupting them corrupts state. Output is also long and noisy — too much for the conversation context — so it must be logged to disk where you (and the user) can grep it later.

## Hard rules

1. **NEVER interrupt** a running cdktf or terraform process. State corruption follows.
2. **Always check first:**

   ```bash
   ps aux | grep -E "(cdktf|terraform)" | grep -v grep
   ```

   If something is running, **stop and tell the user** — do not start another command.
3. **Always log to a file.** Pipe every cdktf/terraform invocation through `tee` into `<tier>/logs/`.
4. **Never run from the AI session without the user's go-ahead.** Deploys happen in CI. Local invocations are the operator's call.
5. **Never use a `timeout:` parameter** with the Bash tool for these commands. They take as long as they take.

## The wrapper pattern

For every cdktf command, run from the tier dir and tee to a timestamped log file:

```bash
cd /Users/radupopa/p/radu/random-code/cdktf-demo/tier-XX-cdktf-...
mkdir -p logs
LOG="logs/cdktf-$(echo "$@" | tr ' /' '__')-$(date -u +%Y%m%dT%H%M%SZ).log"
echo "==> $(date -u) cdktf $* (env=devnet)" | tee "$LOG"
cdktf "$@" devnet 2>&1 | tee -a "$LOG"
```

Or just inline:

```bash
cd tier-01-cdktf-environments && \
  mkdir -p logs && \
  cdktf synth devnet 2>&1 | tee "logs/cdktf-synth-$(date -u +%Y%m%dT%H%M%SZ).log"
```

## Common commands

| Command | What it does | Safe to run from AI? |
|---|---|---|
| `cdktf synth devnet` | Compile TS → terraform JSON. No state writes. | ✅ Yes |
| `cdktf plan devnet` | Show diff. No state writes. Needs AWS creds. | ⚠️ Ask user first (uses creds) |
| `cdktf deploy devnet` | Apply. **Long-running.** Mutates state. | ❌ Operator-only |
| `cdktf destroy devnet` | Tear down. **Long-running.** | ❌ Operator-only |
| `cdktf get` | Generate provider/module bindings. Local only. | ✅ Yes |
| `terraform validate` (in `modules/<name>/`) | Validates HCL. | ✅ Yes |
| `terraform fmt -check` | Style check. | ✅ Yes |

## Pre-flight checklist

Before any plan/deploy:

- [ ] AWS profile exported: `export AWS_PROFILE=radupopa AWS_REGION=eu-central-1`
- [ ] AWS auth fresh: `aws sts get-caller-identity --profile radupopa` returns the expected account
- [ ] Backend bucket + table exist (`scripts/bootstrap-tf-backend.sh` ran once)
- [ ] Lower tiers have been deployed (tier 02 needs tier 01 outputs in remote state, etc.)
- [ ] No other cdktf/terraform process running (see process check above)

## Reading the log afterwards

```bash
ls -lt logs/                                         # newest first
tail -n 200 logs/cdktf-plan-*.log                    # quick scan
grep -E "Error|error|panic|failed" logs/<file>.log   # find failures
```

## When something goes sideways

- **State lock**: someone else is running terraform OR a previous run was killed. Do **not** force-unlock without confirming with the user.
- **Provider version mismatch**: re-run `cdktf get`.
- **Secret not found**: secret hasn't been bootstrapped — see `scripts/bootstrap-secrets.sh`.
- **OIDC auth failed in CI**: check repo variable `AWS_ROLE_ARN` and the trust policy on the role.
