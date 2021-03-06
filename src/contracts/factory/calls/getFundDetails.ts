import * as web3Utils from 'web3-utils';
import {
  Address,
  createPrice,
  createQuantity,
  greaterThan,
  isEqual,
} from '@melonproject/token-math';

import { getContract } from '~/utils/solidity/getContract';
import { Contracts } from '~/Contracts';
import { getTokenByAddress } from '~/utils/environment/getTokenByAddress';
import { Environment } from '~/utils/environment/Environment';

export const getFundDetails = async (
  environment: Environment,
  contractAddress: Address = environment.deployment.melonContracts.ranking,
  versionAddress: Address = environment.deployment.melonContracts.version,
) => {
  const contract = getContract(
    environment,
    Contracts.FundRanking,
    contractAddress,
  );

  const fundDetails = await contract.methods
    .getFundDetails(versionAddress.toString())
    .call();

  const {
    0: addresses,
    1: sharePrices,
    2: creationTimes,
    3: names,
    4: denominationAsset,
  } = fundDetails;

  const result = addresses
    .map((address, index) => {
      const denominationToken = getTokenByAddress(
        environment,
        denominationAsset[index],
      );

      const fundToken = {
        decimals: 18,
        symbol: 'MLNF',
      };

      return {
        address,
        creationTime: new Date(creationTimes[index] * 1000),
        name: web3Utils.toUtf8(names[index]),
        sharePrice: createPrice(
          createQuantity(fundToken, 1),
          createQuantity(denominationToken, sharePrices[index]),
        ),
      };
    })
    .sort((a, b) => {
      if (isEqual(a.sharePrice, b.sharePrice)) {
        return 0;
      } else if (greaterThan(a.sharePrice.quote, b.sharePrice.quote)) {
        return -1;
      } else {
        return 1;
      }
    })
    .map((fund, index) => {
      return {
        ...fund,
        rank: index + 1,
      };
    });

  return result;
};
