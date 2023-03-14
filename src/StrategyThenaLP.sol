// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IThenaPair.sol";
import "./interfaces/IThenaGaugeV2.sol";
import "./interfaces/IThenaRouter.sol";

// constants
// LP(sAMM USDT-FRAX LP): 0x8D65dBe7206A768C466073aF0AB6d76f9e14Fc6D
// USDT: 0x55d398326f99059fF775485246999027B3197955
// FRAX: 0x90c97f71e18723b0cf0dfa30ee176ab653e89f40
// Want token(USDT): 0x55d398326f99059fF775485246999027B3197955
// Strategy (LP Pool): 0x4b1F8AC4C46348919B70bCAB62443EeAfB770Aa4
// Thena Router: 0xd4ae6eCA985340Dd434D38F470aCCce4DC78D109
// Reward Token(Thena): 0xf4c8e32eadec4bfe97e0f595add0f4450a863a11

/// @title Thena LP strategy
contract StrategyThenaLP is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // treasury
    address public treasury;
    uint256 public treasuryFeePercent;

    // tokens
    address public want;
    address public immutable lpToken0;
    address public immutable lpToken1;
    address public immutable rewardToken;

    // Third party contracts
    address public thenaRouter;
    address public lp;

    // strategy
    address public strategy;

    // path
    mapping(address => mapping(address => IThenaRouter.ThenaRoute[]))
        public paths;

    // events
    event Deposited(address indexed user, uint256 balance);
    event Withdrawed(address indexed user, uint256 balance);
    event Harvested(
        address indexed user,
        uint256 harvestedAmnt,
        uint256 compoundedAmnt,
        uint256 treasuryFee
    );

    constructor(
        address want_,
        address lp_,
        address thenaRouter_,
        address strategy_,
        address treasury_,
        uint256 treasuryFeePercent_
    ) {
        want = want_;
        lp = lp_;
        lpToken0 = IThenaPair(lp_).token0();
        lpToken1 = IThenaPair(lp_).token1();
        rewardToken = IThenaGaugeV2(strategy_).rewardToken();

        thenaRouter = thenaRouter_;
        strategy = strategy_;

        treasury = treasury_;
        treasuryFeePercent = treasuryFeePercent_;
    }

    /**
     * @notice Get pending reward
     */
    function pendingReward() public view returns (uint256) {
        return IThenaGaugeV2(strategy).earned(address(this));
    }

    /**
     * @notice Get path
     * @param inToken_ token address of inToken
     * @param outToken_ token address of outToken
     */
    function getPath(
        address inToken_,
        address outToken_
    ) public view returns (IThenaRouter.ThenaRoute[] memory) {
        IThenaRouter.ThenaRoute[] memory path = paths[inToken_][outToken_];
        require(path.length > 1, "Path length is not valid");
        require(path[0].from == inToken_, "Path is not existed");
        require(path[path.length - 1].to == outToken_, "Path is not existed");

        return path;
    }

    /**
     * @notice Deposit into strategy
     */
    function deposit() external nonReentrant {
        // get want token balance in contract
        uint256 wantAmnt = IERC20(want).balanceOf(address(this));

        require(wantAmnt > 0, "No want to deposit");

        // get lp from want token
        uint256 lpAmount = _getLPFromWant(wantAmnt);

        // deposit sAMM USDT/FRAX LP into USDT/FRAX LP
        IERC20(lp).safeApprove(strategy, 0);
        IERC20(lp).safeApprove(strategy, lpAmount);

        IThenaGaugeV2(strategy).deposit(lpAmount);

        emit Deposited(msg.sender, wantAmnt);
    }

    /**
     * @notice Withdraw from strategy
     * @param lpAmount_ amount of lp
     */
    function withdraw(uint256 lpAmount_) external onlyOwner nonReentrant {
        // withdraw from strategy
        IThenaGaugeV2(strategy).withdraw(lpAmount_);

        // withdrawn lp amount from strategy
        uint256 lpAmnt = IERC20(lp).balanceOf(address(this));

        if (lpAmnt > 0) {
            // get want amount from LP
            uint256 wantAmnt = _getWantFromLP(lpToken0, lpToken1, lpAmnt);

            // TODO: transfer want token to vault or other

            emit Withdrawed(msg.sender, wantAmnt);
        } else {
            emit Withdrawed(msg.sender, 0);
        }
    }

    /**
     * @notice Withdraw all from strategy
     */
    function withdrawAll() external onlyOwner nonReentrant {
        // withdraw from strategy
        IThenaGaugeV2(strategy).withdrawAll();

        // withdrawn lp amount from strategy
        uint256 lpAmnt = IERC20(lp).balanceOf(address(this));

        if (lpAmnt > 0) {
            // get want amount from LP
            uint256 wantAmnt = _getWantFromLP(lpToken0, lpToken1, lpAmnt);

            // TODO: transfer want token to vault or other

            emit Withdrawed(msg.sender, wantAmnt);
        } else {
            emit Withdrawed(msg.sender, 0);
        }
    }

    /**
     * @notice Harvest from strategy
     */
    function harvest() external onlyOwner nonReentrant {
        uint256 availableReward = pendingReward();
        require(availableReward > 0, "No reward to harvest");

        // withdraw reward from strategy
        IThenaGaugeV2(strategy).getReward();

        // reward amount
        uint256 rewardAmnt = IERC20(rewardToken).balanceOf(address(this));

        // transfer reward usdt to treasury
        uint256 treasuryFee = (rewardAmnt * treasuryFeePercent) / 10000;
        uint256 treasuryFeeInUsdt = _swapOnRouter(
            rewardToken,
            want,
            treasuryFee
        );
        IERC20(want).safeTransfer(treasury, treasuryFeeInUsdt);

        // get LP from reward token
        uint256 compoundAmnt = rewardAmnt - treasuryFee;
        uint256 lpAmount = _getLPFromReward(compoundAmnt);
        IERC20(lp).safeApprove(strategy, 0);
        IERC20(lp).safeApprove(strategy, lpAmount);

        // compound LP to strategy
        IThenaGaugeV2(strategy).deposit(lpAmount);

        emit Harvested(msg.sender, rewardAmnt, lpAmount, treasuryFeeInUsdt);
    }

    /**
     * @notice Set paths from inToken to outToken
     * @param inToken_ token address of inToken
     * @param outToken_ token address of outToken
     * @param paths_ swapping paths
     */
    function setPath(
        address inToken_,
        address outToken_,
        IThenaRouter.ThenaRoute[] memory paths_
    ) external onlyOwner {
        require(paths_.length > 1, "Invalid paths length");
        require(inToken_ == paths_[0].from, "Invalid inToken address");
        require(
            outToken_ == paths_[paths_.length - 1].to,
            "Invalid outToken address"
        );

        uint256 i;
        for (i; i < paths_.length; i++) {
            if (i < paths[inToken_][outToken_].length) {
                paths[inToken_][outToken_][i] = paths_[i];
            } else {
                paths[inToken_][outToken_].push(paths_[i]);
            }
        }

        if (paths[inToken_][outToken_].length > paths_.length)
            for (
                i = 0;
                i < paths[inToken_][outToken_].length - paths_.length;
                i++
            ) paths[inToken_][outToken_].pop();
    }

    /**
     * @notice get LP from want token
     * @param amount_ amount of want token
     */
    function _getLPFromWant(
        uint256 amount_
    ) internal returns (uint256 lpAmount) {
        uint256 wantAmnt = amount_ / 2;
        uint256 pairTokenAmnt = _swapOnRouter(
            want,
            want == lpToken0 ? lpToken1 : lpToken0,
            wantAmnt
        );

        // get lp from usdt and frax
        lpAmount = _getLP(
            lpToken0,
            lpToken1,
            want == lpToken0 ? wantAmnt : pairTokenAmnt,
            want == lpToken0 ? pairTokenAmnt : wantAmnt
        );
    }

    /**
     * @notice get LP from reward token
     * @param amount_ amount of reward token
     */
    function _getLPFromReward(
        uint256 amount_
    ) internal returns (uint256 lpAmount) {
        // get pair tokens from reward token
        uint256 token0Amnt = _swapOnRouter(rewardToken, lpToken0, amount_ / 2);
        uint256 token1Amnt = _swapOnRouter(rewardToken, lpToken1, amount_ / 2);

        // get lp from usdt and frax
        lpAmount = _getLP(lpToken0, lpToken1, token0Amnt, token1Amnt);
    }

    /**
     * @notice get want tokean from LP
     * @param token0_ address of token0
     * @param token1_ address of token1
     * @param amount_ amount of LP
     */
    function _getWantFromLP(
        address token0_,
        address token1_,
        uint256 amount_
    ) internal returns (uint256 wantAmnt) {
        IERC20(lp).safeApprove(thenaRouter, amount_);
        (uint256 amountA, uint256 amountB) = IThenaRouter(thenaRouter)
            .removeLiquidity(
                token0_,
                token1_,
                true, // stable or volatile
                amount_,
                0,
                0,
                address(this),
                block.timestamp
            );

        // if token0 is want
        if (want == lpToken0) {
            // convert token1 to want
            uint256 swappedWantAmnt = _swapOnRouter(
                lpToken1,
                lpToken0,
                amountB
            );
            wantAmnt = amountA + swappedWantAmnt;
        } else {
            // convert token0 to want
            uint256 swappedWantAmnt = _swapOnRouter(
                lpToken0,
                lpToken1,
                amountA
            );
            wantAmnt = amountB + swappedWantAmnt;
        }
    }

    /**
     * @notice swap on Thena router
     * @param inToken_ address of in token
     * @param outToken_ address of out token
     * @param amountIn_ amount of in token
     */
    function _swapOnRouter(
        address inToken_,
        address outToken_,
        uint256 amountIn_
    ) internal returns (uint256 amountOut) {
        IERC20(inToken_).safeApprove(thenaRouter, amountIn_);

        IThenaRouter.ThenaRoute[] memory routes = getPath(inToken_, outToken_);
        uint256[] memory amountsOuts = IThenaRouter(thenaRouter).getAmountsOut(
            amountIn_,
            routes
        );
        uint256 amountOutMin = amountsOuts[amountsOuts.length - 1];

        // swap in token to out token
        uint256[] memory amounts = IThenaRouter(thenaRouter)
            .swapExactTokensForTokens(
                amountIn_,
                amountOutMin,
                routes,
                address(this),
                block.timestamp
            );

        // outToken amount
        amountOut = amounts[routes.length - 1];
    }

    /**
     * @notice get Thena LP
     * @param token0_ address of token0
     * @param token1_ address of token1
     * @param token0Amnt_ amount of token0
     * @param token1Amnt_ amount of token1
     */
    function _getLP(
        address token0_,
        address token1_,
        uint256 token0Amnt_,
        uint256 token1Amnt_
    ) internal returns (uint256 amountOut) {
        // approve router contract to transfer token0 and token1 from this contract
        IERC20(token0_).safeApprove(thenaRouter, 0);
        IERC20(token0_).safeApprove(thenaRouter, token0Amnt_);
        IERC20(token1_).safeApprove(thenaRouter, 0);
        IERC20(token1_).safeApprove(thenaRouter, token1Amnt_);

        // get Thena LP
        (, , amountOut) = IThenaRouter(thenaRouter).addLiquidity(
            token0_,
            token1_,
            true, // stable or volatile
            token0Amnt_,
            token1Amnt_,
            0,
            0,
            address(this),
            block.timestamp
        );
    }
}
