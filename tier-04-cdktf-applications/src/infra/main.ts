import { App } from "cdktf";
import { loadEnvironments, getEnvironment } from "./tools/config";
import { ApplicationsDevnetStack } from "./stacks/applications-devnet-stack";

const app = new App();
const envs = loadEnvironments();

const STATE_BUCKET =
  process.env.CDKTF_STATE_BUCKET ?? "cdktf-demo-tfstate";
const STATE_LOCK_TABLE =
  process.env.CDKTF_STATE_LOCK_TABLE ?? "cdktf-demo-tfstate-lock";

{
  const envName = "devnet";
  const config = getEnvironment(envs, envName);
  const region = process.env.AWS_REGION ?? "eu-central-1";
  new ApplicationsDevnetStack(app, envName, {
    envName,
    region,
    config,
    stateBucket: STATE_BUCKET,
    stateLockTable: STATE_LOCK_TABLE,
  });
}

app.synth();
