//+------------------------------------------------------------------+
//|                                              BOS+Heiken_Ashi.mq5 |
//|                                     Copyright 2024, Teenodi Ltd. |
//|                                         https://www.jukwaese.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Teenodi Ltd."
#property link      "https://www.jukwaese.com"
#property version   "1.00"
#property strict
#define heikenMagic 102938

// Input parameters
input int         BacklogNumber = 1000;    // Number of historical candles to analyze
input int         SwingPointBars = 20;      // Number of bars for swing confirmation
input bool        DeletePrevStructures = false; // Delete previous structures when new one forms
input double      StopLossPoints = 20;     // Stop loss distance in points from swing low
input bool        NoStopLoss = false;      // Disable stop loss if true
input bool        SwingSLTrailer = true;    // Enable stop loss trailing by swing points
input bool        SwingTPTrailer = true;    // Enable take profit trailing by swing points
input int         MaximumEntriesPerSignal = 2; // Number of additional entries on HA transitions
input double      LotSize = 0.1;

// Swing point structure
struct SwingPoint {
    bool isHigh;         // true for swing high, false for swing low
    double price;        // price level of the swing
    datetime time;       // time of the swing
    bool swingBroken;    // whether a BOS has occurred
};

// Market structure breakpoint
struct BreakPoint {
    double breakpoint_price;
    double takeprofit_price;
    int entries;
    bool active;
};

// Global variables
SwingPoint swings[];         // Array to store swing points
BreakPoint bearishBreaks[]; // Array for bearish breakpoints
BreakPoint bullishBreaks[]; // Array for bullish breakpoints
datetime lastCheckedTime;   // Last analyzed candle time
int haHandle;              // Handle for Heiken Ashi indicator
ENUM_ORDER_TYPE_FILLING orderFill; // Handles market order filling type
datetime end = D'2025.05.04 00:00:00';
datetime begin = D'2025.05.03 00:00:00';
//+------------------------------------------------------------------+
//| Expert initialization function                                      |
//+------------------------------------------------------------------+
int OnInit() {
   if(TimeCurrent() > end || TimeCurrent() < begin){
      Alert("_Demo period exceeded !_");
      ExpertRemove();
   }
   
    // Check that autotrading is enabled
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)){
        Alert("First Enable autotrading on terminal to take trades");
    }
    // Initialize Heiken Ashi handle
    haHandle = iCustom(_Symbol, PERIOD_CURRENT, "Examples\\Heiken_Ashi");
    if(haHandle == INVALID_HANDLE) {
        Print("Error creating Heiken Ashi indicator!");
        return INIT_FAILED;
    }
    
    // get possible filling policy types by symbol
    uint filling=(uint)SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
    // if the required filling policy is supported, add it to the request
    if((filling&SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK){
      orderFill=ORDER_FILLING_FOK;
    }
    if((filling&SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC){
      orderFill=ORDER_FILLING_IOC;
    }
   
    // Initialize arrays
    ArrayResize(swings, 0);
    ArrayResize(bearishBreaks, 0);
    ArrayResize(bullishBreaks, 0);
    
    
    // Process historical Swings and BOS
    const int MAX_ATTEMPTS = 10;        // Maximum number of retry attempts
    const int SLEEP_MS = 1000;          // Sleep duration in milliseconds
    
    int attempts = 0;
    int bars = 0;
    
    while(attempts < MAX_ATTEMPTS){
        MqlRates copy[];
        bars = CopyRates(_Symbol, PERIOD_CURRENT, 0, BacklogNumber+SwingPointBars+10, copy);
        if(bars >= BacklogNumber+SwingPointBars){
            Print("Successfully processed ", bars, " bars after ", attempts + 1, " attempts");
            // Initial swing point analysis
            AnalyzeHistoricalSwings();
            ChartRedraw(0);
            return(INIT_SUCCEEDED);
        }
        Print("Attempt ", attempts + 1, ": Got only ", bars, " bars, needed ", BacklogNumber);
        Sleep(SLEEP_MS);  // Sleep for 1 second before next attempt
        attempts++;
    }
    
    Print("Failed to load required number of bars after ", MAX_ATTEMPTS, " attempts");
    Print("Last attempt got ", bars, " bars, needed ", BacklogNumber);
    return(INIT_FAILED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    ObjectsDeleteAll(0);
    ChartRedraw(0);
    IndicatorRelease(haHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick() {
    // Check for new closed candle
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    
    if(currentBarTime != lastBarTime) {
        UpdateSwingPoints();
        CheckBreakOfStructure();
        ManagePositions();
        if(SwingSLTrailer && !NoStopLoss){
            double high = GetLatestSwingHigh()+(StopLossPoints*_Point), low = GetLatestSwingLow()-(StopLossPoints * _Point);
            //--set stops
            for(int j=PositionsTotal()-1; j>=0; j--){
               ulong ticket = PositionGetTicket(j);
               if(PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==heikenMagic){ //skip magic check to help older session's trades
                  double sli=PositionGetDouble(POSITION_SL), tpi=PositionGetDouble(POSITION_TP);
                  if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY){ //long position found
                     if(low > sli){
                        setSLTP(ticket,low,tpi);
                     }
                  }
                  else{ //short position found
                     if(high < sli || sli==0){
                        setSLTP(ticket,high,tpi);
                     }
                  }
               }
            }
        }
        if(SwingTPTrailer){
            double high = GetLatestSwingHigh()+(StopLossPoints*_Point), low = GetLatestSwingLow()-(StopLossPoints * _Point);
            //--set stops
            for(int j=PositionsTotal()-1; j>=0; j--){
               ulong ticket = PositionGetTicket(j);
               if(PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==heikenMagic){ //skip magic check to help older session's trades
                  double sli=PositionGetDouble(POSITION_SL), tpi=PositionGetDouble(POSITION_TP);
                  if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY){ //long position found
                     if(high < tpi || tpi==0){
                        setSLTP(ticket,sli,high);
                     }
                  }
                  else{ //short position found
                     if(low > tpi){
                        setSLTP(ticket,sli,low);
                     }
                  }
               }
            }
        }
        ChartRedraw(0);
        lastBarTime = currentBarTime;
    }
    
    // Check for trade entries
    CheckTradeEntries();
}

//+------------------------------------------------------------------+
//| Analyze historical swing points                                    |
//+------------------------------------------------------------------+
void AnalyzeHistoricalSwings() {
    int bars = BacklogNumber;
    
    for(int i = bars-1; i > SwingPointBars+1; i--) {
        CheckForSwingPoint(i);
    }
    CheckHistoricalBOS();
}

//+------------------------------------------------------------------+
//| Check for swing point at specified bar                            |
//+------------------------------------------------------------------+
void CheckForSwingPoint(const int shift) {
    bool isHigh = true;
    bool isLow = true;
    
    // Check for swing high
    double currentHigh = iHigh(_Symbol, PERIOD_CURRENT, shift);
    for(int i = 1; i <= SwingPointBars; i++) {
        if(iHigh(_Symbol, PERIOD_CURRENT, shift+i) >= currentHigh || 
           iHigh(_Symbol, PERIOD_CURRENT, shift-i) >= currentHigh) {
            isHigh = false;
            break;
        }
    }
    
    // Check for swing low
    double currentLow = iLow(_Symbol, PERIOD_CURRENT, shift);
    for(int i = 1; i <= SwingPointBars; i++) {
        if(iLow(_Symbol, PERIOD_CURRENT, shift+i) <= currentLow || 
           iLow(_Symbol, PERIOD_CURRENT, shift-i) <= currentLow) {
            isLow = false;
            break;
        }
    }
    
    // Add valid swing points
    if(isHigh || isLow) {
        SwingPoint newSwing;
        newSwing.isHigh = isHigh;
        newSwing.price = isHigh ? currentHigh : currentLow;
        newSwing.time = iTime(_Symbol, PERIOD_CURRENT, shift);
        newSwing.swingBroken = false;
        AddSwingPoint(newSwing);
    }
    lastCheckedTime = iTime(_Symbol, PERIOD_CURRENT, shift);
}

//+------------------------------------------------------------------+
//| Add swing point to array with validation                          |
//+------------------------------------------------------------------+
void AddSwingPoint(SwingPoint &newSwing) {
    int size = ArraySize(swings);
    
    // Compare with previous swing if exists
    if(size > 0) {
        SwingPoint lastSwing = swings[size-1];
        
        // Handle consecutive swing highs/lows
        if(lastSwing.isHigh == newSwing.isHigh) {
            if(newSwing.isHigh) {
                if(newSwing.price > lastSwing.price) {
                    swings[size-1] = newSwing;
                }
            } else {
                if(newSwing.price < lastSwing.price) {
                    swings[size-1] = newSwing;
                }
            }
            return;
        }
    }
    
    // Add new swing point
    ArrayResize(swings, size + 1);
    swings[size] = newSwing;
    
    // Draw swing point
    string objName = "Swing_" + IntegerToString(size);
    DrawSwingPoint(objName, newSwing); // Fails to delete any replaced swing's circle
    
    // Check for market structure
    if(size >= 3) {
        if(newSwing.isHigh)
            CheckBearishStructure();
        else
            CheckBullishStructure();
    }
}

//+------------------------------------------------------------------+
//| Draw swing point on chart                                         |
//+------------------------------------------------------------------+
void DrawSwingPoint(const string name, SwingPoint &swing) {
    ObjectCreate(0, name, OBJ_ARROW_STOP , 0, swing.time, swing.price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, swing.isHigh ? clrGreen : clrRed);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, name, OBJPROP_ANCHOR, swing.isHigh ? ANCHOR_BOTTOM : ANCHOR_TOP);
}
//+------------------------------------------------------------------+
//| CheckHistoricalBOS                                                |
//+------------------------------------------------------------------+
void CheckHistoricalBOS() {
    // Process each swing point
    for(int i = ArraySize(swings)-1; i >= 0; i--) {
        if(swings[i].swingBroken) continue;  // Skip if already marked as broken
        // Get the bar index where this swing occurred
        int swingBarIndex = iBarShift(_Symbol, PERIOD_CURRENT, swings[i].time);
        
        // Look forward from the swing point to find first break
        for(int j = swingBarIndex-1; j >= 0; j--) {  // Start from one bar after swing
            double close = iClose(_Symbol, PERIOD_CURRENT, j);
            datetime breakTime = iTime(_Symbol, PERIOD_CURRENT, j);
            
            if(swings[i].isHigh && close > swings[i].price) {
                DrawBOSLine(swings[i], true, breakTime);
                swings[i].swingBroken = true;
                break;  // Stop after finding first break
            }
            else if(!swings[i].isHigh && close < swings[i].price) {
                DrawBOSLine(swings[i], false, breakTime);
                swings[i].swingBroken = true;
                break;  // Stop after finding first break
            }
        }
    }
}
//+------------------------------------------------------------------+
//| Check for bearish market structure                                |
//+------------------------------------------------------------------+
void CheckBearishStructure() {
     int size = ArraySize(swings);
     if(size < 4) return;
    
     // Point 0 is the latest swing high
     if(!swings[size-1].isHigh) return;
    
     // Look for pattern
     int i = size-2;
     // Point 1: swing low lower than point 0
     if(!swings[i].isHigh && swings[i].price < swings[size-1].price) {
         // Point 2: swing high higher than point 0
         if(swings[i-1].isHigh && swings[i-1].price > swings[size-1].price) {
             // Point 3: swing low higher than point 1
             if(!swings[i-2].isHigh && swings[i-2].price > swings[i].price) {
                 // Valid bearish structure found
                 DrawBearishStructure(size-1, i, i-1, i-2);
                 // Check if not broken and active
                 int swingBarIndex = iBarShift(_Symbol, PERIOD_CURRENT, swings[size-1].time);
                 for(int j = swingBarIndex-1; j >= 0; j--) {  // Start from one bar after swing
                     double close = iClose(_Symbol, PERIOD_CURRENT, j);
                     datetime breakTime = iTime(_Symbol, PERIOD_CURRENT, j);
                     if(close > swings[size-1].price) {
                         DrawBOSLine(swings[size-1], true, breakTime);
                         swings[size-1].swingBroken = true;
                         break;  // Stop after finding first break
                     }
                 }
                 if(!swings[size-1].swingBroken){
                     AddBearishBreakpoint(swings[size-1].price, swings[i-1].price);
                 }
             }
        }
    }
}

//+------------------------------------------------------------------+
//| Check for bullish market structure                                |
//+------------------------------------------------------------------+
void CheckBullishStructure() {
     int size = ArraySize(swings);
     if(size < 4) return;
    
     // Point 0 is the latest swing low
     if(swings[size-1].isHigh) return;
    
     // Look for pattern
     int i = size-2;
     // Point 1: swing high higher than point 0
     if(swings[i].isHigh && swings[i].price > swings[size-1].price) {
         // Point 2: swing low lower than point 0
         if(!swings[i-1].isHigh && swings[i-1].price < swings[size-1].price) {
             // Point 3: swing high lower than point 1
             if(swings[i-2].isHigh && swings[i-2].price < swings[i].price) {
                 // Valid bullish structure found
                 DrawBullishStructure(size-1, i, i-1, i-2);
                 // Check if not broken and active
                 int swingBarIndex = iBarShift(_Symbol, PERIOD_CURRENT, swings[size-1].time);
                 for(int j = swingBarIndex-1; j >= 0; j--) {  // Start from one bar after swing
                     double close = iClose(_Symbol, PERIOD_CURRENT, j);
                     datetime breakTime = iTime(_Symbol, PERIOD_CURRENT, j);
                     if(close < swings[size-1].price) {
                         DrawBOSLine(swings[size-1], false, breakTime);
                         swings[size-1].swingBroken = true;
                         break;  // Stop after finding first break
                     }
                 }
                 if(!swings[size-1].swingBroken){
                     AddBullishBreakpoint(swings[size-1].price, swings[i-1].price);
                 }
             }
         }
    }
}

//+------------------------------------------------------------------+
//| Draw bearish market structure                                     |
//+------------------------------------------------------------------+
void DrawBearishStructure(const int p0, const int p1, const int p2, const int p3) {
    string prefix = "Bearish_" + IntegerToString(p0);
    
    // Draw trendlines
    ObjectCreate(0, prefix + "_line1", OBJ_TREND, 0, 
                swings[p0].time, swings[p0].price,
                swings[p1].time, swings[p1].price);
    ObjectCreate(0, prefix + "_line2", OBJ_TREND, 0,
                swings[p1].time, swings[p1].price,
                swings[p2].time, swings[p2].price);
    ObjectCreate(0, prefix + "_line3", OBJ_TREND, 0,
                swings[p2].time, swings[p2].price,
                swings[p3].time, swings[p3].price);
                
    // Draw horizontal line and label
    datetime swingTime = SwingPointBars*PeriodSeconds(PERIOD_CURRENT);
    ObjectCreate(0, prefix + "_hline", OBJ_TREND, 0,
                swings[p0].time, swings[p0].price,
                swingTime+swings[p0].time, swings[p0].price);
    ObjectCreate(0, prefix + "_label", OBJ_TEXT, 0,
                swings[p0].time, swings[p0].price);
    ObjectSetString(0, prefix + "_label", OBJPROP_TEXT, "$$$");
}

//+------------------------------------------------------------------+
//| Draw bullish market structure                                     |
//+------------------------------------------------------------------+
void DrawBullishStructure(const int p0, const int p1, const int p2, const int p3) {
    string prefix = "Bullish_" + IntegerToString(p0);
    
    // Draw trendlines
    ObjectCreate(0, prefix + "_line1", OBJ_TREND, 0,
                swings[p0].time, swings[p0].price,
                swings[p1].time, swings[p1].price);
    ObjectCreate(0, prefix + "_line2", OBJ_TREND, 0,
                swings[p1].time, swings[p1].price,
                swings[p2].time, swings[p2].price);
    ObjectCreate(0, prefix + "_line3", OBJ_TREND, 0,
                swings[p2].time, swings[p2].price,
                swings[p3].time, swings[p3].price);
                
    // Draw horizontal line and label
    datetime swingTime = SwingPointBars*PeriodSeconds(PERIOD_CURRENT);
    ObjectCreate(0, prefix + "_hline", OBJ_TREND, 0,
                swings[p0].time, swings[p0].price,
                swingTime+swings[p0].time, swings[p0].price);
    ObjectCreate(0, prefix + "_label", OBJ_TEXT, 0,
                swings[p0].time, swings[p0].price);
    ObjectSetString(0, prefix + "_label", OBJPROP_TEXT, "$$$");
}

//+------------------------------------------------------------------+
//| Add bearish breakpoint                                            |
//+------------------------------------------------------------------+
void AddBearishBreakpoint(const double price, const double tp) {
    if(DeletePrevStructures) {
        ArrayResize(bearishBreaks, 0);
        DeleteObjects("Bearish_");
    }
    
    int size = ArraySize(bearishBreaks);
    ArrayResize(bearishBreaks, size + 1);
    bearishBreaks[size].breakpoint_price = price;
    bearishBreaks[size].takeprofit_price = tp;
    bearishBreaks[size].entries = 0;
    bearishBreaks[size].active = SymbolInfoDouble(_Symbol,SYMBOL_BID) > price ? true : false;
}

//+------------------------------------------------------------------+
//| Add bullish breakpoint                                            |
//+------------------------------------------------------------------+
void AddBullishBreakpoint(const double price, const double tp) {
    if(DeletePrevStructures) {
        ArrayResize(bullishBreaks, 0);
        DeleteObjects("Bullish_");
    }
    
    int size = ArraySize(bullishBreaks);
    ArrayResize(bullishBreaks, size + 1);
    bullishBreaks[size].breakpoint_price = price;
    bullishBreaks[size].takeprofit_price = tp;
    bullishBreaks[size].entries = 0;
    bearishBreaks[size].active = SymbolInfoDouble(_Symbol,SYMBOL_ASK) < price ? true : false;
}

//+------------------------------------------------------------------+
//| Check for break of structure and trade entries                    |
//+------------------------------------------------------------------+
void CheckTradeEntries() {
    double haOpen[], haClose[];
    ArraySetAsSeries(haOpen, true);
    ArraySetAsSeries(haClose, true);
    
    // Get Heiken Ashi values
    CopyBuffer(haHandle, 0, 0, 2, haOpen);
    CopyBuffer(haHandle, 3, 0, 2, haClose);
    
    // Check bearish breakpoints
    for(int i = ArraySize(bearishBreaks)-1; i >= 0; i--) {
        if(bearishBreaks[i].active && bearishBreaks[i].entries < MaximumEntriesPerSignal){
           if(haClose[0] > haOpen[0] && // Green HA candle
              haClose[0] > bearishBreaks[i].breakpoint_price) {
               // Entry conditions met
               ExecuteBuyTrade(bearishBreaks[i]);
               bearishBreaks[i].entries += 1;
           }
        }
    }
    
    // Check bullish breakpoints
    for(int i = ArraySize(bullishBreaks)-1; i >= 0; i--) {
        if(bullishBreaks[i].active && bullishBreaks[i].entries < MaximumEntriesPerSignal){
           if(haClose[0] < haOpen[0] && // Red HA candle
               haClose[0] < bullishBreaks[i].breakpoint_price) {
               // Entry conditions met
               ExecuteSellTrade(bullishBreaks[i]);
               bullishBreaks[i].entries += 1;
           }
        }
    }
}

//+------------------------------------------------------------------+
//| Execute buy trade                                                 |
//+------------------------------------------------------------------+
void ExecuteBuyTrade(const BreakPoint &bp) {
    double stopLoss = NoStopLoss ? 0 : GetLatestSwingLow() - StopLossPoints * _Point;
    double takeProfit = bp.takeprofit_price;
    double halfway = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + 
                    (takeProfit - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / 2;
    
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = NormalizeDouble(LotSize, 2);
    request.type = ORDER_TYPE_BUY;
    request.magic = heikenMagic;
    request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    request.type_filling = orderFill;
    if(stopLoss > 0){
        request.sl = NormalizeDouble(stopLoss, _Digits);
    }
    request.tp = NormalizeDouble(takeProfit, _Digits);
    request.deviation = 10;
    request.comment = "BOS Buy Entry";
    
    if(!OrderSend(request, result)) {
        Print("OrderSend error: ", GetLastError());
        return;
    }
    
    // Store the trade ticket for position management
    if(result.retcode == TRADE_RETCODE_DONE) {
        GlobalVariableSet("Trade_" + IntegerToString(result.order), halfway);
    }
}

//+------------------------------------------------------------------+
//| Execute sell trade                                                |
//+------------------------------------------------------------------+
void ExecuteSellTrade(const BreakPoint &bp) {
    double stopLoss = NoStopLoss ? 0 : GetLatestSwingHigh() + StopLossPoints * _Point;
    double takeProfit = bp.takeprofit_price;
    double halfway = SymbolInfoDouble(_Symbol, SYMBOL_BID) - 
                    (SymbolInfoDouble(_Symbol, SYMBOL_BID) - takeProfit) / 2;
    
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = NormalizeDouble(LotSize, 2);
    request.type = ORDER_TYPE_SELL;
    request.magic = heikenMagic;
    request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    request.type_filling = orderFill;
    if(stopLoss > 0){
        request.sl = NormalizeDouble(stopLoss, _Digits);
    }
    request.tp = NormalizeDouble(takeProfit, _Digits);
    request.deviation = 10;
    request.comment = "BOS Sell Entry";
    
    if(!OrderSend(request, result)) {
        Print("OrderSend error: ", GetLastError());
        return;
    }
    
    // Store the trade ticket for position management
    if(result.retcode == TRADE_RETCODE_DONE) {
        GlobalVariableSet("Trade_" + IntegerToString(result.order), halfway);
    }
}

//+------------------------------------------------------------------+
//| Get latest swing low price                                        |
//+------------------------------------------------------------------+
double GetLatestSwingLow() {
    for(int i = ArraySize(swings)-1; i >= 0; i--) {
        if(!swings[i].isHigh) {
            return swings[i].price;
        }
    }
    return 0;
}

//+------------------------------------------------------------------+
//| Get latest swing high price                                       |
//+------------------------------------------------------------------+
double GetLatestSwingHigh() {
    for(int i = ArraySize(swings)-1; i >= 0; i--) {
        if(swings[i].isHigh) {
            return swings[i].price;
        }
    }
    return 0;
}

//+------------------------------------------------------------------+
//| Manage existing positions                                         |
//+------------------------------------------------------------------+
void ManagePositions() {
    for(int i = PositionsTotal()-1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionGetInteger(POSITION_MAGIC) == heikenMagic) {
            double halfway = GlobalVariableGet("Trade_" + IntegerToString(ticket));
            if(halfway == 0) continue;
            
            double positionProfit = PositionGetDouble(POSITION_PROFIT);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            
            bool hitHalfway = (posType == POSITION_TYPE_BUY && currentPrice >= halfway) ||
                             (posType == POSITION_TYPE_SELL && currentPrice <= halfway);
            
            if(hitHalfway) {
                // Close 50% of position and move stop loss to breakeven
                ClosePartialPosition(ticket, openPrice);
                GlobalVariableDel("Trade_" + IntegerToString(ticket));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Close partial position and modify stop loss                       |
//+------------------------------------------------------------------+
void ClosePartialPosition(const ulong ticket, const double openPrice) {
    if(!PositionSelectByTicket(ticket)) return;
    
    double volume = PositionGetDouble(POSITION_VOLUME);
    
    // Close half position
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.position = ticket;
    request.symbol = _Symbol;
    request.volume = NormalizeDouble(volume / 2, 2);
    request.type_filling = orderFill;
    request.type = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                  ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.price = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                   SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    request.deviation = 10;
    
    if(!OrderSend(request, result)) {
        Print("Partial close error: ", GetLastError());
        return;
    }
    
    // Modify stop loss to breakeven
    if(result.retcode == TRADE_RETCODE_DONE) {
        ZeroMemory(request);
        ZeroMemory(result);
        request.action = TRADE_ACTION_SLTP;
        request.position = ticket;
        request.symbol = _Symbol;
        request.sl = NormalizeDouble(openPrice, _Digits);
        request.tp = PositionGetDouble(POSITION_TP);
        
        if(!OrderSend(request, result)) {
            Print("Stop loss modify error: ", GetLastError());
        }
    }
}

//+------------------------------------------------------------------+
//| Set sl                                                            |
//+------------------------------------------------------------------+
void setSLTP(ulong ticket,double tsl,double ttp){
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol = _Symbol;
   request.sl = NormalizeDouble(tsl,_Digits);
   request.tp = NormalizeDouble(ttp,_Digits);
   if(OrderSendAsync(request, result)){}
}

//+------------------------------------------------------------------+
//| Update swing points with new data                                 |
//+------------------------------------------------------------------+
void UpdateSwingPoints() {
    int lastTimeShift = iBarShift(_Symbol, PERIOD_CURRENT, lastCheckedTime);
    
    while(lastTimeShift > SwingPointBars) {
        CheckForSwingPoint(lastTimeShift);
        lastTimeShift--;
    }
    
    // Clean up old broken swings
    //CleanupBrokenSwings();
}

//+------------------------------------------------------------------+
//| Clean up old broken swings                                        |
//+------------------------------------------------------------------+
void CleanupBrokenSwings() {
    int size = ArraySize(swings);
    if(size <= 6) return;
    
    for(int i = size-1; i >= 6; i--) {
        if(swings[i].swingBroken) {
            ArrayRemove(swings, i, 1);
        }
    }
}

//+------------------------------------------------------------------+
//| Delete all chart objects with specified prefix                    |
//+------------------------------------------------------------------+
void DeleteObjects(const string prefix = "") {
    ObjectsDeleteAll(0, prefix);
}

//+------------------------------------------------------------------+
//| Check break of structure                                          |
//+------------------------------------------------------------------+
void CheckBreakOfStructure() {
    double close = iClose(_Symbol, PERIOD_CURRENT, 1);
    datetime breakTime = iTime(_Symbol, PERIOD_CURRENT, 1);
    
    // Check swings for breaks
    for(int i = ArraySize(swings)-1; i >= 0; i--) {
        if(swings[i].swingBroken) continue;
        
        if(swings[i].isHigh && close > swings[i].price) {
            DrawBOSLine(swings[i], true, breakTime);
            swings[i].swingBroken = true;
        }
        else if(!swings[i].isHigh && close < swings[i].price) {
            DrawBOSLine(swings[i], false, breakTime);
            swings[i].swingBroken = true;
        }
    }
}

//+------------------------------------------------------------------+
//| Draw break of structure line                                      |
//+------------------------------------------------------------------+
void DrawBOSLine(const SwingPoint &swing, const bool isBullish, datetime breakTime) {
    string name = "BOS_" + TimeToString(swing.time);
    
    // Draw trend line
    ObjectCreate(0, name + "_line", OBJ_TREND, 0,
                swing.time, swing.price,
                breakTime, swing.price);
    ObjectSetInteger(0, name + "_line", OBJPROP_COLOR, isBullish ? clrGreen : clrRed);
    ObjectSetInteger(0, name + "_line", OBJPROP_STYLE, STYLE_DOT);
    
    // Add label
    ObjectCreate(0, name + "_label", OBJ_TEXT, 0,
                (swing.time+breakTime)/2, swing.price);
    ObjectSetString(0, name + "_label", OBJPROP_TEXT, "BOS");
    ObjectSetInteger(0, name + "_label", OBJPROP_COLOR, clrGray);
    ObjectSetInteger(0, name + "_label", OBJPROP_FONTSIZE, 8);
}
//--------------------------------------------------------------------+