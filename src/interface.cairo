use starknet::{ContractAddress, ClassHash};

#[starknet::interface]
trait IQuestBoost<TContractState> {
    // admin
    fn set_admin(ref self: TContractState, new_admin: ContractAddress);

    fn claim(
        ref self: TContractState,
        amount: u256,
        token: ContractAddress,
        signature: Span<felt252>,
        boost_id: felt252
    );
    fn fill(ref self: TContractState, amount: u256, token: ContractAddress);
    fn withdraw_all(ref self: TContractState, token: ContractAddress);

    fn upgrade(ref self: TContractState, new_class_hash: ClassHash);
}

