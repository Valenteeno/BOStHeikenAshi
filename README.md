# BOStHeikenAshi

Break-of-Structure trading toolkit built on Heiken-Ashi candles — an Expert Advisor plus its companion indicator.

> **Proprietary software** — © Teenodi Ltd. All rights reserved. Private repository; not for distribution. See [LICENSE](LICENSE).

## BOStHeiken_Ashi_EA.mq5

### Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `BacklogNumber` | int | `1000` | Number of historical candles to analyze |
| `SwingPointBars` | int | `20` | Number of bars for swing confirmation |
| `DeletePrevStructures` | bool | `false` | Delete previous structures when new one forms |
| `StopLossPoints` | double | `20` | Stop loss distance in points from swing low |
| `NoStopLoss` | bool | `false` | Disable stop loss if true |
| `SwingSLTrailer` | bool | `true` | Enable stop loss trailing by swing points |
| `SwingTPTrailer` | bool | `true` | Enable take profit trailing by swing points |
| `MaximumEntriesPerSignal` | int | `2` | Number of additional entries on HA transitions |
| `LotSize` | double | `0.1` |  |

## BOStHeiken_Ashi_Indicator.mq5

### Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `BacklogNumber` | int | `1000` | Number of historical candles to analyze |
| `SwingPointBars` | int | `20` | Number of bars for swing confirmation |
| `DeletePrevStructures` | bool | `false` | Delete previous structures when new one forms |
| `StopLossPoints` | double | `20` | Stop loss distance in points from swing low |
| `NoStopLoss` | bool | `false` | Disable stop loss if true |
| `SwingSLTrailer` | bool | `true` | Enable stop loss trailing by swing points |
| `SwingTPTrailer` | bool | `true` | Enable take profit trailing by swing points |
| `MaximumEntriesPerSignal` | int | `2` | Number of additional entries on HA transitions |
| `LotSize` | double | `0.1` |  |

## Install

1. Copy the source file(s) into your MetaTrader 5 `MQL5/` tree (`Experts/`, `Indicators/`, or `Scripts/` as appropriate).
2. In MetaEditor, open the file and compile (**F7**).
3. Attach the compiled program to a chart from the terminal Navigator.

## License

Proprietary and confidential. © Teenodi Ltd. All rights reserved. See [LICENSE](LICENSE).
