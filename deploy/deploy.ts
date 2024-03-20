import { Deployer } from "../web3webdeploy/types";

export interface DepartmentDeploymentSettings {}

export interface DepartmentDeployment {}

export async function deploy(
  deployer: Deployer,
  settings?: DepartmentDeploymentSettings
): Promise<DepartmentDeployment> {
  return {};
}
