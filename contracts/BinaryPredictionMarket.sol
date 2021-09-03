pragma solidity ^0.4.23;
import "./utils/MintableERC20.sol";

contract PredictionMarket {
    address public owner;

    struct BinaryOption {
        string description;
        uint256 expiryBlock;
        bool resolved;
        Outcome outcome;
        uint256 totalBalance;
        mapping(uint8 => uint256) balances; // Outcome => balance
    }

    struct Prediction {
        uint256 amount;
        Outcome predictedOutcome;
        bool paidOut;
    }

    mapping(bytes32 => BinaryOption) public binaryOptions;
    mapping(address => mapping(bytes32 => Prediction)) public predictions; // maps address to predictions per Binary Option

    enum Outcome {
        Unresolved,
        Yes,
        No,
        Undecided
    }

    MintableToken[] public tokens;

    constructor() public {
        owner = msg.sender;
    }

    function getOutcomeBalance(bytes32 identifier, Outcome outcome) public view isValidOutcome(outcome) 
    returns (uint256 balance)
    {
        return binaryOptions[identifier].balances[uint8(outcome)];
    }

    function getTotalBalance(bytes32 identifier) public view 
    returns (uint256 totalBalance)
    {
        return binaryOptions[identifier].totalBalance;
    }

    function getOutcomePrice(bytes32 identifier, Outcome outcome) public view 
    returns (uint outcomePrice)
    {
        uint256 marketSize = getTotalBalance(identifier);
        uint256 outcomeSize = getOutcomeBalance(identifier, outcome);
        outcomePrice = outcomeSize / (marketSize); //change to use SafeMath.sol or add underflow/overflow checks
        return outcomePrice;
    }

    function addBinaryOption(bytes32 identifier, string description, uint256 durationInBlocks) public isOwner 
    returns (bool success) 
    {
        // Don't allow options with no expiry
        require(durationInBlocks > 0);

        // Check that this option does not exist already
        require(binaryOptions[identifier].expiryBlock == 0);

        BinaryOption memory option;
        option.expiryBlock = block.number + durationInBlocks;
        option.description = description;
        option.resolved = false;
        option.outcome = Outcome.Unresolved;

        binaryOptions[identifier] = option;
        // tokens.push(new MintableToken(0, 18, toString(option.outcome))) ;
        // tokens.push(new MintableToken(0, 18, toString(option.outcome)));
        //@dev create a token for affarmative and negative outcomes.

        return true;
    }

    function predict(bytes32 identifier, Outcome outcome)
        public
        payable
        isValidOutcome(outcome)
        returns (bool success)
    {
        // Must back your prediction
        require(msg.value > 0);

        // Require that the option exists
        require(binaryOptions[identifier].expiryBlock > 0);

        // Require that the option has not expired
        require(binaryOptions[identifier].expiryBlock >= block.number);

        // Require that the option has not been resolved
        require(!binaryOptions[identifier].resolved);

        // Don't allow duplicate bets
        require(predictions[msg.sender][identifier].amount == 0);

        BinaryOption storage option = binaryOptions[identifier];

        option.balances[uint8(outcome)] += msg.value;
        option.totalBalance += msg.value;

        Prediction memory prediction;
        prediction.amount = msg.value;
        prediction.predictedOutcome = outcome;
        predictions[msg.sender][identifier] = prediction;

        return true;
    }

    // Mark the option as resolved so that an outcome can be set
    // This must be done in a separate block from setting an outcome
    function resolveBinaryOption(bytes32 identifier)
        public
        isOwner
        returns (bool success)
    {
        BinaryOption storage option = binaryOptions[identifier];
        option.resolved = true;

        return true;
    }

    function setOptionOutcome(bytes32 identifier, Outcome outcome)
        public
        isOwner
        returns (bool success)
    {
        require(
            outcome == Outcome.Yes ||
                outcome == Outcome.No ||
                outcome == Outcome.Undecided
        );

        BinaryOption storage option = binaryOptions[identifier];

        require(option.resolved);

        option.outcome = outcome;

        return true;
    }

    function requestPayout(bytes32 identifier) public returns (bool success) {
        BinaryOption storage option = binaryOptions[identifier];

        // Option must exist
        require(option.expiryBlock > 0);

        Prediction storage prediction = predictions[msg.sender][identifier];

        // Prediction must exist
        require(prediction.amount > 0);

        // Don't pay out twice
        require(!prediction.paidOut);

        // If the outcome has not been resolved, require that the option has expired
        if (!option.resolved) {
            require(option.expiryBlock > block.number);
        }

        uint256 totalBalance = option.totalBalance;
        uint256 outcomeBalance = getOutcomeBalance(
            identifier,
            prediction.predictedOutcome
        );

        // Scaling factor of the outcome pool to the total balance
        uint256 r = 1;

        if (option.outcome != Outcome.Undecided) {
            // If the outcome was not undecided, they must have predicted the correct outcome
            require(prediction.predictedOutcome == option.outcome);

            r = totalBalance / outcomeBalance;
        }

        uint256 payoutAmount = r * prediction.amount;

        prediction.paidOut = true;
        option.totalBalance -= payoutAmount;
        msg.sender.transfer(payoutAmount);

        return true;
    }

    function toString(bytes32 b) internal pure 
    returns (string) {
        // Convert a null-terminated bytes32 to a string.

        uint256 length = 0;
        while (length < 32 && b[length] != 0) {
            length += 1;
        }

        bytes memory bytesString = new bytes(length);
        for (uint256 j = 0; j < length; j++) {
            bytesString[j] = b[j];
        }

        return string(bytesString);
    }

    function kill() public isOwner {
        selfdestruct(owner);
    }

    modifier isOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier isValidOutcome(Outcome outcome) {
        require(outcome == Outcome.Yes || outcome == Outcome.No);
        _;
    }
}
