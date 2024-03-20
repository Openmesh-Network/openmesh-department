// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DAO, IDAO} from "../lib/osx/packages/contracts/src/core/dao/DAO.sol";
import {
    PluginSetupProcessor,
    PluginSetupRef,
    IPluginSetup,
    PluginRepo,
    PermissionLib,
    hashHelpers
} from "../lib/osx/packages/contracts/src/framework/plugin/setup/PluginSetupProcessor.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts-v5/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {
    TokenVotingSetup,
    GovernanceERC20
} from "../lib/osx/packages/contracts/src/plugins/governance/majority-voting/token/TokenVotingSetup.sol";
import {MajorityVotingBase} from "../lib/aragon-tag-voting/src/TagVotingSetup.sol";
import {ERC721TagManager} from "../lib/tag-manager/src/ERC721TagManager.sol";
import {ITrustlessManagement, NO_PERMISSION_CHECKER} from "../lib/trustless-management/src/TrustlessManagement.sol";
import {IOptimisticActions} from "../lib/optimistic-actions/src/IOptimisticActions.sol";
import {IVerifiedContributor} from "../lib/verified-contributor/src/IVerifiedContributor.sol";

import {OpenmeshENSReverseClaimable} from "../lib/openmesh-admin/src/OpenmeshENSReverseClaimable.sol";

bytes32 constant DEPARTMENT_SETUP_EXECUTION_ID = keccak256("DEPARTMENT_SETUP");

contract DepartmentFactory is OpenmeshENSReverseClaimable {
    event DepartmentOwnerCreated(IDAO departmentOwner);
    event DepartmentCreated(IDAO department, bytes32 tag);

    struct DepartmentOwnerSettings {
        bytes metadata;
        PluginRepo tokenVoting;
        IVerifiedContributor token;
        ITrustlessManagement trustlessManagement;
    }

    struct PluginSettings {
        PluginSetupRef pluginSetupRef;
        bytes data;
    }

    /// @notice The DAO base contract, to be used for creating new `DAO`s via `createERC1967Proxy` function.
    address public immutable daoBase;

    /// @notice The plugin setup processor for installing plugins on the newly created `DAO`s.
    PluginSetupProcessor public immutable pluginSetupProcessor;

    /// @notice The repo used for the tag voting plugin installation.
    PluginRepo public immutable aragonTagVoting;

    /// @notice The tag manager used for the tag voting plugin installation.
    ERC721TagManager public immutable tagManager;

    /// @notice The implemention used for the trustless management setup.
    ITrustlessManagement public immutable trustlessManagement;

    /// @notice Address trustless management (for optimstic actions).
    ITrustlessManagement public immutable addressTrustlessManagement;

    /// @notice The implemention used for the optimstic actions setup.
    IOptimisticActions public immutable optimsticActions;

    /// @notice The address of OpenR&D that will be optimsticly interactable for departments by default.
    address public immutable openRD;

    constructor(
        PluginSetupProcessor _pluginSetupProcessor,
        PluginRepo _aragonTagVoting,
        ERC721TagManager _tagManager,
        ITrustlessManagement _trustlessManagement,
        ITrustlessManagement _addressTrustlessManagement,
        IOptimisticActions _optimisticActions,
        address _openRD,
        DepartmentOwnerSettings memory _departmentOwnerSettings
    ) {
        pluginSetupProcessor = _pluginSetupProcessor;
        aragonTagVoting = _aragonTagVoting;
        tagManager = _tagManager;
        trustlessManagement = _trustlessManagement;
        addressTrustlessManagement = _addressTrustlessManagement;
        optimsticActions = _optimisticActions;
        openRD = _openRD;

        daoBase = address(new DAO());
        _createDepartmentOwner(_departmentOwnerSettings);
    }

    /// @notice Creates a new DAO according to the Department Owner specification.
    /// @param _settings Initial DAO settings.
    function _createDepartmentOwner(DepartmentOwnerSettings memory _settings) internal {
        // Create DAO.
        DAO createdDao = DAO(payable(new ERC1967Proxy{salt: bytes32(0)}(daoBase, bytes(""))));

        // Initialize the DAO and give the `ROOT_PERMISSION_ID` permission to this contract.
        createdDao.initialize(_settings.metadata, address(this), address(0), "");

        // Grant the temporary permissions.
        _setupDAOPermissions(createdDao);

        // Token Voting
        PluginSettings[] memory pluginSettings = new PluginSettings[](1);
        pluginSettings[0] = PluginSettings(
            PluginSetupRef(PluginRepo.Tag(1, 1), _settings.tokenVoting),
            abi.encode(
                MajorityVotingBase.VotingSettings(
                    MajorityVotingBase.VotingMode.EarlyExecution, 50 * 10 ** 4, 20 * 10 ** 4, 1 days, 1
                ),
                TokenVotingSetup.TokenSettings(address(_settings.token), "", ""),
                GovernanceERC20.MintSettings(new address[](0), new uint256[](0))
            )
        );

        // Enable 7 day delayed optmistic token minting
        IDAO.Action[] memory actions = new IDAO.Action[](4);
        actions[0] = IDAO.Action(
            address(_settings.trustlessManagement),
            0,
            abi.encodeWithSelector(
                _settings.trustlessManagement.changeFunctionAccess.selector,
                address(createdDao),
                1, // Assumed ERC721CountTrustlessManagement
                address(optimsticActions),
                optimsticActions.createAction.selector,
                NO_PERMISSION_CHECKER
            )
        );
        actions[1] = IDAO.Action(
            address(_settings.trustlessManagement),
            0,
            abi.encodeWithSelector(
                _settings.trustlessManagement.changeFunctionAccess.selector,
                address(createdDao),
                1, // Assumed ERC721CountTrustlessManagement
                address(optimsticActions),
                optimsticActions.rejectAction.selector,
                NO_PERMISSION_CHECKER
            )
        );
        actions[2] = IDAO.Action(
            address(optimsticActions),
            0,
            abi.encodeWithSelector(optimsticActions.setExecuteDelay.selector, address(createdDao), 7 days)
        );
        actions[3] = IDAO.Action(
            address(addressTrustlessManagement),
            0,
            abi.encodeWithSelector(
                addressTrustlessManagement.changeFunctionAccess.selector,
                address(createdDao),
                uint160(address(optimsticActions)),
                address(_settings.token),
                _settings.token.mint.selector,
                NO_PERMISSION_CHECKER
            )
        );

        _installDAOPlugins(createdDao, pluginSettings, actions);

        // Set the rest of DAO's permissions and revoke the temporary setup ones.
        _finalizeDAOPermissions(createdDao, address(_settings.trustlessManagement));

        emit DepartmentOwnerCreated(createdDao);
    }

    /// @notice Creates a new DAO according to the Department specification.
    /// @param _metadata The metadata the DAO should be initilized with.
    /// @param _tag The tag that defines the members of the DAO.
    function createDepartment(bytes calldata _metadata, bytes32 _tag) external returns (DAO createdDao) {
        // Create DAO.
        createdDao = DAO(payable(new ERC1967Proxy{salt: _tag}(daoBase, bytes(""))));

        // Initialize the DAO and give the `ROOT_PERMISSION_ID` permission to this contract.
        createdDao.initialize(_metadata, address(this), address(0), "");

        // Grant the temporary permissions.
        _setupDAOPermissions(createdDao);

        // Aragon tag voting
        PluginSettings[] memory pluginSettings = new PluginSettings[](1);
        pluginSettings[0] = PluginSettings(
            PluginSetupRef(PluginRepo.Tag(1, 1), aragonTagVoting),
            abi.encode(
                MajorityVotingBase.VotingSettings(
                    MajorityVotingBase.VotingMode.EarlyExecution, 50 * 10 ** 4, 20 * 10 ** 4, 1 days, 1
                ),
                tagManager,
                _tag
            )
        );

        // Enable 7 day delayed OpenR&D actions
        IDAO.Action[] memory actions = new IDAO.Action[](4);
        actions[0] = IDAO.Action(
            address(trustlessManagement),
            0,
            abi.encodeWithSelector(
                trustlessManagement.changeFunctionAccess.selector,
                address(createdDao),
                _tag, // Assumed TagTrustlessManagement
                address(optimsticActions),
                optimsticActions.createAction.selector,
                NO_PERMISSION_CHECKER
            )
        );
        actions[1] = IDAO.Action(
            address(trustlessManagement),
            0,
            abi.encodeWithSelector(
                trustlessManagement.changeFunctionAccess.selector,
                address(createdDao),
                _tag, // Assumed TagTrustlessManagement
                address(optimsticActions),
                optimsticActions.rejectAction.selector,
                NO_PERMISSION_CHECKER
            )
        );
        actions[2] = IDAO.Action(
            address(optimsticActions),
            0,
            abi.encodeWithSelector(optimsticActions.setExecuteDelay.selector, address(createdDao), 7 days)
        );
        actions[3] = IDAO.Action(
            address(addressTrustlessManagement),
            0,
            abi.encodeWithSelector(
                addressTrustlessManagement.changeZoneAccess.selector,
                address(createdDao),
                uint160(address(optimsticActions)),
                openRD,
                NO_PERMISSION_CHECKER
            )
        );

        _installDAOPlugins(createdDao, pluginSettings, actions);

        // Set the rest of DAO's permissions and revoke the temporary setup ones.
        _finalizeDAOPermissions(createdDao, address(trustlessManagement));

        // Allow the department to manage their own tag.
        tagManager.grantRole(_tag, address(createdDao));

        emit DepartmentCreated(createdDao, _tag);
    }

    // Installs Aragon OSx plugins and a list of other setup actions
    function _installDAOPlugins(DAO _dao, PluginSettings[] memory _pluginSettings, IDAO.Action[] memory _actions)
        internal
    {
        // Get Permission IDs
        bytes32 applyInstallationPermissionID = pluginSetupProcessor.APPLY_INSTALLATION_PERMISSION_ID();

        // Grant Temporarly `APPLY_INSTALLATION_PERMISSION` on `pluginSetupProcessor` to this `DAOFactory`.
        _dao.grant(address(pluginSetupProcessor), address(this), applyInstallationPermissionID);

        // Install Aragon OSx plugins on the newly created DAO.
        for (uint256 i; i < _pluginSettings.length; ++i) {
            // Prepare plugin.
            (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData) = pluginSetupProcessor
                .prepareInstallation(
                address(_dao),
                PluginSetupProcessor.PrepareInstallationParams(
                    _pluginSettings[i].pluginSetupRef, _pluginSettings[i].data
                )
            );

            // Apply plugin.
            pluginSetupProcessor.applyInstallation(
                address(_dao),
                PluginSetupProcessor.ApplyInstallationParams(
                    _pluginSettings[i].pluginSetupRef,
                    plugin,
                    preparedSetupData.permissions,
                    hashHelpers(preparedSetupData.helpers)
                )
            );
        }

        // Revoke `APPLY_INSTALLATION_PERMISSION` on `pluginSetupProcessor` from this `DAOFactory` .
        _dao.revoke(address(pluginSetupProcessor), address(this), applyInstallationPermissionID);

        // Perform any other setup actions
        _dao.execute(DEPARTMENT_SETUP_EXECUTION_ID, _actions, 0);
    }

    /// @notice Sets the required permissions for the setup.
    /// @param _dao The DAO instance just created.
    function _setupDAOPermissions(DAO _dao) internal {
        // Set permissionIds on the dao itself.
        PermissionLib.SingleTargetPermission[] memory items = new PermissionLib.SingleTargetPermission[](2);

        // Grant all setup permissions required
        items[0] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Grant, address(pluginSetupProcessor), _dao.ROOT_PERMISSION_ID()
        );
        items[1] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Grant, address(this), _dao.EXECUTE_PERMISSION_ID()
        );

        _dao.applySingleTargetPermissions(address(_dao), items);
    }

    /// @notice Sets the required permissions for the new DAO and revokes the setup permissions.
    /// @param _dao The DAO instance just created.
    /// @param _trustlessManagement The trustless management instance to active (in addition to address trustless management).
    function _finalizeDAOPermissions(DAO _dao, address _trustlessManagement) internal {
        // Set permissionIds on the dao itself.
        PermissionLib.SingleTargetPermission[] memory items = new PermissionLib.SingleTargetPermission[](6);

        bytes32 rootPermission = _dao.ROOT_PERMISSION_ID();
        bytes32 executePermission = _dao.EXECUTE_PERMISSION_ID();

        // Grant admin all the permissions required
        items[0] = PermissionLib.SingleTargetPermission(PermissionLib.Operation.Grant, address(_dao), rootPermission);

        // Enable trustless management
        items[1] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Grant, address(addressTrustlessManagement), executePermission
        );
        items[2] =
            PermissionLib.SingleTargetPermission(PermissionLib.Operation.Grant, _trustlessManagement, executePermission);

        // Revoke setup granted permissions
        items[3] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Revoke, address(pluginSetupProcessor), rootPermission
        );
        items[4] = PermissionLib.SingleTargetPermission(PermissionLib.Operation.Revoke, address(this), rootPermission);
        items[5] =
            PermissionLib.SingleTargetPermission(PermissionLib.Operation.Revoke, address(this), executePermission);

        _dao.applySingleTargetPermissions(address(_dao), items);
    }
}
