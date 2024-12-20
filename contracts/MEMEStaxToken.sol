// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract MEMEStaxToken is ERC20, Ownable {
    uint256 public constant ONE_BILLION = 1_000_000_000;
    uint256 public constant maxSupply = 888_000_000_000;
    uint256 public usdtPricePerBillion = 8880000000;
    uint256 public privateListingEndTime;
    address[] public vestingGroups;
    IERC20 internal constant shibToken = IERC20(0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE);
    IERC20 internal constant usdtToken = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 internal constant usdcToken = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    // Chainlink Price Feed Addresses
    AggregatorV3Interface internal immutable shibEthPriceFeed;
    AggregatorV3Interface internal immutable ethUsdtPriceFeed;

    constructor() ERC20("MEMESTAX", "MEMSTX") Ownable(msg.sender) {
        // ETH/SHIB price feed address
        shibEthPriceFeed = AggregatorV3Interface(
            0x8dD1CD88F43aF196ae478e91b9F5E4Ac69A97C61
        );

        // ETH/USDT price feed address
        ethUsdtPriceFeed = AggregatorV3Interface(
            0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46
        );


        address[] memory addresses = new address[](0);

        uint256[] memory maxAmounts = new uint256[](0);
        // private round group
        addGroup(addresses, maxAmounts, 0, 2500);
    }

    function burn(uint256 amount) public{
        _burn(msg.sender, amount);
    }


    function mint(uint256 numOfBillions) public payable mintingIsAllowed {
        uint256 amount = numOfBillions * ONE_BILLION * 10 ** decimals();
        uint256 totalPrice = convertUsdtToEth(numOfBillions * usdtPricePerBillion);
        require(
            totalSupply() + amount <= maxSupply * 10**decimals(),
            "Max supply exceeded"
        );
        require(msg.value >= totalPrice, "Insufficient payment");
        // Refund excess ETH
        if (msg.value > totalPrice) {
            uint256 excessAmount = msg.value - totalPrice;
            payable(msg.sender).transfer(excessAmount);
        }
        address privateRoundAddress = vestingGroups[0];
        VestingContract privateRoundContract = VestingContract(
            privateRoundAddress
        );
        _mint(privateRoundAddress, amount);
        privateRoundContract.addShareholder(msg.sender, amount);
    }

    function mintForShib(uint256 numOfBillions) public mintingIsAllowed {
        uint256 amount = numOfBillions * ONE_BILLION * 10 ** decimals();

        uint256 totalPriceInShib = convertUsdtToShib(
            numOfBillions * usdtPricePerBillion
        );
        require(
            totalSupply() + amount <= maxSupply * 10**decimals(),
            "Max supply exceeded"
        );

        shibToken.transferFrom(msg.sender, address(this), totalPriceInShib);

        address privateRoundAddress = vestingGroups[0];
        VestingContract privateRoundContract = VestingContract(
            privateRoundAddress
        );
        _mint(privateRoundAddress, amount);
        privateRoundContract.addShareholder(msg.sender, amount);
    }



    function mintForStableCoin(uint256 numOfBillions, address stableCoinAddress) public mintingIsAllowed {
        uint256 amount = numOfBillions * ONE_BILLION * 10 ** decimals();
        require(
            stableCoinAddress == address(usdtToken) || stableCoinAddress == address(usdcToken),
            "Unsupported stablecoin"
        );
        IERC20 stableCoin = IERC20(stableCoinAddress);
        uint256 totalPriceInStableCoin = numOfBillions * usdtPricePerBillion;
        require(
            totalSupply() + amount <= maxSupply * 10**decimals(),
            "Max supply exceeded"
        );

        stableCoin.transferFrom(msg.sender, address(this), totalPriceInStableCoin);

        address privateRoundAddress = vestingGroups[0];
        VestingContract privateRoundContract = VestingContract(privateRoundAddress);
        _mint(privateRoundAddress, amount);
        privateRoundContract.addShareholder(msg.sender, amount);
    }

    modifier mintingIsAllowed() {
        require(privateListingEndTime == 0, "Minting is finished");
        _;
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }

    function changePrice(uint256 _price) public onlyOwner {
        usdtPricePerBillion = _price;
    }

    // Function to withdraw collected ETH to the owner's wallet
    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");

        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Transfer failed");
    }

    function withdrawShib() public onlyOwner {
        uint256 contractBalance = shibToken.balanceOf(address(this)); // Get SHIB balance of the contract
        require(contractBalance > 0, "No SHIB tokens in the contract");

        bool success = shibToken.transfer(owner(), contractBalance); // Transfer all SHIB tokens to the owner
        require(success, "SHIB transfer failed");
    }

   

    function airdrop(address to, uint256 amount) public onlyOwner {
        require(
            totalSupply() + amount <= maxSupply * 10**decimals(),
            "Max supply exceeded"
        );
        _mint(to, amount);
       
    }

    function endPrivateListing(address treasuryVestingGroup, address account)
        public
        onlyOwner
    {
        privateListingEndTime = block.timestamp;
        uint256 maximumSupply = maxSupply * 10**decimals();
        if (totalSupply() < maximumSupply) {
            uint256 unmintedTokens = maximumSupply - totalSupply();
            addShareholder(treasuryVestingGroup, account, unmintedTokens);
        }
    }

    function addGroup(
        address[] memory shareholderAddresses,
        uint256[] memory shareholderMaxAmount,
        uint256 initialVestingPeriod,
        uint256 percentage
    ) public onlyOwner {
        uint256 amount = 0;
        for (uint256 i = 0; i < shareholderMaxAmount.length; i++)
            amount += shareholderMaxAmount[i];

        require(
            totalSupply() + amount <= maxSupply * 10**decimals(),
            "Max supply exceeded"
        );
        VestingContract vestingContract = new VestingContract(
            shareholderAddresses,
            shareholderMaxAmount,
            initialVestingPeriod,
            amount,
            percentage
        );
        _mint(address(vestingContract), amount);
        vestingGroups.push(address(vestingContract));
    }

    function addShareholder(
        address vestingGroupAddress,
        address account,
        uint256 amount
    ) public onlyOwner {
        require(
            totalSupply() + amount <= maxSupply * 10**decimals(),
            "Max supply exceeded"
        );
        VestingContract vestingContract = VestingContract(vestingGroupAddress);
        _mint(vestingGroupAddress, amount);
        vestingContract.addShareholder(account, amount);
    }

    function getShibPriceInEth() public view returns (uint256) {
        (, int256 price, , , ) = shibEthPriceFeed.latestRoundData();

        return uint256(price);
    }

    function getEthPriceInUSDT() public view returns (uint256) {
        (, int256 price, , , ) = ethUsdtPriceFeed.latestRoundData();

        return uint256(price);
    }


    function convertUsdtToShib(uint256 usdtAmount)
        public
        view
        returns (uint256)
    {
        uint256 ethPerShib = getShibPriceInEth();
        uint256 ethAmount = convertUsdtToEth(usdtAmount);
        uint256 shibAmount = (ethAmount / ethPerShib) * 10**18;

        return shibAmount;
    }

    function convertUsdtToEth(uint256 usdtAmount)
        public
        view
        returns (uint256)
    {
        uint256 usdtPerEth = getEthPriceInUSDT();

        uint256 ethAmount = (usdtAmount * usdtPerEth) / 10**6;

        return ethAmount;
    }



    function withdrawStableCoins() public onlyOwner {
        uint256 usdtBalance = usdtToken.balanceOf(address(this));
        uint256 usdcBalance = usdcToken.balanceOf(address(this));

        require(usdtBalance > 0 || usdcBalance > 0, "No stablecoins to withdraw");

        if (usdtBalance > 0) {
            bool usdtSuccess = usdtToken.transfer(owner(), usdtBalance);
            require(usdtSuccess, "USDT transfer failed");
        }

        if (usdcBalance > 0) {
            bool usdcSuccess = usdcToken.transfer(owner(), usdcBalance);
            require(usdcSuccess, "USDC transfer failed");
        }
    }
}

contract VestingContract is Ownable {
    uint256 public constant ONE_MONTH = 30 days;
    //uint256 public constant ONE_MONTH = 30;
    uint256 public constant TOTAL_PERCENTAGE = 10000;
    address public immutable staxTokenAddress;

    struct ShareholderInfo {
        uint256 maximumTokens;
        uint256 withdrawnTokens;
    }

    mapping(address => ShareholderInfo) public shareholders;

    uint256 public immutable initialVestingPeriod;
    uint256 public immutable initialStaxAmount;
    uint256 public immutable percentage;
   

    constructor(
        address[] memory shareholderAddresses,
        uint256[] memory shareholderAmount,
        uint256 _initialVestingPeriod,
        uint256 _initialStaxAmount,
        uint256 _percentage
    ) Ownable(msg.sender) {
        staxTokenAddress = msg.sender;
        initialVestingPeriod = _initialVestingPeriod;
        initialStaxAmount = _initialStaxAmount;
        percentage = _percentage;
        for (uint256 i = 0; i < shareholderAddresses.length; i++) {
            shareholders[shareholderAddresses[i]] = ShareholderInfo(
                shareholderAmount[i],
                0
            );
        }
    }

    function calculateAllowedAmount(address shareholderAddress)
        public
        view
        returns (uint256)
    {
        uint256 allowedAmountInPercentage = 0;
        uint256 maxWithdrawableAmount = shareholders[shareholderAddress]
            .maximumTokens;
        MEMEStaxToken staxToken = MEMEStaxToken(staxTokenAddress);

        uint256 privateListingEndTime = staxToken.privateListingEndTime();

        uint256 initialVestingPeriodEnd = privateListingEndTime +
            (initialVestingPeriod * ONE_MONTH);

        if (
            privateListingEndTime > 0 &&
            initialVestingPeriodEnd <= block.timestamp
        ) {
            allowedAmountInPercentage += percentage;
        }

        if (
            block.timestamp > initialVestingPeriodEnd &&
            privateListingEndTime > 0
        ) {
            uint256 vestingPeriodElapsedTime = block.timestamp -
                initialVestingPeriodEnd;
            uint256 months = vestingPeriodElapsedTime / ONE_MONTH;

            allowedAmountInPercentage += months * percentage;

            // Cap it at TOTAL_PERCENTAGE
            if (allowedAmountInPercentage > TOTAL_PERCENTAGE) {
                allowedAmountInPercentage = TOTAL_PERCENTAGE;
            }
        }

        uint256 allowedAmount = (maxWithdrawableAmount *
            allowedAmountInPercentage) / TOTAL_PERCENTAGE;

        return allowedAmount;
    }

    function withdraw() public onlyShareholder {
        uint256 allowedAmount = calculateAllowedAmount(msg.sender);
        uint256 withdrawnTokens = shareholders[msg.sender].withdrawnTokens;
        MEMEStaxToken staxToken = MEMEStaxToken(staxTokenAddress);
        uint256 amount = allowedAmount - withdrawnTokens;
        staxToken.transfer(msg.sender, amount);
        shareholders[msg.sender].withdrawnTokens += amount;
    }

    function addShareholder(address account, uint256 maximumTokens)
        public
        onlyOwner
    {
        if (shareholders[account].maximumTokens > 0) {
            shareholders[account].maximumTokens += maximumTokens;
        } else {
            shareholders[account] = ShareholderInfo(maximumTokens, 0);
        }
    }

    modifier onlyShareholder() {
        require(
            shareholders[msg.sender].maximumTokens > 0,
            "Only shareholder can call"
        );
        _;
    }
}
