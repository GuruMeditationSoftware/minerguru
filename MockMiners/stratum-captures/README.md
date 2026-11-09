# Stratum captures of public solo pools

Raw Stratum V1 replies from 17 pool endpoints, recorded on 2026-11-03 (13:23–13:44 UTC) as test data for
the Stratum probe (MG-04): reading the pool's block template without mining.

Per endpoint one connection: `mining.subscribe` (user agent `MinerGuru-probe/0.1`), `mining.authorize`
with `<address>.minerguru` and password `x`, wait for the first `mining.notify`, disconnect.
No share was ever submitted. Each `*.jsonl` holds the lines the pool sent, unchanged, one JSON message per line.

Addresses are early, public ones: the genesis address `1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa` for BTC and BSV,
the same key as CashAddr for BCH (`bitcoincash:qp3wjpa3tjlj042z2wv7hahsldgwhwy0rq9sywjpyy`) and eCash
(`ecash:qp3wjpa3tjlj042z2wv7hahsldgwhwy0rquas9fmzn`), and `DRNiw2k4iFuHGS2fF1wMahounXo6H9iGbh` from DigiByte block 1.
The coinbase outputs also contain pool fee addresses and, for Ocean, payout addresses of other Ocean miners.
All of them are public on-chain data.

`expected.json` lists per capture what was decoded at recording time: pool, coin, user, extranonce,
BIP34 height, pool tags, merkle branches, every output (type, value, address, scriptPubKey) and whether it
pays the test address. Use it as the reference for the coinbase decoder.

Cases worth knowing:
- Outputs are not always in `coinb2`: Ocean and solopool.eu BCH carry the extranonce in an OP_RETURN
  output, so the outputs before it sit in `coinb1`. Decode the assembled coinbase, never `coinb2` alone.
- `ocean-btc`: shared coinbase with 20 outputs; `mining.notify` arrives before the authorize result.
- `nerdminers-btc`: subscribe is refused for unknown user agents (no extranonce in the reply), work arrives
  anyway; the 12-byte extranonce gap follows from the scriptSig length.
- `kryptex-bsv`: the whole reward goes to the pool address.
- `solopooleu-bch`: the fee output comes first, the miner last.
- `solopooleu-xec`, `solopoolorg-xec`: about 42 % goes to fixed eCash protocol outputs.
- `solopooleu-btc`: Namecoin merge-mining tag in the scriptSig, extranonce2 size 4.
- `2miners-bch`: authorize fails with `[20,"Invalid address"]`, no work.
