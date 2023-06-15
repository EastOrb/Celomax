pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.3.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/celo-org/celo-monorepo/packages/protocol/contracts/stability/interfaces/IGoldToken.sol";

interface IUniswapRouter {
    function swapExactTokensForTokens(
        uint amountIn, 
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    ) external returns (uint[] memory amounts);
}

contract CeloMax {
    IERC20 public celoUSD;
    IGoldToken public celo;
    IUniswapRouter public uniswapRouter;
    mapping(address => uint256) public stakedAmounts;
    mapping(address => uint256) public stakedTimestamps;
    mapping(address => bool) public validators;

    event Deposit(address indexed user, uint256 amount, uint256 timestamp);
    event Withdrawal(address indexed user, uint256 amount, uint256 timestamp);
    event ValidatorSignUp(address indexed validator);

    constructor(address _celoUSDAddress, address _celoAddress, address _uniswapRouter) {
        celoUSD = IERC20(_celoUSDAddress);
        celo = IGoldToken(_celoAddress);
        uniswapRouter = IUniswapRouter(_uniswapRouter);
    }

    function depositAndStake(address token, uint256 amount, bool convertToCelo) external {
        require(amount > 0, "Amount must be greater than zero");

        // Transfer user's tokens to the contract
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        if (convertToCelo) {
            // Convert token to celo using Uniswap
            address[] memory path = new address[](2);
            path[0] = token;
            path[1] = address(celo);

            IERC20(token).approve(address(uniswapRouter), amount);

            uint[] memory amounts = uniswapRouter.swapExactTokensForTokens(
                amount, 
                0, 
                path, 
                address(this), 
                block.timestamp + 600
            );

            amount = amounts[amounts.length - 1];
        } else {
            // Convert token to celo USD using Uniswap
            address[] memory path = new address[](3);
            path[0] = token;
            path[1] = address(celoUSD);
            path[2] = address(celo);

            IERC20(token).approve(address(uniswapRouter), amount);

            uint[] memory amounts = uniswapRouter.swapExactTokensForTokens(
                amount, 
                0, 
                path, 
                address(this), 
                block.timestamp + 600
            );

            amount = amounts[amounts.length - 1];
        }

        // Stake the converted token
        uint256 stakedAmount = amount;
        stakedAmounts[msg.sender] += stakedAmount;
        stakedTimestamps[msg.sender] = block.timestamp;

        emit Deposit(msg.sender, amount, block.timestamp);
    }

    function withdraw(bool inCeloUSD) external {
        uint256 stakedAmount = stakedAmounts[msg.sender];
        require(stakedAmount > 0, "No staked amount");
                // Calculate the incentives
        uint256 incentives = calculateIncentives(msg.sender);

        // Reduce the staked amount
        stakedAmounts[msg.sender] = 0;

        // Transfer staked celo or celo USD back to the user
        if (inCeloUSD) {
            celo.approve(address(celoUSD), stakedAmount);
            celo.deposit(stakedAmount);
            celoUSD.transfer(msg.sender, stakedAmount);
        } else {
            celo.transfer(msg.sender, stakedAmount);
        }

        // Transfer incentives to the user
        celoUSD.transfer(msg.sender, incentives);

        emit Withdrawal(msg.sender, stakedAmount, block.timestamp);
    }

    function calculateIncentives(address user) internal view returns (uint256) {
        uint256 stakedAmount = stakedAmounts[user];
        uint256 stakedTimestamp = stakedTimestamps[user];
        uint256 currentTimestamp = block.timestamp;

        // Calculate incentives based on the staking duration
        uint256 stakingDuration = currentTimestamp - stakedTimestamp;
        uint256 incentives = (stakedAmount * stakingDuration) / 100;

        return incentives;
    }

    function signUpAsValidator() external {
        validators[msg.sender] = true;
        emit ValidatorSignUp(msg.sender);
    }
}
