//SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";


interface ILpPool is IERC20Upgradeable{
    function earned(address _account) external view returns (uint);
    function lpt() external view returns (address);
    
    
    function getReward() external ;
    function stake(uint _amount) external ;
    function withdraw(uint _amount) external ;
}

interface IUniRouter {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity) ;

    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);

}

interface IUniPair {
    function getReserves() external view returns (uint, uint);
    function totalSupply() external view returns (uint);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IChainlink {
    function latestAnswer() external view returns (int256);
}


contract MirrorVault is Initializable, ERC20Upgradeable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public constant Mir  = IERC20Upgradeable(0x09a3EcAFa817268f77BE1283176B946C4ff2E608);
    IERC20Upgradeable public constant WETH = IERC20Upgradeable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20Upgradeable public constant UST = IERC20Upgradeable(0xa47c8bf37f92aBed4A126BDA807A7b7498661acD);
    IERC20Upgradeable public lpToken;
    IUniPair public pair;
    ILpPool public lpPool;

    IUniRouter public constant router = IUniRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    uint private _fees;
    uint private constant DENOMINATOR = 10000;
    uint public yieldFee;
    uint public depositFee;

    address public treasuryWallet;
    address public communityWallet;
    address public strategist;
    address public admin;
    address private mAsset;

    mapping(address => bool) public isWhitelisted;
    mapping(address => uint) private depositedBlock;

    event Deposit(address _user, uint _amount, uint _shares);
    event EmergencyWithdraw(uint _amount);
    event Invest(uint _amount);
    event SetAdmin(address _oldAdmin, address _newAdmin);
    event SetDepositFeePerc(uint _fee);
    event SetYieldFeePerc(uint _fee);
    event SetCommunityWallet(address _wallet);
    event SetStrategistWallet(address _wallet);
    event SetTreasuryWallet(address _wallet);
    event SetWhitelist(address, bool);
    event Withdraw(address _user, uint _amount, uint _shares);
    event YieldFee(uint _amount);
    event Yield(uint _amount);

    modifier onlyOwnerOrAdmin {
        require(msg.sender == owner() || msg.sender == admin, "Only owner or admin");
        _;
    }


    function initialize(string memory _name, string memory _symbol, 
        ILpPool _lpPool, address _mAsset, address _lpToken,
        address _treasury, address _communityWallet, address _strategist, address _admin
    ) external initializer {

        __ERC20_init(_name, _symbol);
        __Ownable_init();

        yieldFee = 2000; //20%
        depositFee = 1000; //10%
        
        lpPool = _lpPool;
        lpToken = IERC20Upgradeable(_lpToken);

        require(_lpToken == lpPool.lpt(), "lptoken mismatch");
        pair = IUniPair(_lpToken);

        mAsset = _mAsset;
        admin = _admin;

        treasuryWallet = _treasury;
        communityWallet = _communityWallet;
        strategist = _strategist;

        lpToken.safeApprove(address(_lpPool), type(uint).max);
        Mir.safeApprove(address(router), type(uint).max);
        UST.safeApprove(address(router), type(uint).max);
        IERC20Upgradeable(mAsset).approve(address(router), type(uint).max);
        
    }
    /**
     *@param _amount amount of lptokens to deposit
    */
    function deposit(uint _amount) external nonReentrant whenNotPaused{
        require(_amount > 0, "Invalid amount");

        uint _pool = getAllPool();
        lpToken.safeTransferFrom(msg.sender, address(this), _amount);

        if(isWhitelisted[msg.sender] == false) {
            uint fees = _amount * depositFee / DENOMINATOR;
            _amount = _amount - fees;

            _fees += fees;
        }

        depositedBlock[msg.sender] = block.number;

        uint _totalSupply = totalSupply();
        uint _shares = _totalSupply == 0 ? _amount : _amount * _totalSupply / _pool;

        _mint(msg.sender, _shares);
        emit Deposit(msg.sender, _amount, _shares);
    }

    /**
     *@param _shares amount of shares to burn
    */
    function withdraw(uint _shares) external nonReentrant{
        require(_shares > 0, "Invalid Amount");
        require(balanceOf(msg.sender) >= _shares, "Not enough balance");
        require(depositedBlock[msg.sender] != block.number, "Withdraw within same block");


        uint _amountToWithdraw = getAllPool() * _shares / totalSupply(); 

        if(lpToken.balanceOf(address(this)) - _fees < _amountToWithdraw) {
            lpPool.withdraw(_amountToWithdraw);
        }

        _burn(msg.sender, _shares);

        lpToken.safeTransfer(msg.sender, _amountToWithdraw);

        emit Withdraw(msg.sender, _amountToWithdraw, _shares);
        
    }

    function invest() external onlyOwnerOrAdmin whenNotPaused {
        _transferFees();
        uint _amount = _invest();

        emit Invest(_amount);
    }

    function _invest() private returns (uint){
        uint lpTokenBalance = lpToken.balanceOf(address(this));
        if(lpTokenBalance > _fees) {
            lpPool.stake(lpTokenBalance - _fees);
            
            return lpTokenBalance - _fees;
        }

        return 0;
    }

    function yield() external onlyOwnerOrAdmin whenNotPaused { 
        _yield();
    }

    function _yield() private {
        uint rewardMir = lpPool.earned(address(this));

        if(rewardMir > 0) {

            lpPool.getReward();

            uint outAmount = mAsset != address(Mir) ? _swap(address(Mir), mAsset, rewardMir /2) : rewardMir /2;
            uint outAmount1 = _swap(address(Mir), address(UST), rewardMir /2);

            (,,uint lpTokenAmount) = router. addLiquidity(address(mAsset), address(UST), outAmount, outAmount1, 0, 0, address(this), block.timestamp);

            uint fee = lpTokenAmount * yieldFee / DENOMINATOR;
            _fees += fee;

            _invest();

            address[] memory path = new address[](2);
            path[0] = address(Mir);
            path[1] = address(WETH);
            
            uint priceInETH = router.getAmountsOut(1e18, path)[1];

            emit Yield(rewardMir * priceInETH);
            emit YieldFee(fee * priceInETH);

        }
    }
    ///@notice Withdraws funds staked in mirror to this vault and pauses deposit, yield, invest functions
    function emergencyWithdraw() external onlyOwnerOrAdmin whenNotPaused{ 
        _pause();

        _yield();

        uint stakedTokens = lpPool.balanceOf(address(this));

        if(stakedTokens > 0 ) {
            lpPool.withdraw(stakedTokens);
        }

        emit EmergencyWithdraw(stakedTokens);
    }

    function setWhitelist(address _addr, bool _value) external onlyOwnerOrAdmin {
        isWhitelisted[_addr] = _value;
        emit SetWhitelist(_addr, _value);
    }

    ///@notice Unpauses deposit, yield, invest functions, and invests funds.
    function reInvest() external onlyOwnerOrAdmin whenPaused {
        _invest();
        _unpause();
    }

    function setAdmin(address _newAdmin) external onlyOwner{
        address oldAdmin = admin;
        admin = _newAdmin;

        emit SetAdmin(oldAdmin, _newAdmin);
    }
    ///@notice Function to set deposit and yield fee
    ///@param _depositFeePerc deposit fee percentage. 1000 for 10%
    ///@param _yieldFeePerc deposit fee percentage. 2000 for 20%
    function setFee(uint _depositFeePerc, uint _yieldFeePerc) external onlyOwnerOrAdmin{
        depositFee = _depositFeePerc;
        yieldFee = _yieldFeePerc;

        emit SetDepositFeePerc(_depositFeePerc);
        emit SetYieldFeePerc(_yieldFeePerc);
    }

    function setTreasuryWallet(address _wallet) external onlyOwnerOrAdmin {
        treasuryWallet = _wallet;
        emit SetTreasuryWallet(_wallet);
    }

    function setCommunityWallet(address _wallet) external onlyOwnerOrAdmin {
        communityWallet = _wallet;
        emit SetCommunityWallet(_wallet);
    }

    function setStrategistWallet(address _wallet) external onlyOwnerOrAdmin {
        strategist = _wallet;
        emit SetStrategistWallet(_wallet);
    }

    function _swap(address _token0, address _token1, uint _amount) private returns (uint _outAmount){

        //Mir -> mAsset pair doesn;t exists
        if(_token1 == mAsset) { 
            address[] memory path = new address[](3);
            path[0] = _token0;
            path[1] = address(UST);
            path[2] = _token1;

            _outAmount = router.swapExactTokensForTokens(_amount, 0, path, address(this), block.timestamp)[2];
        } else {
            address[] memory path = new address[](2);
            path[0] = _token0;
            path[1] = _token1;


            _outAmount = router.swapExactTokensForTokens(_amount, 0, path, address(this), block.timestamp)[1];
        }

    }

    ///@notice transfers out fees from vault
    function transferFees() external onlyOwnerOrAdmin { 
        _transferFees();
    }

    function _transferFees() private {
        uint feeSplit = _fees * 2 / 5;

        lpToken.safeTransfer(treasuryWallet, feeSplit);
        lpToken.safeTransfer(communityWallet, feeSplit);
        lpToken.safeTransfer(strategist, _fees - (feeSplit + feeSplit));

        _fees = 0;
    }

    ///@return _pool Returns the total lp tokens in vault and staked in mirror
    function getAllPool() public view returns (uint _pool) {
        _pool = lpToken.balanceOf(address(this)) + 
            lpPool.balanceOf(address(this)) - 
            _fees;
    }

    function _getReserves() private view returns (uint _mAssetReserve, uint _ustReserve) {
        (_mAssetReserve, _ustReserve) = pair.getReserves();
         
        if(pair.token0() != mAsset) {
            (_mAssetReserve, _ustReserve) = (_ustReserve, _mAssetReserve);
        }
    }

    ///@return Returns the value of lpToken in ETH (18 decimals)
    function getAllPoolInETH() public view returns (uint) {

        uint _pool = getAllPool();
        address[] memory path = new address[](2);
        path[0] = address(mAsset);
        path[1] = address(UST);

        uint mAssetPriceInUST = router.getAmountsOut(1e18, path)[1];

        (uint reservemAsset, uint reserveUST) = _getReserves();

        uint _totalSupply = pair.totalSupply();
        uint totalmAsset = _pool * reservemAsset / _totalSupply;
        uint totalUST = _pool * reserveUST / _totalSupply;

        uint valueInUST = (totalmAsset * mAssetPriceInUST / 1e18) + totalUST;

        path[0] = address(UST);
        path[1] = address(WETH);

        return router.getAmountsOut(valueInUST, path)[1];
    }
    
    ///@return Returns the value of lpToken in USD (8 decimals)
    function getAllPoolInUSD() public view returns (uint) {
        uint ETHPriceInUSD = uint(IChainlink(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419).latestAnswer()); // 8 decimals
        return getAllPoolInETH() * ETHPriceInUSD / 1e8;
    }

    function getPricePerFullShare(bool inUSD) public view returns (uint) {
        uint _totalSupply = totalSupply();
        if (_totalSupply == 0) return 0;
        return inUSD == true ?
            getAllPoolInUSD() * 1e18 / _totalSupply :
            getAllPool() * 1e18 / _totalSupply;
    }

}