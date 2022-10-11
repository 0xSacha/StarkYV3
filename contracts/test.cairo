%lang starknet

from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.cairo.common.uint256 import ALL_ONES, Uint256, uint256_check, uint256_eq, uint256_lt, uint256_le
from starkware.cairo.common.math import assert_not_zero
from openzeppelin.token.erc20.library import ERC20
from openzeppelin.token.erc20.IERC20 import IERC20
from openzeppelin.security.reentrancyguard.library import ReentrancyGuard 
from openzeppelin.security.pausable.library import Pausable 
from openzeppelin.security.safemath.library import SafeUint256 



from utils.safeerc20 import SafeERC20
from interfaces.IStrategy import IStrategy
from interfaces.IAccountant import IAccountant


from starkware.starknet.common.syscalls import (
    get_block_number,
    get_block_timestamp,
)


// Events
// ERC4626 EVENTS
@event
func Deposit(sender: felt, owner: felt, assets: Uint256, shares: Uint256){
}

@event
func Withdraw(sender: felt, receiver: felt, owner: Uint256, assets: Uint256, shares: Uint256){
}

@event
func StrategyAdded(strategy: felt){
}

@event
func StrategyRevoked(strategy: felt){
}

@event
func StrategyMigrated(old_strategy: felt, new_strategy: felt){
}

@event
func StrategyReported(strategy: felt, gain: Uint256, loss: Uint256, current_debt: Uint256, total_fees: Uint256, total_refunds: Uint256){
}

// DEBT MANAGEMENT EVENTS
@event
func DebtUpdated(strategy: felt, current_debt: Uint256, new_debt: Uint256){
}

// STORAGE MANAGEMENT EVENTS
@event
func UpdateAccountant(accountant: felt){
}

@event 
func UpdatedMaxDebtForStrategy(sender: felt, strategy: felt, new_debt: Uint256){
}

@event 
func UpdateDepositLimit(deposit_limit: Uint256){
}

@event 
func UpdateMinimumTotalIdle(minimum_total_idle: Uint256){
}

@event 
func Shutdown(){
}

@event 
func Sweep(token: felt, amount: Uint256){
}


// STRUCTS 

struct StrategyParams {
    activation: felt,
    last_report: Uint256,
    current_debt: Uint256,
    max_debt: Uint256,
}

// CONSTANTS

const MAX_BPS = 10000;

// const API_VERSION = 73839733893

// const DOMAIN_TYPE_HASH = 73839733893

// const PERMIT_TYPE_HASH = 73839733893


// ENUM NOT LIVE YET 
const STRATEGY_MANAGER = 1;
const DEBT_MANAGER = 2;
const EMERGENCY_MANAGER = 3;
const ACCOUNTING_MANAGER = 4;


// STORAGE


@storage_var
func asset() -> (asset : felt){
}

@storage_var
func strategies(strategy: felt) -> (parameter : StrategyParams){
}

@storage_var
func total_debt() -> (total_debt : Uint256){
}

@storage_var
func total_idle() -> (total_idle: Uint256){
}

@storage_var
func minimum_total_idle() -> (minimum_total_idle : Uint256){
}

@storage_var
func deposit_limit() -> (deposit_limit : Uint256){
}

@storage_var
func accountant() -> (accountant : felt){
}

@storage_var
func roles(address: felt) -> (role : felt){
}

@storage_var
func open_roles(role: felt) -> (open : felt){
}

@storage_var
func role_manager() -> (role_manager : felt){
}

@storage_var
func future_role_manager() -> (future_role_manager : felt){
}

@storage_var
func shutdown() -> (shutdown : felt){
}

@storage_var
func nonces(address: felt) -> (nonce : Uint256){
}

@storage_var
func profit_end_date() -> (profit_end_date : Uint256){
}

@storage_var
func profit_last_update() -> (profit_last_update : Uint256){
}

@storage_var
func profit_distribution_rate() -> (profit_distribution_rate : Uint256){
}

@storage_var
func profit_max_unlock_time() -> (profit_max_unlock_time: Uint256){
}
    
    
    
    
    // Setters
    
    func set_accountant{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _new_accountant: felt) {
        //TODO: permissioning: CONFIG_MANAGER
        accountant.write(_new_accountant);
        UpdateAccountant.emit(_new_accountant);
        tempvar assets_: Uint256;
        if(1 == 1){
            tempvar syscall_ptr = syscall_ptr;
            assets_.low = 8;
            assets_= Uint256(1,0);
        } else{
            tempvar syscall_ptr = syscall_ptr;
        }
        return ();
    }
    

