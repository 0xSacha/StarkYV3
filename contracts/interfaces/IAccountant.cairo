%lang starknet

from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace IAccountant {

    func report(gain: Uint256, loss: Uint256) -> (gain: Uint256, loss: Uint256) {
    }

}