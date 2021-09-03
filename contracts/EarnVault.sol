// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

interface ICvStake {
    function balanceOf(address _account) external view returns (uint256);
    function withdrawAndUnwrap(uint256 _amount, bool _claim) external;
    function getReward() external returns(bool);
    function extraRewards(uint256 _index) external view returns (address);
    function extraRewardsLength() external view returns (uint256);
}

interface ICvVault {
    function deposit(uint256 _pid, uint256 _amount, bool _stake) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function poolInfo(uint256 _pid) external view returns (address, address, address, address, address, bool);
}

interface ICurveZap {
    function getVirtualPrice() external view returns (uint256);
    function setStrategy(address _strategy) external;
    function swapFees(uint256 _fees) external returns (uint256, address);
    function compound(uint256 _amount) external returns (uint256);
    function emergencyWithdraw(uint256 _amount, address _vault) external;
}

interface ICvRewards {
    function rewardToken() external view returns (address);
}

interface IDAOmine {
    function depositByProxy(address _user, uint256 _pid, uint256 _amount) external;
}

interface ISushiRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint[] memory amounts);
}

interface IWETH is IERC20Upgradeable {
    function withdraw(uint256 _amount) external;
}


contract EarnVault is Initializable, ERC20Upgradeable, OwnableUpgradeable,
        ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public lpToken;
    ICvStake public cvStake;
    
    ISwapRouter private constant _uniRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    ISushiRouter private constant _uniV2Router = ISushiRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    ICvVault private constant _cvVault = ICvVault(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    ISushiRouter private constant _sushiRouter = ISushiRouter(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);
    IWETH private constant _WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20Upgradeable private constant _stkAAVE = IERC20Upgradeable(0x4da27a545c0c5B758a6BA100e3a049001de870f5);
    IERC20Upgradeable private constant _CVX = IERC20Upgradeable(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20Upgradeable private constant _CRV = IERC20Upgradeable(0xD533a949740bb3306d119CC777fa900bA034cd52);

    // uint256 public percKeepInVault;
    // IStrategy public strategy;
    ICurveZap public curveZap;
    address public admin;
    uint256 private constant _DENOMINATOR = 10000;

    // DAOmine
    IDAOmine public daoMine;
    uint256 public daoMinePid;
    uint256 public depositFeePerc;
    uint256 public yieldFeePerc;
    uint256 public pid; // Index for Convex pool
    uint private vaultType;

    // Calculation for fees
    uint256 private _fees;

    // Address to collect fees
    address public treasuryWallet;
    address public communityWallet;
    address public strategist;

    // For smart contract interaction
    mapping(address => uint256) public depositTime;
    mapping(address => bool) public isWhitelisted;

    event Deposit(address indexed caller, uint256 amtDeposit, uint256 sharesMint);
    event Withdraw(address indexed caller, uint256 amtWithdraw, uint256 sharesBurn);
    event Invest(uint256 amtToInvest);
    event RetrievetokenFromStrategy(uint256 _amount);
    event TransferredOutFees(uint256 fees);
    event SetCurveZap(address indexed _curveZap);
    event YieldFee(uint256 yieldFee);
    event Yield(uint amtToCompound, uint lpTokenBal);
    event EmergencyWithdraw(uint _lptokenAmount);

    event SetYieldFeePerc(uint256 indexed percentage);
    event setDepositFeePerc(uint indexed percentage);
    event SetTreasuryWallet(address indexed treasuryWallet);
    event SetCommunityWallet(address indexed communityWallet);
    event SetAdminWallet(address indexed admin);
    event SetStrategistWallet(address indexed strategistWallet);
    event SetDaoMine(address indexed daoMine, uint256 indexed daoMinePid);

    modifier onlyOwnerOrAdmin {
        require(msg.sender == owner() || msg.sender == address(admin), "Only owner or admin");
        _;
    }

    /// @notice Initialize this vault contract
    /// @notice This function can only be execute once (by vault factory contract)
    /// @param _curveZap Address of CurveZap contract
    /// @param _treasuryWallet Address of treasury wallet
    /// @param _communityWallet Address of community wallet
    /// @param _admin Address of admin
    /// @param _strategist Address of strategist
    function initialize(
        string memory _name, string memory _symbol, 
        address _curveZap, address _treasuryWallet, address _communityWallet,
        address _admin, address _strategist, uint _pid, uint _type
    ) external initializer {
        __ERC20_init("DAO Earn", "daoERN");
        __Ownable_init();
        

        curveZap = ICurveZap(_curveZap);
        treasuryWallet = _treasuryWallet;
        communityWallet = _communityWallet;
        admin = _admin;
        strategist = _strategist;
        vaultType = _type;

        yieldFeePerc = 1000; //10%
        depositFeePerc = 1000; //10%

        pid = _pid;

        (address _lpToken, , , address _cvStakeAddr, , ) = _cvVault.poolInfo(_pid);
        lpToken = IERC20Upgradeable(_lpToken);

        lpToken.safeApprove(address(_cvVault), type(uint256).max);
        lpToken.safeApprove(_curveZap, type(uint256).max);
        _CVX.safeApprove(address(_sushiRouter), type(uint256).max);
        _CRV.safeApprove(address(_sushiRouter), type(uint256).max);
        _WETH.approve(address(_sushiRouter), type(uint256).max);

        _WETH.approve(_curveZap, type(uint256).max);

        _stkAAVE.safeApprove(address(_uniRouter), type(uint256).max);

        cvStake = ICvStake(_cvStakeAddr);
    }

    /// @notice Function to deposit token
    /// @param _amount Amount to deposit (18 decimals)
    /// @param _stake True if stake into DAOmine
    /// @return _daoERNBal Amount of minted shares
    function deposit(uint256 _amount, bool _stake) external nonReentrant whenNotPaused returns (uint256 _daoERNBal) {
        require(_amount > 0, "Amount must > 0");
        if (msg.sender != tx.origin) {
            // Smart contract interaction: to prevent deposit & withdraw at same transaction
            depositTime[msg.sender] = block.timestamp;
        }
        
        uint256 _pool = _getAllPool();
        lpToken.safeTransferFrom(msg.sender, address(this), _amount);
        _daoERNBal = _deposit(_amount, msg.sender, _stake, _pool);
    }

    /// @notice Derived function from deposit()
    /// @param _amount Amount to deposit (18 decimals)
    /// @param _account Account to deposit (user address)
    /// @param _stake True if stake into DAOmine
    /// @param _pool All pool before deposit
    /// @return Amount of minted shares
    function _deposit(uint256 _amount, address _account, bool _stake, uint256 _pool) private returns (uint256) {
        uint256 _amtDeposit = _amount; // For event purpose

        if(isWhitelisted[_account] == false) {
            // Calculate deposit fee
            uint256 _fee = _amount * depositFeePerc / _DENOMINATOR;
            _fees = _fees + _fee;
            _amount = _amount - _fee;
        }

        uint256 _totalSupply = totalSupply();
        uint256 _shares = _totalSupply == 0 ? _amount : _amount * _totalSupply / _pool;
        if (_stake) {
            _mint(address(this), _shares);
            daoMine.depositByProxy(_account, daoMinePid, _shares);
        } else {
            _mint(_account, _shares);
        }
        emit Deposit(_account, _amtDeposit, _shares);

        return _shares;
    }

    /// @notice Function to withdraw token
    /// @param _shares Amount of shares to withdraw (18 decimals)
    /// @return _withdrawAmt Amount of token been withdrawn
    function withdraw(uint256 _shares) external nonReentrant returns (uint256 _withdrawAmt) {
        if (msg.sender != tx.origin) {
            // Smart contract interaction: to prevent deposit & withdraw at same transaction
            require(depositTime[msg.sender] + 300 < block.timestamp, "Withdraw within locked period");
        }
        _withdrawAmt = _withdraw(_shares, msg.sender);
    }

    /// @notice Derived function from withdraw()
    /// @param _shares Amount of shares to withdraw (18 decimals)
    /// @param _account Account to withdraw (user address)
    /// @return Amount of token to withdraw (18 decimals)
    function _withdraw(uint256 _shares, address _account) private returns (uint256) {
        require(_shares > 0, "Shares must > 0");
        require(_shares <= balanceOf(_account), "Not enough shares to withdraw");
        
        // Calculate withdraw amount
        uint256 _withdrawAmt = _getAllPool() * _shares / totalSupply(); // 18 decimals
        _burn(_account, _shares);
        if (_withdrawAmt > lpToken.balanceOf(address(this))) {
            // Not enough token in vault, need to get from strategy
            _withdrawAmt = _withdrawFromFarm(_withdrawAmt);
        }

        lpToken.safeTransfer(msg.sender, _withdrawAmt);
        emit Withdraw(_account, _withdrawAmt, _shares);
        return _withdrawAmt;
    }

    function _withdrawFromFarm(uint _amount) internal returns(uint _withdrawAmt){
        uint lpTokenBalanceBefore = lpToken.balanceOf(address(this));
        
        cvStake.withdrawAndUnwrap(_amount, false);

        uint lpTokenBalanceAfter = lpToken.balanceOf(address(this));

        _withdrawAmt =  lpTokenBalanceAfter -  lpTokenBalanceBefore;
    }

    /// @notice Function to invest funds into strategy
    function invest() public onlyOwnerOrAdmin whenNotPaused {
        // Transfer out available fees
        transferOutFees();

        // Calculation for keep portion of token and transfer balance of token to strategy
        uint256 _lpTokenBalance = lpToken.balanceOf(address(this)) ;
        if (_lpTokenBalance > 0) {
            _invest(_lpTokenBalance);
        }
    }

    function investZap(uint _amount) external {
        require(msg.sender == address(curveZap), "Only zap");

        lpToken.safeTransferFrom(address(curveZap), address(this), _amount);

        uint256 _lpTokenBalance = lpToken.balanceOf(address(this)) - _fees;
        if (_lpTokenBalance > 0) {
            _invest(_lpTokenBalance);
        }
    }

    function _invest(uint _amount) internal {
        _cvVault.deposit(pid, _amount, true);
        emit Invest(_amount);

    }

    /// @notice Function to yield farms rewards in strategy
    function yield() external onlyOwnerOrAdmin {
        cvStake.getReward();
        uint256 _amtToCompound = _yield();
        uint256 _lpTokenBal = curveZap.compound(_amtToCompound);
        emit Yield(_amtToCompound, _lpTokenBal);
    }

    /// @notice Derived function from yield()
    function _yield() private returns (uint256) {
        uint256 _CVXBalance = _CVX.balanceOf(address(this));
        if (_CVXBalance > 0) {
            _swap(address(_CVX), address(_WETH), _CVXBalance);
        }
        uint256 _CRVBalance = _CRV.balanceOf(address(this));
        if (_CRVBalance > 0) {
            _swap(address(_CRV), address(_WETH), _CRVBalance);
        }

        if(vaultType == 0) {
            _yieldEarnStrategy();
        } else if (vaultType == 1 ) {
            _yieldAaveStrategy(); 
        } else if (vaultType == 2 ) {
            _yieldUniV2();
        }

        // Split yield fees
        uint256 _WETHBalance = _WETH.balanceOf(address(this));
        uint256 _yieldFee = _WETHBalance - (_WETHBalance * yieldFeePerc / _DENOMINATOR);
        _WETH.withdraw(_yieldFee);

        uint256 _yieldFeeInETH = address(this).balance * 2 / 5;
        (bool _a,) = admin.call{value: _yieldFeeInETH}(""); // 40%
        require(_a, "Fee transfer failed");
        (bool _t,) = communityWallet.call{value: _yieldFeeInETH}(""); // 40%
        require(_t, "Fee transfer failed");
        (bool _s,) = strategist.call{value: (address(this).balance)}(""); // 20%
        require(_s, "Fee transfer failed");

        emit YieldFee(_yieldFee);
        return _WETHBalance - _yieldFee;
    }

    function _yieldEarnStrategy() internal {
                // Dealing with extra reward tokens if available
        if (cvStake.extraRewardsLength() > 0) {
            // Extra reward tokens might more than 1
            for (uint256 _i = 0; _i < cvStake.extraRewardsLength(); _i++) {
                IERC20Upgradeable _extraRewardToken = IERC20Upgradeable(ICvRewards(cvStake.extraRewards(_i)).rewardToken());
                uint256 _extraRewardTokenBalance = _extraRewardToken.balanceOf(address(this));
                if (_extraRewardTokenBalance > 0) {
                    // We do token approval here, because the reward tokens have many kinds and 
                    // might be added in future by Convex
                    if (_extraRewardToken.allowance(address(this), address(_sushiRouter)) == 0) {
                        _extraRewardToken.safeApprove(address(_sushiRouter), type(uint256).max);
                    }
                    _swap(address(_extraRewardToken), address(_WETH), _extraRewardTokenBalance);
                }
            }
        }
    }

    function _yieldAaveStrategy() internal {
        uint256 _stkAAVEBalance = _stkAAVE.balanceOf(address(this));
        if (_stkAAVEBalance > 0) {
            ISwapRouter.ExactInputParams memory params =
                ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(
                        address(_stkAAVE), uint24(10000),
                        0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9,
                        uint24(3000), address(_WETH)
                    ),
                    recipient: msg.sender,
                    deadline: block.timestamp,
                    amountIn: _stkAAVEBalance,
                    amountOutMinimum: 0
                });
            _uniRouter.exactInput(params);
        }
    }

    function _yieldUniV2() internal {
         if (cvStake.extraRewardsLength() > 0) {
            // Extra reward tokens might more than 1
            for (uint256 _i = 0; _i < cvStake.extraRewardsLength(); _i++) {
                IERC20Upgradeable _extraRewardToken = IERC20Upgradeable(ICvRewards(cvStake.extraRewards(_i)).rewardToken());
                uint256 _extraRewardTokenBalance = _extraRewardToken.balanceOf(address(this));
                if (_extraRewardTokenBalance > 0) {
                    // We do token approval here, because the reward tokens have many kinds and 
                    // might be added in future by Convex
                    if (_extraRewardToken.allowance(address(this), address(_uniV2Router)) == 0) {
                        _extraRewardToken.safeApprove(address(_uniV2Router), type(uint256).max);
                    }
                    address[] memory _path = new address[](2);
                    _path[0] = address(_extraRewardToken);
                    _path[1] = address(_WETH);
                    _uniV2Router.swapExactTokensForTokens(_extraRewardTokenBalance, 0, _path, address(this), block.timestamp);
                }
            }
        }
    } 

    /// @notice Swap tokens with Sushi
    /// @param _tokenA Token to be swapped
    /// @param _tokenB Token to be received
    /// @param _amount Amount of token to be swapped
    function _swap(address _tokenA, address _tokenB, uint256 _amount) private {
        address[] memory _path = new address[](2);
        _path[0] = _tokenA;
        _path[1] = _tokenB;
        _sushiRouter.swapExactTokensForTokens(_amount, 0, _path, address(this), block.timestamp);
    }

    // To enable receive ETH from WETH in _yield()
    receive() external payable {}

    /// @notice Function to retrieve token from strategy
    /// @param _amount Amount of token to retrieve (18 decimals)
    function retrievetokenFromStrategy(uint256 _amount) external onlyOwnerOrAdmin {
        _withdrawFromFarm(_amount);
        emit RetrievetokenFromStrategy(_amount);
    }

    /// @notice Function to withdraw all token from strategy and pause deposit & invest function
    function emergencyWithdraw() external onlyOwnerOrAdmin {
        _pause();
        _emergencyWithdraw();
    }

    function _emergencyWithdraw() internal{
        cvStake.withdrawAndUnwrap(cvStake.balanceOf(address(this)), true);
        uint256 _amtToDeposit = _yield();
        curveZap.emergencyWithdraw(_amtToDeposit, address(this));
        uint256 _lpTokenBal = lpToken.balanceOf(address(this));
        
        emit EmergencyWithdraw(_lpTokenBal);
    }

    /// @notice Function to reinvest funds into strategy
    function reinvest() external onlyOwnerOrAdmin whenPaused {
        _unpause();
        invest();
    }

    /// @notice Function to transfer out available network fees
    function transferOutFees() public {
        require(
            msg.sender == address(this) ||
            msg.sender == owner() ||
            msg.sender == admin, "Only authorized caller");
        if (_fees != 0) {
            if (lpToken.balanceOf(address(this)) > _fees) {
                (uint256 _amount, address _tokenAddr) = curveZap.swapFees(_fees); 
                IERC20Upgradeable _token = IERC20Upgradeable(_tokenAddr);
                uint256 _fee = _amount * 2 / 5; // (40%)
                _token.safeTransfer(treasuryWallet, _fee); // 40%
                _token.safeTransfer(communityWallet, _fee); // 40%
                _token.safeTransfer(strategist, _amount - _fee - _fee); // 20%
                emit TransferredOutFees(_fees); // Decimal follow _token
                _fees = 0;
            }
        }
    }

    function setCurveZap(address _curveZap) external onlyOwnerOrAdmin {
        curveZap = ICurveZap(_curveZap);
        _WETH.approve(_curveZap, type(uint256).max);

        emit SetCurveZap(_curveZap);
    }

    ///@notice Function to set deposit fee
    ///@param _depositFeePerc deposit fee percentage => 1000 for 10 %
    function setDepositFee(uint _depositFeePerc) external onlyOwnerOrAdmin {
        depositFeePerc = _depositFeePerc;

        emit setDepositFeePerc(_depositFeePerc);
    }
    ///@notice Function to set yield fee
    ///@param _yieldFeePerc yield fee percentage => 1000 for 10 %
    function setYieldFeePerc(uint _yieldFeePerc) external onlyOwnerOrAdmin {
        yieldFeePerc = _yieldFeePerc;
        emit SetYieldFeePerc(_yieldFeePerc);
    }

    /// @notice Function to get total amount of token(vault+strategy)
    /// @return Total amount of token (18 decimals)
    function _getAllPool() private view returns (uint256) {
        uint256 _vaultPool = lpToken.balanceOf(address(this)) - _fees;
        uint256 _strategyPool = paused() ? 0 : cvStake.balanceOf(address(this));
        return _vaultPool + _strategyPool;
    }

    /// @notice Function to get all pool amount(vault+strategy) in USD
    /// @return All pool in currency(usd, eth, btc) based on vault (18 decimals)
    function getAllPoolInNative() external view returns (uint256) {
        return _getAllPool() * curveZap.getVirtualPrice() / 1e18;
    }

    /// @notice Function to get price per full share (LP token price)
    /// @param _native true for calculate user share in vault's native (ETH, BTC, USD), false for calculate APR
    /// @return Price per full share (18 decimals)
    function getPricePerFullShare(bool _native) external view returns (uint256) {
        uint256 _pricePerFullShare = _getAllPool() * 1e18 / totalSupply();
        return _native == true ? _pricePerFullShare * curveZap.getVirtualPrice() / 1e18 : _pricePerFullShare;
    }
}