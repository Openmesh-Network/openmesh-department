export const ExpertDepartmentSmartAccountContract = {
  address: "0x5aC5C9eF579f70D307121a2Cf34Bf16807158A0e",
  abi: [
    { type: "constructor", inputs: [], stateMutability: "nonpayable" },
    { type: "fallback", stateMutability: "payable" },
    { type: "receive", stateMutability: "payable" },
    {
      type: "function",
      name: "multicall",
      inputs: [{ name: "data", type: "bytes[]", internalType: "bytes[]" }],
      outputs: [{ name: "results", type: "bytes[]", internalType: "bytes[]" }],
      stateMutability: "nonpayable",
    },
    {
      type: "function",
      name: "performCall",
      inputs: [
        { name: "to", type: "address", internalType: "address" },
        { name: "value", type: "uint256", internalType: "uint256" },
        { name: "data", type: "bytes", internalType: "bytes" },
      ],
      outputs: [{ name: "returnValue", type: "bytes", internalType: "bytes" }],
      stateMutability: "nonpayable",
    },
    {
      type: "function",
      name: "performDelegateCall",
      inputs: [
        { name: "to", type: "address", internalType: "address" },
        { name: "data", type: "bytes", internalType: "bytes" },
      ],
      outputs: [{ name: "returnValue", type: "bytes", internalType: "bytes" }],
      stateMutability: "nonpayable",
    },
    {
      type: "error",
      name: "AddressEmptyCode",
      inputs: [{ name: "target", type: "address", internalType: "address" }],
    },
    {
      type: "error",
      name: "AddressInsufficientBalance",
      inputs: [{ name: "account", type: "address", internalType: "address" }],
    },
    { type: "error", name: "FailedInnerCall", inputs: [] },
    {
      type: "error",
      name: "FunctionNotFound",
      inputs: [
        { name: "functionSelector", type: "bytes4", internalType: "bytes4" },
      ],
    },
    {
      type: "error",
      name: "NotOwner",
      inputs: [
        { name: "account", type: "address", internalType: "address" },
        { name: "owner", type: "address", internalType: "address" },
      ],
    },
  ],
} as const;
