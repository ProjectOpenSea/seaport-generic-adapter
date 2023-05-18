# ETH <> WETH Contract Offerer

The ETH <> WETH Contract Offerer is a work in progress Seaport app that offers ETH in exchange for an equal amount of WETH, or vice versa. It relies on [the contract order pattern](https://github.com/ProjectOpenSea/seaport/blob/main/docs/SeaportDocumentation.md#contract-orders) that was added as part of Seaport v1.2.

## Install

To install dependencies and compile contracts:

```bash
git clone --recurse-submodules https://github.com/ProjectOpenSea/weth-converter && cd weth-converter && forge build
```

## Usage

```bash
forge test
```

## License

[MIT](LICENSE) Copyright 2023 Ozone Networks, Inc.
