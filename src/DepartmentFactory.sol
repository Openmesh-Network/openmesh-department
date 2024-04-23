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

import {MajorityVotingBase} from "../lib/aragon-tag-voting/src/TagVotingSetup.sol";
import {ERC721TagManager} from "../lib/tag-manager/src/ERC721TagManager.sol";
import {ITrustlessManagement, NO_PERMISSION_CHECKER} from "../lib/trustless-management/src/TrustlessManagement.sol";
import {IOptimisticActions} from "../lib/trustless-actions/src/IOptimisticActions.sol";
import {IVerifiedContributor} from "../lib/verified-contributor/src/IVerifiedContributor.sol";

import {OpenmeshENSReverseClaimable} from "../lib/openmesh-admin/src/OpenmeshENSReverseClaimable.sol";

bytes32 constant DEPARTMENT_SETUP_EXECUTION_ID = keccak256("DEPARTMENT_SETUP");

struct TokenSettings {
    address addr;
    string name;
    string symbol;
}

struct MintSettings {
    address[] receivers;
    uint256[] amounts;
}

contract DepartmentFactory is OpenmeshENSReverseClaimable {
    event DepartmentOwnerCreated(IDAO departmentOwner);
    event DepartmentCreated(IDAO department, bytes32 tag);

    /// @notice Settings for creating the department owner DAO.
    /// @param metadata Initial metadata of the DAO.
    /// @param tokenVoting Aragons Token Voting Repo.
    /// @param token Verified contributor collection to use for token voting.
    /// @param trustlessManagement Trustless management solution for creating optimistic actions.
    /// @param role Role to use for creating optimistic actions.
    /// @param addressTrustlessManagement Address trustless management for executing optimistic actions.
    /// @param optimisticActions The optimistic actions implementation.
    struct DepartmentOwnerSettings {
        bytes metadata;
        PluginRepo tokenVoting;
        IVerifiedContributor token;
        ITrustlessManagement trustlessManagement;
        uint256 role;
        ITrustlessManagement addressTrustlessManagement;
        IOptimisticActions optimisticActions;
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

    constructor(
        PluginSetupProcessor _pluginSetupProcessor,
        PluginRepo _aragonTagVoting,
        ERC721TagManager _tagManager,
        DepartmentOwnerSettings memory _departmentOwnerSettings
    ) {
        pluginSetupProcessor = _pluginSetupProcessor;
        aragonTagVoting = _aragonTagVoting;
        tagManager = _tagManager;

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
        _setupDAOPermissions(createdDao, true);

        // Token Voting
        PluginSettings[] memory pluginSettings = new PluginSettings[](1);
        uint8 release = _settings.tokenVoting.latestRelease();
        uint16 version = uint16(_settings.tokenVoting.buildCount(release));
        pluginSettings[0] = PluginSettings(
            PluginSetupRef(PluginRepo.Tag(release, version), _settings.tokenVoting),
            abi.encode(
                MajorityVotingBase.VotingSettings(
                    MajorityVotingBase.VotingMode.EarlyExecution, 50 * 10 ** 4, 20 * 10 ** 4, 1 days, 1
                ),
                TokenSettings(address(_settings.token), "", ""),
                MintSettings(new address[](0), new uint256[](0))
            )
        );

        // Enable 7 day delayed optimistic token minting
        IDAO.Action[] memory actions = new IDAO.Action[](4);
        actions[0] = IDAO.Action(
            address(_settings.trustlessManagement),
            0,
            abi.encodeWithSelector(
                _settings.trustlessManagement.changeFunctionAccess.selector,
                address(createdDao),
                _settings.role,
                address(_settings.optimisticActions),
                _settings.optimisticActions.createAction.selector,
                NO_PERMISSION_CHECKER
            )
        );
        actions[1] = IDAO.Action(
            address(_settings.trustlessManagement),
            0,
            abi.encodeWithSelector(
                _settings.trustlessManagement.changeFunctionAccess.selector,
                address(createdDao),
                _settings.role,
                address(_settings.optimisticActions),
                _settings.optimisticActions.rejectAction.selector,
                NO_PERMISSION_CHECKER
            )
        );
        actions[2] = IDAO.Action(
            address(_settings.optimisticActions),
            0,
            abi.encodeWithSelector(_settings.optimisticActions.setExecuteDelay.selector, address(createdDao), 7 days)
        );
        actions[3] = IDAO.Action(
            address(_settings.addressTrustlessManagement),
            0,
            abi.encodeWithSelector(
                _settings.addressTrustlessManagement.changeFunctionAccess.selector,
                address(createdDao),
                uint160(address(_settings.optimisticActions)),
                address(_settings.token),
                _settings.token.mint.selector,
                NO_PERMISSION_CHECKER
            )
        );

        _installDAOPlugins(createdDao, pluginSettings, actions);

        // Enable trustless management
        bytes32 executePermission = createdDao.EXECUTE_PERMISSION_ID();
        PermissionLib.SingleTargetPermission[] memory trustlessManagementPermissions =
            new PermissionLib.SingleTargetPermission[](2);
        trustlessManagementPermissions[0] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Grant, address(_settings.trustlessManagement), executePermission
        );
        trustlessManagementPermissions[1] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Grant, address(_settings.addressTrustlessManagement), executePermission
        );
        createdDao.applySingleTargetPermissions(address(createdDao), trustlessManagementPermissions);

        // Set the rest of DAO's permissions and revoke the temporary setup ones.
        _finalizeDAOPermissions(createdDao, true);

        emit DepartmentOwnerCreated(createdDao);
    }

    /// @notice Creates a new DAO according to the Department specification.
    /// @param _metadata The metadata the DAO should be initialized with.
    /// @param _tag The tag that defines the members of the DAO.
    function createDepartment(bytes calldata _metadata, bytes32 _tag) external returns (DAO createdDao) {
        // Create DAO.
        createdDao = DAO(payable(new ERC1967Proxy{salt: _tag}(daoBase, bytes(""))));

        // Initialize the DAO and give the `ROOT_PERMISSION_ID` permission to this contract.
        createdDao.initialize(_metadata, address(this), address(0), "");

        // Grant the temporary permissions.
        _setupDAOPermissions(createdDao, false);

        // Aragon tag voting
        PluginSettings[] memory pluginSettings = new PluginSettings[](1);
        uint8 release = aragonTagVoting.latestRelease();
        uint16 version = uint16(aragonTagVoting.buildCount(release));
        pluginSettings[0] = PluginSettings(
            PluginSetupRef(PluginRepo.Tag(release, version), aragonTagVoting),
            abi.encode(
                MajorityVotingBase.VotingSettings(
                    MajorityVotingBase.VotingMode.EarlyExecution, 50 * 10 ** 4, 20 * 10 ** 4, 1 days, 1
                ),
                tagManager,
                _tag
            )
        );

        IDAO.Action[] memory actions = new IDAO.Action[](0);
        _installDAOPlugins(createdDao, pluginSettings, actions);

        // Set the rest of DAO's permissions and revoke the temporary setup ones.
        _finalizeDAOPermissions(createdDao, false);

        emit DepartmentCreated(createdDao, _tag);
    }

    // Installs Aragon OSx plugins and a list of other setup actions
    function _installDAOPlugins(DAO _dao, PluginSettings[] memory _pluginSettings, IDAO.Action[] memory _actions)
        internal
    {
        // Get Permission IDs
        bytes32 applyInstallationPermissionID = pluginSetupProcessor.APPLY_INSTALLATION_PERMISSION_ID();

        // Grant Temporary `APPLY_INSTALLATION_PERMISSION` on `pluginSetupProcessor` to this `DAOFactory`.
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

        if (_actions.length != 0) {
            // Perform any other setup actions
            _dao.execute(DEPARTMENT_SETUP_EXECUTION_ID, _actions, 0);
        }
    }

    /// @notice Sets the required permissions for the setup.
    /// @param _dao The DAO instance just created.
    /// @param _grantExecute If the setup involves executing actions as the DAO.
    function _setupDAOPermissions(DAO _dao, bool _grantExecute) internal {
        // Set permissionIds on the dao itself.
        PermissionLib.SingleTargetPermission[] memory items =
            new PermissionLib.SingleTargetPermission[](_grantExecute ? 2 : 1);

        // Grant all setup permissions required
        items[0] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Grant, address(pluginSetupProcessor), _dao.ROOT_PERMISSION_ID()
        );
        if (_grantExecute) {
            items[1] = PermissionLib.SingleTargetPermission(
                PermissionLib.Operation.Grant, address(this), _dao.EXECUTE_PERMISSION_ID()
            );
        }

        _dao.applySingleTargetPermissions(address(_dao), items);
    }

    /// @notice Sets the required permissions for the new DAO and revokes the setup permissions.
    /// @param _dao The DAO instance just created.
    /// @param _revokeExecute If the setup was granted temporary execute permission.
    function _finalizeDAOPermissions(DAO _dao, bool _revokeExecute) internal {
        // Set permissionIds on the dao itself.
        PermissionLib.SingleTargetPermission[] memory items =
            new PermissionLib.SingleTargetPermission[](_revokeExecute ? 4 : 3);

        bytes32 rootPermission = _dao.ROOT_PERMISSION_ID();
        bytes32 executePermission = _dao.EXECUTE_PERMISSION_ID();

        // Grant admin all the permissions required
        items[0] = PermissionLib.SingleTargetPermission(PermissionLib.Operation.Grant, address(_dao), rootPermission);

        // Revoke setup granted permissions
        items[1] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Revoke, address(pluginSetupProcessor), rootPermission
        );
        items[2] = PermissionLib.SingleTargetPermission(PermissionLib.Operation.Revoke, address(this), rootPermission);
        if (_revokeExecute) {
            items[3] =
                PermissionLib.SingleTargetPermission(PermissionLib.Operation.Revoke, address(this), executePermission);
        }

        _dao.applySingleTargetPermissions(address(_dao), items);
    }
}
