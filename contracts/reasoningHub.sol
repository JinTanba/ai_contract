// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FunctionsClient} from "@chainlink/contracts@1.1.1/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts@1.1.1/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface IReasoning {
    function getArgs(bytes memory params) external view returns(Types.FunctionArgs memory);
    function receiveReasoningResult(bytes memory result, uint256 actionId, address sender) external;
}

contract ReasoningHub is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;
    using Strings for uint256;

    address router = 0xf9B8fc078197181C841c296C876945aaa425B278;
    bytes32 donID = 0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000;
    uint32 gasLimit = 300000;
    uint256 actionCount;

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
        emit ActionUploaded(actionCount,msg.sender);
        return actionCount;
    }

    function getAction(uint256 id) external pure returns(Types.Action memory) {
        return Storage._action(id);
    }

    function executeAction(
        bytes memory encryptedSecretsUrls,
        uint256 actionId,
        bytes memory params,
        address _client,
        Types.FunctionArgs memory _functionArgs
    ) external {
        uint64 subId = Storage._subscription()[msg.sender];
        Types.FunctionArgs memory functionArgs = _functionArgs.args.length == 0 && _functionArgs.bytesArgs.length == 0 ? IReasoning(_client).getArgs(params) : _functionArgs;
        Types.Action storage action = Storage._action(actionId);
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(action.code);
        req.addSecretsReference(encryptedSecretsUrls);
        req.setArgs(setArgs(functionArgs.args, action.prompt));
        req.setBytesArgs(functionArgs.bytesArgs);
        bytes32 requestId = _sendRequest(
            req.encodeCBOR(),
            subId,
            gasLimit,
            donID
        );
        Storage._stack(requestId).clientAddress = _client;
        Storage._stack(requestId).actionId = actionId;
        Storage._stack(requestId).functionArgs = functionArgs;
        Storage._stack(requestId).sender = msg.sender;
    }

    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        Types.Promise memory _promise = Storage._stack(requestId);
        require(err.length == 0 || _promise.sender != address(0), "error execute code");
        IReasoning(_promise.clientAddress).receiveReasoningResult(response, _promise.actionId, _promise.sender);
        emit OnchainReasoning(_promise.actionId, response, _promise.clientAddress,_promise.sender,_promise.functionArgs.args, _promise.functionArgs.bytesArgs);
    }

    function setArgs(string[] memory args, string memory prompt) public pure returns(string[] memory) {
        string[] memory completeArgs = new string[](args.length + 1);
        completeArgs[0] = prompt;
        for(uint i = 0; i < args.length; i++) {
            completeArgs[i+1] = args[i];
        }
        return completeArgs;
    }

    function join(uint64 subscriptionId) external {
        Storage._subscription()[msg.sender] = subscriptionId;
        emit SetSubscription(subscriptionId, msg.sender);
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
    }
}

library Storage {
    uint8 constant SUBSCRIPTION_SLOT = 1;
    uint8 constant ACTION_SLOT = 2;
    uint8 constant STACK_SLOT = 3;

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
}