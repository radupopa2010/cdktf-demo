import { Construct } from "constructs";
import {
  TerraformStack,
  S3Backend,
  TerraformHclModule,
  TerraformOutput,
  TerraformVariable,
  DataTerraformRemoteStateS3,
  Token,
} from "cdktf";
import { AwsProvider } from "@providers/aws/provider";
import { NullProvider } from "@providers/null/provider";
import { EnvironmentConfig } from "../tools/config";

export interface ClustersDevnetStackProps {
  envName: string;
  region: string;
  config: EnvironmentConfig;
  stateBucket: string;
  stateLockTable: string;
}

export class ClustersDevnetStack extends TerraformStack {
  constructor(
    scope: Construct,
    id: string,
    props: ClustersDevnetStackProps,
  ) {
    super(scope, id);

    const { envName, region, config, stateBucket, stateLockTable } = props;

    const awsProfile = new TerraformVariable(this, "aws_profile", {
      type: "string",
      default: "",
      description: "AWS profile (overridden by OIDC in CI).",
    });

    new S3Backend(this, {
      bucket: stateBucket,
      key: `tier-02-clusters/${envName}.tfstate`,
      region,
      dynamodbTable: stateLockTable,
      encrypt: true,
    });

    new AwsProvider(this, "aws", {
      region,
      profile: awsProfile.stringValue,
      defaultTags: [
        {
          tags: {
            Project: "cdktf-demo",
            Env: envName,
            Tier: "02-clusters",
            ManagedBy: "cdktf",
          },
        },
      ],
    });
    new NullProvider(this, "null");

    // ── Read tier-01 outputs ────────────────────────────────────────────────
    const tier01 = new DataTerraformRemoteStateS3(this, "tier_01", {
      bucket: stateBucket,
      key: `tier-01-environments/${envName}.tfstate`,
      region,
    });

    const vpcId = tier01.getString("vpc_id");
    const privateSubnetIds = Token.asList(tier01.get("private_subnet_ids"));

    // ── Cluster ────────────────────────────────────────────────────────────
    const clusterName = `cdktf-demo-${envName}`;

    const cluster = new TerraformHclModule(this, "cluster", {
      source: "./modules/aws-eks-cluster",
      variables: {
        cluster_name: clusterName,
        cluster_version: config.cluster.version,
        vpc_id: vpcId,
        private_subnet_ids: privateSubnetIds,
        endpoint_public_access: config.cluster.endpoint_public_access,
        endpoint_public_access_cidrs:
          config.cluster.endpoint_public_access_cidrs,
        tags: { Project: "cdktf-demo", Env: envName, Tier: "02-clusters" },
      },
    });

    // ── App-dedicated node group ───────────────────────────────────────────
    const appNg = config.nodegroups.app;
    const nodegroup = new TerraformHclModule(this, "nodegroup_app", {
      source: "./modules/aws-eks-nodegroup",
      variables: {
        name: "app",
        cluster_name: cluster.get("cluster_name"),
        subnet_ids: privateSubnetIds,
        instance_types: appNg.instance_types,
        min_size: appNg.min_size,
        max_size: appNg.max_size,
        desired_size: appNg.desired_size,
        disk_size_gb: appNg.disk_size_gb,
        labels: appNg.labels,
        taints: appNg.taints,
        tags: { Project: "cdktf-demo", Env: envName, Tier: "02-clusters" },
      },
    });

    // ── ECR ────────────────────────────────────────────────────────────────
    const ecr = new TerraformHclModule(this, "ecr", {
      source: "./modules/aws-ecr",
      variables: {
        repository_name: config.ecr.repository_name,
        image_retention_count: config.ecr.image_retention_count,
        tags: { Project: "cdktf-demo", Env: envName, Tier: "02-clusters" },
      },
    });

    // ── Secrets skeleton ───────────────────────────────────────────────────
    new TerraformHclModule(this, "secrets", {
      source: "./modules/aws-secrets",
      variables: {
        region,
        env: envName,
        aws_profile: awsProfile.stringValue,
      },
    });

    // ── Outputs ────────────────────────────────────────────────────────────
    new TerraformOutput(this, "cluster_name", {
      value: cluster.get("cluster_name"),
    });
    new TerraformOutput(this, "cluster_endpoint", {
      value: cluster.get("cluster_endpoint"),
    });
    new TerraformOutput(this, "cluster_ca_certificate", {
      value: cluster.get("cluster_ca_certificate"),
      sensitive: true,
    });
    new TerraformOutput(this, "cluster_oidc_provider_arn", {
      value: cluster.get("cluster_oidc_provider_arn"),
    });
    new TerraformOutput(this, "cluster_oidc_issuer_url", {
      value: cluster.get("cluster_oidc_issuer_url"),
    });
    new TerraformOutput(this, "node_role_arn", {
      value: nodegroup.get("node_role_arn"),
    });
    new TerraformOutput(this, "app_node_group_name", {
      value: nodegroup.get("node_group_name"),
    });
    new TerraformOutput(this, "ecr_repo_url", {
      value: ecr.get("repository_url"),
    });
  }
}
