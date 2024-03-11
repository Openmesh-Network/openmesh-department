import { NetworkDeployment } from "../lib/osx-commons/configs/src";
import { Address, DeployInfo, Deployer } from "../web3webdeploy/types";
import {
  DeployDepartmentSettings,
  deployDepartment,
} from "./department/Department";
import {
  DeployDepartmentFactorySettings,
  deployDepartmentFactory,
} from "./department/DepartmentFactory";

export interface DepartmentDeploymentSettings
  extends Omit<DeployInfo, "contract" | "args"> {
  aragonDeployment: NetworkDeployment;
  departmentFactorySettings: DeployDepartmentFactorySettings;
  coreMemberDepartmentSettings?: Omit<
    DeployDepartmentSettings,
    "name" | "departmentFactory"
  >;
  forceRedeploy?: boolean;
}

export interface DepartmentDeployment {
  departmentFactory: Address;
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

  const coreMemberDepartment = await deployDepartment(deployer, {
    name: "CORE_MEMBER",
    departmentFactory: departmentFactory,
    ...settings.coreMemberDepartmentSettings,
  });

  const deployment = {
    departmentFactory: departmentFactory,
    coreMemberDepartment: coreMemberDepartment,
  };
  await deployer.saveDeployment({
    deploymentName: "latest.json",
    deployment: deployment,
  });
  return deployment;
}
