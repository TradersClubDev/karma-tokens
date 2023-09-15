import { expect } from "chai";
import { ethers } from "hardhat";
import { StandardToken } from "../typechain-types";
import {
  IUniswapV2Router02,
  UniswapV2Deployer,
  IUniswapV2Pair__factory,
  IUniswapV2Factory,
  WETH9,
} from "uniswap-v2-deploy-plugin";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { utils } from "ethers";

function eth(n: number) {
  return utils.parseEther(n.toString());
}

describe("StandardToken", function () {
  // We define a fixture to reuse the same setup in every test.
  let owner: SignerWithAddress;
  let user: SignerWithAddress;
  let router: IUniswapV2Router02;
  let factory: IUniswapV2Factory;
  let tokenContract: StandardToken;
  this.beforeAll(async () => {
    const tokenFactory = await ethers.getContractFactory("StandardToken");
    tokenContract = (await tokenFactory.deploy()) as StandardToken;
    await tokenContract.deployed();
  });

  describe("Deployment", function () {
    it("Initialized", async function () {
      [owner, user] = await ethers.getSigners();
      ({ router, factory } = await UniswapV2Deployer.deploy(owner));

      const tokenData = {
        name: "A A A",
        symbol: "aaa",
        decimals: 18,
        supply: 1_000_000n * 10n ** 18n,
        maxTx: (1_000_000n * 10n ** 18n) / 1000n,
        maxWallet: ((1_000_000n * 10n ** 18n) / 1000n) * 2n,
        routerAddress: router.address,
        karmaDeployer: owner?.address ?? "",
        buyTax: { marketing: 50n, reflection: 0n },
        sellTax: { marketing: 150n, reflection: 0n },
        marketingWallet: "0xe422C2757AD02bb90f44cA32976eb2B07086cad0",
        rewardToken: "0xdac17f958d2ee523a2206206994597c13d831ec7",
        antiBot: "0x0000000000000000000000000000000000000000",
        limitedOwner: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
        karmaCampaignFactory: "0x0000000000000000000000000000000000000000",
      };

      expect(await tokenContract.initialize(tokenData)).to.not.revertedWithPanic();
      expect(await tokenContract.symbol()).to.equal(tokenData.symbol);
      expect(await tokenContract.name()).to.equal(tokenData.name);
      expect(await tokenContract.decimals()).to.equal(tokenData.decimals);
      expect(await tokenContract.totalSupply()).to.equal(tokenData.supply);
    });

    it("works", async () => {
      const total = await tokenContract.totalSupply();

      await tokenContract.approve(router.address, total);
      const weth = await router.WETH();
      const wethToken = await ethers.getContractAt(WETH9.abi, weth);

      await wethToken.approve(router.address, eth(100));
      await router.addLiquidityETH(
        tokenContract.address,
        total,
        1,
        eth(10),
        owner.address,
        Math.round(Date.now() / 1000) + 3600,
        { value: eth(100) },
      );

      const pair = IUniswapV2Pair__factory.connect(await factory.getPair(tokenContract.address, weth), owner);

      expect((await pair.balanceOf(owner.address)).toString()).equal("9999999999999999999000");

      await router.swapExactETHForTokens(
        0,
        [weth, tokenContract.address],
        owner.address,
        Math.round(Date.now() / 1000) + 3600,
        { value: eth(1) },
      );

      expect((await tokenContract.balanceOf(owner.address)).toString()).to.equal("9871580343970612988504");
    });

    it("trade disabled", async () => {
      const weth = await router.WETH();

      const routerUser = await router.connect(user);
      await expect(
        routerUser.swapExactETHForTokens(
          0,
          [weth, tokenContract.address],
          user.address,
          Math.round(Date.now() / 1000) + 3600,
          { value: eth(0.001) },
        ),
      ).to.be.revertedWith("UniswapV2: TRANSFER_FAILED");

      await tokenContract.enableTrading();

      await expect(
        routerUser.swapExactETHForTokens(
          0,
          [weth, tokenContract.address],
          user.address,
          Math.round(Date.now() / 1000) + 3600,
          { value: eth(0.001) },
        ),
      ).not.to.be.revertedWith("UniswapV2: TRANSFER_FAILED");
    });

    it("max TX", async () => {
      const weth = await router.WETH();
      const routerUser = await router.connect(user);

      await expect(
        routerUser.swapExactETHForTokens(
          0,
          [weth, tokenContract.address],
          user.address,
          Math.round(Date.now() / 1000) + 3600,
          { value: eth(1) },
        ),
      ).to.be.revertedWith("UniswapV2: TRANSFER_FAILED");
    });

    it("max Wallet", async () => {
      const weth = await router.WETH();
      const routerUser = await router.connect(user);

      await expect(
        routerUser.swapExactETHForTokens(
          0,
          [weth, tokenContract.address],
          user.address,
          Math.round(Date.now() / 1000) + 3600,
          { value: eth(0.1) },
        ),
      ).to.not.be.revertedWith("UniswapV2: TRANSFER_FAILED");

      await expect(
        routerUser.swapExactETHForTokens(
          0,
          [weth, tokenContract.address],
          user.address,
          Math.round(Date.now() / 1000) + 3600,
          { value: eth(0.1) },
        ),
      ).to.not.be.revertedWith("UniswapV2: TRANSFER_FAILED");

      await expect(
        routerUser.swapExactETHForTokens(
          0,
          [weth, tokenContract.address],
          user.address,
          Math.round(Date.now() / 1000) + 3600,
          { value: eth(0.1) },
        ),
      ).to.be.revertedWith("UniswapV2: TRANSFER_FAILED");
    });

    it("set maxTx", async () => {
      await expect(tokenContract.updateMaxTxAmount(1)).to.be.revertedWith("maxTxAmount < 0.01%");
      expect(await tokenContract.maxTxAmount()).to.equal((1_000_000n * 10n ** 18n) / 1000n);

      await expect(tokenContract.updateMaxTxAmount((1_000_000n * 10n ** 18n) / 2000n)).to.not.be.revertedWith(
        "maxTxAmount < 0.01%",
      );
      expect(await tokenContract.maxTxAmount()).to.equal((1_000_000n * 10n ** 18n) / 2000n);
    });

    it("set maxWallet", async () => {
      await expect(tokenContract.updateMaxWalletAmount(1)).to.be.revertedWith("maxWalletAmount < 0.01%");
      expect(await tokenContract.maxWalletAmount()).to.equal(((1_000_000n * 10n ** 18n) / 1000n) * 2n);

      await expect(tokenContract.updateMaxWalletAmount((1_000_000n * 10n ** 18n) / 2000n)).to.not.be.revertedWith(
        "maxWalletAmount < 0.01%",
      );
      expect(await tokenContract.maxWalletAmount()).to.equal((1_000_000n * 10n ** 18n) / 2000n);
    });

    it("disable trading karmaDeployer", async () => {
      await expect(tokenContract.disableTrading()).to.not.be.revertedWith("Only karma deployer");
      expect(await tokenContract.tradingEnabled()).to.equal(false);
    });

    it("enable trading karmaDeployer", async () => {
      await expect(tokenContract.enableTrading()).to.not.be.revertedWith("Trading already active");
      expect(await tokenContract.tradingEnabled()).to.equal(true);
    });

    it("disable trading user owner", async () => {
      await tokenContract.transferOwnership(user.address);
      expect(await tokenContract.owner()).to.be.eq(user.address);

      const userTokenContract = tokenContract.connect(user);

      await expect(userTokenContract.disableTrading()).to.be.revertedWith("Only karma deployer can disable");
      expect(await userTokenContract.tradingEnabled()).to.equal(true);
    });

    it("transfer", async () => {
      const userTokenContract = tokenContract.connect(user);
      await tokenContract.transfer("0x888cea2bbdd5d47a4032cf63668d7525c74af57a", 1000000);
      expect(await userTokenContract.balanceOf("0x888cea2bbdd5d47a4032cf63668d7525c74af57a")).to.eq(1000000);
    });

    it("buy", async () => {
      // eslint-disable-next-line @typescript-eslint/no-unused-vars
      const [owner, user, user2] = await ethers.getSigners();
      const userTokenContract = tokenContract.connect(user);

      await userTokenContract.updateMaxTxAmount((1_000_000n * 10n ** 18n) / 100n);
      await userTokenContract.updateMaxWalletAmount(((1_000_000n * 10n ** 18n) / 100n) * 2n);

      const weth = await router.WETH();
      const routerUser = await router.connect(user2);

      await routerUser.swapExactETHForTokens(
        0,
        [weth, tokenContract.address],
        user2.address,
        Math.round(Date.now() / 1000) + 3600,
        { value: eth(1) },
      );

      expect(await tokenContract.balanceOf(user2.address)).to.eq(9158135226595044137385n);
    });

    it("sell", async () => {
      // eslint-disable-next-line @typescript-eslint/no-unused-vars
      const [owner, user, user2, user3] = await ethers.getSigners();
      const weth = await router.WETH();
      const routerUser = await router.connect(user3);
      const userTokenContract = tokenContract.connect(user3);

      await routerUser.swapExactETHForTokens(
        0,
        [weth, tokenContract.address],
        user3.address,
        Math.round(Date.now() / 1000) + 3600,
        { value: eth(1) },
      );

      await userTokenContract.approve(router.address, ethers.constants.MaxUint256);
      expect(await tokenContract.balanceOf(user3.address)).to.eq(8980914776125942961565n);
      const initialETH = await user3.getBalance();

      await routerUser.swapExactTokensForETHSupportingFeeOnTransferTokens(
        8980914776125942961565n,
        0,
        [tokenContract.address, weth],
        user3.address,
        Math.round(Date.now() / 1000) + 3600,
      );

      expect(await tokenContract.balanceOf(user3.address)).to.eq(0n);
      expect(Math.ceil(parseFloat(utils.formatEther((await user3.getBalance()).sub(initialETH))))).to.eq(1);
    });
  });
});
