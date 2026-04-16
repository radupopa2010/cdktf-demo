import * as fs from "fs";
import * as path from "path";
import { parse as parseJsonc } from "jsonc-parser";

export interface NetworkingConfig {
  cidr_prefix: string;
  mask_length_environment: number;
  mask_length_vpc: number;
  mask_length_subnet: number;
}

export interface EnvironmentConfig {
  regions: string[];
  networking: NetworkingConfig;
}

export type EnvironmentsFile = Record<string, EnvironmentConfig>;

export function loadEnvironments(filePath?: string): EnvironmentsFile {
  const resolved =
    filePath ?? path.join(__dirname, "..", "..", "..", "environments.jsonc");
  const raw = fs.readFileSync(resolved, "utf8");
  const parsed = parseJsonc(raw) as EnvironmentsFile;
  if (!parsed || typeof parsed !== "object") {
    throw new Error(`Failed to parse ${resolved}`);
  }
  return parsed;
}

export function getEnvironment(
  envs: EnvironmentsFile,
  name: string,
): EnvironmentConfig {
  const env = envs[name];
  if (!env) {
    throw new Error(
      `Environment '${name}' not found in environments.jsonc — active sections: ${Object.keys(envs).join(", ")}`,
    );
  }
  return env;
}

/**
 * Build the per-region VPC CIDR from the environments.jsonc convention.
 *
 * cidr_prefix=10.251 + mask_length_vpc=20 → 10.251.0.0/20 (per region, region 0).
 * For multi-region we'd offset; demo is single-region so we use index 0.
 */
export function regionVpcCidr(env: EnvironmentConfig): string {
  return `${env.networking.cidr_prefix}.0.0/${env.networking.mask_length_vpc}`;
}

/**
 * Allocate N public + N private /24 subnets inside the VPC /20.
 * /20 → /24 gives 16 child subnets; we use 0..N-1 for public, 8..8+N-1 for private.
 */
export function allocateSubnets(
  env: EnvironmentConfig,
  count: number,
): { publicCidrs: string[]; privateCidrs: string[] } {
  const prefix = env.networking.cidr_prefix; // e.g. "10.251"
  const publicCidrs: string[] = [];
  const privateCidrs: string[] = [];
  for (let i = 0; i < count; i++) {
    publicCidrs.push(`${prefix}.${i}.0/24`);
    privateCidrs.push(`${prefix}.${8 + i}.0/24`);
  }
  return { publicCidrs, privateCidrs };
}
