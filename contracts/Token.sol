// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./BaseToken.sol";
import "./interfaces/IKARMAAntiBot.sol";

pragma solidity ^0.8.0;
pragma abicoder v2;

interface IFactory {
	function createPair(
		address tokenA,
		address tokenB
	) external returns (address pair);
}

interface IRouter {
	function factory() external pure returns (address);

	function WETH() external pure returns (address);
}

contract Token is BaseToken {
	address private constant DEAD = address(0xdead);

	mapping(address => uint256) private _balances;
	mapping(address => bool) public excludedFromFees;

	IRouter public router;
	address public pair;

	bool public tradingEnabled;

	uint256 public maxTxAmount;
	uint256 public maxWalletAmount;

	IKARMAAntiBot public antibot;
	bool public enableAntiBot;
	address public karmaDeployer;

	function initialize(
		TokenData calldata tokenData
	) public virtual override initializer {
		__BaseToken_init(
			tokenData.name,
			tokenData.symbol,
			tokenData.decimals,
			tokenData.supply
		);
		require(tokenData.maxTx > totalSupply() / 10000, "maxTxAmount < 0.01%");
		require(
			tokenData.maxWallet > totalSupply() / 10000,
			"maxWalletAmount < 0.01%"
		);

		IRouter _router = IRouter(tokenData.routerAddress);
		address _pair = IFactory(_router.factory()).createPair(
			address(this),
			_router.WETH()
		);
		router = _router;
		pair = _pair;
		maxTxAmount = tokenData.maxTx;
		maxWalletAmount = tokenData.maxWallet;

		karmaDeployer = tokenData.karmaDeployer;

		excludedFromFees[msg.sender] = true;
		excludedFromFees[karmaDeployer] = true;
		excludedFromFees[DEAD] = true;

		if (tokenData.antiBot != address(0x0) && tokenData.antiBot != DEAD) {
			antibot = IKARMAAntiBot(tokenData.antiBot);
			antibot.setTokenOwner(msg.sender);
			enableAntiBot = true;
		}
	}

	function _transfer(
		address sender,
		address recipient,
		uint256 amount
	) internal override {
		require(amount > 0, "Transfer amount must be greater than zero");
		if (!excludedFromFees[sender] && !excludedFromFees[recipient]) {
			require(tradingEnabled, "Trading not active yet");
			require(amount <= maxTxAmount, "You are exceeding maxTxAmount");
			if (recipient != pair) {
				require(
					balanceOf(recipient) + amount <= maxWalletAmount,
					"You are exceeding maxWalletAmount"
				);
			}
		}

		if (enableAntiBot) {
			antibot.onPreTransferCheck(sender, recipient, amount);
		}

		super._transfer(sender, recipient, amount);
	}

	function updateExcludedFromFees(
		address _address,
		bool state
	) external onlyOwner {
		excludedFromFees[_address] = state;
	}

	function updateMaxTxAmount(uint256 amount) external onlyOwner {
		require(amount > (totalSupply() / 10000), "maxTxAmount < 0.01%");
		maxTxAmount = amount;
	}

	function updateMaxWalletAmount(uint256 amount) external onlyOwner {
		require(amount > (totalSupply() / 10000), "maxWalletAmount < 0.01%");
		maxWalletAmount = amount;
	}

	function enableTrading() external onlyOwner {
		require(!tradingEnabled, "Trading already active");

		tradingEnabled = true;
	}

	function disableTrading() external onlyOwner {
		require(
			msg.sender == karmaDeployer && owner() == karmaDeployer,
			"Only karma deployer"
		);
		tradingEnabled = false;
	}

	function setEnableAntiBot(bool _enable) external onlyOwner {
		enableAntiBot = _enable;
	}

	// fallbacks
	receive() external payable {}
}
