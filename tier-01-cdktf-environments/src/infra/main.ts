import { App } from "cdktf";
import { loadEnvironments, getEnvironment } from "./tools/config";
import { EnvironmentsDevnetStack } from "./stacks/environments-devnet-stack";

const app = new App();

const envs = loadEnvironments();

// State backend — bootstrapped by scripts/bootstrap-tf-backend.sh
const STATE_BUCKET =
  process.env.CDKTF_STATE_BUCKET ?? "cdktf-demo-tfstate";
const STATE_LOCK_TABLE =
  process.env.CDKTF_STATE_LOCK_TABLE ?? "cdktf-demo-tfstate-lock";

// devnet
{
  const envName = "devnet";
  const config = getEnvironment(envs, envName);
  const region = config.regions[0]; // single-region demo
  new EnvironmentsDevnetStack(app, envName, {
    envName,
    region,
    config,
    stateBucket: STATE_BUCKET,
    stateLockTable: STATE_LOCK_TABLE,
  });
}

// To onboard testnet/mainnet later:
// 1. Uncomment the section in environments.jsonc.
// 2. Add a stack instantiation here following the devnet pattern above.

app.synth();
