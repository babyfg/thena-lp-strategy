// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {StrategyThenaLP} from "src/StrategyThenaLP.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../src/interfaces/IThenaRouter.sol";

contract StrategyThenaLPTest is Test {
    using stdStorage for StdStorage;

    // whale address
    address internal whale = 0x97b9D2102A9a65A26E1EE82D59e42d1B73B68689;
    address internal user1 = 0x013823485705f0773Ba8230D6Ed0B06a3d95C706;
    address internal user2 = 0x9E978d946839d3425d12682aDc3187F4AcE82fbd;
    address internal owner = 0x708fde9e8ff536B7B0021aE5D748679e28f1600a;

    // strategy params
    address internal usdt = 0x55d398326f99059fF775485246999027B3197955;
    address internal frax = 0x90C97F71E18723b0Cf0dfa30ee176Ab653E89F40;
    address internal thena = 0xF4C8E32EaDEC4BFe97E0F595AdD0f4450a863a11;
    address internal want = usdt;
    address internal lp = 0x8D65dBe7206A768C466073aF0AB6d76f9e14Fc6D; // lp(sAMM USDT-FRAX LP)
    address internal thenaRouter = 0xd4ae6eCA985340Dd434D38F470aCCce4DC78D109; // thena router
    address internal thenaLpStrategy =
        0x4b1F8AC4C46348919B70bCAB62443EeAfB770Aa4; // sAMM USDT-FRAX Pool
    address internal treasury = 0x4ea60A428838e70D0459479a82b1A005fe329BD8;
    uint256 internal treasuryFeePercent = 2000;

    StrategyThenaLP strategy;

    function setUp() external {
        // deploy contract
        vm.prank(owner);
        strategy = new StrategyThenaLP(
            usdt,
            lp,
            thenaRouter,
            thenaLpStrategy,
            treasury,
            treasuryFeePercent
        );

        // set usdt->frax swap path
        vm.prank(owner);
        IThenaRouter.ThenaRoute[]
            memory routes1 = new IThenaRouter.ThenaRoute[](3);
        routes1[0] = IThenaRouter.ThenaRoute({
            from: 0x55d398326f99059fF775485246999027B3197955,
            to: 0xe80772Eaf6e2E18B651F160Bc9158b2A5caFCA65,
            stable: true
        });
        routes1[1] = IThenaRouter.ThenaRoute({
            from: 0xe80772Eaf6e2E18B651F160Bc9158b2A5caFCA65,
            to: 0xFa4BA88Cf97e282c505BEa095297786c16070129,
            stable: true
        });
        routes1[2] = IThenaRouter.ThenaRoute({
            from: 0xFa4BA88Cf97e282c505BEa095297786c16070129,
            to: 0x90C97F71E18723b0Cf0dfa30ee176Ab653E89F40,
            stable: true
        });

        strategy.setPath(usdt, frax, routes1);

        // set frax->usdt swap path
        vm.prank(owner);
        IThenaRouter.ThenaRoute[]
            memory routes2 = new IThenaRouter.ThenaRoute[](3);
        routes2[0] = IThenaRouter.ThenaRoute({
            from: 0x90C97F71E18723b0Cf0dfa30ee176Ab653E89F40,
            to: 0xFa4BA88Cf97e282c505BEa095297786c16070129,
            stable: true
        });
        routes2[1] = IThenaRouter.ThenaRoute({
            from: 0xFa4BA88Cf97e282c505BEa095297786c16070129,
            to: 0xe80772Eaf6e2E18B651F160Bc9158b2A5caFCA65,
            stable: true
        });
        routes2[2] = IThenaRouter.ThenaRoute({
            from: 0xe80772Eaf6e2E18B651F160Bc9158b2A5caFCA65,
            to: 0x55d398326f99059fF775485246999027B3197955,
            stable: true
        });

        strategy.setPath(frax, usdt, routes2);

        // set thena->usdt swap path
        vm.prank(owner);
        IThenaRouter.ThenaRoute[]
            memory routes3 = new IThenaRouter.ThenaRoute[](3);
        routes3[0] = IThenaRouter.ThenaRoute({
            from: 0xF4C8E32EaDEC4BFe97E0F595AdD0f4450a863a11,
            to: 0x1bdd3Cf7F79cfB8EdbB955f20ad99211551BA275,
            stable: false
        });
        routes3[1] = IThenaRouter.ThenaRoute({
            from: 0x1bdd3Cf7F79cfB8EdbB955f20ad99211551BA275,
            to: 0x90C97F71E18723b0Cf0dfa30ee176Ab653E89F40,
            stable: false
        });
        routes3[2] = IThenaRouter.ThenaRoute({
            from: 0x90C97F71E18723b0Cf0dfa30ee176Ab653E89F40,
            to: 0x55d398326f99059fF775485246999027B3197955,
            stable: true
        });

        strategy.setPath(thena, usdt, routes3);

        // set thena->frax swap path
        vm.prank(owner);
        IThenaRouter.ThenaRoute[]
            memory routes4 = new IThenaRouter.ThenaRoute[](2);
        routes4[0] = IThenaRouter.ThenaRoute({
            from: 0xF4C8E32EaDEC4BFe97E0F595AdD0f4450a863a11,
            to: 0x1bdd3Cf7F79cfB8EdbB955f20ad99211551BA275,
            stable: false
        });
        routes4[1] = IThenaRouter.ThenaRoute({
            from: 0x1bdd3Cf7F79cfB8EdbB955f20ad99211551BA275,
            to: 0x90C97F71E18723b0Cf0dfa30ee176Ab653E89F40,
            stable: false
        });

        strategy.setPath(thena, frax, routes4);

        // charge usdt to user1 and user2 accounts
        vm.prank(whale);
        IERC20(usdt).transfer(user1, 10000e18);
        vm.prank(whale);
        IERC20(usdt).transfer(user2, 10000e18);
    }

    function test_constructor_params_set_correctly() external {
        address _want = strategy.want();
        address _lp = strategy.lp();
        address _lpToken0 = strategy.lpToken0();
        address _lpToken1 = strategy.lpToken1();
        address _rewardToken = strategy.rewardToken();
        address _thenaRouter = strategy.thenaRouter();
        address _strategy = strategy.strategy();
        address _treasury = strategy.treasury();
        uint256 _treasuryFeePercent = strategy.treasuryFeePercent();

        assertEq(_want, want);
        assertEq(_lp, lp);
        assertEq(_lpToken0, usdt);
        assertEq(_lpToken1, frax);
        assertEq(_rewardToken, thena);
        assertEq(_thenaRouter, thenaRouter);
        assertEq(_strategy, thenaLpStrategy);
        assertEq(_treasury, treasury);
        assertEq(_treasuryFeePercent, treasuryFeePercent);
    }

    function test_failed_Deposit_when_no_want_token() external {
        vm.prank(user1);

        vm.expectRevert("Invalid want amount");
        strategy.deposit(0);
    }

    function test_success_Deposit() external {
        vm.prank(user1);
        IERC20(usdt).approve(address(strategy), 100e18);

        vm.prank(user1);
        strategy.deposit(100e18);
    }

    function test_success_Withdraw() external {
        vm.prank(user1);
        IERC20(usdt).approve(address(strategy), 100e18);

        vm.prank(user1);
        strategy.deposit(100e18);

        // withdraw
        vm.prank(user1);
        vm.expectRevert("No want to withdraw");
        strategy.withdraw(0);

        vm.prank(user1);
        vm.expectRevert("Exceed the amount");
        strategy.withdraw(200e18);

        vm.prank(user1);
        uint256 usdtBefore = IERC20(usdt).balanceOf(user1);
        vm.prank(user1);
        strategy.withdraw(100e18);
        uint256 usdtAfter = IERC20(usdt).balanceOf(user1);

        assertGt(usdtAfter, usdtBefore);
    }

    function test_success_Harvest() external {
        // deposit
        vm.prank(user1);
        IERC20(usdt).approve(address(strategy), 100e18);

        vm.prank(user1);
        strategy.deposit(100e18);

        // skip 7 days
        skip(7 days);

        // harvest
        uint256 usdtBefore = IERC20(usdt).balanceOf(treasury);
        vm.prank(owner);
        strategy.harvest();
        uint256 usdtAfter = IERC20(usdt).balanceOf(treasury);

        assertGt(usdtAfter, usdtBefore);
    }
}
