%lang starknet

from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.cairo.common.uint256 import ALL_ONES, Uint256, uint256_check, uint256_eq, uint256_lt, uint256_le, uint256_add, uint256_sub, uint256_mul, uint256_unsigned_div_rem
from starkware.cairo.common.math import assert_not_zero, assert_le

from openzeppelin.token.erc20.library import ERC20, ERC20_allowances
from openzeppelin.token.erc20.IERC20 import IERC20
from openzeppelin.security.reentrancyguard.library import ReentrancyGuard 
from openzeppelin.security.pausable.library import Pausable 


from utils.safeerc20 import SafeERC20
from interfaces.IRegistery import IStrategy

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

const ALL_ONES = 2 ** 128 - 1; 

const MAX_BPS = 10000

const API_VERSION = 73839733893

const DOMAIN_TYPE_HASH = 73839733893

const PERMIT_TYPE_HASH = 73839733893


// ENUM NOT LIVE YET 
const STRATEGY_MANAGER = 0
const DEBT_MANAGER = 1
const EMERGENCY_MANAGER = 2
const ACCOUNTING_MANAGER = 3


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
func profit_last_update() -> (profit_last_update : felt){
}

@storage_var
func profit_distribution_rate() -> (profit_distribution_rate : Uint256){
}

@storage_var
func prodit_max_unlock_time() -> (prodit_max_unlock_time: felt){
}

// Constructor
@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _role_manager: felt,
        _asset : felt,
        _name : felt,
        _symbol : felt,
        _profit_max_unlock_time: felt,
        ){
        let (decimals_) = IERC20.decimals(_asset);
        ERC20.initializer(_name, _symbol, decimals_);
        asset.write(_asset);
        role_manager.write(_role_manager);
        profit_max_unlock_time.write(_profit_max_unlock_time);
        shutdown.write(FALSE)
        let (block_timestamp_) = get_block_timestamp();
        profit_last_update.write(block_timestamp_);
        profit_end_date.write(block_timestamp_);
    return ();
}


//SHARE MANAGEMENT 


@external
func pause{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    assert_only_configurator();
    Pausable.assert_not_paused();
    Pausable._pause();
    return();
}

@external
func unpause{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    assert_only_configurator();
    Pausable.assert_paused();
    Pausable._unpause();
    return();
}

@external
func freezeBorrow{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    assert_only_configurator();
    assert_borrow_not_frozen();
    borrow_frozen.write(TRUE);
    BorrowFrozen.emit();
    return ();
}

@external
func unfreezeBorrow{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    assert_only_configurator();
    assert_borrow_frozen();
    borrow_frozen.write(FALSE);
    BorrowUnfrozen.emit();
    return ();
}

@external
func freezeRepay{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    assert_only_configurator();
    assert_repay_not_frozen();
    repay_frozen.write(TRUE);
    repayFrozen.emit();
    return ();
}

@external
func unfreezerepay{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    assert_only_configurator();
    assert_repay_frozen();
    repay_frozen.write(FALSE);
    let (caller_) = get_caller_address();
    repayUnfrozen.emit();
    return ();
}


@external
func setWithdrawFee{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(_base_withdraw_fee: Uint256) {
    assert_only_configurator();
    let (is_allowed_amount1_) = uint256_le(_base_withdraw_fee, Uint256(PRECISION,0));
    let (is_allowed_amount2_) = uint256_le(Uint256(0,0), _base_withdraw_fee);
    with_attr error_message("0 <= withdrawFee <= 1.000.000"){
        assert is_allowed_amount1_ * is_allowed_amount2_ = 1;
    }
    base_withdraw_fee.write(_base_withdraw_fee);
    NewWithdrawFee.emit(_base_withdraw_fee);
    return ();
}



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
    with_attr error_message("invalid recipient"){
        assert (_recipient - this_) * _recipient != 0;
    }
    // If the amount is max_value(uint256) we assume the user wants to deposit their whole balance
    let (is_max_uint256_) = uint256_eq(_assets, Uint256(ALL_ONES,ALL_ONES));
    let (asset_) = asset.read();
    if(is_max_uint256_ == 1){
        let (user_balance_) = IERC20.balanceOf(asset_, _sender);
        let assets_ = user_balance_;
    else{
        let assets_ = _assets;
    }

    // Why original version doesn't use maxdeposit function
    let (max_assets_) = maxDeposit(_sender);
    let (is_allowed_amount_) = uint256_le(assets_, max_assets_);

    let (shares_) = issue_shares_for_amount(assets_, _recipient);
    let (is_shares_nul_) = uint256_lt(Uint256(0,0), shares_);

    with_attr error_message("cannot mint zero"){
        assert is_shares_nul_ == 0;
    }

    // why original version use msg.sender better than sender param?
    SafeERC20.transferFrom(asset_, _sender, _recipient, assets_)
    let (total_idle_) = total_idle.read();
    let (new_total_idle_,_) = uint256_add(total_idle_, assets_);
    total_idle.write(new_total_idle_);

    ReentrancyGuard._end();
    Deposit.emit(_sender, _recipient, assets_, shares_);
    return (shares_,);
}

func assess_share_of_unrealised_losses{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _strategy: felt,
        _assets_needed : Uint256) -> (losses_user_share : Uint256){
    //NOTE: the function returns the share of losses that a user should take if withdrawing from this strategy
    alloc_locals;
    let (strategy_current_debt_) = strategies.read(_strategy).current_debt;
    let (are_assets_needed_exceed_debt_) = uint256_le(strategy_current_debt_, _assets_needed);
    if(are_assets_needed_exceed_debt_ == 1){
        let assets_to_withdraw_ = strategy_current_debt_;
    else{
        let assets_to_withdraw_ = _assets_needed;
    }
    let (this_) = get_contract_address();
    let (vault_shares_) = IStrategy.balanceOf(_strategy, this_);
    let (strategy_assets_) =  IStrategy.convertToAssets(_strategy, vault_shares_);

    // If no losses, return 0
    let (is_strategy_current_debt_nul_) = uint256_eq(Uint256(0,0), strategy_current_debt_);

    uint256_check(_assets);
    ReentrancyGuard._start();
    let (shutdown_) = shutdown.read();
    with_attr error_message("vault is down"){
        assert shutdown_ = FALSE;
    }
    let (this_) = get_contract_address();
    with_attr error_message("invalid recipient"){
        assert (_recipient - this_) * _recipient != 0;
    }
    // If the amount is max_value(uint256) we assume the user wants to deposit their whole balance
    let (is_max_uint256_) = uint256_eq(_assets, Uint256(ALL_ONES,ALL_ONES));
    let (asset_) = asset.read();
    if(is_max_uint256_ == 1){
        let (user_balance_) = IERC20.balanceOf(asset_, _sender);
        let assets_ = user_balance_;
    else{
        let assets_ = _assets;
    }

    // Why original version doesn't use maxdeposit function
    let (max_assets_) = maxDeposit(_sender);
    let (is_allowed_amount_) = uint256_le(assets_, max_assets_);

    let (shares_) = issue_shares_for_amount(assets_, _recipient);
    let (is_shares_nul_) = uint256_lt(Uint256(0,0), shares_);

    with_attr error_message("cannot mint zero"){
        assert is_shares_nul_ == 0;
    }

    // why original version use msg.sender better than sender param?
    SafeERC20.transferFrom(asset_, _sender, _recipient, assets_)
    let (total_idle_) = total_idle.read();
    let (new_total_idle_,_) = uint256_add(total_idle_, assets_);
    total_idle.write(new_total_idle_);

    ReentrancyGuard._end();
    Deposit.emit(_sender, _recipient, assets_, shares_);
    return (shares_,);
}


@external
func redeem{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _shares : Uint256, _receiver : felt, _owner : felt) -> (assets : Uint256){
    alloc_locals;
    ReentrancyGuard._start();

    let (assets_) = convertToAssets(_shares);
    let (withdraw_fee_) = withdrawFee();
    let (treasury_fee_) = uint256_permillion(assets_, withdraw_fee_);
    let (remaining_assets_) = uint256_sub(assets_, treasury_fee_);
    let (treasury_) = treasury();

    with_attr error_message("ERC4626: cannot reedem for 0 assets"){
        let (shares_is_zero) = uint256_eq(_shares, Uint256(0, 0));
        assert shares_is_zero = FALSE;
    }

    let (max_reedem_) = maxRedeem(_receiver);
    let (is_limit_not_exceeded_) = uint256_le(_shares, max_reedem_);
    with_attr error_message("amount exceeds max deposit "){
        assert is_limit_not_exceeded_ = 1;
    }

    with_attr error_message("Zero address not allowed"){
        assert_not_zero(_receiver * _owner);
    }

    let (caller_) = get_caller_address();
    ERC20_decrease_allowance_manual(_owner, caller_, _shares);
    ERC20._burn(_owner, _shares);

    let (ERC4626_asset_) = ERC4626_asset.read();
    SafeERC20.transfer(ERC4626_asset_, _receiver, remaining_assets_);
    SafeERC20.transfer(ERC4626_asset_, treasury_, treasury_fee_);

    let (expected_liquidity_) = expected_liquidity_last_update.read();
    let (new_expected_liqudity_) = uint256_sub(expected_liquidity_, assets_);
    expected_liquidity_last_update.write(new_expected_liqudity_);
    update_borrow_rate(Uint256(0,0));

    ReentrancyGuard._end();
    Withdraw.emit(_owner, _receiver, assets_, _shares);
    return (assets_,);
}



//
// VIEW
//

@view
func asset{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (asset : felt){
    let (read_asset : felt) = ERC4626_asset.read();
    return(read_asset,);
}

@view
func maxDeposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(_receiver: felt) -> (maxAssets : Uint256){
    let (total_assets_) = totalAssets();
    let (deposit_limit_) = deposit_limit.read();
    let (is_limit_exceeded_) = uint256_le(deposit_limit_, total_assets_);
    if(is_limit_exceeded_ == 1){
        return(Uint256(0,0));
    else{
        let (diff_) = uint256_sub(deposit_limit_, total_assets_);
        return(diff_)
    }
}

@view
func maxMint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(_receiver: felt) -> (maxShares : Uint256){
    let (max_deposit_) = maxDeposit(_receiver);
    let (max_shares_) = convertToShares(max_deposit_);
    return(max_shares_);
}

@view
func maxRedeem{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _owner : felt) -> (maxShares : Uint256){
    let (balance_of_owner_) = balanceOf(_owner);
    let (total_idle_) = total_idle.read();
    let (total_idle_to_shares_) = convertToShares(total_idle_);
    let (is_vault_enough_funds_) = uint256_le(balance_of_owner_,total_idle_to_shares_);
    if(is_vault_enough_funds_ == 1){
        return(balance_of_owner_);
    else{
        return(total_idle_to_shares_);
    }
}

@view
func maxWithdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(_owner: felt) -> (maxAssets : Uint256){
    let (max_reedem_) = maxRedeem(_owner);
    let (max_assets_) = convertToAssets(max_reedem_);
    return(max_assets_);
}



@view
func previewDeposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _assets : Uint256) -> (shares : Uint256){
    return convertToShares(_assets);
}


@view
func previewMint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _shares : Uint256) -> (assets : Uint256){
    return convertToAssets(_shares);
}

@view
func previewWithdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(_assets : Uint256) -> (shares : Uint256){
    alloc_locals;
    let (withdraw_fee_) = withdrawFee();
    let (treasury_fee_) = uint256_permillion(_assets, withdraw_fee_);
    let (remaining_assets_) = uint256_sub(_assets, treasury_fee_);
    return convertToShares(remaining_assets_);
}

@view
func previewRedeem{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(_shares : Uint256) -> (assets : Uint256){
    alloc_locals;
    let (assets_) = convertToAssets(_shares);
    let (withdraw_fee_) = withdrawFee();
    let (treasury_fee_) = uint256_permillion(assets_, withdraw_fee_);
    let (remaining_assets_) = uint256_sub(assets_, treasury_fee_);
    return (remaining_assets_,);
}

@view
func convertToShares{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(_assets : Uint256) -> (shares : Uint256){
    alloc_locals;
    with_attr error_message("ERC4626: assets is not a valid Uint256"){
        uint256_check(_assets);
    }

    let (supply_) = ERC20.total_supply();
    let (all_assets) = totalAssets();
    let (supply_is_zero) = uint256_eq(supply_, Uint256(0, 0));
    if (supply_is_zero == TRUE) {
        return (_assets,);
    }
    let (shares_) = mul_div_down(_assets, supply_, all_assets);
    return (shares_,);
}

@view
func convertToAssets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(_shares : Uint256) -> (assets : Uint256){
    alloc_locals;
    with_attr error_message("ERC4626: shares is not a valid Uint256"){
        uint256_check(_shares);
    }

    let (supply_) = ERC20.total_supply();
    let (all_assets_) = totalAssets();
    let (supply_is_zero) = uint256_eq(supply_, Uint256(0, 0));
    if(supply_is_zero == TRUE){
        return (_shares,);
    }
    let (assets_) = mul_div_down(_shares, all_assets_, supply_);
    return (assets_,);
}


@view
func totalAssets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (totalAssets : Uint256){
    alloc_locals;
    let (total_idle_) = total_idle.read();
    let (total_debt_) = total_debt.read();
    let (total_assets_,_) = uint256_add(total_idle_, total_debt_);
    return (total_assets_,);
}

@view
func totalBorrowed{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (totalBorrowed : Uint256){
    let (total_borrowed_) = total_borrowed.read();
    return (total_borrowed_,);
}

@view
func borrowRate{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (borrowRate : Uint256){
    let (borrow_rate_) = borrow_rate.read();
    return (borrow_rate_,);
}

@view
func cumulativeIndex{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (borrowRate : Uint256){
    let (cumulative_index_) = cumulative_index.read();
    let (new_cumulative_index_) = calculLinearCumulativeIndex(cumulative_index_)
    return (new_cumulative_index_,);
}

@view
func lastUpdatedTimestamp{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (lastUpdatedTimestamp : felt){
    let (last_updated_timestamp_) = last_updated_timestamp.read();
    return (last_updated_timestamp_,);
}

@view
func expectedLiquidityLastUpdate{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (expectedLiquidityLastUpdate : Uint256){
    let (expected_liquidity_last_update_) = expected_liquidity_last_update.read();
    return (expected_liquidity_last_update_,);
}

@view
func expectedLiquidityLimit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (lastUpdatedTimestamp : Uint256){
    let (expected_liquidity_limit_) = expected_liquidity_limit.read();
    return (expected_liquidity_limit_,);
}

//
// INTERNALS
//

func ERC20_decrease_allowance_manual{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(_owner: felt, _spender: felt, subtracted_value: Uint256) -> (){
        alloc_locals;

        // This is vault logic, we place it here to avoid revoked references at callsite
        if (_spender == _owner){
            return ();
        }

        // This is decrease_allowance, but edited
        with_attr error_message("ERC20: subtracted_value is not a valid Uint256"){
            uint256_check(subtracted_value);
        }

        let (current_allowance: Uint256) = ERC20_allowances.read(_owner, _spender);

        with_attr error_message("ERC20: allowance below zero"){
            let (new_allowance: Uint256) = uint256_sub(current_allowance, subtracted_value);
        }

        ERC20._approve(_owner, _spender, new_allowance);
        return ();
}

func ERC20_decrease_allowance_manual{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(_owner: felt, _spender: felt, subtracted_value: Uint256) -> (){
        alloc_locals;

        // This is vault logic, we place it here to avoid revoked references at callsite
        if (_spender == _owner){
            return ();
        }

        // This is decrease_allowance, but edited
        with_attr error_message("ERC20: subtracted_value is not a valid Uint256"){
            uint256_check(subtracted_value);
        }

        let (current_allowance: Uint256) = ERC20_allowances.read(_owner, _spender);

        with_attr error_message("ERC20: allowance below zero"){
            let (new_allowance: Uint256) = uint256_sub(current_allowance, subtracted_value);
        }

        ERC20._approve(_owner, _spender, new_allowance);
        return ();
}

func issue_shares_for_amount{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        _amount: Uint256, 
        _recipient: felt) -> (shares_issued: Uint256){
        alloc_locals;
        let (new_shares_) = convertToShares(_amount)
        let (is_new_shares_nul_) = uint256_eq(new_shares_, Uint256(0,0));

        //  We don't make the function revert
        if (is_new_shares_nul_ == 1){
            return (Uint256(0,0));
        }

        erc20._mint(_recipient, _amount);
        return (_amount);
}





// ERC 20 STUFF

// Getters

@view
func name{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (name : felt){
    let (name_) = ERC20.name();
    return (name_,);
}

@view
func symbol{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (symbol : felt){
    let (symbol_) = ERC20.symbol();
    return (symbol_,);
}

@view
func totalSupply{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        totalSupply : Uint256){
    let (totalSupply_ : Uint256) = ERC20.total_supply();
    return (totalSupply_,);
}

@view
func decimals{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        decimals : felt){
    let (decimals_) = ERC20.decimals();
    return (decimals_,);
}

@view
func balanceOf{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        account : felt) -> (balance : Uint256){
    let (balance_ : Uint256) = ERC20.balance_of(account);
    return (balance_,);
}

@view
func allowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _owner : felt, _spender : felt) -> (remaining : Uint256){
    let (remaining_ : Uint256) = ERC20.allowance(_owner, _spender);
    return (remaining_,);
}

// Externals

@external
func transfer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        recipient : felt, amount : Uint256) -> (success : felt){
    ERC20.transfer(recipient, amount);
    return (TRUE,);
}

@external
func transferFrom{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        sender : felt, recipient : felt, amount : Uint256) -> (success : felt){
    ERC20.transfer_from(sender, recipient, amount);
    return (TRUE,);
}

@external
func approve{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _spender : felt, amount : Uint256) -> (success : felt){
    ERC20.approve(_spender, amount);
    return (TRUE,);
}

@external
func increaseAllowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _spender : felt, added_value : Uint256) -> (success : felt){
    ERC20.increase_allowance(_spender, added_value);
    return (TRUE,);
}

@external
func decreaseAllowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _spender : felt, subtracted_value : Uint256) -> (success : felt){
    ERC20.decrease_allowance(_spender, subtracted_value);
    return (TRUE,);
}