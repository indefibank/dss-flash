# dss-flash
![Build Status](https://github.com/indefibank/dss-flash/actions/workflows/.github/workflows/tests.yaml/badge.svg?branch=master)

This module conforms to the [ERC3156 spec](https://eips.ethereum.org/EIPS/eip-3156) so please read this over to get a firm idea of the considerations/risks.

## Usage

Since this module conforms to the ERC3156 spec, you can just use the reference borrower implementation from the spec:

```
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IERC3156FlashBorrower.sol";
import "./interfaces/IERC3156FlashLender.sol";

contract FlashBorrower is IERC3156FlashBorrower {
    enum Action {NORMAL, OTHER}

    IERC3156FlashLender lender;

    constructor (
        IERC3156FlashLender lender_
    ) public {
        lender = lender_;
    }

    /// @dev ERC-3156 Flash loan callback
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        require(
            msg.sender == address(lender),
            "FlashBorrower: Untrusted lender"
        );
        require(
            initiator == address(this),
            "FlashBorrower: Untrusted loan initiator"
        );
        (Action action) = abi.decode(data, (Action));
        if (action == Action.NORMAL) {
            require(IERC20(token).balanceOf(address(this)) >= amount);
            // make a profitable trade here
            IERC20(token).transfer(initiator, amount + fee);
        } else if (action == Action.OTHER) {
            // do another
        }
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    /// @dev Initiate a flash loan
    function flashBorrow(
        address token,
        uint256 amount
    ) public {
        bytes memory data = abi.encode(Action.NORMAL);
        uint256 _allowance = IERC20(token).allowance(address(this), address(lender));
        uint256 _fee = lender.flashFee(token, amount);
        uint256 _repayment = amount + _fee;
        IERC20(token).approve(address(lender), _allowance + _repayment);
        lender.flashLoan(this, token, amount, data);
    }
}
```

## Vat Stbl

It may be that users are interested in moving stbl around in the internal vat balances. Instead of wasting gas by minting/burning ERC20 stbl you can instead use the vat stbl flash mint function to short cut this.

The vat stbl version of flash mint is roughly the same as the ERC20 stbl version with a few caveats:

### Function Signature

`vatStblFlashLoan(IVatStblFlashBorrower receiver, uint256 amount, bytes calldata data)`

vs

`flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data)`

Notice that no token is required because it is assumed to be vat stbl. Also, the `amount` is in RADs and not in WADs.

### Approval Mechanism

ERC3156 specifies using a token approval to approve the amount to repay to the lender. Unfortunately vat stbl does not have a way to specify delegation amounts, so instead of giving the flash mint module full rights to withdraw any amount of vat stbl we have instead opted to have the receiver push the balance owed at the end of the transaction.

### Example

Here is an example similar to the one above to showcase the differences:

```
pragma solidity ^0.6.12;

import "dss-interfaces/dss/VatAbstract.sol";

import "./interfaces/IERC3156FlashLender.sol";
import "./interfaces/IVatStblFlashBorrower.sol";

contract FlashBorrower is IVatStblFlashBorrower {
    enum Action {NORMAL, OTHER}

    VatAbstract vat;
    IVatStblFlashLender lender;

    constructor (
        VatAbstract vat_,
        IVatStblFlashLender lender_
    ) public {
        vat = vat_;
        lender = lender_;
    }

    /// @dev Vat Stbl Flash loan callback
    function onVatStblFlashLoan(
        address initiator,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        require(
            msg.sender == address(lender),
            "FlashBorrower: Untrusted lender"
        );
        require(
            initiator == address(this),
            "FlashBorrower: Untrusted loan initiator"
        );
        (Action action) = abi.decode(data, (Action));
        if (action == Action.NORMAL) {
            // do one thing
        } else if (action == Action.OTHER) {
            // do another
        }

        // Repay the loan amount + fee
        // Be sure not to overpay as there are no safety guards for this
        vat.move(address(this), lender, amount + fee);

        return keccak256("VatStblFlashBorrower.onVatStblFlashLoan");
    }

    /// @dev Initiate a flash loan
    function vatStblFlashBorrow(
        uint256 amount
    ) public {
        bytes memory data = abi.encode(Action.NORMAL);
        lender.vatStblFlashLoan(this, amount, data);
    }
}

```

## Deployment

To deploy this contract run the following commands:

`make deploy-mainnet` for mainnet deployment

`make deploy-goerli` for goerli deployment

[//]: # (Deployed Mainnet address: [0x60744434d6339a6B27d73d9Eda62b6F66a0a04FA]&#40;https://etherscan.io/address/0x60744434d6339a6B27d73d9Eda62b6F66a0a04FA#code&#41;  )
