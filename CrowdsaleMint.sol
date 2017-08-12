pragma solidity ^0.4.11;


contract SafeMath{
	function safeMul(uint a, uint b) internal returns (uint) {
		uint c = a * b;
		assert(a == 0 || c / a == b);
		return c;
	}

	function safeDiv(uint a, uint b) internal returns (uint) {
		assert(b > 0);
		uint c = a / b;
		assert(a == b * c + a % b);
		return c;
	}

	function safeSub(uint a, uint b) internal returns (uint) {
		assert(b <= a);
		return a - b;
	}

	function safeAdd(uint a, uint b) internal returns (uint) {
		uint c = a + b;
		assert(c >= a);
		return c;
	}
	function assert(bool assertion) internal {
		if (!assertion) {
			revert();
		}
	}
}


// Contract that defines administrative actions
contract admined {

	// Define adminitrator address
	address public admin;

	// Entry function sets the admin as the sender
	function admined(){
		admin = msg.sender;
	}

	// Check if the sender is the admin
	modifier onlyAdmin(){
		require(msg.sender == admin);
		_;
	}

	// Transfer the admin role to a new address
	function transferAdminship(address newAdmin) onlyAdmin {
		admin = newAdmin;
	}
}

// Contract that creates the Token
contract Token is SafeMath {

	// Contract balance
	mapping (address => uint256) public balanceOf;
	// Token name
	string public name;
	// Token symbol
	string public symbol;
	// Decimals to use
	uint8 public decimal; 
	// Total initial suppy
	uint256 public totalSupply;
	// Transfer function interface
	event Transfer(address indexed from, address indexed to, uint256 value);

	// Token creation function
	function Token(uint256 initialSupply, string tokenName, string tokenSymbol, uint8 decimalUnits){
		// set the balance of the creator to the initial supply
		balanceOf[msg.sender] = initialSupply;
		totalSupply = initialSupply;
		decimal = decimalUnits;
		symbol = tokenSymbol;
		name = tokenName;
	}

	// Transfer function used to send tokens to an address
	function transfer(address _to, uint256 _value){
		// Check if the creator actually has the required balance
		require(balanceOf[msg.sender] >= _value);
		// Check if the amount sent will not overflow
		require(safeAdd(balanceOf[_to], _value) >= balanceOf[_to]);
		// Substract tokens from the creator
		balanceOf[msg.sender] = safeSub(balanceOf[msg.sender], _value);
		// Add tokens to the transfer address
		balanceOf[_to] = safeAdd(balanceOf[_to], _value);
		// Execute the transfer
		Transfer(msg.sender, _to, _value);
	}
}

// Contract that creates a token which inherits
// the administrator contract properties and token contract properties
contract AssetToken is admined, Token{

	// Create the token
	function AssetToken(uint256 initialSupply, string tokenName, string tokenSymbol, uint8 decimalUnits, address centralAdmin) Token (0, tokenName, tokenSymbol, decimalUnits ){
		// set the total supply to the initial supply
		totalSupply = initialSupply;
		// If there there is an admin address supplied
		if(centralAdmin != 0)
			// If yes then set admin to the supplied value
			admin = centralAdmin;
		else
			// otherwise set the admin as the creator of the contract
			admin = msg.sender;
		// Set the balance of the administrator to the inital supply
		balanceOf[admin] = initialSupply;
	}

	// Minting function that can only be called by the admin
	function mintToken(address target, uint256 mintedAmount) onlyAdmin{
		// Increase the balance of the target address with the amount of minted tokens
		balanceOf[target] = safeAdd(balanceOf[target], mintedAmount);
		// Increase the total supply of tokens
		totalSupply = safeAdd(totalSupply, mintedAmount);
		// Transfer the amount to this contract
		Transfer(0, this, mintedAmount);
		// Then transfer the amount to the target address
		Transfer(this, target, mintedAmount);
	}

	// Toekn transfer function
	function transfer(address _to, uint256 _value){
		// Check if balance of the sender is not negative
		require(balanceOf[msg.sender] > 0);
		// Check if balance of the sender is greater than or equal than the amount transfered
		require(balanceOf[msg.sender] >= _value);
		// Check for overflow
		require(safeAdd(balanceOf[_to], _value) >= balanceOf[_to]);

		// Substract the amount of tokens from the creator
		balanceOf[msg.sender] = safeSub(balanceOf[msg.sender], _value);
		// And add the amount of tokens to the target address
		balanceOf[_to] = safeAdd(balanceOf[_to], _value);
		// Execute the transfer
		Transfer(msg.sender, _to, _value);
	}
}




/*
* Crowdsale contract
*/
contract CrowdSale is SafeMath{

    // Enumerate the states
    enum State {
        // Crowdsale is in progress
        Fundraising,
        // Crowdsale has failed
        Failed,
        // Crowdsale was succesful
        Successful,
        // Crowdsale is closed
        Closed
    }

    // Initial state is Fundraising
    State public state = State.Fundraising;

    // Define contributor structure
    struct Contribution {
        uint amount;
        address contributor;
    }

    Contribution[] contributions;

    // Total amount raised
    uint public totalRaised;
    // Current balance
    uint public currentBalance;
    // Crowdsale deadline
    uint public deadline;
    // Time when the crowdfund was completed
    uint public completedAt;
    // Price per token in wei (18 digits after 0)
    uint256 public priceInWei;
    // Minimum funding target 
    uint public fundingMinimumTargetInWei; 
    // The token used as reward
    AssetToken public tokenReward;
    // Createor of the contract
    address public creator;
    // The beneficiary of the crowdsale
    address public beneficiary; 
    // Website URL
    string campaignUrl;

    // Event triggered when funding is received
    event LogFundingReceived(address addr, uint amount, uint currentTotal);
    // Event triggered when the beneficiary is paid
    event LogBeneficiaryPaid(address beneficiaryAddress);
    // Event triggered when the funding has been succesful
    event LogFundingSuccessful(uint totalRaised);
    // Event triggered when the crowdsale is initialized
    event LogFunderInitialized(
        address creator,
        address beneficiary,
        string url,
        uint256 deadline);

    // Check the crowdsale state
    modifier inState(State _state) {
        require(state == _state);
         _;
    }

    // Check if the amount sent is greater than the minimum price
    modifier isMinimum() {
        require(msg.value >= priceInWei);
        _;
    }

    /**
    *
    * Fix for the ERC20 short address attack
    *
    * http://vessenes.com/the-erc20-short-address-attack-explained/
    */
    modifier onlyPayloadSize(uint size) {
        if(msg.data.length < size + 4) {
        revert();
        }
        _;
    }

    // Check the ratio (no decimal values i.e. 1.2 TOKEN) is correct
    modifier inMultipleOfPrice() {
        require(msg.value%priceInWei == 0);
        _;
    }

    // modifier thath checks if the sender is the creator
    modifier isCreator() {
        require(msg.sender == creator);
        _;
    }

    // Check if the crowdsale has ended or is close to ending
    modifier atEndOfLifecycle() {
        require((state == State.Failed || state == State.Successful) && completedAt + 1 hours < now);
        _;
    }

    // Crowdsale initialization function
    function CrowdSale()
    {
        var _campaignUrl = "www.test.com";
        uint _timeInMinutesForFundraising = 10;
        address _ifSuccessfulSendTo = 0x5638D9125D46FeA242Fa95B41E995Aa9CDfE389F;
        uint _fundingMinimumTargetInEther = 1;
        uint256 _tokensPerEther = 500;

        // Set the creator as the sender of the transaction
        creator = msg.sender;
        // Set the beneficiary
        beneficiary = _ifSuccessfulSendTo;
        // Set the website URL
        campaignUrl = _campaignUrl;
        // Set the minimum crowdsale target
        fundingMinimumTargetInWei = _fundingMinimumTargetInEther * 1 ether; 
        // Set the crowdsale deadline in minutes
        deadline = now + (_timeInMinutesForFundraising * 1 minutes);
        // Set the current balance to 0 so we can mint coins
        currentBalance = 0;
        // Create a token object from the address of the reward token
        tokenReward =  new AssetToken(0,"Testing","TTK",0, this);
        // Set the price for 1 token (the conversion ratio with ether)
        priceInWei = _tokensPerEther;
        // Trigger the crowdsale initialization event
        LogFunderInitialized(
            creator,
            beneficiary,
            campaignUrl,
            deadline);
    }

    // Define the contribution function as a payable type
    function contribute()
    // It is an explicit public function
    public
    /* If the following conditions are respected:
    *  - Crowdsale is in progress
    *  - Contributed amount is greater than the minimum allowed
    *  - Contributed amount respectes the ratio (no decimal units)
    */
    inState(State.Fundraising)
    payable
    {
        // Add as a contributor
        contributions.push(
            Contribution({
                amount: msg.value,
                contributor: msg.sender
                }) 
            );

        // Increment crowdfund raised sum by the amount of ether
        totalRaised = safeAdd(totalRaised, msg.value);
        // Set current crowdfund balance to the total amount of ether raised
        currentBalance = totalRaised;

        uint tokens = safeDiv(safeMul(msg.value, priceInWei), 1 ether);

        tokenReward.mintToken(msg.sender, tokens);

        // Trigger the funding received event
        LogFundingReceived(msg.sender, msg.value * 1 ether, totalRaised);

        // Check if the crowdsale has reached its objective
        checkIfFundingCompleteOrExpired();
    }

    // Function that checks the status of the crowdfund
    function checkIfFundingCompleteOrExpired() {
        
        /*
        * Check for the following conditions:
        * - Crowdfund maximum target exists and is greater than 0
        * - Total amount raised is greater than or equal the the maxiumum target
        * In other words check if we have excedeed the maximum target or not
        */
        if ( now > deadline )  {

                // Check if the minimum has been achieved
                if(totalRaised >= fundingMinimumTargetInWei){
                    // Set the crowdsale state as succesful
                    state = State.Successful;
                    // Trigger the crowdsale successful funding event
                    LogFundingSuccessful(totalRaised);
                    // Call the payout function
                    payOut();
                    // Set the completion date to now
                    completedAt = now;
                }
                // If the crowdsale deadline is exceeded and none of the targets have been reached
                else {
                    // Set the crowdsale state as failed
                    state = State.Failed; 
                    // Set the completion date to now
                    completedAt = now;
                }
            }
    }
    // Define payout function
    function payOut()
    // It is an explicit public function
    public
    // If the crowdsale has been succesful
    inState(State.Successful)
    {   
        // Check if the transaction is not in progress
        require(beneficiary.send(this.balance));
        // Set the crowdsale state to closed
        state = State.Closed;
        // Set the current balance of the contract to 0
        currentBalance = 0;
        // Trigger the beneficiary has been paid event
        LogBeneficiaryPaid(beneficiary);
    }

    // Function to refund the contributors
    function getRefund()
    public
    // Only refund if the crowdsale has failed
    inState(State.Failed) 
    returns (bool)
    {   
        // Search if the contributor actually exists
        for(uint i=0; i<=contributions.length; i++)
        {
            if(contributions[i].contributor == msg.sender){
                uint amountToRefund = contributions[i].amount;
                contributions[i].amount = 0;
                // Send refund and decrement crowdsale amount
                if(!contributions[i].contributor.send(amountToRefund)) {
                    contributions[i].amount = amountToRefund;
                    return false;
                }
                else{
                    totalRaised = safeSub(totalRaised, amountToRefund);
                    currentBalance = totalRaised;
                }
                return true;
            }
        }
        return false;
    }

    // Function to destroy the contract
    function removeContract()
    public
    isCreator()
    atEndOfLifecycle()
    {
        selfdestruct(msg.sender);  
    }
    

    /* The function without name is the default function that is called whenever anyone sends funds to a contract */
    function () payable {
        contribute();
    }

}

