import { Address, DeployInfo, Deployer } from "../web3webdeploy/types";
import {
  DeployDepartmentSettings,
  deployDepartment,
} from "./internal/Department";
import {
  DeployDepartmentFactorySettings,
  deployDepartmentFactory,
} from "./internal/DepartmentFactory";

export interface DepartmentDeploymentSettings
  extends Omit<DeployInfo, "contract" | "args"> {
  departmentFactorySettings: DeployDepartmentFactorySettings;
  departmentSettings?: Omit<
    DeployDepartmentSettings,
    "name" | "departmentFactory"
  >;
  forceRedeploy?: boolean;
}

export interface DepartmentDeployment {
  departmentFactory: Address;
  dipsuteDepartment: Address;
  coreMemberDepartment: Address;
}

export async function deploy(
  deployer: Deployer,
  settings?: DepartmentDeploymentSettings
): Promise<DepartmentDeployment> {
  if (settings?.forceRedeploy !== undefined && !settings.forceRedeploy) {
    return await deployer.loadDeployment({ deploymentName: "latest.json" });
  }

  if (!settings) {
    throw new Error("Settings not provided");
  }
  const departmentFactory = await deployDepartmentFactory(
    deployer,
    settings.departmentFactorySettings
  );

  const dipsuteDepartment = await deployDepartment(deployer, {
    name: "DISPUTE",
    departmentFactory: departmentFactory,
    ...settings.departmentSettings,
  });

  const coreMemberDepartment = await deployDepartment(deployer, {
    name: "CORE_MEMBER",
    departmentFactory: departmentFactory,
    ...settings.departmentSettings,
  });

  const deployment = {
    departmentFactory: departmentFactory,
    dipsuteDepartment: dipsuteDepartment,
    coreMemberDepartment: coreMemberDepartment,
  };
  await deployer.saveDeployment({
    deploymentName: "latest.json",
    deployment: deployment,
  });
  return deployment;
}
