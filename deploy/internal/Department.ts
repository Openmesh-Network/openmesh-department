import { Address, Deployer, ExecuteInfo } from "../../web3webdeploy/types";
import { keccak256, toBytes } from "viem";

export interface DeployDepartmentSettings
  extends Omit<ExecuteInfo, "abi" | "to" | "function" | "args"> {
  name: string;
  departmentFactory: Address;
}

export async function deployDepartment(
  deployer: Deployer,
  settings: DeployDepartmentSettings
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

  const department = (events[0].args as any as { department: Address })
    .department;
  return department;
}
