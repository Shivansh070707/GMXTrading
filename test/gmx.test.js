const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("GMX Trading", function () {
    let gmxTrading;
    let positionRouter;
    let usdcToken;
    let vault;
    let owner;
    let user1;
    let user2;
    let whale;
    let gmxVault;

    // GMX contract addresses on Arbitrum
    const POSITION_ROUTER = '0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868';
    const GMX_ROUTER_ADDRESS = "0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064";
    const GMX_READER_ADDRESS = "0x22199a49A999c351eF7927602CFB187ec3cae489";
    const GMX_VAULT_ADDRESS = "0x489ee077994B6658eAfA855C308275EAd8097C4A";
    const USDC_ADDRESS = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831";
    const WETH_ADDRESS = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
    const WBTC_ADDRESS = "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f"
    const WHALE_ADDRESS = "0x1F7bc4dA1a0c2e49d7eF542F74CD46a3FE592cb1";

    before(async function () {
        [owner, user1, user2] = await ethers.getSigners();

        whale = await ethers.getImpersonatedSigner(WHALE_ADDRESS);

        const Vault = await ethers.getContractFactory("Vault");
        vault = await Vault.deploy(USDC_ADDRESS)

        const GMXTrading = await ethers.getContractFactory("GMXTrading");
        gmxTrading = await GMXTrading.deploy(
            POSITION_ROUTER,
            GMX_ROUTER_ADDRESS,
            GMX_READER_ADDRESS,
            GMX_VAULT_ADDRESS,
            USDC_ADDRESS,
            vault.target,
            [WBTC_ADDRESS, WETH_ADDRESS]
        );

        positionRouter = await ethers.getContractAt("IGMXPositionRouter", POSITION_ROUTER);
        gmxVault = await ethers.getContractAt("IVault", GMX_VAULT_ADDRESS);
        usdcToken = await ethers.getContractAt("IERC20", USDC_ADDRESS);

        // Transfer USDC from whale to user1
        const transferAmount = ethers.parseUnits("100000", 6); // 100,000 USDC
        await usdcToken.connect(whale).transfer(user1.address, transferAmount);
    });

    it("Should allow owner to whitelist a user", async function () {
        await expect(gmxTrading.connect(owner).addToWhitelist(user1.address))
            .to.emit(gmxTrading, "UserWhitelisted")
            .withArgs(user1.address);

        expect(await gmxTrading.whitelistedUsers(user1.address)).to.be.true;
    });

    it("Should create a new user account for whitelisted user", async function () {
        await expect(gmxTrading.connect(user1).createAccount())
            .to.emit(gmxTrading, "AccountCreated");

        const userAccountAddress = await gmxTrading.getUserAccount(user1.address);
        expect(userAccountAddress).to.not.equal(ethers.ZeroAddress);
    });

    it("Should not allow creating multiple accounts for the same user", async function () {
        await expect(gmxTrading.connect(user1).createAccount())
            .to.be.revertedWithCustomError(gmxTrading, "AccountAlreadyExists");
    });

    it("Should not allow non-whitelisted users to create an account", async function () {
        await expect(gmxTrading.connect(user2).createAccount())
            .to.be.revertedWithCustomError(gmxTrading, "UserNotWhitelisted");
    });

    it("Should allow transferring margin (USDC)", async function () {
        const transferAmount = ethers.parseUnits("10000", 6);
        await usdcToken.connect(user1).approve(vault.target, transferAmount);
        await gmxTrading.connect(user1).transferMargin(transferAmount);

        const userBalance = await gmxTrading.getUserBalance(user1.address);
        expect(userBalance).to.equal(transferAmount);
    });

    it("Should open long WETH and short WBTC positions, then close them", async function () {

        const positionRouterOwner = await ethers.getImpersonatedSigner('0xB4d2603B2494103C90B2c607261DD85484b49eF0');
        await positionRouter.connect(positionRouterOwner).setPositionKeeper(owner.address, true);

        const amountIn = ethers.parseUnits("1000", 6);
        const sizeDelta = ethers.parseUnits("5000", 30);
        const executionFee = await positionRouter.minExecutionFee();

        //Opening long WETH position
        const acceptablePriceWETH = await gmxVault.getMaxPrice(WETH_ADDRESS);
        await gmxTrading.connect(user1).openPosition(
            WETH_ADDRESS,
            amountIn,
            sizeDelta,
            true,
            acceptablePriceWETH,
            executionFee,
            { value: executionFee }
        );

        //Opening short WBTC position
        const acceptablePriceWBTC = await gmxVault.getMaxPrice(WBTC_ADDRESS);
        await gmxTrading.connect(user1).openPosition(
            WBTC_ADDRESS,
            amountIn,
            sizeDelta,
            false,
            acceptablePriceWBTC,
            executionFee,
            { value: executionFee }
        );

        const endIndexForIncreasePositions = await positionRouter.increasePositionRequestKeysStart();
        await positionRouter.connect(owner).executeIncreasePositions(Number(endIndexForIncreasePositions) + 2, owner.address);

        const positions = await gmxTrading.getPositions(
            user1.address,
            [WETH_ADDRESS, USDC_ADDRESS],
            [WETH_ADDRESS, WBTC_ADDRESS],
            [true, false]
        );

        expect(positions[0]).to.not.equal(0, "WETH long size should be non-zero");
        expect(positions[1]).to.not.equal(0, "WETH long collateral should be non-zero");
        expect(positions[9]).to.not.equal(0, "WBTC short size should be non-zero");
        expect(positions[10]).to.not.equal(0, "WBTC short collateral should be non-zero");

        //Closing long WETH position
        await gmxTrading.connect(user1).closePosition(
            WETH_ADDRESS,
            0, // collateralDelta (0 to close full position)
            positions[0], // Use the actual size
            true, // isLong
            await gmxVault.getMaxPrice(WETH_ADDRESS),
            executionFee,
            { value: executionFee }
        );

        //Closing short WBTC position
        await gmxTrading.connect(user1).closePosition(
            WBTC_ADDRESS,
            0,
            positions[9],
            false,
            await gmxVault.getMaxPrice(WBTC_ADDRESS),
            executionFee,
            { value: executionFee }
        );

        const endIndexForDecreasePositions = await positionRouter.decreasePositionRequestKeysStart();
        await positionRouter.connect(owner).executeDecreasePositions(Number(endIndexForDecreasePositions) + 2, owner.address);

        const closedPositions = await gmxTrading.getPositions(
            user1.address,
            [WETH_ADDRESS, USDC_ADDRESS],
            [WETH_ADDRESS, WBTC_ADDRESS],
            [true, false]
        );

        expect(closedPositions[0]).to.equal(0, "WETH long size should be zero after closing");
        expect(closedPositions[1]).to.equal(0, "WETH long collateral should be zero after closing");
        expect(closedPositions[9]).to.equal(0, "WBTC short size should be zero after closing");
        expect(closedPositions[10]).to.equal(0, "WBTC short collateral should be zero after closing");
    });
    it("Should cancel position and get back tokens", async function () {
        const positionRouterOwner = await ethers.getImpersonatedSigner('0xB4d2603B2494103C90B2c607261DD85484b49eF0');
        await positionRouter.connect(positionRouterOwner).setPositionKeeper(owner.address, true);

        const amountIn = ethers.parseUnits("1000", 6);
        const sizeDelta = ethers.parseUnits("5000", 30);
        const executionFee = await positionRouter.minExecutionFee();
        const userAddress = await gmxTrading.userAccounts(user1.address)

        const acceptablePriceWETH = await gmxVault.getMaxPrice(WETH_ADDRESS);
        const orderId = await gmxTrading.connect(user1).openPosition.staticCall(
            WETH_ADDRESS,
            amountIn,
            sizeDelta,
            true,
            acceptablePriceWETH,
            executionFee,
            { value: executionFee, from: user1 }
        );
        await gmxTrading.connect(user1).openPosition(
            WETH_ADDRESS,
            amountIn,
            sizeDelta,
            true,
            acceptablePriceWETH,
            executionFee,
            { value: executionFee, from: user1 }
        );

        let increasePositionIndex = await positionRouter.increasePositionsIndex(userAddress)
        expect(increasePositionIndex).to.not.eq(0)

        await ethers.provider.send("evm_increaseTime", [181]);
        await ethers.provider.send("evm_mine");
        await expect(gmxTrading.connect(user1).cancelOrder(orderId)).to.changeTokenBalances(usdcToken, [vault.target], [amountIn]);

        const endIndexForIncreasePositions = await positionRouter.increasePositionRequestKeysStart();
        await positionRouter.connect(owner).executeIncreasePositions(Number(endIndexForIncreasePositions) + 2, owner.address)

        const closedPositions = await gmxTrading.getPositions(
            user1.address,
            [WETH_ADDRESS],
            [WETH_ADDRESS],
            [true]
        );

        expect(closedPositions[0]).to.equal(0, "WETH long size should be zero after closing");
        expect(closedPositions[1]).to.equal(0, "WETH long collateral should be zero after closing");
    });
    it("Should cancel position and get back execution fees", async function () {
        const positionRouterOwner = await ethers.getImpersonatedSigner('0xB4d2603B2494103C90B2c607261DD85484b49eF0');
        await positionRouter.connect(positionRouterOwner).setPositionKeeper(owner.address, true);

        const amountIn = ethers.parseUnits("1000", 6);
        const sizeDelta = ethers.parseUnits("5000", 30);
        const executionFee = await positionRouter.minExecutionFee();
        const userAddress = await gmxTrading.userAccounts(user1.address)

        const acceptablePriceWETH = await gmxVault.getMaxPrice(WETH_ADDRESS);
        const orderId = await gmxTrading.connect(user1).openPosition.staticCall(
            WETH_ADDRESS,
            amountIn,
            sizeDelta,
            false,
            acceptablePriceWETH,
            executionFee,
            { value: executionFee, from: user1 }
        );
        const balanceBeforeOrder = await vault.balances(user1.address)

        await gmxTrading.connect(user1).openPosition(
            WETH_ADDRESS,
            amountIn,
            sizeDelta,
            true,
            acceptablePriceWETH,
            executionFee,
            { value: executionFee, from: user1 }
        );
        const balanceAfterOrder = await vault.balances(user1.address)
        expect(balanceAfterOrder).to.eq(Number(balanceBeforeOrder) - Number(amountIn))

        let increasePositionIndex = await positionRouter.increasePositionsIndex(userAddress)
        expect(increasePositionIndex).to.not.eq(0)

        await ethers.provider.send("evm_increaseTime", [181]);
        await ethers.provider.send("evm_mine");
        await expect(gmxTrading.connect(user1).cancelOrder(orderId)).to.changeEtherBalances([user1.address], [executionFee]);
        const balanceAfterCancelOrder = await vault.balances(user1.address)
        expect(balanceAfterCancelOrder).to.eq(balanceBeforeOrder)
        const endIndexForIncreasePositions = await positionRouter.increasePositionRequestKeysStart();
        await positionRouter.connect(owner).executeIncreasePositions(Number(endIndexForIncreasePositions) + 2, owner.address)

        const closedPositions = await gmxTrading.getPositions(
            user1.address,
            [WETH_ADDRESS],
            [WETH_ADDRESS],
            [true]
        );

        expect(closedPositions[0]).to.equal(0, "WETH long size should be zero after closing");
        expect(closedPositions[1]).to.equal(0, "WETH long collateral should be zero after closing");
    });
    it("Should allow owner to add supported asset", async function () {
        const newAsset = "0x1234567890123456789012345678901234567890";
        await expect(gmxTrading.connect(owner).addSupportedAsset(newAsset))
            .to.emit(gmxTrading, "AssetAdded")
            .withArgs(newAsset);

        expect(await gmxTrading.isAssetSupported(newAsset)).to.be.true;
    });
    it("Should allow owner to remove supported asset", async function () {
        const assetToRemove = "0x1234567890123456789012345678901234567890";
        await expect(gmxTrading.connect(owner).removeSupportedAsset(assetToRemove))
            .to.emit(gmxTrading, "AssetRemoved")
            .withArgs(assetToRemove);

        expect(await gmxTrading.isAssetSupported(assetToRemove)).to.be.false;
    });
    it("Should allow owner to remove user from whitelist", async function () {
        await expect(gmxTrading.connect(owner).removeFromWhitelist(user1.address))
            .to.emit(gmxTrading, "UserRemovedFromWhitelist")
            .withArgs(user1.address);

        expect(await gmxTrading.whitelistedUsers(user1.address)).to.be.false;
    });
    it("Should not allow non-whitelisted users to perform actions", async function () {
        const amount = ethers.parseUnits("100", 6);
        const sizeDelta = ethers.parseUnits("1000", 6);
        const isLong = true;
        const price = ethers.parseUnits("2000", 8);
        const executionFee = ethers.parseEther("0.01");

        await expect(gmxTrading.connect(user1).transferMargin(amount))
            .to.be.revertedWithCustomError(gmxTrading, "UserNotWhitelisted");

        await expect(gmxTrading.connect(user1).openPosition(WETH_ADDRESS, amount, sizeDelta, isLong, price, executionFee, { value: executionFee }))
            .to.be.revertedWithCustomError(gmxTrading, "UserNotWhitelisted");

        await expect(gmxTrading.connect(user1).closePosition(WETH_ADDRESS, amount, sizeDelta, isLong, price, executionFee, { value: executionFee }))
            .to.be.revertedWithCustomError(gmxTrading, "UserNotWhitelisted");
    });
    it("Should return correct user balance", async function () {
        const balance = await gmxTrading.getUserBalance(user1.address);
        expect(balance).to.equal(await vault.getBalance(user1.address));
    });
    it("Should return correct supported assets", async function () {
        const supportedAssets = await gmxTrading.getSupportedAssets();
        expect(supportedAssets).to.include(WETH_ADDRESS);
    });

});