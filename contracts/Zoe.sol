//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Zoe {
    // token used to collect and pay
    address public token;

    // monthly percentage yield in thousandths
    uint256 public mpy;

    // leverage percentage in hundredths
    uint256 public leverage;

    // referral comission percentage in hundredths
    uint256 public referralComission;

    mapping(address => uint256) deposits;
    mapping(address => uint256) timestamps;
    mapping(address => bool) active;
    mapping(address => bool) withdrawn;
    mapping(address => bool) deposited;
    mapping(address => uint256) lastCollected;

    constructor(
        address _token,
        uint256 _mpy,
        uint256 _leverage,
        uint256 _referralComission
    ) {
        token = _token;
        mpy = _mpy; // 75 -> 7.5%
        leverage = _leverage; // 20 -> 20%
        referralComission = _referralComission; // 20 -> 20%
    }

    function balance() public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function _transfer(address _to, uint256 _amount) private {
        IERC20(token).transfer(_to, _amount);
    }

    function _collect(address _from, uint256 _amount) private {
        IERC20(token).transferFrom(_from, address(this), _amount);
    }

    function _leveraged(address _addr) private view returns (uint256) {
        return (deposits[_addr] * (100 + leverage)) / 100;
    }

    //
    // REGISTER
    //

    function register(uint256 _amount) public {
        _register(_amount);
    }

    function register(uint256 _amount, address _referral) public {
        // referral must have deposited previously
        require(deposited[_referral], "Referral is not a depositor");

        _register(_amount);

        // transfer 20% to referral address
        _transfer(_referral, (_amount * referralComission) / 100);
    }

    function _register(uint256 _amount) private {
        require(_amount > 0, "Invalid amount");
        require(!active[msg.sender], "Address has already an active deposit");

        _collect(msg.sender, _amount);
        deposits[msg.sender] = _amount;

        deposited[msg.sender] = true;
        active[msg.sender] = true;
        withdrawn[msg.sender] = false;

        timestamps[msg.sender] = block.timestamp;
    }

    // calculate yield based on the timestamp from which time is counted
    function _yield(
        address _addr,
        uint256 _fromTs,
        uint256 _upToTs
    ) private view returns (uint256) {
        // leveraged_deposit * months * 0.075
        return
            (_leveraged(_addr) * ((_upToTs - _fromTs) / 30 days) * mpy) / 1000;
    }

    //
    // COLLECT YIELD
    //

    function collectYield() public returns (uint256 amount) {
        require(active[msg.sender], "Caller has not an active deposit");

        uint256 _lastCollected = lastCollected[msg.sender];
        uint256 _depositTs = timestamps[msg.sender];

        uint256 fromTs;
        uint256 upToTs;

        if (_lastCollected == 0) {
            // first collection
            (fromTs, upToTs) = (_depositTs, block.timestamp);
        } else {
            // following collection
            fromTs = _lastCollected;
            if (block.timestamp - _depositTs > 1080 days) {
                // last collection
                upToTs = _depositTs + 1080 days;
                active[msg.sender] = false;
            } else {
                // mid collections
                upToTs = block.timestamp;
            }
        }

        amount = _yield(msg.sender, fromTs, upToTs);
        _transfer(msg.sender, amount);

        lastCollected[msg.sender] = block.timestamp;
    }

    //
    // WITHDRAW
    //

    // user can withdraw the initial deposit after three years
    function withdraw() public {
        require(block.timestamp - timestamps[msg.sender] >= 1080 days); // ~ 36 months ~ 3 years

        _withdraw(deposits[msg.sender]);
    }

    // user can opt out and withdraw 50% of the deposit after the first year
    function forceWithdrawal() public {
        uint256 _timeDelta = block.timestamp - timestamps[msg.sender];

        require(_timeDelta >= 360 days); // ~ 12 months ~ 1 year
        require(_timeDelta < 1080 days); // ~ 36 months ~ 3 years

        _withdraw(deposits[msg.sender] / 2);
    }

    function _withdraw(uint256 _amount) private {
        require(_amount > 0);
        require(!withdrawn[msg.sender]);

        _transfer(msg.sender, _amount);

        withdrawn[msg.sender] = true;
    }
}
