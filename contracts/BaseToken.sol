// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import './interfaces/IToken.sol';
import './extensions/ERC20TokenRecover.sol';
import './ERC1363/ERC1363.sol';
// import './ERC2612/ERC2612.sol';

abstract contract BaseToken is
    Initializable,
    ContextUpgradeable,
    OwnableUpgradeable,
    IToken,
    ERC20Upgradeable,
    ERC20TokenRecover,
    ERC1363
    // ERC2612
{
    address public deployer;

    uint8 _decimals = 18;

    constructor() {
        deployer = _msgSender();
    }

    function __BaseToken_init(
        string memory name,
        string memory symbol,
        uint8 decim,
        uint256 supply
    ) public virtual {
        // msg.sender = address(0) when using Clone.
        require(deployer == address(0) || _msgSender() == deployer, 'UNAUTHORIZED');
        require(decim > 3 && decim < 19, 'DECIM');

        deployer = _msgSender();

        super.__ERC20_init(name, symbol);
        super.__Ownable_init_unchained();
        // super.__ERC20Capped_init_unchained(supply);
        // super.__ERC20Burnable_init_unchained(true);
        // super.__ERC2612_init_unchained(name);
        _decimals = decim;

        _mint(_msgSender(), supply);
    }

    function decimals() public view virtual override(ERC20Upgradeable, IERC20MetadataUpgradeable) returns (uint8) {
        return _decimals;
    }

    //== BEP20 owner function ==
    function getOwner() public view override returns (address) {
        return owner();
    }

    //== Mandatory overrides ==/
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1363) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _mint(address account, uint256 amount) internal virtual override(ERC20Upgradeable) {
        super._mint(account, amount);
    }
}
