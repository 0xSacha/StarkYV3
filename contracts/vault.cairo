%lang starknet

from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.cairo.common.uint256 import ALL_ONES, Uint256, uint256_check, uint256_eq, uint256_lt, uint256_le
from openzeppelin.token.erc20.library import ERC20, ERC20_allowances
from openzeppelin.token.erc20.IERC20 import IERC20
from openzeppelin.security.reentrancyguard.library import ReentrancyGuard 
from openzeppelin.security.pausable.library import Pausable 
from openzeppelin.security.safemath.library import SafeUint256 



from library import Vault, StrategyParams

//TODO: nonces + DOMAIN_TYPE_HASH + PERMIT_TYPE_HASH + permit + multi roles feature


// CONSTRUCTOR
@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _role_manager: felt,
        _asset : felt,
        _name : felt,
        _symbol : felt,
        _profit_max_unlock_time: Uint256,
        ){
        Vault.init(_role_manager, _asset, _name, _symbol, _profit_max_unlock_time);
    return ();
}

// SETTERS

@external
func setAccountant{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _new_accountant: felt
) {
    Vault.set_accountant(_new_accountant);
    return();
}

@external
func setDepositLimit{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _deposit_limit: Uint256
) {
    Vault.set_deposit_limit(_deposit_limit);
    return();
}

@external
func setMinimumTotalIdle{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _minimum_total_idle: Uint256
) {
    Vault.set_minimum_total_idle(_minimum_total_idle);
    return();
}

// ROLE MANAGEMENT

@external
func setRole{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _account: felt,
    _role: felt
) {
    Vault.set_role(_account, _role);
    return();
}

@external
func setOpenRole{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _role: felt
) {
    Vault.set_open_role(_role);
    return();
}

@external
func transferRoleManager{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _role_manager: felt
) {
    Vault.transfer_role_manager(_role_manager);
    return();
}

@external
func acceptRoleManager{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
) {
    Vault.accept_role_manager();
    return();
}

// VAULT STATUS VIEWS

@view
func pricePerShare{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (pricePerShare: Uint256){
    let (price_per_share_) = Vault.price_per_share();
    return (price_per_share_,);
}

@view
func availableDepositLimit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (availableDepositLimit: Uint256){
    let (available_deposit_limit_ ) = Vault.available_deposit_limit();
    return (available_deposit_limit_,);
}

// ACCOUNTING MANAGEMENT

@external
func processReport{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _strategy: felt) -> (gain: Uint256, loss: Uint256) {
    let (gain_: Uint256, loss_: Uint256) = Vault.process_report(_strategy);
    return (gain_,loss_,);
}

@external
func sweep{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _token: felt) -> (amount: Uint256) {
    let (amount_) = Vault.sweep(_token);
    return (amount_,);
}

// STRATEGY MANAGEMENT

@external
func addStrategy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _new_strategy: felt) {
    Vault.add_strategy(_new_strategy);
    return ();
}

@external
func revokeStrategy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _old_strategy: felt) {
    Vault.revoke_strategy(_old_strategy);
    return ();
}

@external
func migrateStrategy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _new_strategy: felt,
    _old_strategy: felt) {
    Vault.migrate_strategy(_new_strategy, _old_strategy);
    return ();
}

// DEBT MANAGEMENT

@external
func updateMaxDebtForStrategy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _strategy: felt,
    _new_max_debt: Uint256) {
    Vault.update_max_debt_for_strategy(_strategy, _new_max_debt);
    return ();
}

@external
func updateDebt{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _strategy: felt,
    _target_debt: Uint256) -> () {
    Vault.update_debt(_strategy, _target_debt,);
    return ();
}

// EMERGENCY MANAGEMENT

@external
func shutdownVault{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    Vault.shutdown_vault();
    return ();
}

// SHARE MANAGEMENT

// ERC20 + ERC4626

@external
func deposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _assets: Uint256, 
        _receiver: felt,) -> (shares: Uint256){
    let (caller_) = get_caller_address();
    return Vault.deposit(caller_, _receiver, _assets);
}

@external
func mint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _shares: Uint256, 
        _receiver: felt,) -> (assets: Uint256){
    alloc_locals;
    let (caller_) = get_caller_address();
    let (assets_) = Vault.convert_to_assets(_shares); 
    Vault.deposit(caller_, _receiver, assets_);
    return (assets_,);
}

@external
func withdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _assets: Uint256, 
        _receiver: felt,
        _owner : felt, 
        _strategies_len: felt, 
        _strategies: felt*
        ) -> (shares: Uint256){
    alloc_locals;
    let (caller_) = get_caller_address();
    let (shares_) = Vault.convert_to_shares(_assets);
    Vault.redeem(caller_, _receiver, _owner, shares_, _strategies_len, _strategies);
    return (shares_,);
}

@external
func redeem{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _shares: Uint256, 
        _receiver: felt,
        _owner : felt, 
        _strategies_len: felt, 
        _strategies: felt*
        ) -> (assets: Uint256){
    alloc_locals;
    let (caller_) = get_caller_address();
    let (assets_) = Vault.redeem(caller_, _receiver, _owner, _shares, _strategies_len, _strategies);
    return (assets_,);
}

@external
func approve{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _spender : felt, amount : Uint256) -> (success : felt){
    ERC20.approve(_spender, amount);
    return (TRUE,);
}

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

// ERC20 + ERC4626 compatibility

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


//TODO: permit 

@view
func balanceOf{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _account : felt) -> (balance : Uint256){
    return ERC20.balance_of(_account);
}

@view
func totalSupply{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        totalSupply : Uint256){
    let (total_supply_) = ERC20.total_supply();
    return (total_supply_,);
}

@view
func decimals{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        decimals: felt){
    let (decimals_) = ERC20.decimals();
    return (decimals_,);
}

@view
func totalDebt{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        totalDebt: Uint256){
    let (total_debt_) = Vault.get_total_debt();
    return (total_debt_,);
}

@view
func profitDistributionRate{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        profitDistributionRate: Uint256){
    let (profit_distribution_rate_) = Vault.get_profit_distribution_rate();
    return (profit_distribution_rate_,);
}

@view
func totalAssets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        totalAssets : Uint256){
    let (total_assets_) =  Vault.total_assets();
    return (total_assets_,);
}

@view
func convertToShares{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _assets: Uint256) -> (shares: Uint256){
    let (shares_) = Vault.convert_to_shares(_assets);
    return (shares_,);
}

@view
func previewDeposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _assets: Uint256) -> (shares: Uint256){
    let (shares_) = Vault.convert_to_shares(_assets);
    return (shares_,);
}

@view
func previewMint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _shares: Uint256) -> (assets: Uint256){
    let (assets_) = Vault.convert_to_assets(_shares);
    return (assets_,);
}

@view
func convertToAssets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _shares: Uint256) -> (assets: Uint256){
    return Vault.convert_to_assets(_shares);
}

@view
func maxDeposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _receiver: felt) -> (maxDeposit: Uint256){
    let (max_deposit_) = Vault.max_deposit(_receiver);
    return (max_deposit_,);
}

@view
func maxMint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _receiver: felt) -> (maxMint: Uint256){
    let (max_deposit_) = Vault.max_deposit(_receiver);
    let (shares_) = Vault.convert_to_shares(max_deposit_);
    return (shares_,);
}

@view
func maxWithdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _receiver: felt) -> (maxWithdraw: Uint256){
    let (max_redeem_) = Vault.max_redeem(_receiver);
    let (assets_) = Vault.convert_to_assets(max_redeem_);
    return (assets_,);
}

@view
func maxRedeem{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _receiver: felt) -> (maxRedeem: Uint256){
    let (max_redeem_) = Vault.max_redeem(_receiver);
    return (max_redeem_,);
}

@view
func previewWithdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _assets: Uint256) -> (shares: Uint256){
    let (shares_) = Vault.convert_to_shares(_assets);
    return (shares_,);
}

@view
func previewRedeem{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _shares: Uint256) -> (assets: Uint256){
    let (assets_) = Vault.convert_to_assets(_shares);
    return (assets_,);
}


// getters for public var

@view
func asset{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (asset : felt){
    let (asset_) = Vault.get_asset();
    return (asset_,);
}

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
func allowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _owner: felt, _spender: felt) -> (remaining: Uint256){
    let (remaining_) =  ERC20.allowance(_owner, _spender);
    return (remaining_,);
}

@view
func strategies{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _strategy: felt) -> (strategyParameters: StrategyParams){
    let (strategy_parameters_) = Vault.get_strategy(_strategy);
    return (strategy_parameters_,);
}

@view
func totalIdle{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (totalIdle : Uint256){
    let (total_idle_) = Vault.get_total_idle();
    return (total_idle_,);
}

@view
func minimumTotalIdle{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (minimumTotalIdle: Uint256){
    let (minimum_total_idle_) = Vault.get_minimum_total_idle();
    return (minimum_total_idle_,);
}

@view
func depositLimit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (depositLimit: Uint256){
    let (deposit_limit_) = Vault.get_deposit_limit();
    return (deposit_limit_,);
}

@view
func accountant{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (accountant: felt){
    let (account_) = Vault.get_accountant();
    return (account_,);
}

@view
func roles{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(_account: felt) -> (role: felt){
    let (roles_) = Vault.get_roles(_account);
    return (roles_,);
}

@view
func openRoles{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(_role: felt) -> (isOpen: felt){
    let (open_roles_) = Vault.get_open_roles(_role);
    return (open_roles_,);
}

@view
func roleManager{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (roleManager: felt){
    let (role_manager_) = Vault.get_role_manager();
    return (role_manager_,);
}

@view
func futureRoleManager{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (futureRoleManager: felt){
    let (future_role_manager_) = Vault.get_future_role_manager();
    return (future_role_manager_,);
}

@view
func shutdown{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (shutdown: felt){
    let (shutdown_) = Vault.get_shutdown();
    return (shutdown_,);
}

@view
func profitEndDate{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (profitEndDate: Uint256){
    let (profit_end_date_) = Vault.get_profit_end_date();
    return (profit_end_date_,);
}

@view
func profitlastUpdate{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (profitlastUpdate: Uint256){
    let (profit_last_update_) =Vault.get_profit_last_update();
    return (profit_last_update_,);
}


