import { AbiCoder } from 'web3-eth-abi';
import { Address, toString } from '@melonproject/token-math';
import {
  transactionFactory,
  PrepareArgsFunction,
  EnhancedExecute,
} from '~/utils/solidity/transactionFactory';
import { Contracts } from '~/Contracts';
import { FunctionSignatures } from '../../trading/utils/FunctionSignatures';

interface Policy {
  method: FunctionSignatures;
  policy: Address;
}

type RegisterArgs = Policy | Policy[];

const prepareArgs: PrepareArgsFunction<RegisterArgs> = async (
  _,
  args: RegisterArgs,
) => {
  const abiCoder = new AbiCoder();
  const methods = Array.isArray(args) ? args.map(a => a.method) : [args.method];
  const policies = Array.isArray(args)
    ? args.map(a => a.policy)
    : [args.policy];

  return [
    methods.map(sig =>
      abiCoder.encodeFunctionSignature((sig as any) as string),
    ),
    policies.map(toString),
  ];
};

const register: EnhancedExecute<RegisterArgs, boolean> = transactionFactory(
  'batchRegister',
  Contracts.PolicyManager,
  undefined,
  prepareArgs,
);

export { register };
