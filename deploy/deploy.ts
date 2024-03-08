import { NetworkDeployment } from "../lib/osx-commons/configs/src";
import {
  Address,
  DeployInfo,
  Deployer,
  ExecuteInfo,
} from "../web3webdeploy/types";
import { keccak256, toBytes } from "../web3webdeploy/node_modules/viem";

export interface DepartmentDeploymentSettings
  extends Omit<DeployInfo, "contract" | "args"> {
  aragonDeployment: NetworkDeployment;
  tagVotingRepo: Address;
  tagManager: Address;
  trustlessManagement: Address;

  coreMemberDepartmentSettings?: Omit<
    DepartmentDeploymentSettingsInternal,
    "name" | "departmentFactory"
  >;
}

export interface DepartmentDeployment {
  departmentFactory: Address;
  coreMemberDepartment: Address;
}

export async function deploy(
  deployer: Deployer,
  settings?: DepartmentDeploymentSettings
): Promise<DepartmentDeployment> {
  if (!settings) {
    throw new Error("Settings not provided");
  }

  const departmentFactory = (
    await deployer.deploy({
      id: "DepartmentFactory",
      contract: "DepartmentFactory",
      args: [
        settings.aragonDeployment.PluginSetupProcessor.address,
        settings.tagVotingRepo,
        settings.tagManager,
        settings.trustlessManagement,
      ],
      ...settings,
    })
  ).address;

  const coreMemberDepartment = await deployDepartment(deployer, {
    name: "CORE_MEMBER",
    departmentFactory: departmentFactory,
    ...settings.coreMemberDepartmentSettings,
  });
  console.log(coreMemberDepartment);

  return {
    departmentFactory: departmentFactory,
    coreMemberDepartment: coreMemberDepartment,
  };
}

export interface DepartmentDeploymentSettingsInternal
  extends Omit<ExecuteInfo, "abi" | "to" | "function" | "args"> {
  name: string;
  departmentFactory: Address;
}
async function deployDepartment(
  deployer: Deployer,
  settings: DepartmentDeploymentSettingsInternal
): Promise<Address> {
  const tag = keccak256(toBytes(settings.name));
  const metadata = "";
  const { receipt } = await deployer.execute({
    abi: "DepartmentFactory",
    to: settings.departmentFactory,
    function: "createDao",
    args: [metadata, tag],
    ...settings,
  });

  const events = await deployer.getEvents({
    abi: "DepartmentFactory",
    address: settings.departmentFactory,
    eventName: "DepartmentCreated",
    logs: receipt.logs,
  });

  if (events.length === 0) {
    throw new Error("DepartmentCreated event not emitted");
  }

  const department = (events[0].args as { department: Address }).department;
  return department;
}
