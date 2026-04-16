import * as fs from "fs";
import * as path from "path";
import { parse as parseJsonc } from "jsonc-parser";

export interface NodeGroupConfig {
  instance_types: string[];
  min_size: number;
  max_size: number;
  desired_size: number;
  disk_size_gb: number;
  labels: Record<string, string>;
  taints: { key: string; value: string; effect: string }[];
}

export interface ClusterConfig {
  version: string;
  endpoint_public_access: boolean;
  endpoint_public_access_cidrs: string[];
}

export interface EcrConfig {
  repository_name: string;
  image_retention_count: number;
}

export interface EnvironmentConfig {
  cluster: ClusterConfig;
  nodegroups: Record<string, NodeGroupConfig>;
  ecr: EcrConfig;
}

export type EnvironmentsFile = Record<string, EnvironmentConfig>;

export function loadEnvironments(filePath?: string): EnvironmentsFile {
  const resolved =
    filePath ?? path.join(__dirname, "..", "..", "..", "environments.jsonc");
  const raw = fs.readFileSync(resolved, "utf8");
  return parseJsonc(raw) as EnvironmentsFile;
}

export function getEnvironment(
  envs: EnvironmentsFile,
  name: string,
): EnvironmentConfig {
  const env = envs[name];
  if (!env) throw new Error(`Environment '${name}' not in environments.jsonc`);
  return env;
}
