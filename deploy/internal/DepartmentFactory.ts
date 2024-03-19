import {
  Address,
  Bytes,
  DeployInfo,
  Deployer,
} from "../../web3webdeploy/types";

export interface DeployDepartmentFactorySettings
  extends Omit<DeployInfo, "contract" | "args"> {
  pluginSetupProcessor: Address;
  tagVotingRepo: Address;
  tagManager: Address;
  trustlessManagement: Address;
  addressTrustlessManagement: Address;
  optimisticActions: Address;
  openrd: Address;
  departmentOwnerSettings: {
    metadata: Bytes;
    tokenVoting: Address;
    token: Address;
    trustlessManagement: Address;
  };
}

export async function deployDepartmentFactory(
  deployer: Deployer,
  settings: DeployDepartmentFactorySettings
): Promise<Address> {
  return await deployer
    .deploy({
      id: "DepartmentFactory",
      contract: "DepartmentFactory",
      args: [
        settings.pluginSetupProcessor,
        settings.tagVotingRepo,
        settings.tagManager,
        settings.trustlessManagement,
        settings.addressTrustlessManagement,
        settings.optimisticActions,
        settings.openrd,
        settings.departmentOwnerSettings,
      ],
      ...settings,
    })
    .then((deployment) => deployment.address);
}
