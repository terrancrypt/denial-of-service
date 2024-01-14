// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {DeployDenialOfService} from "script/DeployDenialOfService.s.sol";
import {DenialOfService, AttackDenialOfService} from "src/DenialOfService.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";

contract DenialOfServiceTest is Test {
    DeployDenialOfService deployer;
    DenialOfService denialOfService;

    // Chainlink VRF V2 Mock
    uint96 baseFee = 0.25 ether;
    uint96 gasPriceLink = 1e9;
    VRFCoordinatorV2Mock vrfCoordinatorMock;
    uint64 vrfSubId;

    address owner = makeAddr("owner");
    address attacker = makeAddr("attacker");

    uint constant START_AMOUNT = 10 ether;
    uint constant PARTICIPANT_FEE = 1 ether;

    function setUp() external {
        // Chainlink VRF Mock
        vrfCoordinatorMock = new VRFCoordinatorV2Mock(baseFee, gasPriceLink);
        vrfSubId = vrfCoordinatorMock.createSubscription();
        uint96 fundAmount = 3 ether;
        vrfCoordinatorMock.fundSubscription(vrfSubId, fundAmount);

        deal(owner, START_AMOUNT);
        deal(attacker, START_AMOUNT);

        deployer = new DeployDenialOfService();
        denialOfService = deployer.run(
            owner,
            address(vrfCoordinatorMock),
            vrfSubId
        );

        vm.prank(owner);
        denialOfService.setFee(PARTICIPANT_FEE);

        vrfCoordinatorMock.addConsumer(vrfSubId, address(denialOfService));
    }

    modifier addParticipants() {
        uint256 playersNum = 100;
        address[] memory players = new address[](playersNum);
        for (uint256 i = 0; i < playersNum; i++) {
            players[i] = address(uint160(i));
        }

        deal(owner, PARTICIPANT_FEE * playersNum);
        vm.prank(owner);
        uint256 gasStart = gasleft();
        denialOfService.enterRaffle{value: PARTICIPANT_FEE * playersNum}(
            players
        );
        _;
    }

    function test_canEnterRaffle() public {
        vm.txGasPrice(1);

        // Thêm vào 100 players
        uint256 playersNum = 100;
        address[] memory players = new address[](playersNum);
        for (uint256 i = 0; i < playersNum; i++) {
            players[i] = address(uint160(i));
        }

        deal(owner, PARTICIPANT_FEE * playersNum);
        vm.prank(owner);
        uint256 gasStart = gasleft();
        denialOfService.enterRaffle{value: PARTICIPANT_FEE * playersNum}(
            players
        );
        uint256 gasEnd = gasleft();
        uint256 gasUsed = (gasStart - gasEnd) * tx.gasprice;

        console.log("Gas price of first 100 players:", gasUsed);

        // Thêm tiếp 100 players lần thứ 2
        address[] memory secondPlayers = new address[](playersNum);
        for (uint256 i = 0; i < playersNum; i++) {
            secondPlayers[i] = address(uint160(i + playersNum));
        }

        deal(owner, PARTICIPANT_FEE * playersNum);
        vm.prank(owner);
        uint256 gasStart2nd = gasleft();
        denialOfService.enterRaffle{value: PARTICIPANT_FEE * playersNum}(
            secondPlayers
        );
        uint256 gasEnd2nd = gasleft();
        uint256 gasUsed2nd = (gasStart2nd - gasEnd2nd) * tx.gasprice;

        console.log("Gas price of 2nd 100 players", gasUsed2nd);
    }

    function test_canGetTheWinner() public addParticipants {
        vm.prank(owner);
        uint256 requestId = denialOfService.getWinner();

        vrfCoordinatorMock.fulfillRandomWords(
            requestId,
            address(denialOfService)
        );

        // address winner = denialOfService.getRecentWinner();

        // console.log(winner);
    }

    function test_canAttackToDenialOfService() public {
        uint256 numberOfContract = 10;
        address[] memory attackContracts = new address[](numberOfContract);
        for (uint256 i; i < numberOfContract; i++) {
            AttackDenialOfService attackContract = new AttackDenialOfService(
                address(denialOfService)
            );
            attackContracts[i] = address(attackContract);
        }

        vm.prank(attacker);
        denialOfService.enterRaffle{value: numberOfContract * PARTICIPANT_FEE}(
            attackContracts
        );

        vm.prank(owner);
        uint256 requestId = denialOfService.getWinner();

        vrfCoordinatorMock.fulfillRandomWords(
            requestId,
            address(denialOfService)
        );

        // vm.prank(0xc7183455a4C133Ae270771860664b6B7ec320bB1);
        // denialOfService.claimPrize();

        // vm.prank(owner);
        // denialOfService.sentPrizeToWinner();
    }
}
