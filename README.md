# moving-average-aux

Expert Advisor for MetaTrader 5 (MT5) based on the Moving Average indicator, optimised for the **M5 timeframe**.

## Strategy Overview

The EA uses **three Exponential Moving Averages (EMAs)** to clearly determine market trend and generate trade signals:

| MA | Default Period | Purpose |
|----|---------------|---------|
| Fast EMA | 8 | Short-term momentum |
| Medium EMA | 21 | Mid-term trend |
| Slow EMA | 50 | Long-term trend / filter |

### Entry Rules

- **BUY**: Fast EMA crosses above Medium EMA **and** all three MAs are bullish-aligned (Fast > Medium > Slow)
- **SELL**: Fast EMA crosses below Medium EMA **and** all three MAs are bearish-aligned (Fast < Medium < Slow)

Signals are evaluated on each completed M5 bar to avoid repainting.

### Exit Rules

- Fixed **Take Profit** (default: 60 pips) and **Stop Loss** (default: 30 pips)
- Optional **Trailing Stop** to lock in profits as the trade moves in your favour
- Optional automatic close when an opposite signal fires

## Input Parameters

### Moving Average Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| `FastMAPeriod` | 8 | Period for the fast EMA |
| `MediumMAPeriod` | 21 | Period for the medium EMA |
| `SlowMAPeriod` | 50 | Period for the slow EMA |
| `MAMethod` | EMA | MA calculation method |
| `AppliedPrice` | Close | Price used for MA calculation |

### Trade Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| `LotSize` | 0.01 | Trade volume in lots |
| `StopLossPips` | 30 | Stop loss distance in pips |
| `TakeProfitPips` | 60 | Take profit distance in pips |
| `MagicNumber` | 20240101 | Unique identifier for EA orders |
| `MaxSpreadPoints` | 20 | Maximum spread allowed to open a trade |
| `CloseOnOppositeSignal` | true | Close trade when opposite signal fires |

### Risk Management
| Parameter | Default | Description |
|-----------|---------|-------------|
| `UseTrailingStop` | true | Enable trailing stop |
| `TrailingStopPips` | 15 | Trailing stop distance in pips |
| `TrailingStepPips` | 5 | Minimum step before trailing stop moves |
| `MaxOpenPositions` | 1 | Maximum concurrent open positions |

## Installation

1. Copy `MovingAverageEA.mq5` to your MT5 `MQL5/Experts/` directory.
2. Open MetaEditor and compile the file (F7).
3. Attach the EA to a **M5 chart** of your preferred symbol (e.g. XAGUSD for silver).
4. Enable **Algo Trading** in MT5.
5. Adjust input parameters as needed and click **OK**.

## Optimisation Tips (M5 Timeframe)

- Start optimisation with `FastMAPeriod` in range 5–13, `MediumMAPeriod` 15–30, `SlowMAPeriod` 40–70.
- Use at least 3 months of M5 tick data for reliable backtesting results.
- Keep `MaxSpreadPoints` tight (10–25) to avoid bad fills during volatile periods.
- A **Risk:Reward** ratio of at least 1:2 (`StopLossPips` : `TakeProfitPips`) is recommended.
