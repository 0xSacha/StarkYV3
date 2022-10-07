%lang starknet

from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.cairo.common.uint256 import ALL_ONES, Uint256, uint256_check, uint256_eq, uint256_lt, uint256_le
from starkware.cairo.common.math_cmp import is_le, 
from openzeppelin.token.erc20.library import ERC20, ERC20_allowances
from openzeppelin.token.erc20.IERC20 import IERC20
from openzeppelin.security.reentrancyguard.library import ReentrancyGuard 
from openzeppelin.security.pausable.library import Pausable 
from openzeppelin.security.safemath.library import SafeUint256 



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
    activation: felt,
    last_report: Uint256,
    current_debt: Uint256,
    max_debt: Uint256,
}

// CONSTANTS

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
func profit_last_update() -> (profit_last_update : Uint256){
}

@storage_var
func profit_distribution_rate() -> (profit_distribution_rate : Uint256){
}

@storage_var
func profit_max_unlock_time() -> (profit_max_unlock_time: Uint256){
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
    let (new_total_idle_) = safemath.add(total_idle_, assets_);
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
    let (strategy_assets_) =  IStrategy.convert_to_assets(_strategy, vault_shares_);

    // If no losses, return 0
    let (is_strategy_current_debt_nul_) = uint256_eq(Uint256(0,0), strategy_current_debt_);
    let (is_strategy_current_debt_lt_strategy_assets_) = uint256_le(strategy_current_debt_, strategy_assets_);

    if(is_strategy_current_debt_nul_ + is_strategy_current_debt_lt_strategy_assets_ != 0){
        return(Uint256(0,0));
    }

    // user will withdraw assets_to_withdraw divided by loss ratio (strategy_assets / strategy_current_debt - 1)
    // but will only receive assets_to_withdrar
    // NOTE: if there are unrealised losses, the user will take his share

    let (step1_) = safemath.mul(assets_to_withdraw, strategy_assets_);
    let (step2_,_) = safemath.div_rem(step1_, strategy_current_debt_);
    let (losses_user_share_) = safemath.sub_lt(assets_to_withdraw, step2_);
    return (losses_user_share_,);
}

func redeem{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _sender: felt, 
        _receiver : felt, 
        _owner : felt, 
        _shares_to_burn: Uint256, 
        _strategies_len: felt, 
        _strategies: felt*) -> (assets : Uint256){
    alloc_locals;
    ReentrancyGuard._start();
    uint256_check(_shares_to_burn);
    if(_sender != _owner){
        ERC20._spend_allowance(_owner, _sender, _shares_to_burn);
    }

    let (is_max_uint256_) = uint256_eq(_shares_to_burn, Uint256(ALL_ONES,ALL_ONES));
    if(is_max_uint256_ == 1){
        let (user_balance_) = balanceOf(_owner);
        let shares_ = user_balance_;
    else{
        let shares_ = _shares_to_burn;
    }
    // assert shares_balance >= shares, "insufficient shares to redeem" why knowing burn will revert if balance not enough
    let (is_shares_positive_) = uint256_lt(Uint256(0,0),shares_)

    with_attr error_message("no shares to redeem"){
        assert is_shares_positive_ = 1;
    }

    let (temp_requested_assets_) = convert_to_assets(shares_);
    let (temp_total_idle_) = total_idle.read();

    let (is_requested_assets_exceed_total_idle_) = uint256_lt(temp_total_idle_, temp_requested_assets_);
    let (asset_) = asset.read();
    if(is_requested_assets_exceed_total_idle_ == 1){
        let (total_debt_) = total_debt.read();
        let (profit_distribution_rate_) = profit_distribution_rate.read();
        let (profit_last_update_) = profit_last_update.read();
        let (profit_end_date_) = profit_end_date.read();
        let (block_timestamp_) = get_block_timestamp();
        let (is_block_timestamp_lt_profit_end_date_) = uint256_lt(Uint256(block_timestamp_,0),profit_end_date_);
        if(is_block_timestamp_lt_profit_end_date_ == 1){
            let (step1_) = safemath.sub_lt(Uint256(block_timestamp_,0), profit_last_update_)
            let (step2_) = safemath.mul(step1_, profit_distribution_rate_);
            let (unlocked_profit_) = safemath.div_rem(step2_, Uint256(MAX_BPS,0));
            // we update last update time as profit is unlocked and will be added to storage debt afterwards
            profit_last_update.write(Uint256(block_timestamp_,0));
        else{
            let (step1_) = safemath.sub_lt(profit_end_date_, profit_last_update_);
            let (step2_) = safemath.mul(step1_, profit_distribution_rate_);
            let (unlocked_profit_) = safemath.div_rem(step2_, Uint256(MAX_BPS,0));
            profit_distribution_rate.write(Uint256(0,0));
        }
        let (curr_total_debt_) = safemath.add(curr_total_debt_, unlocked_profit_);
        let (assets_needed_) = safemath.sub_lt(temp_requested_assets_, temp_total_idle_);
        let (this_) = get_contract_address();
        let (previous_balance_) = IERC20.balanceOf(asset_, this_);
        let (new_total_debt_, total_idle_, requested_assets_) = loop_strategies(
                _strategies_len,
                _strategies,
                previous_balance_,
                temp_requested_assets_,
                assets_needed_,
                curr_total_debt_,
                total_idle_,
                this_,
                asset_);
        let (is_le_) = uint256_le(requested_assets_, curr_total_idle_);
        with_attr error_message("insufficient assets in vault"){
            assert is_le_ = 1;
        }
        total_debt.write(new_total_debt_);
    else{
        let requested_assets_ = temp_requested_assets_;
        let total_idle_ = temp_total_idle_;
    }
    ERC20._burn(shares_, _owner);
    let (new_total_idle_) = uint256_le(total_idle_, requested_assets_);
    total_idle.write(new_total_idle_);
    safeerc20.transfer(asset_, _receiver, requested_assets_);
    ReentrancyGuard._end();
    Withdraw.emit(_owner, _receiver, requested_assets_, shares_);
    return (assets_, );
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
    let (is_strategy_activated_) = strategies.read(_strategies[0]);
    with_attr error_message("inactive strategy"){
        assert is_strategy_activated_ = 1;
    }

    let (unrealised_losses_share_) = assess_share_of_unrealised_losses(_strategies[0], _assets_needed);
    let (is_unrealised_losses_share_positive_) = uint256_lt(Uint256(0,0), unrealised_losses_share_);
    
    if(is_unrealised_losses_share_positive_ == 1){
        let (temp_assets_to_withdraw_) = safemath.sub_le(_assets_needed, unrealised_losses_share_);
        let (temp_requested_assets_) = safemath.sub_le(_requested_assets, unrealised_losses_share_);
        let (temp_assets_needed_) = safemath.sub_le(_assets_needed, unrealised_losses_share_);
        let (temp_curr_total_debt_) = safemath.sub_le(_curr_total_debt, unrealised_losses_share_);
    else{
        let temp_assets_to_withdraw_ = _assets_needed;
        let temp_requested_assets_ = _requested_assets;
        let temp_assets_needed_ = _assets_needed;
        let temp_curr_total_debt_ = _curr_total_debt;
    }

    let (strategy_max_withdraw_) = IStrategy.maxWithdraw(_strategies[0], _this);
    let (is_lt_) = uint256_lt(strategy_max_withdraw_, temp_assets_to_withdraw_);
    if(is_lt_ == 1){
        let assets_to_withdraw_ = strategy_max_withdraw_;
    else{
        let assets_to_withdraw_ = temp_assets_to_withdraw_;
    }

    // continue to next strategy if nothing to withdraw
    let (is_nul_) = uint256_eq(Uint256(0,0), assets_to_withdraw_);
    if(is_nul_ == 1{
        return loop_strategies(
                _strategies_len - 1,
                _strategies + 1,
                _previous_balance,
                temp_requested_assets_,
                temp_assets_needed_,
                _curr_total_debt,
                _curr_total_idle,
                _this,
                _asset);
    }

    // WITHDRAW FROM STRATEGY
    IStrategy.withdraw(_strategies[0], assets_to_withdraw_, _this, _this);
    let (post_balance_) = IERC20.balanceOf(_asset, _this);
    let (expected_post_balance_) = safemath.add(_previous_balance, assets_to_withdraw_);

    let (is_lt_) = uint256_lt(post_balance_, expected_post_balance_);
    if (is_lt_ == 1){
        let (loss_) = safemath.sub_lt(expected_post_balance_, post_balance_);
    else {
        let (loss_) = Uint256(0,0);
    }

    let (previous_balance_) = post_balance_;

    let (diff_) = safemath.sub_lt(assets_to_withdraw_, loss);
    let (curr_total_idle_) = safemath.add(_curr_total_idle, diff_);
    let (requested_assets_) = safemath.sub_lt(temp_requested_assets_, loss);
    let (curr_total_debt_) = safemath.sub_lt(temp_curr_total_debt_, assets_to_withdraw_);

    let (strategy_params_) = strategies.read(_strategies[0])
    let (to_sub_) = safemath.add(assets_to_withdraw_, loss_);
    let (new_debt_) = safemath.sub_lt(strategy_params_.current_debt, to_sub_);
    let (new_strategy_params_) = StrategyParams(strategy_params_.activation, strategy_params_.last_report, new_debt_, strategy_params_.max_debt);

    let (is_le_) = uint256_le(requested_assets_, curr_total_idle_);
    if (is_le_ == 1){
        return(curr_total_debt_, curr_total_idle_, requested_assets_);
    else{
        let (assets_needed_) = safemath.sub_lt(temp_assets_needed_, assets_to_withdraw_);
        return loop_strategies(
                _strategies_len - 1,
                _strategies + 1,
                previous_balance_,
                requested_assets_,
                assets_needed_,
                curr_total_debt_,
                curr_total_idle_,
                _this,
                _asset);
    }    
}

func add_strategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _new_strategy : felt){
    with_attr error_message("strategy cannot be zero address"){
        assert _new_strategy != 0;
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

    let (is_active_) = strategies.read(_new_strategy).activation;
    with_attr error_message("strategy already active"){
        assert is_active_ = 0;
    }
    let (block_timestamp_) = get_block_timestamp();
    let (strategy_params_) = StrategyParams(Uint256(block_timestamp_,0),Uint256(block_timestamp_,0),Uint256(0,0), Uint256(0,0));

    StrategyAdded.emit(_new_strategy);
    return ();
}

func revoke_strategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _old_strategy : felt){
    
    let (is_active_) = strategies.read(_old_strategy).activation;
    with_attr error_message("strategy not active"){
        assert is_active_ = 1;
    }

    let (has_debt_) = strategies.read(_old_strategy).current_debt;
    with_attr error_message("strategy has debt"){
        assert has_debt_ = 0;
    }

    let (strategy_params_nul_) = StrategyParams(Uint256(0,0),Uint256(0,0),Uint256(0,0),Uint256(0,0));
    strategies(_old_strategy).write(strategy_params_nul_);
    StrategyRevoked.emit(_old_strategy);
    return ();
}

func migrate_strategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _new_strategy : felt,
        _old_strategy : felt){

    let (is_active_) = strategies.read(_old_strategy).activation;
    with_attr error_message("strategy not active"){
        assert is_active_ = 1;
    }

    let (has_debt_) = strategies.read(_old_strategy).current_debt;
    with_attr error_message("strategy has debt"){
        assert has_debt_ = 0;
    }

    with_attr error_message("strategy cannot be zero address"){
        assert _new_strategy != 0;
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

    let (is_active_) = strategies.read(_new_strategy).activation;
    with_attr error_message("strategy already active"){
        assert is_active_ = 0;
    }

    let (old_strategy_params_) = strategies.read(_old_strategy);
    let (block_timestamp_) =get_block_timestamp();
    let (new_strategy_params_) = StrategyParams(Uint256(block_timestamp_,0),Uint256(block_timestamp_,0), old_strategy_params_.curr_total_debt,old_strategy_params_.max_debt);
    strategies(_new_strategy).write(new_strategy_params_);
    revoke_strategy(_old_strategy);
    StrategyMigrated.emit(_old_strategy, _new_strategy);
    return ();
}

func update_debt{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _strategy : felt,
        _target_debt: Uint256){

    //     The vault will rebalance the debt vs target debt. Target debt must be smaller or equal strategy max_debt.
    //     This function will compare the current debt with the target debt and will take funds or deposit new 
    //     funds to the strategy. 
    //     The strategy can require a minimum (or a maximum) amount of funds that it wants to receive to invest. 
    //     The strategy can also reject freeing funds if they are locked.
    //     The vault will not invest the funds into the underlying protocol, which is responsibility of the strategy. 
    
    let (strategy_max_debt_) = strategies.read(_strategy).max_debt;
    let (is_le_) = uint256_le(_target_debt, strategy_max_debt_);
    with_attr error_message("target debt higher than max debt"){
        assert is_le_ = 1;
    }

    let (shutdown_) = shutdown.read();
    if(shutdown_ == 1){
        let (new_debt_) = Uint256(0,0);
    else{
        let (new_debt_) = _target_debt;
    }

    let (strategy_current_debt_) = strategies.read(_strategy).current_debt;
    let (is_eq_) = uint256_eq(strategy_current_debt_, new_debt_);
    with_attr error_message("target debt higher than max debt"){
        assert is_le_ = 1;
    }

    let (is_lt_) = uint256_lt(new_debt_, strategy_current_debt_);
    if(is_lt_ == 1){
        let (assets_to_withdraw_) = uint256_lt(strategy_current_debt_, new_debt_);
        let (minimum_total_idle_) = minimum_total_idle.read();
        let (total_idle_) = total_idle.read();

        // Respect minimum total idle in vault
        let (sum_) = safemath.add(assets_to_withdraw_, total_idle_);
        let (is_lt_) = uint256_lt(sum_, minimum_total_idle_);
        if(is_lt_ == 1){

        }


    else{


    }
    return ();
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
    let (max_assets_) = convert_to_assets(max_reedem_);
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
    return convert_to_assets(_shares);
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
    let (assets_) = convert_to_assets(_shares);
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
func convert_to_assets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(_shares : Uint256) -> (assets : Uint256){
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
    let (total_assets_) = safemath.add(total_idle_, total_debt_);
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