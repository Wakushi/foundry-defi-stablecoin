// SPDX-License-Identifier: MIT

// Have our invariants, aka the properties we want to hold true.
// What are our invariants ?

// 1. The total supply of DSC should be less than the total value of the collateral
// 2. Getter view functions should never revert <- evergreen invariant

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();
        handler = new Handler(dscEngine, dsc);
        // targetContract(address(dscEngine));
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // Get the value of all the collateral
        // Compare it to all the debt (dsc)
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalwethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalwbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValueInUsd = dscEngine.getUsdValue(weth, totalwethDeposited);
        uint256 wbtcValueInUsd = dscEngine.getUsdValue(wbtc, totalwbtcDeposited);

        console.log("wethValueInUsd", wethValueInUsd);
        console.log("wbtcValueInUsd", wbtcValueInUsd);
        console.log("totalSupply", totalSupply);
        console.log("Times mint is called", handler.timesMintIsCalled());

        uint256 totalCollateralValue = wethValueInUsd + wbtcValueInUsd;

        assert(totalCollateralValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        dscEngine.getCollateralTokens();
        dscEngine.getPrecision();
    }
}
