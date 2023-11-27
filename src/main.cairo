#[starknet::interface]
trait IERC20<TContractState> {
    fn transferFrom(
        ref self: TContractState, sender: felt252, recipient: felt252, amount: u256
    ) -> bool;
    fn balanceOf(self: @TContractState, account: felt252) -> u256;
    fn transfer(ref self: TContractState, recipient: felt252, amount: u256) -> bool;
}


#[starknet::contract]
mod QuestBoost {
    use core::starknet::event::EventEmitter;
    use starknet::{ContractAddress, contract_address_const, contract_address_to_felt252};
    use starknet::{get_caller_address, get_contract_address};
    use super::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    struct Storage {
        owner: ContractAddress,
        blacklist: LegacyMap::<u256, bool>,
    }

    // events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        on_claim: on_claim,
    }


    #[derive(Drop, starknet::Event)]
    struct on_claim {
        timestamp: u64,
        amount: u256,
        #[key]
        address: ContractAddress
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write(owner);
    }

    #[external(v0)]
    fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
        let caller = get_caller_address();
        let old_owner = self.owner.read();
        assert(caller == old_owner, 'only owner can transfer');
        self.owner.write(new_owner);
    }

    #[external(v0)]
    fn fill(self: @ContractState, amount: u256, token: ContractAddress) {
        let ERC20_TOKEN: ContractAddress = token;
        let caller: felt252 = contract_address_to_felt252(get_caller_address());
        let owner: felt252 = contract_address_to_felt252(self.owner.read());
        let contract_address: felt252 = contract_address_to_felt252(get_contract_address());

        let starknet_erc20 = IERC20Dispatcher { contract_address: ERC20_TOKEN };

        // check if owner has called fill contract
        assert(caller == owner, 'only owner can fill');

        // transfer tokens from caller to contract
        let transfer_result = starknet_erc20.transferFrom(caller, contract_address, amount);
        assert(transfer_result, 'transfer failed');
    }

    #[external(v0)]
    fn withdraw_all(self: @ContractState, token: ContractAddress) {
        let ERC20_TOKEN: ContractAddress = token;
        let caller: felt252 = contract_address_to_felt252(get_caller_address());
        let owner: felt252 = contract_address_to_felt252(self.owner.read());
        let contract_address: felt252 = contract_address_to_felt252(get_contract_address());

        let starknet_erc20 = IERC20Dispatcher { contract_address: ERC20_TOKEN };

        let balance = starknet_erc20.balanceOf(contract_address_to_felt252(ERC20_TOKEN));

        // check if owner has called fill contract
        assert(caller == owner, 'only owner can withdraw');

        // transfer tokens from caller to contract
        let transfer_result = starknet_erc20.transferFrom(contract_address, caller, balance);
        assert(transfer_result, 'transfer failed');
    }

    #[external(v0)]
    fn claim(
        self: @ContractState,
        amount: u128,
        token: ContractAddress,
        signature: felt252,
        boost_id: u256
    ) {}
}
