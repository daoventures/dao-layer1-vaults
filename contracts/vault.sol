//SPDX-License-Identifier: MIT
pragma solidity  0.8.7;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

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

interface IUniPair is IERC20Upgradeable{
    function getReserves() external view returns (uint, uint);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IMasterChef {
    function pendingCake(uint pid, address user) external view returns (uint);
    function poolInfo(uint pid) external view returns(address, uint, uint, uint);
    function userInfo(uint pid, address user) external view returns(uint, uint);

    function deposit(uint pid, uint amount) external;
    function withdraw(uint pid, uint amount) external;
}

interface IChainlink {
    function latestAnswer() external view returns (int256);
}

contract BscVault is Initializable, ERC20Upgradeable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    using SafeERC20Upgradeable for IUniPair;

    IERC20Upgradeable public constant CAKE  = IERC20Upgradeable(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
    IERC20Upgradeable public constant WBNB = IERC20Upgradeable(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    IERC20Upgradeable public constant BNB = IERC20Upgradeable(0xa47c8bf37f92aBed4A126BDA807A7b7498661acD);
    IERC20Upgradeable public token0;
    IERC20Upgradeable public token1;
    IUniPair public lpToken;

    IUniRouter public constant PckRouter = IUniRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    IMasterChef public constant MasterChef = IMasterChef(0x73feaa1eE314F8c655E354234017bE2193C9E24E);

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

    uint pid;
    bool feeOn;

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
        uint _pid,
        address _treasury, address _communityWallet, address _strategist, address _admin
    ) external initializer {

        __ERC20_init(_name, _symbol);
        __Ownable_init();

        feeOn = true;
        yieldFee = 2000; //20%
        depositFee = 1000; //10%
        pid = _pid;

        (address _lpToken,,,) = MasterChef.poolInfo(_pid);

        lpToken = IUniPair(_lpToken);
        token0 = IERC20Upgradeable(lpToken.token0());
        token1 = IERC20Upgradeable(lpToken.token1());
        
        treasuryWallet = _treasury;
        communityWallet = _communityWallet;
        strategist = _strategist;
        admin = _admin;
        
        lpToken.safeApprove(address(MasterChef), type(uint).max);
        CAKE.safeApprove(address(PckRouter), type(uint).max);
        token0.approve(address(PckRouter), type(uint).max);
        token1.approve(address(PckRouter), type(uint).max);
    
    }
    
    /**
     *@param _amount amount of lptokens to deposit
    */
    function deposit(uint _amount) external nonReentrant whenNotPaused{
        require(_amount > 0, "Invalid amount");

        uint _pool = getAllPool();
        lpToken.safeTransferFrom(msg.sender, address(this), _amount);

        if(feeOn == true && isWhitelisted[msg.sender] == false) {
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

        uint lpTokenAvailable = lpToken.balanceOf(address(this)) - _fees;
        if(lpTokenAvailable < _amountToWithdraw) {
            MasterChef.withdraw(pid, _amountToWithdraw - lpTokenAvailable );
        }

        _burn(msg.sender, _shares);

        lpToken.safeTransfer(msg.sender, _amountToWithdraw);

        emit Withdraw(msg.sender, _amountToWithdraw, _shares);
        
    }

    function invest() external onlyOwnerOrAdmin whenNotPaused{
        transferFees();
        uint _amt = _invest();

        emit Invest(_amt);
    }

    function _invest() private returns (uint available){
        available = lpToken.balanceOf(address(this)) - _fees;
        if(available > 0) {
            MasterChef.deposit(pid, available);
        }
    }

    ///@notice Withdraws funds staked in mirror to this vault and pauses deposit, yield, invest functions
    function emergencyWithdraw() external onlyOwnerOrAdmin whenNotPaused{ 
        _pause();

        _yield();

        (uint stakedTokens,) = MasterChef.userInfo(pid, address(this));

        if(stakedTokens > 0 ) {
            MasterChef.withdraw(pid, stakedTokens);
        }

        emit EmergencyWithdraw(stakedTokens);
    }

    function setWhitelist(address _addr, bool _value) external onlyOwnerOrAdmin {
        isWhitelisted[_addr] = _value;
        emit SetWhitelist(_addr, _value);
    }
    
    ///@dev Function to enable/disable deposit fee 
    function setFeeStatus(bool _isFeeEnabled) external onlyOwner {
        feeOn = _isFeeEnabled;
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
    function setFee(uint _depositFeePerc, uint _yieldFeePerc) external onlyOwner{
        depositFee = _depositFeePerc;
        yieldFee = _yieldFeePerc;

        emit SetDepositFeePerc(_depositFeePerc);
        emit SetYieldFeePerc(_yieldFeePerc);
    }

    function setTreasuryWallet(address _wallet) external onlyOwner {
        treasuryWallet = _wallet;
        emit SetTreasuryWallet(_wallet);
    }

    function setCommunityWallet(address _wallet) external onlyOwner {
        communityWallet = _wallet;
        emit SetCommunityWallet(_wallet);
    }

    function setStrategistWallet(address _wallet) external onlyOwner {
        strategist = _wallet;
        emit SetStrategistWallet(_wallet);
    }

    function yield() external onlyOwnerOrAdmin whenNotPaused {
        _yield();
    }

    function _yield() private {
        uint cakeBalance = CAKE.balanceOf(address(this));
        
        if(cakeBalance > 0) {
            uint _token0Amount = token0 == CAKE ? cakeBalance /2 : _swap(address(CAKE), address(token0), cakeBalance/2)[1];
            uint _token1Amount = token1 == CAKE ? cakeBalance /2 :  _swap(address(CAKE), address(token1), cakeBalance/2)[1];

            (,,uint lpTokens) = PckRouter.addLiquidity(address(token0), address(token1), _token0Amount, _token1Amount, 0, 0, address(this), block.timestamp);

            uint fee = lpTokens * yieldFee / DENOMINATOR; //yield fee
            _fees += fee;

            _invest();

            address[] memory path = new address[](2);
            path[0] = address(CAKE);
            path[1] = address(WBNB);

            uint priceInBNB = PckRouter.getAmountsOut(1e18, path)[1];

            emit Yield(cakeBalance * priceInBNB);
            emit YieldFee(fee * priceInBNB);
        }
    }

    function _swap(address _tokenA, address _tokenB, uint _amt) private returns (uint[] memory amounts){
        address[] memory path = new address[](2);

        path[0] = address(_tokenA);
        path[1] = address(_tokenB);

        amounts = PckRouter.swapExactTokensForTokens(_amt, 0, path, address(this), block.timestamp);
    }

    ///@notice transfers out fees from vault
    function transferFees() public  onlyOwnerOrAdmin {
        if(_fees > 0) {
            uint feeSplit = _fees * 2 / 5;
            lpToken.safeTransfer(treasuryWallet, feeSplit);
            lpToken.safeTransfer(communityWallet, feeSplit);
            lpToken.safeTransfer(strategist, _fees - (feeSplit + feeSplit));

            _fees = 0;
        }
    }

    function getAllPool() public view returns (uint ) {
        (uint stakedTokens,) = MasterChef.userInfo(pid, address(this));
        return lpToken.balanceOf(address(this)) + stakedTokens - _fees;
    }
}