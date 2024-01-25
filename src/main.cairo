#[starknet::contract]
mod QuestBoost {
    use openzeppelin::access::ownable::interface::IOwnable;
    use openzeppelin::access::ownable::ownable::OwnableComponent::InternalTrait;
    use core::debug::PrintTrait;
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use core::traits::Into;
    use quest_boost_contract::interface::IQuestBoost;
    use core::starknet::event::EventEmitter;
    use core::array::SpanTrait;
    use openzeppelin::{
        upgrades::UpgradeableComponent, account, access::ownable::OwnableComponent,
        token::erc20::interface::{IERC20Camel, IERC20CamelDispatcher, IERC20CamelDispatcherTrait}
    };
    use starknet::{
        ContractAddress, contract_address_const, contract_address_to_felt252, get_block_timestamp,
        ClassHash
    };
    use starknet::{get_caller_address, get_contract_address};
    use ecdsa::check_ecdsa_signature;
    use core::pedersen::pedersen;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    // add an owner
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    /// Upgradeable
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        blacklist: LegacyMap::<felt252, bool>,
        boostMap: LegacyMap::<u128, bool>,
        public_key: felt252,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage
    }

    // events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OnClaim: on_claim,
        OnBoostCreated: on_boost_created,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event
    }


    #[derive(Drop, starknet::Event)]
    struct on_claim {
        timestamp: u64,
        amount: u256,
        #[key]
        address: ContractAddress,
        #[key]
        boost_id: u128
    }

    #[derive(Drop, starknet::Event)]
    struct on_boost_created {
        token: ContractAddress,
        amount: u256,
        #[key]
        boost_id: u128
    }


    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, public_key: felt252) {
        self.ownable.initializer(owner);
        self.public_key.write(public_key);
    }

    #[external(v0)]
    impl QuestBoost of IQuestBoost<ContractState> {
        fn create_boost(
            ref self: ContractState, boost_id: u128, amount: u256, token: ContractAddress
        ) {
            // check if boost_id is already created
            let boostMap_data = self.boostMap.read(boost_id);
            assert(!boostMap_data, 'boost already created');

            let caller: ContractAddress = get_caller_address();
            let contract_address: ContractAddress = get_contract_address();
            let starknet_erc20 = IERC20CamelDispatcher { contract_address: token };
            // transfer tokens from caller to contract
            let transfer_result = starknet_erc20.transferFrom(caller, contract_address, amount);
            assert(transfer_result, 'transfer failed');

            self.boostMap.write(boost_id, true);
            self
                .emit(
                    Event::OnBoostCreated(
                        on_boost_created { amount: amount, token: token, boost_id: boost_id }
                    )
                );
        }

        fn withdraw_all(ref self: ContractState, token: ContractAddress) {
            let caller: ContractAddress = get_caller_address();

            let starknet_erc20 = IERC20CamelDispatcher { contract_address: token };

            let balance = starknet_erc20.balanceOf(token.try_into().unwrap());

            // check if admin has called fill contract
            assert(caller == self.ownable.owner(), 'only admin can withdraw');

            // transfer tokens from caller to contract
            let transfer_result = starknet_erc20.transfer(caller, balance);
            assert(transfer_result, 'transfer failed');
        }

        fn claim(
            ref self: ContractState,
            amount: u256,
            token: ContractAddress,
            boost_id: u128,
            signature: Span<felt252>
        ) {
            let r = *signature.at(0);
            let s = *signature.at(1);

            // check if signature is blacklisted
            let blacklist_data = self.blacklist.read(r);
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
            self.blacklist.write(r, true);

            // transfer tokens from contract to caller
            let starknet_erc20 = IERC20CamelDispatcher { contract_address: token };

            // approve tokens
            assert(
                starknet_erc20.balanceOf(get_contract_address()) > amount,
                'amount more than balance'
            );
            // transfer tokens from caller to contract
            let transfer_result = starknet_erc20.transfer(caller, amount);
            assert(transfer_result, 'transfer failed');

            // emit event
            self
                .emit(
                    Event::OnClaim(
                        on_claim {
                            timestamp: get_block_timestamp(),
                            amount: amount,
                            address: caller,
                            boost_id: boost_id
                        }
                    )
                );
        }

        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            // This function can only be called by the owner
            self.ownable.assert_only_owner();

            // Replace the class hash upgrading the contract
            self.upgradeable._upgrade(new_class_hash);
        }

        fn get_balance(self: @ContractState, token: ContractAddress) -> u256 {
            let starknet_erc20 = IERC20CamelDispatcher { contract_address: token };
            starknet_erc20.balanceOf(get_contract_address())
        }
    }
}
