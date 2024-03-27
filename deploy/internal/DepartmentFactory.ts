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
  departmentOwner: {
    dao: Address;
    tokenVoting: Address;
  };
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

  const departmentCreatedEvents = await deployer.getEvents({
    abi: "DepartmentFactory",
    address: departmentFactory.address,
    eventName: "DepartmentOwnerCreated",
    logs: departmentFactory.receipt.logs,
  });
  if (departmentCreatedEvents.length === 0) {
    throw new Error("DepartmentOwnerCreated event not emitted");
  }
  const departmentOwner = (
    departmentCreatedEvents[0].args as any as { departmentOwner: Address }
  ).departmentOwner;

  const installationPreparedEvents = await deployer.getEvents({
    abi: "PluginSetupProcessor",
    address: settings.pluginSetupProcessor,
    eventName: "InstallationPrepared",
    logs: departmentFactory.receipt.logs,
  });
  if (installationPreparedEvents.length === 0) {
    throw new Error("InstallationPrepared event not emitted");
  }
  const tokenVoting = (
    installationPreparedEvents[0].args as any as { plugin: Address }
  ).plugin;

  return {
    departmentFactory: departmentFactory.address,
    departmentOwner: {
      dao: departmentOwner,
      tokenVoting: tokenVoting,
    },
  };
}
