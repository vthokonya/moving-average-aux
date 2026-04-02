//+------------------------------------------------------------------+
//|                                              MovingAverageEA.mq5 |
//|                                                                  |
//| Expert Advisor using 3 Moving Averages to determine trend        |
//| Optimised for M5 timeframe                                       |
//+------------------------------------------------------------------+
#property copyright "moving-average-aux"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input parameters
input group "Moving Average Settings"
input int    FastMAPeriod    = 8;             // Fast MA period
input int    MediumMAPeriod  = 21;            // Medium MA period
input int    SlowMAPeriod    = 50;            // Slow MA period
input ENUM_MA_METHOD MAMethod = MODE_EMA;     // MA method
input ENUM_APPLIED_PRICE AppliedPrice = PRICE_CLOSE; // Applied price

input group "Trade Settings"
input double LotSize         = 0.01;          // Lot size
input int    StopLossPips    = 30;            // Stop loss in pips
input int    TakeProfitPips  = 60;            // Take profit in pips
input int    MagicNumber     = 20240101;      // Magic number
input int    MaxSpreadPoints = 20;            // Maximum allowed spread (points)
input bool   CloseOnOppositeSignal = true;    // Close trade on opposite signal

input group "Risk Management"
input bool   UseTrailingStop   = true;        // Use trailing stop
input int    TrailingStopPips  = 15;          // Trailing stop distance (pips)
input int    TrailingStepPips  = 5;           // Trailing stop step (pips)
input int    MaxOpenPositions  = 1;           // Maximum open positions

//--- Global variables
int    handleFastMA;
int    handleMediumMA;
int    handleSlowMA;

CTrade trade;
CPositionInfo posInfo;

double pipValue;
double pointValue;

//+------------------------------------------------------------------+
//| Expert initialisation function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Validate input parameters
   if (FastMAPeriod >= MediumMAPeriod || MediumMAPeriod >= SlowMAPeriod)
   {
      Print("ERROR: MA periods must be in ascending order: Fast < Medium < Slow");
      return INIT_PARAMETERS_INCORRECT;
   }
   if (LotSize <= 0 || StopLossPips <= 0 || TakeProfitPips <= 0)
   {
      Print("ERROR: LotSize, StopLossPips and TakeProfitPips must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }

   //--- Create MA indicator handles on the M5 timeframe
   handleFastMA = iMA(_Symbol, PERIOD_M5, FastMAPeriod, 0, MAMethod, AppliedPrice);
   if (handleFastMA == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create Fast MA indicator handle");
      return INIT_FAILED;
   }

   handleMediumMA = iMA(_Symbol, PERIOD_M5, MediumMAPeriod, 0, MAMethod, AppliedPrice);
   if (handleMediumMA == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create Medium MA indicator handle");
      return INIT_FAILED;
   }

   handleSlowMA = iMA(_Symbol, PERIOD_M5, SlowMAPeriod, 0, MAMethod, AppliedPrice);
   if (handleSlowMA == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create Slow MA indicator handle");
      return INIT_FAILED;
   }

   //--- Configure trade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_RETURN);

   //--- Calculate pip/point values
   pointValue = _Point;
   pipValue   = (_Digits == 5 || _Digits == 3) ? pointValue * 10 : pointValue;

   Print("MovingAverageEA initialised successfully on ", _Symbol,
         " | Fast MA(", FastMAPeriod, ") Medium MA(", MediumMAPeriod,
         ") Slow MA(", SlowMAPeriod, ")");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handleFastMA);
   IndicatorRelease(handleMediumMA);
   IndicatorRelease(handleSlowMA);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Only process on a new M5 bar to avoid multiple signals per bar
   if (!IsNewBar())
      return;

   //--- Check spread
   if ((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > MaxSpreadPoints)
      return;

   //--- Get MA values for current and previous completed bars
   double fastMA[2], mediumMA[2], slowMA[2];

   if (CopyBuffer(handleFastMA,   0, 1, 2, fastMA)   < 2) return;
   if (CopyBuffer(handleMediumMA, 0, 1, 2, mediumMA) < 2) return;
   if (CopyBuffer(handleSlowMA,   0, 1, 2, slowMA)   < 2) return;

   //--- CopyBuffer with start_pos=1, count=2 fills:
   //      index 0 = bar 1 (most recent completed bar)
   //      index 1 = bar 2 (two bars ago, the older bar)
   double fastPrev    = fastMA[0],   fastPrev2   = fastMA[1];
   double medPrev     = mediumMA[0], medPrev2    = mediumMA[1];
   double slowPrev    = slowMA[0],   slowPrev2   = slowMA[1];

   //--- Determine trend: all 3 MAs must be aligned for a valid trend
   //    Bullish: Fast > Medium > Slow
   //    Bearish: Fast < Medium < Slow
   bool bullishTrend = (fastPrev > medPrev) && (medPrev > slowPrev);
   bool bearishTrend = (fastPrev < medPrev) && (medPrev < slowPrev);

   //--- Detect fast MA crossover of medium MA as entry trigger (confirmed by slow MA alignment)
   bool bullishCross = (fastPrev2 <= medPrev2) && (fastPrev > medPrev) && bullishTrend;
   bool bearishCross = (fastPrev2 >= medPrev2) && (fastPrev < medPrev) && bearishTrend;

   //--- Manage trailing stops for existing positions
   if (UseTrailingStop)
      ManageTrailingStop();

   //--- Close opposite positions if enabled
   if (CloseOnOppositeSignal)
   {
      if (bullishCross && HasOpenPosition(POSITION_TYPE_SELL))
         CloseAllPositions(POSITION_TYPE_SELL);
      if (bearishCross && HasOpenPosition(POSITION_TYPE_BUY))
         CloseAllPositions(POSITION_TYPE_BUY);
   }

   //--- Open new positions only if below maximum
   int openCount = CountOpenPositions();
   if (openCount >= MaxOpenPositions)
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if (bullishCross && !HasOpenPosition(POSITION_TYPE_BUY))
   {
      double sl = NormalizeDouble(ask - StopLossPips  * pipValue, _Digits);
      double tp = NormalizeDouble(ask + TakeProfitPips * pipValue, _Digits);

      if (trade.Buy(LotSize, _Symbol, ask, sl, tp, "MA_BUY"))
         Print("BUY opened @ ", ask, " SL=", sl, " TP=", tp);
      else
         Print("BUY failed: ", trade.ResultRetcodeDescription());
   }
   else if (bearishCross && !HasOpenPosition(POSITION_TYPE_SELL))
   {
      double sl = NormalizeDouble(bid + StopLossPips  * pipValue, _Digits);
      double tp = NormalizeDouble(bid - TakeProfitPips * pipValue, _Digits);

      if (trade.Sell(LotSize, _Symbol, bid, sl, tp, "MA_SELL"))
         Print("SELL opened @ ", bid, " SL=", sl, " TP=", tp);
      else
         Print("SELL failed: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Detect a new M5 bar                                              |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime lastBarTime = 0;
   datetime currentBarTime = (datetime)SeriesInfoInteger(_Symbol, PERIOD_M5, SERIES_LASTBAR_DATE);
   if (currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if an open position of a given type exists for this EA     |
//+------------------------------------------------------------------+
bool HasOpenPosition(ENUM_POSITION_TYPE posType)
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (posInfo.SelectByIndex(i))
      {
         if (posInfo.Symbol()       == _Symbol      &&
             posInfo.Magic()        == MagicNumber   &&
             posInfo.PositionType() == posType)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Count all open positions managed by this EA                      |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (posInfo.SelectByIndex(i))
      {
         if (posInfo.Symbol() == _Symbol && posInfo.Magic() == MagicNumber)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Close all positions of the specified type managed by this EA     |
//+------------------------------------------------------------------+
void CloseAllPositions(ENUM_POSITION_TYPE posType)
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (posInfo.SelectByIndex(i))
      {
         if (posInfo.Symbol()       == _Symbol      &&
             posInfo.Magic()        == MagicNumber   &&
             posInfo.PositionType() == posType)
         {
            if (!trade.PositionClose(posInfo.Ticket()))
               Print("Failed to close position #", posInfo.Ticket(),
                     ": ", trade.ResultRetcodeDescription());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage trailing stop for all open positions of this EA           |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   double trailDist = TrailingStopPips * pipValue;
   double trailStep = TrailingStepPips * pipValue;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (!posInfo.SelectByIndex(i))
         continue;
      if (posInfo.Symbol() != _Symbol || posInfo.Magic() != MagicNumber)
         continue;

      double currentSL = posInfo.StopLoss();

      if (posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double newSL = NormalizeDouble(bid - trailDist, _Digits);

         if (newSL > currentSL + trailStep)
         {
            if (!trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit()))
               Print("TrailingStop modify failed for #", posInfo.Ticket(),
                     ": ", trade.ResultRetcodeDescription());
         }
      }
      else if (posInfo.PositionType() == POSITION_TYPE_SELL)
      {
         double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double newSL = NormalizeDouble(ask + trailDist, _Digits);

         if (newSL < currentSL - trailStep)
         {
            if (!trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit()))
               Print("TrailingStop modify failed for #", posInfo.Ticket(),
                     ": ", trade.ResultRetcodeDescription());
         }
      }
   }
}
//+------------------------------------------------------------------+
