import {
  BigInteger,
  // add,
  greaterThan,
} from '@melonproject/token-math';

import { transactionFactory } from '~/utils/solidity/transactionFactory';
import { getContract } from '~/utils/solidity/getContract';
import { ensure } from '~/utils/guards/ensure';
import { Contracts } from '~/Contracts';

const guard = async (environment, params, engineAddress) => {
  const engine = getContract(environment, Contracts.Engine, engineAddress);

  // // TODO: Fix that check
  // const lastThaw = new BigInteger(await engine.methods.lastThaw().call());
  // const thawingDelay = new BigInteger(
  //   await engine.methods.THAWING_DELAY().call(),
  // );
  // const now = new BigInteger(Math.floor(new Date().getTime() / 1000));

  // console.log(
  //   now.toString(),
  //   lastThaw.toString(),
  //   thawingDelay.toString(),
  //   add(thawingDelay, lastThaw),
  //   );

  //   ensure(
  //     greaterThan(now, add(thawingDelay, lastThaw)),
  //     'Not enough time has passed since the last thaw',
  //     );
  const frozenEther = await engine.methods.frozenEther().call();
  ensure(
    greaterThan(new BigInteger(frozenEther), new BigInteger(0)),
    'No frozen ether to thaw',
  );
};

export const thaw = transactionFactory('thaw', Contracts.Engine, guard);
