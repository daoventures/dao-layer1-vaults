// This zap contract is specific for Yearn on Curve pool only
// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ICurvePool {
    function add_liquidity(uint256[4] memory _amounts, uint256 _amountOutMin) external;
    function calc_token_amount(uint256[4] memory _amounts, bool _isDeposit) external returns (uint256);
    function get_virtual_price() external view returns (uint256);
}

interface ICurveZap {
    function add_liquidity(uint256[4] memory _amounts, uint256 _amountOutMin) external;
    function remove_liquidity_one_coin(uint256 _amount, int128 _index, uint256 _amountOutMin) external;
}

interface IEarnVault {
    function lpToken() external view returns (address);
    function investZap(uint256 _amount) external;
}

interface ISushiRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint[] memory amounts);
    function getAmountsOut(uint256 amountIn, address[] memory path) external view returns (uint[] memory amounts);
}

contract CurveYZap is Ownable {
    using SafeERC20 for IERC20;

    ISushiRouter private constant _sushiRouter = ISushiRouter(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);
    ICurvePool public constant curvePool = ICurvePool(0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51);
    ICurveZap public constant curveZap = ICurveZap(0xbBC81d23Ea2c3ec7e56D39296F0cbB648873a5d3);
    IEarnVault public vault;

    IERC20 private constant _WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 private constant _DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 private constant _USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private constant _USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 private constant _TUSD = IERC20(0x0000000000085d4780B73119b644AE5ecd22b376);
    IERC20 private constant _yDAI = IERC20(0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01);
    IERC20 private constant _yUSDC = IERC20(0xd6aD7a6750A7593E092a9B218d66C0A814a3436e);
    IERC20 private constant _yUSDT = IERC20(0x83f798e925BcD4017Eb265844FDDAbb448f1707D);
    IERC20 private constant _yTUSD = IERC20(0x73a052500105205d34Daf004eAb301916DA8190f);
    IERC20 private constant _lpToken = IERC20(0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8);

    mapping(address => bool) public isWhitelistedVault;

    event Deposit(address indexed vault, uint256 amount, address indexed coin, uint256 lptokenBal, uint256 daoERNBal, bool stake);
    event Withdraw(address indexed vault, uint256 shares, address indexed coin, uint256 lptokenBal, uint256 coinAmount);
    event SwapFees(uint256 amount, uint256 coinAmount, address indexed coin);
    event Compound(uint256 amount, address indexed vault, uint256 lpTokenBal);
    event AddLiquidity(uint256 amount, address indexed vault, address indexed best, uint256 lpTokenBal);
    event EmergencyWithdraw(uint256 amount, address indexed vault, uint256 lpTokenBal);
    event AddPool(address indexed vault, address indexed curvePool, address indexed curveZap);
    event SetStrategy(address indexed strategy);
    event SetBiconomy(address indexed biconomy);

    modifier onlyEOAOrBiconomy {
        require(msg.sender == tx.origin, "Only EOA or Biconomy");
        _;
    }

    constructor() {
        _WETH.safeApprove(address(_sushiRouter), type(uint).max);
    }

    /// @notice Function to swap fees from vault contract (and transfer back to vault contract)
    /// @param _amount Amount of LP token to be swapped (18 decimals)
    /// @return Amount and address of coin to receive (amount follow decimal of coin)
    function swapFees(uint256 _amount) external returns (uint256, address) {
        require(msg.sender == address(vault), "Only authorized vault");
        _lpToken.safeTransferFrom(msg.sender, address(this), _amount);
        curveZap.remove_liquidity_one_coin(_amount, 2, 0);
        uint256 _coinAmount = _USDT.balanceOf(address(this));
        _USDT.safeTransfer(msg.sender, _coinAmount);
        emit SwapFees(_amount, _coinAmount, address(_USDT));
        return (_coinAmount, address(_USDT));
    }

    /// @notice Function to swap WETH from strategy contract (and invest into strategy contract)
    /// @param _amount Amount to compound in WETH
    /// @return _lpTokenBal LP token amount to invest after add liquidity to Curve pool (18 decimals)
    function compound(uint256 _amount) external returns (uint256 _lpTokenBal) {
        require(isWhitelistedVault[msg.sender], "Only authorized vault");
        _lpTokenBal = _addLiquidity(_amount, msg.sender);
        IEarnVault(msg.sender).investZap(_lpTokenBal);
        emit Compound(_amount, msg.sender, _lpTokenBal);
    }

    /// @notice Function to swap WETH and add liquidity into Curve pool
    /// @param _amount Amount of WETH to swap and add into Curve pool
    /// @param _vault Address of vault contract to determine pool
    /// @return _lpTokenBal LP token amount received after add liquidity into Curve pool (18 decimals)
    function _addLiquidity(uint256 _amount, address _vault) private returns (uint256 _lpTokenBal) {
        _WETH.safeTransferFrom(_vault, address(this), _amount);
        // Swap WETH to coin which can provide highest LP token return
        address _best = _findCurrentBest(_amount, address(0));
        address[] memory _path = new address[](2);
        _path[0] = address(_WETH);
        _path[1] = _best;
        uint256[] memory _amountsOut = _sushiRouter.swapExactTokensForTokens(_amount, 0, _path, address(this), block.timestamp);
        // Add coin into Curve pool
        uint256[4] memory _amounts;
        if (_best == address(_DAI)) {
            _amounts[0] = _amountsOut[1];
        } else if (_best == address(_USDC)) {
            _amounts[1] = _amountsOut[1];
        } else if (_best == address(_USDT)) {
            _amounts[2] = _amountsOut[1];
        } else { // address(_TUSD)
            _amounts[3] = _amountsOut[1];
        }
        curveZap.add_liquidity(_amounts, 0);
        _lpTokenBal = _lpToken.balanceOf(address(this));
        emit AddLiquidity(_amount, _vault, _best, _lpTokenBal);
    }

    /// @notice Same function as compound() but transfer received LP token to vault instead of strategy contract
    /// @param _amount Amount to emergency withdraw in WETH
    /// @param _vault Address of vault contract
    function emergencyWithdraw(uint256 _amount, address _vault) external {
        require(isWhitelistedVault[msg.sender], "Only authorized vault");
        uint256 _lpTokenBal = _addLiquidity(_amount, _vault);
        IERC20(IEarnVault(_vault).lpToken()).safeTransfer(_vault, _lpTokenBal);
        emit EmergencyWithdraw(_amount, _vault, _lpTokenBal);
    }

    /// @notice Function to find coin that provide highest LP token return
    /// @param _amount Amount of WETH to be calculate
    /// @param _token Input token address to be calculate
    /// @return Coin address that provide highest LP token return
    function _findCurrentBest(uint256 _amount, address _token) private returns (address) {
        // Get estimated amount out of LP token for each input token
        uint256 _amountOut = _calcAmountOut(_amount, _token, address(_DAI));
        uint256 _amountOutUSDC = _calcAmountOut(_amount, _token, address(_USDC));
        uint256 _amountOutUSDT = _calcAmountOut(_amount, _token, address(_USDT));
        uint256 _amountOutTUSD = _calcAmountOut(_amount, _token, address(_TUSD));
        // Compare for highest LP token out among coin address
        address _best = address(_DAI);
        if (_amountOutUSDC > _amountOut) {
            _best = address(_USDC);
            _amountOut = _amountOutUSDC;
        }
        if (_amountOutUSDT > _amountOut) {
            _best = address(_USDT);
            _amountOut = _amountOutUSDT;
        }
        if (_amountOutTUSD > _amountOut) {
            _best = address(_TUSD);
        }
        return _best;
    }

    /// @notice Function to calculate amount out of LP token
    /// @param _amount Amount of WETH to be calculate
    /// @param _token Input token address to be calculate (for depositZap(), otherwise address(0))
    /// @return Amount out of LP token
    function _calcAmountOut(uint256 _amount, address _token, address _coin) private returns (uint256) {
        uint256 _amountOut;
        if (_token == address(0)) { // From _addLiquidity()
            address[] memory _path = new address[](2);
            _path[0] = address(_WETH);
            _path[1] = _coin;
            _amountOut = (_sushiRouter.getAmountsOut(_amount, _path))[1];
        } else { // From depositZap()
            address[] memory _path = new address[](3);
            _path[0] = _token;
            _path[1] = address(_WETH);
            _path[2] = _coin;
            _amountOut = (_sushiRouter.getAmountsOut(_amount, _path))[2];
        }

        uint256[4] memory _amounts;
        if (_coin == address(_DAI)) {
            _amounts[0] = _amountOut;
        } else if (_coin == address(_USDC)) {
            _amounts[1] = _amountOut;
        } else if (_coin == address(_USDT)) {
            _amounts[2] = _amountOut;
        } else { // address(_TUSD)
            _amounts[3] = _amountOut;
        }
        return curvePool.calc_token_amount(_amounts, true);
    }

    /// @notice Function to add new Curve Y pool (limit only for Curve Y pool)
    /// @param vault_ Address of corresponding vault contract
    /// @param curvePool_ Address of Curve Y contract
    /// @param curveZap_ Address of Curve Y deposit zap contract
    function addPool(address vault_, address curvePool_, address curveZap_) external onlyOwner {
        vault = IEarnVault(vault_);
        
        isWhitelistedVault[vault_] = true;

        _lpToken.safeApprove(vault_, type(uint).max);
        _lpToken.safeApprove(curveZap_, type(uint).max);
        _DAI.safeApprove(curveZap_, type(uint).max);
        _USDC.safeApprove(curveZap_, type(uint).max);
        _USDT.safeApprove(curveZap_, type(uint).max);
        _TUSD.safeApprove(curveZap_, type(uint).max);
        _yDAI.safeApprove(curvePool_, type(uint).max);
        _yUSDC.safeApprove(curvePool_, type(uint).max);
        _yUSDT.safeApprove(curvePool_, type(uint).max);
        _yTUSD.safeApprove(curvePool_, type(uint).max);

        emit AddPool(vault_, curvePool_, curveZap_);
    }
    
    function setWhitelistVault(address _vault, bool _status) external onlyOwner {
        isWhitelistedVault[_vault] = _status;
    }

    /// @notice Function to get LP token price
    /// @return LP token price of corresponding Curve pool (18 decimals)
    function getVirtualPrice() external view returns (uint256) {
        return curvePool.get_virtual_price();
    }

    /// @notice Function to check token availability to depositZap()
    /// @param _amount Amount to be swapped (decimals follow _tokenIn)
    /// @param _tokenIn Address to be swapped
    /// @param _tokenOut Address to be received (Stablecoin)
    /// @return Amount out in USD. Token not available if return 0.
    function checkTokenSwapAvailability(uint256 _amount, address _tokenIn, address _tokenOut) external view returns (uint256) {
        address[] memory _path = new address[](3);
        _path[0] = _tokenIn;
        _path[1] = address(_WETH);
        _path[2] = _tokenOut;
        try _sushiRouter.getAmountsOut(_amount, _path) returns (uint256[] memory _amountsOut){
            return _amountsOut[2];
        } catch {
            return 0;
        }
    }
}