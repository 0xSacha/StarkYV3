%lang starknet

from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace IStrategy {

    func asset() -> (asset: felt) {
    }

    func vault() -> (vault: felt) {
    }

    func balanceOf(owner: felt) -> (balance: Uint256) {
    }

    func maxDeposit(receiver: felt) -> (maxAssets: Uint256) {
    }

    func maxWithdraw(owner: felt) -> (maxAssets: Uint256) {
    }

    func withdraw(amount: Uint256, receiver: felt, owner: felt) -> (assets: Uint256) {
    }

    func deposit(amount: Uint256, receiver: felt) -> (assets: Uint256) {
    }

    func totalAssets() -> (totalAssets: Uint256) {
    }

    func convertToAssets(shares: Uint256) -> (assets: Uint256) {
    }

    func convertToShares(assets: Uint256) -> (shares: Uint256) {
    }
}

