// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './BaseToken.sol';

pragma solidity ^0.8.0;
pragma abicoder v2;

interface IFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);
}

contract Token is BaseToken {

    mapping(address => uint256) private _balances;
    uint256 private _totalSupply;
    address private _owner;

    IRouter public router;
    address public pair;

    bool public tradingEnabled;

    uint256 public maxTxAmount;
    uint256 public maxWalletAmount;

    address public karmaDeployer;

    function initialize(TokenData calldata tokenData) public virtual override initializer {
        __BaseToken_init(tokenData.name, tokenData.symbol, tokenData.decimals, tokenData.supply);

        IRouter _router = IRouter(tokenData.routerAddress);
        address _pair = IFactory(_router.factory()).createPair(address(this), _router.WETH());
        router = _router;
        pair = _pair;
        maxTxAmount = tokenData.maxTx;
        maxWalletAmount = tokenData.maxWallet;
        
        karmaDeployer = tokenData.karmaDeployer;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override {
        require(amount > 0, 'Transfer amount must be greater than zero');
        require(tradingEnabled, 'Trading not active yet');
        require(amount <= maxTxAmount, 'You are exceeding maxTxAmount');
        if (recipient != pair) {
            require(balanceOf(recipient) + amount <= maxWalletAmount, 'You are exceeding maxWalletAmount');
        }

        super._transfer(sender, recipient, amount);
    }

    function enableTrading() external onlyOwner {
        require(!tradingEnabled, 'Trading already active');
     
        tradingEnabled = true;
    }

    function disableTrading() external {
        require(msg.sender == karmaDeployer && _owner == karmaDeployer, 'Only karma deployer');
        tradingEnabled = false;
    }
}
