pragma solidity ^0.6.12;

interface auctionPriceMgr {
    function getCurPrice(uint256 initPrice, uint256 during) external view returns (uint256);
}

contract LinearDecrease is auctionPriceMgr {

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    modifier auth {
        require(wards[msg.sender] == 1, "LinearDecrease/not-authorized");
        _;
    }

    // --- Data ---
    uint256 public auctionEndTime;  // Seconds after auction start when the price reaches zero [seconds]

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);

    event File(bytes32 indexed what, uint256 data);

    // --- Init ---
    constructor() public {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    function file(bytes32 what, uint256 data) external auth {
        if (what ==  "tau") auctionEndTime = data;
        else revert("LinearDecrease/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Math ---
    uint256 constant RAY = 10 ** 27;
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y;
        require(y == 0 || z / y == x);
        z = z / RAY;
    }

    // duration: seconds since the auction has started
    // cut: cut encodes the percentage to decrease per second.
    function getCurPrice(uint256 initPrice, uint256 duraion) override external view returns (uint256) {
        if (duraion >= auctionEndTime) return 0;
        return rmul(initPrice, mul(auctionEndTime - duraion, RAY) / auctionEndTime);
    }
}

contract StairstepExponentialDecrease is auctionPriceMgr {

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    modifier auth {
        require(wards[msg.sender] == 1, "StairstepExponentialDecrease/not-authorized");
        _;
    }

    // --- Data ---
    uint256 public step; // Length of time between price drops [seconds]
    uint256 public cut;  // Per-step multiplicative factor     [ray]

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);

    event File(bytes32 indexed what, uint256 data);

    // --- Init ---
    // @notice: `cut` and `step` values must be correctly set for
    //     this contract to return a valid price
    constructor() public {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    function file(bytes32 what, uint256 data) external auth {
        if      (what ==  "cut") require((cut = data) <= RAY, "StairstepExponentialDecrease/cut-gt-RAY");
        else if (what == "step") step = data;
        else revert("StairstepExponentialDecrease/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Math ---
    uint256 constant RAY = 10 ** 27;  // a unit
    function rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y;
        require(y == 0 || z / y == x);
        z = z / RAY;
    }
    // optimized version from dss PR #78
    function rpow(uint256 x, uint256 n, uint256 b) internal pure returns (uint256 z) {
        assembly {
            switch n case 0 { z := b }
            default {
                switch x case 0 { z := 0 }
                default {
                    switch mod(n, 2) case 0 { z := b } default { z := x }
                    let half := div(b, 2)  // for rounding.
                    for { n := div(n, 2) } n { n := div(n,2) } {
                        let xx := mul(x, x)
                        if shr(128, x) { revert(0,0) }
                        let xxRound := add(xx, half)
                        if lt(xxRound, xx) { revert(0,0) }
                        x := div(xxRound, b)
                        if mod(n,2) {
                            let zx := mul(z, x)
                            if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
                            let zxRound := add(zx, half)
                            if lt(zxRound, zx) { revert(0,0) }
                            z := div(zxRound, b)
                        }
                    }
                }
            }
        }
    }


    function getCurPrice(uint256 initPrice, uint256 duration) override external view returns (uint256) {
        return rmul(initPrice, rpow(cut, duration, RAY));
    }
}


contract ExponentialDecrease is auctionPriceMgr {

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    modifier auth {
        require(wards[msg.sender] == 1, "ExponentialDecrease/not-authorized");
        _;
    }

    // --- Data ---
    uint256 public multFactor;  // Per-second multiplicative factor [ray]

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);

    event File(bytes32 indexed what, uint256 data);

    constructor() public {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Administration ---
    function file(bytes32 what, uint256 data) external auth {
        if      (what ==  "cut") require((multFactor = data) <= RAY, "ExponentialDecrease/cut-gt-RAY");
        else revert("ExponentialDecrease/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Math ---
    uint256 constant RAY = 10 ** 27;
    function rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y;
        require(y == 0 || z / y == x);
        z = z / RAY;
    }
    // optimized version from dss PR #78
    function rpow(uint256 x, uint256 n, uint256 b) internal pure returns (uint256 z) {
        assembly {
            switch n case 0 { z := b }
            default {
                switch x case 0 { z := 0 }
                default {
                    switch mod(n, 2) case 0 { z := b } default { z := x }
                    let half := div(b, 2)  // for rounding.
                    for { n := div(n, 2) } n { n := div(n,2) } {
                        let xx := mul(x, x)
                        if shr(128, x) { revert(0,0) }
                        let xxRound := add(xx, half)
                        if lt(xxRound, xx) { revert(0,0) }
                        x := div(xxRound, b)
                        if mod(n,2) {
                            let zx := mul(z, x)
                            if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
                            let zxRound := add(zx, half)
                            if lt(zxRound, zx) { revert(0,0) }
                            z := div(zxRound, b)
                        }
                    }
                }
            }
        }
    }

    function getCurPrice(uint256 initPrice, uint256 duration) override external view returns (uint256) {
        return rmul(initPrice, rpow(multFactor, duration, RAY));
    }
}
