// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol";

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

interface IChainlink {
    function latestAnswer() external view returns (int256);
}

contract uniVault is ERC20Upgradeable, ReentrancyGuardUpgradeable {

    using SafeMathUpgradeable for uint;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public token0;
    IERC20Upgradeable public token1;
    IERC20Upgradeable public constant WETH = IERC20Upgradeable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); 

    INonfungiblePositionManager public constant nonfungiblePositionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IUniswapV3PoolState public UniswapPool;

    ISwapRouter public constant Router  = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    uint feePerc;
    uint yieldFee;
    uint vaultPositionTokenId;
    uint totalLiquidity;
    uint private _feeToken0;
    uint private _feeToken1;

    uint24 poolFee; // uni v3 pool fee //3000 - 0.3 % fee tier

    int24 lowerTick;
    int24 upperTick;

    address public admin;
    address public treasury;
    address public communityWallet;
    address public strategist;

    mapping(uint => address) positionOwner;

    modifier onlyAdmin {
        require(msg.sender == admin, "only Admin");
        _;
    }

    ///@dev _token0, _token1 should be same as in uniswap pool
    function initialize(IERC20Upgradeable _token0, IERC20Upgradeable _token1, IUniswapV3PoolState _UniswapPool,
        address _admin, address _communityWallet, address _treasury, address _strategist, 
        uint24 _uniPoolFee, int24 _lowerTick, int24 _upperTick) external initializer {
        
        __ERC20_init("name", "symbol"); //TODO change

        token0 = _token0;
        token1 = _token1;
        feePerc = 1000; //10 % 
        yieldFee = 5000; //5%
        poolFee = _uniPoolFee; //10000; //_uniPoolFee; //10000 //3000; //0.3 % fee tier
        lowerTick = _lowerTick;
        upperTick = _upperTick;

        UniswapPool = _UniswapPool;
        admin = _admin;
        treasury = _treasury;
        communityWallet = _communityWallet;
        strategist = _strategist;

        IERC20Upgradeable(token0).approve( address(nonfungiblePositionManager), type(uint).max);
        IERC20Upgradeable(token1).approve( address(nonfungiblePositionManager), type(uint).max);
        _token0.approve(address(Router), type(uint).max);
        _token1.approve(address(Router), type(uint).max);
    }

    function deposit(uint _amount0, uint _amount1) external nonReentrant {
        require(_amount0 > 0 && _amount1 > 0, "amount should be greater than 0");

        token0.safeTransferFrom(msg.sender, address(this), _amount0);
        token1.safeTransferFrom(msg.sender, address(this), _amount1);

        (_amount0, _amount1) = _calcFee(_amount0, _amount1, 0);

        uint _liquidityAdded =_addLiquidity(_amount0, _amount1);
    
        uint _shares;
        if(totalSupply() == 0) {
            _shares = _liquidityAdded;
            totalLiquidity = totalLiquidity.add(_liquidityAdded);
        } else {            
            _shares = _liquidityAdded.mul(totalSupply()).div(totalLiquidity);
            totalLiquidity = totalLiquidity.add(_liquidityAdded);
        }

        _mint(msg.sender, _shares);
    }

    function withdraw(uint _shares) external nonReentrant returns (uint _amount0, uint _amount1){
        require(_shares > 0, "invalid amount");

        uint _liquidity = totalLiquidity.mul (_shares) .div( totalSupply());
        totalLiquidity = totalLiquidity.sub(_liquidity);
        
        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: vaultPositionTokenId,
                liquidity: uint128(_liquidity),
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        //decrease liquidity to collect deposit fee
        (_amount0, _amount1) = nonfungiblePositionManager.decreaseLiquidity(params);

        _collect(_amount0, _amount1);

        _burn(msg.sender, _shares);
        
        if(_amount0 > 0) {
            token0.safeTransfer(msg.sender, _amount0);
        }

        if(_amount1 > 0) {
            token1.safeTransfer(msg.sender, _amount1);
        }

    }

    function yield() external onlyAdmin{ 
        
        (uint _amt0Collected, uint _amt1Collected) = _collect(type(uint128).max, type(uint128).max);
        if(_amt0Collected >0 && _amt1Collected > 0) {
            _calcFee(_amt0Collected, _amt0Collected, 1);
            
            (uint _amt0, uint _amt1 ) = _available();
            uint _liquidityAdded = _addLiquidity(_amt0, _amt1);
            totalLiquidity = totalLiquidity.add(_liquidityAdded);        
            _transferFee();
        }
        
    }

    function changeTicks(int24 _upper, int24 _lower) external onlyAdmin{

        (uint _amt0, uint _amt1) = _decreaseLiquidity(totalLiquidity);

        (_amt0, _amt1) = _collect(_amt0, _amt1);

        lowerTick = _lower;
        upperTick = _upper;
        
        vaultPositionTokenId = 0;
        uint _liquidity = _addLiquidity(_amt0, _amt1);
         
        totalLiquidity = _liquidity;
    }

    function setTreasury(address _treasury) external onlyAdmin {
        treasury = _treasury;
    }

    function setCommunityWallet(address _communityWallet) external onlyAdmin {
        communityWallet = _communityWallet;
    }

    function setStrategist(address _strategist) external onlyAdmin {
        strategist = _strategist;
    }

    function setAdmin(address _admin) external onlyAdmin {
        admin = _admin;
    }

    function setFee(uint _feePerc, uint _yieldFee) external onlyAdmin {
        feePerc = _feePerc; //deposit fee
        yieldFee =_yieldFee; //yield Fee
    }

    function transferFee() external onlyAdmin{
        _transferFee();
    }

    function _swap(address _source, address _target, uint _sourceAmount) internal returns (uint _outAmount) {
        ISwapRouter.ExactInputSingleParams memory param = ISwapRouter.ExactInputSingleParams({
            tokenIn: _source, 
            tokenOut: _target, 
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _sourceAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        _outAmount = Router.exactInputSingle(param);
    }

    function _transferFee() internal {
        uint _feeInETH;

        if(token0 == WETH) {
            uint _out = _swap(address(token1), address(token0), _feeToken1);
            _feeInETH = _out.add(_feeToken0);
        } else {
            uint _out = _swap(address(token0), address(token1), _feeToken0);
            _feeInETH = _out.add(_feeToken1);
        }


        if(_feeInETH > 0) {
            uint _feeSplit = _feeInETH.mul(2).div(5);

            WETH.safeTransfer(treasury, _feeSplit);
            WETH.safeTransfer(communityWallet, _feeSplit);
            WETH.safeTransfer(strategist, _feeInETH.sub(_feeSplit).sub(_feeSplit));
            
        }

    }

    function _addLiquidity(uint _amount0, uint _amount1) internal returns (uint _liquidity){
        
        if(vaultPositionTokenId == 0) {
            // add liquidity for the first time
            INonfungiblePositionManager.MintParams memory params =
                INonfungiblePositionManager.MintParams({
                    token0: address(token0),
                    token1: address(token1),
                    fee: poolFee,
                    tickLower: lowerTick, 
                    tickUpper: upperTick, 
                    amount0Desired: _amount0,
                    amount1Desired: _amount1,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: block.timestamp
                });

            
            (uint _tokenId, uint liquidity, ,) = nonfungiblePositionManager.mint(params);

            vaultPositionTokenId = _tokenId;

            return liquidity;

        } else {

            INonfungiblePositionManager.IncreaseLiquidityParams memory params =
                INonfungiblePositionManager.IncreaseLiquidityParams({
                    tokenId: vaultPositionTokenId,
                    amount0Desired: _amount0,
                    amount1Desired: _amount1,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                });

            (uint liquidity, , ) = nonfungiblePositionManager.increaseLiquidity(params);

            return liquidity;
        }
    }

    function _decreaseLiquidity(uint _liquidity) internal returns (uint _amt0, uint _amt1){
         INonfungiblePositionManager.DecreaseLiquidityParams memory params =
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: vaultPositionTokenId,
                liquidity: uint128(_liquidity),
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        //decrease liquidity to collect deposit fee
        (_amt0, _amt1) = nonfungiblePositionManager.decreaseLiquidity(params);
    }

    function _collect(uint _amount0, uint _amount1) internal returns (uint _amt0Collected, uint _amt1Collected){

        INonfungiblePositionManager.CollectParams memory collectParams =
            INonfungiblePositionManager.CollectParams({
                tokenId: vaultPositionTokenId,
                recipient: address(this),
                amount0Max: uint128(_amount0),
                amount1Max: uint128(_amount1)
            });

        (_amt0Collected, _amt1Collected) =  nonfungiblePositionManager.collect(collectParams);
    }

    //type == 0 for depositFee
    function _calcFee(uint _amount0, uint _amount1, uint _type) internal returns (uint _amt0AfterFee, uint _amt1AfterFee){
        //both tokens added as liquidity
        uint _half = _type == 0 ? feePerc/2 : yieldFee/2;
        uint _fee0 = _amount0.mul(_half).div(10000);
        uint _fee1 = _amount1.mul(_half).div(10000);
        
        _feeToken0 = _feeToken0.add(_fee0);
        _feeToken1 = _feeToken1.add(_fee1);

        _amt0AfterFee = _amount0 .sub (_fee0);
        _amt1AfterFee = _amount1 .sub (_fee1);

    }

    function _available() internal view returns (uint _amt0, uint _amt1) {
        _amt0 = token0.balanceOf(address(this)).sub(_feeToken0);
        _amt1 = token1.balanceOf(address(this)).sub(_feeToken1);
    }

    function getAllPool() public view returns (uint _amount0, uint _amount1) {
        (,,,,,int24 _tickLower, int24 _tickHigher, uint128 _liquidity, ,,,) =  nonfungiblePositionManager.positions(vaultPositionTokenId);
        
        (uint160 sqrtRatioX96,,,,,,) = UniswapPool.slot0(); //Current price // (sqrt(token1/token0))

        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(_tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(_tickHigher);
        

        (_amount0, _amount1) = LiquidityAmounts.getAmountsForLiquidity(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, _liquidity);
        
    }
    function getAllPoolInETH() public view returns (uint _valueInETH) {
        (uint _amount0, uint _amount1) = getAllPool();
        _valueInETH = token0 == WETH ? _amount0.mul(2) : _amount1.mul(2); //since the value(in USD) of _amount1 and _amount0 are equal
    }

    function getAllPoolInUSD() public view returns (uint) {
        uint ETHPriceInUSD = uint(IChainlink(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419).latestAnswer()).mul(1e10); // 8 decimals
        return getAllPoolInETH() .mul (ETHPriceInUSD) .div (1e18);
    }
    
    function getPricePerFullShare(bool inUSD) external view returns (uint) {
        uint _totalSupply = totalSupply();
        if (_totalSupply == 0) return 0;
        return inUSD == true ?
            getAllPoolInUSD() .mul (1e18) .div (_totalSupply) :
            getAllPoolInETH() .mul (1e18) .div (_totalSupply);
    }
    

}