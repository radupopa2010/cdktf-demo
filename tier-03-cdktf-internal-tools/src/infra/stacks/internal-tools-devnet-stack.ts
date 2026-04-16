import { Construct } from "constructs";
import {
  TerraformStack,
  S3Backend,
  TerraformHclModule,
  TerraformOutput,
  TerraformVariable,
  DataTerraformRemoteStateS3,
  Fn,
} from "cdktf";
import { AwsProvider } from "@providers/aws/provider";
import { DataAwsEksCluster } from "@providers/aws/data-aws-eks-cluster";
import { DataAwsEksClusterAuth } from "@providers/aws/data-aws-eks-cluster-auth";
import { KubernetesProvider } from "@providers/kubernetes/provider";
import { HelmProvider } from "@providers/helm/provider";
import { EnvironmentConfig } from "../tools/config";

export interface InternalToolsDevnetStackProps {
  envName: string;
  region: string;
  config: EnvironmentConfig;
  stateBucket: string;
  stateLockTable: string;
}

export class InternalToolsDevnetStack extends TerraformStack {
  constructor(
    scope: Construct,
    id: string,
    props: InternalToolsDevnetStackProps,
  ) {
    super(scope, id);

    const { envName, region, config, stateBucket, stateLockTable } = props;

    const awsProfile = new TerraformVariable(this, "aws_profile", {
      type: "string",
      default: "radupopa",
    });

    new S3Backend(this, {
      bucket: stateBucket,
      key: `tier-03-internal-tools/${envName}.tfstate`,
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
            Tier: "03-internal-tools",
            ManagedBy: "cdktf",
          },
        },
      ],
    });

    // ── Read remote state from tier-01 + tier-02 ──────────────────────────
    const tier01 = new DataTerraformRemoteStateS3(this, "tier_01", {
      bucket: stateBucket,
      key: `tier-01-environments/${envName}.tfstate`,
      region,
    });
    const tier02 = new DataTerraformRemoteStateS3(this, "tier_02", {
      bucket: stateBucket,
      key: `tier-02-clusters/${envName}.tfstate`,
      region,
    });

    const vpcId = tier01.getString("vpc_id");
    const clusterName = tier02.getString("cluster_name");
    const oidcProviderArn = tier02.getString("cluster_oidc_provider_arn");
    const oidcIssuerUrl = tier02.getString("cluster_oidc_issuer_url");

    // ── K8s + Helm providers backed by EKS data sources ───────────────────
    const eksData = new DataAwsEksCluster(this, "eks", { name: clusterName });
    const eksAuth = new DataAwsEksClusterAuth(this, "eks_auth", {
      name: clusterName,
    });

    new KubernetesProvider(this, "k8s", {
      host: eksData.endpoint,
      clusterCaCertificate: Fn.base64decode(
        eksData.certificateAuthority.get(0).data,
      ),
      token: eksAuth.token,
    });

    new HelmProvider(this, "helm", {
      kubernetes: {
        host: eksData.endpoint,
        clusterCaCertificate: Fn.base64decode(
          eksData.certificateAuthority.get(0).data,
        ),
        token: eksAuth.token,
      },
    });

    // ── AWS Load Balancer Controller ──────────────────────────────────────
    const lbc = new TerraformHclModule(this, "lbc", {
      source: "./modules/kubernetes-aws-load-balancer-controller",
      variables: {
        cluster_name: clusterName,
        region,
        vpc_id: vpcId,
        oidc_provider_arn: oidcProviderArn,
        oidc_issuer_url: oidcIssuerUrl,
        chart_version: config.lbc.chart_version,
        namespace: config.lbc.namespace,
        service_account: config.lbc.service_account,
        tags: { Project: "cdktf-demo", Env: envName, Tier: "03-internal-tools" },
      },
    });

    // ── cert-manager (optional) ───────────────────────────────────────────
    new TerraformHclModule(this, "cert_manager", {
      source: "./modules/kubernetes-cert-manager",
      variables: {
        enabled: config.cert_manager.enabled,
        chart_version: config.cert_manager.chart_version,
        namespace: config.cert_manager.namespace,
      },
    });

    // ── Outputs ───────────────────────────────────────────────────────────
    new TerraformOutput(this, "lbc_iam_role_arn", {
      value: lbc.get("iam_role_arn"),
    });
    new TerraformOutput(this, "lbc_namespace", {
      value: lbc.get("namespace"),
    });
    new TerraformOutput(this, "lbc_service_account", {
      value: lbc.get("service_account"),
    });
  }
}
