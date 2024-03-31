import { Address, DeployInfo, Deployer } from "../../web3webdeploy/types";

export interface DeploySmartAccountDepartmentInstallerSettings
  extends Omit<DeployInfo, "contract" | "args"> {
  smartAccountTrustlessExecution: Address;
  tagTrustlessManagement: Address;
  addressTrustlessManagement: Address;
  optimisticActions: Address;
  openRD: Address;
}

export async function deploySmartAccountDepartmentInstaller(
  deployer: Deployer,
  settings: DeploySmartAccountDepartmentInstallerSettings
): Promise<Address> {
  return await deployer
    .deploy({
      id: "SmartAccountDepartmentInstaller",
      contract: "SmartAccountDepartmentInstaller",
      args: [
        settings.smartAccountTrustlessExecution,
        settings.tagTrustlessManagement,
        settings.addressTrustlessManagement,
        settings.optimisticActions,
        settings.openRD,
      ],
      ...settings,
    })
    .then((deployment) => deployment.address);
}
