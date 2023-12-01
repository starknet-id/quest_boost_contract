use core::traits::Into;
use core::debug::PrintTrait;
use array::ArrayTrait;
use super::utils::constants::{ADMIN};
use core::result::ResultTrait;
use option::OptionTrait;
use starknet::{
    class_hash::Felt252TryIntoClassHash, ContractAddress, SyscallResultTrait, get_caller_address
};
use openzeppelin::tests::mocks::erc20_mocks::{CamelERC20Mock, SnakeERC20Mock};
use traits::TryInto;
use openzeppelin::utils::serde::SerializedAppend;
use quest_boost_contract::main::QuestBoost;
use core::pedersen::pedersen;
use starknet::testing::{set_contract_address, set_caller_address};
use quest_boost_contract::interface::{
    IQuestBoost, IQuestBoostDispatcher, IQuestBoostDispatcherTrait
};
use openzeppelin::token::erc20::interface::{
    IERC20Camel, IERC20CamelDispatcher, IERC20CamelDispatcherTrait
};
use super::utils::mock_erc20::ERC20Component;


fn deploy(contract_class_hash: felt252, calldata: Array<felt252>) -> ContractAddress {
    let (address, _) = starknet::deploy_syscall(
        contract_class_hash.try_into().unwrap(), 0, calldata.span(), false
    )
        .unwrap_syscall();
    address
}

fn deploy_token(reciepient: ContractAddress, amount: u256) -> IERC20CamelDispatcher {
    let erc20 = deploy(
        CamelERC20Mock::TEST_CLASS_HASH,
        ERC20ConstructorArgumentsImpl::new(reciepient, amount).to_calldata()
    );
    IERC20CamelDispatcher { contract_address: erc20 }
}

#[derive(Drop)]
struct ERC20ConstructorArguments {
    name: felt252,
    symbol: felt252,
    initial_supply: u256,
    recipient: ContractAddress
}

#[generate_trait]
impl ERC20ConstructorArgumentsImpl of ERC20ConstructorArgumentsTrait {
    fn new(recipient: ContractAddress, initial_supply: u256) -> ERC20ConstructorArguments {
        ERC20ConstructorArguments {
            name: 0_felt252, symbol: 0_felt252, initial_supply: initial_supply, recipient: recipient
        }
    }
    fn to_calldata(self: ERC20ConstructorArguments) -> Array<felt252> {
        let mut calldata = array![];
        calldata.append_serde(self.name);
        calldata.append_serde(self.symbol);
        calldata.append_serde(self.initial_supply);
        calldata.append_serde(self.recipient);
        calldata
    }
}


fn deploy_contract() -> IQuestBoostDispatcher {
    let mut calldata = array![
        0x48f24d0d0618fa31813db91a45d8be6c50749e5e19ec699092ce29abe809294,
        0x5b938888fc7959e81f859f3e492ba547ca49c31b3d7cb6e7009ff681d6d87e7
    ];
    let address = deploy(QuestBoost::TEST_CLASS_HASH, calldata);

    IQuestBoostDispatcher { contract_address: address }
}


#[test]
#[available_gas(20000000000)]
fn test_claim() {
    let quest_boost = deploy_contract();
    let erc20 = deploy_token(quest_boost.contract_address, 10000);
    let amount: u256 = 1000;
    let token_id: ContractAddress = erc20.contract_address;
    set_contract_address(ADMIN());
    let (sig_0, sig_1) = (
        765301107836623957948028135212947639996218756476579369944383988832488039190,
        364743106737423797092878139014999646784167567917477096350335031799658835871
    );
    let boost_id = 1;
    erc20.approve(ADMIN(), amount);
    quest_boost.claim(amount, token_id, array![sig_0, sig_1].span(), boost_id);
}

#[test]
#[available_gas(20000000000)]
#[should_panic(expected: ('invalid signature', 'ENTRYPOINT_FAILED',))]
fn test_claim_invalid_sign() {
    let quest_boost = deploy_contract();
    let erc20 = deploy_token(quest_boost.contract_address, 10000);
    let amount: u256 = 1000;
    let token_id: ContractAddress = erc20.contract_address;
    set_contract_address(ADMIN());
    let (sig_0, sig_1) = (123, 123);
    let boost_id = 1;
    erc20.approve(ADMIN(), amount);
    quest_boost.claim(amount, token_id, array![sig_0, sig_1].span(), boost_id);
}


#[test]
#[available_gas(20000000000)]
#[should_panic(expected: ('invalid signature', 'ENTRYPOINT_FAILED',))]
fn test_claim_invalid_caller() {
    let quest_boost = deploy_contract();
    let erc20 = deploy_token(quest_boost.contract_address, 10000);
    let amount: u256 = 1000;
    let token_id: ContractAddress = erc20.contract_address;
    set_contract_address(0x123.try_into().unwrap());
    let (sig_0, sig_1) = (
        765301107836623957948028135212947639996218756476579369944383988832488039190,
        364743106737423797092878139014999646784167567917477096350335031799658835871
    );
    let boost_id = 1;
    erc20.approve(ADMIN(), amount);
    quest_boost.claim(amount, token_id, array![sig_0, sig_1].span(), boost_id);
}


#[test]
#[available_gas(20000000000)]
fn test_fill() {
    let quest_boost = deploy_contract();
    let erc20 = deploy_token(ADMIN(), 10000);
    let amount: u256 = 1000;
    let token_id: ContractAddress = erc20.contract_address;
    set_contract_address(ADMIN());
    erc20.approve(quest_boost.contract_address, amount);
    quest_boost.fill(amount, token_id);
}

#[test]
#[available_gas(20000000000)]
#[should_panic(expected: ('only admin can fill', 'ENTRYPOINT_FAILED',))]
fn test_fill_not_owner() {
    let quest_boost = deploy_contract();
    let erc20 = deploy_token(ADMIN(), 10000);
    let amount: u256 = 1000;
    let token_id: ContractAddress = erc20.contract_address;
    set_contract_address(0x123.try_into().unwrap());
    erc20.approve(quest_boost.contract_address, amount);
    quest_boost.fill(amount, token_id);
}


#[test]
#[available_gas(20000000000)]
fn test_withdraw_all() {
    let quest_boost = deploy_contract();
    let erc20 = deploy_token(ADMIN(), 10000);
    let token_id: ContractAddress = erc20.contract_address;
    set_contract_address(ADMIN());
    quest_boost.withdraw_all(token_id);
}


#[test]
#[available_gas(20000000000)]
#[should_panic(expected: ('only admin can withdraw', 'ENTRYPOINT_FAILED',))]
fn test_withdraw_all_not_owner() {
    let quest_boost = deploy_contract();
    let erc20 = deploy_token(ADMIN(), 10000);
    let token_id: ContractAddress = erc20.contract_address;
    set_contract_address(0x123.try_into().unwrap());
    quest_boost.withdraw_all(token_id);
}

