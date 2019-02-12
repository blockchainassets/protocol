import { Accounts } from 'web3-eth-accounts';

import { Environment } from './Environment';

const withPrivateKeySigner = async (
  environment: Environment,
  privateKey: string,
) => {
  const accounts = new Accounts(environment.eth.currentProvider);

  const { address } = accounts.privateKeyToAccount(privateKey);

  const signTransaction = unsignedTransaction =>
    accounts
      .signTransaction(unsignedTransaction, privateKey)
      .then(t => t.rawTransaction);

  const signMessage = message => accounts.sign(message, privateKey);

  const withWallet = {
    ...environment,
    wallet: {
      address,
      signMessage,
      signTransaction,
    },
  };

  return withWallet;
};

export { withPrivateKeySigner };
