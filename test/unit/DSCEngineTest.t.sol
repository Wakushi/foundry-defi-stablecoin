// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    address public USER_B = makeAddr("userb");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL_TO_REDEEM = 1 ether;
    uint256 public constant LOW_AMOUNT_COLLATERAL = 1;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_DSC_TO_MINT = 50;
    uint256 public constant AMOUNT_DSC_TO_BURN = 40;
    uint256 public constant BIG_AMOUNT_DSC_TO_MINT = 2000;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(USER_B, STARTING_ERC20_BALANCE);
    }

    //////////////////////////
    // Constructor Tests    //
    //////////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ////////////////
    // Modifiers  //
    ////////////////

    modifier despositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier mintDsc() {
        vm.startPrank(USER);
        dscEngine.mintDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        _;
    }

    ////////////////////
    // Price Tests    //
    ////////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30,000e18
        uint256 expectedUsdValue = 30000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsdValue);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 4000 ether;
        uint256 tokenAmountFromUsd = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        uint256 expectedTokenAmount = 2 ether;
        assertEq(tokenAmountFromUsd, expectedTokenAmount);
    }

    //////////////////////////////
    // despositCollateral Tests //
    //////////////////////////////

    function testRevertsIfCollateralZero() public {
        // The user will make the next call
        vm.startPrank(USER);
        // The user approves our DSCEngine to take control of the entered amount
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock rugToken = new ERC20Mock("RUG", "RUG", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(rugToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDespositCollateralAndGetAccountInfo() public despositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        // The user has only just deposited collateral, not minted yet
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDespositAmountInUsd = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(collateralValueInUsd, expectedDespositAmountInUsd);
    }

    function testDscEngineIsFundedWithCollateralDeposited() public despositedCollateral {
        uint256 dscEngineEthBalance = ERC20Mock(weth).balanceOf(address(dscEngine));
        assertEq(dscEngineEthBalance, AMOUNT_COLLATERAL);
    }

    ///////////////////
    // mintDsc Tests //
    ///////////////////

    function testCanMintDscAndGetAccountInfo() public despositedCollateral mintDsc {
        (uint256 totalDscMinted,) = dscEngine.getAccountInformation(USER);
        uint256 userDscBalance = dsc.balanceOf(USER);
        assertEq(totalDscMinted, AMOUNT_DSC_TO_MINT);
        assertEq(totalDscMinted, userDscBalance);
    }

    function testMintDscRevertsIfNotEnoughCollateralDeposited() public {
        vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
        vm.startPrank(USER);
        dscEngine.mintDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
    }

    ///////////////////
    // burnDsc Tests //
    ///////////////////

    function testCanBurnDsc() public despositedCollateral mintDsc {
        uint256 previousDscDebt = dscEngine.getUserDebt(USER);
        uint256 startingDscBalance = dsc.balanceOf(USER);
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_DSC_TO_MINT);
        dscEngine.burnDsc(AMOUNT_DSC_TO_BURN);
        vm.stopPrank();
        uint256 finalDscDebt = dscEngine.getUserDebt(USER);
        uint256 endingDscBalance = dsc.balanceOf(USER);
        assertEq(finalDscDebt, previousDscDebt - AMOUNT_DSC_TO_BURN);
        assertEq(endingDscBalance, startingDscBalance - AMOUNT_DSC_TO_BURN);
    }

    ////////////////////////////
    // redeemCollateral Tests //
    ////////////////////////////

    function testCanRedeemCollateral() public despositedCollateral {
        uint256 startingCollateralDeposited = dscEngine.getCollateralDeposited(USER, weth);
        vm.startPrank(USER);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 endingCollateralDeposited = dscEngine.getCollateralDeposited(USER, weth);
        assertEq(endingCollateralDeposited, startingCollateralDeposited - AMOUNT_COLLATERAL);
    }

    function testCantRedeemCollateralIfHasMintedDscAndBreaksHealthFactor() public despositedCollateral mintDsc {
        vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
        vm.startPrank(USER);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
    }

    function testCanRedeemCollateralIfHasMintedDscAndDoesntBreakHealthFactor() public despositedCollateral mintDsc {
        uint256 startingCollateralDeposited = dscEngine.getCollateralDeposited(USER, weth);
        vm.startPrank(USER);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL / 2);
        vm.stopPrank();
        uint256 endingCollateralDeposited = dscEngine.getCollateralDeposited(USER, weth);
        assertEq(endingCollateralDeposited, startingCollateralDeposited - AMOUNT_COLLATERAL / 2);
    }

    ////////////////////////////////////////
    // despositCollateralAndMintDsc Tests //
    ////////////////////////////////////////

    function testCanDepositCollateralAndMintDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        (uint256 totalDscMinted,) = dscEngine.getAccountInformation(USER);
        uint256 userDscBalance = dsc.balanceOf(USER);
        assertEq(totalDscMinted, AMOUNT_DSC_TO_MINT);
        assertEq(totalDscMinted, userDscBalance);
    }

    function testDepositCollateralAndMintDscRevertsIfNotEnoughCollateralDeposited() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), LOW_AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
        dscEngine.depositCollateralAndMintDsc(weth, LOW_AMOUNT_COLLATERAL, BIG_AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
    }

    //////////////////////////////////
    // redeemCollateralForDsc Tests //
    //////////////////////////////////

    function testCanRedeemCollateralForDsc() public despositedCollateral mintDsc {
        uint256 startingCollateralDeposited = dscEngine.getCollateralDeposited(USER, weth);
        uint256 startingDscBalance = dsc.balanceOf(USER);
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_DSC_TO_BURN);
        dscEngine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL_TO_REDEEM, AMOUNT_DSC_TO_BURN);
        vm.stopPrank();
        uint256 endingCollateralDeposited = dscEngine.getCollateralDeposited(USER, weth);
        uint256 endingDscBalance = dsc.balanceOf(USER);
        assertEq(endingCollateralDeposited, startingCollateralDeposited - AMOUNT_COLLATERAL_TO_REDEEM);
        assertEq(endingDscBalance, startingDscBalance - AMOUNT_DSC_TO_BURN);
    }

    /////////////////////
    // liquidate Tests //
    /////////////////////
}
