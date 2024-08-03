# How to describe llm inferences in protocols by Chainlink
```
██╗     ██╗     ███╗   ███╗
██║     ██║     ████╗ ████║
██║     ██║     ██╔████╔██║
██║     ██║     ██║╚██╔╝██║
███████╗███████╗██║ ╚═╝ ██║
╚══════╝╚══════╝╚═╝     ╚═╝
```
The reasoningHub makes it possible to prove the connection between the results of LLM reasoning and the process (prompt and code) through smart contracts and chainlinkFunction, providing reasoning application developers with a way to describe reasoning that is transparent and traceable, For contract developers, it additionally provides an easy way to describe llm reasoning in protocols and Dapps.


Saves the Action composed by the Prompt and code to the contract. By calling it via id and executing it via Chainlink FUnctions, the LLM's reasoning and processes can prove their connection by ethreum security!
SaveAction:
```solidity
    function uploadAction(string memory prompt, string memory code) external returns (uint256) {
        actionCount++;
        Types.Action storage action = Storage._action(actionCount);
        action.prompt = prompt;
        action.code = code;
        emit ActionUploaded(actionCount,msg.sender);
        return actionCount;
    }

```
executeAction bia ChinalinkFunctions
```solidity
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
```



## UseCase
Onchain Content Moderation:
As Lens Protocol and Farcaster become successful and grow in scale, the need for content moderation may arise. However, unlike X, this cannot be done centrally.
1. have DAOs determine regulatory policies through a democratic process
(2) Ask the LLM to make a decision by giving a prompt such as "output true/false if {{content}} violates {{dao_policy}} or not", rather than having a human manually do it

The problem here is that it is impossible to prove that the judgment made by the LLM in step 2 is really based on the policy set by the DAO.
How can we tamper with the prompt in the process of running the LLM to prevent unjust suppression by the center, or to prove that no such injustice has been done?

Here, the proposed reasoningContract solves this.
When the DAO decides on a prompt, it can send it to the reasoningContract and then solve the reasoningContract when it performs the judgment.




