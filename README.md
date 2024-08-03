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
## Onchain Content Moderation:
We recommend the use of this contract for platforms that are frequently criticized for content moderation due to opaque processes. In other words, it does the following.
1. set policy through a democratic process by users (e.g.; no violent content. etc.)
2. set up the prompt as an Action in the reasoningHub.
(e.g.,  {{content}} is against {{DAO_PLICY}} or output true/flase)

When a post suspected of violating the policy is found, LLM's inference is executed via contract by the Action registered in step 2.

This method can be used to bring transparency and fairness to content moderation.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "./reasoningHub.sol";

contract Polikore is IReasoning {
    address immutable hub;
    address immutable gov;
    uint256 public aiActionId;
    mapping(uint256 => Post) public posts;
    mapping(uint256 => bool) public blockedPosts;
    uint256 public objectionCount;
    uint256 public lastReviewedObjectionId;

    struct Post {
        address author;
        string content;
        uint256 timestamp;
    }

    event PostObjected(uint256 indexed objectionId, address indexed author, string content);
    event PostsReviewed(uint256 fromObjectionId, uint256 toObjectionId, uint256[] blockedPostIds);

    constructor(address _hub, address _gov) {
        hub = _hub;
        gov = _gov;

        string memory prompt = 
        "You are an AI that determines whether or not a social networking post violates the stated policy. "
        "1. First review the public policy guidelines. "
        "<policy>"
        "1. Hate speech and discrimination: Discriminatory statements or offensive content based on race, ethnicity, nationality, religion, gender, sexual orientation, age, disability, or other protected characteristics are forbidden."
        "2. Sharing personal information: Sharing others' personal information (address, phone number, email, etc.) without permission is prohibited."
        "3. Spreading misinformation: Intentionally spreading false information or fake news is not allowed."
        "4. Copyright infringement: Unauthorized use or distribution of copyrighted content is prohibited."
        "5. Promotion of illegal activities: Advertising or encouraging illegal activities or products is forbidden."
        "Posts that violate this policy may be removed, and users who repeatedly violate these guidelines may be subject to account suspension or permanent banning."
        "</policy>"
        "2. Please review the list of submissions below and consider whether each submission violates the policy guidelines."
        "<posts>"
        "{{POSTS}}"
        "</posts>"
        "3. Output the results according to the following output format."
        "<violating_posts>"
        "[List of IDs of posts that violate the policy]"
        "</violating_posts>"
        "4. Ensure that the violating_posts section contains a valid array of post IDs, even if the array is empty. For example:"
        "- If there are violating posts: [1, 3, 5]"
        "- If there are no violating posts: []";


        string memory code =
           "const ethers = await import('npm:ethers@5.7.0');"
            "const Anthropic = await import('npm:@anthropic-ai/sdk');"
            ""
            "// Decode the bytesArgs"
            "const decoder = new ethers.utils.AbiCoder();"
            ""
            "const objectedPosts = decoder.decode(['tuple(address author, string content, uint256 timestamp)[]'], bytesArgs[0])[0];"
            ""
            "// Prepare the prompt with the objected posts"
            "let postsDescription = objectedPosts.map((post, index) => "
            "  `${index}.${post.content}\n`"
            ").join('\n');"
            ""
            "const prompt = args[0];"
            ""
            "// Call Anthropic API"
            "const anthropic = new Anthropic.Anthropic({"
            "  apiKey: secrets.apiKey,"
            "});"
            "let response;"
            "try {"
            "    response = await anthropic.messages.create({"
            "        model: 'claude-3-sonnet-20240229',"
            "        max_tokens: 1000,"
            "        temperature: 0,"
            "        messages: ["
            "          {"
            "            role: 'user',"
            "            content: ["
            "              {"
            "                type: 'text',"
            "                text: prompt.replace('{{POSTS}}', postsDescription)"
            "              }"
            "            ]"
            "          }"
            "        ]"
            "      });"
            ""
            "} catch (e) {"
            "    console.error('Error calling Anthropic API:', e);"
            "    response = { content: [{ text: 'Error calling Anthropic API' }] };"
            "}"
            ""
            "function extractTagContent(xml, tagName) {"
            "    const startTag = `<${tagName}>`;"
            "    const endTag = `</${tagName}>`;"
            "    const startIndex = xml.indexOf(startTag);"
            "    const endIndex = xml.indexOf(endTag, startIndex + startTag.length);"
            ""
            "    if (startIndex === -1 || endIndex === -1) {"
            "        return '';"
            "    }"
            ""
            "    return xml.slice(startIndex + startTag.length, endIndex);"
            "}"
            "// Extract the result from the Anthropic response"
            "const result = response.content[0].text;"
            ""
            "// Convert the array to a string representation"
            "const resultString = extractTagContent(result, 'violating_posts');"
            "console.log('Result:', resultString);"
            ""
            "// Return the result"
            "return Functions.encodeString(resultString);";

        aiActionId = ReasoningHub(_hub).uploadAction(prompt, code);
    }

    function renewAction(string memory prompt, string memory code) external {
        require(msg.sender == gov, "only gov");
        Types.Action memory action = ReasoningHub(hub).getAction(aiActionId);
        string memory newcode = bytes(code).length > 0 ? code : action.code;
        string memory newPrompt = bytes(prompt).length > 0 ? prompt : action.prompt;
        aiActionId = ReasoningHub(hub).uploadAction(newPrompt, newcode);
    }

    function objection(address author, string memory content) external {
        objectionCount++;
        posts[objectionCount] = Post(author, content, block.timestamp);
        emit PostObjected(objectionCount, author, content);
    }

    function getArgs(bytes memory) external view override returns(Types.FunctionArgs memory) {
        uint256 fromObjectionId = lastReviewedObjectionId;
        uint256 toObjectionId = objectionCount;
        
        require(toObjectionId > fromObjectionId, "No new objections to review");
        
        uint256 postCount = toObjectionId - fromObjectionId;
        Post[] memory objectedPosts = new Post[](postCount);
        
        for (uint256 i = 0; i < postCount; i++) {
            uint256 postId = fromObjectionId + i + 1;
            objectedPosts[i] = posts[postId];
        }

        bytes[] memory bytesArgs = new bytes[](1);
        bytesArgs[0] = abi.encode(objectedPosts);

        return Types.FunctionArgs({
            args: new string[](0),
            bytesArgs: bytesArgs
        });
    }

    function receiveReasoningResult(bytes memory result, uint256 actionId, address sender) external override {
        require(msg.sender == hub, "Only hub can call this function");
        require(actionId == aiActionId, "Invalid action ID");

        string memory resultString = string(result);
        uint256[] memory blockedPostIds = _stringToUintArray(resultString);

        for (uint256 i = 0; i < blockedPostIds.length; i++) {
            uint256 postId = lastReviewedObjectionId + blockedPostIds[i];
            if (postId <= objectionCount) {
                blockedPosts[postId] = true;
            }
        }

        uint256 newLastReviewedObjectionId = objectionCount;
        emit PostsReviewed(lastReviewedObjectionId + 1, newLastReviewedObjectionId, blockedPostIds);
        lastReviewedObjectionId = newLastReviewedObjectionId;
    }

    function _stringToUintArray(string memory input) internal pure returns (uint256[] memory) {
        bytes memory inputBytes = bytes(input);
        uint256 count = 1;

        for (uint256 i = 1; i < inputBytes.length - 1; i++) {
            if (inputBytes[i] == ',') {
                count++;
            }
        }

        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        uint256 currentNum = 0;
        bool parsingNumber = false;

        for (uint256 i = 1; i < inputBytes.length - 1; i++) {
            if (inputBytes[i] >= '0' && inputBytes[i] <= '9') {
                currentNum = currentNum * 10 + (uint256(uint8(inputBytes[i])) - 48);
                parsingNumber = true;
            } else if (inputBytes[i] == ',' && parsingNumber) {
                result[index++] = currentNum;
                currentNum = 0;
                parsingNumber = false;
            }
        }

        if (parsingNumber) {
            result[index] = currentNum;
        }

        return result;
    }


    function getPost(uint256 objectionId) external view returns (address author, string memory content, uint256 timestamp) {
        Post memory post = posts[objectionId];
        return (post.author, post.content, post.timestamp);
    }
}
```




