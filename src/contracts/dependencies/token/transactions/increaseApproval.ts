import { QuantityInterface, Address } from '@melonproject/token-math';

import { ensure } from '~/utils/guards/ensure';
import { isAddress } from '~/utils/checks/isAddress';
import { transactionFactory } from '~/utils/solidity/transactionFactory';
import { Contracts } from '~/Contracts';
import {
  WithAddressQueryExecute,
  withContractAddressQuery,
} from '~/utils/solidity/withContractAddressQuery';

const guard = async (_, { howMuch, spender }) => {
  ensure(
    isAddress(spender),
    `Spender is not an address. Got: ${spender}`,
    spender,
  );
  ensure(
    isAddress(howMuch.token.address),
    `Token needs to have an address. Got: ${howMuch.token.address}`,
  );
};

const prepareArgs = async (_, { howMuch, spender }) => [
  spender.toString(),
  howMuch.quantity.toString(),
];

const postProcess = async () => {
  return true;
};

interface IncreaseApprovalArgs {
  howMuch: QuantityInterface;
  spender: Address;
}

type IncreaseApprovalResult = boolean;

const increaseApproval: WithAddressQueryExecute<
  IncreaseApprovalArgs,
  IncreaseApprovalResult
> = withContractAddressQuery(
  ['howMuch', 'token', 'address'],
  transactionFactory(
    'increaseApproval',
    Contracts.StandardToken,
    guard,
    prepareArgs,
    postProcess,
  ),
);

export { increaseApproval };
