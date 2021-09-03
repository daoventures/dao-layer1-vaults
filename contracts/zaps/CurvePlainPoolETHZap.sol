// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ICurvePool {
    function add_liquidity(uint256[2] memory _amounts, uint256 _amountOutMin) external payable returns (uint256);
    function remove_liquidity_one_coin(uint256 _amount, int128 _index, uint256 _amountOutMin) external returns (uint256);
    function get_virtual_price() external view returns (uint256);
    function coins(uint256 _index) external view returns (address);
}

interface IEarnVault {
    function lpToken() external view returns (address);
    function investZap(uint256 _amount) external;
}

interface ISushiRouter {
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint[] memory amounts);
    function getAmountsOut(uint256 amountIn, address[] memory path) external view returns (uint[] memory amounts);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 _amount) external;
}

contract CurvePlainPoolETHZap is Ownable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    struct PoolInfo {
        ICurvePool curvePool;
        IERC20 baseCoin;
    }
    mapping(address => PoolInfo) public poolInfos;
    mapping(address => bool) public isWhitelistedVault;

    ISushiRouter private constant _sushiRouter = ISushiRouter(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    IWETH private constant _WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

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

    /// @notice Function to receive ETH by this contract
    receive() external payable {}


    /// @notice Function to swap fees from vault contract (and transfer back to vault contract)
    /// @param _amount Amount of LP token to be swapped (18 decimals)
    /// @return Amount and address of coin to receive (amount follow decimal of coin)
    function swapFees(uint256 _amount) external returns (uint256, address) {
        PoolInfo memory _poolInfo = poolInfos[msg.sender];
        require(address(_poolInfo.curvePool) != address(0), "Only authorized vault");
        IERC20(IEarnVault(msg.sender).lpToken()).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _coinAmount = _poolInfo.curvePool.remove_liquidity_one_coin(_amount, 0, 0);
        _WETH.deposit{value: address(this).balance}();
        _coinAmount = _WETH.balanceOf(address(this));
        _WETH.safeTransfer(msg.sender, _coinAmount);
        emit SwapFees(_amount, _coinAmount, address(_WETH));
        return (_coinAmount, address(_WETH));
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
        _WETH.safeTransferFrom(_vault, address(this), _amount);
        _WETH.withdraw(_amount);
        uint256[2] memory _amounts = [_amount, 0];
        _lpTokenBal = _poolInfo.curvePool.add_liquidity{value: address(this).balance}(_amounts, 0);
        emit AddLiquidity(_amount, _vault, address(_WETH), _lpTokenBal);
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

    /// @notice Function to add new Curve pool
    /// @param vault_ Address of corresponding vault contract
    /// @param curvePool_ Address of Curve metapool contract
    function addPool(address vault_, address curvePool_) external onlyOwner {
        ICurvePool _curvePool = ICurvePool(curvePool_);
        IEarnVault _vault = IEarnVault(vault_);
        IERC20 _lpToken = IERC20(_vault.lpToken());
        IERC20 _baseCoin = IERC20(_curvePool.coins(1)); // Base coin is the coin other than ETH in Curve pool
        isWhitelistedVault[vault_] = true;

        _lpToken.safeApprove(vault_, type(uint).max);
        _lpToken.safeApprove(curvePool_, type(uint).max);
        _baseCoin.safeApprove(curvePool_, type(uint).max);

        poolInfos[vault_] = PoolInfo(
            _curvePool,
            _baseCoin
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

    /// @notice Function to check token availability to depositZap(). _tokenOut = WETH
    /// @param _amount Amount to be swapped (decimals follow _tokenIn)
    /// @param _tokenIn Address to be swapped
    /// @return Amount out in BTC. Token not available if return 0.
    function checkTokenSwapAvailability(uint256 _amount, address _tokenIn) external view returns (uint256) {
        address[] memory _path = new address[](2);
        _path[0] = _tokenIn;
        _path[1] = address(_WETH);
        try _sushiRouter.getAmountsOut(_amount, _path) returns (uint256[] memory _amountsOut){
            return _amountsOut[1];
        } catch {
            return 0;
        }
    }
}