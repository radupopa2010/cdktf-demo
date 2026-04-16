import * as fs from "fs";
import * as path from "path";
import { parse as parseJsonc } from "jsonc-parser";

export interface AppConfig {
  namespace: string;
  release_name: string;
  replicas: number;
  image_tag: string;
}

export interface EnvironmentConfig {
  app: AppConfig;
}

export type EnvironmentsFile = Record<string, EnvironmentConfig>;

export function loadEnvironments(filePath?: string): EnvironmentsFile {
  const resolved =
    filePath ?? path.join(__dirname, "..", "..", "..", "environments.jsonc");
  return parseJsonc(fs.readFileSync(resolved, "utf8")) as EnvironmentsFile;
}

export function getEnvironment(
  envs: EnvironmentsFile,
  name: string,
): EnvironmentConfig {
  const env = envs[name];
  if (!env) throw new Error(`Environment '${name}' not in environments.jsonc`);
  return env;
}
