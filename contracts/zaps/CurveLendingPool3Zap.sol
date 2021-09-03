// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ICurvePool {
    function coins(uint256 _index) external returns (address);
    function underlying_coins(uint256 _index) external returns (address);
    function add_liquidity(uint256[3] memory _amounts, uint256 _amountOutMin, bool _useUnderlying) external returns (uint256);
    function remove_liquidity_one_coin(uint256 _amount, int128 _index, uint256 _amountOutMin, bool _useUnderlying) external returns (uint256);
    function calc_token_amount(uint256[3] memory _amounts, bool _isDeposit) external returns (uint256);
    function get_virtual_price() external view returns (uint256);
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

contract CurveLendingPool3Zap is Ownable {
    using SafeERC20 for IERC20;

    struct PoolInfo {
        ICurvePool curvePool;
        address[] coins;
        address[] underlying;
    }
    mapping(address => PoolInfo) public poolInfos;
    mapping(address => bool) public isWhitelistedVault;
    

    ISushiRouter private constant _sushiRouter = ISushiRouter(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    IERC20 private constant _WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    event Deposit(address indexed vault, uint256 amount, address indexed coin, uint256 lptokenBal, uint256 daoERNBal, bool stake);
    event Withdraw(address indexed vault, uint256 shares, address indexed coin, uint256 lptokenBal, uint256 coinAmount);
    event SwapFees(uint256 amount, uint256 coinAmount, address indexed coin);
    event Compound(uint256 amount, address indexed vault, uint256 lpTokenBal);
    event AddLiquidity(uint256 amount, address indexed vault, address indexed best, uint256 lpTokenBal);
    event EmergencyWithdraw(uint256 amount, address indexed vault, uint256 lpTokenBal);
    event AddPool(address indexed vault, address indexed curvePool);
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
        PoolInfo memory _poolInfo = poolInfos[msg.sender];
        ICurvePool _curvePool = _poolInfo.curvePool;
        require(address(_curvePool) != address(0), "Only authorized vault");
        IERC20 lpToken = IERC20(IEarnVault(msg.sender).lpToken());
        lpToken.safeTransferFrom(msg.sender, address(this), _amount);
        IERC20 _DAI = IERC20(_poolInfo.underlying[0]);
        uint256 _coinAmount = _curvePool.remove_liquidity_one_coin(_amount, 0, 0, true);
        _DAI.safeTransfer(msg.sender, _coinAmount);
        emit SwapFees(_amount, _coinAmount, address(_DAI));
        return (_coinAmount, address(_DAI));
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
        PoolInfo memory _poolInfo = poolInfos[_vault];
        address[] memory _underlying = _poolInfo.underlying;
        
        _WETH.safeTransferFrom(address(_vault), address(this), _amount);
    
        // Swap WETH to coin which can provide highest LP token return
        address _best = _findCurrentBest(_amount, _vault, address(0));
        address[] memory _path = new address[](2);
        _path[0] = address(_WETH);
        _path[1] = _best;
        uint256[] memory _amountsOut = _sushiRouter.swapExactTokensForTokens(_amount, 0, _path, address(this), block.timestamp);
        // Add coin into Curve pool
        uint256[3] memory _amounts;
        if (_best == address(_underlying[0])) {
            _amounts[0] = _amountsOut[1];
        } else if (_best == address(_underlying[1])) {
            _amounts[1] = _amountsOut[1];
        } else { // address(_underlying[2])
            _amounts[2] = _amountsOut[1];
        }
        _lpTokenBal = _poolInfo.curvePool.add_liquidity(_amounts, 0, true);
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
    /// @param _vault Address of vault contract
    /// @param _token Input token address to be calculate
    /// @return Coin address that provide highest LP token return
    function _findCurrentBest(uint256 _amount, address _vault, address _token) private returns (address) {
        address[] memory _underlying = poolInfos[_vault].underlying;
        // Get estimated amount out of LP token for each input token
        uint256 _amountOut = _calcAmountOut(_amount, _token, _underlying[0], _vault);
        uint256 _amountOut1 = _calcAmountOut(_amount, _token, _underlying[1], _vault);
        uint256 _amountOut2 = _calcAmountOut(_amount, _token, _underlying[2], _vault);
        // Compare for highest LP token out among coin address
        address _best = _underlying[0];
        if (_amountOut1 > _amountOut) {
            _best = _underlying[1];
            _amountOut = _amountOut1;
        }
        if (_amountOut2 > _amountOut) {
            _best = _underlying[2];
        }
        return _best;
    }

    /// @notice Function to calculate amount out of LP token
    /// @param _amount Amount of WETH to be calculate
    /// @param _vault Address of vault contract to retrieve pool
    /// @param _token Input token address to be calculate (for depositZap(), otherwise address(0))
    /// @return Amount out of LP token
    function _calcAmountOut(uint256 _amount, address _token, address _coin, address _vault) private returns (uint256) {
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

        PoolInfo memory _poolInfo = poolInfos[_vault];
        address[] memory _underlying = _poolInfo.underlying;
        uint256[3] memory _amounts;
        if (_coin == address(_underlying[0])) {
            _amounts[0] = _amountOut;
        } else if (_coin == address(_underlying[1])) {
            _amounts[1] = _amountOut;
        } else { // address(_underlying[2])
            _amounts[2] = _amountOut;
        }
        return _poolInfo.curvePool.calc_token_amount(_amounts, true);
    }

    /// @notice Function to add new Curve lending pool (with 3 assets only)
    /// @param vault_ Address of corresponding vault contract
    /// @param curvePool_ Address of Curve lending contract
    function addPool(address vault_, address curvePool_) external onlyOwner {
        IEarnVault _vault = IEarnVault(vault_);
        ICurvePool _curvePool = ICurvePool(curvePool_);
        
        isWhitelistedVault[vault_] = true;
        
        // Here use loop because of stake too deep issue
        address[] memory _coins = new address[](3);
        for (uint256 _i; _i < 3; _i++) {
            address _coin = _curvePool.coins(_i);
            IERC20(_coin).safeApprove(curvePool_, type(uint).max);
            _coins[_i] = _coin;
        }
        address[] memory _underlying = new address[](3);
        for (uint256 _i; _i < 3; _i++) {
            address underlying_ = _curvePool.underlying_coins(_i);
            IERC20(underlying_).safeApprove(curvePool_, type(uint).max);
            _underlying[_i] = underlying_;
        }

        IERC20 _lpToken = IERC20(_vault.lpToken());
        _lpToken.safeApprove(vault_, type(uint).max);

        poolInfos[vault_] = PoolInfo(
            _curvePool,
            _coins,
            _underlying
        );
        emit AddPool(vault_, curvePool_);
    }

    function setWhitelistVault(address _vault, bool _status) external onlyOwner {
        isWhitelistedVault[_vault] = _status;
    }
    
    /// @notice Function to get LP token price
    /// @return LP token price of corresponding Curve pool (18 decimals)
    function getVirtualPrice() external view returns (uint256) {
        return poolInfos[msg.sender].curvePool.get_virtual_price();
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