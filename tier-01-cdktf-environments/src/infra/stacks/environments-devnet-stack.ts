import { Construct } from "constructs";
import {
  TerraformStack,
  S3Backend,
  TerraformOutput,
  TerraformVariable,
} from "cdktf";
import { AwsProvider } from "@providers/aws/provider";
import { AwsNetwork } from "@modules/aws-network";
import {
  EnvironmentConfig,
  regionVpcCidr,
  allocateSubnets,
} from "../tools/config";

export interface EnvironmentsDevnetStackProps {
  envName: string;
  region: string;
  config: EnvironmentConfig;
  stateBucket: string;
  stateLockTable: string;
}

export class EnvironmentsDevnetStack extends TerraformStack {
  constructor(
    scope: Construct,
    id: string,
    props: EnvironmentsDevnetStackProps,
  ) {
    super(scope, id);

    const { envName, region, config, stateBucket, stateLockTable } = props;

    const awsProfile = new TerraformVariable(this, "aws_profile", {
      type: "string",
      description: "AWS profile to use locally (overridden in CI by OIDC).",
      default: "radupopa",
    });

    new S3Backend(this, {
      bucket: stateBucket,
      key: `tier-01-environments/${envName}.tfstate`,
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
            Tier: "01-environments",
            ManagedBy: "cdktf",
          },
        },
      ],
    });

    const azs = config.regions[0] === region ? [`${region}a`, `${region}b`] : [];
    const { publicCidrs, privateCidrs } = allocateSubnets(config, 2);

    const network = new AwsNetwork(this, "network", {
      name: `${envName}-${region}`,
      vpcCidr: regionVpcCidr(config),
      azs,
      publicSubnetCidrs: publicCidrs,
      privateSubnetCidrs: privateCidrs,
      tags: {
        Project: "cdktf-demo",
        Env: envName,
        Tier: "01-environments",
      },
    });

    new TerraformOutput(this, "vpc_id", {
      value: network.getString("vpc_id"),
    });
    new TerraformOutput(this, "vpc_cidr", {
      value: network.getString("vpc_cidr"),
    });
    new TerraformOutput(this, "public_subnet_ids", {
      value: network.interpolationForOutput("public_subnet_ids"),
    });
    new TerraformOutput(this, "private_subnet_ids", {
      value: network.interpolationForOutput("private_subnet_ids"),
    });
    new TerraformOutput(this, "azs", {
      value: network.interpolationForOutput("azs"),
    });
    new TerraformOutput(this, "region", { value: region });
  }
}
