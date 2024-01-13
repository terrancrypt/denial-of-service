// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {DenialOfService} from "src/DenialOfService.sol";

contract DeployDenialOfService is Script {
    DenialOfService denialOfService;

    function run(
        address owner,
        address _vrfCoordinator,
        uint64 _subscriptionId
    ) external returns (DenialOfService) {
        vm.startBroadcast();
        denialOfService = new DenialOfService(
            owner,
            _vrfCoordinator,
            _subscriptionId
        );
        vm.stopBroadcast();

        return denialOfService;
    }
}
