import { default as Web3Accounts } from 'web3-eth-accounts';

import { Environment } from './Environment';

const withPrivateKeySigner = async (
  environment: Environment,
  privateKey: string,
) => {
  const web3Accounts = new Web3Accounts(environment.eth.currentProvider);

  const { address } = web3Accounts.privateKeyToAccount(privateKey);

  const signTransaction = unsignedTransaction =>
    web3Accounts
      .signTransaction(unsignedTransaction, privateKey)
      .then(t => t.rawTransaction);

  const signMessage = message => web3Accounts.sign(message, privateKey);

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
