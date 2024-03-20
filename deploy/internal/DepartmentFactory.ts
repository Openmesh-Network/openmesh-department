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
  openRD: Address;
  departmentOwnerSettings: {
    metadata: Bytes;
    tokenVoting: Address;
    token: Address;
    trustlessManagement: Address;
  };
}

export interface DeployDepartmentFactoryReturn {
  departmentFactory: Address;
  departmentOwner: Address;
}

export async function deployDepartmentFactory(
  deployer: Deployer,
  settings: DeployDepartmentFactorySettings
): Promise<DeployDepartmentFactoryReturn> {
  const departmentFactory = await deployer.deploy({
    id: "DepartmentFactory",
    contract: "DepartmentFactory",
    args: [
      settings.pluginSetupProcessor,
      settings.tagVotingRepo,
      settings.tagManager,
      settings.trustlessManagement,
      settings.addressTrustlessManagement,
      settings.optimisticActions,
      settings.openRD,
      settings.departmentOwnerSettings,
    ],
    ...settings,
  });

  const events = await deployer.getEvents({
    abi: "DepartmentFactory",
    address: departmentFactory.address,
    eventName: "DepartmentOwnerCreated",
    logs: departmentFactory.receipt.logs,
  });

  if (events.length === 0) {
    throw new Error("DepartmentOwnerCreated event not emitted");
  }

  const departmentOwner = (
    events[0].args as any as { departmentOwner: Address }
  ).departmentOwner;
  return {
    departmentFactory: departmentFactory.address,
    departmentOwner: departmentOwner,
  };
}
