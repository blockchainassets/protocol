import { getContract } from '~/utils/solidity/getContract';
import { Contracts, Exchanges } from '~/Contracts';
import { ensure } from '~/utils/guards/ensure';
import { Address } from '@melonproject/token-math';
import { Environment } from '~/utils/environment/Environment';

const getExchangeIndex = async (
  environment: Environment,
  tradingAddress: Address,
  { exchange }: { exchange: Exchanges },
) => {
  const exchangeAddress: Address =
    environment.deployment.exchangeConfigs[exchange].adapter;

  const tradingContract = getContract(
    environment,
    Contracts.Trading,
    tradingAddress,
  );
  const exchanges = await tradingContract.methods.getExchangeInfo().call();
  const index = exchanges[1].findIndex(
    e => e.toLowerCase() === exchangeAddress.toLowerCase(),
  );
  ensure(
    index !== -1,
    `Fund with address ${
      Contracts.Hub
    } does not authorize exchange with address ${exchangeAddress}`,
  );

  return index;
};

export { getExchangeIndex };
