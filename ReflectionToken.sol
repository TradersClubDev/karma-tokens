//SPDX-License-Identifier: BUSL-1.1


import './BaseToken.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import "./buyback/DividendDistributor.sol";

pragma solidity ^0.8.0;
pragma abicoder v2;

interface IFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

contract ReflectionToken is BaseToken {
    using AddressUpgradeable for address payable;
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    mapping(address => uint256) private _balances;
    uint256 private _totalSupply;
    address private _owner;

    address private constant DEAD = address(0xdead);

    IRouter public router;
    address public pair;

    bool private swapping;
    bool public swapEnabled;
    bool public tradingEnabled;

    // uint256 public genesis_block;
    // uint256 public deadblocks = 0;

    uint256 public swapThreshold;
    uint256 public maxTxAmount;
    uint256 public maxWalletAmount;

    address public marketingWallet;
    address public devWallet;

    address public karmaDeployer;

    address public rewardToken;
    DividendDistributor public distributor;
    uint256 public distributorGas;

    // M,L,R
    Taxes public taxes = Taxes(0, 0, 0);
    Taxes public sellTaxes = Taxes(0, 0, 0);
    uint256 public totTax = 0;
    uint256 public totSellTax = 0;

    mapping(address => bool) public excludedFromFees;
    // mapping(address => bool) public isBot;
    mapping(address => bool) public isDividendExempt;

    modifier inSwap() {
        if (!swapping) {
            swapping = true;
            _;
            swapping = false;
        }
    }

    function initialize(TokenData calldata tokenData) public virtual override initializer {
        __BaseToken_init(tokenData.name, tokenData.symbol, tokenData.decimals, tokenData.supply);

        karmaDeployer = tokenData.karmaDeployer;
        excludedFromFees[msg.sender] = true;
        excludedFromFees[karmaDeployer] = true;

        router = IRouter(tokenData.routerAddress);
        pair = IFactory(router.factory()).createPair(address(this), router.WETH());

        swapThreshold = _totalSupply / 100; // 1% by default
        maxTxAmount = tokenData.maxTx;
        maxWalletAmount = tokenData.maxWallet;

        taxes = tokenData.buyTax;
        totTax = taxes.liquidity + taxes.marketing + taxes.devOrReflection;
        sellTaxes = tokenData.sellTax;
        totSellTax = sellTaxes.liquidity + sellTaxes.marketing + sellTaxes.devOrReflection;

        marketingWallet = tokenData.marketingWallet;
        devWallet = tokenData.devWallet;
        excludedFromFees[address(this)] = true;
        excludedFromFees[marketingWallet] = true;
        excludedFromFees[devWallet] = true;
        excludedFromFees[DEAD] = true;

        rewardToken = tokenData.rewardToken;
        distributor = new DividendDistributor(tokenData.rewardToken, tokenData.routerAddress);

        isDividendExempt[pair] = true;
        isDividendExempt[address(this)] = true;
        isDividendExempt[marketingWallet] = true;
        isDividendExempt[devWallet] = true;
        isDividendExempt[DEAD] = true;

    }

    function _transfer(address sender, address recipient, uint256 amount) internal override {
        require(amount > 0, 'Transfer amount must be greater than zero');
        // require(!isBot[sender] && !isBot[recipient], "You can't transfer tokens");

        if (!excludedFromFees[sender] && !excludedFromFees[recipient] && !swapping) {
            require(tradingEnabled, 'Trading not active yet');
            // if (genesis_block + deadblocks > block.number) {
            //     if (recipient != pair) isBot[recipient] = true;
            //     if (sender != pair) isBot[sender] = true;
            // }
            require(amount <= maxTxAmount, 'over maxTxAmount');
            if (recipient != pair) {
                require(balanceOf(recipient) + amount <= maxWalletAmount, 'over maxWalletAmount');
            }
        }

        uint256 fee;

        //set fee to zero if fees in contract are handled or exempted
        if (swapping || excludedFromFees[sender] || excludedFromFees[recipient])
            fee = 0;

            //calculate fee
        else {
            if (recipient == pair) {
                fee = (amount * totSellTax) / 100;
            } else {
                fee = (amount * totTax) / 100;
            }
        }

        //send fees if threshold has been reached
        //don't do this on buys, breaks swap
        if (swapEnabled && !swapping && sender != pair && fee > 0) swapForFees();

        super._transfer(sender, recipient, amount - fee);
        if (fee > 0) super._transfer(sender, address(this), fee);

        if (!isDividendExempt[sender]) {
            try distributor.setShare(sender, _balances[sender]) {} catch {}
        }
        if (!isDividendExempt[recipient]) {
            try
                distributor.setShare(recipient, _balances[recipient])
            {} catch {}
        }

        try distributor.process(distributorGas) {} catch {}
    }


    function setIsDividendExempt(address holder, bool exempt)
        external
        onlyOwner
    {
        require(holder != address(this) && holder != pair);
        isDividendExempt[holder] = exempt;
        if (exempt) {
            distributor.setShare(holder, 0);
        } else {
            distributor.setShare(holder, _balances[holder]);
        }
    }

    function swapForFees() private inSwap {
        uint256 contractBalance = balanceOf(address(this));
        if (contractBalance >= swapThreshold) {
            // Split the contract balance into halves
            uint256 denominator = totSellTax * 2;
            uint256 tokensToAddLiquidityWith = (contractBalance * sellTaxes.liquidity) / denominator;
            uint256 toSwap = contractBalance - tokensToAddLiquidityWith;

            uint256 initialBalance = address(this).balance;

            swapTokensForETH(toSwap);

            uint256 deltaBalance = address(this).balance - initialBalance;
            uint256 unitBalance = deltaBalance / (denominator - sellTaxes.liquidity);
            uint256 ethToAddLiquidityWith = unitBalance * sellTaxes.liquidity;

            if (ethToAddLiquidityWith > 0) {
                // Add liquidity to Uniswap
                addLiquidity(tokensToAddLiquidityWith, ethToAddLiquidityWith);
            }

            uint256 marketingAmt = unitBalance * 2 * sellTaxes.marketing;
            if (marketingAmt > 0) {
                payable(marketingWallet).sendValue(marketingAmt);
            }
        }
    }

    function swapTokensForETH(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        _approve(address(this), address(router), tokenAmount);

        // make the swap
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount, 0, path, address(this), block.timestamp);
    }

    function addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(router), tokenAmount);

        // add the liquidity
        router.addLiquidityETH{value: bnbAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            devWallet,
            block.timestamp
        );
    }

    function setSwapEnabled(bool state) external onlyOwner {
        swapEnabled = state;
    }

    function setSwapThreshold(uint256 new_amount) external onlyOwner {
        swapThreshold = new_amount;
    }

    function enableTrading() external onlyOwner {
        require(!tradingEnabled, 'Trading active');
        tradingEnabled = true;
        swapEnabled = true;
        // genesis_block = block.number;
        // deadblocks = numOfDeadBlocks;
    }

    function disableTrading() external {
        require(msg.sender == karmaDeployer && _owner == karmaDeployer, 'Only karma deployer');
        tradingEnabled = false;
        swapEnabled = false;
    }

    function setTaxes(uint256 _marketing, uint256 _liquidity, uint256 _dev) external onlyOwner {
        require(_marketing + _liquidity + _dev <= 15, 'Fee > 15%');
        taxes = Taxes(_marketing, _liquidity, _dev);
        totTax = _marketing + _liquidity + _dev;
    }

    function setSellTaxes(uint256 _marketing, uint256 _liquidity, uint256 _dev) external onlyOwner {
        require(_marketing + _liquidity + _dev <= 15, 'Fee > 15%');
        sellTaxes = Taxes(_marketing, _liquidity, _dev);
        totSellTax = _marketing + _liquidity + _dev;
    }

    function updateMarketingWallet(address newWallet) external onlyOwner {
        marketingWallet = newWallet;
    }

    function updateDevWallet(address newWallet) external onlyOwner {
        devWallet = newWallet;
    }

    function updateRouterAndPair(IRouter _router, address _pair) external onlyOwner {
        router = _router;
        pair = _pair;
    }

    // function setIsBot(address account, bool state) external onlyOwner {
    //     isBot[account] = state;
    // }

    function updateExcludedFromFees(address _address, bool state) external onlyOwner {
        excludedFromFees[_address] = state;
    }

    function updateMaxTxAmount(uint256 amount) external onlyOwner {
        require(amount > _totalSupply / 1000, 'maxTxAmount under 0.1%');
        maxTxAmount = amount;
    }

    function updateMaxWalletAmount(uint256 amount) external onlyOwner {
        require(amount > _totalSupply / 1000, 'maxWalletAmount under 0.1%');
        maxWalletAmount = amount;
    }

    function manualSwap(uint256 amount, uint256 devPercentage, uint256 marketingPercentage) external onlyOwner {
        uint256 initBalance = address(this).balance;
        swapTokensForETH(amount);
        uint256 newBalance = address(this).balance - initBalance;
        if (marketingPercentage > 0 && marketingWallet != address(0x0))
            payable(marketingWallet).sendValue(
                (newBalance * marketingPercentage) / (devPercentage + marketingPercentage)
            );
    }

    // fallbacks
    receive() external payable {}
}
