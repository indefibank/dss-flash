// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity 0.6.12;

import "./interface/IERC3156FlashLender.sol";
import "./interface/IERC3156FlashBorrower.sol";
import "./interface/IVatStblFlashLender.sol";

interface StblLike {
    function balanceOf(address) external returns (uint256);
    function transferFrom(address, address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
}

interface StblJoinLike {
    function stbl() external view returns (address);
    function vat() external view returns (address);
    function join(address, uint256) external;
    function exit(address, uint256) external;
}

interface VatLike {
    function hope(address) external;
    function stbl(address) external view returns (uint256);
    function live() external view returns (uint256);
    function move(address, address, uint256) external;
    function heal(uint256) external;
    function suck(address, address, uint256) external;
}

contract DssFlash is IERC3156FlashLender, IVatStblFlashLender {

    // --- Auth ---
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    mapping (address => uint256) public wards;
    modifier auth {
        require(wards[msg.sender] == 1, "DssFlash/not-authorized");
        _;
    }

    // --- Data ---
    VatLike     public immutable vat;
    StblJoinLike public immutable stblJoin;
    StblLike     public immutable stbl;

    uint256     public  max;     // Maximum borrowable Stbl  [wad]
    uint256     private locked;  // Reentrancy guard

    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");
    bytes32 public constant CALLBACK_SUCCESS_VAT_STBL = keccak256("VatStblFlashBorrower.onVatStblFlashLoan");

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event FlashLoan(address indexed receiver, address token, uint256 amount, uint256 fee);
    event VatStblFlashLoan(address indexed receiver, uint256 amount, uint256 fee);

    modifier lock {
        require(locked == 0, "DssFlash/reentrancy-guard");
        locked = 1;
        _;
        locked = 0;
    }

    // --- Init ---
    constructor(address stblJoin_) public {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        VatLike vat_ = vat = VatLike(StblJoinLike(stblJoin_).vat());
        stblJoin = StblJoinLike(stblJoin_);
        StblLike stbl_ = stbl = StblLike(StblJoinLike(stblJoin_).stbl());

        vat_.hope(stblJoin_);
        stbl_.approve(stblJoin_, type(uint256).max);
    }

    // --- Math ---
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;
    function _mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Administration ---
    function file(bytes32 what, uint256 data) external auth {
        if (what == "max") {
            // Add an upper limit of 10^27 STBL to avoid breaking technical assumptions of STBL << 2^256 - 1
            require((max = data) <= RAD, "DssFlash/ceiling-too-high");
        }
        else revert("DssFlash/file-unrecognized-param");
        emit File(what, data);
    }

    // --- ERC 3156 Spec ---
    function maxFlashLoan(
        address token
    ) external override view returns (uint256) {
        if (token == address(stbl) && locked == 0) {
            return max;
        } else {
            return 0;
        }
    }

    function flashFee(
        address token,
        uint256 amount
    ) external override view returns (uint256) {
        amount;
        require(token == address(stbl), "DssFlash/token-unsupported");

        return 0;
    }

    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external override lock returns (bool) {
        require(token == address(stbl), "DssFlash/token-unsupported");
        require(amount <= max, "DssFlash/ceiling-exceeded");
        require(vat.live() == 1, "DssFlash/vat-not-live");

        uint256 amt = _mul(amount, RAY);

        vat.suck(address(this), address(this), amt);
        stblJoin.exit(address(receiver), amount);

        emit FlashLoan(address(receiver), token, amount, 0);

        require(
            receiver.onFlashLoan(msg.sender, token, amount, 0, data) == CALLBACK_SUCCESS,
            "DssFlash/callback-failed"
        );

        stbl.transferFrom(address(receiver), address(this), amount);
        stblJoin.join(address(this), amount);
        vat.heal(amt);

        return true;
    }

    // --- Vat Stbl Flash Loan ---
    function vatStblFlashLoan(
        IVatStblFlashBorrower receiver,          // address of conformant IVatStblFlashBorrower
        uint256 amount,                         // amount to flash loan [rad]
        bytes calldata data                     // arbitrary data to pass to the receiver
    ) external override lock returns (bool) {
        require(amount <= _mul(max, RAY), "DssFlash/ceiling-exceeded");
        require(vat.live() == 1, "DssFlash/vat-not-live");

        vat.suck(address(this), address(receiver), amount);

        emit VatStblFlashLoan(address(receiver), amount, 0);

        require(
            receiver.onVatStblFlashLoan(msg.sender, amount, 0, data) == CALLBACK_SUCCESS_VAT_STBL,
            "DssFlash/callback-failed"
        );

        vat.heal(amount);

        return true;
    }
}
