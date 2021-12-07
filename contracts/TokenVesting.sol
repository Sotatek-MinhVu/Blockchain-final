// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


import "./libraries/Ownable.sol";
import "./libraries/ReentrancyGuard.sol";
import "./libraries/SafeMath.sol";
import "./interfaces/IERC20.sol";
import "./utils/SafeERC20.sol";

/**
 * @title TokenVesting
 */

 contract TokenVesting is Ownable, ReentrancyGuard{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant PRIVATE = keccak256("PRIVATE");
    bytes32 public constant PUBLIC = keccak256("PUBLIC");
    bytes32 public constant INVESTOR = keccak256("INVESTOR");


    struct ScheduleTime {

      // cliff period in seconds
      uint256 cliff;
      // duration of the vesting period in seconds
      uint256 duration;
    }

    mapping(bytes32 => ScheduleTime) public scheduleTimes;
    mapping (address => uint256) private _balances;

    struct VestingSchedule{
      bool initialized;
      // beneficiary of tokens after they are released
      address  beneficiary;
      // start time of the vesting period
      uint256  start;
      // duration of the vesting period in seconds
      uint256  duration;
      // whether or not the vesting is revocable
      bool  revocable;
      // total amount of tokens to be released at the end of the vesting
      uint256 amountTotal;
      // amount of tokens released
      uint256  released;
      // whether or not the vesting has been revoked
      bool revoked;
    }

    // address of the ERC20 token
    IERC20 private _token;

    mapping(bytes32 => VestingSchedule) private vestingSchedules;
    uint256 private vestingSchedulesTotalAmount;

    event Released(uint256 amount);
    event Transfer(address, address recipient, uint256 amount);
    event Revoked();


    /**
    * @dev Creates a vesting contract.
    * @param token_ address of the ERC20 token contract
    */
    constructor(address token_) {
        require(token_ != address(0x0));
        _token = IERC20(token_);
    }

    /**
    * @dev Create schedule time for team.
    */
    function setScheduleTime(bytes32 team, uint32 cliff, uint32 duration ) public onlyOwner{
      scheduleTimes[team] = ScheduleTime(cliff, duration);
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    /**
    * @dev modifier check wallet not in cliff duration.
    */
    modifier checkWalletNotInCliffDuration(address _beneficiary) {
        require(getVestingScheduleByAddress(_beneficiary).start < block.timestamp, "User in cliff duration");
        _;
    }

    /**
    * @notice Send vested amount of tokens.
    * @param recipient address of user vesting 
    * @param amount the amount token
    */
    function transferVestingToken(address recipient, uint256 amount)
    public
    payable
    nonReentrant
    checkWalletNotInCliffDuration(msg.sender)
    checkWalletNotInCliffDuration(recipient)
    {
        require(_computeReleasableAmount(getVestingScheduleByAddress(msg.sender)) > amount, "amount token unlock not enough");
        getVestingScheduleByAddress(msg.sender).released = getVestingScheduleByAddress(msg.sender).released.add(amount);
        _balances[recipient] = _balances[recipient].add(amount);
        _token.safeTransfer(recipient, amount);

        emit Transfer(msg.sender, recipient, amount);
    }

    /**
    * @notice burn tokens.
    */
    function burn(uint256 amount)
    public
    payable
    nonReentrant
    {
        uint256 amountburn = _balances[msg.sender];
        require(amountburn > amount, "User not token");
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        _token.safeTransferFrom(msg.sender, address(this), amount);
        emit Transfer(msg.sender, address(this), amount);

    }


    /**
    * @notice Returns the vesting schedule information for a given holder and index.
    * @return the vesting schedule structure information
    */
    function getVestingScheduleByAddress(address _beneficiary)
    internal
    view
    returns(VestingSchedule memory){
        return vestingSchedules[computeVestingScheduleIdForAddress(_beneficiary)];
    }

    /**
    * @notice Returns token agranted amount of beneficiary.
    * @return the total agranted amount of beneficiary
    */
    function getTotalAgrantedAmountOfUserByAddress(address _beneficiary)
    external
    view
    returns(uint256){
        return vestingSchedules[computeVestingScheduleIdForAddress(_beneficiary)].amountTotal;
    }

    /**
    * @notice Returns token unlocked amount of beneficiary.
    * @return the total unlocked amount of beneficiary
    */
    function getUnlockAmountOfBeneficiaryByAddress(address _beneficiary)
    external
    view
    returns(uint256){
        VestingSchedule storage vestinSchedule = vestingSchedules[computeVestingScheduleIdForAddress(_beneficiary)];
        return _computeUnlockAmount(vestinSchedule);
    }

    /**
    * @notice Returns token locked amount of beneficiary.
    * @return the total locked amount of beneficiary
    */
    function getLockedAmountOfBeneficiaryByAddress(address _beneficiary)
    external
    view
    returns(uint256){
        VestingSchedule storage vestinSchedule = vestingSchedules[computeVestingScheduleIdForAddress(_beneficiary)];
        return _computelockAmount(vestinSchedule);
    }

    /**
    * @notice Returns the total amount of vesting schedules.
    * @return the total amount of vesting schedules
    */
    function getVestingSchedulesTotalAmount()
    external
    view
    returns(uint256){
        return vestingSchedulesTotalAmount;
    }

    /**
    * @notice Creates a new vesting schedule for a beneficiary.
    * @param _beneficiary address of the beneficiary to whom vested tokens are transferred
    * @param _team team of the beneficiary
    * @param _revocable whether the vesting is revocable or not
    * @param _amount total amount of tokens to be released at the end of the vesting
    */
    function createVestingSchedule(
        address _beneficiary,
        bytes32 _team,
        bool _revocable,
        uint256 _amount
    ) public onlyOwner
        {
        require(
            getWithdrawableAmount() >= _amount,
            "TokenVesting: cannot create vesting schedule because not sufficient tokens"
        );
        require(_amount > 0, "TokenVesting: amount must be > 0");
        bytes32 vestingKey = computeVestingScheduleIdForAddress(_beneficiary);
        uint256 start = block.timestamp.add(scheduleTimes[_team].cliff);
        uint256 duration = scheduleTimes[_team].duration;
        vestingSchedules[vestingKey] = VestingSchedule(
            true,
            _beneficiary,
            start,
            duration,
            _revocable,
            _amount,
            0,
            false
        );
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount.add(_amount);
    }

    /**
    * @dev Computes the vesting schedule identifier for an address.
    */
    function computeVestingScheduleIdForAddress(address _beneficiary)
        internal
        pure
        returns(bytes32){
        return keccak256(abi.encodePacked(_beneficiary));
    }

    /**
    * @dev Computes the unlock amount of tokens for a vesting schedule.
    * @return the amount of unlock tokens
    */
    function _computeUnlockAmount(VestingSchedule memory vestingSchedule)
    internal
    view
    returns(uint256){
        uint256 currentTime = getCurrentTime();
        if ((currentTime < vestingSchedule.start) || vestingSchedule.revoked == true) {
            return 0;
        } else if (currentTime >= vestingSchedule.start.add(vestingSchedule.duration)) {
            return vestingSchedule.amountTotal;
        } else {
            uint256 vestedSeconds = currentTime.sub(vestingSchedule.start);
            uint256 vestedUnlockAmount = vestingSchedule.amountTotal.mul(vestedSeconds).div(vestingSchedule.duration);
            return vestedUnlockAmount;
        }
    }

    /**
    * @dev Computes the lock amount of tokens for a vesting schedule.
    * @return the amount of lock tokens
    */
    function _computelockAmount(VestingSchedule memory vestingSchedule)
    internal
    view
    returns(uint256){
        uint256 vestedLockAmount = vestingSchedule.amountTotal.sub(_computeUnlockAmount(vestingSchedule));
        return vestedLockAmount;
    }

    /**
    * @dev Computes the releasable amount of tokens for a vesting schedule.
    * @return the amount of releasable tokens
    */
    function _computeReleasableAmount(VestingSchedule memory vestingSchedule)
    internal
    view
    returns(uint256){
        uint256 vestedAmount = _computeUnlockAmount(vestingSchedule).sub(vestingSchedule.released);
        return vestedAmount;
    }

    function getCurrentTime()
        internal
        virtual
        view
        returns(uint256){
        return block.timestamp;
    }

    /**
    * @dev Returns the amount of tokens that can be withdrawn by the owner.
    * @return the amount of tokens
    */
    function getWithdrawableAmount()
        internal
        view
        returns(uint256){
        return _token.totalSupply().sub(vestingSchedulesTotalAmount);
    }

    /**
    * @dev Get balances token
    */

    function getBalanceToken() public view returns(uint256) { 
      return _token.balanceOf(address(this));
    }

 }