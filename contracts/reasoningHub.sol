// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FunctionsClient} from "@chainlink/contracts@1.1.1/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts@1.1.1/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts@1.1.1/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC677 {
  event Transfer(address indexed from, address indexed to, uint256 value, bytes data);
  function transferAndCall(address to, uint256 amount, bytes memory data) external returns (bool);
}

interface IRouterForGetSubscriptionBalance {
    struct Subscription {
        uint96 balance;
        address owner;
        uint96 blockedBalance;
        address proposedOwner;
        address[] consumers;
        bytes32 flags;
    }
    function getSubscription(uint64 subscriptionId) external view returns (Subscription memory);
}

// !!! !If you use ReasoningHub in your contract you have to inherit IReasoning!!!!
// !!!! If you use ReasoningHub in your contract you have to inherit IReasoning!!!!
interface IReasoning {
    function reasoningCallback(bytes memory result, uint256 actionId, address sender) external;
}
// !!!! If you use ReasoningHub in your contract you have to inherit IReasoning!!!!
// !!!! If you use ReasoningHub in your contract you have to inherit IReasoning!!!!

contract ReasoningHub is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;
    using Strings for uint256;

    address router = 0xf9B8fc078197181C841c296C876945aaa425B278;
    bytes32 donID = 0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000;
    address link = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;
    uint32 gasLimit = 300000;
    uint256 actionCount;
    uint64 subscriptionId=147;

    constructor() FunctionsClient(router) ConfirmedOwner(msg.sender) {}

    event OnchainReasoning(uint256 indexed actionId, bytes result, address client, address sender, string[] args, bytes[] bytesArgs);
    event Response(bytes32 indexed requestId, bytes response, bytes err);
    event SetSubscription(uint256 subscriptionId, address sender);
    event ActionUploaded(uint256 actionId, address sender);

    function uploadAction(string memory prompt, string memory code) external returns (uint256) {
        actionCount++;
        Types.Action storage action = Storage._action(actionCount);
        action.prompt = prompt;
        action.code = code;
        emit ActionUploaded(actionCount, msg.sender);
        return actionCount;
    }

    function getAction(uint256 id) external pure returns(Types.Action memory) {
        return Storage._action(id);
    }

    function getSubscriptionBalance() internal view returns(uint256) {
        return IRouterForGetSubscriptionBalance(router).getSubscription(subscriptionId).balance;
    }

    function executeAction(
        bytes memory encryptedSecretsUrls,
        uint256 actionId,
        Types.FunctionArgs memory functionArgs,
        uint256 sendAmount,
        address linkOwner
    ) external {
        uint256 oldBalance = getSubscriptionBalance();
        // Types.FunctionArgs memory functionArgs = _functionArgs.args.length == 0 && _functionArgs.bytesArgs.length == 0 ? IReasoning(_client).getArgs() : _functionArgs;
        Types.Action storage action = Storage._action(actionId);
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(action.code);
        req.addSecretsReference(encryptedSecretsUrls);
        req.setArgs(setArgs(functionArgs.args, action.prompt));
        req.setBytesArgs(functionArgs.bytesArgs);
        bytes32 requestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            gasLimit,
            donID
        );
        Storage._stack(requestId).clientAddress = msg.sender;
        Storage._stack(requestId).actionId = actionId;
        Storage._stack(requestId).functionArgs = functionArgs;
        Storage._stack(requestId).sender = linkOwner;
        Storage._stack(requestId).oldBalance = oldBalance;

        depositLink(linkOwner, sendAmount);
    }

    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        Types.Promise memory _promise = Storage._stack(requestId);
        uint256 payedLink = Storage._linkDeposit()[_promise.sender];
        uint256 newBalance = getSubscriptionBalance();
        uint256 usedLink = _promise.oldBalance - newBalance;
        IReasoning(_promise.clientAddress).reasoningCallback(response, _promise.actionId, _promise.sender);
        refund(payedLink - usedLink, _promise.sender);
        emit OnchainReasoning(_promise.actionId, response, _promise.clientAddress, _promise.sender, _promise.functionArgs.args, _promise.functionArgs.bytesArgs);
        emit Response(requestId, response, err);
    }

    function setArgs(string[] memory args, string memory prompt) public pure returns(string[] memory) {
        string[] memory completeArgs = new string[](args.length + 1);
        completeArgs[0] = prompt;
        for(uint i = 0; i < args.length; i++) {
            completeArgs[i+1] = args[i];
        }
        return completeArgs;
    }

    // LINK token management functions
    function depositLink(address to, uint256 sendAmount) public {
        Storage._linkDeposit()[to] += sendAmount;
        IERC20(link).transferFrom(to, address(this), sendAmount);
    }

    function refund(uint256 amount, address sender) internal {
        IERC677(link).transferAndCall(router, amount, abi.encode(subscriptionId));
        uint256 depositBalance = Storage._linkDeposit()[sender];
        if(depositBalance > amount) {
            IERC20(link).transfer(sender, depositBalance - amount);
        }
        Storage._linkDeposit()[sender] -= amount;
    }

}

library Types {
    struct Action {
        string prompt;
        string code;
    }

    struct FunctionArgs {
        string[] args;
        bytes[] bytesArgs;
    }

    struct Promise {
        address clientAddress;
        uint256 actionId;
        FunctionArgs functionArgs;
        address sender;
        uint256 oldBalance;
    }
}

library Storage {
    uint8 constant SUBSCRIPTION_SLOT = 1;
    uint8 constant ACTION_SLOT = 2;
    uint8 constant STACK_SLOT = 3;
    uint8 constant LINK_DEPOSIT_SLOT = 4;

    function _action(uint256 id) internal pure returns(Types.Action storage _s) {
        assembly {
            mstore(0, ACTION_SLOT)
            mstore(32, id)
            _s.slot := keccak256(0, 64)
        }
    }

    function _subscription() internal pure returns(mapping(address => uint64) storage _s) {
        assembly {
            mstore(0, SUBSCRIPTION_SLOT)
            _s.slot := keccak256(0, 32)
        }
    }

    function _stack(bytes32 requestId) internal pure returns(Types.Promise storage _s) {
        assembly {
            mstore(0, STACK_SLOT)
            mstore(32, requestId)
            _s.slot := keccak256(0, 64)
        }
    }

    function _linkDeposit() internal pure returns(mapping(address => uint256) storage _s) {
        assembly {
            mstore(0, LINK_DEPOSIT_SLOT)
            _s.slot := keccak256(0, 32)
        }
    }
}