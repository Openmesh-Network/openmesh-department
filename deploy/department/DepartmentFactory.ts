import { Address, DeployInfo, Deployer } from "../../web3webdeploy/types";

export interface DeployDepartmentFactorySettings
  extends Omit<DeployInfo, "contract" | "args"> {
  pluginSetupProcessor: Address;
  tagVotingRepo: Address;
  tagManager: Address;
  trustlessManagement: Address;
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
      ],
      ...settings,
    })
    .then((deployment) => deployment.address);
}
