use starknet::{ContractAddress, ClassHash};

#[starknet::interface]
trait IQuestBoost<TContractState> {
    fn claim(
        ref self: TContractState,
        amount: u256,
        token: ContractAddress,
        boost_id: u128,
        signature: Span<felt252>
    );
    fn create_boost(ref self: TContractState, boost_id: u128, amount: u256, token: ContractAddress);
    fn withdraw_all(ref self: TContractState, token: ContractAddress);
    fn update_pub_key(ref self: TContractState, new_pub_key: felt252);
    fn upgrade(ref self: TContractState, new_class_hash: ClassHash);
    fn get_balance(self: @TContractState, token: ContractAddress) -> u256;
}

