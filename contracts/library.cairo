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
    activation: Uint256,
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
    
    
namespace Vault{
    
    func init{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _role_manager: felt,
            _asset : felt,
            _name : felt,
            _symbol : felt,
            _profit_max_unlock_time: Uint256){
        let (decimals_) = IERC20.decimals(_asset);
        ERC20.initializer(_name, _symbol, decimals_);
        asset.write(_asset);
        role_manager.write(_role_manager);
        profit_max_unlock_time.write(_profit_max_unlock_time);
        shutdown.write(FALSE);
        let (block_timestamp_) = get_block_timestamp();
        profit_last_update.write(Uint256(block_timestamp_,0));
        profit_end_date.write(Uint256(block_timestamp_,0));
        return ();
    }
    
    
    
    // Setters
    
    func set_accountant{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _new_accountant: felt) {
        //TODO: permissioning: CONFIG_MANAGER
        accountant.write(_new_accountant);
        UpdateAccountant.emit(_new_accountant);
        return ();
    }
    
    func set_deposit_limit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _deposit_limit: Uint256) {
        // TODO: permissioning: CONFIG_MANAGER
        deposit_limit.write(_deposit_limit);
        UpdateDepositLimit.emit(_deposit_limit);
        return ();
    }
    
    func set_minimum_total_idle{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _minimum_total_idle: Uint256) {
        let (caller_) = get_caller_address();
        enforce_role(caller_, DEBT_MANAGER);
        minimum_total_idle.write(_minimum_total_idle);
        UpdateMinimumTotalIdle.emit(_minimum_total_idle);
        return ();
    }
    
    // ROLE MANAGEMENT
    
    func enforce_role{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _account: felt,
            _role: felt) {
        let (is_open_role_) = open_roles.read(_role);
        let (account_role_) = roles.read(_account);
        if (is_open_role_ == 1){
            return();
        }
        with_attr error_message("not allowed caller"){
            assert account_role_ = _account;
        }
        return();
    }
    
    func set_role{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _account: felt,
            _role: felt) {
        let (caller_) = get_caller_address();
        let (role_manager_) = role_manager.read();
        with_attr error_message("only callable by role manager"){
            assert caller_ = role_manager_;
        }
        roles.write(_account, _role);
        return ();
    }
    
    func set_open_role{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _role: felt) {
        let (caller_) = get_caller_address();
        let (role_manager_) = role_manager.read();
        with_attr error_message("only callable by role manager"){
            assert caller_ = role_manager_;
        }
        open_roles.write(_role, TRUE);
        return ();
    }
    
    func transfer_role_manager{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _role_manager: felt) {
        let (caller_) = get_caller_address();
        let (role_manager_) = role_manager.read();
        with_attr error_message("only callable by role manager"){
            assert caller_ = role_manager_;
        }
        future_role_manager.write(_role_manager);
        return ();
    }
    
    func accept_role_manager{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() {
        let (caller_) = get_caller_address();
        let (future_role_manager_) = future_role_manager.read();
        with_attr error_message("only callable by future role manager"){
            assert caller_ = future_role_manager_;
        }
        role_manager.write(future_role_manager_);
        future_role_manager.write(0);
        return ();
    }
    
    func price_per_share{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (price_per_share: Uint256) {
        let (decimals_) = ERC20.decimals();
        let (one_share_) = pow(10, decimals_);
        let (price_per_share_) =  convert_to_assets(Uint256(one_share_,0));
        return (price_per_share_,);
    }
    
    func available_deposit_limit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}()
        -> (available_deposit_limit: Uint256) {
        alloc_locals;
        let (deposit_limit_) = deposit_limit.read();
        let (total_assets_) = total_assets();
        let (is_lt_) = uint256_lt(total_assets_, deposit_limit_);
        if (is_lt_ == 1){
            let (diff_) = SafeUint256.sub_lt(deposit_limit_, total_assets_);
            return(diff_,);
        }
        return(Uint256(0,0),);
    }
    
    // ACCOUNTING MANAGEMENT
    
    func process_report{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _strategy : felt) -> (gain: Uint256, loss: Uint256){
        // TODO: should it be open?
        let (caller_) = get_caller_address();
        enforce_role(caller_, ACCOUNTING_MANAGER);
        return _process_report(_strategy);
    }
    
    func sweep{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _token : felt) -> (amount: Uint256){
        alloc_locals;
        let (caller_) = get_caller_address();
        enforce_role(caller_, ACCOUNTING_MANAGER);
        let (asset_) = asset.read();
        let (this_) = get_contract_address();
        if (_token == asset_){
            let (asset_balance_) = ERC20.balance_of(this_);
            let (total_idle_) = total_idle.read();
            let (amount_) = SafeUint256.sub_le(asset_balance_, total_idle_);
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
        } else{
            let (amount_) = IERC20.balanceOf(_token, this_);
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
        }
        SafeERC20.transfer(_token, caller_, amount_);
        Sweep.emit(_token, amount_);
        return (amount_,);
    }
    
    func add_strategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _new_strategy : felt){
        let (caller_) = get_caller_address();
        enforce_role(caller_, ACCOUNTING_MANAGER);
        _add_strategy(_new_strategy);
        return ();
    }
    
    func revoke_strategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _old_strategy : felt){
        let (caller_) = get_caller_address();
        enforce_role(caller_, ACCOUNTING_MANAGER);
        _revoke_strategy(_old_strategy);
        return ();
    }
    
    func migrate_strategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _new_strategy : felt,
            _old_strategy : felt){
        let (caller_) = get_caller_address();
        enforce_role(caller_, ACCOUNTING_MANAGER);
        _migrate_strategy(_new_strategy, _old_strategy);
        return ();
    }
    
    // MANAGEMENT
    
    func update_max_debt_for_strategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _strategy: felt,
            _new_max_debt: Uint256) {
        let (caller_) = get_caller_address();
        enforce_role(caller_, DEBT_MANAGER);
        let (strategy_params_) = strategies.read(_strategy);
        with_attr error_message("strategy not activated"){
            assert_not_zero(strategy_params_.activation.low);
        }
        let new_strategy_params_ = StrategyParams(strategy_params_.activation, strategy_params_.last_report, strategy_params_.current_debt, _new_max_debt);
        strategies.write(_strategy, new_strategy_params_);
        UpdatedMaxDebtForStrategy.emit(caller_, _strategy, _new_max_debt,);
        return ();
    }
    
    
    func update_debt{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _strategy : felt,
            _target_debt: Uint256) -> (new_debt: Uint256){
        let (caller_) = get_caller_address();
        enforce_role(caller_, DEBT_MANAGER);
        return _update_debt(_strategy, _target_debt);
    }
    
    func shutdown_vault{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(){
        let (caller_) = get_caller_address();
        enforce_role(caller_, EMERGENCY_MANAGER);
        let (shutdown_) = shutdown.read();
        with_attr error_message("Vault already shutdowned"){
            assert shutdown_ = FALSE;
        }
        shutdown.write(TRUE);
        //TODO: attribute roles debt manager 
        Shutdown.emit();
        return ();
    }
    
    // SHARE MANAGEMENT
    
    func deposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _sender: felt,
            _recipient : felt,
            _assets : Uint256) -> (shares : Uint256){
        alloc_locals;
        uint256_check(_assets);
        ReentrancyGuard._start();
        let (shutdown_) = shutdown.read();
        with_attr error_message("vault is down"){
            assert shutdown_ = FALSE;
        }
        let (this_) = get_contract_address();
        assert_not_zero(_recipient);
        assert_not_zero(_recipient - this_);
    
        // If the amount is max_value(uint256) we assume the user wants to deposit their whole balance
        let (is_max_uint256_) = uint256_eq(_assets, Uint256(ALL_ONES,ALL_ONES));
        let (asset_) = asset.read();
        tempvar assets_: Uint256;
        if(is_max_uint256_ == 1){
            let (user_balance_) = IERC20.balanceOf(asset_, _sender);
            assets_.low = user_balance_.low;
            assets_.high = user_balance_.high;
            tempvar syscall_ptr = syscall_ptr;
            tempvar range_check_ptr;
        } else{
            assets_.low = _assets.low;
            assets_.high = _assets.high;
            tempvar syscall_ptr = syscall_ptr;
            tempvar range_check_ptr;
        }
    
        let (max_assets_) = max_deposit(_sender);
        let (is_allowed_amount_) = uint256_le(assets_, max_assets_);
    
        let (shares_) = issue_shares_for_amount(assets_, _recipient);
        let (is_shares_nul_) = uint256_lt(Uint256(0,0), shares_);
    
        with_attr error_message("cannot mint zero"){
            assert is_shares_nul_ = 0;
        }
    
        // why original version use msg.sender better than sender param?
        SafeERC20.transferFrom(asset_, _sender, _recipient, assets_);
        let (total_idle_) = total_idle.read();
        let (new_total_idle_) = SafeUint256.add(total_idle_, assets_);
        total_idle.write(new_total_idle_);
    
        ReentrancyGuard._end();
        Deposit.emit(_sender, _recipient, assets_, shares_);
        return (shares_,);
    }
    
    func redeem{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _sender: felt, 
            _receiver : felt, 
            _owner : felt, 
            _shares_to_burn: Uint256, 
            _strategies_len: felt, 
            _strategies: felt*) -> (assets : Uint256){
        alloc_locals;
        uint256_check(_shares_to_burn);
        let (owner_balance_) = ERC20.balance_of(_owner);
        let (is_eq_) = uint256_eq(_shares_to_burn, Uint256(ALL_ONES,ALL_ONES));
        if(_sender != _owner){
            ERC20._spend_allowance(_owner, _sender, _shares_to_burn);
            tempvar range_check_ptr = range_check_ptr;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
        } else {
            tempvar range_check_ptr = range_check_ptr;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
        }
        tempvar shares_: Uint256;
        if(is_eq_ == 1){
            shares_.low = owner_balance_.low;
            shares_.high = owner_balance_.high;
        } else{
            shares_.low = _shares_to_burn.low;
            shares_.high = _shares_to_burn.high;
        }
        // assert shares_balance >= shares, "insufficient shares to redeem" why knowing burn will revert if balance not enough
        let (is_shares_positive_) = uint256_lt(Uint256(0,0),shares_);
        with_attr error_message("no shares to redeem"){
            assert is_shares_positive_ = 1;
        }
    
        let (requested_assets_) = convert_to_assets(shares_);
        let (total_idle_) = total_idle.read();

        tempvar temp_requested_assets_: Uint256;
        tempvar temp_total_idle_: Uint256;

        let (is_requested_assets_exceed_total_idle_) = uint256_lt(temp_total_idle_, requested_assets_);
        let (asset_) = asset.read();
        if(is_requested_assets_exceed_total_idle_ == 1){
            let (total_debt_) = total_debt.read();
            let (profit_distribution_rate_) = profit_distribution_rate.read();
            let (profit_last_update_) = profit_last_update.read();
            let (profit_end_date_) = profit_end_date.read();
            let (block_timestamp_) = get_block_timestamp();
            let (is_block_timestamp_lt_profit_end_date_) = uint256_lt(Uint256(block_timestamp_,0),profit_end_date_);
            if(is_block_timestamp_lt_profit_end_date_ == 1){
                let (step1_) = SafeUint256.sub_lt(Uint256(block_timestamp_,0), profit_last_update_);
                let (step2_) = SafeUint256.mul(step1_, profit_distribution_rate_);
                let (unlocked_profit_,_) = SafeUint256.div_rem(step2_, Uint256(MAX_BPS,0));
                // we update last update time as profit is unlocked and will be added to storage debt afterwards
                profit_last_update.write(Uint256(block_timestamp_,0));
            } else{
                let (step1_) = SafeUint256.sub_lt(profit_end_date_, profit_last_update_);
                let (step2_) = SafeUint256.mul(step1_, profit_distribution_rate_);
                let (unlocked_profit_,_) = SafeUint256.div_rem(step2_, Uint256(MAX_BPS,0));
                profit_distribution_rate.write(Uint256(0,0));
            }
            let (curr_total_debt_) = SafeUint256.add(total_debt_, unlocked_profit_);
            let (assets_needed_) = SafeUint256.sub_lt(requested_assets_, total_idle_);
            let (this_) = get_contract_address();
            let (previous_balance_) = IERC20.balanceOf(asset_, this_);
            let (new_total_debt_, new_total_idle_, new_requested_assets_) = loop_strategies(
                    _strategies_len,
                    _strategies,
                    previous_balance_,
                    requested_assets_,
                    assets_needed_,
                    curr_total_debt_,
                    total_idle_,
                    this_,
                    asset_);
            let (is_le_) = uint256_le(new_requested_assets_, new_total_idle_);
            with_attr error_message("insufficient assets in vault"){
                assert is_le_ = 1;
            }
            total_debt.write(new_total_debt_);
            temp_total_idle_.low = new_total_idle_.low;
            temp_total_idle_.high = new_total_idle_.high;
            temp_requested_assets_.low = new_requested_assets_.low;
            temp_requested_assets_.high = new_requested_assets_.high;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
        } else{
            temp_total_idle_.low = total_idle_.low;
            temp_total_idle_.high = total_idle_.high;
            temp_requested_assets_.low = requested_assets_.low;
            temp_requested_assets_.high = temp_requested_assets_.high;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
        }
        ERC20._burn(_owner, shares_);
        let (new_total_idle_) = SafeUint256.sub_le(temp_total_idle_, temp_requested_assets_);
        total_idle.write(new_total_idle_);
        SafeERC20.transfer(asset_, _receiver, requested_assets_);
        ReentrancyGuard._end();
        Withdraw.emit(_owner, _receiver, requested_assets_, temp_requested_assets_,shares_);
        return (requested_assets_,);
}
    
    
    
    
    
    func get_total_debt{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            ) -> (total_debt: Uint256){
        alloc_locals;
        let (total_debt_) = total_debt.read();
        let (unlocked_profit_) = get_unlocked_profit();
        let (total_debt_) = SafeUint256.add(total_debt_, unlocked_profit_);
        return (total_debt_,);
    }
    
    func get_profit_distribution_rate{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            ) -> (profit_distribution_rate: Uint256){
        let (profit_end_date_) = profit_end_date.read();
        let (block_timestamp_) = get_block_timestamp();
        let (profit_distribution_rate_) = profit_distribution_rate.read();
        let (is_le_) = uint256_le(Uint256(block_timestamp_,0),profit_end_date_);
        if (is_le_ == 1) {
            return(profit_distribution_rate_,);
        } else{
            return(Uint256(0,0),);
        }
    }
    
    func total_assets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (totalAssets : Uint256){
        alloc_locals;
        let (total_idle_) = total_idle.read();
        let (total_debt_) = get_total_debt();
        let (total_assets_) = SafeUint256.add(total_idle_, total_debt_);
        return (total_assets_,);
    }
    
    func convert_to_shares{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(_assets : Uint256) -> (shares : Uint256){
        alloc_locals;
        with_attr error_message("assets is not a valid Uint256"){
            uint256_check(_assets);
        }
    
        let (supply_) = ERC20.total_supply();
        let (all_assets) = total_assets();
        let (supply_is_zero) = uint256_eq(supply_, Uint256(0, 0));
        if (supply_is_zero == TRUE) {
            return (_assets,);
        }
        let (shares_) = mul_div_down(_assets, supply_, all_assets);
        return (shares_,);
    }
    
    func convert_to_assets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(_shares : Uint256) -> (assets : Uint256){
        alloc_locals;
        with_attr error_message("shares is not a valid Uint256"){
            uint256_check(_shares);
        }
    
        let (supply_) = ERC20.total_supply();
        let (all_assets_) = total_assets();
        let (supply_is_zero) = uint256_eq(supply_, Uint256(0, 0));
        if(supply_is_zero == TRUE){
            return (_shares,);
        }
        let (assets_) = mul_div_down(_shares, all_assets_, supply_);
        return (assets_,);
    }
    
    func max_deposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(_receiver: felt) -> (max_deposit : Uint256){
        let (total_assets_) = total_assets();
        let (deposit_limit_) = deposit_limit.read();
        let (is_limit_exceeded_) = uint256_le(deposit_limit_, total_assets_);
        if(is_limit_exceeded_ == 1){
            return(Uint256(0,0),);
        } else{
            let (diff_) = SafeUint256.sub_lt(deposit_limit_, total_assets_);
            return(diff_,);
        }
    }
    
    func max_redeem{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _owner : felt) -> (max_redeem : Uint256){
        alloc_locals;
        let (balance_of_owner_) = ERC20.balance_of(_owner);
        let (total_idle_) = total_idle.read();
        let (total_idle_to_shares_) = convert_to_shares(total_idle_);
        let (is_vault_enough_funds_) = uint256_le(balance_of_owner_,total_idle_to_shares_);
        if(is_vault_enough_funds_ == 1){
            return(balance_of_owner_,);
        } else{
            return(total_idle_to_shares_,);
        }
    }
    
    
    
    // getters for public var
    
    func get_asset{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (asset : felt){
        let (asset_ : felt) = asset.read();
        return(asset_,);
    }
    
    func get_strategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _strategy: felt) -> (strategy_parameters: StrategyParams){
        let (strategy_params_) = strategies.read(_strategy);
        return (strategy_params_,);
    }
    
    func get_total_idle{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (total_idle: Uint256){
        let (total_idle_) = total_idle.read();
        return (total_idle_,);
    }
    
    func get_minimum_total_idle{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (minimum_total_idle: Uint256){
        let (minimum_total_idle_) = minimum_total_idle.read();
        return (minimum_total_idle_,);
    }
    
    func get_deposit_limit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (deposit_limit: Uint256){
        let (deposit_limit_) = deposit_limit.read();
        return (deposit_limit_,);
    }
    
    func get_accountant{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (accountant: felt){
        let (accountant_) = accountant.read();
        return (accountant_,);
    }

    func get_roles{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(_account: felt) -> (role: felt){
        let (roles_) = roles.read(_account);
        return (roles_,);
    }
    

    func get_open_roles{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(_role: felt) -> (is_open: felt){
        let (is_open_) = open_roles.read(_role);
        return (is_open_,);
    }
    

    func get_role_manager{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (role_manager: felt){
        let (role_manager_) = role_manager.read();
        return (role_manager_,);
    }
    
    func get_future_role_manager{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (future_role_manager: felt){
        let (future_role_manager_) = future_role_manager.read();
        return (future_role_manager_,);
    }
    
    func get_shutdown{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (shutdown: felt){
        let (shutdown_) = shutdown.read();
        return (shutdown_,);
    }
    
    func get_profit_end_date{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (profit_end_date: Uint256){
        let (profit_end_date_) = profit_end_date.read();
        return (profit_end_date_,);
    }
    
    func get_profit_last_update{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (profit_last_update: Uint256){
        let (profit_last_update_) = profit_last_update.read();
        return (profit_last_update_,);
    }
    
    
    // Internals
    
    func _process_report{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _strategy : felt) -> (gain: Uint256, loss: Uint256){
        alloc_locals;
        // Processing a report means comparing the debt that the strategy has taken with the current amount of funds it is reporting
        // If the strategy ows less than it currently have, it means it has had a profit
        // Else (assets < debt) it has had a loss
        // Different strategies might choose different reporting strategies: pessimistic, only realised P&L, ...
        // The best way to report depends on the strategy
        // The profit will be distributed following a smooth curve over the next PROFIT_MAX_UNLOCK_TIME seconds. 
        // Losses will be taken immediately
        let (block_timestamp_) = get_block_timestamp();
        let (strategy_params_) = strategies.read(_strategy);
        
        with_attr error_message("strategy not activated"){
            assert_not_zero(strategy_params_.activation.low);
        }
    
        // Vault needs to assess 
        let (this_) = get_contract_address();
        let (strategy_shares_) = IStrategy.balanceOf(_strategy, this_);
        let (total_assets_) = IStrategy.convertToAssets(_strategy, strategy_shares_);
        let (is_eq_) = uint256_eq(total_assets_, strategy_params_.current_debt);

        with_attr error_message("nothing to report"){
            assert is_eq_ = 0;
        }
    

        let (is_lt_) = uint256_lt(strategy_params_.current_debt, total_assets_);
        
        
        tempvar temp_gain_: Uint256;
        tempvar temp_loss_: Uint256;

        if (is_lt_ == 1){
        let (gain_) = SafeUint256.sub_lt(total_assets_, strategy_params_.current_debt);
        temp_gain_.low = gain_.low;
        temp_gain_.high = gain_.high;
        temp_loss_.low = 0;
        temp_loss_.high = 0;
        } else{
        let (loss_) = SafeUint256.sub_lt(strategy_params_.current_debt, total_assets_);
        temp_gain_.low = 0;
        temp_gain_.high = 0;
        temp_loss_.low = loss_.low;
        temp_loss_.high = loss_.low;
        }

        tempvar temp_remaining_time_: Uint256;
        tempvar temp_unlocked_profit_: Uint256;
        tempvar temp_pending_profit_: Uint256;
        let (profit_distribution_rate_) = profit_distribution_rate.read();
    
        let (is_nul_) = uint256_eq(Uint256(0,0), profit_distribution_rate_);
        if (is_nul_ == 0){
            let (profit_end_date_) = profit_end_date.read();
            let (profit_last_update_) = profit_last_update.read();
            let (is_lt_) = uint256_lt(profit_end_date_, Uint256(block_timestamp_,0));    
            if( is_lt_ == 1){
                let (step1_) = SafeUint256.sub_lt(profit_end_date_, profit_last_update_);
                let (step2_) = SafeUint256.mul(step1_, profit_distribution_rate_);
                let (unlocked_profit_,_) = SafeUint256.div_rem(step2_, Uint256(MAX_BPS,0));
                profit_distribution_rate.write(Uint256(0,0));
                temp_unlocked_profit_.low = unlocked_profit_.low;
                temp_unlocked_profit_.high = unlocked_profit_.high;
                temp_remaining_time_.low = 0;
                temp_remaining_time_.high = 0;
                temp_pending_profit_.low = 0;
                temp_pending_profit_.high= 0;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
                tempvar range_check_ptr = range_check_ptr;
            } else{
                let (step1_) = SafeUint256.sub_lt(Uint256(block_timestamp_,0), profit_last_update_);
                let (step2_) = SafeUint256.mul(step1_, profit_distribution_rate_);
                let (unlocked_profit_,_) = SafeUint256.div_rem(step2_, Uint256(MAX_BPS,0));
                let (remaining_time_) = SafeUint256.sub_le(profit_end_date_,Uint256(block_timestamp_,0));
                let (step1_) = SafeUint256.mul(profit_distribution_rate_, remaining_time_);
                let (pending_profit_,_) = SafeUint256.div_rem(step1_, Uint256(MAX_BPS,0));
                temp_unlocked_profit_.low = unlocked_profit_.low;
                temp_unlocked_profit_.high = unlocked_profit_.high;
                temp_remaining_time_.low = remaining_time_.low;
                temp_remaining_time_.high = remaining_time_.high;
                temp_pending_profit_.low = pending_profit_.low;
                temp_pending_profit_.high= pending_profit_.high;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
                tempvar range_check_ptr = range_check_ptr;
            }
        } else {
            temp_unlocked_profit_.low = 0;
            temp_unlocked_profit_.high = 0;
            temp_remaining_time_.low = 0;
            temp_remaining_time_.high = 0;
            temp_pending_profit_.low = 0;
            temp_pending_profit_.high= 0;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
        }
    
        //  should we add a very low protocol management fee? (set to factory contract)
        let (accountant_) = accountant.read();

        tempvar temp_total_fees_: Uint256;
        tempvar temp_total_refunds_: Uint256;
    
        if (accountant_ != 0){
            let (total_fees_, total_refunds_) = IAccountant.report(_strategy, temp_gain_, temp_loss_);
            temp_total_fees_.low = total_fees_.low;
            temp_total_fees_.high = total_fees_.high;
            temp_total_refunds_.low = total_refunds_.low;
            temp_total_refunds_.high = total_refunds_.high;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
        } else{
            temp_total_fees_.low = 0;
            temp_total_fees_.high = 0;
            temp_total_refunds_.low = 0;
            temp_total_refunds_.high = 0;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
        }
    
        let (is_gain_) = uint256_lt(Uint256(0,0), temp_gain_);

        tempvar temp_strategy_debt_: Uint256;
    
        let (total_debt_) = total_debt.read();
        if (is_gain_ == 1){
            let (strategy_current_debt_) = SafeUint256.add(strategy_params_.current_debt, temp_gain_);
            temp_strategy_debt_.low = strategy_current_debt_.low;
            temp_strategy_debt_.high = strategy_current_debt_.high;
            let (profit_max_unlock_time_) = profit_max_unlock_time.read();
            let (is_nul_)=  uint256_eq(Uint256(0,0), profit_max_unlock_time_);
            if (is_nul_ == 1){
                let (step1_) = SafeUint256.add(temp_gain_, temp_unlocked_profit_);
                let (new_total_debt_) = SafeUint256.add(step1_, total_debt_);
                total_debt.write(new_total_debt_);
                tempvar range_check_ptr = range_check_ptr;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
            } else {
                // Fees need to be released immediately to avoid price per share going down after minting the shares
                let (is_lt_) = uint256_lt(temp_total_fees_, temp_gain_);
                if (is_lt_ == 1){
                    let (gain_without_fees_) = SafeUint256.sub_lt(temp_gain_, temp_total_fees_);
                    let (step1_) = SafeUint256.mul(temp_pending_profit_, temp_remaining_time_);
                    let (step2_) = SafeUint256.mul(gain_without_fees_, profit_max_unlock_time_);
                    let (step3_) = SafeUint256.add(step1_, step2_);
                    let (step4_) = SafeUint256.add(temp_pending_profit_, gain_without_fees_);
                    let (new_profit_locking_period_,_) = SafeUint256.div_rem(step3_, step4_);
                    let (step1_) = SafeUint256.mul(temp_pending_profit_, gain_without_fees_);
                    let (step2_) = SafeUint256.mul(step1_, Uint256(MAX_BPS,0));
                    let (new_profit_distribution_rate_,_) = SafeUint256.div_rem(step2_, new_profit_locking_period_);
                    profit_distribution_rate.write(new_profit_distribution_rate_);
                    let (profit_end_date_) = SafeUint256.add(Uint256(block_timestamp_,0), new_profit_locking_period_);
                    profit_end_date.write(profit_end_date_);
                    profit_last_update.write(Uint256(block_timestamp_,0));
                    let (step1_) = SafeUint256.add(temp_unlocked_profit_, temp_total_fees_);
                    let (new_total_debt_) = SafeUint256.add(total_debt_, step1_);
                    total_debt.write(new_total_debt_);
                    tempvar range_check_ptr = range_check_ptr;
                    tempvar syscall_ptr = syscall_ptr;
                    tempvar pedersen_ptr = pedersen_ptr;
                } else{
                    // Fees are >= gain, it's like we had a loss (we will unlock as much profits as required to avoid a decrease in pps, if there is enough profit locked to cover fees)
                    let (diff_) = SafeUint256.sub_le(temp_total_fees_, temp_gain_);
                    let (is_lt_) = uint256_lt(diff_, temp_pending_profit_);
                    if (is_lt_ == 1){
                    // We unlock profit immediately, leaving the remaining time as is
                    //If there is pending profit, we reduce it by the difference between total_fees and gain
                            let (step1_) = SafeUint256.sub_lt(temp_pending_profit_, diff_);
                            let (step2_) = SafeUint256.mul(step1_, Uint256(MAX_BPS,0));
                            let (new_profit_distribution_rate_,_) = SafeUint256.div_rem(step2_, temp_remaining_time_);
                            profit_distribution_rate.write(new_profit_distribution_rate_);
                            let (profit_end_date_) = SafeUint256.add(Uint256(block_timestamp_,0), temp_remaining_time_);
                            profit_end_date.write(profit_end_date_);
                            profit_last_update.write(Uint256(block_timestamp_,0));
                            let (step1_) = SafeUint256.add(temp_unlocked_profit_, temp_total_fees_);
                            let (new_total_debt_) = SafeUint256.add(total_debt_, step1_);
                            total_debt.write(new_total_debt_);
                            tempvar range_check_ptr = range_check_ptr;
                            tempvar syscall_ptr = syscall_ptr;
                            tempvar pedersen_ptr = pedersen_ptr;
                    } else{
                        profit_distribution_rate.write(Uint256(0,0));
                        let (step1_) = SafeUint256.add(temp_unlocked_profit_, temp_gain_);
                        let (step2_) = SafeUint256.add(step1_, temp_pending_profit_);
                        let (new_total_debt_) = SafeUint256.add(total_debt_, step2_);
                        total_debt.write(new_total_debt_);
                        tempvar range_check_ptr = range_check_ptr;
                        tempvar syscall_ptr = syscall_ptr;
                        tempvar pedersen_ptr = pedersen_ptr;
                    }
                }
            }
        } else {
            temp_strategy_debt_.low = 0;
            temp_strategy_debt_.high = 0;
            tempvar range_check_ptr = range_check_ptr;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
        }
        let (is_lt_) = uint256_lt(Uint256(0,0), temp_total_fees_);
        if (is_lt_ == 1){
            issue_shares_for_amount(temp_total_fees_, accountant_);
            tempvar range_check_ptr = range_check_ptr;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
        } else {
            tempvar range_check_ptr = range_check_ptr;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
        }
        let (is_lt_) = uint256_lt(Uint256(0,0), temp_total_refunds_);
        if (is_lt_ == 1){
            let (asset_) = asset.read();
            let (accountant_balance_) = IERC20.balanceOf(accountant_, asset_);
            let (is_lt_) = uint256_lt(accountant_balance_, temp_total_refunds_);
            if(is_lt_ == 1){
                temp_total_refunds_.low = accountant_balance_.low;
                temp_total_refunds_.high = accountant_balance_.high;
            }
            SafeERC20.transferFrom(asset_, accountant_, this_, temp_total_refunds_);
            let (total_idle_) = total_idle.read();
            let (new_total_idle_) = SafeUint256.add(total_idle_, temp_total_refunds_);
            total_idle.write(new_total_idle_);
            tempvar range_check_ptr = range_check_ptr;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
        } else {
            tempvar range_check_ptr = range_check_ptr;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
        }
        
    
        let (is_lt_) = uint256_lt(Uint256(0,0), temp_loss_);
        if (is_lt_ == 1){
            let (strategy_current_debt_) = SafeUint256.sub_lt(strategy_params_.current_debt, temp_loss_);
            temp_strategy_debt_.low = strategy_current_debt_.low;
            temp_strategy_debt_.high = strategy_current_debt_.high;
            let (loss_with_fees_) = SafeUint256.add(temp_loss_, temp_total_fees_);
            let (is_le_) = uint256_le(temp_pending_profit_, loss_with_fees_);
            if(is_le_ == 1){
                profit_distribution_rate.write(Uint256(0,0));
                let (is_lt_) = uint256_lt(temp_pending_profit_, temp_loss_);
                if (is_lt_ == 1) {
                    let (step1_) = SafeUint256.sub_lt(temp_loss_, temp_pending_profit_);
                    let (step2_) = SafeUint256.add(temp_unlocked_profit_, total_debt_);
                    let (total_debt_) = SafeUint256.sub_lt(step2_, step1_);
                    total_debt.write(total_debt_);
                    tempvar range_check_ptr = range_check_ptr;
                    tempvar syscall_ptr = syscall_ptr;
                    tempvar pedersen_ptr = pedersen_ptr;
                } else{
                    let (step1_) = SafeUint256.sub_lt(temp_pending_profit_,temp_loss_);
                    let (step2_) = SafeUint256.add(step1_, temp_unlocked_profit_);
                    let (total_debt_) = SafeUint256.add(step2_, total_debt_);
                    total_debt.write(total_debt_);
                    tempvar range_check_ptr = range_check_ptr;
                    tempvar syscall_ptr = syscall_ptr;
                    tempvar pedersen_ptr = pedersen_ptr;
                }
            } else {
                tempvar range_check_ptr = range_check_ptr;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
            }
        } else {
            tempvar range_check_ptr = range_check_ptr;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
        }
        let new_strategy_params_ = StrategyParams(Uint256(block_timestamp_,0), Uint256(block_timestamp_,0), temp_strategy_debt_, strategy_params_.max_debt);
        strategies.write(_strategy, new_strategy_params_);
        return (temp_gain_, temp_loss_);
    }
    
    func _add_strategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _new_strategy : felt){
        
        with_attr error_message("strategy cannot be zero address"){
            assert_not_zero(_new_strategy);
        }
        let (strategy_asset_) = IStrategy.asset(_new_strategy);
        let (vault_asset_) = asset.read();
        with_attr error_message("strategy cannot be zero address"){
            assert strategy_asset_ = vault_asset_;
        }
        let (strategy_vault_) = IStrategy.vault(_new_strategy);
        let (this_) = get_contract_address();
        with_attr error_message("invalid vault"){
            assert strategy_vault_ = this_;
        }
    
        let (strategy_params_) = strategies.read(_new_strategy);
        let is_active_ = strategy_params_.activation;
        with_attr error_message("strategy already active"){
            assert_not_zero(strategy_params_.activation.low);
        }
        let (block_timestamp_) = get_block_timestamp();
        let strategy_params_ = StrategyParams(Uint256(block_timestamp_,0),Uint256(block_timestamp_,0),Uint256(0,0), Uint256(0,0));
    
        StrategyAdded.emit(_new_strategy);
        return ();
    }
    
    func _revoke_strategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _old_strategy : felt){
        alloc_locals;
        let (strategy_params_) = strategies.read(_old_strategy);
        let is_active_ = strategy_params_.activation;
        with_attr error_message("strategy not active"){
            assert is_active_.low = 1;
        }
    
        let has_debt_ = strategy_params_.current_debt;
        let (is_eq_) = uint256_eq(has_debt_, Uint256(0,0));
        with_attr error_message("strategy has debt"){
            assert is_eq_ = 1;
        }
        let (block_timestamp_) = get_block_timestamp();
        let strategy_params_nul_ = StrategyParams(Uint256(0,0),Uint256(0,0),Uint256(0,0),Uint256(0,0));
        strategies.write(_old_strategy, strategy_params_nul_);
        StrategyRevoked.emit(_old_strategy);
        return ();
    }
    
    func _migrate_strategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _new_strategy : felt,
            _old_strategy : felt){
        alloc_locals;
        let (old_strategy_params_) = strategies.read(_old_strategy);
        with_attr error_message("strategy not active"){
            assert old_strategy_params_.activation.low = 1;
        }
    
        let has_debt_ = old_strategy_params_.current_debt;
        let (is_eq_) = uint256_eq(has_debt_, Uint256(0,0));
        with_attr error_message("strategy has debt"){
            assert is_eq_ = 1;
        }
    
        with_attr error_message("strategy cannot be zero address"){
            assert_not_zero(_new_strategy);
        }
        let (strategy_asset_) = IStrategy.asset(_new_strategy);
        let (vault_asset_) = asset.read();
        with_attr error_message("strategy cannot be zero address"){
            assert strategy_asset_ = vault_asset_;
        }
        let (strategy_vault_) = IStrategy.vault(_new_strategy);
        let (this_) = get_contract_address();
        with_attr error_message("invalid vault"){
            assert strategy_vault_ = this_;
        }
    
        let (new_strategy_params_) = strategies.read(_new_strategy);
        with_attr error_message("strategy already active"){
            assert new_strategy_params_.activation.low = 0;
        }
    
        let (block_timestamp_) = get_block_timestamp();
        let new_strategy_params_ = StrategyParams(Uint256(block_timestamp_,0),Uint256(block_timestamp_,0), old_strategy_params_.current_debt,old_strategy_params_.max_debt);
        strategies.write(_new_strategy, new_strategy_params_);
        revoke_strategy(_old_strategy);
        StrategyMigrated.emit(_old_strategy, _new_strategy);
        return ();
    }
    
    func _update_debt{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _strategy : felt,
            _target_debt: Uint256) -> (new_debt: Uint256){
        alloc_locals;
        //     The vault will rebalance the debt vs target debt. Target debt must be smaller or equal strategy max_debt.
        //     This function will compare the current debt with the target debt and will take funds or deposit new 
        //     funds to the strategy. 
        //     The strategy can require a minimum (or a maximum) amount of funds that it wants to receive to invest. 
        //     The strategy can also reject freeing funds if they are locked.
        //     The vault will not invest the funds into the underlying protocol, which is responsibility of the strategy. 
        let (strategy_params_) = strategies.read(_strategy);
        let (is_le_) = uint256_le(_target_debt, strategy_params_.max_debt);
        tempvar temp_assets_to_withdraw_: Uint256;
        tempvar temp_new_debt_: Uint256;
        with_attr error_message("target debt higher than max debt"){
            assert is_le_ = 1;
        }
        
        let (shutdown_) = shutdown.read();

        if(shutdown_ == 1){
            temp_new_debt_.low = 0;
            temp_new_debt_.high = 0;
            
        } else{
            temp_new_debt_.low = _target_debt.low;
            temp_new_debt_.high = _target_debt.high;
        }
    
        let (is_eq_) = uint256_eq(strategy_params_.current_debt, temp_new_debt_);
    
        with_attr error_message("new debt equals current debt"){
            assert is_eq_ = 0;
        }
    
        let (is_lt_) = uint256_lt(temp_new_debt_, strategy_params_.current_debt);
        let (this_) = get_contract_address();
        let (total_debt_) = total_debt.read();
        let (minimum_total_idle_) = minimum_total_idle.read();
        let (total_idle_) = total_idle.read();
        let (withdrawable_) = IStrategy.maxWithdraw(_strategy, this_);
        let (is_eq_) = uint256_eq(withdrawable_, Uint256(0,0));
        
        if(is_lt_ == 1){
            
            let (assets_to_withdraw_) = SafeUint256.sub_lt(strategy_params_.current_debt, temp_new_debt_);

            // Respect minimum total in vault
            let (sum_) = SafeUint256.add(assets_to_withdraw_, total_idle_);
            let (is_lt_) = uint256_lt(sum_, minimum_total_idle_);
    
            if(is_lt_ == 1){
                let (new_assets_to_withdraw_) = SafeUint256.sub_lt(minimum_total_idle_, total_idle_);
                let (is_lt_) = uint256_lt(strategy_params_.current_debt, new_assets_to_withdraw_);
                if(is_lt_ == 1){
                    temp_assets_to_withdraw_.low = strategy_params_.current_debt.low;
                    temp_assets_to_withdraw_.high = strategy_params_.current_debt.high;
                } else {
                    temp_assets_to_withdraw_.low = new_assets_to_withdraw_.low;
                    temp_assets_to_withdraw_.high = new_assets_to_withdraw_.high;
                }
                let (new_debt_) = SafeUint256.sub_le(strategy_params_.current_debt, temp_assets_to_withdraw_);
                temp_new_debt_.low = new_debt_.low;
                temp_new_debt_.high = new_debt_.high;
                tempvar range_check_ptr = range_check_ptr;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
            } else {
                tempvar range_check_ptr = range_check_ptr;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
            }
            
            
            with_attr error_message("nothing to withdraw"){
                assert is_eq_ = 0;
            }

            let (is_lt_) = uint256_lt(withdrawable_, temp_assets_to_withdraw_);
            let (new_debt_) = SafeUint256.sub_lt(strategy_params_.current_debt, withdrawable_);
            if(is_lt_ == 1){
                temp_assets_to_withdraw_.low = withdrawable_.low;
                temp_assets_to_withdraw_.high = withdrawable_.high;
                temp_new_debt_.low = new_debt_.low;
                temp_new_debt_.high = new_debt_.high;
                tempvar range_check_ptr = range_check_ptr;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
            } else {
                tempvar range_check_ptr = range_check_ptr;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
            }
    
            let (unrealised_losses_share_) = assess_share_of_unrealised_losses(_strategy, assets_to_withdraw_);
            let (is_eq_) = uint256_eq(unrealised_losses_share_, Uint256(0,0));
            with_attr error_message("strategy has unrealised losses"){
                assert is_eq_ = 1;
            }
            IStrategy.withdraw(_strategy, temp_assets_to_withdraw_, this_, this_);
            let (new_total_idle_) = SafeUint256.add(total_idle_, temp_assets_to_withdraw_);
            total_idle.write(new_total_idle_);
    
            let (is_le_) = uint256_le(total_debt_, temp_assets_to_withdraw_);
            tempvar temp_total_debt: Uint256;
            if(is_le_ == 1){
                temp_total_debt.low = 0;
                temp_total_debt.high = 0;
                tempvar range_check_ptr = range_check_ptr;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
            } else{
                let (new_total_debt_) = SafeUint256.sub_lt(total_debt_, temp_assets_to_withdraw_);
                temp_total_debt.low = new_total_debt_.low;
                temp_total_debt.high = new_total_debt_.high;
                tempvar range_check_ptr = range_check_ptr;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
            }
            total_debt.write(temp_total_debt);
            tempvar range_check_ptr = range_check_ptr;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
        } else{
            // Vault is increasing debt with the strategy by sending more funds
            let (max_deposit_) = IStrategy.maxDeposit(_strategy, this_);
            let (assets_to_transfer_) = SafeUint256.sub_le(temp_new_debt_, strategy_params_.current_debt);
            let (is_lt_) = uint256_lt(max_deposit_, assets_to_transfer_);

            tempvar temp_assets_to_transfer_: Uint256;
            if (is_lt_ == 1){
                temp_assets_to_transfer_.low = max_deposit_.low;
                temp_assets_to_transfer_.high = max_deposit_.high;
            } else {
                temp_assets_to_transfer_.low = assets_to_transfer_.low;
                temp_assets_to_transfer_.high = assets_to_transfer_.high;
            }

            let (is_le_) = uint256_lt(total_idle_, minimum_total_idle_);
            with_attr error_message("no funds to deposit"){
                assert is_le_ = 0;
            }      
            let (available_idle_) = SafeUint256.sub_lt(total_idle_, minimum_total_idle_);
    
            let (is_lt_) = uint256_lt(available_idle_, temp_assets_to_transfer_);
            if (is_lt_ == 1){
                temp_assets_to_transfer_.low = available_idle_.low;
                temp_assets_to_transfer_.high = available_idle_.high;
                tempvar range_check_ptr = range_check_ptr;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
            } else {
                tempvar range_check_ptr = range_check_ptr;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
            }

            let (is_lt_) = uint256_lt(Uint256(0,0), temp_assets_to_transfer_);
            if (is_lt_ == 1){
                let (asset_) = asset.read();
                IERC20.approve(asset_, _strategy, temp_assets_to_transfer_);
                IStrategy.deposit(_strategy, temp_assets_to_transfer_, this_);
                IERC20.approve(asset_, _strategy, Uint256(0,0));
                let (new_total_idle_) = SafeUint256.sub_lt(total_idle_, temp_assets_to_transfer_);
                let (new_total_debt_) = SafeUint256.add(total_debt_, temp_assets_to_transfer_);
                tempvar range_check_ptr = range_check_ptr;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
            } else {
                tempvar range_check_ptr = range_check_ptr;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
            }
    
            let (new_debt_) = SafeUint256.add(strategy_params_.current_debt, temp_assets_to_transfer_);
            temp_new_debt_.low = new_debt_.low;
            temp_new_debt_.high = new_debt_.high;
            tempvar range_check_ptr = range_check_ptr;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
        }
        strategies.write(_strategy, StrategyParams(strategy_params_.activation, strategy_params_.last_report, temp_new_debt_,  strategy_params_.max_debt));
        DebtUpdated.emit(_strategy, strategy_params_.current_debt, temp_new_debt_);
        return (temp_new_debt_,);
    }
    
    func loop_strategies{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _strategies_len: felt,
            _strategies: felt*,
            _previous_balance: Uint256,
            _requested_assets: Uint256,
            _assets_needed: Uint256,
            _curr_total_debt: Uint256,
            _curr_total_idle : Uint256,
            _this: felt,
            _asset: felt) -> (
            curr_total_debt : Uint256,
            curr_total_idle: Uint256,
            requested_assets: Uint256){
        //NOTE: the function returns the share of losses that a user should take if withdrawing from this strategy
        alloc_locals;
        if(_strategies_len == 0){
            return(_curr_total_debt, _curr_total_idle, _requested_assets);
        }
    
        let (strategy_params_) = strategies.read(_strategies[0]);
        let (is_eq_) = uint256_eq(Uint256(0,0), strategy_params_.activation);
        with_attr error_message("inactive strategy"){
            assert is_eq_ = 0;
        }
    
        let (unrealised_losses_share_) = assess_share_of_unrealised_losses(_strategies[0], _assets_needed);
        let (is_unrealised_losses_share_positive_) = uint256_lt(Uint256(0,0), unrealised_losses_share_);

        tempvar temp_assets_to_withdraw_: Uint256;
        tempvar temp_requested_assets_: Uint256;
        tempvar temp_assets_needed_: Uint256;
        tempvar temp_curr_total_debt_: Uint256;
        
        if(is_unrealised_losses_share_positive_ == 1){
            let (assets_to_withdraw_) = SafeUint256.sub_le(_assets_needed, unrealised_losses_share_);
            let (requested_assets_) = SafeUint256.sub_le(_requested_assets, unrealised_losses_share_);
            let (assets_needed_) = SafeUint256.sub_le(_assets_needed, unrealised_losses_share_);
            let (curr_total_debt_) = SafeUint256.sub_le(_curr_total_debt, unrealised_losses_share_);
            temp_assets_to_withdraw_.low = assets_to_withdraw_.low;
            temp_assets_to_withdraw_.high = assets_to_withdraw_.high;
            temp_requested_assets_.low = requested_assets_.low;
            temp_requested_assets_.high = requested_assets_.high;
            temp_assets_needed_.low = assets_needed_.low;
            temp_assets_needed_.high = assets_needed_.high;
            temp_curr_total_debt_.low = curr_total_debt_.low;
            temp_curr_total_debt_.high = curr_total_debt_.high;
            tempvar range_check_ptr = range_check_ptr;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
        } else{
            temp_assets_to_withdraw_.low = 0;
            temp_assets_to_withdraw_.high = 0;
            temp_requested_assets_.low = 0;
            temp_requested_assets_.high = 0;
            temp_assets_needed_.low = 0;
            temp_assets_needed_.high = 0;
            temp_curr_total_debt_.low = 0;
            temp_curr_total_debt_.high = 0;
            tempvar range_check_ptr = range_check_ptr;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
        }
    
        let (strategy_max_withdraw_) = IStrategy.maxWithdraw(_strategies[0], _this);
        let (is_lt_) = uint256_lt(strategy_max_withdraw_, temp_assets_to_withdraw_);
        if(is_lt_ == 1){
            temp_assets_to_withdraw_.low = strategy_max_withdraw_.low;
            temp_assets_to_withdraw_.high = strategy_max_withdraw_.high;
        } 
        let (expected_post_balance_) = SafeUint256.add(_previous_balance, temp_assets_to_withdraw_);
    
        let (is_nul_) = uint256_eq(Uint256(0,0), temp_assets_to_withdraw_);
        if(is_nul_ == 1){
            // continue to next strategy if nothing to withdraw
            return loop_strategies(
                    _strategies_len - 1,
                    _strategies + 1,
                    _previous_balance,
                    temp_requested_assets_,
                    temp_assets_needed_,
                    _curr_total_debt,
                    _curr_total_idle,
                    _this,
                    _asset,);
        } else {
            // WITHDRAW FROM STRATEGY
            IStrategy.withdraw(_strategies[0], temp_assets_to_withdraw_, _this, _this);
            let (post_balance_) = IERC20.balanceOf(_asset, _this);
            let (is_lt_) = uint256_lt(post_balance_, expected_post_balance_);
            tempvar temp_loss_: Uint256;
            if (is_lt_ == 1){
                let (loss_) = SafeUint256.sub_lt(expected_post_balance_, post_balance_);
                temp_loss_.low = loss_.low;
                temp_loss_.high = loss_.high;
                tempvar range_check_ptr = range_check_ptr;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
            } else {
                temp_loss_.low = 0;
                temp_loss_.high = 0;
                tempvar range_check_ptr = range_check_ptr;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
            }

            let (diff_) = SafeUint256.sub_lt(temp_assets_to_withdraw_, temp_loss_);
            let (curr_total_idle_) = SafeUint256.add(_curr_total_idle, diff_);
            let (requested_assets_) = SafeUint256.sub_lt(temp_requested_assets_, temp_loss_);
            let (curr_total_debt_) = SafeUint256.sub_lt(temp_curr_total_debt_, temp_assets_to_withdraw_);

            let (strategy_params_) = strategies.read(_strategies[0]);
            let (to_sub_) = SafeUint256.add(temp_assets_to_withdraw_, unrealised_losses_share_);
            let (new_debt_) = SafeUint256.sub_lt(strategy_params_.current_debt, to_sub_);
            let new_strategy_params_ = StrategyParams(strategy_params_.activation, strategy_params_.last_report, new_debt_, strategy_params_.max_debt);
            strategies.write(_strategies[0], new_strategy_params_);
            let (is_le_) = uint256_le(requested_assets_, curr_total_idle_);
            if (is_le_ == 1){
                return(curr_total_debt_, curr_total_idle_, requested_assets_,);
            } else{
                let (assets_needed_) = SafeUint256.sub_lt(temp_assets_needed_, temp_assets_to_withdraw_);
                return loop_strategies(
                        _strategies_len - 1,
                        _strategies + 1,
                        post_balance_,
                        requested_assets_,
                        assets_needed_,
                        curr_total_debt_,
                        curr_total_idle_,
                        _this,
                        _asset,);
            }   
        } 
    }
    
    func issue_shares_for_amount{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
            _amount: Uint256, 
            _recipient: felt) -> (shares_issued: Uint256){
            alloc_locals;
            let (new_shares_) = convert_to_shares(_amount);
            let (is_new_shares_nul_) = uint256_eq(new_shares_, Uint256(0,0));
    
            //  We don't make the function revert
            if (is_new_shares_nul_ == 1){
                return (Uint256(0,0),);
            }
    
            ERC20._mint(_recipient, _amount);
            return (_amount,);
    }
    
    func get_unlocked_profit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            ) -> (unlocked_profit: Uint256){
            alloc_locals;
        let (profit_distribution_rate_) = profit_distribution_rate.read();
        let (is_eq_) = uint256_eq(profit_distribution_rate_, Uint256(0,0));
        //If profit_distribution_rate is equal to zero, there is no profit to unlock, otherwise we compute it
        if(is_eq_ == 1){
            return(Uint256(0,0),);
        }
        let (profit_end_date_) = profit_end_date.read();
        let (profit_last_update_) = profit_last_update.read();
        let (block_timestamp_) = get_block_timestamp();
        let (is_lt_) = uint256_lt(Uint256(block_timestamp_,0),profit_end_date_);
        tempvar temp_unlocked_profit_: Uint256;
        if(is_lt_ == 1){
            let (step1_) = SafeUint256.sub_lt(Uint256(block_timestamp_,0), profit_last_update_);
            let (step2_) = SafeUint256.mul(step1_, profit_distribution_rate_);
            let (unlocked_profit_,_) = SafeUint256.div_rem(step2_, Uint256(MAX_BPS,0));
            temp_unlocked_profit_.low = unlocked_profit_.low;
            temp_unlocked_profit_.high = unlocked_profit_.high;
            profit_last_update.write(Uint256(block_timestamp_,0));
        } else{
            let (step1_) = SafeUint256.sub_lt(profit_end_date_, profit_last_update_);
            let (step2_) = SafeUint256.mul(step1_, profit_distribution_rate_);
            let (unlocked_profit_,_) = SafeUint256.div_rem(step2_, Uint256(MAX_BPS,0));
            temp_unlocked_profit_.low = unlocked_profit_.low;
            temp_unlocked_profit_.high = unlocked_profit_.high;
            profit_distribution_rate.write(Uint256(0,0));
        }
        return (temp_unlocked_profit_,);
    }
    
    func assess_share_of_unrealised_losses{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
            _strategy: felt,
            _assets_needed : Uint256) -> (losses_user_share : Uint256){
        //NOTE: the function returns the share of losses that a user should take if withdrawing from this strategy
        alloc_locals;
        let (strategy_params_) = strategies.read(_strategy);
        let (are_assets_needed_exceed_debt_) = uint256_le(strategy_params_.current_debt, _assets_needed);
        tempvar temp_assets_to_withdraw_: Uint256;
        if(are_assets_needed_exceed_debt_ == 1){
            temp_assets_to_withdraw_.low = strategy_params_.current_debt.low;
            temp_assets_to_withdraw_.high = strategy_params_.current_debt.high;
        } else{
            temp_assets_to_withdraw_.low = _assets_needed.low;
            temp_assets_to_withdraw_.high = _assets_needed.high;
        }
        let (this_) = get_contract_address();
        let (vault_shares_) = IStrategy.balanceOf(_strategy, this_);
        let (strategy_assets_) =  IStrategy.convertToAssets(_strategy, vault_shares_);
    
        // If no losses, return 0
        let (is_strategy_current_debt_nul_) = uint256_eq(Uint256(0,0), strategy_params_.current_debt);
        let (is_strategy_current_debt_lt_strategy_assets_) = uint256_le(strategy_params_.current_debt, strategy_assets_);
    
        if(is_strategy_current_debt_nul_ + is_strategy_current_debt_lt_strategy_assets_ != 0){
            return(Uint256(0,0),);
        }
    
        // user will withdraw assets_to_withdraw divided by loss ratio (strategy_assets / strategy_current_debt - 1)
        // but will only receive assets_to_withdrar
        // NOTE: if there are unrealised losses, the user will take his share
    
        let (step1_) = SafeUint256.mul(temp_assets_to_withdraw_, strategy_assets_);
        let (step2_,_) = SafeUint256.div_rem(step1_, strategy_params_.current_debt);
        let (losses_user_share_) = SafeUint256.sub_lt(temp_assets_to_withdraw_, step2_);
        return (losses_user_share_,);
    }
    
    
    func mul_div_down{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(x: Uint256, y: Uint256, denominator: Uint256) -> (z: Uint256){
        alloc_locals;
        let (prod) = SafeUint256.mul(x, y);
        let (q2, _) = SafeUint256.div_rem(prod, denominator);
        return (q2,);
    }
    
    // Computes base^exp.
    func pow{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(base : felt, exp : felt) -> (res: felt){
        alloc_locals;
        if (exp == 0){
            return (1,);
        }
        let (res) = pow(base, exp - 1);
        return (res * base,);
    }


}
