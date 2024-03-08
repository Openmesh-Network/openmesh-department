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

import {MajorityVotingBase, ITagManagerExtended} from "../lib/aragon-tag-voting/src/TagVotingSetup.sol";
import {ITrustlessManagement} from "../lib/trustless-management/src/ITrustlessManagement.sol";

import {OpenmeshENSReverseClaimable} from "../lib/openmesh-admin/src/OpenmeshENSReverseClaimable.sol";

bytes32 constant DEPARTMENT_SETUP_EXECUTION_ID = keccak256("DEPARTMENT_SETUP");

contract DepartmentFactory is OpenmeshENSReverseClaimable {
    event DepartmentCreated(IDAO department, bytes32 tag);

    /// @notice The DAO base contract, to be used for creating new `DAO`s via `createERC1967Proxy` function.
    address public immutable daoBase;

    /// @notice The plugin setup processor for installing plugins on the newly created `DAO`s.
    PluginSetupProcessor public immutable pluginSetupProcessor;

    /// @notice The repo used for the tag voting plugin installation.
    PluginRepo public immutable aragonTagVoting;

    /// @notice The tag manager used for the tag voting plugin installation.
    ITagManagerExtended public immutable tagManager;

    /// @notice The implemention used for the trustless management setup.
    ITrustlessManagement public immutable trustlessManagement;

    /// @notice The container with the information required to install a plugin on the DAO.
    /// @param pluginSetupRef The `PluginSetupRepo` address of the plugin and the version tag.
    /// @param data The bytes-encoded data containing the input parameters for the installation as specified in the plugin's build metadata JSON file.
    struct PluginSettings {
        PluginSetupRef pluginSetupRef;
        bytes data;
    }

    /// @notice The constructor setting the plugin setup processor and creating the base contracts for the factory.
    /// @param _pluginSetupProcessor The address of PluginSetupProcessor.
    constructor(
        PluginSetupProcessor _pluginSetupProcessor,
        PluginRepo _aragonTagVoting,
        ITagManagerExtended _tagManager,
        ITrustlessManagement _trustlessManagement
    ) {
        pluginSetupProcessor = _pluginSetupProcessor;
        aragonTagVoting = _aragonTagVoting;
        tagManager = _tagManager;
        trustlessManagement = _trustlessManagement;

        daoBase = address(new DAO());
    }

    /// @notice Creates a new DAO according to the Department specification.
    /// @param _metadata The metadata the DAO should be initilized with.
    /// @param _tag The tag that defines the members of the DAO.
    function createDao(bytes calldata _metadata, bytes32 _tag) external returns (DAO createdDao) {
        // Create DAO.
        createdDao = DAO(payable(new ERC1967Proxy{salt: _tag}(daoBase, bytes(""))));

        // Initialize the DAO and give the `ROOT_PERMISSION_ID` permission to this contract.
        createdDao.initialize(_metadata, address(this), address(0), "");

        // Get Permission IDs
        bytes32 applyInstallationPermissionID = pluginSetupProcessor.APPLY_INSTALLATION_PERMISSION_ID();

        // Grant the temporary permissions.
        _setupDAOPermissions(createdDao);

        // Grant Temporarly `APPLY_INSTALLATION_PERMISSION` on `pluginSetupProcessor` to this `DAOFactory`.
        createdDao.grant(address(pluginSetupProcessor), address(this), applyInstallationPermissionID);

        // Install plugins on the newly created DAO.
        PluginSettings[] memory _pluginSettings = new PluginSettings[](1);
        uint8 aragonTagVotingRelease = aragonTagVoting.latestRelease();
        uint16 aragonTagVotingVersion = uint16(aragonTagVoting.buildCount(aragonTagVotingRelease));
        _pluginSettings[0] = PluginSettings(
            PluginSetupRef(PluginRepo.Tag(aragonTagVotingRelease, aragonTagVotingVersion), aragonTagVoting),
            abi.encode(
                MajorityVotingBase.VotingSettings(
                    MajorityVotingBase.VotingMode.EarlyExecution, 50 * 10 ** 4, 20 * 10 ** 4, 1 days, 1
                ),
                tagManager,
                _tag
            )
        );
        for (uint256 i; i < _pluginSettings.length; ++i) {
            // Prepare plugin.
            (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData) = pluginSetupProcessor
                .prepareInstallation(
                address(createdDao),
                PluginSetupProcessor.PrepareInstallationParams(
                    _pluginSettings[i].pluginSetupRef, _pluginSettings[i].data
                )
            );

            // Apply plugin.
            pluginSetupProcessor.applyInstallation(
                address(createdDao),
                PluginSetupProcessor.ApplyInstallationParams(
                    _pluginSettings[i].pluginSetupRef,
                    plugin,
                    preparedSetupData.permissions,
                    hashHelpers(preparedSetupData.helpers)
                )
            );
        }

        // Revoke `APPLY_INSTALLATION_PERMISSION` on `pluginSetupProcessor` from this `DAOFactory` .
        createdDao.revoke(address(pluginSetupProcessor), address(this), applyInstallationPermissionID);

        // Set trustless management admin
        // Possibly a custom contract (inheriting from DAO) could be used instead, that calls this code during intialize
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0] = IDAO.Action(
            address(trustlessManagement),
            0,
            abi.encodeWithSelector(trustlessManagement.setAdmin.selector, address(createdDao), OPENMESH_ADMIN)
        );
        createdDao.execute(DEPARTMENT_SETUP_EXECUTION_ID, actions, 0);

        // Set the rest of DAO's permissions and revoke the temporary setup ones.
        _finalizeDAOPermissions(createdDao, OPENMESH_ADMIN);

        emit DepartmentCreated(createdDao, _tag);
    }

    /// @notice Sets the required permissions for the setup.
    /// @param _dao The DAO instance just created.
    function _setupDAOPermissions(DAO _dao) internal {
        // Set permissionIds on the dao itself.
        PermissionLib.SingleTargetPermission[] memory items = new PermissionLib.SingleTargetPermission[](2);

        // Grant admin all the permissions required
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
    /// @param _admin The address that should get the permissions to alter the dao.
    function _finalizeDAOPermissions(DAO _dao, address _admin) internal {
        // Set permissionIds on the dao itself.
        PermissionLib.SingleTargetPermission[] memory items = new PermissionLib.SingleTargetPermission[](5);

        bytes32 rootPermission = _dao.ROOT_PERMISSION_ID();
        bytes32 executePermission = _dao.EXECUTE_PERMISSION_ID();

        // Grant admin all the permissions required
        items[0] = PermissionLib.SingleTargetPermission(PermissionLib.Operation.Grant, _admin, rootPermission);

        // Enable trustless management
        items[1] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Grant, address(trustlessManagement), executePermission
        );

        // Revoke setup granted permissions
        items[2] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Revoke, address(pluginSetupProcessor), rootPermission
        );
        items[3] = PermissionLib.SingleTargetPermission(PermissionLib.Operation.Revoke, address(this), rootPermission);
        items[4] =
            PermissionLib.SingleTargetPermission(PermissionLib.Operation.Revoke, address(this), executePermission);

        _dao.applySingleTargetPermissions(address(_dao), items);
    }
}
