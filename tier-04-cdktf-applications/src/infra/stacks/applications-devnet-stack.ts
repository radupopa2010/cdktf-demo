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

export interface ApplicationsDevnetStackProps {
  envName: string;
  region: string;
  config: EnvironmentConfig;
  stateBucket: string;
  stateLockTable: string;
}

export class ApplicationsDevnetStack extends TerraformStack {
  constructor(
    scope: Construct,
    id: string,
    props: ApplicationsDevnetStackProps,
  ) {
    super(scope, id);

    const { envName, region, config, stateBucket, stateLockTable } = props;

    const awsProfile = new TerraformVariable(this, "aws_profile", {
      type: "string",
      default: "",
    });

    // Image tag is overridden by CI on tag releases.
    const imageTag = new TerraformVariable(this, "image_tag", {
      type: "string",
      default: config.app.image_tag,
      description: "Container image tag (overridden by app-release workflow).",
    });

    new S3Backend(this, {
      bucket: stateBucket,
      key: `tier-04-applications/${envName}.tfstate`,
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
            Tier: "04-applications",
            ManagedBy: "cdktf",
          },
        },
      ],
    });

    const tier02 = new DataTerraformRemoteStateS3(this, "tier_02", {
      bucket: stateBucket,
      key: `tier-02-clusters/${envName}.tfstate`,
      region,
    });

    const clusterName = tier02.getString("cluster_name");
    const ecrRepoUrl = tier02.getString("ecr_repo_url");

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

    const release = new TerraformHclModule(this, "rust_demo", {
      source: "./modules/kubernetes-rust-demo",
      variables: {
        namespace: config.app.namespace,
        release_name: config.app.release_name,
        chart_path: "../../../app/helm/rust-demo",
        image_repository: ecrRepoUrl,
        image_tag: imageTag.stringValue,
        replicas: config.app.replicas,
      },
    });

    new TerraformOutput(this, "release_name", {
      value: release.get("release_name"),
    });
    new TerraformOutput(this, "namespace", {
      value: release.get("namespace"),
    });
    new TerraformOutput(this, "image", { value: release.get("image") });
  }
}
