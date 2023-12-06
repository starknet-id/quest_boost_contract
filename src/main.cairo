#[starknet::contract]
mod QuestBoost {
    use core::debug::PrintTrait;
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use core::traits::Into;
    use quest_boost_contract::interface::IQuestBoost;
    use core::starknet::event::EventEmitter;
    use core::array::SpanTrait;
    use openzeppelin::token::erc20::interface::{
        IERC20Camel, IERC20CamelDispatcher, IERC20CamelDispatcherTrait
    };
    use starknet::{
        ContractAddress, contract_address_const, contract_address_to_felt252, get_block_timestamp,
        ClassHash
    };
    use starknet::{get_caller_address, get_contract_address};
    use ecdsa::check_ecdsa_signature;
    use core::pedersen::pedersen;


    #[storage]
    struct Storage {
        blacklist: LegacyMap::<u128, bool>,
        boostMap: LegacyMap::<u128, bool>,
        public_key: felt252,
        _admin_address: ContractAddress
    }

    // events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        on_claim: on_claim,
        on_fill: on_fill
    }


    #[derive(Drop, starknet::Event)]
    struct on_claim {
        timestamp: u64,
        amount: u256,
        #[key]
        address: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct on_fill {
        token: ContractAddress,
        amount: u256,
        #[key]
        boost_id: u128
    }


    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, public_key: felt252) {
        self._admin_address.write(owner);
        self.public_key.write(public_key);
    }

    #[external(v0)]
    impl QuestBoost of IQuestBoost<ContractState> {
        // ADMIN
        fn set_admin(ref self: ContractState, new_admin: ContractAddress) {
            assert(get_caller_address() == self._admin_address.read(), 'you are not admin');
            self._admin_address.write(new_admin);
        }

        fn create_boost(
            ref self: ContractState, boost_id: u128, amount: u256, token: ContractAddress
        ) {
            // check if boost_id is blacklisted
            let boostMap_data = self.boostMap.read(boost_id);
            assert(!boostMap_data, 'boost already created');

            let caller: ContractAddress = get_caller_address();
            let contract_address: ContractAddress = get_contract_address();
            let starknet_erc20 = IERC20CamelDispatcher { contract_address: token };
            // transfer tokens from caller to contract
            let transfer_result = starknet_erc20.transferFrom(caller, contract_address, amount);
            assert(transfer_result, 'transfer failed');

            self.boostMap.write(boost_id, true);
            self.emit(Event::on_fill(on_fill { amount: amount, token: token, boost_id: boost_id }));
        }

        fn withdraw_all(ref self: ContractState, token: ContractAddress) {
            let caller: ContractAddress = get_caller_address();
            let contract_address: ContractAddress = get_contract_address();

            let starknet_erc20 = IERC20CamelDispatcher { contract_address: token };

            let balance = starknet_erc20.balanceOf(token.try_into().unwrap());

            // check if admin has called fill contract
            assert(caller == self._admin_address.read(), 'only admin can withdraw');

            // transfer tokens from caller to contract
            let transfer_result = starknet_erc20.transfer(caller, balance);
            assert(transfer_result, 'transfer failed');
        }

        fn claim(
            ref self: ContractState,
            amount: u256,
            token: ContractAddress,
            signature: Span<felt252>,
            boost_id: u128
        ) {
            let r = *signature.at(0);
            let s = *signature.at(1);

            // check if signature is blacklisted
            let blacklist_data = self.blacklist.read(boost_id);
            assert(!blacklist_data, 'blacklisted');

            // check if signature is valid
            let caller: ContractAddress = get_caller_address();
            let hashed = pedersen(
                boost_id.into(),
                pedersen(
                    amount.low.into(),
                    pedersen(amount.high.into(), pedersen(token.into(), caller.into()))
                )
            );
            let stark_public_key = self.public_key.read();

            assert(
                check_ecdsa_signature(hashed, stark_public_key, r, s) == true, 'invalid signature'
            );

            // add r to the blacklist
            self.blacklist.write(boost_id, true);

            // transfer tokens from contract to caller
            let starknet_erc20 = IERC20CamelDispatcher { contract_address: token };

            // approve tokens
            assert(
                starknet_erc20.balanceOf(get_contract_address()) > amount,
                'amount more than balance'
            );
            starknet_erc20.approve(get_contract_address(), amount);
            // transfer tokens from caller to contract
            let transfer_result = starknet_erc20.transfer(caller, amount);
            assert(transfer_result, 'transfer failed');

            // emit event
            self
                .emit(
                    Event::on_claim(
                        on_claim {
                            timestamp: get_block_timestamp(), amount: amount, address: caller
                        }
                    )
                );
        }

        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            assert(get_caller_address() == self._admin_address.read(), 'you are not admin');
            // todo: use components
            assert(!new_class_hash.is_zero(), 'Class hash cannot be zero');
            starknet::replace_class_syscall(new_class_hash).unwrap();
        }

        fn get_balance(self: @ContractState, token: ContractAddress) -> u256 {
            let starknet_erc20 = IERC20CamelDispatcher { contract_address: token };
            starknet_erc20.balanceOf(get_contract_address())
        }
    }
}
