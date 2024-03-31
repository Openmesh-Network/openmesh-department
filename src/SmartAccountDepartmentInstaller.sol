// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    SmartAccountTrustlessExecutionLib,
    ISmartAccountTrustlessExecution
} from "../lib/smart-account/src/modules/trustless-execution/SmartAccountTrustlessExecutionLib.sol";

import {
    ITrustlessManagement, IDAO, NO_PERMISSION_CHECKER
} from "../lib/trustless-management/src/TrustlessManagement.sol";
import {IOptimisticActions, IDAO as IOptimsticActionDAO} from "../lib/optimistic-actions/src/IOptimisticActions.sol";

contract SmartAccountDepartmentInstaller {
    event DepartmentInstalled(address indexed department, bytes32 indexed tag);

    /// @notice The smart account module to add execute, which is needed to use trustless management.
    ISmartAccountTrustlessExecution public immutable smartAccountTrustlessExecution;

    /// @notice Address trustless management (for creating optimstic actions).
    ITrustlessManagement public immutable tagTrustlessManagement;

    /// @notice Address trustless management (for executing optimstic actions).
    ITrustlessManagement public immutable addressTrustlessManagement;

    /// @notice The optimstic actions implementation.
    IOptimisticActions public immutable optimisticActions;

    /// @notice The address of OpenR&D that will be optimsticly interactable for departments by default.
    address public immutable openRD;

    constructor(
        ISmartAccountTrustlessExecution _smartAccountTrustlessExecution,
        ITrustlessManagement _tagTrustlessManagement,
        ITrustlessManagement _addressTrustlessManagement,
        IOptimisticActions _optimisticActions,
        address _openRD
    ) {
        smartAccountTrustlessExecution = _smartAccountTrustlessExecution;
        tagTrustlessManagement = _tagTrustlessManagement;
        addressTrustlessManagement = _addressTrustlessManagement;
        optimisticActions = _optimisticActions;
        openRD = _openRD;
    }

    function install(bytes32 _tag) external {
        // Install smart account module
        SmartAccountTrustlessExecutionLib.fullInstall(address(smartAccountTrustlessExecution));

        // Enable trustless management (give execute permission).
        SmartAccountTrustlessExecutionLib.setExecutePermission(address(tagTrustlessManagement), true);
        SmartAccountTrustlessExecutionLib.setExecutePermission(address(addressTrustlessManagement), true);

        // Set trustless management permissions and optmistic actions delay.
        tagTrustlessManagement.changeFunctionAccess(
            IDAO(address(this)),
            uint256(_tag),
            address(optimisticActions),
            optimisticActions.createAction.selector,
            NO_PERMISSION_CHECKER
        );
        tagTrustlessManagement.changeFunctionAccess(
            IDAO(address(this)),
            uint256(_tag),
            address(optimisticActions),
            optimisticActions.rejectAction.selector,
            NO_PERMISSION_CHECKER
        );
        optimisticActions.setExecuteDelay(IOptimsticActionDAO(address(this)), 7 days);
        addressTrustlessManagement.changeZoneAccess(
            IDAO(address(this)), uint160(address(optimisticActions)), openRD, NO_PERMISSION_CHECKER
        );

        emit DepartmentInstalled(address(this), _tag);
    }
}
