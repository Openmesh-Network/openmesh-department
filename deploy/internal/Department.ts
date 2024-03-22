import { Address, Deployer, ExecuteInfo } from "../../web3webdeploy/types";

export interface DeployDepartmentSettings
  extends Omit<ExecuteInfo, "abi" | "to" | "function" | "args"> {
  name: string;
  departmentFactory: Address;
  pluginSetupProcessor?: Address;
}

export interface DeployDepartmentReturn {
  dao: Address;
  tagVoting: Address;
}

export async function deployDepartment(
  deployer: Deployer,
  settings: DeployDepartmentSettings
): Promise<DeployDepartmentReturn> {
  const tag = deployer.viem.keccak256(deployer.viem.toBytes(settings.name));
  const metadata = "";
  const { receipt } = await deployer.execute({
    abi: "DepartmentFactory",
    to: settings.departmentFactory,
    function: "createDepartment",
    args: [metadata, tag],
    ...settings,
  });

  const departmentCreatedEvents = await deployer.getEvents({
    abi: "DepartmentFactory",
    address: settings.departmentFactory,
    eventName: "DepartmentCreated",
    logs: receipt.logs,
  });
  if (departmentCreatedEvents.length === 0) {
    throw new Error("DepartmentCreated event not emitted");
  }
  const dao = (
    departmentCreatedEvents[0].args as any as { department: Address }
  ).department;

  const installationPreparedEvents = await deployer.getEvents({
    abi: "PluginSetupProcessor",
    address: settings.pluginSetupProcessor,
    eventName: "InstallationPrepared",
    logs: receipt.logs,
  });
  if (installationPreparedEvents.length === 0) {
    throw new Error("InstallationPrepared event not emitted");
  }
  const tagVoting = (
    installationPreparedEvents[0].args as any as { plugin: Address }
  ).plugin;

  return {
    dao: dao,
    tagVoting: tagVoting,
  };
}
